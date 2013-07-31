//
//  JXURLSession.h
//  JXExample
//
//  Created by Peyton Randolph on 7/31/13.
//  Copyright (c) 2013 JXHTTP. All rights reserved.
//

#import "JXURLConnectionOperation.h"

typedef NS_ENUM(NSUInteger, JXURLSessionType)
{
    JXURLSessionTypeForeground,
    JXURLSessionTypeBackground,
};

@interface JXURLSession : NSObject <NSURLSessionDelegate, NSURLSessionDataDelegate, NSURLSessionTaskDelegate>

@property (atomic, strong, readonly) NSURLSession *backingSession;
@property (atomic, assign, readonly) JXURLSessionType type;
@property (atomic, strong) void (^backgroundCompletionHandler)();

- (id)initWithConfiguration:(NSURLSessionConfiguration *)configuration type:(JXURLSessionType)type queue:(NSOperationQueue *)queue;

+ (instancetype)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration type:(JXURLSessionType)type queue:(NSOperationQueue *)queue;

- (void)registerTask:(NSURLSessionTask *)task forDelegate:(id<JXURLCommonConnectionDelegate>)delegate;

@end
