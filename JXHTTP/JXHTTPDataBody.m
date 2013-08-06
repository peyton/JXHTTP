#import "JXHTTPDataBody.h"

@implementation JXHTTPDataBody

#pragma mark - Initialization

- (instancetype)initWithData:(NSData *)data contentType:(NSString *)contentType
{
    if (self = [super init]) {
        self.data = data;
        self.httpContentType = contentType;
    }
    return self;
}

+ (instancetype)withData:(NSData *)data contentType:(NSString *)contentType
{
    return [[self alloc] initWithData:data contentType:contentType];
}

+ (instancetype)withData:(NSData *)data
{
    return [self withData:data contentType:nil];
}

#pragma mark - <JXHTTPRequestBody>

- (NSInputStream *)httpInputStream
{
    return [[NSInputStream alloc] initWithData:self.data];
}

- (long long)httpContentLength
{
    return [self.data length];
}

- (void)writeToFile:(void (^)(NSString *))completion;
{
    dispatch_queue_t callbackQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
    [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
    dispatch_io_t fd = dispatch_io_create_with_path(DISPATCH_IO_STREAM, [path UTF8String], O_WRONLY, 0, callbackQueue, ^(int error){});
    
    dispatch_data_t data = dispatch_data_create([self.data bytes], [self.data length], NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    dispatch_io_write(fd, 0, data, callbackQueue, ^(bool done, dispatch_data_t data, int error) {
        if (done)
        {
            if (completion)
                completion(path);
            dispatch_io_close(fd, 0);
        }
    });
}

@end
