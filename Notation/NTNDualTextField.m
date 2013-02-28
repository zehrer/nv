//
//  NTNDualTextField.m
//  Notation
//
//  Created by Zachary Waldowski on 2/23/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import "NTNDualTextField.h"

static CGFloat const textLeftInset = 18.0f;

@interface NTNDualTextFieldCell ()

@property (nonatomic, strong) NSButtonCell *altSearchButton;

@end

@implementation NTNDualTextFieldCell

- (id)initWithCoder:(NSCoder *)aDecoder {
	if ((self = [super initWithCoder: aDecoder])) {
		[self setStringValue:@""];
		[self setPlaceholderString:NSLocalizedString(@"Search or Create", @"placeholder text in search/create field")];
		[self setFocusRingType:NSFocusRingTypeExterior];

		self.altSearchButton = [[self searchButtonCell] copy];
		[self.altSearchButton setButtonType: NSMomentaryChangeButton];

		[self setSearchButtonCell: self.altSearchButton];
	}
	return self;
}

- (NSRect)drawingRectForBounds:(NSRect)bounds {
	NSRect someBounds = [super drawingRectForBounds: bounds];
	//someBounds.origin.x += textLeftInset;
	//someBounds.size.width -= textLeftInset;
	return someBounds;
}

- (NSRect) searchTextRectForBounds:(NSRect)rect {
	NSRect bounds = [super searchTextRectForBounds: rect];
	return bounds;
}

- (NSRect) searchButtonRectForBounds:(NSRect)rect {
	NSRect bounds = [super searchButtonRectForBounds: rect];
	bounds.origin.y-=0.5;
	return bounds;
	
}

- (NSRect) cancelButtonRectForBounds:(NSRect)rect {
	NSRect bounds = [super cancelButtonRectForBounds: rect];
	bounds.origin.y-=0.5;
	return bounds;
}

@end

@implementation NTNDualTextField

+ (Class)cellClass {
	return [NTNDualTextFieldCell class];
}

- (id)initWithCoder:(NSCoder *)aDecoder {
	if ((self = [super initWithCoder: aDecoder])) {

	}
	return self;
}

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code here.
    }
    
    return self;
}

- (void)drawRect:(NSRect)dirtyRect
{
	[super drawRect:dirtyRect];
    // Drawing code here.
}

@end
