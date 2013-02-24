//
//  NTNSplitView.m
//  New NSSplitView class with multiple subviews resize behaviors and animated transitions
//
//  Derived from DMSplitView.
//  Created by Daniele Margutti on 12/21/12.
//  Copyright (c) 2012 www.danielemargutti.com. All rights reserved.
//
//  Includes parts of from NTNSplitView.
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
#import <Quartz/Quartz.h>

static NSColor *NTNDefaultDividerColor() {
	return [NSColor colorWithCalibratedRed:0.50 green:0.50 blue:0.50 alpha:1.0];
}

static CGFloat const NTNDefaultAnimationDuration = 0.2;

#pragma mark - Internal Constraint Implementation

/** DMSubviewConstraint allows you to set any custom constraint for a
 NTNSplitView subview. You can specify if a subview can be collapsed and
 minimum & maximum allowed size. */
@interface DMSubviewConstraint : NSObject

/** YES if subview can be collapsed */
@property (nonatomic) BOOL canCollapse;
/** minimum allowed size of the subview */
@property (nonatomic) CGFloat minSize;
/** maximum allowed size of the subview */
@property (nonatomic) CGFloat maxSize;

@end

@implementation DMSubviewConstraint

@end

#pragma mark - NTNSplitView Implementation

@interface NTNSplitView () {
	NSMutableDictionary *_priorityIndexes;
	NSMutableArray *_subviewContraints;
	NSMutableDictionary *_viewsToCollapseByDivider;
	CGFloat *_lastValuesBeforeCollapse;
	BOOL *_subviewStates;

	// override divider thickneess
	CGFloat _ntn_dividerThickness;
	BOOL _dividerThicknessOverriden;

	CGFloat _collapsedSubviewDimension;
	BOOL _isAnimating; // an animation is in progress
}
@property(nonatomic, strong) NSView *toolbarContainer;
@property(nonatomic, strong) NSView *anchoredView;
@property(nonatomic, strong) NTNSplitViewToolbar *toolbar;
@end

@implementation NTNSplitView

- (void)ntn_sharedInit {
	[super setDelegate:self];
	self.dividerColor = NTNDefaultDividerColor();

	_priorityIndexes = [[NSMutableDictionary alloc] init];
	_viewsToCollapseByDivider = [[NSMutableDictionary alloc] init];
	_subviewContraints = [[NSMutableArray alloc] init];
	_lastValuesBeforeCollapse = calloc(sizeof(CGFloat), self.subviews.count);
	_subviewStates = calloc(sizeof(BOOL), self.subviews.count);

	for (NSUInteger k = 0; k < self.subviews.count; k++) {
		[_subviewContraints addObject:[[DMSubviewConstraint alloc] init]];
		[self setPriority: self.subviews.count - 1 - k ofSubviewAtIndex: k];
	}
}

- (id)init {
	return [self initWithFrame:NSZeroRect];
}

- (id)initWithCoder:(NSCoder *)coder {
	self = [super initWithCoder:coder];
	if (self) {
		[self ntn_sharedInit];
	}
	return self;
}

- (id)initWithFrame:(NSRect)frameRect {
	self = [super initWithFrame:frameRect];
	if (self) {
		[self ntn_sharedInit];
	}
	return self;
}

- (void)reset {
	[self ntn_sharedInit];
}

- (void)dealloc {
	free(_lastValuesBeforeCollapse);
	free(_subviewStates);
}

#pragma mark - Toolbar management

