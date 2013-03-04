//
//  NTNNotesListTableView.h
//  Notation
//
//  Created by Zachary Waldowski on 2/27/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

@class NTNEditorView;
@class NTNDualTextField;

@interface NTNNotesListTableView : NSTableView

@property (nonatomic, unsafe_unretained) IBOutlet NTNEditorView *editorView;
@property (nonatomic, weak) IBOutlet NTNDualTextField *dualField;

@end
