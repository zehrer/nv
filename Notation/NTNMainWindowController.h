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
@class NTNEditorView;

@interface NTNMainWindowController : NSWindowController

@property (nonatomic, weak) IBOutlet NSToolbar *toolbar;
@property (nonatomic, weak) IBOutlet NTNDualTextField *dualField;

@property (nonatomic, weak) IBOutlet NTNSplitView *splitView;

@property (nonatomic, weak) IBOutlet RBLScrollView *notesListScrollView;
@property (nonatomic, weak) IBOutlet NSTableView *notesListTableView;

@property (nonatomic, weak) IBOutlet RBLScrollView *editorScrollView;
@property (nonatomic, unsafe_unretained) IBOutlet NTNEditorView *editorView;
@property (nonatomic, weak) IBOutlet NTNEditorStatusView *editorStatusView;

- (IBAction)focusOnSearchField:(id)sender;

@end
