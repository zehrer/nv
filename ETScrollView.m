//
//  ETScrollView.m
//  Notation
//
//  Created by elasticthreads on 3/14/11.
//

#import "ETScrollView.h"
#import "ETTransparentScroller.h"
#import "ETOverlayScroller.h"
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
    needsOverlayTiling=NO;
    BOOL fillIt=NO;
    if([[[self documentView]className] isEqualToString:@"NotesTableView"]){
        scrollerClass=NSClassFromString(@"ETOverlayScroller");
    }else{
        scrollerClass=NSClassFromString(@"ETTransparentScroller");
    }
	
	[[GlobalPrefs defaultPrefs] registerForSettingChange:@selector(setUseETScrollbarsOnLion:sender:) withTarget:self];
	[self setHorizontalScrollElasticity:NSScrollElasticityNone];
	[self setVerticalScrollElasticity:NSScrollElasticityAllowed];
	
    if ([[GlobalPrefs defaultPrefs]useETScrollbarsOnLion]) {
		id theScroller=[[scrollerClass alloc]init];
        [theScroller setFillBackground:fillIt];
        [self setVerticalScroller:theScroller];
        [theScroller release];
    }
}


- (void)settingChangedForSelectorString:(NSString*)selectorString{
    if ([selectorString isEqualToString:SEL_STR(setUseETScrollbarsOnLion:sender:)]) {
        [self changeUseETScrollbarsOnLion];
    }
}

- (void)changeUseETScrollbarsOnLion{
    NSScrollerStyle style=[self scrollerStyle];
    id theScroller;
    if ([[GlobalPrefs defaultPrefs]useETScrollbarsOnLion]) {
        theScroller=[[scrollerClass alloc]init];
    }else{
        theScroller=[[NSScroller alloc]init];
        if (style==NSScrollerStyleLegacy) {
            style=[NSScroller preferredScrollerStyle];
        }
    }
    [theScroller setScrollerStyle:style];
    [self setVerticalScroller:theScroller];
    [theScroller release];
    [self setScrollerStyle:style];
    [self tile];
    [self reflectScrolledClipView:[self contentView]];
}

- (void)tile {
	[super tile];
    if (needsOverlayTiling) {
        if (![[self verticalScroller] isHidden]) {
            //            NSRect vsRect=[[self verticalScroller] frame];
            NSRect conRect = [[self contentView] frame];
            //            NSView *wdContent = [[self contentView] retain];
            conRect.size.width = conRect.size.width + [[self verticalScroller] frame].size.width;
            [[self contentView] setFrameSize:conRect.size];
            //            [wdContent setFrame:conRect];
            //            [wdContent release];
            //            [[self verticalScroller] setFrame:vsRect];            
        }
    }
}


@end
