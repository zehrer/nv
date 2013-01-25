//
//  NSURL+Notation.m
//  Notation
//
//  Created by Zachary Waldowski on 1/25/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import "NSURL+Notation.h"

@implementation NSURL (Notation)

+ (NSURL *)URLWithFSRef:(const FSRef *)ref {
	return (__bridge_transfer NSURL *)CFURLCreateFromFSRef(NULL, ref);
}

- (BOOL)getFSRef:(out FSRef *)outRef {
	return CFURLGetFSRef((__bridge CFURLRef)self, outRef) != 0;
}

@end
