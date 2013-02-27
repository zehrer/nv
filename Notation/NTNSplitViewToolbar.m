//
//  NTNSplitViewToolBar.m
//  Notation
//
//  Derived from NTNSplitView.
//  Created by Frank Gregor on 29.07.12.
//  Copyright (c) 2012 cocoa:naut. All rights reserved.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the “Software”), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED “AS IS”, WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

#import "NTNSplitView.h"

CGFloat NTNSplitViewToolbarButtonTextInset = 10.0;
CGFloat NTNSplitViewToolbarButtonImageInset = 10.0;
CGFloat NTNSplitViewToolbarButtonImageToTextDistance = 10.0;

CGFloat const NTNSplitViewDefaultColorHighlightLevel = 0.42;

static CGFloat  kDefaultToolbarHeight, kDefaultItemDelimiterWidth;
static NSColor  *kDefaultBorderColor, *kDefaultGradientStartColor, *kDefaultGradientEndColor;
static NSColor  *delimiterGradientEndColor, *delimiterGradientMiddleColor, *delimiterGradientCenterColor;

NSString *const NTNSplitViewToolbarAddedNotification = @"InjectReferenceNotification";

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
@interface NTNSplitViewToolbar () {
	NSRect _previousToolbarRect;
	NSMutableArray *_delimiterOffsets;
	NTNSplitView *_enclosingSplitView;
	NSMutableArray *_buttons;
}

- (void)drawItemDelimiter;
- (void)recalculateItemPositions;
@end


@implementation NTNSplitViewToolbar
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Initialzation

+ (void)initialize
{
	kDefaultBorderColor				= [NSColor colorWithCalibratedRed:0.50 green:0.50 blue:0.50 alpha:1.0];
	kDefaultGradientStartColor		= [NSColor colorWithCalibratedRed:0.75 green:0.75 blue:0.75 alpha:1.0];
	kDefaultGradientEndColor		= [NSColor colorWithCalibratedRed:0.95 green:0.95 blue:0.95 alpha:1.0];
	delimiterGradientEndColor		= [NSColor colorWithCalibratedRed: 0.75 green: 0.75 blue: 0.75 alpha: 0.1];
	delimiterGradientMiddleColor	= [NSColor colorWithCalibratedRed: 0.78 green: 0.78 blue: 0.78 alpha: 0.5];
	delimiterGradientCenterColor	= [NSColor colorWithCalibratedRed: 0.42 green: 0.42 blue: 0.42 alpha: 1];

	kDefaultToolbarHeight = 24.0;
	kDefaultItemDelimiterWidth = 1.0;
}

- (id)init
{
	self = [super init];
	if (self) {
		[self commonConfiguration];
	}
	return self;
}