- (void)addToolbar:(NTNSplitViewToolbar *)theToolbar besidesSubviewAtIndex:(NSUInteger)theSubviewIndex onEdge:(NTNSplitViewToolbarEdge)theEdge {
	/// via notification we inject a refernce to ourself into the toolbar
	[[NSNotificationCenter defaultCenter] postNotificationName:NTNSplitViewToolbarAddedNotification object:self];

	self.anchoredView = self.subviews[theSubviewIndex];
	self.anchoredView.wantsLayer = YES;
	self.anchoredView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

	/// we need a new container view for our toolbar + anchoredView
	self.toolbarContainer = [[NSView alloc] initWithFrame:self.anchoredView.frame];
	self.toolbarContainer.wantsLayer = YES;
	self.toolbarContainer.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;

	[self replaceSubview:self.anchoredView with:self.toolbarContainer];
	[self adjustSubviews];

	self.toolbar = theToolbar;
	self.toolbar.anchoredEdge = theEdge;
	CGFloat posY = theEdge == NTNSplitViewToolbarEdgeBottom ? NSMinY(self.anchoredView.frame) - self.toolbar.height : NSHeight(self.anchoredView.frame);
	self.toolbar.frame = NSMakeRect(NSMinX(self.anchoredView.frame), posY, NSWidth(self.anchoredView.frame), self.toolbar.height);

	[self.toolbarContainer addSubview:self.toolbar];
	[self.toolbarContainer addSubview:self.anchoredView];
}

- (void)setToolbarVisible:(BOOL)toolbarVisible {
	[self setToolbarVisible:toolbarVisible animated:NO];
}

- (void)setToolbarVisible:(BOOL)visible animated:(BOOL)animated {
	_toolbarVisible = visible;

	[NSAnimationContext runAnimationGroup:^(NSAnimationContext *context) {
		context.duration = (animated ? NTNDefaultAnimationDuration : 0.02);
		context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];

		// place the anchor
		NSRect adjustedAnchoredViewRect = self.anchoredView.frame;
		CGFloat anchorPosY = 0.0;
		if (self.toolbar.anchoredEdge == NTNSplitViewToolbarEdgeBottom) {
			anchorPosY = NSMinY(self.anchoredView.frame) + (visible ? self.toolbar.height : -self.toolbar.height);
		}
		adjustedAnchoredViewRect.origin.y = anchorPosY;
		adjustedAnchoredViewRect.size.height += visible ? -self.toolbar.height : self.toolbar.height;
		[self.anchoredView.animator setFrame:adjustedAnchoredViewRect];

		/// place the toolbar
		CGFloat posY;
		if (visible)
			posY = (self.toolbar.anchoredEdge == NTNSplitViewToolbarEdgeBottom ? 0 : NSHeight(self.anchoredView.frame) - self.toolbar.height);
		else
			posY = (self.toolbar.anchoredEdge == NTNSplitViewToolbarEdgeBottom ? -self.toolbar.height : NSHeight(self.anchoredView.frame) + self.toolbar.height);
		NSPoint adjustedToolbarOrigin = NSMakePoint(NSMinX(self.toolbar.frame), posY);
		[self.toolbar.animator setFrameOrigin:adjustedToolbarOrigin];
		
	} completionHandler:^{
		[self.anchoredView setNeedsDisplay:YES];
		[self.anchoredView.superview setNeedsLayout:YES];
		[self.anchoredView setNeedsLayout:YES];
	}];
}

- (void)toggleToolbarVisibileAnimated:(BOOL)animated {
	[self setToolbarVisible:!self.toolbarVisible animated:animated];
}

#pragma mark - Appearance Properties

- (void)setDelegate:(id <NSSplitViewDelegate>)delegate {
	if (delegate) [self doesNotRecognizeSelector:_cmd];
	[super setDelegate:nil];
}

- (void)setShouldDrawDivider:(BOOL)newShouldDrawDivider {
	_shouldDrawDivider = newShouldDrawDivider;
	[self setNeedsDisplay:YES];
}

- (void)setDividerColor:(NSColor *)newDividerColor {
	if (newDividerColor != _dividerColor) {
		_dividerColor = newDividerColor;
		[self setNeedsDisplay:YES];
	}
}

- (CGFloat)dividerThickness {
	if (_dividerThicknessOverriden)
		return _ntn_dividerThickness;
	return [super dividerThickness];
}

- (void)setDividerThickness:(CGFloat)newDividerThickness {
	_ntn_dividerThickness = newDividerThickness;
	_dividerThicknessOverriden = YES;
	[self setNeedsDisplay:YES];
}

- (void)setDividerRectEdge:(NSRectEdge)newDividerRectEdge {
	_dividerRectEdge = newDividerRectEdge;
	[self setNeedsDisplay:YES];
}

