//
//  NSOrderedSet+NVFiltering.m
//  Notation
//
//  Created by Zach Waldowski on 7/6/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import "NSOrderedSet+NVFiltering.h"
#include <libkern/OSAtomic.h>

@implementation NSOrderedSet (NVFiltering)

- (NSOrderedSet *)nv_filteredOrderedSetUsingBlock:(BOOL (^)(id obj))predicate whileLocked:(void(^)(id obj, NSUInteger idx))lockedBlock
{
	__block volatile OSSpinLock spinLock = OS_SPINLOCK_INIT;
	NSMutableIndexSet *matchesIndexes = [NSMutableIndexSet indexSet];
	
	[self enumerateObjectsWithOptions:NSEnumerationConcurrent usingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
		if (!predicate(obj)) {
			OSSpinLockLock(&spinLock);
			[matchesIndexes addIndex:idx];
			if (lockedBlock) lockedBlock(obj, idx);
			OSSpinLockUnlock(&spinLock);
		}
	}];
	
	return [NSOrderedSet orderedSetWithArray:[self objectsAtIndexes:matchesIndexes]];
}

- (NSOrderedSet *)nv_filteredOrderedSetUsingBlock:(BOOL (^)(id obj))predicate
{
	return [self nv_filteredOrderedSetUsingBlock:predicate whileLocked:NULL];
}

@end


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
