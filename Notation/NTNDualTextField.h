//
//  NTNDualTextField.h
//  Notation
//
//  Created by Zachary Waldowski on 2/23/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface NTNDualTextFieldCell : NSSearchFieldCell

@end

@interface NTNDualTextField : NSSearchField

@property (nonatomic, strong) IBOutlet NSTableView *notesListTableView;

@end
