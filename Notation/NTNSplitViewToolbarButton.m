//
//  NTNSplitViewToolBarButton.m
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

#import "NTNSplitViewToolbarButton.h"
#import "NTNSplitViewToolbarButtonCell.h"

static CGFloat kDefaultButtonWidth = 28.0;

@implementation NTNSplitViewToolbarButton

+ (Class)cellClass
{
	return [NTNSplitViewToolbarButtonCell class];
}

- (id)init
{
	self = [super init];
	if (self) {
		_toolbarButtonAlign = NTNSplitViewToolbarButtonAlignmentLeft;
		[(NTNSplitViewToolbarButtonCell *)[self cell] setAlign:_toolbarButtonAlign];
		
		_toolbarButtonImage = NTNSplitViewToolbarButtonImagePlain;
		_toolbarButtonWidth = kDefaultButtonWidth;

		[self setAutoresizingMask:NSViewNotSizable];
		[self setImagePosition:NSImageLeft];
		[self setButtonType:NSMomentaryPushInButton];
		[self setBezelStyle:NSSmallSquareBezelStyle];
		[self setTitle:@""];

		void (^windowStatusChanged)(NSNotification *) = ^(NSNotification *note) {
			[self setNeedsDisplay:YES];
		};

		[[NSNotificationCenter defaultCenter] addObserverForName: NSWindowDidBecomeKeyNotification object: nil queue: nil usingBlock: windowStatusChanged];
		[[NSNotificationCenter defaultCenter] addObserverForName: NSWindowDidResignKeyNotification object: nil queue: nil usingBlock: windowStatusChanged];
	}
	return self;
}

- (void)setTitle:(NSString *)aString
{
	NSMutableParagraphStyle* textStyle = [[NSMutableParagraphStyle defaultParagraphStyle] mutableCopy];
	[textStyle setAlignment: NSCenterTextAlignment];

	NSFont *font = [NSFont fontWithName:@"Helvetiva Neue" size:11.0];

	NSColor *textColor = [NSColor controlTextColor];
	NSShadow* textShadow = [[NSShadow alloc] init];
	[textShadow setShadowColor: [NSColor whiteColor]];
	[textShadow setShadowOffset: NSMakeSize(0, -1)];
	[textShadow setShadowBlurRadius: 0];

	NSDictionary *attributes = [NSDictionary dictionaryWithObjectsAndKeys:
								textShadow, NSShadowAttributeName,
								textColor,  NSForegroundColorAttributeName,
								textStyle,  NSParagraphStyleAttributeName,
								font,		NSFontAttributeName,
								nil];
	NSAttributedString *attributedTitle = [[NSAttributedString alloc] initWithString:aString attributes:attributes];
	[self setAttributedTitle:attributedTitle];
}

- (void)setToolbarButtonAlign:(NTNSplitViewToolbarButtonAlignment)align
{
	_toolbarButtonAlign = align;
	[(NTNSplitViewToolbarButtonCell *)[self cell] setAlign:_toolbarButtonAlign];
}

- (void)setImagePosition:(NSCellImagePosition)aPosition
{
	[super setImagePosition:aPosition];
	[(NTNSplitViewToolbarButtonCell *)[self cell] setImagePosition:aPosition];
}

- (void)setToolbarButtonImage:(NTNSplitViewToolbarButtonImage)toolbarButtonImage
{
	_toolbarButtonImage = toolbarButtonImage;

	NSString *imageName = nil;
	switch (_toolbarButtonImage) {
		case NTNSplitViewToolbarButtonImageAdd:			imageName = NSImageNameAddTemplate; break;
		case NTNSplitViewToolbarButtonImageRemove:		imageName = NSImageNameRemoveTemplate; break;
		case NTNSplitViewToolbarButtonImageQuickLook:	imageName = NSImageNameQuickLookTemplate; break;
		case NTNSplitViewToolbarButtonImageAction:		imageName = NSImageNameActionTemplate; break;
		case NTNSplitViewToolbarButtonImageShare:		imageName = NSImageNameShareTemplate; break;
		case NTNSplitViewToolbarButtonImageIconView:		imageName = NSImageNameIconViewTemplate; break;
		case NTNSplitViewToolbarButtonImageListView:		imageName = NSImageNameListViewTemplate; break;
		case NTNSplitViewToolbarButtonImageLockLocked:	imageName = NSImageNameLockLockedTemplate; break;
		case NTNSplitViewToolbarButtonImageLockUnlocked:	imageName = NSImageNameLockUnlockedTemplate; break;
		case NTNSplitViewToolbarButtonImageGoRight:		imageName = NSImageNameGoRightTemplate; break;
		case NTNSplitViewToolbarButtonImageGoLeft:		imageName = NSImageNameGoLeftTemplate; break;
		case NTNSplitViewToolbarButtonImageStopProgress:	imageName = NSImageNameStopProgressTemplate; break;
		case NTNSplitViewToolbarButtonImageRefresh:		imageName = NSImageNameRefreshTemplate; break;
		default: return;
	}
	self.image = [NSImage imageNamed: imageName];
}


@end
