//
//  NSMutableOrderedSet+NVFiltering.m
//  Notation
//
//  Created by Zach Waldowski on 7/6/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import "NSMutableOrderedSet+NVFiltering.h"
#include <libkern/OSAtomic.h>

@implementation NSMutableOrderedSet (NVFiltering)

- (void)nv_filterStableUsingBlock:(BOOL (^)(id obj))predicate
{
	__block volatile OSSpinLock spinLock = OS_SPINLOCK_INIT;
	NSMutableIndexSet *notMatchesIndexes = [NSMutableIndexSet indexSet];
	
	[self enumerateObjectsWithOptions:NSEnumerationConcurrent usingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
		if (!predicate(obj)) {
			OSSpinLockLock(&spinLock);
			[notMatchesIndexes addIndex:idx];
			OSSpinLockUnlock(&spinLock);
		}
	}];
	
	[self removeObjectsAtIndexes:notMatchesIndexes];
}

@end
