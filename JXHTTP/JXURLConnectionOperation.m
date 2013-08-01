#import "JXURLConnectionOperation.h"
#import "JXHTTPOperationQueue.h"
#import "JXURLSession.h"

@interface JXURLConnectionOperation ()
{
    long long _bytesDownloaded;
    long long _bytesUploaded;
    BOOL _continuesInAppBackground;
}

@property (strong) NSURLConnection *connection;
@property (strong) NSURLSessionTask *task;
@property (strong) NSMutableURLRequest *request;
@property (strong) NSURLResponse *response;
@property (strong) NSError *error;
@property (assign) long long bytesDownloaded;
@property (assign) long long bytesUploaded;
@end

@implementation JXURLConnectionOperation
@dynamic bytesDownloaded, bytesUploaded;

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

    if (self.session)
    {
        
        if (self.session.isBackgroundSession)
        {
            NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSProcessInfo processInfo].globallyUniqueString];
            dispatch_io_t fd = dispatch_io_create_with_path(DISPATCH_IO_STREAM, [path fileSystemRepresentation], O_WRONLY, 0, NULL, NULL);
            
            NSInputStream *bodyStream = self.request.HTTPBodyStream;
            dispatch_data_t data = NULL;
            while ([bodyStream hasBytesAvailable])
            {
                uint8_t *buffer;
                NSUInteger size;
                if ([bodyStream getBuffer:&buffer length:&size])
                {
                    dispatch_data_t newData = dispatch_data_create(buffer, size, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), DISPATCH_DATA_DESTRUCTOR_DEFAULT);
                    if (data)
                        data = dispatch_data_create_concat(data, newData);
                    else
                        data = newData;
                }
            }
            
            if (data)
            {
                dispatch_write(fd, data, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^(dispatch_data_t data, int error) {
                    if (data != NULL)
                    {
                        NSLog(@"error %u writing HTTP body", error);
                        return;
                    }
                    
                    self.task = [self.session.backingSession uploadTaskWithRequest:self.request fromFile:[NSURL fileURLWithPath:path isDirectory:NO]];
                    [self _startTask];
                    
                });
            }
        }
        else {
            self.task = [self.session.backingSession dataTaskWithRequest:self.request];
            [self _startTask];
        }
    } else {
        self.connection = [[NSURLConnection alloc] initWithRequest:self.request delegate:self startImmediately:NO];
        [self.connection scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
        [self.connection start];
    }
}

- (void)_startTask;
{
    [self.session registerTask:self.task forDelegate:self];
    [self.task resume];
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
        self.task = nil;
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

#pragma mark - <NSURLConnectionDelegate>

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error
{
    [self commonConnectionObject:connection didFailWithError:error];
}

#pragma mark - <NSURLConnectionDelegate, NSURLSessionDelegate> common

- (void)commonConnectionObject:(id)obj didFailWithError:(NSError *)error;
{
    if ([self isCancelled])
        return;
    
    self.error = error;
    
    [self finish];
}

#pragma mark - <NSURLConnectionDataDelegate>

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)urlResponse
{
    [self commonConnectionObject:connection didReceiveResponse:urlResponse];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data
{
    [self commonConnectionObject:connection didReceiveData:data];
}

- (void)connection:(NSURLConnection *)connection didSendBodyData:(NSInteger)bytes totalBytesWritten:(NSInteger)total totalBytesExpectedToWrite:(NSInteger)expected
{
    [self commonConnectionObject:connection didSendBodyData:bytes totalBytesSent:total totalBytesExpectedToSend:expected];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)connection
{
    [self commonConnectionObjectDidFinishLoading:connection];
}

#pragma mark - <NSURLConnectionDataDelegate, NSURLSessionDataDelegate> common

- (BOOL)commonConnectionObject:(id)obj didReceiveResponse:(NSURLResponse *)urlResponse;
{
    if ([self isCancelled])
        return NO;
    
    self.response = urlResponse;
    
    [self.outputStream open];
    
    return YES;
}

- (void)commonConnectionObject:(id)obj didReceiveData:(NSData *)data;
{
    if ([self isCancelled])
        return;
    
    if ([self.outputStream hasSpaceAvailable]) {
        NSInteger bytesWritten = [self.outputStream write:[data bytes] maxLength:[data length]];
        
        if (bytesWritten != -1)
            self.bytesDownloaded += bytesWritten;
    }
}

- (void)commonConnectionObject:(id)obj didSendBodyData:(NSInteger)bytes totalBytesSent:(int64_t)totalBytesSent totalBytesExpectedToSend:(int64_t)totalBytesExpectedToSend;
{
    if ([self isCancelled])
        return;
    
    self.bytesUploaded += bytes;
}

- (void)commonConnectionObjectDidFinishLoading:(id)obj;
{
    if ([self isCancelled])
        return;
    
    [self finish];
}

#pragma mark - Getters and setters

- (long long)bytesDownloaded;
{
    @synchronized(self)
    {
        if (self.task)
            return self.task.countOfBytesReceived;
        else
            return _bytesDownloaded;
    }
}

- (void)setBytesDownloaded:(long long)bytesDownloaded;
{
    @synchronized(self)
    {
        _bytesDownloaded = bytesDownloaded;
    }
}

- (long long)bytesUploaded;
{
    @synchronized(self)
    {
        if (self.task)
            return self.task.countOfBytesSent;
        else
            return _bytesUploaded;
    }
}

- (void)setBytesUploaded:(long long)bytesUploaded;
{
    @synchronized(self)
    {
        _bytesUploaded = bytesUploaded;
    }
}

- (BOOL)continuesInAppBackground;
{
    @synchronized(self)
    {
        if (self.session.isBackgroundSession)
            return NO;
        
        return _continuesInAppBackground;
    }
}

- (void)setContinuesInAppBackground:(BOOL)continuesInAppBackground;
{
    @synchronized(self)
    {
        _continuesInAppBackground = continuesInAppBackground;
    }
}

@end