- (void)setShouldDrawDividerHandle:(BOOL)newShouldDrawDividerHandle {
	_shouldDrawDividerHandle = newShouldDrawDividerHandle;
	[self setNeedsDisplay:YES];
}

- (BOOL)isSubviewCollapsed:(NSView *)subview {
	// Overloaded version of [NSSplitView isSubviewCollapsed:] which take into account the subview dimension: it is a far more tolerant version of the method.
	if (self.isVertical)
		return ([super isSubviewCollapsed:subview] || ([subview frame].size.width == 0));
	else
		return ([super isSubviewCollapsed:subview] || ([subview frame].size.height == 0));
}

- (void)setVertical:(BOOL)flag {
	[super setVertical:flag];
	
	CATransition *transition = [CATransition animation];
	transition.duration = 0.2;
	transition.type = kCATransitionFade;
	[self.layer addAnimation:transition forKey:nil];
}

#pragma mark - Appearance Drawing Routines

- (void)drawDividerInRect:(NSRect)aRect {
	if (self.shouldDrawDivider) {
		[self.dividerColor set];
		[NSBezierPath fillRect: aRect];

		if (self.dividerStyle != NSSplitViewDividerStyleThin && self.shouldDrawDividerHandle) {
			NSColor *tempDividerColor = self.dividerColor;
			NSSplitViewDividerStyle tempStyle = self.dividerStyle;

			self.dividerColor = [NSColor clearColor];
			self.dividerStyle = NSSplitViewDividerStyleThick;

			[super drawDividerInRect:aRect];

			self.dividerStyle = tempStyle;
			self.dividerColor = tempDividerColor;
		}
	} else { // OS's standard handler
		[super drawDividerInRect:aRect];
	}
}

#pragma mark - Behavior Properties Set

- (void)setPriority:(NSInteger)priorityIndex ofSubviewAtIndex:(NSInteger)subviewIndex {
	_priorityIndexes[@(priorityIndex)] = @(subviewIndex);
}

- (void)setMaxSize:(CGFloat)maxSize ofSubviewAtIndex:(NSUInteger)subviewIndex {
	((DMSubviewConstraint *)_subviewContraints[subviewIndex]).maxSize = maxSize;
}

- (void)setMinSize:(CGFloat)minSize ofSubviewAtIndex:(NSUInteger)subviewIndex {
	((DMSubviewConstraint *) _subviewContraints[subviewIndex]).minSize = minSize;
}

- (CGFloat)minSizeForSubviewAtIndex:(NSUInteger)subviewIndex {
	return ((DMSubviewConstraint *) _subviewContraints[subviewIndex]).minSize;
}

- (CGFloat)maxSizeForSubviewAtIndex:(NSUInteger)subviewIndex {
	return ((DMSubviewConstraint *) _subviewContraints[subviewIndex]).maxSize;
}

- (void)setCanCollapse:(BOOL)canCollapse subviewAtIndex:(NSUInteger)subviewIndex {
	((DMSubviewConstraint *) _subviewContraints[subviewIndex]).canCollapse = canCollapse;
}

- (BOOL)canCollapseSubviewAtIndex:(NSUInteger)subviewIndex {
	return ((DMSubviewConstraint *) _subviewContraints[subviewIndex]).canCollapse;
}

- (void)setCollapseSubviewAtIndex:(NSUInteger)viewIndex forDoubleClickOnDividerAtIndex:(NSUInteger)dividerIndex {
	[_viewsToCollapseByDivider setObject:@(viewIndex) forKey:@(dividerIndex)];
}

- (NSUInteger)subviewIndexToCollapseForDoubleClickOnDividerAtIndex:(NSUInteger)dividerIndex {
	id num = _viewsToCollapseByDivider[@(dividerIndex)];
	return num ? [num unsignedIntegerValue] : NSNotFound;
}

#pragma mark - Splitview delegate methods

