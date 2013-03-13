//
//  NTNMainWindowController.h
//  Notation
//
//  Created by Zachary Waldowski on 2/22/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

extern NSString *const NTNTextFindContextDidChangeNotification;
extern NSString *const NTNTextEditorDidChangeContentsNotification;

@class NTNDualTextField;
@class NTNSplitView;
@class NTNEditorStatusView;
@class NTNEditorView;
@class NotationController;
@class GlobalPrefs;

@interface NTNMainWindowController : NSWindowController

@property (nonatomic, weak) IBOutlet NSToolbar *toolbar;
@property (nonatomic, weak) IBOutlet NTNDualTextField *dualField;

@property (nonatomic, weak) IBOutlet NTNSplitView *splitView;

@property (nonatomic, weak) IBOutlet RBLScrollView *notesListScrollView;
@property (nonatomic, weak) IBOutlet NSTableView *notesListTableView;
@property (nonatomic, strong) IBOutlet NSArrayController *notesListController;
@property (nonatomic, weak) IBOutlet NTNEditorStatusView *notesListStatusView;

@property (nonatomic, weak) IBOutlet RBLScrollView *editorScrollView;
@property (nonatomic, unsafe_unretained) IBOutlet NTNEditorView *editorView;
@property (nonatomic, weak) IBOutlet NTNEditorStatusView *editorStatusView;

@property (nonatomic, strong) IBOutlet NotationController *notationController;

@property (nonatomic, readonly) GlobalPrefs *prefs;

@property (nonatomic, readonly) NSFont *tableTitleFont;
@property (nonatomic, readonly) NSFont *tableFont;

- (IBAction)focusOnSearchField:(id)sender;

@end
