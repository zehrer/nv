//
//  NTNEditorView.m
//  Notation
//
//  Created by Zachary Waldowski on 3/3/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import "NTNEditorView.h"

@interface NTNEditorView () <NSLayoutManagerDelegate> {
	NSRange _lastAutomaticallySelectedRange;
	BOOL _didChangeIntoAutomaticRange;
}

@end

@implementation NTNEditorView

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code here.
    }
    
    return self;
}

- (void)awakeFromNib {
	[super awakeFromNib];

	[[self layoutManager] setDelegate:self];
}

#pragma mark - Accessors

- (void)setAutomaticallySelectedRange:(NSRange)newRange {
	_lastAutomaticallySelectedRange = newRange;
	_didChangeIntoAutomaticRange = NO;
	[self setSelectedRange:newRange];
}

- (NSRange)getSelectedRangeWasAutomatic:(BOOL *)wasAutomatic {
	NSRange myRange = [self selectedRange];
	if (wasAutomatic) {
		*wasAutomatic = !_didRenderFully || NSEqualRanges(_lastAutomaticallySelectedRange, myRange);
	}
	return myRange;
}

#pragma mark - Actions

- (void)highlightRangesTemporarily:(CFArrayRef)ranges {
#warning TODO
}

- (NSRange)highlightTermsTemporarilyReturningFirstRange:(NSString *)typedString avoidHighlight:(BOOL)noHighlight {
#warning TODO
	return NSMakeRange(NSNotFound, 0);
}

#pragma mark - NSLayoutManager

- (void)layoutManager:(NSLayoutManager *)aLayoutManager didCompleteLayoutForTextContainer:(NSTextContainer *)aTextContainer atEnd:(BOOL)flag {
	_didRenderFully = YES;
}

- (void)layoutManagerDidInvalidateLayout:(NSLayoutManager *)aLayoutManager {
	_didRenderFully = NO;
}

@end
