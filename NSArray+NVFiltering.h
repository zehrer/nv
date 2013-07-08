//
//  NSArray+NVFiltering.h
//  Notation
//
//  Created by Zach Waldowski on 7/8/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSArray (NVFiltering)

- (instancetype)nv_stableFilteredArrayUsingBlock:(BOOL (^)(id obj))predicate;
- (instancetype)nv_stableFilteredArrayUsingBlock:(BOOL (^)(id obj))predicate whileLocked:(void(^)(id obj, NSUInteger idx))lockedBlock;

@end
