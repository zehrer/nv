//
//  StatusItemView.m
//  Notation
//
//  Created by elasticthreads on 07/03/2010.
//  Copyright 2010 elasticthreads. All rights reserved.
//

#import "StatusItemView.h"
#import "AppController.h"

@interface StatusItemView () {
	NSImage *_menuDarkImage;
	NSImage *_menuClickedImage;
}

@property (weak, nonatomic, readonly) NSImage *menuDarkImage;
@property (weak, nonatomic, readonly) NSImage *menuClickedImage;

@end

@implementation StatusItemView


- (id)initWithFrame:(NSRect)frame controller:(AppController *)ctrlr
{
    if ((self = [super initWithFrame:frame])) {
        controller = ctrlr; // deliberately weak reference.
    }    
    return self;
}


- (void)dealloc
{
    controller = nil;
}

- (NSImage *)menuClickedImage {
	if (!_menuClickedImage) {
		NSBundle *bundle = [NSBundle bundleForClass:[self class]];
		NSString *path = [bundle pathForResource: @"nvMenuC" ofType:@"png"];
		_menuClickedImage = [[NSImage alloc] initWithContentsOfFile: path];
	}
	return _menuClickedImage;
}

- (NSImage *)menuDarkImage {
	if (!_menuDarkImage) {
		NSBundle *bundle = [NSBundle bundleForClass:[self class]];
		NSString *path = [bundle pathForResource: @"nvMenuDark" ofType:@"png"];
		_menuDarkImage = [[NSImage alloc] initWithContentsOfFile: path];
	}
	return _menuDarkImage;
}

- (void)drawRect:(NSRect)rect {
	NSImage *menuIcon = nil;
	if (clicked) {
        menuIcon = self.menuClickedImage;
        [[NSColor selectedMenuItemColor] set];
		NSRectFill(rect);
    }else {
        menuIcon = self.menuDarkImage;
		[[NSColor clearColor] set];
        NSRectFill(rect);
	}
	NSSize msgSize = [menuIcon size];
    NSRect msgRect = NSMakeRect(0, 0, msgSize.width, msgSize.height);
    msgRect.origin.x = ([self frame].size.width - msgSize.width)/2;
    msgRect.origin.y = ([self frame].size.height - msgSize.height)/2;
	[menuIcon drawInRect:msgRect fromRect:NSZeroRect operation: NSCompositeSourceOver fraction:1.0];
}

- (void)mouseDown:(NSEvent *)event
{
//    [controller resetModTimers];
//    [[NSNotificationCenter defaultCenter] postNotificationName:@"ModTimersShouldReset" object:nil];
	clicked = YES;
	[self setNeedsDisplay:YES];
    NSUInteger modFlags=[event modifierFlags];
    if ((modFlags&NSControlKeyMask)&&!((modFlags&NSCommandKeyMask)||(modFlags&NSAlternateKeyMask)||(modFlags&NSShiftKeyMask))) {
//        NSLog(@"ctrl click");
        [[NSNotificationCenter defaultCenter]postNotificationName:@"StatusItemMenuShouldDrop" object:nil];
        //	[controller toggleAttachedMenu:self];	
        clicked = NO;
        [self setNeedsDisplay:YES];
    }else{
//        NSLog(@"not ctrl click");
        [[NSNotificationCenter defaultCenter]postNotificationName:@"NVShouldActivate" object:self];
    }
//	[controller toggleAttachedWindow:self];
}

- (void)mouseUp:(NSEvent *)event {
    
//    [[NSNotificationCenter defaultCenter] postNotificationName:@"ModTimersShouldReset" object:nil];
	clicked = NO;	
	[self setNeedsDisplay:YES];
	[self viewWillDraw];
}

- (void)rightMouseDown:(NSEvent *)event {
	clicked = YES;
	[self setNeedsDisplay:YES];
     [[NSNotificationCenter defaultCenter]postNotificationName:@"StatusItemMenuShouldDrop" object:nil];
//	[controller toggleAttachedMenu:self];	
    clicked = NO;
    [self setNeedsDisplay:YES];
}

- (void)setInactiveIcon:(id)sender{
	[self setNeedsDisplay:YES];
}

- (void)setActiveIcon:(id)sender{
	[self setNeedsDisplay:YES];
}

@end
