//
//  NSURL+NVFSRefCompat.m
//  Notation
//
//  Created by Zach Waldowski on 7/14/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import "NSURL+NVFSRefCompat.h"

@implementation NSURL (NVFSRefCompat)

- (BOOL)nv_getFSRef:(FSRef *)ref
{
	return (BOOL)CFURLGetFSRef((__bridge CFURLRef)self, ref);
}

+ (instancetype)nv_URLFromFSRef:(FSRef *)ref
{
	return (__bridge_transfer NSURL *)CFURLCreateFromFSRef(NULL, ref);
}

@end