- (void)commonConfiguration
{
	_frame = NSZeroRect;
	_height = kDefaultToolbarHeight;
	_itemDelimiterEnabled = YES;
	_contentAlign = NTNSplitViewToolbarContentAlignmentDirected;

	_buttons = [[NSMutableArray alloc] init];
	_previousToolbarRect = NSZeroRect;
	_delimiterOffsets = [NSMutableArray array];
	_enclosingSplitView = nil;
	_anchoredEdge = NTNSplitViewToolbarEdgeUndefined;
	[self setAnchoredEdge:NTNSplitViewToolbarEdgeBottom];

	void (^windowStatusChanged)(NSNotification *) = ^(NSNotification *note) {
		[self setNeedsDisplay:YES];
	};

	[[NSNotificationCenter defaultCenter] addObserverForName: NSWindowDidBecomeKeyNotification object: nil queue: nil usingBlock: windowStatusChanged];
	[[NSNotificationCenter defaultCenter] addObserverForName: NSWindowDidResignKeyNotification object: nil queue: nil usingBlock: windowStatusChanged];
	
	[[NSNotificationCenter defaultCenter] addObserverForName: NTNSplitViewToolbarAddedNotification object: nil queue: nil usingBlock: ^(NSNotification *note) {
		_enclosingSplitView = note.object;
	}];
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - API

- (void)addItem:(NTNSplitViewToolbarButton *)aButton
{
	if (!_buttons)
		_buttons = [[NSMutableArray alloc] init];

	/// calculate or set the correct button width
	NSSize buttonSize;
	NSSize imageSize = (aButton.image ? aButton.image.size : NSMakeSize(0, 0));
	NSSize textSize = (aButton.attributedTitle ? aButton.attributedTitle.size : NSMakeSize(0, 0));

	CGFloat buttonWidth = aButton.toolbarButtonWidth;
	/// text + image
	if (textSize.width > 0 && imageSize.width > 0) {
		buttonWidth = NTNSplitViewToolbarButtonImageInset + imageSize.width + NTNSplitViewToolbarButtonImageToTextDistance + textSize.width + NTNSplitViewToolbarButtonTextInset;
	}
	/// image only
	else if (textSize.width == 0 && imageSize.width > 0) {
		CGFloat width = (NTNSplitViewToolbarButtonImageInset + imageSize.width + NTNSplitViewToolbarButtonImageInset);
		buttonWidth = (aButton.toolbarButtonWidth > width ? aButton.toolbarButtonWidth : width);
	}
	/// text only
	else if (textSize.width > 0 && imageSize.width == 0) {
		buttonWidth = NTNSplitViewToolbarButtonTextInset + textSize.width + NTNSplitViewToolbarButtonTextInset;
	}
	buttonWidth = (buttonWidth < aButton.toolbarButtonWidth ? aButton.toolbarButtonWidth : buttonWidth);
	buttonSize = NSMakeSize(buttonWidth, self.height - 1);

	/// set the correct button alignment
	switch (aButton.toolbarButtonAlign) {
		case NTNSplitViewToolbarButtonAlignmentLeft: aButton.autoresizingMask = NSViewMaxXMargin; break;
		case NTNSplitViewToolbarButtonAlignmentRight: aButton.autoresizingMask = NSViewMinXMargin; break;
	}
	aButton.frame = NSMakeRect(0, 0, buttonSize.width, buttonSize.height);

	[_buttons addObject:aButton];
	[self addSubview:aButton];
}

- (void)removeItem:(NTNSplitViewToolbarButton *)aButton
{
	[_buttons removeObject:aButton];
	[aButton removeFromSuperview];
}

- (void)removeAllItems
{
	self.subviews = [NSArray array];
	[_buttons removeAllObjects];
	[self setNeedsDisplay:YES];
}

- (void)enable
{
	[_buttons enumerateObjectsWithOptions: NSEnumerationConcurrent usingBlock:^(NTNSplitViewToolbarButton *obj, NSUInteger idx, BOOL *stop) {
		[obj setEnabled: YES];
	}];
}

- (void)disable
{
	[_buttons enumerateObjectsWithOptions: NSEnumerationConcurrent usingBlock:^(NTNSplitViewToolbarButton *obj, NSUInteger idx, BOOL *stop) {
		[obj setEnabled: NO];
	}];
}



/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Accessors

- (void)setAnchoredEdge:(NTNSplitViewToolbarEdge)anchoredEdge
{
	_anchoredEdge = anchoredEdge;
	[self setAutoresizingMask:NSViewWidthSizable | (_anchoredEdge == NTNSplitViewToolbarEdgeBottom ? NSViewMaxYMargin : NSViewMinYMargin)];

	/// In case of the toolbar is on top, we have to draw a 1 pixel wide separator line on the bottom side (origin.y == 0).
	/// For this reason all toolbar buttons have to placed this 1 pixel above that line for not overpainting it.
	if (_anchoredEdge == NTNSplitViewToolbarEdgeTop) {
		[self.subviews enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
			NSPoint adjustedOrigin = [(NSView *)obj frame].origin;
			adjustedOrigin.y++;
			[(NSView *)obj setFrameOrigin:adjustedOrigin];
		}];
	}
}

