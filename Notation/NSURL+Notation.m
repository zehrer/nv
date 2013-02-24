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

- (BOOL)isEqualToFileURL:(NSURL *)otherURL {
	if (!self.isFileURL || !otherURL.isFileURL) return NO;

	if ([self isEqual: otherURL]) {
		return YES;
	} else {
		NSError *error = nil;
		id resourceIdentifier1 = nil;
		id resourceIdentifier2 = nil;

		if (![self getResourceValue:&resourceIdentifier1 forKey:NSURLFileResourceIdentifierKey error:&error]) {
			@throw [NSException exceptionWithName: NSInternalInconsistencyException reason:error.localizedDescription userInfo:nil];
		}

		if (![otherURL getResourceValue:&resourceIdentifier2 forKey:NSURLFileResourceIdentifierKey error:&error]) {
			@throw [NSException exceptionWithName:NSInternalInconsistencyException reason:error.localizedDescription userInfo:nil];
		}

		return [resourceIdentifier1 isEqual:resourceIdentifier2];
	}
}

@end
