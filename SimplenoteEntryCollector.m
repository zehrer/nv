//
//  SimplenoteEntryCollector.m
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


#import "GlobalPrefs.h"
#import "SimplenoteEntryCollector.h"
#import "SyncResponseFetcher.h"
#import "SimplenoteSession.h"
#import "NSString_NV.h"
#import "NoteObject.h"
#import "DeletedNoteObject.h"
#import <objc/message.h>

@interface SimplenoteEntryCollector () <SyncResponseFetcherDelegate>

@end

@implementation SimplenoteEntryCollector

//instances this short-lived class are intended to be started only once, and then deallocated

- (id)initWithEntriesToCollect:(NSArray *)wantedEntries authToken:(NSString *)anAuthToken email:(NSString *)anEmail {
	if ((self = [super init])) {
		authToken = anAuthToken;
		email = anEmail;
		entriesToCollect = wantedEntries;
		entriesCollected = [[NSMutableArray alloc] init];
		entriesInError = [[NSMutableArray alloc] init];

		if (![email length] || ![authToken length] || ![entriesToCollect count]) {
			NSLog(@"%@: missing parameters", NSStringFromSelector(_cmd));
			return nil;
		}
	}
	return self;
}

- (NSArray *)entriesToCollect {
	return entriesToCollect;
}

- (NSArray *)entriesCollected {
	return entriesCollected;
}

- (NSArray *)entriesInError {
	return entriesInError;
}

- (BOOL)collectionStarted {
	return entryFinishedCount != 0;
}

- (BOOL)collectionStoppedPrematurely {
	return stopped;
}

- (void)setRepresentedObject:(id)anObject {
	representedObject = anObject;
}

- (id)representedObject {
	return representedObject;
}


- (NSString *)statusText {
	return [NSString stringWithFormat:NSLocalizedString(@"Downloading %u of %u notes", @"status text when downloading a note from the remote sync server"),
									  entryFinishedCount, [entriesToCollect count]];
}

- (SyncResponseFetcher *)currentFetcher {
	return currentFetcher;
}

- (NSString *)localizedActionDescription {
	return NSLocalizedString(@"Downloading", nil);
}

- (void)stop {
	stopped = YES;

	//cancel the current fetcher, which will cause it to send its finished callback
	//and the stopped condition will send this class' finished callback
	[currentFetcher cancel];
}

- (SyncResponseFetcher *)fetcherForEntry:(id)entry {

	id <SynchronizedNote> originalNote = nil;
	if ([entry conformsToProtocol:@protocol(SynchronizedNote)]) {
		originalNote = entry;
		entry = [entry syncServicesMD][SimplenoteServiceName];
	}
	NSURL *noteURL = [SimplenoteSession servletURLWithPath:[NSString stringWithFormat:@"/api2/data/%@", entry[@"key"]] parameters:
			@{@"email" : email,
					@"auth" : authToken}];
	SyncResponseFetcher *fetcher = [[SyncResponseFetcher alloc] initWithURL:noteURL POSTData:nil delegate:self];
	//remember the note for later? why not.
	if (originalNote) [fetcher setRepresentedObject:originalNote];
	return fetcher;
}

- (void)startCollectingWithCallback:(SEL)aSEL collectionDelegate:(id)aDelegate {
	NSAssert([aDelegate respondsToSelector:aSEL], @"delegate doesn't respond!");
	NSAssert(![self collectionStarted], @"collection already started!");
	entriesFinishedCallback = aSEL;
	collectionDelegate = aDelegate;


	[(currentFetcher = [self fetcherForEntry:entriesToCollect[entryFinishedCount++]]) start];
}

- (NSDictionary *)preparedDictionaryWithFetcher:(SyncResponseFetcher *)fetcher receivedData:(NSData *)data {
	//logic abstracted for subclassing

	NSDictionary *rawObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];

	if (!rawObject)
		return nil;

	NSMutableDictionary *entry = [NSMutableDictionary dictionaryWithCapacity:12];
	entry[@"key"] = rawObject[@"key"];
	entry[@"deleted"] = @([rawObject[@"deleted"] intValue]);
	// Normalize dates from unix epoch timestamps to mac os x epoch timestamps
	entry[@"create"] = @([[NSDate dateWithTimeIntervalSince1970:[rawObject[@"createdate"] doubleValue]] timeIntervalSinceReferenceDate]);
	entry[@"modify"] = @([[NSDate dateWithTimeIntervalSince1970:[rawObject[@"modifydate"] doubleValue]] timeIntervalSinceReferenceDate]);
	entry[@"syncnum"] = @([rawObject[@"syncnum"] intValue]);
	entry[@"version"] = @([rawObject[@"version"] intValue]);
	entry[@"minversion"] = @([rawObject[@"minversion"] intValue]);
	if (rawObject[@"sharekey"]) {
		entry[@"sharekey"] = rawObject[@"sharekey"];
	}
	if (rawObject[@"publishkey"]) {
		entry[@"publishkey"] = rawObject[@"publishkey"];
	}
	entry[@"systemtags"] = rawObject[@"systemtags"];
	entry[@"tags"] = rawObject[@"tags"];
	if ([[fetcher representedObject] conformsToProtocol:@protocol(SynchronizedNote)]) entry[@"NoteObject"] = [fetcher representedObject];
	entry[@"content"] = rawObject[@"content"];

	//NSLog(@"fetched entry %@" , entry);

	return entry;
}

