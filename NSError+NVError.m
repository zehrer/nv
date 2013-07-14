//
//  NSError+NVError.m
//  Notation
//
//  Created by Zach Waldowski on 7/14/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import "NSError+NVError.h"

@implementation NSError (NVError)

NSString *const NVErrorDomain = @"NVErrorDomain";

+ (instancetype)nv_errorWithCode:(NVError)code
{
	static NSDictionary *reasons = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSURL *URL = [[NSBundle mainBundle] URLForResource:@"CarbonErrorStrings" withExtension:@"plist"];
		reasons = [NSDictionary dictionaryWithContentsOfURL:URL];
		
	});
	
	NSDictionary *userInfo = nil;
	NSString *reason = reasons[[@(code) stringValue]];
	if (reason) {
		userInfo = @{NSLocalizedFailureReasonErrorKey: reason};
	}
	
	return [NSError errorWithDomain:NVErrorDomain code:code userInfo:userInfo];
}

@end
