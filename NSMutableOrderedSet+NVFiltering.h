//
//  NSMutableOrderedSet+NVFiltering.h
//  Notation
//
//  Created by Zach Waldowski on 7/6/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSMutableOrderedSet (NVFiltering)

- (void)nv_filterStableUsingBlock:(BOOL (^)(id obj))predicate;

@end
