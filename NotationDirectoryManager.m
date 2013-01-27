//
//  NotationDirectoryManager.m
//  Notation
//
//  Created by Zachary Schneirov on 12/10/09.

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

#import "NotationDirectoryManager.h"
#import "NSFileManager_NV.h"
#import "GlobalPrefs.h"
#import "NotationSyncServiceManager.h"
#import "DeletionManager.h"
#import "NSCollection_utils.h"
#import "NotationFileManager.h"
#import "NoteCatalogEntry.h"
#import "NSDate+Notation.h"

#define kMaxFileIteratorCount 100

@implementation NotationController (NotationDirectoryManager)

//used to find notes corresponding to a group of existing files in the notes dir, with the understanding 
//that the files' contents are up-to-date and the filename property of the note objs is also up-to-date
//e.g. caller should know that if notes are stored as a single DB, then the file could still be out-of-date
- (NSSet *)notesWithFilenames:(NSArray *)filenames unknownFiles:(NSArray **)unknownFiles {
	//intersects a list of filenames with the current set of available notes

	NSUInteger i = 0;

	NSMutableDictionary *lcNamesDict = [NSMutableDictionary dictionaryWithCapacity:[filenames count]];
	for (i = 0; i < [filenames count]; i++) {
		NSString *path = filenames[i];
		//assume that paths are of NSFileManager origin, not Carbon File Manager
		//(note filenames are derived with the expectation of matching against Carbon File Manager)
		lcNamesDict[[[[[path lastPathComponent] precomposedStringWithCanonicalMapping]
				lowercaseString] stringByReplacingOccurrencesOfString:@":" withString:@"/"]] = path;
	}

	NSMutableSet *foundNotes = [NSMutableSet setWithCapacity:[filenames count]];

	for (i = 0; i < [allNotes count]; i++) {
		NoteObject *aNote = allNotes[i];
		NSString *existingRequestedFilename = aNote.filename.lowercaseString;
		if (existingRequestedFilename && lcNamesDict[existingRequestedFilename]) {
			[foundNotes addObject:aNote];
			//remove paths from the dict as they are matched to existing notes; those left over will be new ("unknown") files
			[lcNamesDict removeObjectForKey:existingRequestedFilename];
		}
	}
	if (unknownFiles) *unknownFiles = [lcNamesDict allValues];
	return foundNotes;
}


static void FSEventsCallback(ConstFSEventStreamRef stream, void *info, size_t num_events, void *event_paths,
		const FSEventStreamEventFlags flags[],
		const FSEventStreamEventId event_ids[]) {
	NotationController *self = (__bridge NotationController *) info;

	BOOL rootChanged = NO;
	size_t i = 0;
	for (i = 0; i < num_events; i++) {
		//on 10.5, could also check whether all the events are bookended by eventIDs that were contemporaneous with a change by NotationFileManager
		//as it lacks kFSEventStreamCreateFlagIgnoreSelf
		if ((flags[i] & kFSEventStreamEventFlagRootChanged) && !event_ids[i]) {
			rootChanged = YES;
			break;
		}
	}

	//the directory was moved; re-initialize the event stream for the new path
	//but do so after this callback ends to avoid confusing FSEvents
	if (rootChanged) {
		NSLog(@"FSEventsCallback detected directory dislocation; reconfiguring stream");
		[self performSelector:@selector(_configureDirEventStream) withObject:nil afterDelay:0];
	}

	//NSLog(@"FSEventsCallback got a path change");
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(synchronizeNotesFromDirectory) object:nil];
	[self performSelector:@selector(synchronizeNotesFromDirectory) withObject:nil afterDelay:0.0];
}