- (void)syncResponseFetcher:(SyncResponseFetcher *)fetcher receivedData:(NSData *)data returningError:(NSString *)errString {

	if (errString) {
		NSLog(@"collector-%@ returned %@", fetcher, errString);
		id obj = [fetcher representedObject];
		if (obj) {
			[entriesInError addObject:@{@"NoteObject" : obj,
					@"StatusCode" : @([fetcher statusCode])}];
		}
	} else {
		NSDictionary *preparedDictionary = [self preparedDictionaryWithFetcher:fetcher receivedData:data];
		if (!preparedDictionary) {
			// Parsing JSON failed.  Is this the right way to handle the error?
			id obj = [fetcher representedObject];
			if (obj) {
				[entriesInError addObject:@{@"NoteObject" : obj,
						@"StatusCode" : @([fetcher statusCode])}];
			}
		} else {
			[entriesCollected addObject:preparedDictionary];
		}
	}

	if (entryFinishedCount >= [entriesToCollect count] || stopped) {
		//no more entries to collect!
		currentFetcher = nil;
		objc_msgSend(collectionDelegate, entriesFinishedCallback, self);
	} else {
		//queue next entry
		[(currentFetcher = [self fetcherForEntry:entriesToCollect[entryFinishedCount++]]) start];
	}

}

@end

@implementation SimplenoteEntryModifier

//TODO:
//if modification or creation date is 0, set it to the most recent time as parsed from the HTTP response headers
//when updating notes, sync times will be set to 0 when they are older than the time of the last HTTP header date
//which will be stored in notePrefs as part of the simplenote service dict

//all this to prevent syncing mishaps when notes are created and user's clock is set inappropriately

//modification times dates are set in case the app has been out of connectivity for a long time
//and to ensure we know what the time was for the next time we compare dates

- (id)initWithEntries:(NSArray *)wantedEntries operation:(SEL)opSEL authToken:(NSString *)anAuthToken email:(NSString *)anEmail {
	if ((self = [super initWithEntriesToCollect:wantedEntries authToken:anAuthToken email:anEmail])) {
		//set creation and modification date when creating
		//set modification date when updating
		//need to check for success when deleting
		if (![self respondsToSelector:opSEL]) {
			NSLog(@"%@ doesn't respond to %@", self, NSStringFromSelector(_cmd));
			return nil;
		}
		fetcherOpSEL = opSEL;
	}
	return self;
}

- (SyncResponseFetcher *)fetcherForEntry:(id)anEntry {
	return objc_msgSend(self, fetcherOpSEL, anEntry);
}

- (SyncResponseFetcher *)_fetcherForNote:(NoteObject *)aNote creator:(BOOL)doesCreate {
	NSAssert([aNote isKindOfClass:[NoteObject class]], @"need a real note to create");

	//if we're creating a note, grab the metadata directly from the note object itself, as it will not have a syncServiceMD dict
	NSDictionary *info = [aNote syncServicesMD][SimplenoteServiceName];
	//following assertion tests the efficacy our queued invocations system
	NSAssert(doesCreate == (nil == info), @"noteobject has MD for this service when it was attempting to be created or vise versa!");
	CFAbsoluteTime modNum = doesCreate ? aNote.modifiedDate : [info[@"modify"] doubleValue];

	//always set the mod date, set created date if we are creating, set the key if we are updating
	NSDictionary *params = @{@"email" : email, @"auth" : authToken};

	NSMutableString *noteBody = [[aNote combinedContentWithContextSeparator: /* explicitly assume default separator if creating */
			doesCreate ? nil : info[SimplenoteSeparatorKey]] mutableCopy];
	//simpletext iPhone app loses any tab characters
	[noteBody replaceTabsWithSpacesOfWidth:[[GlobalPrefs defaultPrefs] numberOfSpacesInTab]];

	NSMutableDictionary *rawObject = [NSMutableDictionary dictionaryWithCapacity:12];
	if (modNum > 0.0) rawObject[@"modifydate"] = @([[NSDate dateWithTimeIntervalSinceReferenceDate:modNum] timeIntervalSince1970]);
	if (doesCreate) rawObject[@"createdate"] = @([[NSDate dateWithTimeIntervalSinceReferenceDate:aNote.createdDate] timeIntervalSince1970]);

	NSArray *tags = [aNote orderedLabelTitles];
	// Don't send an empty tagset if this note has never been synced via sn-api2
	if ([tags count] || (info[@"syncnum"] != nil)) {
		rawObject[@"tags"] = tags;
	}

	rawObject[@"content"] = noteBody;

	NSURL *noteURL = nil;
	if (doesCreate) {
		noteURL = [SimplenoteSession servletURLWithPath:@"/api2/data" parameters:params];
	} else {
		noteURL = [SimplenoteSession servletURLWithPath:[NSString stringWithFormat:@"/api2/data/%@", info[@"key"]] parameters:params];
	}

	NSData *JSONData = [NSJSONSerialization dataWithJSONObject:rawObject options:0 error:NULL];
	if (!JSONData) return nil;

	SyncResponseFetcher *fetcher = [[SyncResponseFetcher alloc] initWithURL:noteURL POSTData:JSONData contentType:@"application/json" delegate:self];
	[fetcher setRepresentedObject:aNote];
	return fetcher;
}

