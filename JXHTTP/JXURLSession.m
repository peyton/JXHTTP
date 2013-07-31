//
//  JXURLSession.m
//  JXExample
//
//  Created by Peyton Randolph on 7/31/13.
//  Copyright (c) 2013 JXHTTP. All rights reserved.
//

#import "JXURLSession.h"

#import "JXURLConnectionOperation.h"
#import "JXHTTPOperationQueue.h"

@interface JXURLSession ()

@property (atomic, strong) NSURLSession *backingSession;
@property (atomic, assign) JXURLSessionType type;

@property (atomic, strong) NSMapTable *tasksToOperations;

@property (atomic, strong) void (^backgroundCompletionHandler)();

@end

@implementation JXURLSession

#pragma mark - Lifecycle

- (id)initWithConfiguration:(NSURLSessionConfiguration *)configuration type:(JXURLSessionType)type queue:(NSOperationQueue *)queue;
{
    if (!(self = [self init]))
        return nil;
    
    self.type = type;
    
    // Create backing session
    self.backingSession = [NSURLSession sessionWithConfiguration:configuration delegate:self delegateQueue:queue];
    
    // Create tasks to operations map
    self.tasksToOperations = [NSMapTable weakToWeakObjectsMapTable];
    
    return self;
}

+ (instancetype)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration type:(JXURLSessionType)type queue:(NSOperationQueue *)queue;
{
    return [[self alloc] initWithConfiguration:configuration type:type queue:queue];
}

- (void)dealloc;
{
    [self.backingSession invalidateAndCancel];
}

#pragma mark - Operation tracking

- (void)registerTask:(NSURLSessionTask *)task forDelegate:(id<JXURLCommonConnectionDelegate>)operation;
{
    [self.tasksToOperations setObject:operation forKey:task];
}

+ (instancetype)sessionForBackgroundURLSessionIdentifier:(NSString *)identifier completionHandler:(void (^)(void))completionHandler;
{
    JXURLSession *session = [self sessionWithConfiguration:[NSURLSessionConfiguration backgroundSessionConfiguration:identifier] type:JXURLSessionTypeBackground queue:[JXHTTPOperationQueue sharedQueue]];
    session.backgroundCompletionHandler = completionHandler;
    
    return session;
}

- (void)_callCompletionHandlerIfFinished;
{
    if (self.type != JXURLSessionTypeBackground)
        return;
    
    [self.backingSession getTasksWithCompletionHandler:^(NSArray *dataTasks, NSArray *uploadTasks, NSArray *downloadTasks) {
        if ([dataTasks count] || [uploadTasks count] || [downloadTasks count])
            return;
        
        if (!self.backgroundCompletionHandler)
            return;
        
        self.backgroundCompletionHandler();
        self.backgroundCompletionHandler = nil;
    }];
}

#pragma mark - <NSURLSessionTaskDelegate>

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error;
{
    id<JXURLCommonConnectionDelegate> operation = [self.tasksToOperations objectForKey:task];

    if (error.code == NSURLErrorCancelled)
        goto complete;
    
    if (error)
    {
        if ([operation respondsToSelector:@selector(commonConnectionObject:didFailWithError:)])
            [operation commonConnectionObject:task didFailWithError:error];
    } else {
        if ([operation respondsToSelector:@selector(commonConnectionObjectDidFinishLoading:)])
            [operation commonConnectionObjectDidFinishLoading:task];
    }

complete:
    [self _callCompletionHandlerIfFinished];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didSendBodyData:(int64_t)bytesSent totalBytesSent:(int64_t)totalBytesSent totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend;
{
    id<JXURLCommonConnectionDataDelegate> operation = [self.tasksToOperations objectForKey:task];
    
    if ([operation respondsToSelector:@selector(commonConnectionObject:didSendBodyData:totalBytesSent:totalBytesExpectedToSend:)])
        [operation commonConnectionObject:task didSendBodyData:bytesSent totalBytesSent:totalBytesSent totalBytesExpectedToSend:totalBytesExpectedToSend];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task willPerformHTTPRedirection:(NSHTTPURLResponse *)response newRequest:(NSURLRequest *)request completionHandler:(void (^)(NSURLRequest *))completionHandler;
{
    id<JXURLCommonConnectionDelegate> operation = [self.tasksToOperations objectForKey:task];
    
    NSURLRequest *updatedRequest = nil;
    
    if ([operation respondsToSelector:@selector(commonConnectionObject:willSendRequest:redirectResponse:)])
        updatedRequest = [operation commonConnectionObject:session willSendRequest:request redirectResponse:response];
    
    if (!updatedRequest)
        [task cancel];
    
    completionHandler(updatedRequest);
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didReceiveChallenge:(NSURLAuthenticationChallenge *)challenge completionHandler:(void (^)(NSURLSessionAuthChallengeDisposition, NSURLCredential *))completionHandler;
{
    id<JXURLCommonConnectionDataDelegate> operation = [self.tasksToOperations objectForKey:task];
    
    if ([operation respondsToSelector:@selector(commonConnectionObject:didReceiveAuthenticationChallenge:successHandler:continueHandler:cancellationHandler:)])
    {
        [operation commonConnectionObject:session didReceiveAuthenticationChallenge:challenge successHandler:^(NSURLAuthenticationChallenge *challenge, NSURLCredential *credential) {
            completionHandler(NSURLSessionAuthChallengeUseCredential, credential);
        } continueHandler:^(NSURLAuthenticationChallenge *challenge) {
            completionHandler(NSURLSessionAuthChallengePerformDefaultHandling, nil);
        } cancellationHandler:^(NSURLAuthenticationChallenge *challenge) {
            completionHandler(NSURLSessionAuthChallengeCancelAuthenticationChallenge, nil);
        }];
    }
}

#pragma mark - <NSURLSessionDataDelegate>

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler;
{
    id<JXURLCommonConnectionDelegate> operation = [self.tasksToOperations objectForKey:dataTask];
    
    BOOL shouldReceive = YES;
    if ([operation respondsToSelector:@selector(commonConnectionObject:didReceiveResponse:)])
        shouldReceive &= [operation commonConnectionObject:dataTask didReceiveResponse:response];
    
    completionHandler(shouldReceive ? NSURLSessionResponseAllow : NSURLSessionResponseCancel);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data;
{
    id<JXURLCommonConnectionDelegate> operation = [self.tasksToOperations objectForKey:dataTask];
    
    if ([operation respondsToSelector:@selector(commonConnectionObject:didReceiveData:)])
        [operation commonConnectionObject:dataTask didReceiveData:data];
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task needNewBodyStream:(void (^)(NSInputStream *))completionHandler;
{
    id<JXURLCommonConnectionDelegate> operation = [self.tasksToOperations objectForKey:task];
    
    NSInputStream *newBodyStream = nil;
    
    if ([operation respondsToSelector:@selector(commonConnectionObject:needNewBodyStream:)])
        newBodyStream = [operation commonConnectionObject:task needNewBodyStream:nil];
    
    completionHandler(newBodyStream);
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask willCacheResponse:(NSCachedURLResponse *)proposedResponse completionHandler:(void (^)(NSCachedURLResponse *))completionHandler;
{
    id<JXURLCommonConnectionDataDelegate> operation = [self.tasksToOperations objectForKey:dataTask];
    
    NSCachedURLResponse *cachedResponse = nil;
    if ([operation respondsToSelector:@selector(commonConnectionObject:willCacheResponse:)])
        cachedResponse = [operation commonConnectionObject:dataTask willCacheResponse:proposedResponse];
    
    completionHandler(cachedResponse);
}

@end
