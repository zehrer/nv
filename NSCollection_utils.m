//
//  NSCollection_utils.m
//  Notation
//
//  Created by Zachary Schneirov on 1/13/06.

/*Copyright (c) 2010, Zachary Schneirov. All rights reserved.
  Redistribution and use in source and binary forms, with or without modification, are permitted 
  provided that the following conditions are met:
   - Redistributions of source code must retain the above copyright notice, this list of conditions 
     and the following disclaimer.
   - Redistributions in binary form must reproduce the above copyright notice, this list of 
	 conditions and the following disclaimer in the documentation and/or other materials provided with
     the distribution.
   - Neither the name of Notational Velocity nor the names of its contributors may be used to endorse 
     or promote products derived from this software without specific prior written permission. */


#import "NSCollection_utils.h"
#import "AttributedPlainText.h"
#import "NSString_NV.h"
#import "NSFileManager_NV.h"
#import "NoteObject.h"
#import "BufferUtils.h"

@implementation NSDictionary (FontTraits)

- (BOOL)attributesHaveFontTrait:(NSFontTraitMask)desiredTrait orAttribute:(NSString*)attrName {
	if (self[attrName])
		return YES;
	NSFont *font = self[NSFontAttributeName];
	if (font) {
		NSFontTraitMask traits = [[NSFontManager sharedFontManager] traitsOfFont:font];
		return traits & desiredTrait;
	}
	
	return NO;
	
}

@end

@implementation NSMutableDictionary (FontTraits)

- (void)addDesiredAttributesFromDictionary:(NSDictionary*)dict {
	id strikethroughStyle = dict[NSStrikethroughStyleAttributeName];
	id hiddenDoneTagStyle = dict[NVHiddenDoneTagAttributeName];
	id strokeWidthStyle = dict[NSStrokeWidthAttributeName];
	id obliquenessStyle = dict[NSObliquenessAttributeName];
	id linkStyle = dict[NSLinkAttributeName];
	
	if (linkStyle)
		self[NSLinkAttributeName] = linkStyle;
	if (strikethroughStyle)
		self[NSStrikethroughStyleAttributeName] = @(NSUnderlineStyleSingle);
	if (strokeWidthStyle)
		self[NSStrokeWidthAttributeName] = strokeWidthStyle;
	if (obliquenessStyle)
		self[NSObliquenessAttributeName] = obliquenessStyle;
	if (hiddenDoneTagStyle)
		self[NVHiddenDoneTagAttributeName] = hiddenDoneTagStyle;
}

- (void)applyStyleInverted:(BOOL)opposite trait:(NSFontTraitMask)trait forFont:(NSFont*)font 
	alternateAttributeName:(NSString*)attrName alternateAttributeValue:(id)value {
	
	NSFontManager *fontMan = [NSFontManager sharedFontManager];
	
	if (opposite) {
		font = [fontMan convertFont:font toNotHaveTrait:trait];	
		[self removeObjectForKey:attrName];
	} else {
		font = [fontMan convertFont:font toHaveTrait:trait];
		NSFontTraitMask newTraits = [fontMan traitsOfFont:font];
		
		if (!(newTraits & trait)) {
			self[attrName] = value;
		} else {
			[self removeObjectForKey:attrName];
		}
	}
	self[NSFontAttributeName] = font;
}

@end

@implementation NSDictionary (HTTP)

+ (NSDictionary*)optionsDictionaryWithTimeout:(float)timeout {
	return @{NSTimeoutDocumentOption: @(timeout)};
}

- (NSString*)URLEncodedString {
	
	NSMutableArray *pairs = [NSMutableArray arrayWithCapacity:[self count]];
	
	NSEnumerator *enumerator = [self keyEnumerator];
	NSString *aKey = nil;
	while ((aKey = [enumerator nextObject])) {
		[pairs addObject:[NSString stringWithFormat: @"%@=%@", 
						  [aKey stringWithPercentEscapes], [self[aKey] stringWithPercentEscapes]]];
		
	}
	return [pairs componentsJoinedByString:@"&"];
}


@end



@implementation NSSet (Utilities)

- (NSMutableSet*)setIntersectedWithSet:(NSSet*)set {
    NSMutableSet *existingItems = [NSMutableSet setWithSet:self];
    [existingItems intersectSet:set];
   
    return existingItems;
}

@end

@implementation NSArray (NoteUtilities)

- (NSArray*)objectsFromDictionariesForKey:(id)aKey {
	NSUInteger i = 0;
	NSMutableArray *objects = [NSMutableArray arrayWithCapacity:[self count]];
	for (i=0; i<[self count]; i++) {
		id obj = self[i][aKey];
		if (obj) [objects addObject:obj];
	}
	return objects;
}


- (void)addMenuItemsForURLsInNotes:(NSMenu*)urlsMenu {
	//iterate over notes in array
	//accumulate links as NSMenuItems, with separators between them and disabled items being names of notes
	unsigned int i;
	
	//while ([urlsMenu numberOfItems]) {
	//	[urlsMenu removeItemAtIndex:0];
	//}
	
//	NSMenu *urlsMenu = [[NSMenu alloc] initWithTitle:@"URLs Menu"];
	NSDictionary *blackAttrs = @{NSFontAttributeName: [NSFont menuFontOfSize:13.0f]};
	NSDictionary *grayAttrs = @{NSForegroundColorAttributeName: [NSColor grayColor], 
		NSFontAttributeName: [NSFont menuFontOfSize:13.0f]};

	BOOL didAddInitialSeparator = NO;
	
	for (i = 0; i<[self count]; i++) {
		NoteObject *aNote = self[i];
		NSArray *urls = [[aNote contentString] allLinks];
		if ([urls count] > 0) {
			if (!didAddInitialSeparator) {
				[urlsMenu addItem:[NSMenuItem separatorItem]];
				didAddInitialSeparator = YES;
			}
			
			unsigned int j;
			for (j=0; j<[urls count]; j++) {
				NSURL *url = urls[j];
				NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Copy URL",@"contextual menu item title to copy urls")
															  action:@selector(copyItemToPasteboard:) keyEquivalent:@""];
				//_other_ people would use "_web_userVisibleString" here, but resourceSpecifier looks like it's good enough
				NSString *urlString = [[url scheme] isEqualToString:@"mailto"] ? [url resourceSpecifier] : [url absoluteString];
				NSString *truncatedURLString = [urlString length] > 60 ? [[urlString substringToIndex: 60] stringByAppendingString:NSLocalizedString(@"...", @"ellipsis character")] : urlString;
				NSMutableAttributedString *titleString = [[NSMutableAttributedString alloc] initWithString:[NSLocalizedString(@"Copy ",@"menu item prefix to copy a URL") stringByAppendingString:truncatedURLString] attributes:blackAttrs];
				
				NSAttributedString *titleDesc = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@" (%@)", aNote.titleString] attributes:grayAttrs];
				[titleString appendAttributedString:titleDesc];
				[item setAttributedTitle:titleString];
				[item setRepresentedObject:urlString];
				[item setTarget:[item representedObject]];
				[urlsMenu addItem:item];
			}
		}
	}
//	if (![urlsMenu numberOfItems])
//		[urlsMenu addItemWithTitle:@"No URLs Found" action:NULL keyEquivalent:@""];
	
//	return [urlsMenu autorelease];
}

@end
