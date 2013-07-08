//
//  NSOrderedSet+NVFiltering.h
//  Notation
//
//  Created by Zach Waldowski on 7/6/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSOrderedSet (NVFiltering)

- (NSOrderedSet *)nv_filteredOrderedSetUsingBlock:(BOOL (^)(id obj))predicate;
- (NSOrderedSet *)nv_filteredOrderedSetUsingBlock:(BOOL (^)(id obj))predicate whileLocked:(void(^)(id obj, NSUInteger idx))lockedBlock;

@end

@interface NSMutableOrderedSet (NVFiltering)

- (void)nv_filterStableUsingBlock:(BOOL (^)(id obj))predicate;

@end