- (void)_configureDirEventStream {
	//"updates" the event stream to point to the current notation directory path
	//or if the stream doesn't exist, creates it

	if (!eventStreamStarted) return;

	if (noteDirEventStreamRef) {
		//remove the event stream if it already exists, so that a new one can be created
		[self _destroyDirEventStream];
	}

	NSString *path = self.noteDirectoryURL.path;

	FSEventStreamContext context = {0, (__bridge void *) (self), CFRetain, CFRelease, CFCopyDescription};

	noteDirEventStreamRef = FSEventStreamCreate(NULL, &FSEventsCallback, &context, (__bridge CFArrayRef) @[path], kFSEventStreamEventIdSinceNow,
			1.0, kFSEventStreamCreateFlagWatchRoot | 0x00000008 /*kFSEventStreamCreateFlagIgnoreSelf*/);

	FSEventStreamScheduleWithRunLoop(noteDirEventStreamRef, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
	if (!FSEventStreamStart(noteDirEventStreamRef)) {
		NSLog(@"could not start the FSEvents stream!");
	}

}

- (void)_destroyDirEventStream {
	if (eventStreamStarted) {
		NSAssert(noteDirEventStreamRef != NULL, @"can't destroy a NULL event stream");

		FSEventStreamStop(noteDirEventStreamRef);
		FSEventStreamInvalidate(noteDirEventStreamRef);
		FSEventStreamRelease(noteDirEventStreamRef);
		noteDirEventStreamRef = NULL;
	}
}

- (void)startFileNotifications {
	eventStreamStarted = YES;
	[self _configureDirEventStream];
}

- (void)stopFileNotifications {
	if (!eventStreamStarted) return;

	[self _destroyDirEventStream];

	eventStreamStarted = NO;
}

- (BOOL)synchronizeNotesFromDirectory {
	if ([self currentNoteStorageFormat] == SingleDatabaseFormat) {
		//NSLog(@"%s: called when storage format is singledatabase", _cmd);
		return NO;
	}

	NSArray *catalogEntries = nil;

	//NSDate *date = [NSDate date];
	if ((catalogEntries = [self _readFilesInDirectory])) {
		//NSLog(@"read files in directory");

		directoryChangesFound = NO;
		if (catalogEntries.count && [allNotes count]) {
			[self makeNotesMatchCatalogEntries: catalogEntries];
		} else {
			if (![allNotes count]) {
				//no notes exist, so every file must be new
				for (NoteCatalogEntry *entry in catalogEntries) {
					if ([notationPrefs catalogEntryAllowed: entry])
						[self addNoteFromCatalogEntry: entry];
				}
			}

			if (!catalogEntries.count) {
				//there is nothing at all in the directory, so remove all the notes
				[deletionManager addDeletedNotes:allNotes];
			}
		}

		if (directoryChangesFound) {
			[self resortAllNotes];
			[self refilterNotes];

			[self updateTitlePrefixConnections];
		}

		//NSLog(@"file sync time: %g, ",[[NSDate date] timeIntervalSinceDate:date]);
		return YES;
	}

	return NO;
}

//scour the notes directory for fresh meat
- (NSArray *)_readFilesInDirectory {

	OSStatus status = noErr;
	FSIterator dirIterator;
	ItemCount dirObjectCount = 0;
	unsigned int i = 0;

	//something like 16 VM pages used here?
	if (!fsCatInfoArray) fsCatInfoArray = (FSCatalogInfo *) calloc(kMaxFileIteratorCount, sizeof(FSCatalogInfo));
	if (!HFSUniNameArray) HFSUniNameArray = (HFSUniStr255 *) calloc(kMaxFileIteratorCount, sizeof(HFSUniStr255));

	NSMutableArray *catalogEntries = [NSMutableArray array];

	if ((status = FSOpenIterator(&noteDirectoryRef, kFSIterateFlat, &dirIterator)) == noErr) {
		//catEntriesCount = 0;

		do {
			// Grab a batch of source files to process from the source directory
			status = FSGetCatalogInfoBulk(dirIterator, kMaxFileIteratorCount, &dirObjectCount, NULL,
					kFSCatInfoNodeFlags | kFSCatInfoFinderInfo | kFSCatInfoContentMod |
							kFSCatInfoAttrMod | kFSCatInfoDataSizes | kFSCatInfoCreateDate,
					fsCatInfoArray, NULL, NULL, HFSUniNameArray);

			if ((status == errFSNoMoreItems || status == noErr) && dirObjectCount) {
				status = noErr;

				for (i = 0; i < dirObjectCount; i++) {
					// Only read files, not directories
					if (!(fsCatInfoArray[i].nodeFlags & kFSNodeIsDirectoryMask)) {
						//filter these only for files that will be added
						//that way we can catch changes in files whose format is still being lazily updated

						NoteCatalogEntry *entry = [NoteCatalogEntry new];
						HFSUniStr255 *filename = &HFSUniNameArray[i];

						entry.fileType = ((FileInfo *) fsCatInfoArray[i].finderInfo)->fileType;
						entry.logicalSize = (UInt32) (fsCatInfoArray[i].dataLogicalSize & 0xFFFFFFFF);
						entry.creationDate = [NSDate datewithUTCDateTime: &fsCatInfoArray[i].createDate];
						entry.contentModificationDate = [NSDate datewithUTCDateTime: &fsCatInfoArray[i].contentModDate];
						entry.attributeModificationDate = [NSDate datewithUTCDateTime: &fsCatInfoArray[i].attributeModDate];

						if (filename->length > entry.filenameCharCount) {
							entry.filenameCharCount = filename->length;
							entry.filenameChars = (UniChar *) realloc(entry.filenameChars, entry.filenameCharCount * sizeof(UniChar));
						}

						memcpy(entry.filenameChars, filename->unicode, filename->length * sizeof(UniChar));

						if (!entry.filename)
							entry.filename = CFStringCreateMutableWithExternalCharactersNoCopy(NULL, entry.filenameChars, filename->length, entry.filenameCharCount, kCFAllocatorNull);
						else
							CFStringSetExternalCharactersNoCopy(entry.filename, entry.filenameChars, filename->length, entry.filenameCharCount);

						// mipe: Normalize the filename to make sure that it will be found regardless of international characters
						CFStringNormalize(entry.filename, kCFStringNormalizationFormC);

						[catalogEntries addObject: entry];
					}
				}
			}

		} while (status == noErr);

		FSCloseIterator(dirIterator);
		
		return [catalogEntries copy];
	}

	NSLog(@"Error opening FSIterator: %d", status);

	return nil;
}

- (BOOL)modifyNoteIfNecessary:(NoteObject *)aNoteObject usingCatalogEntry:(NoteCatalogEntry *)catEntry {
	//check dates
	updateForVerifiedExistingNote(deletionManager, aNoteObject);

	NSDate *noteLastAttrMod = aNoteObject.attributesModificationDate;
	NSDate *noteLastMod = aNoteObject.contentModificationDate;
	NSDate *catLastAttrMod = catEntry.attributeModificationDate;
	NSDate *catLastMod = catEntry.contentModificationDate;

	// TODO some garbage is getting generated somewhere
	if ([noteLastMod isGreaterThan: [NSDate distantFuture]]) {
		noteLastMod = catLastMod;
	}

	BOOL sizesEquals = (aNoteObject.fileSize == catEntry.logicalSize);
	BOOL lastAttrModDatesEqual = [noteLastAttrMod isEqualToDate: catLastAttrMod];
	BOOL lastModDatesEquals = [noteLastMod isEqualToDate: catLastMod];

	if (!sizesEquals || !lastModDatesEquals || !lastAttrModDatesEqual) {

		//assume the file on disk was modified by someone other than us

		//check if this note has changes in memory that still need to be committed -- that we _know_ the other writer never had a chance to see
		if (![unwrittenNotes containsObject:aNoteObject]) {

			if (![aNoteObject updateFromCatalogEntry:catEntry]) {
				NSLog(@"file %@ was modified but could not be updated", catEntry.filename);
				//return NO;
			}
			//do not call makeNoteDirty because use of the WAL in this instance would cause redundant disk activity
			//in the event of a crash this change could still be recovered;

			[aNoteObject registerModificationWithOwnedServices];
			[self schedulePushToAllSyncServicesForNote:aNoteObject];

			[self note:aNoteObject attributeChanged:NotePreviewString]; //reverse delegate?

			id <NotationControllerDelegate> delegate = self.delegate;
			[delegate contentsUpdatedForNote:aNoteObject];

			[self performSelector:@selector(scheduleUpdateListForAttribute:) withObject:NoteDateModifiedColumnString afterDelay:0.0];

			notesChanged = YES;
			NSLog(@"FILE WAS MODIFIED: %@", catEntry.filename);

			return YES;
		} else {
			//it's a conflict! we win.
			NSLog(@"%@ was modified with unsaved changes in NV! Deciding the conflict in favor of NV.", catEntry.filename);
		}
		
	}
	
	return NO;
}

- (void)makeNotesMatchCatalogEntries:(NSArray *)array {

	NSArray *currentNotes = [allNotes sortedArrayWithOptions: NSSortConcurrent | NSSortStable usingComparator:^NSComparisonResult(NoteObject *a, NoteObject *b) {
		return [a.filename caseInsensitiveCompare:b.filename];
	}];

	NSArray *catEntries = [array sortedArrayWithOptions: NSSortConcurrent | NSSortStable usingComparator: ^NSComparisonResult(NoteCatalogEntry *obj1, NoteCatalogEntry *obj2) {
		return [(__bridge NSString *)obj1.filename caseInsensitiveCompare: (__bridge NSString *)obj2.filename];
	}];
	NSUInteger bSize = catEntries.count;

	NSMutableArray *addedEntries = [NSMutableArray array];
	NSMutableArray *removedEntries = [NSMutableArray array];

	NSUInteger j, lastInserted = 0;

	for (NoteObject *note in currentNotes) {
		BOOL exitedEarly = NO;
		for (j = lastInserted; j < bSize; j++) {
			NoteCatalogEntry *entry = catEntries[j];

			NSComparisonResult order = [note.filename caseInsensitiveCompare: (__bridge NSString *)entry.filename];
			if (order == NSOrderedAscending) {		//if (A[i] < B[j])
				lastInserted = j;
				exitedEarly = YES;

				[removedEntries addObject:note];
				break;
			} else if (order == NSOrderedSame) {	//if (A[i] == B[j])
				//the name matches, so add this to changed iff its contents also changed
				lastInserted = j + 1;
				exitedEarly = YES;

				[self modifyNoteIfNecessary:note usingCatalogEntry: entry];

				break;
			} else {
				if ([notationPrefs catalogEntryAllowed: entry])
					[addedEntries addObject: entry];
			}
		}

		if (!exitedEarly) {
			NSUInteger idx = MIN(lastInserted, bSize - 1);
			NoteCatalogEntry *tEntry = catEntries[idx];

			if ([note.filename caseInsensitiveCompare: (__bridge NSString *)tEntry.filename] == NSOrderedDescending) {
				lastInserted = bSize;

				//NSLog(@"FILE DELETED (after): %@", currentNotes[i].filename);
				[removedEntries addObject:note];
			}
		}
	}

	for (j = lastInserted; j < bSize; j++) {
		NoteCatalogEntry *entry = catEntries[j];
		if ([notationPrefs catalogEntryAllowed: entry])
			[addedEntries addObject: entry];
	}

	if ([addedEntries count] && [removedEntries count]) {
		[self processNotesAddedByCNID:addedEntries removed:removedEntries];
	} else {
		if (![removedEntries count]) {
			for (NoteCatalogEntry *entry in addedEntries) {
				[self addNoteFromCatalogEntry:entry];
			}
		}

		if (![addedEntries count]) {
			[deletionManager addDeletedNotes:removedEntries];
		}
	}
}

//find renamed notes through unique file IDs
- (void)processNotesAddedByCNID:(NSMutableArray *)addedEntries removed:(NSMutableArray *)removedEntries {
	NSUInteger aSize = [removedEntries count], bSize = [addedEntries count];

	//sort on creation date here
	[addedEntries sortWithOptions: NSSortConcurrent usingComparator:^NSComparisonResult(NoteCatalogEntry *aEntry, NoteCatalogEntry *bEntry) {
		return [aEntry.creationDate compare: bEntry.creationDate];
	}];

	[removedEntries sortWithOptions: NSSortConcurrent usingComparator:^NSComparisonResult(NoteObject *aEntry, NoteObject *bEntry) {
		return [aEntry.creationDate compare: bEntry.creationDate];
	}];

	NSMutableArray *hfsAddedEntries = [NSMutableArray array];
	NSMutableArray *hfsRemovedEntries = [NSMutableArray array];

	//oldItems(a,i) = currentNotes
	//newItems(b,j) = catEntries;

	NSUInteger i, j, lastInserted = 0;

	for (i = 0; i < aSize; i++) {
		NoteObject *currentNote = removedEntries[i];

		BOOL exitedEarly = NO;
		for (j = lastInserted; j < bSize; j++) {
			NoteCatalogEntry *catEntry = addedEntries[j];

			NSComparisonResult compare = [currentNote.creationDate compare: catEntry.creationDate];

			if (compare == NSOrderedAscending) { // if (A[i] < B[j])
				lastInserted = j;
				exitedEarly = YES;

				NSLog(@"File deleted as per CNID: %@", currentNote.filename);
				[hfsRemovedEntries addObject:currentNote];
				break;
			} else if (compare == NSOrderedSame) { // if (A[i] == B[j])
				lastInserted = j + 1;
				exitedEarly = YES;


				//note was renamed!
				NSLog(@"File %@ renamed as per CNID to %@", currentNote.filename, catEntry.filename);
				if (![self modifyNoteIfNecessary:currentNote usingCatalogEntry:catEntry]) {
					//at least update the file name, because we _know_ that changed

					directoryChangesFound = YES;

					[currentNote setFilename:(__bridge NSString *)catEntry.filename withExternalTrigger:YES];
				}

				notesChanged = YES;
				
				break;
			}

			//a new file was found on the disk! read it into memory!

			NSLog(@"File added as per CNID: %@", catEntry.filename);
			[hfsAddedEntries addObject: catEntry];
		}

		if (!exitedEarly) {
			NoteCatalogEntry *appendedCatEntry = addedEntries[MIN(lastInserted, bSize - 1)];
			if ([currentNote.creationDate compare: appendedCatEntry.creationDate] == NSOrderedDescending) {
				lastInserted = bSize;

				//file deleted from disk;
				NSLog(@"File deleted as per CNID: %@", currentNote.filename);
				[hfsRemovedEntries addObject:currentNote];
			}
		}
	}

	for (j = lastInserted; j < bSize; j++) {
		NoteCatalogEntry *appendedCatEntry = addedEntries[j];
		NSLog(@"File added as per CNID: %@", appendedCatEntry.filename);
		[hfsAddedEntries addObject: appendedCatEntry];
	}

	if ([hfsAddedEntries count] && [hfsRemovedEntries count]) {
		[self processNotesAddedByContent:hfsAddedEntries removed:hfsRemovedEntries];
	} else {
		//NSLog(@"hfsAddedEntries: %@, hfsRemovedEntries: %@", hfsAddedEntries, hfsRemovedEntries);
		if (![hfsRemovedEntries count]) {
			for (NoteCatalogEntry *addedEntry in hfsAddedEntries) {
				NSLog(@"File _actually_ added: %@ (%@)", addedEntry.filename, NSStringFromSelector(_cmd));
				[self addNoteFromCatalogEntry: addedEntry];
			}
		}

		if (![hfsAddedEntries count]) {
			[deletionManager addDeletedNotes:hfsRemovedEntries];
		}
	}

}

//reconcile the "actually" added/deleted files into renames for files with identical content, looking at logical size first
- (void)processNotesAddedByContent:(NSMutableArray *)addedEntries removed:(NSMutableArray *)removedEntries {
	//more than 1 entry in the same list could have the same file size, so sort-algo assumptions above don't apply here
	//instead of sorting, build a dict keyed by file size, with duplicate sizes (on the same side) chained into arrays
	//make temporary notes out of the new NoteCatalogEntries to allow their contents to be compared directly where sizes match
	NSMutableDictionary *addedDict = [NSMutableDictionary dictionaryWithCapacity:[addedEntries count]];

	for (NoteCatalogEntry *addedEntry in addedEntries) {
		NSNumber *sizeKey = @(addedEntry.logicalSize);
		id sameSizeObj = addedDict[sizeKey];

		if ([sameSizeObj isKindOfClass:[NSArray class]]) {
			//just insert it directly; an array already exists
			NSAssert([sameSizeObj isKindOfClass:[NSMutableArray class]], @"who's inserting immutable collections into my dictionary?");
			[sameSizeObj addObject: addedEntry];
		} else if (sameSizeObj) {
			//two objects need to be inserted into the new array
			addedDict[sizeKey] = [@[sameSizeObj, addedEntry] mutableCopy];
		} else {
			//nothing with this key, just insert it directly
			addedDict[sizeKey] = addedEntry;
		}
	}

	for (NoteObject *removedObj in removedEntries) {
		NSNumber *sizeKey = @(removedObj.fileSize);
		BOOL foundMatchingContent = NO;

		//does any added item have the same size as removedObj?
		//if sizes match, see if that added item's actual content fully matches removedObj's
		//if content matches, then both items cancel each other out, with a rename operation resulting on the item in the removedEntries list
		//if content doesn't match, then check the next item in the array (if there is more than one matching size), and so on
		//any item in removedEntries that has no match in the addedEntries list is marked deleted
		//everything left over in the addedEntries list is marked as new
		id sameSizeObj = addedDict[sizeKey];
		NSUInteger addedObjCount = [sameSizeObj isKindOfClass:[NSArray class]] ? [sameSizeObj count] : 1;
		
		while (sameSizeObj && !foundMatchingContent && addedObjCount-- > 0) {
			NoteCatalogEntry *val = [sameSizeObj isKindOfClass:[NSArray class]] ? sameSizeObj[addedObjCount] : sameSizeObj;
			NoteObject *addedObjToCompare = [[NoteObject alloc] initWithCatalogEntry: val delegate:self];

			if ([[[addedObjToCompare contentString] string] isEqualToString:[[removedObj contentString] string]]) {
				//process this pair as a modification

				NSLog(@"File %@ renamed as per content to %@", removedObj.filename, addedObjToCompare.filename);
				if (![self modifyNoteIfNecessary:removedObj usingCatalogEntry: val]) {
					//at least update the file name, because we _know_ that changed
					directoryChangesFound = YES;
					notesChanged = YES;
					[removedObj setFilename:addedObjToCompare.filename withExternalTrigger:YES];
				}

				if ([sameSizeObj isKindOfClass:[NSArray class]]) {
					[sameSizeObj removeObjectIdenticalTo:val];
				} else {
					[addedDict removeObjectForKey:sizeKey];
				}
				//also remove it from original array, which is easier to process for the leftovers that will actually be added
				[addedEntries removeObjectIdenticalTo:val];
				foundMatchingContent = YES;
			}
		}

		if (!foundMatchingContent) {
			NSLog(@"File %@ _actually_ removed (size: %u)", removedObj.filename, removedObj.fileSize);
			[deletionManager addDeletedNote:removedObj];
		}
	}

	for (NoteCatalogEntry *appendedCatEntry in addedEntries) {
		NSLog(@"File _actually_ added: %@ (%@)", appendedCatEntry.filename, NSStringFromSelector(_cmd));
		[self addNoteFromCatalogEntry:appendedCatEntry];
	}
}

@end