- (SyncResponseFetcher *)fetcherForCreatingNote:(NoteObject *)aNote {
	return [self _fetcherForNote:aNote creator:YES];
}

- (SyncResponseFetcher *)fetcherForUpdatingNote:(NoteObject *)aNote {
	return [self _fetcherForNote:aNote creator:NO];
}

- (SyncResponseFetcher *)fetcherForDeletingNote:(DeletedNoteObject *)aDeletedNote {
	NSAssert([aDeletedNote isKindOfClass:[DeletedNoteObject class]], @"can't delete a note until you delete it yourself");

	NSDictionary *info = [aDeletedNote syncServicesMD][SimplenoteServiceName];

	if (!info[@"key"]) {
		//the deleted note lacks a key, so look up its created-equivalent and use _its_ metadata
		//handles the case of deleting a newly-created note after it had begun to sync, but before the remote operation gave it a key
		//because notes are queued against each other, by the time the create operation finishes on originalNote, it will have syncMD
		if ((info = [[aDeletedNote originalNote] syncServicesMD][SimplenoteServiceName]))
			[aDeletedNote setSyncObjectAndKeyMD:info forService:SimplenoteServiceName];
	}
	NSAssert(info[@"key"], @"fetcherForDeletingNote: got deleted note and couldn't find a key anywhere!");

	//in keeping with nv's behavior with sn api1, deleting only marks a note as deleted.
	//may want to implement actual purging (using HTTP DELETE) in the future
	NSURL *noteURL = [SimplenoteSession servletURLWithPath:[NSString stringWithFormat:@"/api2/data/%@", info[@"key"]] parameters:
			@{@"email" : email,
					@"auth" : authToken}];
	NSDictionary *jsonDict = @{@"deleted" : @1};
	NSData *postData = [NSJSONSerialization dataWithJSONObject:jsonDict options:0 error:NULL];
	if (!postData) return nil;

	SyncResponseFetcher *fetcher = [[SyncResponseFetcher alloc] initWithURL:noteURL POSTData:postData contentType:@"application/json" delegate:self];
	[fetcher setRepresentedObject:aDeletedNote];
	return fetcher;
}

- (NSString *)localizedActionDescription {
	return (@selector(fetcherForCreatingNote:) == fetcherOpSEL ? NSLocalizedString(@"Creating", nil) :
			(@selector(fetcherForUpdatingNote:) == fetcherOpSEL ? NSLocalizedString(@"Updating", nil) :
					(@selector(fetcherForDeletingNote:) == fetcherOpSEL ? NSLocalizedString(@"Deleting", nil) : NSLocalizedString(@"Processing", nil))));
}

- (NSString *)statusText {
	NSString *opName = [self localizedActionDescription];
	if ([entriesToCollect count] == 1) {
		NoteObject *aNote = [currentFetcher representedObject];
		if ([aNote isKindOfClass:[NoteObject class]]) {
			return [NSString stringWithFormat:NSLocalizedString(@"%@ quot%@quot...", @"example: Updating 'joe shmoe note'"), opName, aNote.title];
		} else {
			return [NSString stringWithFormat:NSLocalizedString(@"%@ a note...", @"e.g., 'Deleting a note...'"), opName];
		}
	}
	return [NSString stringWithFormat:NSLocalizedString(@"%@ %u of %u notes", @"Downloading/Creating/Updating/Deleting 5 of 10 notes"),
									  opName, entryFinishedCount, [entriesToCollect count]];
}

#if 0 /* allowing creation to complete will be of no use when the note's 
	delegate notationcontroller has closed its WAL and DB, and as it is unretained can cause a crash */
