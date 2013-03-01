//
//  NTNMainWindowController.h
//  Notation
//
//  Created by Zachary Waldowski on 2/22/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

@class NTNDualTextField;
@class NTNSplitView;
@class NTNEditorStatusView;

@interface NTNMainWindowController : NSWindowController

@property (nonatomic, strong) IBOutlet NSToolbar *toolbar;
@property (nonatomic, strong) IBOutlet NSBox *dualFieldWrapper;
@property (nonatomic, strong) IBOutlet NTNDualTextField *dualField;

@property (nonatomic, strong) IBOutlet NTNSplitView *splitView;

- (IBAction)focusOnSearchField:(id)sender;

@property (nonatomic, strong) IBOutlet NTNEditorStatusView *editorStatusView;

@end
