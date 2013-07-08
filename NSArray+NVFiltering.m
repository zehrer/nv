//
//  NSArray+NVFiltering.m
//  Notation
//
//  Created by Zach Waldowski on 7/8/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import "NSArray+NVFiltering.h"

@implementation NSArray (NVFiltering)

- (instancetype)nv_stableFilteredArrayUsingBlock:(BOOL (^)(id))predicate whileLocked:(void (^)(id, NSUInteger))lockedBlock
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
	
	return [self objectsAtIndexes:matchesIndexes];
}

- (instancetype)nv_stableFilteredArrayUsingBlock:(BOOL (^)(id obj))predicate
{
	return [self nv_stableFilteredArrayUsingBlock:predicate whileLocked:NULL];
}

@end