- (void)stop {
	//cancel the current fetcher only if it is not a creator-fetcher; otherwise we risk it finishing without fully receiving notification of its sucess
	if (@selector(fetcherForCreatingNote:) == fetcherOpSEL) {
		//only stop the progression but allow the current fetcher to complete
		stopped = YES;
	} else {
		[super stop];
	}
}
#endif

- (NSDictionary *)preparedDictionaryWithFetcher:(SyncResponseFetcher *)fetcher receivedData:(NSData *)data {

	NSDictionary *rawObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];

	if (!rawObject)
		return nil;

	NSString *keyString = rawObject[@"key"];

	NSMutableDictionary *result = [NSMutableDictionary dictionaryWithCapacity:5];
	NSMutableDictionary *syncMD = [NSMutableDictionary dictionaryWithCapacity:5];
	syncMD[@"key"] = rawObject[@"key"];
	syncMD[@"create"] = @([[NSDate dateWithTimeIntervalSince1970:[rawObject[@"createdate"] doubleValue]] timeIntervalSinceReferenceDate]);
	syncMD[@"modify"] = @([[NSDate dateWithTimeIntervalSince1970:[rawObject[@"modifydate"] doubleValue]] timeIntervalSinceReferenceDate]);
	syncMD[@"syncnum"] = @([rawObject[@"syncnum"] intValue]);
	syncMD[@"dirty"] = @NO;

	if ([fetcher representedObject]) {
		id <SynchronizedNote> aNote = [fetcher representedObject];
		result[@"NoteObject"] = aNote;

		if (@selector(fetcherForCreatingNote:) == fetcherOpSEL) {
			//these entries were created because no metadata had existed, thus we must give them metadata now,
			//which SHOULD be the same metadata we used when creating the note, but in theory the note could have changed in the meantime
			//in that case the newer modification date should later cause a resynchronization

			//we are giving this note metadata immediately instead of waiting for the SimplenoteSession delegate to do it during the final callback
			//to reduce the possibility of duplicates in the case of interruptions (where we might have forgotten that we had already created this)

			NSAssert([aNote isKindOfClass:[NoteObject class]], @"received a non-noteobject from a fetcherForCreatingNote: operation!");
			//don't need to store a separator for newly-created notes; when nil it is presumed the default separator
			[aNote setSyncObjectAndKeyMD:syncMD forService:SimplenoteServiceName];

			[(NoteObject *) aNote makeNoteDirtyUpdateTime:NO updateFile:NO];
		} else if (@selector(fetcherForDeletingNote:) == fetcherOpSEL) {
			//this note has been successfully deleted, and can now have its Simplenote syncServiceMD entry removed
			//so that _purgeAlreadyDistributedDeletedNotes can remove it permanently once the deletion has been synced with all other registered services
			NSAssert([aNote isKindOfClass:[DeletedNoteObject class]], @"received a non-deletednoteobject from a fetcherForDeletingNote: operation");
			[aNote removeAllSyncMDForService:SimplenoteServiceName];
		} else if (@selector(fetcherForUpdatingNote:) == fetcherOpSEL) {
			// SN api2 can return a content key in an update response containing
			// the merged changes from other clients....
			if (rawObject[@"content"]) {
				NSUInteger bodyLoc = 0;
				NSString *separator = nil;
				NSString *combinedContent = rawObject[@"content"];
				NSString *newTitle = [combinedContent syntheticTitleAndSeparatorWithContext:&separator bodyLoc:&bodyLoc oldTitle:[(NoteObject *) aNote title] maxTitleLen:60];

				[(NoteObject *) aNote updateWithSyncBody:[combinedContent substringFromIndex:bodyLoc] andTitle:newTitle];
			}

			// Tags may have been changed by another client...
			NSSet *localTags = [NSSet setWithArray:[(NoteObject *) aNote orderedLabelTitles]];
			NSSet *remoteTags = [NSSet setWithArray:rawObject[@"tags"]];
			if (![localTags isEqualToSet:remoteTags]) {
				NSLog(@"Updating tags with remote values.");
				NSString *newLabelString = [[remoteTags allObjects] componentsJoinedByString:@" "];
				[(NoteObject *) aNote setLabelString:newLabelString];
			}

			[aNote setSyncObjectAndKeyMD:syncMD forService:SimplenoteServiceName];
			//NSLog(@"note update:\n %@", [aNote syncServicesMD]);
		} else {
			NSLog(@"%@ called with unknown opSEL: %@", NSStringFromSelector(_cmd), NSStringFromSelector(fetcherOpSEL));
		}

	} else {
		NSLog(@"Hmmm. Fetcher %@ doesn't have a represented object. op = %@", fetcher, NSStringFromSelector(fetcherOpSEL));
	}
	result[@"key"] = keyString;


	return result;
}

@end
