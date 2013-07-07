//
//  PTHotKey.m
//  Protein
//
//  Created by Quentin Carnicelli on Sat Aug 02 2003.
//  Copyright (c) 2003 Quentin D. Carnicelli. All rights reserved.
//

#import "PTHotKey.h"
#import "PTHotKeyCenter.h"
#import "PTKeyCombo.h"
#import <objc/message.h>

@implementation PTHotKey

- (id)init
{
	self = [super init];
	
	if( self )
	{
		self.keyCombo = [PTKeyCombo clearKeyCombo];
	}
	
	return self;
}


- (NSString*)description
{
	return [NSString stringWithFormat: @"<%@: %@>", NSStringFromClass( [self class] ), [self keyCombo]];
}

#pragma mark -

- (void)invoke
{
	if (self.target && self.action) {
		objc_msgSend(self.target, self.action, self);
	}
}

@end
