#import "JXURLConnectionOperation.h"
#import "JXHTTPOperationQueue.h"

@interface JXURLConnectionOperation ()
{
    NSURLSession *_session;
}
@property (strong) NSURLConnection *connection;
@property (strong, readonly) NSURLSession *session;
@property (strong) NSURLSessionTask *task;
@property (strong) NSMutableURLRequest *request;
@property (strong) NSURLResponse *response;
@property (strong) NSError *error;
@property (assign) long long bytesDownloaded;
@property (assign) long long bytesUploaded;
@end

@implementation JXURLConnectionOperation
@dynamic session;

#pragma mark - Initialization

- (void)dealloc
{
    [self stopConnection];
}

- (instancetype)init
{
    if (self = [super init]) {
        self.connection = nil;
        self.request = nil;
        self.response = nil;
        self.error = nil;

        self.bytesDownloaded = 0LL;
        self.bytesUploaded = 0LL;
        
        self.outputStream = [[NSOutputStream alloc] initToMemory];
    }
    return self;
}

- (instancetype)initWithURL:(NSURL *)url
{
    if (self = [self init]) {
        self.request = [[NSMutableURLRequest alloc] initWithURL:url];
    }
    return self;
}

#pragma mark - NSOperation

- (void)main
{
    if ([self isCancelled])
        return;
    
    [self startConnection];
}

- (void)willFinish
{
    [super willFinish];

    [self stopConnection];
}

#pragma mark - Scheduling

- (void)startConnection
{
    if ([NSThread currentThread] != [[self class] networkThread]) {
        [self performSelector:@selector(startConnection) onThread:[[self class] networkThread] withObject:nil waitUntilDone:YES];
        return;
    }
    
    if ([self isCancelled])
        return;

    [self.outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];

    if (NSClassFromString(@"NSURLSession"))
    {
        NSURLSessionTask *task = [[self session] dataTaskWithRequest:self.request];
        self.task = task;
        [task resume];
    } else {
        self.connection = [[NSURLConnection alloc] initWithRequest:self.request delegate:self startImmediately:NO];
        [self.connection scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
        [self.connection start];
    }
}

- (void)stopConnection
{
    if ([NSThread currentThread] != [[self class] networkThread]) {
        [self performSelector:@selector(stopConnection) onThread:[[self class] networkThread] withObject:nil waitUntilDone:YES];
        return;
    }

    if (NSClassFromString(@"NSURLSession"))
    {
        [self.task cancel];
    } else {
        [self.connection unscheduleFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
        [self.connection cancel];
    }

    [self.outputStream removeFromRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
    [self.outputStream close];
}

+ (NSThread *)networkThread
{
    static NSThread *thread = nil;
    static dispatch_once_t predicate;
    
    dispatch_once(&predicate, ^{
        thread = [[NSThread alloc] initWithTarget:self selector:@selector(runLoopForever) object:nil];
        [thread start];
    });
    
    return thread;
}

+ (void)runLoopForever
{
    [[NSThread currentThread] setName:@"JXHTTP"];

    while (YES) {
        @autoreleasepool {
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate distantFuture]];
        }
    }
}

#pragma mark - NSURLSession

- (NSURLSession *)session;
{
    @synchronized(self)
    {
        if (!_session)
            _session = [NSURLSession sessionWithConfiguration:[NSURLSessionConfiguration defaultSessionConfiguration] delegate:self delegateQueue:[JXHTTPOperationQueue sharedQueue]];
        
        return _session;
    }
}

#pragma mark - <NSURLConnectionDelegate>

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    [self _commonConnectionObject:connection didFailWithError:error];
}

#pragma mark - <NSURLSessionDelegate>

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error;
{
    if (error.code == NSURLErrorCancelled)
        return;
    
    if (error)
        [self _commonConnectionObject:session didFailWithError:error];
    else
        [self _commonConnectionObjectDidFinishLoading:session];
}

#pragma mark - <NSURLConnectionDelegate, NSURLSessionDelegate> common

- (void)_commonConnectionObject:(id)obj didFailWithError:(NSError *)error;
{
    if ([self isCancelled])
        return;
    
    self.error = error;
    
    [self finish];
}

#pragma mark - <NSURLConnectionDataDelegate>

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)urlResponse
{
    [self _commonConnectionObject:connection didReceiveResponse:urlResponse];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    [self _commonConnectionObject:connection didReceiveData:data];
}

- (void)connection:(NSURLConnection *)connection didSendBodyData:(NSInteger)bytes totalBytesWritten:(NSInteger)total totalBytesExpectedToWrite:(NSInteger)expected
{
    [self _commonConnectionObject:connection didSendBodyData:bytes totalBytesSent:total totalBytesExpectedToSend:expected];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    [self _commonConnectionObjectDidFinishLoading:connection];
}

#pragma mark - <NSURLSessionDataDelegate>

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveResponse:(NSURLResponse *)response completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler;
{
    BOOL shouldReceive = [self _commonConnectionObject:session didReceiveResponse:response];
    completionHandler(shouldReceive ? NSURLSessionResponseAllow : NSURLSessionResponseCancel);
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didSendBodyData:(int64_t)bytesSent totalBytesSent:(int64_t)totalBytesSent totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend;
{
    [self _commonConnectionObject:session didSendBodyData:bytesSent totalBytesSent:totalBytesSent totalBytesExpectedToSend:totalBytesExpectedToSend];
}

- (void)URLSession:(NSURLSession *)session dataTask:(NSURLSessionDataTask *)dataTask didReceiveData:(NSData *)data;
{
    [self _commonConnectionObject:session didReceiveData:data];
}

#pragma mark - <NSURLConnectionDataDelegate, NSURLSessionDataDelegate> common

- (BOOL)_commonConnectionObject:(id)obj didReceiveResponse:(NSURLResponse *)urlResponse;
{
    if ([self isCancelled])
        return NO;
    
    self.response = urlResponse;
    
    [self.outputStream open];
    
    return YES;
}

- (void)_commonConnectionObject:(id)obj didReceiveData:(NSData *)data;
{
    if ([self isCancelled])
        return;
    
    if ([self.outputStream hasSpaceAvailable]) {
        NSInteger bytesWritten = [self.outputStream write:[data bytes] maxLength:[data length]];
        
        if (bytesWritten != -1)
            self.bytesDownloaded += bytesWritten;
    }
}

- (void)_commonConnectionObject:(id)obj didSendBodyData:(NSInteger)bytes totalBytesSent:(int64_t)totalBytesSent totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend;
{
    if ([self isCancelled])
        return;
    
    self.bytesUploaded += bytes;
}

- (void)_commonConnectionObjectDidFinishLoading:(id)obj;
{
    if ([self isCancelled])
        return;
    
    [self finish];
}

@end
