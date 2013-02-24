//
//  NTNSplitViewToolBarButtonCell.m
//  Notation
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

#import "NTNSplitViewToolbar.h"

@class NTNSplitView;

@protocol NTNSplitViewDelegate <NSObject>
@optional
/** Inform delegate about the status of the animation (if set).
 @param	splitView	target NTNSplitView instance
 @param	animating	YES if animating is started, NO if animation is ended
 */
- (void)splitView:(NTNSplitView *)splitView didStartOrStopAnimation:(BOOL)animating;

/** Sent when a divider is moved via user drag. You don't receive this message when animating divider position or set it programmatically
 @param splitView	  target NTNSplitView instance
 @param dividerIndex    index of the divider
 @param newPosition	the new divider position
 */
- (void)splitView:(NTNSplitView *)splitView dividerAtIndex:(NSInteger)index movedTo:(CGFloat)newPosition;

/** A subview previously expanded is now collapsed or viceversa
 @param splitView	  target MKSplitView instance
 @param subviewIndex    index of target subview
 @param newState		YES if expanded, NO if collapsed
 */
- (void)splitView:(NTNSplitView *)splitView subviewAtIndex:(NSUInteger)index didExpand:(BOOL)newState;
@end

extern CGFloat NTNSplitViewToolbarButtonTextInset;
extern CGFloat NTNSplitViewToolbarButtonImageInset;
extern CGFloat NTNSplitViewToolbarButtonImageToTextDistance;

/** NTNSplitView is a revisited version of the standard OSX's NSSplitView control.
 The e problem with NSSplitView is that some things which should be simple require implementing unintuitive delegate methods, which gets to be pretty annoying.
 NTNSplitView offer a powerful control over some important settings of NSSplitView such like:
 
 - subview's size and constraint (Specificy uniform, proportional, or priority-based resizing, min/max sizes for subviews)
 - dividers positions
 - collapsible subviews (specify whether a subview can collapse)
 - animatable transitions (both on dividers and subview's sizes)
 - control over divider thickness and style
 - save/restore state of dividers (using standard's OS X autosave feature)
 
 Special thanks:
 
 - CocoaWithLove blog for it's work on priority based NSSplitView implementation (http://www.cocoawithlove.com/2009/09/nssplitview-delegate-for-priority-based.html)
 - Seth Willits for it's AGNSSplitView implementation (https://github.com/swillits/AGNSSplitView).
 
 */
@interface NTNSplitView : NSSplitView <NSSplitViewDelegate> {
}

/** @name Behavior properties */
#pragma mark Behavior Properties

/* the new delegate of DMSplitView. *Do not set splitview's standard delegate* */
@property(nonatomic, weak) IBOutlet id <NTNSplitViewDelegate> eventsDelegate;

- (void)setDelegate:(id <NSSplitViewDelegate>)delegate NS_UNAVAILABLE;

#pragma  mark - Toolbar management

- (void)addToolbar:(NTNSplitViewToolbar *)theToolbar besidesSubviewAtIndex:(NSUInteger)theSubviewIndex onEdge:(NTNSplitViewToolbarEdge)theEdge;

@property(nonatomic, getter = toolbarIsVisible) BOOL toolbarVisible;

- (void)setToolbarVisible:(BOOL)visible animated:(BOOL)animated;

- (void)toggleToolbarVisibileAnimated:(BOOL)animated;

#pragma mark - NSSplitView appearance

/** set divider thickness value */
@property(nonatomic) CGFloat dividerThickness;
/** should draw splitview divider. NO to use default NSSplitView behavior */
@property(nonatomic) BOOL shouldDrawDivider;
/** set divider's color */
@property(nonatomic, strong) NSColor *dividerColor;
/** set divider draw rect edge */
@property(nonatomic) NSRectEdge dividerRectEdge;
/** should draw divider handle */
@property(nonatomic) BOOL shouldDrawDividerHandle;

#pragma mark - Working with priorities
/** @name Priorities */

/** Set prirority of subview at index. Priority-based resizing nominates 1 view as the most important. This is normally the window's "main" view. This highest priority view is the only view that grows in size as the window grows.
 @param	 priority		priority value
 @param	 subviewIndex    target subview index
 */
- (void)setPriority:(NSInteger)priorityIndex ofSubviewAtIndex:(NSInteger)subviewIndex;