- (void)setItemDelimiterEnabled:(BOOL)itemDelimiterEnabled
{
	_itemDelimiterEnabled = itemDelimiterEnabled;
	_previousToolbarRect = NSZeroRect;
	[self setNeedsDisplay:YES];
}

- (void)setContentAlign:(NTNSplitViewToolbarContentAlignment)contentAlign
{
	_contentAlign = contentAlign;
	_previousToolbarRect = NSZeroRect;
	[self setNeedsDisplay:YES];
}

/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Private Helper

- (void)drawItemDelimiter
{
	if (!self.itemDelimiterEnabled)
		return;

	BOOL isKeyWindow = [[self window] isKeyWindow];
	NSGradient *gradient = [[NSGradient alloc] initWithColorsAndLocations:
							(isKeyWindow ? delimiterGradientEndColor		: [delimiterGradientEndColor highlightWithLevel:NTNSplitViewDefaultColorHighlightLevel]), 0.0,
							(isKeyWindow ? delimiterGradientMiddleColor	: [delimiterGradientMiddleColor highlightWithLevel:NTNSplitViewDefaultColorHighlightLevel]), 0.10,
							(isKeyWindow ? delimiterGradientCenterColor	: [delimiterGradientCenterColor highlightWithLevel:NTNSplitViewDefaultColorHighlightLevel]), 0.50,
							(isKeyWindow ? delimiterGradientMiddleColor	: [delimiterGradientMiddleColor highlightWithLevel:NTNSplitViewDefaultColorHighlightLevel]), 0.90,
							(isKeyWindow ? delimiterGradientEndColor		: [delimiterGradientEndColor highlightWithLevel:NTNSplitViewDefaultColorHighlightLevel]), 1.0,
							nil];

	[_delimiterOffsets enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
		CGFloat posX = [(NSNumber *)obj doubleValue];
		NSRect delimiterRect = NSMakeRect(posX, (self.anchoredEdge == NTNSplitViewToolbarEdgeBottom ? 0 : 1), kDefaultItemDelimiterWidth, NSHeight(self.bounds) - 1);
		NSBezierPath *delimiterLine = [NSBezierPath bezierPathWithRect:delimiterRect];
		[gradient drawInBezierPath:delimiterLine angle:90];
	}];
}

