//
//  NotesTableHeaderCell.m
//  Notation
//
//  Created by elasticthreads on 10/19/10.
//

#import "NotesTableHeaderCell.h"
#import <objc/runtime.h>

static const void *NotesTableHeaderBackgroundColorKey = &NotesTableHeaderBackgroundColorKey;
static const void *NotesTableHeaderHighlightColorKey = &NotesTableHeaderHighlightColorKey;
static const void *NotesTableHeaderTextColorKey = &NotesTableHeaderTextColorKey;

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

+ (NSColor *)backgroundColor
{
	return objc_getAssociatedObject(self, NotesTableHeaderBackgroundColorKey) ?: [NSColor whiteColor];
}

+ (NSColor *)highlightColor
{
	return objc_getAssociatedObject(self, NotesTableHeaderHighlightColorKey) ?: [NSColor grayColor];
}

+ (void)setBackgroundColor:(NSColor *)inColor{
	objc_setAssociatedObject(self, NotesTableHeaderBackgroundColorKey, inColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

	CGFloat fWhite;
	CGFloat endWhite;
	CGFloat fAlpha;
	NSColor	*gBack = [inColor colorUsingColorSpaceName:NSCalibratedWhiteColorSpace];
	[gBack getWhite:&fWhite alpha:&fAlpha];
	if (fWhite<0.5f) {
		endWhite = fWhite + .4f;
	}else {		
		endWhite = fWhite - .27f;
	}
	
	objc_setAssociatedObject(self, NotesTableHeaderHighlightColorKey, [inColor blendedColorWithFraction:0.60f ofColor:[NSColor colorWithCalibratedWhite:endWhite alpha:0.98f]], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

+ (NSColor *)foregroundColor
{
	return objc_getAssociatedObject(self, NotesTableHeaderTextColorKey) ?: [NSColor blackColor];
}

+ (void)setForegroundColor:(NSColor *)inColor{
	objc_setAssociatedObject(self, NotesTableHeaderTextColorKey, inColor, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSRect)drawingRectForBounds:(NSRect)theRect {
	return NSInsetRect(theRect, 6.0f, 0.0);
}

- (void)drawWithFrame:(NSRect)inFrame inView:(NSView*)inView
{
	NSColor *bColor = [[self class] backgroundColor], *tColor = [[self class] foregroundColor];
	
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

- (void)drawSortIndicatorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView ascending:(BOOL)ascending priority:(NSInteger)priority{
	NSLog(@"draw sort");
}

- (void)highlight:(BOOL)hBool withFrame:(NSRect)inFrame inView:(NSView *)controlView{
	NSColor *bColor = [[self class] backgroundColor],
	*tColor = [[self class] foregroundColor],
	*hColor = [[self class] highlightColor];
	
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
