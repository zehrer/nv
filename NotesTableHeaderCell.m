//
//  NotesTableHeaderCell.m
//  Notation
//
//  Created by David Halter on 6/12/13.
//  Copyright (c) 2013 David Halter. All rights reserved.
//

#import "NotesTableHeaderCell.h"

@interface NotesTableHeaderCell ()

@property (nonatomic, strong) NSGradient *gradient;

@end

@implementation NotesTableHeaderCell

- (id)initTextCell:(NSString *)text{
    if ((self = [super initTextCell:text])) {
        if (!text || !text.length) {
            [self setTitle:@"Title"];
        }
		
		[self setBackgroundColor:[[NSColor whiteColor] colorUsingColorSpaceName:NSCalibratedRGBColorSpace]];
		[self setTextColor:[[NSColor blackColor] colorUsingColorSpaceName:NSCalibratedRGBColorSpace]];
    }
    return self;
}

- (BOOL)isOpaque{
    return YES;
}

- (NSRect)drawingRectForBounds:(NSRect)theRect {
	return NSIntegralRect(NSInsetRect(theRect, 6.0f, 0.0f));
}

- (NSRect)sortIndicatorRectForBounds:(NSRect)theRect{
    theRect=[super sortIndicatorRectForBounds:theRect];
    theRect.origin.y= floorf(theRect.origin.y-0.5f);
    return NSIntegralRect(theRect);
}

- (void)drawSortIndicatorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView ascending:(BOOL)ascending priority:(NSInteger)priority{ }

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView{
    cellFrame=NSInsetRect(cellFrame, 0.0f, 1.0f);
    cellFrame.size.height-=1.0f;
    [super drawInteriorWithFrame:cellFrame inView:controlView];
}

- (void)drawWithFrame:(NSRect)inFrame inView:(NSView*)inView{
    [self.gradient drawInRect:inFrame angle:90.0f];
    [self drawBorderWithFrame:inFrame];
    [self drawInteriorWithFrame:inFrame inView:inView];
}

- (void)highlight:(BOOL)hBool withFrame:(NSRect)inFrame inView:(NSView *)controlView{
    NSColor *theBack;
    if ([[self.backgroundColor colorUsingColorSpaceName:NSCalibratedWhiteColorSpace] whiteComponent]<0.5f) {
        theBack=[self.backgroundColor highlightWithLevel:0.24f];
        [self setTextColor:[self.textColor highlightWithLevel:0.3f]];
	}else {
        theBack=[self.backgroundColor shadowWithLevel:0.24f];
        [self setTextColor:[self.textColor shadowWithLevel:0.3f]];
	}
    [[self gradientFromBaseColor:theBack] drawInRect:inFrame angle:90.0f];
    [self drawBorderWithFrame:inFrame];
    [self drawInteriorWithFrame:inFrame inView:controlView];
}

#pragma mark - nvALT additions

- (void)drawBorderWithFrame:(NSRect)cellFrame{
    NSBezierPath* thePath = [NSBezierPath bezierPath];
    [thePath removeAllPoints];
    [thePath moveToPoint:NSMakePoint((cellFrame.origin.x + cellFrame.size.width),(cellFrame.origin.y +  cellFrame.size.height))];
    [thePath lineToPoint:NSMakePoint(cellFrame.origin.x,(cellFrame.origin.y +  cellFrame.size.height))];
    if (cellFrame.origin.x>5.0f) {
        [thePath lineToPoint:cellFrame.origin];
    }
    
    [self.textColor setStroke];
    [thePath setLineWidth:1.3];
    [thePath stroke];
}

- (NSGradient *)gradientFromBaseColor:(NSColor *)baseColor
{
	baseColor = [baseColor colorUsingColorSpaceName:NSCalibratedRGBColorSpace];//[bColor
    NSColor *startColor = [baseColor blendedColorWithFraction:0.3f ofColor:[[NSColor colorWithCalibratedWhite:0.9f alpha:1.0f] colorUsingColorSpaceName:NSCalibratedRGBColorSpace]];
    
    NSColor *endColor = [baseColor blendedColorWithFraction:0.52f ofColor:[[NSColor colorWithCalibratedWhite:0.1f alpha:1.0f] colorUsingColorSpaceName:NSCalibratedRGBColorSpace]];
	
    return [[NSGradient alloc] initWithColorsAndLocations: startColor, 0.11f, endColor, 0.94f, nil];
}

- (NSGradient *)gradient
{
	if (!_gradient) {
		self.gradient = [self gradientFromBaseColor:self.backgroundColor];
	}
	return _gradient;
}

- (void)setBackgroundColor:(NSColor *)color
{
	[super setBackgroundColor:[color colorUsingColorSpaceName:NSCalibratedRGBColorSpace]];
	self.gradient = nil;
}

- (void)setTextColor:(NSColor *)color
{
	[super setTextColor:[color colorUsingColorSpaceName:NSCalibratedRGBColorSpace]];
}

@end
