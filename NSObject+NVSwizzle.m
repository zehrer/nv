//
//  NSObject+NVSwizzle.m
//  Notation
//
//  Created by Zach Waldowski on 7/14/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import "NSObject+NVSwizzle.h"
#import <objc/runtime.h>

@implementation NSObject (NVSwizzle)

+ (BOOL)nv_swizzleMethod:(SEL)oldSel withMethod:(SEL)newSel
{
	Method origMethod = class_getInstanceMethod(self, oldSel);
	if (!origMethod) {
		return NO;
	}
	
	Method altMethod = class_getInstanceMethod(self, newSel);
	if (!altMethod) {
		return NO;
	}
	
	class_addMethod(self, oldSel,
					class_getMethodImplementation(self, oldSel),
					method_getTypeEncoding(origMethod));
	class_addMethod(self,
					newSel,
					class_getMethodImplementation(self, newSel),
					method_getTypeEncoding(altMethod));
	
	method_exchangeImplementations(class_getInstanceMethod(self, oldSel), class_getInstanceMethod(self, newSel));
	return YES;
}

+ (BOOL)nv_swizzleMethod:(SEL)oldSel withBlock:(id)block
{
	if (!block) return NO;
	
	Method origMethod = class_getInstanceMethod(self, oldSel);
	if (!origMethod) {
		return NO;
	}
	
	NSString *newSelname = [NSString stringWithFormat:@"_%p_%@", block, NSStringFromSelector(oldSel)];
	SEL newSel = sel_registerName(newSelname.UTF8String);
	
	const char *encoding = method_getTypeEncoding(origMethod);
	class_addMethod(self, oldSel,
					class_getMethodImplementation(self, oldSel),
					encoding);
	class_addMethod(self,
					newSel,
					imp_implementationWithBlock(block),
					encoding);
	
	method_exchangeImplementations(class_getInstanceMethod(self, oldSel), class_getInstanceMethod(self, newSel));
	return YES;
}

@end
