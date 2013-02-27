//
//  NTNSplitViewToolBarButtonCell.m
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

#import "NTNSplitViewToolbarButtonCell.h"
#import "NTNSplitViewToolbar.h"
#import "NTNSplitView.h"

static NSGradient *btnGradient, *btnHighlightGradient;
static NSColor *gradientStartColor, *gradientEndColor;
static CGFloat kDefaultImageFraction, kDefaultImageEnabledFraction, kDefaultImageDisabledFraction;

@implementation NTNSplitViewToolbarButtonCell
/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Initialization

+ (void)initialize
{
	gradientStartColor = [NSColor colorWithCalibratedRed:0.95 green:0.95 blue:0.95 alpha:1.0];
	gradientEndColor = [NSColor colorWithCalibratedRed:0.75 green:0.75 blue:0.75 alpha:1.0];
	btnHighlightGradient = [[NSGradient alloc] initWithStartingColor: [NSColor colorWithCalibratedRed:0.78 green:0.78 blue:0.78 alpha:1.0]
														 endingColor: [NSColor colorWithCalibratedRed:0.90 green:0.90 blue:0.90 alpha:1.0]];
	kDefaultImageFraction = 0.0;
	kDefaultImageEnabledFraction = 1.0;
	kDefaultImageDisabledFraction = 0.42;
}

- (id)init
{
	self = [super init];
	if (self) {
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(parentWindowDidBecomeKey) name:NSWindowDidBecomeKeyNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(parentWindowDidResignKey) name:NSWindowDidResignKeyNotification object:nil];
	}
	return self;
}



/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Notifications

- (void)parentWindowDidBecomeKey
{
	btnGradient = [[NSGradient alloc] initWithStartingColor: gradientStartColor
												endingColor: gradientEndColor];
	kDefaultImageFraction = kDefaultImageEnabledFraction;
}

- (void)parentWindowDidResignKey
{
	btnGradient = [[NSGradient alloc] initWithStartingColor: [gradientStartColor highlightWithLevel:NTNSplitViewDefaultColorHighlightLevel]
												endingColor: [gradientEndColor highlightWithLevel:NTNSplitViewDefaultColorHighlightLevel]];
	kDefaultImageFraction = kDefaultImageDisabledFraction;
}



/////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
#pragma mark - Drawing

- (void)drawBezelWithFrame:(NSRect)cellFrame inView:(NSView *)controlView;
{
	NSBezierPath *buttonPath = [NSBezierPath bezierPathWithRect:cellFrame];
	switch (self.isHighlighted) {
		case YES: [btnHighlightGradient drawInBezierPath:buttonPath angle:90]; break;
		case NO: [btnGradient drawInBezierPath:buttonPath angle:90]; break;
	}
}

- (void)drawImage:(NSImage*)image withFrame:(NSRect)frame inView:(NSView*)controlView
{
	NSSize imageSize = image.size;
	NSRect imageRect;

	if (![self.attributedTitle.string isEqualToString:@""]) {
		switch (self.imagePosition) {
			case NSImageRight: {
				imageRect = NSMakeRect(NSWidth(controlView.frame) - imageSize.width - NTNSplitViewToolbarButtonImageInset,
										(NSHeight(controlView.frame) - imageSize.height) / 2,
										imageSize.width,
										imageSize.height);
				break;
			}
			case NSImageLeft:
			default: {
				imageRect = NSMakeRect(NTNSplitViewToolbarButtonImageInset,
										(NSHeight(controlView.frame) - imageSize.height) / 2,
										imageSize.width,
										imageSize.height);
				break;
			}
		}
	}
	else {
		imageRect = NSMakeRect((NSWidth(controlView.frame) - imageSize.width) / 2,
								(NSHeight(controlView.frame) - imageSize.height) / 2,
								imageSize.width,
								imageSize.height);
	}

	if (self.isEnabled) {
		if (self.isHighlighted)
			imageRect.origin = NSMakePoint(NSMinX(imageRect), NSMinY(imageRect)+1);
		[image drawInRect:imageRect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:kDefaultImageFraction respectFlipped:YES hints:nil];
	}
	else {
		CGFloat fraction = (self.imageDimsWhenDisabled ? kDefaultImageDisabledFraction : kDefaultImageEnabledFraction);
		[image drawInRect:imageRect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:fraction respectFlipped:YES hints:nil];
	}
}

- (NSRect)drawTitle:(NSAttributedString*)title withFrame:(NSRect)frame inView:(NSView*)controlView
{
	if (self.isHighlighted)
		frame.origin = NSMakePoint(NSMinX(frame), NSMinY(frame)+1);
	[title drawWithRect:frame options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading];
	return frame;
}

@end
