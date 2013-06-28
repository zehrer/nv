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
}

- (void)mouseDown:(NSEvent *)theEvent{
	[[NSApp delegate] toggleWordCount:self];
}

@end
