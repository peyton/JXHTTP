//
//  JXURLSession.h
//  JXExample
//
//  Created by Peyton Randolph on 7/31/13.
//  Copyright (c) 2013 JXHTTP. All rights reserved.
//

#import "JXURLConnectionOperation.h"

@interface JXURLSession : NSObject <NSURLSessionDelegate, NSURLSessionDataDelegate, NSURLSessionTaskDelegate>

@property (atomic, strong, readonly) NSURLSession *backingSession;
@property (atomic, strong) void (^backgroundCompletionHandler)();

- (id)initWithConfiguration:(NSURLSessionConfiguration *)configuration queue:(NSOperationQueue *)queue;

+ (instancetype)sessionWithConfiguration:(NSURLSessionConfiguration *)configuration queue:(NSOperationQueue *)queue;

- (void)registerTask:(NSURLSessionTask *)task forDelegate:(id<JXURLCommonConnectionDelegate>)delegate;

@end
