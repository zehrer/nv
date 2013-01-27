//
//  NSData+Notation.m
//  Notation
//
//  Created by Zachary Waldowski on 1/27/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import "NSData+Notation.h"

@implementation NSData (Notation)

- (BOOL)ntn_containsHighASCII {
	const void *bytes = self.bytes;
	NSUInteger n = self.length;


	register NSUInteger *intBuffer = (NSUInteger *)bytes;
	register NSUInteger i, integerCount = n / sizeof(NSUInteger);
#if __LP64__ || NS_BUILD_32_LIKE_64
	register NSUInteger pattern = 0x8080808080808080;
#else
	register NSUInteger pattern = 0x80808080;
#endif

	for (i = 0; i < integerCount; i++) {
		if (pattern & intBuffer[i]) {
			return 1;
		}
	}

	unsigned char *charBuffer = (unsigned char *)bytes;
	NSUInteger leftOverCharCount = n % sizeof(NSUInteger);

	for (i = n - leftOverCharCount; i < n; i++) {
		if (charBuffer[i] > 127) {
			return YES;
		}
	}

	return NO;
}

@end