- (CGFloat)splitView:(NSSplitView *)splitView constrainMinCoordinate:(CGFloat)proposedMin ofSubviewAt:(NSInteger)viewIndex {
	DMSubviewConstraint *subviewConstraint = _subviewContraints[viewIndex];
	if (!subviewConstraint.minSize && !subviewConstraint.maxSize) // no constraint set for this
		return proposedMin;

	NSView *targetSubview = ((NSView *) splitView.subviews[viewIndex]);
	CGFloat subviewOrigin = (splitView.isVertical ? targetSubview.frame.origin.x : targetSubview.frame.origin.y);
	CGFloat finalCoordinate = subviewOrigin + subviewConstraint.minSize;
	return finalCoordinate;
}

- (CGFloat)splitView:(NSSplitView *)splitView constrainMaxCoordinate:(CGFloat)proposedMax ofSubviewAt:(NSInteger)offset {
	DMSubviewConstraint *constraintShrinkingSubview = _subviewContraints[offset + 1];

	NSView *growingSubview = self.subviews[offset];
	NSView *shrinkingSubview = self.subviews[offset + 1];
	NSRect growingSubviewFrame = growingSubview.frame;
	NSRect shrinkingSubviewFrame = shrinkingSubview.frame;
	CGFloat shrinkingSize;
	CGFloat currentCoordinate;
	if (self.isVertical) {
		currentCoordinate = growingSubviewFrame.origin.x + growingSubviewFrame.size.width;
		shrinkingSize = shrinkingSubviewFrame.size.width;
	} else {
		currentCoordinate = growingSubviewFrame.origin.y + growingSubviewFrame.size.height;
		shrinkingSize = shrinkingSubviewFrame.size.height;
	}

	CGFloat minimumSize = constraintShrinkingSubview.minSize;
	return currentCoordinate + (shrinkingSize - minimumSize);
}

//- (void)ntn_enumerateSubviewsByPriority:^(NSView *subview, BOOL *stop)
- (void)ntn_enumerateSubviewsByPriorityUsingBlock:(void (^)(NSUInteger index, BOOL *stop))block {
	if (!block) return;
	if (_priorityIndexes.count == self.subviews.count) {
		[[_priorityIndexes.allKeys sortedArrayUsingSelector: @selector(compare:)] enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
			NSNumber *subviewIndex = _priorityIndexes[obj];
			NSUInteger index = subviewIndex.unsignedIntegerValue;
			if (index >= self.subviews.count)
				return;
			block(index, stop);
		}];
	} else {
		__block NSUInteger priority = 0;
		[self.subviews enumerateObjectsWithOptions: NSEnumerationReverse usingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
			block(priority, stop);
			priority++;
		}];
	}
}

- (void)splitView:(NSSplitView *)splitView resizeSubviewsWithOldSize:(NSSize)oldSize {
	if (_isAnimating) { // if we are inside an animated session we want to redraw correctly NSSplitView elements (as like the moving divider)
		[self setNeedsDisplay:YES];
		return; // relayout constraint does not happend while animating... we don't want to interfere with animation.
	}

	__block CGFloat deltaValue = (self.isVertical ? (self.bounds.size.width - oldSize.width) :
								  (self.bounds.size.height - oldSize.height));

	//if (!_priorityIndexes.count) return;

	[self ntn_enumerateSubviewsByPriorityUsingBlock:^(NSUInteger index, BOOL *stop) {
		NSView *subview = self.subviews[index];

		if ([self isSubviewCollapsed: subview]) return;
		
		NSSize frameSize = subview.frame.size;
		DMSubviewConstraint *constraint = _subviewContraints[index];
		CGFloat minValue = constraint.minSize;

		if (self.isVertical) {
			frameSize.height = self.bounds.size.height;
			if (deltaValue > 0.0f || frameSize.width + deltaValue >= minValue) {
				frameSize.width += deltaValue;
				deltaValue = 0.0f;
			} else if (deltaValue < 0.0f) {
				deltaValue += frameSize.width - minValue;
				frameSize.width = minValue;
			}
		} else {
			frameSize.width = self.bounds.size.width;
			if (deltaValue > 0.0f || frameSize.height + deltaValue >= minValue) {
				frameSize.height += deltaValue;
				deltaValue = 0.0f;
			} else if (deltaValue < 0.0f) {
				deltaValue += frameSize.height - minValue;
				frameSize.height = minValue;
			}
		}
		[subview setFrameSize:frameSize];
	}];

	CGFloat offset = 0;
	NSUInteger k = 0;
	
	for (NSView *subview in self.subviews) {
		NSRect viewFrame = subview.frame;
		NSPoint viewOrigin = viewFrame.origin;

		if (self.isVertical) viewOrigin.x = offset;
		else viewOrigin.y = offset;
		[subview setFrameOrigin:viewOrigin];
		offset += (self.isVertical ? viewFrame.size.width : viewFrame.size.height) + self.dividerThickness;
		k++;

		// When a subview is collapsed NSSplitView set it's hidden property as YES
		// So we need to set it as visible if we set as uncollapsed programmatically, otherwise we will see
		// a blank space instead of our superview
		if (self.isVertical) [subview setHidden:!(subview.frame.size.width > 0)];
		else [subview setHidden:!(subview.frame.size.height > 0)];
	}
}

