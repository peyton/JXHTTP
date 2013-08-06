#import "JXURLConnectionOperation.h"
#import "JXHTTPOperationQueue.h"
#import "JXURLSession.h"

@interface JXURLConnectionOperation ()
{
    long long _bytesDownloaded;
    long long _bytesUploaded;
    BOOL _continuesInAppBackground;
    NSURLResponse *_response;
    NSString *_taskDescription;
}

@property (strong) NSURLConnection *connection;
@property (strong) NSURLSessionTask *task;
@property (strong) NSMutableURLRequest *request;
@property (strong) NSURLResponse *response;
@property (strong) NSError *error;
@property (assign) long long bytesDownloaded;
@property (assign) long long bytesUploaded;
@property (assign) BOOL shouldStartTask;

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

#pragma mark - 

- (void)writeBody;
{
    // Write the request body to a file in preparation for uploading.
    dispatch_queue_t callback_queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[NSProcessInfo processInfo].globallyUniqueString];
    [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
    dispatch_io_t fd = dispatch_io_create_with_path(DISPATCH_IO_STREAM, [path UTF8String], O_WRONLY, 0, callback_queue, ^(int error){
        
    });
    
    NSInputStream *bodyStream = self.request.HTTPBodyStream;
    self.request.HTTPBodyStream = nil;
    
    // Size of a page
    const long buffer_size = sysconf(_SC_PAGE_SIZE);
    
    uint8_t *buffer =
    (uint8_t *)malloc(sizeof(uint8_t) * buffer_size);
    __block NSUInteger size;
    [bodyStream open];
    
    __block void (^readStream)(id k);
    
    readStream = ^(id k){
        size = [bodyStream read:buffer maxLength:buffer_size];
        if (size)
        {
            dispatch_data_t data = dispatch_data_create(buffer, size, callback_queue, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
            dispatch_io_write(fd, 0, data, callback_queue, ^(bool done, dispatch_data_t data, int error) {
                if (error)
                {
                    NSLog(@"error %u writing HTTP body", error);
                    return;
                }
                
                if (!done)
                    return;
                
                void (^readStream)(id) = k;
                readStream(k);
            });
        } else {
            dispatch_io_close(fd, 0);
            free(buffer);
            
            self.task = [self.session.backingSession uploadTaskWithRequest:self.request fromFile:[NSURL fileURLWithPath:path isDirectory:NO]];
            self.task.taskDescription = self.taskDescription;
            if (self.shouldStartTask)
                [self _startTask];
        }
    };
    readStream(readStream);
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
            [self writeBody];
        } else {
            self.task = [self.session.backingSession dataTaskWithRequest:self.request];
            self.task.taskDescription = self.taskDescription;
        }
        [self _startTask];
    } else {
        self.connection = [[NSURLConnection alloc] initWithRequest:self.request delegate:self startImmediately:NO];
        [self.connection scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSRunLoopCommonModes];
        [self.connection start];
    }
}

- (void)_startTask;
{
    self.shouldStartTask = YES;
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
    
    return YES;
}

- (void)commonConnectionObject:(id)obj didReceiveData:(NSData *)data;
{
    if ([self isCancelled])
        return;
    
    if (self.outputStream.streamStatus == NSStreamStatusNotOpen)
        [self.outputStream open];
    
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
            return YES;
        
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

- (NSURLResponse *)response;
{
    @synchronized(self)
    {
        if (self.task.response)
            return self.task.response;
        
        return _response;
    }
}

- (void)setResponse:(NSURLResponse *)response;
{
    @synchronized(self)
    {
        _response = response;
    }
}

- (NSString *)taskDescription;
{
    @synchronized(self)
    {
        if (self.task.taskDescription.length)
            return self.task.taskDescription;
        return _taskDescription;
    }
}

- (void)setTaskDescription:(NSString *)taskDescription;
{
    @synchronized(self)
    {
        if (self.task.taskDescription.length)
            self.task.taskDescription = taskDescription;
        _taskDescription = [taskDescription copy];
    }
}

@end
