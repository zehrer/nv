//
//  NTNEditorView.h
//  Notation
//
//  Created by Zachary Waldowski on 3/3/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

@class NTNNotesListTableView;
@class NTNDualTextField;

@interface NTNEditorView : NSTextView

@property (nonatomic, weak) IBOutlet NTNNotesListTableView *notesListTableView;
@property (nonatomic, weak) IBOutlet NTNDualTextField *dualField;

@end