- (void)recalculateItemPositions
{
	__block CGFloat leftOffset = 0;
	__block CGFloat rightOffset = NSWidth(self.frame);

	[_delimiterOffsets removeAllObjects];

	switch (self.contentAlign) {
		case NTNSplitViewToolbarContentAlignmentDirected: {
			[_buttons enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
				if ([obj isKindOfClass:[NTNSplitViewToolbarButton class]]) {
					NTNSplitViewToolbarButton *theButton = (NTNSplitViewToolbarButton *)obj;
					if (theButton.toolbarButtonAlign == NTNSplitViewToolbarButtonAlignmentLeft) {
						theButton.autoresizingMask = NSViewMaxXMargin;
						[theButton setFrameOrigin:NSMakePoint(leftOffset, (self.anchoredEdge == NTNSplitViewToolbarEdgeBottom ? 0 : 1))];
						leftOffset += NSWidth(theButton.frame) + (self.isItemDelimiterEnabled ? kDefaultItemDelimiterWidth : 0);
						[_delimiterOffsets setObject:[NSNumber numberWithDouble:ceil(NSMaxX(theButton.frame))] atIndexedSubscript:idx];

					} else {
						theButton.autoresizingMask = NSViewMinXMargin;
						[theButton setFrameOrigin:NSMakePoint(rightOffset - NSWidth(theButton.frame), (self.anchoredEdge == NTNSplitViewToolbarEdgeBottom ? 0 : 1))];
						rightOffset -= (NSWidth(theButton.frame) + (self.isItemDelimiterEnabled ? kDefaultItemDelimiterWidth : 0));
						[_delimiterOffsets setObject:[NSNumber numberWithDouble:ceil(NSMinX(theButton.frame))-1] atIndexedSubscript:idx];
					}
				}
			}];
			break;
		}

		case NTNSplitViewToolbarContentAlignmentCentered: {
			__block CGFloat allButtonsWidth = 0;

			/// calculate the left offset related to all button widths
			[_buttons enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
				if ([obj isKindOfClass:[NTNSplitViewToolbarButton class]]) {
					NTNSplitViewToolbarButton *theButton = (NTNSplitViewToolbarButton *)obj;
					allButtonsWidth += NSWidth(theButton.frame) + (self.isItemDelimiterEnabled ? kDefaultItemDelimiterWidth : 0);
				}
			}];
			leftOffset = ceil((NSWidth(self.bounds) - allButtonsWidth) / 2);

			/// calculate the button positions
			[_buttons enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
				if ([obj isKindOfClass:[NTNSplitViewToolbarButton class]]) {
					NTNSplitViewToolbarButton *theButton = (NTNSplitViewToolbarButton *)obj;
					theButton.autoresizingMask = NSViewNotSizable;
					[theButton setFrameOrigin:NSMakePoint(leftOffset, (self.anchoredEdge == NTNSplitViewToolbarEdgeBottom ? 0 : 1))];
					leftOffset += ceil(NSWidth(theButton.frame)) + (self.isItemDelimiterEnabled ? kDefaultItemDelimiterWidth : 0);

					/// As we draw the delimiter always on the right side of an item,
					/// the first item needs to get space for an additional delimiter on its left side.
					if (idx == 0)
						[_delimiterOffsets setObject:[NSNumber numberWithDouble:ceil(NSMinX(theButton.frame))-1] atIndexedSubscript:idx];

					[_delimiterOffsets setObject:[NSNumber numberWithDouble:ceil(NSMaxX(theButton.frame))] atIndexedSubscript:idx+1];
				}
			}];
			break;
		}
	}
}

- (BOOL)containsSubView:(NSView *)subview
{
	__block BOOL containsSubView = NO;
	[[self subviews] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
		if ([subview isEqualTo:(NSView *)obj]) {
			containsSubView = YES;
			*stop = YES;
		}
	}];
	return containsSubView;
}


/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - NSView

- (void)drawRect:(NSRect)dirtyRect
{
	BOOL isKeyWindow = [[self window] isKeyWindow];

	NSColor *startColor = (isKeyWindow ? kDefaultGradientStartColor : [kDefaultGradientStartColor highlightWithLevel:NTNSplitViewDefaultColorHighlightLevel]);
	NSColor *endColor = (isKeyWindow ? kDefaultGradientEndColor : [kDefaultGradientEndColor highlightWithLevel:NTNSplitViewDefaultColorHighlightLevel]);
	NSGradient *toolbarKeyWindowGradient = [[NSGradient alloc] initWithStartingColor: startColor endingColor: endColor];
	NSBezierPath *buttonBarPath = [NSBezierPath bezierPathWithRect:dirtyRect];
	[toolbarKeyWindowGradient drawInBezierPath:buttonBarPath angle:90];

	CGFloat originY = (self.anchoredEdge == NTNSplitViewToolbarEdgeTop ? 0 : NSHeight(dirtyRect) - 1);
	NSRect borderLineRect = NSMakeRect(0, originY, NSWidth(dirtyRect), 1.0);
	NSBezierPath *borderLinePath = [NSBezierPath bezierPathWithRect:borderLineRect];
	NSColor *borderColor = (isKeyWindow ? kDefaultBorderColor : [kDefaultBorderColor highlightWithLevel:NTNSplitViewDefaultColorHighlightLevel]);
	[borderColor setFill];
	[borderLinePath fill];

	if (!NSEqualRects(self.bounds, _previousToolbarRect))
		[self recalculateItemPositions];
	_previousToolbarRect = self.bounds;

	[self drawItemDelimiter];
}


@end