- (BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview {
	NSUInteger viewIndex = [self.subviews indexOfObject:subview];
	if (viewIndex == NSNotFound) return NO;
	return [_subviewContraints[viewIndex] canCollapse];
}

- (BOOL)splitView:(NSSplitView *)splitView shouldCollapseSubview:(NSView *)subview forDoubleClickOnDividerAtIndex:(NSInteger)dividerIndex {
	NSUInteger indexOfSubviewToCollapse = [self subviewIndexToCollapseForDoubleClickOnDividerAtIndex:dividerIndex];
	NSUInteger indexOfSubview = [self.subviews indexOfObject:subview];

	return ((indexOfSubviewToCollapse == NSNotFound) || (indexOfSubview == indexOfSubviewToCollapse));
}

#pragma mark - Collapse

- (CGFloat)positionOfDividerAtIndex:(NSInteger)dividerIndex {
	// It looks like NSSplitView relies on its subviews being ordered left->right or top->bottom so we can too.
	// It also raises w/ array bounds exception if you use its API with dividerIndex > count of subviews.
	while (dividerIndex >= 0 && [self isSubviewCollapsed: self.subviews[dividerIndex]])
		dividerIndex--;
	
	if (dividerIndex < 0) return 0;

	NSRect priorViewFrame = [self.subviews[dividerIndex] frame];
	return self.isVertical ? NSMaxX(priorViewFrame) : NSMaxY(priorViewFrame);
}

- (NSArray *)ntn_getNewSubviewsRectsWithPositionsOfDividersAtIndexes:(NSDictionary *)positionsByIndexes {
	NSMutableArray *arr = [NSMutableArray arrayWithCapacity: self.subviews.count];

	CGFloat dividerTkn = self.dividerThickness;
	for (NSUInteger i = 0; i < self.subviews.count; i++)
		arr[i] = [NSValue valueWithRect: [self.subviews[i] frame]];

	[positionsByIndexes enumerateKeysAndObjectsUsingBlock:^(NSNumber *indexObject, NSNumber *positionObject, BOOL *stop) {
		NSUInteger index = [indexObject unsignedIntegerValue];
		CGFloat newPosition = [positionObject doubleValue];

		// save divider state where necessary
		[self ntn_saveCurrentDivididerState];

		NSRect thisRect = [arr[index] rectValue];
		NSRect nextRect = [arr[index+1] rectValue];

		if (self.isVertical) {
			CGFloat oldMaxXOfRightHandView = NSMaxX(nextRect);
			thisRect.size.width = newPosition - NSMinX(thisRect);
			CGFloat dividerAdjustment = (newPosition < NSWidth(self.bounds)) ? dividerTkn : 0.0;
			nextRect.origin.x = newPosition + dividerAdjustment;
			nextRect.size.width = oldMaxXOfRightHandView - newPosition - dividerAdjustment;
		} else {
			CGFloat oldMaxYOfBottomView = NSMaxY(nextRect);
			thisRect.size.height = newPosition - NSMinY(thisRect);
			CGFloat dividerAdjustment = (newPosition < NSHeight(self.bounds)) ? dividerTkn : 0.0;
			nextRect.origin.y = newPosition + dividerAdjustment;
			nextRect.size.height = oldMaxYOfBottomView - newPosition - dividerAdjustment;
		}

		arr[index] = [NSValue valueWithRect: thisRect];
		arr[index + 1] = [NSValue valueWithRect: nextRect];
	}];

	return arr;
}

- (void)setPositionsOfDividersAtIndexes:(NSDictionary *)positionsByIndexes animated:(BOOL)animated completitionBlock:(void (^)(BOOL isEnded))completition {
	NSArray *newRects = [self ntn_getNewSubviewsRectsWithPositionsOfDividersAtIndexes: positionsByIndexes];

	id <NTNSplitViewDelegate> delegate = self.eventsDelegate;
	BOOL shouldNotify = animated && delegate && [delegate respondsToSelector:@selector(splitView:didStartOrStopAnimation:)];

	if (shouldNotify) [delegate splitView:self didStartOrStopAnimation:YES];

	_isAnimating = YES;

	[NSAnimationContext runAnimationGroup: ^(NSAnimationContext *context) {
		context.duration = (animated ? NTNDefaultAnimationDuration : 0.01);
		context.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseInEaseOut];

		[self.subviews enumerateObjectsUsingBlock:^(NSView *subview, NSUInteger i, BOOL *stop) {
			NSRect newRect = [newRects[i] rectValue];
			if (subview.isHidden && ((self.isVertical ? newRect.size.width > 0 : newRect.size.height > 0)))
				[subview setHidden:NO];
			[subview.animator setFrame: newRect];
		}];
	} completionHandler: ^{
		_isAnimating = NO;
		[self setNeedsDisplay:YES];

		if (completition) completition(YES);
		if (shouldNotify) [delegate splitView:self didStartOrStopAnimation:NO];
	}];
}

