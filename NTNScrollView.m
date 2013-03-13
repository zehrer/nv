//
//  NTNScrollView.m
//  Notation
//
//  Created by Zachary Waldowski on 3/11/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import "NTNScrollView.h"

@implementation NTNScrollView {
	NSColor *_linenPatternColor;
}

- (void)ntn_sharedInit {
	_linenPatternColor = [NSColor colorWithPatternImage: [NSImage imageNamed: @"NTNLightScrollViewTexturedBackground"]];
}

- (id)initWithFrame:(NSRect)frameRect {
	if ((self = [super initWithFrame:frameRect])) {
		[self ntn_sharedInit];
	}
	return self;
}

- (void)awakeFromNib {
	[super awakeFromNib];
	[self ntn_sharedInit];
}

- (void)drawRect:(NSRect)rect {
    [_linenPatternColor set];
    NSRectFill(rect);
}

- (void)setDocumentView:(NSView *)aView {
	[super setDocumentView:aView];
	aView.wantsLayer = YES;
	aView.layer.shadowColor = [[NSColor blackColor] CGColor];
	aView.layer.shadowRadius = 5.0f;
	aView.layer.shadowOpacity = 0.8f;
	aView.layer.shadowOffset = CGSizeZero;
}

- (NSView *)hitTest:(NSPoint)aPoint{
    NSEvent * currentEvent = [NSApp currentEvent];
    if([currentEvent type] == NSLeftMouseDown){
        // if we have a vertical scroller and it accepts the current hit
        if([self hasVerticalScroller] && [[self verticalScroller] hitTest:aPoint] != nil){
            [[self verticalScroller] mouseDown:currentEvent];
            return nil;
        }
        // if we have a horizontal scroller and it accepts the current hit
        if([self hasVerticalScroller] && [[self horizontalScroller] hitTest:aPoint] != nil){
            [[self horizontalScroller] mouseDown:currentEvent];
            return nil;
        }
    }else if([currentEvent type] == NSLeftMouseUp){
        // if mouse up, just tell both our scrollers we have moused up
        if([self hasVerticalScroller]){
            [[self verticalScroller] mouseUp:currentEvent];
        }
        if([self hasHorizontalScroller]){
            [[self horizontalScroller] mouseUp:currentEvent];
        }
        return self;
    }

    return [super hitTest:aPoint];
}

@end
