//
//  NTNEditorStatusView.h
//  Notation
//
//  Created by Zachary Waldowski on 3/1/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

@interface NTNEditorStatusViewCell : NSTextFieldCell

@end

@interface NTNEditorStatusView : RBLView

@property (nonatomic, weak) IBOutlet NSTextField *label;
@property (nonatomic) NSInteger notesNumber;
@property (nonatomic) NSInteger lastNotesNumber;

@end