#pragma mark - Working with constraints
/** @name Working with constraints*/

/** Set the max position of the divider for subview at given index
 @param  maxSize			max subview size (position of the divider)
 @param  subviewIndex		index of subview
 */
- (void)setMaxSize:(CGFloat)maxSize ofSubviewAtIndex:(NSUInteger)subviewIndex;

/** Set the min position of the divider for subview at given index
 @param  minSize			min subview size (position of the divider)
 @param  subviewIndex		index of subview
 */
- (void)setMinSize:(CGFloat)minSize ofSubviewAtIndex:(NSUInteger)subviewIndex;

/** Return the min position of the divider for subview at given index
 @param  subviewIndex		max subview size (position of the divider)
 @return				 min size of given subview
 */
- (CGFloat)minSizeForSubviewAtIndex:(NSUInteger)subviewIndex;

/** Return the max position of the divider for subview at given index
 @param  subviewIndex		max subview size (position of the divider)
 @return				 max size of given subview
 */
- (CGFloat)maxSizeForSubviewAtIndex:(NSUInteger)subviewIndex;

#pragma mark - Collapse Subviews
/** @name Collapse subview */

/** Allows a subview to be collapsable via divider drag
 @param  canCollapse	YES to enable collapse feature for given subview
 @param  subviewIndex    target subview index
 */
- (void)setCanCollapse:(BOOL)canCollapse subviewAtIndex:(NSUInteger)subviewIndex;

/** Allows a subview to be collapsable by double cliking on divider
 @param  canCollapse	YES to enable collapse feature for given subview
 @param  subviewIndex    target subview index
 */
- (void)setCollapseSubviewAtIndex:(NSUInteger)viewIndex forDoubleClickOnDividerAtIndex:(NSUInteger)dividerIndex;

/** Return YES if subview at index can be collapsed
 @param  canCollapse	YES to enable collapse feature for given subview
 @return			  YES if subview is collapsable
 */
- (BOOL)canCollapseSubviewAtIndex:(NSUInteger)subviewIndex;

/** Collapse or expand subview at given index
 @param	subviewIndex		index of subview to toggle
 @param	animated			use animated transitions
 */
- (void)toggleSubviewAtIndex:(NSUInteger)subviewIndex animated:(BOOL)animated;

/** Collapse or expand given subview
 @param	subviewIndex		target subview
 @param	animated		  use animated transitions
 @return					 YES if new subview state is collapsed
 @warning					only
 */
- (void)toggleSubview:(NSView *)subview animated:(BOOL)animated;

#pragma mark - Set divider position
/** @name Set divider position */

/** Set the new position of a divider at index.
 @param  position			the new divider position
 @param  dividerIndex		target divider index in this split view
 @param	 animated			use animated transitions?
 @param  completion			completion block handler
 @return					YES if you can animate your transitions
 */
- (void)setPosition:(CGFloat)position ofDividerAtIndex:(NSUInteger)dividerIndex animated:(BOOL)animated
  completitionBlock:(void (^)(BOOL isEnded))completion;

/** Set more than one divider position at the same time
 @param  positionsByIndexes	a dictionary of positions with divider positions
 as keys
 @param  dividerIndexes		divider indexes array (set of NSNumber)
 @param	 animated			YES to animate
 @param  completion			completion block handler
 @return					YES if you can animate your transitions
 */
- (void)setPositionsOfDividersAtIndexes:(NSDictionary *)positionsByIndexes animated:(BOOL)animated
					  completitionBlock:(void (^)(BOOL isEnded))completition;

/** Set the new position of a divider at index.
 @param  position			the new divider position
 @param  dividerIndex		 target divider index in this splitview
 @return					 target divider position
 */
- (CGFloat)positionOfDividerAtIndex:(NSUInteger)dividerIndex;

#pragma mark - Working with subviews' sizes
/** @name Working with subviews' sizes */

/** Set the new size of given subview at index. A proportional shrink/grow is applied to involved dividers (left/right, left or right)
 @param	size				the new size of target subview
 @param	subviewIndex		  index of target subview
 @param	animated				YES to animate
 @param	completition		  completition block handler
 */
- (void)setSize:(CGFloat)size ofSubviewAtIndex:(NSUInteger)subviewIndex animated:(BOOL)animated
   completition:(void (^)(BOOL isEnded))completition;

@end
