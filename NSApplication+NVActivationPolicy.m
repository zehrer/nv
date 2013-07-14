//
//  NSApplication+NVActivationPolicy.m
//  Notation
//
//  Created by Zach Waldowski on 7/14/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import "NSApplication+NVActivationPolicy.h"
#import "NSObject+NVSwizzle.h"

static ProcessApplicationTransformState NVApplicationTransformStateForActivationPolicy(NSApplicationActivationPolicy policy)
{
	switch (policy) {
		case NSApplicationActivationPolicyRegular:		return kProcessTransformToForegroundApplication;
		case NSApplicationActivationPolicyAccessory:	return kProcessTransformToUIElementApplication;
		case NSApplicationActivationPolicyProhibited:	return kProcessTransformToBackgroundApplication;
	}
	return 0;
}

@implementation NSApplication (NVActivationPolicy)

+ (void)load
{
	@autoreleasepool {
		if (floor(NSFoundationVersionNumber) <= NSFoundationVersionNumber10_8) {
			[NSApplication nv_swizzleMethod:@selector(setActivationPolicy:) withMethod:@selector(nv_setActivationPolicy:)];
		}
	}
}

- (BOOL)nv_setActivationPolicy:(NSApplicationActivationPolicy)activationPolicy
{
	ProcessSerialNumber psn = { 0, kCurrentProcess };
	ProcessApplicationTransformState state = NVApplicationTransformStateForActivationPolicy(activationPolicy);
	OSStatus returnCode = TransformProcessType(&psn, state);
	return (returnCode == noErr);
}

@end