- (void)setPosition:(CGFloat)position ofDividerAtIndex:(NSInteger)dividerIndex animated:(BOOL)animated completitionBlock:(void (^)(BOOL isEnded))completition {
	NSUInteger numberOfSubviews = self.subviews.count;
	if (dividerIndex >= numberOfSubviews) return;
	[self setPositionsOfDividersAtIndexes:@{@(dividerIndex) : @(position)} animated:animated completitionBlock:completition];
}

- (void)toggleSubviewAtIndex:(NSUInteger)subviewIndex animated:(BOOL)animated {
	if (subviewIndex >= self.subviews.count || subviewIndex == NSNotFound) return;
	// only side subviews can be collapsed (at least for now)
	if (subviewIndex != 0 && subviewIndex != self.subviews.count - 1) return;
	BOOL isCollapsed = [self isSubviewCollapsed:self.subviews[subviewIndex]];

	NSView *subview = self.subviews[subviewIndex];
	NSInteger dividerIndex = (subviewIndex == 0 ? subviewIndex : subviewIndex - 1);
	CGFloat newValue;
	if (isCollapsed) {
		newValue = _lastValuesBeforeCollapse[dividerIndex];
	} else {
		if (subviewIndex == 0)
			newValue = 0.0f;
		else {
			newValue = [self positionOfDividerAtIndex:dividerIndex];
			newValue += (self.isVertical ? NSWidth(subview.frame) : NSHeight(subview.frame));
		}
	}
	[self setPosition:newValue
	 ofDividerAtIndex:dividerIndex
			 animated:animated completitionBlock:nil];
}

- (void)toggleSubview:(NSView *)subview animated:(BOOL)animated {
	[self toggleSubviewAtIndex:[self.subviews indexOfObject:subview] animated:animated];
}

#pragma mark - Other Events of the delegate

- (void)ntn_saveCurrentDivididerState {
	for (NSUInteger k = 0; k < self.subviews.count - 1; k++) {
		CGFloat position = [self positionOfDividerAtIndex:k];
		BOOL isCollapsedLeft = (position == 0);
		BOOL isCollapsedRight = (position == (self.isVertical ? NSWidth(self.frame) : NSHeight(self.frame)) - self.dividerThickness);
		if (!isCollapsedLeft && !isCollapsedRight)
			_lastValuesBeforeCollapse[k] = position;
	}
}

