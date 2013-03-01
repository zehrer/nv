//
//  NTNEditorStatusView.m
//  Notation
//
//  Created by Zachary Waldowski on 3/1/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import "NTNEditorStatusView.h"
#import "NTNMainWindowController.h"

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
		if (notesNumber > 1) {
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
