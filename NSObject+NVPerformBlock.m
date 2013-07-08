//
//  NSObject+NVPerformBlock.m
//  Notation
//
//  Created by Zach Waldowski on 7/7/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import "NSObject+NVPerformBlock.h"

@implementation NSObject (NVPerformBlock)

+ (void)nv_delayedEnqueueOperation:(NSOperation *)operation {
	[[NSOperationQueue currentQueue] addOperation:operation];
}

+ (void)nv_performBlock:(void(^)(void))block afterDelay:(NSTimeInterval)delay {
	[self performSelector:@selector(nv_delayedEnqueueOperation:)
			   withObject:[NSBlockOperation blockOperationWithBlock:block]
			   afterDelay:delay];
}

+ (void)nv_performBlock:(void(^)(void))block afterDelay:(NSTimeInterval)delay cancelPreviousRequest:(BOOL)cancel {
    if (cancel) {
        [NSObject cancelPreviousPerformRequestsWithTarget:self];
    }
    [self nv_performBlock:block afterDelay:delay];
}

@end
