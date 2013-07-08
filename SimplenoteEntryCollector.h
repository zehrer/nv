//
//  SimplenoteEntryCollector.h
//  Notation
//
//  Created by Zachary Schneirov on 12/4/09.

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


#import <Cocoa/Cocoa.h>

#import "SyncServiceSessionProtocol.h"

@class NoteObject;
@class DeletedNoteObject;
@class SyncResponseFetcher;

@interface SimplenoteEntryCollector : NSObject <SyncServiceTask> {
	NSArray *entriesToCollect;
	NSMutableArray *entriesCollected, *entriesInError;
	NSUInteger entryFinishedCount;
	NSString *simperiumToken;
	BOOL stopped;
	SyncResponseFetcher *currentFetcher;
	
	id representedObject;
}

- (id)initWithEntriesToCollect:(NSArray*)wantedEntries simperiumToken:(NSString*)aSimperiumToken;

- (NSArray*)entriesToCollect;
- (NSArray*)entriesCollected;
- (NSArray*)entriesInError;

- (void)stop;
- (BOOL)collectionStarted;

- (BOOL)collectionStoppedPrematurely;

- (NSString*)localizedActionDescription;

- (void)startCollectingWithCompletion:(void(^)(SimplenoteEntryCollector *))block;

- (SyncResponseFetcher*)fetcherForEntry:(id)anEntry;

- (NSDictionary*)preparedDictionaryWithFetcher:(SyncResponseFetcher*)fetcher receivedData:(NSData*)data;

- (void)setRepresentedObject:(id)anObject;
- (id)representedObject;

@end

typedef NS_ENUM(NSInteger, SimplenoteEntryModifierMode) {
	SimplenoteEntryModifierModeCreating,
	SimplenoteEntryModifierModeUpdating,
	SimplenoteEntryModifierModeDeleting
};

@interface SimplenoteEntryModifier : SimplenoteEntryCollector

@property (nonatomic, readonly) SimplenoteEntryModifierMode mode;

- (id)initWithEntries:(NSArray*)wantedEntries operation:(SimplenoteEntryModifierMode)mode simperiumToken:(NSString*)aSimperiumToken;

- (void)startCollectingWithCompletion:(void(^)(SimplenoteEntryModifier *))block;

@end
