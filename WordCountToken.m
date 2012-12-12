//
//  WordCountToken.m
//  Notation
//
//  Created by ElasticThreads on 3/1/11.
//

#import "WordCountToken.h"
#import "AppController.h"
//#import <QuartzCore/QuartzCore.h>

@implementation WordCountToken

- (id)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
    }
    return self;
}

- (void)awakeFromNib{
	[self refusesFirstResponder];
	//theGrad =  [[[NSGradient alloc] initWithStartingColor:[NSColor colorWithCalibratedWhite:0.2f alpha:0.28f] endingColor:[NSColor colorWithCalibratedWhite:0.74f alpha:0.18f]] retain];
	
	//[self setTxtColor:[[NSApp delegate] foregrndColor]];
	//[self setFldColor:[[NSApp delegate] backgrndColor]];
	
}

- (void)mouseDown:(NSEvent *)theEvent{
	[[NSApp delegate] toggleWordCount:self];
}

@end
