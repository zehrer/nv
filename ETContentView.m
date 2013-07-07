//
//  ETContentView.m
//  Notation
//
//  Created by elasticthreads on 3/15/11.
//

#import "ETContentView.h"
#import "AppController.h"

@implementation ETContentView

//- (id)initWithFrame:(NSRect)frame
//{
//    self = [super initWithFrame:frame];
//    if (self) {
//        // Initialization code here.
//    }
//    
//    return self;
//}
//


- (void)drawRect:(NSRect)dirtyRect
{
//    [super drawRect:dirtyRect];
    if (!backColor) {
        backColor = [[NSApp delegate] backgrndColor];
    }
    [backColor set];
    NSRectFill([self bounds]);
    
}

- (void)setBackgroundColor:(NSColor *)inCol{
    backColor = inCol;
}

- (NSColor *)backgroundColor{    
    if (!backColor) {
        backColor = [[NSApp delegate] backgrndColor];
    }
    return backColor;
}

@end
