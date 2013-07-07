//
//  LabelObject.m
//  Notation
//
//  Created by Zachary Schneirov on 12/30/05.

/*Copyright (c) 2010, Zachary Schneirov. All rights reserved.
  Redistribution and use in source and binary forms, with or without modification, are permitted 
  provided that the following conditions are met:
   - Redistributions of source code must retain the above copyright notice, this list of conditions 
     and the following disclaimer.
   - Redistributions in binary form must reproduce the above copyright notice, this list of 
	 conditions and the following disclaimer in the documentation and/or other materials provided with
     the distribution.
   - Neither the name of Notational Velocity nor the names of its contributors may be used to endorse 
     or promote products derived from this software without specific prior written permission. */


//this class performs record-keeping of label-note relationships

#import "LabelObject.h"
#import "NoteObject.h"

@implementation LabelObject

@synthesize title = labelName;

- (id)initWithTitle:(NSString*)name {
    if ((self = [super init])) {
		labelName = name;
		lowercaseName = [name lowercaseString];
	
		lowercaseHash = [lowercaseName hash];
		
		notes = [[NSMutableSet alloc] init];
    }
    
    return self;
}

- (NSString*)associativeIdentifier {
    return lowercaseName;
}


- (void)setTitle:(NSString*)title {
    labelName = [title copy];
    
    lowercaseName = [[title lowercaseString] copy];
    
    lowercaseHash = [lowercaseName hash];
}

- (void)addNote:(NoteObject*)note {
    [notes addObject:note];
}
- (void)removeNote:(NoteObject*)note {
    [notes removeObject:note];
}

- (void)addNoteSet:(NSSet*)noteSet {
	[notes unionSet:noteSet];
}

- (void)removeNoteSet:(NSSet*)noteSet {
	[notes minusSet:noteSet];
}

- (NSSet*)noteSet {
    return notes;
}

- (NSString*)description {
	return [labelName stringByAppendingFormat:@" (used by %@)", notes];
}

- (BOOL)isEqual:(id)anObject {
    return [lowercaseName isEqualToString:[anObject associativeIdentifier]];
}
- (NSUInteger)hash {
    return lowercaseHash;
}


@end
