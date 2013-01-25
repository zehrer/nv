//
//  NSString+UTType.m
//  Notation
//
//  Created by Zachary Waldowski on 1/25/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import "NSString+UTType.h"
#import <CoreServices/CoreServices.h>

@implementation NSString (UTType)

- (BOOL)ut_conformsToType:(NSString *)typeString {
	return UTTypeConformsTo((__bridge CFStringRef)self, (__bridge CFStringRef)typeString);
}

/*
 UTTypeCreatePreferredIdentifierForTag
 UTTypeCreateAllIdentifiersForTag
 UTTypeCopyPreferredTagWithClass
 UTTypeCopyDescription
 UTTypeCopyDeclaration
 UTTypeCopyDeclaringBundleURL
 UTCreateStringForOSType
 UTGetOSTypeFromString
 */

@end
