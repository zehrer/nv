//
//  NTNEditorStatusView.m
//  Notation
//
//  Created by Zachary Waldowski on 3/1/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import "NTNEditorStatusView.h"
#import "NTNMainWindowController.h"

@implementation NTNEditorStatusViewCell

-(void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
    NSAttributedString *attrString = self.attributedStringValue;

    /* if your values can be attributed strings, make them white when selected */
    if (self.isHighlighted && self.backgroundStyle==NSBackgroundStyleDark) {
        NSMutableAttributedString *whiteString = attrString.mutableCopy;
        [whiteString addAttribute: NSForegroundColorAttributeName
                            value: [NSColor whiteColor]
                            range: NSMakeRange(0, whiteString.length) ];
        attrString = whiteString;
    }

    [attrString drawWithRect: [self titleRectForBounds:cellFrame]
                     options: NSStringDrawingTruncatesLastVisibleLine | NSStringDrawingUsesLineFragmentOrigin];
}

- (NSRect)titleRectForBounds:(NSRect)theRect {
    /* get the standard text content rectangle */
    NSRect titleFrame = [super titleRectForBounds:theRect];

    /* find out how big the rendered text will be */
    NSAttributedString *attrString = self.attributedStringValue;
    NSRect textRect = [attrString boundingRectWithSize: titleFrame.size
                                               options: NSStringDrawingTruncatesLastVisibleLine | NSStringDrawingUsesLineFragmentOrigin ];

    /* If the height of the rendered text is less then the available height,
     * we modify the titleRect to center the text vertically */
    if (textRect.size.height < titleFrame.size.height) {
        titleFrame.origin.y = theRect.origin.y + (theRect.size.height - textRect.size.height) / 2.0;
        titleFrame.size.height = textRect.size.height;
    }
    return titleFrame;
}

@end

@implementation NTNEditorStatusView

- (id)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        self.notesNumber = -1;
    }

    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    if ((self = [super initWithCoder: aDecoder])) {
        self.notesNumber = -1;
    }

    return self;
}

- (void)awakeFromNib {
	[super awakeFromNib];
	self.label.stringValue = @"";
	self.notesNumber = self.notesNumber;
}

- (void)mouseDown:(NSEvent *)anEvent {
	NTNMainWindowController *controller = [self.window windowController];
	[controller performSelector: @selector(focusOnSearchField:) withObject: self];
}

- (void)setNotesNumber:(NSInteger)notesNumber {
	if (_notesNumber != notesNumber || !self.label.stringValue.length) {
		NSString *statusString = nil;
		if (notesNumber == NSNotFound) {
			statusString = NSLocalizedString(@"Loading Notes...", nil);
		} else if (notesNumber > 1) {
			statusString = [NSString stringWithFormat:NSLocalizedString(@"%d Notes Selected", nil), notesNumber];
		} else {
			statusString = NSLocalizedString(@"No Note Selected", nil); //\nPress return to create one.";
		}

		self.label.stringValue = statusString;

		_lastNotesNumber = notesNumber;
	}
}

- (void)resetCursorRects {
	[self addCursorRect:[self bounds] cursor:[NSCursor arrowCursor]];
}

- (BOOL)isOpaque {
	return NO;
}

@end
