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

@interface LabelObject ()

@property (nonatomic, copy) NSString *lowercaseTitle;
@property (nonatomic, strong) NSMutableSet *notes;

@end

@implementation LabelObject

- (id)initWithTitle:(NSString *)name {
	if ((self = [super init])) {
		self.title = name;
		self.lowercaseTitle = self.title.lowercaseString;
		self.notes = [NSMutableSet set];
	}
	return self;
}

- (void)setTitle:(NSString *)title {
	_title = [title copy];
	self.lowercaseTitle = [title lowercaseString];
}

- (void)addNote:(NoteObject *)note {
	[self.notes addObject:note];
}

- (void)removeNote:(NoteObject *)note {
	[self.notes removeObject:note];
}

- (void)addNoteSet:(NSSet *)noteSet {
	[self.notes unionSet:noteSet];
}

- (void)removeNoteSet:(NSSet *)noteSet {
	[self.notes minusSet:noteSet];
}

- (NSSet *)noteSet {
	return [self.notes copy];
}

- (NSString *)description {
	return [self.title stringByAppendingFormat:@" (used by %@)", self.notes];
}

- (BOOL)isEqual:(id)anObject {
	return [self.lowercaseTitle isEqualToString:[anObject lowercaseTitle]];
}

- (NSUInteger)hash {
	return self.lowercaseTitle.hash;
}

@end
