//
//  ETScrollView.m
//  Notation
//
//  Created by elasticthreads on 3/14/11.
//

#import "ETScrollView.h"
#import "GlobalPrefs.h"
#import "LinkingEditor.h"

@implementation ETScrollView


- (NSView *)hitTest:(NSPoint)aPoint{
    if([[[self documentView]className] isEqualToString:@"LinkingEditor"]){
        NSRect vsRect=[[self verticalScroller] frame];
        vsRect.origin.x-=4.0;
        vsRect.size.width+=4.0;
        
        if (NSPointInRect (aPoint,vsRect)) {
            return [self verticalScroller];
        } else {
            if([[self subviews]containsObject:[self findBarView]]) {
                NSView *tView=[super hitTest:aPoint];
                if ((tView==[self findBarView])||([tView superview]==[self findBarView])||([[tView className]isEqualToString:@"NSFindPatternFieldEditor"])) {
                    [[self window]invalidateCursorRectsForView:tView];
                    [[self documentView]setMouseInside:NO];
                    return tView;
                }
            }
        }
        [[self documentView]setMouseInside:YES];
        return [self documentView];
    }
    return [super hitTest:aPoint];
}


- (void)awakeFromNib{ 
	[self setHorizontalScrollElasticity:NSScrollElasticityNone];
	[self setVerticalScrollElasticity:NSScrollElasticityAllowed];
}


@end
