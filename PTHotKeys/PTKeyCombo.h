//
//  PTKeyCombo.h
//  Protein
//
//  Created by Quentin Carnicelli on Sat Aug 02 2003.
//  Copyright (c) 2003 Quentin D. Carnicelli. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface PTKeyCombo : NSObject <NSCopying>
{
	NSInteger	mKeyCode;
	NSInteger	mModifiers;
}

+ (id)clearKeyCombo;
+ (id)keyComboWithKeyCode:(NSInteger)keyCode modifiers: (NSInteger)modifiers;
- (id)initWithKeyCode:(NSInteger)keyCode modifiers: (NSInteger)modifiers;

- (id)initWithPlistRepresentation: (id)plist;
- (id)plistRepresentation;

- (BOOL)isEqual: (PTKeyCombo*)combo;

- (NSInteger)keyCode;
- (NSInteger)modifiers;

- (BOOL)isClearCombo;
- (BOOL)isValidHotKeyCombo;

@end

@interface PTKeyCombo (UserDisplayAdditions)

- (NSString*)description;

@end
