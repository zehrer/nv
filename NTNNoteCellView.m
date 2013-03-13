//
//  NTNNoteCellView.m
//  Notation
//
//  Created by Zachary Waldowski on 3/13/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import "NTNNoteCellView.h"

@implementation NTNNoteCellView

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code here.
    }
    
    return self;
}

- (void)drawRect:(NSRect)dirtyRect
{
    // Drawing code here.
}

- (NoteObject *)note {
	return self.objectValue;
}

@end
