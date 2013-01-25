//
//  NSError+Notation.m
//  Notation
//
//  Created by Zachary Waldowski on 1/25/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import "NSError+Notation.h"

NSString *const NTNErrorDomain = @"NTNErrorDomain";

@implementation NSError (Notation)

+ (NSError *)ntn_errorWithCode:(NSInteger)code carbon:(BOOL)carbonOrNTN {
	static NSDictionary *reasons = nil;
	static dispatch_once_t onceToken;
	dispatch_once(&onceToken, ^{
		NSURL *URL = [[NSBundle mainBundle] URLForResource: @"CarbonErrorStrings" withExtension: @"plist"];
		reasons = [NSDictionary dictionaryWithContentsOfURL: URL];

	});


	NSDictionary *userInfo = nil;
	NSString *reason = reasons[[@(code) stringValue]];
	if (reason) {
		userInfo = @{NSLocalizedFailureReasonErrorKey: reason};
	}

	NSString *domain = carbonOrNTN ? NSOSStatusErrorDomain : NTNErrorDomain;
	return [NSError errorWithDomain: domain code: code userInfo: userInfo];
}

@end
