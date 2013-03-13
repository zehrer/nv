//
//  NTNNoteCellView.h
//  Notation
//
//  Created by Zachary Waldowski on 3/13/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

@class NoteObject;

@interface NTNNoteCellView : NSTableCellView

@property (nonatomic, readonly) NoteObject *note;

@end
