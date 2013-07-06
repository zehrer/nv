//
//  NotesTableHeaderCell.m
//  Notation
//
//  Created by elasticthreads on 10/19/10.
//

#import "NotesTableHeaderCell.h"
#import <objc/runtime.h>

@implementation NotesTableHeaderCell {
	NSGradient *_gradient;
}

- (id)initTextCell:(NSString *)text
{
    if ((self = [super initTextCell:text])) {
		@try {
			_gradient = [[[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedWhite:0.93f alpha:0.3f] endingColor:[NSColor colorWithCalibratedWhite:0.12f alpha:0.25f]] retain];
		}
		@catch (NSException * e) {
			NSLog(@"init colors EXCEPT: %@",[e description]);
		}
		@finally {			
			if (text == nil || [text isEqualToString:@""]) {
				[self setTitle:@"Title"]; 
			}
			attrs = [[NSMutableDictionary dictionaryWithDictionary:
					  [[self attributedStringValue] 
					   attributesAtIndex:0 
					   effectiveRange:NULL]] 
					 mutableCopy];
			//NSLog(@"done initing");
			return self;
		}
    }
    return nil;
}

- (void)setBackgroundColor:(NSColor *)color
{
	CGFloat fWhite;
	CGFloat endWhite;
	CGFloat fAlpha;
	NSColor	*gBack = [color colorUsingColorSpaceName:NSCalibratedWhiteColorSpace];
	[gBack getWhite:&fWhite alpha:&fAlpha];
	if (fWhite<0.5f) {
		endWhite = fWhite + .4f;
	}else {
		endWhite = fWhite - .27f;
	}
	self.highlightColor = [color blendedColorWithFraction:0.60f ofColor:[NSColor colorWithCalibratedWhite:endWhite alpha:0.98f]];
	[super setBackgroundColor:color];
}

- (NSRect)drawingRectForBounds:(NSRect)theRect {
	return NSInsetRect(theRect, 6.0f, 0.0);
}

- (void)drawWithFrame:(NSRect)inFrame inView:(NSView*)inView
{
	NSColor *bColor = self.backgroundColor, *tColor = self.textColor;
	
	[bColor setFill];
	NSRectFill(inFrame);
	[_gradient drawInRect:inFrame angle:90];

	[tColor set];
		 NSBezierPath* thePath = [NSBezierPath bezierPath];
		 [thePath removeAllPoints];	
		[thePath moveToPoint:NSMakePoint((inFrame.origin.x + inFrame.size.width),(inFrame.origin.y +  inFrame.size.height))];
		[thePath lineToPoint:NSMakePoint(inFrame.origin.x,(inFrame.origin.y +  inFrame.size.height))];	
		if (inFrame.origin.x>5) {
			[thePath lineToPoint:inFrame.origin];
		}
		
//			[thePath moveToPoint:NSMakePoint((inFrame.origin.x + inFrame.size.width),inFrame.origin.y)];
//			[thePath lineToPoint:NSMakePoint(inFrame.origin.x,inFrame.origin.y)];
		
		[thePath setLineWidth:1.4];
		 [thePath stroke];
	float offset = 5;  
	NSRect centeredRect = inFrame;
	centeredRect.size = [[self stringValue] sizeWithAttributes:attrs];
	//centeredRect.origin.x += ((inFrame.size.width - centeredRect.size.width) / 2.0); //- offset;
	centeredRect.origin.x += offset;
	centeredRect.origin.y = ((inFrame.size.height - centeredRect.size.height) / 2.0);
	// centeredRect.origin.y += offset/2;

	[attrs setValue:tColor forKey:@"NSColor"];
	[[self stringValue] drawInRect:centeredRect withAttributes:attrs];
	
}

- (void)drawSortIndicatorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView ascending:(BOOL)ascending priority:(NSInteger)priority {}

- (void)highlight:(BOOL)hBool withFrame:(NSRect)inFrame inView:(NSView *)controlView{
	NSColor *bColor = self.backgroundColor,
	*tColor = self.textColor,
	*hColor = self.highlightColor;
	
	if (hBool) {
		[hColor setFill];
		
		NSRectFill(inFrame);
		
		[_gradient drawInRect:inFrame angle:90];
		[tColor setStroke];
		NSBezierPath* thePath = [NSBezierPath bezierPath];
		[thePath removeAllPoints];
		[thePath moveToPoint:NSMakePoint((inFrame.origin.x + inFrame.size.width),(inFrame.origin.y +  inFrame.size.height))];
		[thePath lineToPoint:NSMakePoint(inFrame.origin.x,(inFrame.origin.y +  inFrame.size.height))];	
		if (inFrame.origin.x>5) {
			[thePath lineToPoint:inFrame.origin];
		}
//		[thePath moveToPoint:NSMakePoint((inFrame.origin.x + inFrame.size.width),inFrame.origin.y)];
//		[thePath lineToPoint:NSMakePoint(inFrame.origin.x,inFrame.origin.y)];
//		[thePath setLineWidth:2.0]; // Has no effect.
		[thePath setLineWidth:1.4];
		[thePath stroke];
		
		float offset = 5;
		[attrs setValue:bColor forKey:@"NSColor"];    
		NSRect centeredRect = inFrame;
		centeredRect.size = [[self stringValue] sizeWithAttributes:attrs]; 
		centeredRect.origin.x += offset;
		centeredRect.origin.y = ((inFrame.size.height - centeredRect.size.height) / 2.0); 			
		[attrs setValue:tColor forKey:@"NSColor"];
		[[self stringValue] drawInRect:centeredRect withAttributes:attrs];				
	}		
}


- (id)copyWithZone:(NSZone *)zone
{
    id newCopy = [super copyWithZone:zone];
    [attrs retain];
    return newCopy;
}

@end
