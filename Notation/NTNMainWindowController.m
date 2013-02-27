//
//  NTNMainWindowController.m
//  Notation
//
//  Created by Zachary Waldowski on 2/22/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import "NTNMainWindowController.h"
#import "NTNSplitView.h"

@interface NTNMainWindowController () <NSWindowDelegate, NSToolbarDelegate, NSTextFieldDelegate, NTNSplitViewDelegate>

@end

@implementation NTNMainWindowController

- (id)init {
	return [self initWithWindowNibName: NSStringFromClass([self class])];
}

- (id)initWithWindow:(NSWindow *)window
{
    self = [super initWithWindow:window];
    if (self) {
        // Initialization code here.
    }
    
    return self;
}

- (void)awakeFromNib {
	[super awakeFromNib];
	
	[self.splitView setAutosaveName: @"nvALTMainSplitView"];
    [self.splitView setMinSize:100 ofSubviewAtIndex:0];
	[self.splitView setMinSize:200 ofSubviewAtIndex:1];
	[self.splitView setMaxSize:600 ofSubviewAtIndex:0];
	[self.splitView setCanCollapse:YES subviewAtIndex:0];
	[self.splitView setDividerThickness: 9.75];
}

- (void)windowDidLoad
{
    [super windowDidLoad];
    
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
}

#pragma mark - NSWindowDelegate

#pragma mark - NSToolbarDelegate

#pragma mark - NSTextFieldDelegate

#pragma mark - NTNSplitViewDelegate

@end
