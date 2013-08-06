#import "JXHTTPJSONBody.h"
#import "JXHTTP.h"
#import "JXHTTPFunctions.h"

@interface JXHTTPJSONBody ()
@property (strong, nonatomic) NSData *requestData;
@end

@implementation JXHTTPJSONBody

#pragma mark - Initialization

- (instancetype)initWithData:(NSData *)data
{
    if (self = [super init]) {
        self.requestData = data;
    }
    return self;
}

+ (instancetype)withData:(NSData *)data
{
    return [[self alloc] initWithData:data];
}

+ (instancetype)withString:(NSString *)string
{
    return [self withData:[string dataUsingEncoding:NSUTF8StringEncoding]];
}

+ (instancetype)withJSONObject:(id)dictionaryOrArray
{
    NSError *error = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:dictionaryOrArray options:0 error:&error];
    JXError(error);
        
    return [self withData:data];
}

#pragma mark - <JXHTTPRequestBody>

- (NSInputStream *)httpInputStream
{
    return [[NSInputStream alloc] initWithData:self.requestData];
}

- (NSString *)httpContentType
{
    return @"application/json; charset=utf-8";
}

- (long long)httpContentLength
{
    return [self.requestData length];
}

- (void)writeToFile:(void (^)(NSString *))completion;
{
    JXWriteDataToTempFile(self.requestData, completion);
}

#pragma mark - <JXHTTPOperationDelegate>

- (void)httpOperationDidFinishLoading:(JXHTTPOperation *)operation
{
    self.requestData = nil;
}

@end