- (void)splitViewDidResizeSubviews:(NSNotification *)notification {
	NSUInteger dividerIndex = [notification.userInfo[@"NSSplitViewDividerIndex"] unsignedIntegerValue];
	CGFloat newPosition = [self positionOfDividerAtIndex:dividerIndex];

	id <NTNSplitViewDelegate> delegate = self.eventsDelegate;

	// used to restore from collapse state; we want to save it before animating, not while animating and finally we won't save collapsed state
	if (!_isAnimating) {
		[self ntn_saveCurrentDivididerState];

		if ([delegate respondsToSelector:@selector(splitView:dividerAtIndex:movedTo:)])
			[delegate splitView:self
							dividerAtIndex:dividerIndex
								   movedTo:newPosition];

		BOOL isCollapsing = _subviewStates[dividerIndex] && (newPosition == 0);
		BOOL isExpanding = !_subviewStates[dividerIndex] && (newPosition > 0);

		if ([delegate respondsToSelector:@selector(splitView:subviewAtIndex:didExpand:)]) {
			if (isCollapsing)
				[delegate splitView:self
								subviewAtIndex:dividerIndex
									 didExpand: NO];
			else if (isExpanding)
				[delegate splitView:self
								subviewAtIndex:dividerIndex
									 didExpand: YES];
		}
	}

	[self.subviews enumerateObjectsUsingBlock:^(NSView *subview, NSUInteger subviewIndex, BOOL *stop) {
		CGFloat size = self.isVertical ? NSWidth(subview.frame) : NSHeight(subview.frame);
		_subviewStates[subviewIndex] = [self isSubviewCollapsed: subview] ? NO : (size ? YES : NO);
	}];
}

#pragma mark - Working with subview's sizes

- (void)setSize:(CGFloat)size ofSubviewAtIndex:(NSInteger)subviewIndex animated:(BOOL)animated completition:(void (^)(BOOL isEnded))completition {
	NSView *subview = self.subviews[subviewIndex];
	CGFloat frameOldSize = (self.isVertical ? NSWidth(subview.frame) : NSHeight(subview.frame));
	CGFloat deltaValue = (size - frameOldSize); // if delta > 0 subview will grow, otherwise if delta < 0 subview will shrink

	if (deltaValue == 0)
		return; // no changes required

	NSMutableDictionary *positions = [NSMutableDictionary dictionaryWithCapacity:2];

	if (subviewIndex > 0 && subviewIndex < (self.subviews.count - 1) && self.subviews.count > 2) {
		// We have more than 2 subviews and our target subview index has two dividers, one at left and another at right.
		// We want to apply the same delta value at both edges (proportional)
		NSUInteger leftDividerIndex = (subviewIndex - 1);
		NSUInteger rightDividerIndex = subviewIndex;
		CGFloat leftDividerPosition = [self positionOfDividerAtIndex:leftDividerIndex];
		CGFloat rightDividerPosition = [self positionOfDividerAtIndex:rightDividerIndex];
		CGFloat deltaPerDivider = (deltaValue / 2.0f);

		leftDividerPosition -= deltaPerDivider;
		rightDividerPosition += deltaPerDivider;

		positions[@(leftDividerIndex)] = @(leftDividerPosition);
		positions[@(rightDividerIndex)] = @(rightDividerPosition);
	} else {
		// We can shrink or grow only at one side because our index is the top left or the top right
		NSInteger dividerIndex = (subviewIndex > 0 ? subviewIndex - 1 : subviewIndex);
		NSInteger dividerPosition = [self positionOfDividerAtIndex:dividerIndex];
		if (subviewIndex == 0) dividerPosition += deltaValue;
		else dividerPosition -= deltaValue;
		positions[@(dividerIndex)] = @(dividerPosition);
	}

	[self setPositionsOfDividersAtIndexes:positions animated:animated completitionBlock:completition];
}

@end
