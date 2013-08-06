//
//  JXHTTPFunctions.h
//  JXExample
//
//  Created by Peyton Randolph on 8/6/13.
//  Copyright (c) 2013 JXHTTP. All rights reserved.
//

#ifndef JXExample_JXHTTPFunctions_h
#define JXExample_JXHTTPFunctions_h

static void JXWriteDataToTempFile(NSData *data, void (^completion)(NSString *))
{
    dispatch_queue_t callbackQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSProcessInfo processInfo] globallyUniqueString]];
    [[NSFileManager defaultManager] createFileAtPath:path contents:nil attributes:nil];
    dispatch_io_t fd = dispatch_io_create_with_path(DISPATCH_IO_STREAM, [path UTF8String], O_WRONLY, 0, callbackQueue, ^(int error){});
    
    dispatch_data_t ddata = dispatch_data_create([data bytes], [data length], NULL, DISPATCH_DATA_DESTRUCTOR_DEFAULT);
    dispatch_io_write(fd, 0, ddata, callbackQueue, ^(bool done, dispatch_data_t data, int error) {
        if (done)
        {
            if (completion)
                completion(path);
            dispatch_io_close(fd, 0);
        }
    });
}

#endif
