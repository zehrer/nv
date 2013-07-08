//
//  NSObject+NVPerformBlock.h
//  Notation
//
//  Created by Zach Waldowski on 7/7/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSObject (NVPerformBlock)

+ (void)nv_performBlock:(void(^)(void))block afterDelay:(NSTimeInterval)delay;
+ (void)nv_performBlock:(void(^)(void))block afterDelay:(NSTimeInterval)delay cancelPreviousRequest:(BOOL)cancel;

@end
