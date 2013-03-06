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


#import "NoteAttributeColumn.h"

@implementation NoteAttributeColumn

- (id)initWithIdentifier:(id)anObject {
	if ((self = [super initWithIdentifier:anObject])) {
		absoluteMinimumWidth = [anObject sizeWithAttributes:[NoteAttributeColumn standardDictionary]].width + 5;
		[self setMinWidth:absoluteMinimumWidth];
	}

	return self;
}

+ (NSDictionary *)standardDictionary {
	static NSDictionary *standardDictionary = nil;
	if (!standardDictionary)
		standardDictionary = @{NSFontAttributeName : [NSFont systemFontOfSize:[NSFont smallSystemFontSize]]};

	return standardDictionary;
}

- (void)sizeToFit {
	NSLog(@"tablecolumn size to fit");
	[super sizeToFit];
}

- (void)updateWidthForHighlight {
	[self setMinWidth:absoluteMinimumWidth + ([[self tableView] highlightedTableColumn] == self ? 10 : 0)];

}

- (void)setResizingMaskNumber:(NSNumber *)resizingMaskNumber {
	[self setResizingMask:[resizingMaskNumber unsignedIntValue]];
}

@end
