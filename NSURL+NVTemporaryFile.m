//
//  NSURL+NVTemporaryFile.m
//  Notation
//
//  Created by Zach Waldowski on 7/14/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import "NSURL+NVTemporaryFile.h"
#import "NSString_NV.h"

@implementation NSURL (NVTemporaryFile)

+ (instancetype)nv_temporaryURL
{
	static volatile int32_t seq = 0;
	
	OSAtomicIncrement32(&seq);
	
	int pid = [[NSProcessInfo processInfo] processIdentifier];
	int date = [NSDate timeIntervalSinceReferenceDate];
	
	NSString *fileName = [NSString stringWithFormat:@".%d-%d-%d", pid, date, seq];
	NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:fileName];
	return [NSURL fileURLWithPath:path];
}

@end
