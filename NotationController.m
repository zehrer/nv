//
//  NotationController.m
//  Notation
//
//  Created by Zachary Schneirov on 12/19/05.

/*Copyright (c) 2010, Zachary Schneirov. All rights reserved.
    This file is part of Notational Velocity.

    Notational Velocity is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    Notational Velocity is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with Notational Velocity.  If not, see <http://www.gnu.org/licenses/>. */


#import "AppController.h"
#import "NotationController.h"
#import "NSCollection_utils.h"
#import "DeletedNoteObject.h"
#import "NSString_NV.h"
#import "NSFileManager_NV.h"
#import "GlobalPrefs.h"
#import "NoteAttributeColumn.h"
#import "FrozenNotation.h"
#import "ODBEditor.h"
#import "NotationFileManager.h"
#import "NotationSyncServiceManager.h"
#import "NotationDirectoryManager.h"
#import "SyncSessionController.h"
#import "DeletionManager.h"
#import "NSBezierPath_NV.h"
#import "LabelObject.h"
#import "NSURL+Notation.h"
#import "NSError+Notation.h"
#import <objc/message.h>

@interface NotationController ()

@property (nonatomic, strong) NSMutableDictionary *labelImages;
@property (nonatomic, strong, readwrite) NSFileManager *fileManager;
@property (nonatomic, strong, readwrite) NSURL *noteDatabaseURL;
@property (nonatomic, strong, readwrite) NSURL *noteDirectoryURL;

@end

@implementation NotationController

- (void)ntn_sharedInit {
	self.fileManager = [NSFileManager new];

	directoryChangesFound = notesChanged = NO;

	allNotes = [[NSMutableArray alloc] init]; //<--the authoritative list of all memory-accessible notes
	deletedNotes = [[NSMutableSet alloc] init];
	prefsController = [GlobalPrefs defaultPrefs];
	self.filteredNotesList = [[NSMutableArray alloc] init];
	deletionManager = [[DeletionManager alloc] initWithNotationController:self];

	self.allLabels = [[NSCountedSet alloc] init];
	self.filteredLabels = [[NSCountedSet alloc] init];

	manglingString = currentFilterStr = NULL;
	lastWordInFilterStr = 0;
	selectedNoteIndex = NSNotFound;

	fsCatInfoArray = NULL;
	HFSUniNameArray = NULL;

	lastLayoutStyleGenerated = -1;
	lastCheckedDateInHours = hoursFromAbsoluteTime(CFAbsoluteTimeGetCurrent());

	unwrittenNotes = [[NSMutableSet alloc] init];
}

- (id)init {
	if ((self = [super init])) {
		[self ntn_sharedInit];
	}
	return self;
}

- (id)initWithBookmarkData:(NSData *)data error:(out NSError **)outError {
	NSError *error = nil;
	NSURL *URL = nil;
	BOOL stale = NO;
	NSURL *homeFolder = [NSURL fileURLWithPath: NSHomeDirectory() isDirectory: YES];

	if ((URL = [NSURL URLByResolvingBookmarkData: data options: NSURLBookmarkResolutionWithoutUI | NSURLBookmarkResolutionWithoutMounting relativeToURL: homeFolder bookmarkDataIsStale: &stale error: &error])) {
		if ((self = [self initWithDirectory: URL error: &error])) {
			self.bookmarkNeedsUpdating = stale;
			return self;
		}
	}

	if (outError) *outError = error;
	return nil;
}

- (id)initWithDefaultDirectoryWithError:(out NSError **)err {
	NSError *error = nil;
	NSURL *targetURL = nil;

	if ((targetURL = [NotationController defaultNotesDirectoryURLReturningError: &error])) {
		if ((self = [self initWithDirectory:targetURL error: &error])) {
			return self;
		}
	}

	if (err) *err = error;
	return nil;
}

- (id)initWithDirectory:(NSURL *)directoryURL error:(out NSError **)err {
	if ((self = [super init])) {
		[self ntn_sharedInit];

		self.bookmarkNeedsUpdating = YES;
		self.noteDirectoryURL = [directoryURL fileReferenceURL];

		//check writable and readable perms, warning user if necessary
		//first read cache file
		NSError *anErr = nil;
		
		if (![self _readAndInitializeSerializedNotesWithError: &anErr]) {
			if (err) *err = anErr;
			return nil;
		}

		//set up the directory subscription, if necessary
		//and sync based on notes in directory and their mod. dates
		[self databaseSettingsChangedFromOldFormat:[notationPrefs notesStorageFormat]];
		if (!walWriter) {
			if (err) *err = [NSError errorWithDomain: NTNErrorDomain code: NTNJournalingError userInfo: nil];
			return nil;
		}

		[self upgradeDatabaseIfNecessary];

		[self updateTitlePrefixConnections];
	}
	return self;
}

- (void)upgradeDatabaseIfNecessary {
	if (![notationPrefs firstTimeUsed]) {

		const UInt32 epochIteration = [notationPrefs epochIteration];

		//upgrade note-text-encodings here if there might exist notes with the wrong encoding (check NotationPrefs values)
		if (epochIteration < 2) {
			//this would have to be a database from epoch 1, where the default file-encoding was system-default
			NSLog(@"trying to upgrade note encodings");
			[allNotes makeObjectsPerformSelector:@selector(upgradeToUTF8IfUsingSystemEncoding)];
			//move aside the old database as the new format breaks compatibility
			[self renameAndForgetNoteDatabaseFile:@"Notes & Settings (old version from 2.0b)"];
		}
		if (epochIteration < 3) {
			[allNotes makeObjectsPerformSelector:@selector(writeFileDatesAndUpdateTrackingInfo)];
		}
		if (epochIteration < 4) {
			if ([self removeSpuriousDatabaseFileNotes]) {
				NSLog(@"found and removed spurious DB notes");
				[self refilterNotes];
			}

			//TableColumnsVisible was renamed NoteAttributesVisible to coincide with shifted emphasis; remove old key to declutter prefs
			[[NSUserDefaults standardUserDefaults] removeObjectForKey:@"TableColumnsVisible"];

			//remove and re-add link attributes for all notes
			//remove underline attribute for all notes
			//add automatic strike-through attribute for all notes
			[allNotes makeObjectsPerformSelector:@selector(_resanitizeContent)];
		}

		if (epochIteration < EPOC_ITERATION) {
			NSLog(@"epochIteration was upgraded from %u to %u", epochIteration, EPOC_ITERATION);
			notesChanged = YES;
			[self flushEverything];
		} else if ([notationPrefs epochIteration] > EPOC_ITERATION) {
			if (NSRunCriticalAlertPanel(NSLocalizedString(@"Warning: this database was created by a newer version of Notational Velocity. Continue anyway?", nil),
					NSLocalizedString(@"If you make changes, some settings and metadata will be lost.", nil),
					NSLocalizedString(@"Quit", nil), NSLocalizedString(@"Continue", nil), nil) == NSAlertDefaultReturn)
				exit(0);
		}
	}
}

- (BOOL)_readAndInitializeSerializedNotesWithError:(out NSError **)outError {
	NSError *nsErr = nil;
	if (!(self.noteDatabaseURL = [self createFileWithNameIfNotPresentInNotesDirectory: NotesDatabaseFileName created: NULL error: &nsErr])) {
		if (outError) *outError = nsErr;
		return NO;
	}
	
	NSData *notesData = nil;
	if (!(notesData = [NSData dataWithContentsOfURL: self.noteDatabaseURL options: NSDataReadingUncached | NSDataReadingMappedIfSafe error: &nsErr])) {
		if (outError) *outError = nsErr;
		return NO;
	}

	FrozenNotation *frozenNotation = nil;
	if (notesData.length) {
		@try {
			frozenNotation = [NSKeyedUnarchiver unarchiveObjectWithData: notesData];
		} @catch (NSException *e) {
			NSLog(@"Error unarchiving notes and preferences from data (%@, %@)", [e name], [e reason]);

			//perhaps this shouldn't be an error, but the user should instead have the option of overwriting the DB with a new one?
			if (outError) *outError = [NSError errorWithDomain: NTNErrorDomain code: NTNDeserializationError userInfo: @{NSURLErrorKey: self.noteDatabaseURL}];
			return NO;
		}
	}

	if (!(notationPrefs = [frozenNotation notationPrefs]))
		notationPrefs = [[NotationPrefs alloc] init];
	[notationPrefs setDelegate:self];

	//notationPrefs will have the index of the current disk UUID (or we will add it otherwise)
	//which will be used to determine which attr-mod-time to use for each note after decoding
	[self initializeDiskUUIDIfNecessary];

	syncSessionController = [[SyncSessionController alloc] initWithSyncDelegate:self notationPrefs:notationPrefs];

	//frozennotation will work out passwords, keychains, decryption, etc...
	OSStatus err;
	if (!(allNotes = [frozenNotation unpackedNotesReturningError:&err])) {
		//notes could be nil because the user cancelled password authentication
		//or because they were corrupted, or for some other reason
		if (err != noErr) {
			if (outError) *outError = [NSError errorWithDomain: NTNErrorDomain code: err userInfo: nil];
			return NO;
		}

		allNotes = [[NSMutableArray alloc] init];
	} else {
		for (NoteObject *note in allNotes) {
			note.delegate = self;
		}
	}

	if (!(deletedNotes = [frozenNotation deletedNotes]))
		deletedNotes = [[NSMutableSet alloc] init];

	[prefsController setNotationPrefs:notationPrefs sender:self];

	[self makeForegroundTextColorMatchGlobalPrefs];

	return YES;
}

- (BOOL)initializeJournaling {
	const char *path = self.noteDirectoryURL.path.fileSystemRepresentation;
	NSData *walSessionKey = [notationPrefs WALSessionKey];
	BOOL success = NO;

	//initialize the journal if necessary
	if ((walWriter = [[WALStorageController alloc] initWithParentFSRep: path encryptionKey: walSessionKey])) {
		success = YES;
	} else {
		//journal file probably already exists, so try to recover it

		WALRecoveryController *walReader = [[WALRecoveryController alloc] initWithParentFSRep: path encryptionKey:walSessionKey];

		if (walReader) {
			BOOL databaseCouldNotBeFlushed = NO;
			NSDictionary *recoveredNotes = [walReader recoveredNotes];
			if ([recoveredNotes count] > 0) {
				[self processRecoveredNotes:recoveredNotes];

				if (![self flushAllNoteChanges]) {
					//we shouldn't continue because the journal is still the sole record of the unsaved notes, so we can't delete it
					//BUT: what if the database can't be verified? We should be able to continue, and just keep adding to the WAL
					//in this case the WAL should be destroyed, re-initialized, and the recovered (and de-duped) notes added back
					NSLog(@"Unable to flush recovered notes back to database");
					databaseCouldNotBeFlushed = YES;
				}
			}
			//is there a way that recoverNextObject could fail that would indicate a failure with the file as opposed to simple non-recovery?
			//if so, it perhaps the recoveredNotes method should also return an error condition, to be checked here

			//there could be other issues, too (1)

			if ([walReader destroyLogFile]) {
				if ((walWriter = [[WALStorageController alloc] initWithParentFSRep: path encryptionKey:walSessionKey])) {
					if ([recoveredNotes count] > 0) {
						if (databaseCouldNotBeFlushed) {
							//re-add the contents of recoveredNotes to walWriter; LSNs should take care of the order; no need to sort
							//this allows for an ever-growing journal in the case of broken database serialization
							//it should not be an acceptable condition for permanent use; hopefully an update would come soon
							//warn the user, perhaps
							[walWriter writeNoteObjects:[recoveredNotes allValues]];
						}
						[self refilterNotes];
					}
				} else {
					//couldn't create a journal after recovering the old one
					//if databaseCouldNotBeFlushed is true here, then we've potentially lost notes; perhaps exchangeobjects would be better here?
					NSLog(@"Unable to create a new write-ahead-log after deleting the old one");
				}
			} else {
				//couldn't delete the log file, so we can't create a new one
				NSLog(@"Unable to delete the old write-ahead-log file");
			}
		} else {
			NSLog(@"Unable to recover unsaved notes from write-ahead-log");
			//1) should we let the user attempt to remove it without recovery?
		}
	}

	return success;
}

//stick the newest unique recovered notes into allNotes
- (void)processRecoveredNotes:(NSDictionary *)dict {
	if (!dict) return;
	const unsigned int vListBufCount = 16;
	void *keysBuffer[vListBufCount], *valuesBuffer[vListBufCount];
	NSUInteger i, count = [dict count];

	void **keys = NULL, **values = NULL;

	if (count > vListBufCount) {
		keys = keysBuffer;
		values = valuesBuffer;
	} else {
		keys = malloc(sizeof(void *) * count);
		values = malloc(sizeof(void *) * count);
	}

	if (keys && values) {
		CFDictionaryGetKeysAndValues((CFDictionaryRef) dict, (const void **) keys, (const void **) values);

		for (i = 0; i < count; i++) {

			CFUUIDBytes *objUUIDBytes = (CFUUIDBytes *) keys[i];
			id <SynchronizedNote> obj = (__bridge id) values[i];

			NSUInteger existingNoteIndex = [allNotes indexOfNoteWithUUIDBytes:objUUIDBytes];

			if ([obj isKindOfClass:[DeletedNoteObject class]]) {

				if (existingNoteIndex != NSNotFound) {

					NoteObject *existingNote = allNotes[existingNoteIndex];
					if ([existingNote youngerThanLogObject:obj]) {
						NSLog(@"got a newer deleted note %@", obj);
						//except that normally the undomanager doesn't exist by this point
						[self _registerDeletionUndoForNote:existingNote];
						[allNotes removeObjectAtIndex:existingNoteIndex];
						//try to use use the deleted note object instead of allowing _addDeletedNote: to make a new one, to preserve any changes to the syncMD
						[self _addDeletedNote:obj];
						notesChanged = YES;
					} else {
						NSLog(@"got an older deleted note %@", obj);
					}
				} else {
					NSLog(@"got a deleted note with a UUID that doesn't match anything in allNotes, adding to deletedNotes only");
					//must remember that this was deleted; b/c it could've been added+synced and then deleted before syncing the deletion
					//and it might not be in allNotes because the WALreader would have already coalesced by UUID, and so the next sync might re-add the note
					[self _addDeletedNote:obj];
				}
			} else if (existingNoteIndex != NSNotFound) {

				if ([allNotes[existingNoteIndex] youngerThanLogObject:obj]) {
					// NSLog(@"replacing old note with new: %@", [[(NoteObject*)obj contentString] string]);

					[(NoteObject *) obj setDelegate:self];
					[(NoteObject *) obj updateLabelConnectionsAfterDecoding];
					allNotes[existingNoteIndex] = obj;
					notesChanged = YES;
				} else {
					// NSLog(@"note %@ is not being replaced because its LSN is %u, while the old note's LSN is %u",
					//  [[(NoteObject*)obj contentString] string], [(NoteObject*)obj logSequenceNumber], [[allNotes objectAtIndex:existingNoteIndex] logSequenceNumber]);
				}
			} else {
				//NSLog(@"Found new note: %@", [(NoteObject*)obj contentString]);

				[self _addNote:obj];
				[(NoteObject *) obj updateLabelConnectionsAfterDecoding];
			}
		}
	} else {
		NSLog(@"_makeChangesInDictionary: Could not get values or keys!");
	}

	if (keys && keys != keysBuffer) free(keys);
	if (values && values != valuesBuffer) free(values);

}

- (void)closeJournal {
	//remove journal file if we have one
	if (walWriter) {
		if (![walWriter destroyLogFile])
			NSLog(@"couldn't remove wal file--is this an error for note flushing?");

		walWriter = nil;
	}
}

- (void)checkJournalExistence {
	if (walWriter && ![walWriter logFileStillExists])
		[self performSelector:@selector(handleJournalError) withObject:nil afterDelay:0.0];
}

- (void)flushEverything {

	//if we could flush the database and there was a journal, then close it
	if ([self flushAllNoteChanges] && walWriter) {
		[self closeJournal];

		//re-start the journal if we had one
		if (![self initializeJournaling]) {
			[self performSelector:@selector(handleJournalError) withObject:nil afterDelay:0.0];
		}
	}
}

- (BOOL)flushAllNoteChanges {
	//write only if preferences or notes have been changed
	if (notesChanged || [notationPrefs preferencesChanged]) {

		//finish writing notes and/or db journal entries
		[self synchronizeNoteChanges:changeWritingTimer];
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(synchronizeNoteChanges:) object:nil];

		if (walWriter) {
			if (![walWriter synchronize])
				NSLog(@"Couldn't sync wal file--is this an error for note flushing?");
			[NSObject cancelPreviousPerformRequestsWithTarget:walWriter selector:@selector(synchronize) object:nil];
		}

		NSData *serializedData = [FrozenNotation frozenDataWithExistingNotes:allNotes deletedNotes:deletedNotes prefs:notationPrefs];
		if (!serializedData) {

			NSLog(@"serialized data is nil!");
			return NO;
		}

		//we should have all journal records on disk by now
		//ensure a newly-written Notes & Settings file is valid before finalizing the save
		//read the file back from disk, deserialize it, decrypt and decompress it, and compare the notes roughly to our current notes
		if (!(self.noteDatabaseURL = [self writeDataToNotesDirectory: serializedData withName: NotesDatabaseFileName verifyUsingBlock:^BOOL(NSURL *temporaryFileURL, NSError **outError) {
			NSAssert([temporaryFileURL.lastPathComponent isEqualToString:NotesDatabaseFileName], @"attempting to verify something other than the database");
			NSDate *date = [NSDate date];
			NSError *error = nil;

			NSData *archivedNotation = [NSData dataWithContentsOfURL: temporaryFileURL options:NSDataReadingMappedIfSafe|NSDataReadingUncached error: &error];
			if (!archivedNotation) {
				if (outError) *outError = error;
				return NO;
			}

			FrozenNotation *frozenNotation = nil;
			@try {
				frozenNotation = [NSKeyedUnarchiver unarchiveObjectWithData:archivedNotation];
			}
			@catch (NSException *e) {
				NSLog(@"(VERIFY) Error unarchiving notes and preferences from data (%@, %@)", [e name], [e reason]);
				if (outError) *outError = [NSError ntn_errorWithCode: NTNDeserializationError carbon: NO];
				return NO;
			}

			//unpack notes using the current NotationPrefs instance (not the just-unarchived one), with which we presumably just used to encrypt it
			OSStatus err;
			NSMutableArray *notesToVerify = [frozenNotation unpackedNotesWithPrefs:notationPrefs returningError:&err];
			if (noErr != err) {
				if (outError) *outError = [NSError ntn_errorWithCode: err carbon: YES];
				return NO;
			}

			//notes were unpacked--now roughly compare notesToVerify with allNotes, plus deletedNotes and notationPrefs
			if (!notesToVerify || [notesToVerify count] != [allNotes count] || [[frozenNotation deletedNotes] count] != [deletedNotes count] ||
				[[frozenNotation notationPrefs] notesStorageFormat] != [notationPrefs notesStorageFormat] ||
				[[frozenNotation notationPrefs] hashIterationCount] != [notationPrefs hashIterationCount]) {
				if (outError) *outError = [NSError ntn_errorWithCode: NTNItemVerificationError carbon: NO];
				return NO;
			}

			__block BOOL result = YES;
			[notesToVerify enumerateObjectsUsingBlock:^(NoteObject *note, NSUInteger idx, BOOL *stop) {
				if (note.contentString.length != [[allNotes[idx] contentString] length]) {
					if (outError) *outError = [NSError ntn_errorWithCode: NTNItemVerificationError carbon: NO];
					result = NO;
					*stop = YES;
				}
			}];
			if (result) NSLog(@"verified %lu notes in %g s", [notesToVerify count], (float) [[NSDate date] timeIntervalSinceDate:date]);
			return result;
		} error: NULL])) {
			return NO;
		}

		[notationPrefs setPreferencesAreStored];
		notesChanged = NO;

	}

	return YES;
}

- (void)handleJournalError {

	//we can be static because the resulting action (exit) is global to the app
	static BOOL displayedAlert = NO;

	if (self.delegate && !displayedAlert) {
		//we already have a delegate, so this must be a result of the format or file changing after initialization

		displayedAlert = YES;

		[self flushAllNoteChanges];

		NSRunAlertPanel(NSLocalizedString(@"Unable to create or access the Interim Note-Changes file. Is another copy of Notational Velocity currently running?", nil),
				NSLocalizedString(@"Open Console in /Applications/Utilities/ for more information.", nil), NSLocalizedString(@"Quit", nil), NULL, NULL);


		exit(1);
	}
}

//notation prefs delegate method
- (void)databaseEncryptionSettingsChanged {
	//we _must_ re-init the journal (if fmt is single-db and jrnl exists) in addition to flushing DB
	[self flushEverything];

	//called whenever note-storage format or encryption-activation changes
	[[ODBEditor sharedODBEditor] initializeDatabase:notationPrefs];
}

//notation prefs delegate method
- (void)databaseSettingsChangedFromOldFormat:(NoteStorageFormat)oldFormat {
	NSInteger currentStorageFormat = [notationPrefs notesStorageFormat];

	if (!walWriter && ![self initializeJournaling]) {
		[self performSelector:@selector(handleJournalError) withObject:nil afterDelay:0.0];
	}

	if (currentStorageFormat == SingleDatabaseFormat) {

		[self stopFileNotifications];

		/*if (![self initializeJournaling]) {
			[self performSelector:@selector(handleJournalError) withObject:nil afterDelay:0.0];
		}*/

	} else {
		//write to disk any unwritten notes; do this before flushing database to make sure that when it is flushed, it gets the new file mod. dates
		//otherwise it would be necessary to set notesChanged = YES; after this method

		//also make sure not to write new notes unless changing to a different format; don't rewrite deleted notes upon launch
		if (currentStorageFormat != oldFormat)
			[allNotes makeObjectsPerformSelector:@selector(writeUsingCurrentFileFormatIfNonExistingOrChanged)];

		//flush and close the journal if necessary
		/*if (walWriter) {
			if ([self flushAllNoteChanges])
				[self closeJournal];
		}*/
		//notationPrefs should call flushAllNoteChanges after this method, anyway

		[self startFileNotifications];

		[self synchronizeNotesFromDirectory];
	}
	//perform after delay because this could trigger the mounting of a RAM disk in a background  NSTask
	[[ODBEditor sharedODBEditor] performSelector:@selector(initializeDatabase:) withObject:notationPrefs afterDelay:0.0];
}

- (NoteStorageFormat)currentNoteStorageFormat {
	return [notationPrefs notesStorageFormat];
}

- (void)noteDidNotWrite:(NoteObject *)note errorCode:(OSStatus)error {
	[unwrittenNotes addObject:note];

	if (error != lastWriteError) {
		NSRunAlertPanel([NSString stringWithFormat:NSLocalizedString(@"Changed notes could not be saved because %@.",
												   @"alert title appearing when notes couldn't be written"),
												   [NSString reasonStringFromCarbonFSError:error]], @"", NSLocalizedString(@"OK", nil), NULL, NULL);

		lastWriteError = error;
	}
}

- (void)noteDidNotWrite:(NoteObject *)note error:(NSError *)error {
	[unwrittenNotes addObject: note];

	if (![error isEqual: _lastWriteNSError]) {
		NSRunAlertPanel([NSString stringWithFormat:NSLocalizedString(@"Changed notes could not be saved because %@.",
																	 @"alert title appearing when notes couldn't be written"),
						 [error localizedFailureReason]], @"", NSLocalizedString(@"OK", nil), NULL, NULL);
		_lastWriteNSError = error;
	}
}

- (void)synchronizeNoteChanges:(NSTimer *)timer {

	if ([unwrittenNotes count] > 0) {
		lastWriteError = noErr;
		_lastWriteNSError = nil;
		if ([notationPrefs notesStorageFormat] != SingleDatabaseFormat) {
			//to avoid mutation enumeration if writing this file triggers a filename change which then triggers another makeNoteDirty which then triggers another scheduleWriteForNote:
			//loose-coupling? what?
			[[unwrittenNotes copy] makeObjectsPerformSelector:@selector(writeUsingCurrentFileFormatIfNecessary)];

			//this always seems to call ourselves
			[[NSWorkspace sharedWorkspace] noteFileSystemChanged: self.noteDirectoryURL.path];
		}
		if (walWriter) {
			//append unwrittenNotes to journal, if one exists
			[unwrittenNotes makeObjectsPerformSelector:@selector(writeUsingJournal:) withObject:walWriter];
		}

		//NSLog(@"wrote %d unwritten notes", [unwrittenNotes count]);

		[unwrittenNotes removeAllObjects];

		[self scheduleUpdateListForAttribute:NoteDateModifiedColumnString];

	}

	if (changeWritingTimer) {
		[changeWritingTimer invalidate];
		changeWritingTimer = nil;
	}
}

- (NSData *)bookmarkDataForNoteDirectory {
	NSURL *homeFolder = [NSURL fileURLWithPath: NSHomeDirectory() isDirectory: YES];
	return [self.noteDirectoryURL bookmarkDataWithOptions: 0 includingResourceValuesForKeys: nil relativeToURL: homeFolder error: NULL];
}

- (void)closeAllResources {
	[allNotes makeObjectsPerformSelector:@selector(abortEditingInExternalEditor)];

	[deletionManager cancelPanelReturningCode:NSRunStoppedResponse];
	[self stopSyncServices];
	[self stopFileNotifications];
	if ([self flushAllNoteChanges])
		[self closeJournal];
	[allNotes makeObjectsPerformSelector:@selector(disconnectLabels)];
}

- (void)checkIfNotationIsTrashed {
	if ([self notesDirectoryIsTrashed]) {
		NSString *trashLocation = self.noteDirectoryURL.path.stringByAbbreviatingWithTildeInPath;
		if (!trashLocation) trashLocation = @"unknown";
		NSInteger result = NSRunCriticalAlertPanel([NSString stringWithFormat:NSLocalizedString(@"Your notes directory (%@) appears to be in the Trash.", nil), trashLocation],
				NSLocalizedString(@"If you empty the Trash now, you could lose your notes. Relocate the notes to a less volatile folder?", nil),
				NSLocalizedString(@"Relocate Notes", nil), NSLocalizedString(@"Quit", nil), NULL);
		if (result == NSAlertDefaultReturn)
			[self relocateNotesDirectory];
		else [NSApp terminate:nil];
	}
}

- (void)trashRemainingNoteFilesInDirectory {
	NSAssert([notationPrefs notesStorageFormat] == SingleDatabaseFormat, @"We shouldn't be removing files if the storage is not single-database");
	[allNotes makeObjectsPerformSelector:@selector(moveFileToTrash)];
	[self notifyOfChangedTrash];
}

- (void)updateLinksToNote:(NoteObject *)aNoteObject fromOldName:(NSString *)oldname {
	//O(n)
}

- (void)updateTitlePrefixConnections {
	//used to auto-complete titles to the first, shortest title of the same prefix--
	//to prevent auto-completing "Chicago Brauhaus" before "Chicago" when search string is "Chi", for example.
	//builds a tree-overlay in the list of notes, to find, for any given note,
	//all other notes whose complete titles are a prefix of it

	//***
	//*** this method must run after any note is added, deleted, or retitled **
	//***

	if (![prefsController autoCompleteSearches] || ![allNotes count])
		return;

	//sort alphabetically to find shorter prefixes first
	NSMutableArray *allNotesAlpha = [allNotes mutableCopy];
	[allNotesAlpha sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(id obj1, id obj2) {
		return compareTitleString(&obj1, &obj2);
	}];

	[allNotes makeObjectsPerformSelector:@selector(removeAllPrefixParentNotes)];

	NSUInteger j, i = 0, count = [allNotesAlpha count];
	for (i = 0; i < count - 1; i++) {
		NoteObject *shorterNote = allNotesAlpha[i];
		BOOL isAPrefix = NO;
		//scan all notes sorted beneath this one for matching prefixes
		j = i + 1;
		do {
			NoteObject *longerNote = allNotesAlpha[j];
			if ((isAPrefix = noteTitleIsAPrefixOfOtherNoteTitle(longerNote, shorterNote))) {
				[longerNote addPrefixParentNote:shorterNote];
			}
		} while (isAPrefix && ++j < count);
	}

}

- (void)addNewNote:(NoteObject *)note {
	[self _addNote:note];

	//clear aNoteObject's syncServicesMD to facilitate sync recreation upon undoing of deletion
	//new notes should not have any sync MD; if they do, they should be added using -addNotesFromSync:
	//problem is that note could very likely still be in the process of syncing, in which case these dicts will be accessed
	//for simplenote is is necessary only once the iPhone app has fully deleted the note off the server; otherwise a regular update will recreate it
	//[note removeAllSyncServiceMD];

	[note makeNoteDirtyUpdateTime:YES updateFile:YES];

	[self updateTitlePrefixConnections];

	//force immediate update
	[self synchronizeNoteChanges:nil];

	if ([[self undoManager] isUndoing]) {
		//prohibit undoing of creation--only redoing of deletion
		//NSLog(@"registering %s", _cmd);
		[undoManager registerUndoWithTarget:self selector:@selector(removeNote:) object:note];
		if (![[self undoManager] isUndoing] && ![[self undoManager] isRedoing])
			[undoManager setActionName:[NSString stringWithFormat:NSLocalizedString(@"Create Note quotemark%@quotemark", @"undo action name for creating a single note"), note.title]];
	}

	[self resortAllNotes];
	[self refilterNotes];

	id <NotationControllerDelegate> delegate = self.delegate;
	[delegate notation:self revealNote:note options:NVEditNoteToReveal | NVOrderFrontWindow];
}

//do not update the view here (why not?)
- (NoteObject *)addNoteFromCatalogEntry:(NoteCatalogEntry *)catEntry {
	NoteObject *newNote = [[NoteObject alloc] initWithCatalogEntry:catEntry delegate:self];
	[self _addNote:newNote];

	[self schedulePushToAllSyncServicesForNote:newNote];

	directoryChangesFound = YES;

	return newNote;
}

- (void)addNotesFromSync:(NSArray *)noteArray {

	if (![noteArray count]) return;

	unsigned int i;

	if ([[self undoManager] isUndoing]) [undoManager beginUndoGrouping];
	for (i = 0; i < [noteArray count]; i++) {
		NoteObject *note = noteArray[i];

		[self _addNote:note];

		[note makeNoteDirtyUpdateTime:NO updateFile:YES];

		//absolutely ensure that this note is pushed to the rest of the services
		[note registerModificationWithOwnedServices];
		[self schedulePushToAllSyncServicesForNote:note];
	}
	if ([[self undoManager] isUndoing]) [undoManager endUndoGrouping];
	//don't need to reverse-register undo because removeNote/s: will never use this method

	[self updateTitlePrefixConnections];

	[self synchronizeNoteChanges:nil];

	[self resortAllNotes];
	[self refilterNotes];
}

- (void)addNotes:(NSArray *)noteArray {

	if (![noteArray count]) return;

	unsigned int i;

	if ([[self undoManager] isUndoing]) [undoManager beginUndoGrouping];
	for (i = 0; i < [noteArray count]; i++) {
		NoteObject *note = noteArray[i];

		[self _addNote:note];

		[note makeNoteDirtyUpdateTime:YES updateFile:YES];
	}
	if ([[self undoManager] isUndoing]) [undoManager endUndoGrouping];

	[self updateTitlePrefixConnections];

	[self synchronizeNoteChanges:nil];

	if ([[self undoManager] isUndoing]) {
		//prohibit undoing of creation--only redoing of deletion
		//NSLog(@"registering %s", _cmd);
		[undoManager registerUndoWithTarget:self selector:@selector(removeNotes:) object:noteArray];
		if (![[self undoManager] isUndoing] && ![[self undoManager] isRedoing])
			[undoManager setActionName:[NSString stringWithFormat:NSLocalizedString(@"Add %d Notes", @"undo action name for creating multiple notes"), [noteArray count]]];
	}
	[self resortAllNotes];
	[self refilterNotes];

	id <NotationControllerDelegate> delegate = self.delegate;
	if ([noteArray count] > 1)
		[delegate notation:self revealNotes:noteArray];
	else
		[delegate notation:self revealNote:[noteArray lastObject] options:NVOrderFrontWindow];
}

- (void)note:(NoteObject *)note attributeChanged:(NSString *)attribute {
	id <NotationControllerDelegate> delegate = self.delegate;

	if ([attribute isEqualToString:NotePreviewString]) {
		if ([prefsController tableColumnsShowPreview]) {
			NSUInteger idx = [self.filteredNotesList indexOfObjectIdenticalTo:note];
			if (NSNotFound != idx) {
				[delegate rowShouldUpdate:idx];
			}
		}
		//this attribute is not displayed as a column
		return;
	}

	//[self scheduleUpdateListForAttribute:attribute];
	[self performSelector:@selector(scheduleUpdateListForAttribute:) withObject:attribute afterDelay:0.0];

	//special case for title requires this method, as app controller needs to know a few note-specific things
	if ([attribute isEqualToString:NoteTitleColumnString]) {
		[delegate titleUpdatedForNote:note];

		//also update notationcontroller's psuedo-prefix tree for autocompletion
		[self updateTitlePrefixConnections];
		//should perhaps instead trigger a coalesced notification that also updates wiki-link-titles
	}
}

- (BOOL)openFiles:(NSArray *)filenames {
	//reveal notes that already exist with any of these filenames
	//for paths left over that weren't in the notes-folder/database, import those files as new notes

	if (![filenames count]) return NO;

	NSArray *unknownPaths = filenames; //(this is not a requirement for -notesWithFilenames:unknownFiles:)

	if ([self currentNoteStorageFormat] != SingleDatabaseFormat) {
		//notes are stored as separate files, so if these paths are in the notes folder then NV can claim ownership over them

		//probably should sync directory here to make sure notesWithFilenames has the freshest data
		[self synchronizeNotesFromDirectory];

		NSSet *existingNotes = [self notesWithFilenames:filenames unknownFiles:&unknownPaths];
		id <NotationControllerDelegate> delegate = self.delegate;
		if ([existingNotes count] > 1) {
			[delegate notation:self revealNotes:[existingNotes allObjects]];
			return YES;
		} else if ([existingNotes count] == 1) {
			[delegate notation:self revealNote:[existingNotes anyObject] options:NVEditNoteToReveal];
			return YES;
		}
	}
	//NSLog(@"paths not found in DB: %@", unknownPaths);
	NSArray *createdNotes = [[[AlienNoteImporter alloc] initWithStoragePaths:unknownPaths] importedNotes];
	if (!createdNotes) return NO;

	[self addNotes:createdNotes];

	return YES;
}


- (void)scheduleUpdateListForAttribute:(NSString *)attribute {

	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(scheduleUpdateListForAttribute:) object:attribute];

	if ([[sortColumn identifier] isEqualToString:attribute]) {
		id <NotationControllerDelegate> delegate = self.delegate;
		if ([delegate notationListShouldChange:self]) {
			[self sortAndRedisplayNotes];
		} else {
			[self performSelector:@selector(scheduleUpdateListForAttribute:) withObject:attribute afterDelay:1.5];
		}
	} else {
		//catch col updates even if they aren't the sort key

		NSEnumerator *enumerator = [[prefsController visibleTableColumns] objectEnumerator];
		NSString *colIdentifier = nil;

		//check to see if appropriate col is visible
		while ((colIdentifier = [enumerator nextObject])) {
			if ([colIdentifier isEqualToString:attribute]) {
				id <NotationControllerDelegate> delegate = self.delegate;
				if ([delegate notationListShouldChange:self]) {
					[delegate notationListMightChange:self];
					[delegate notationListDidChange:self];
				} else {
					[self performSelector:@selector(scheduleUpdateListForAttribute:) withObject:attribute afterDelay:1.5];
				}
				break;
			}
		}
	}
}

- (void)scheduleWriteForNote:(NoteObject *)note {

	if ([allNotes containsObject:note]) {

		BOOL immediately = NO;
		notesChanged = YES;

		[unwrittenNotes addObject:note];

		//always synchronize absolutely no matter what 15 seconds after any change
		if (!changeWritingTimer)
			changeWritingTimer = [NSTimer scheduledTimerWithTimeInterval:(immediately ? 0.0 : 15.0) target:self
																selector:@selector(synchronizeNoteChanges:)
																userInfo:nil repeats:NO];

		//next user change always invalidates queued write from performSelector, but not queued write from timer
		//this avoids excessive writing and any potential and unnecessary disk access while user types
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(synchronizeNoteChanges:) object:nil];

		if (walWriter) {
			//perhaps a more general user interface activity timer would be better for this? update process syncs every 30 secs, anyway...
			[NSObject cancelPreviousPerformRequestsWithTarget:walWriter selector:@selector(synchronize) object:nil];
			//fsyncing WAL to disk can cause noticeable interruption when run from main thread
			[walWriter performSelector:@selector(synchronize) withObject:nil afterDelay:15.0];
		}

		if (!immediately) {
			//timer is already scheduled if immediately is true
			//queue to write 2.7 seconds after last user change;
			[self performSelector:@selector(synchronizeNoteChanges:) withObject:nil afterDelay:2.7];
		}
	} else {
		NSLog(@"not writing note %@ because it is not controlled by NoteController", note);
	}
}

//the gatekeepers!
- (void)_addNote:(NoteObject *)aNoteObject {
	[aNoteObject setDelegate:self];

	[allNotes addObject:aNoteObject];
	[deletedNotes removeObject:aNoteObject];

	notesChanged = YES;
}

//the gateway methods must always show warnings, or else flash overlay window if show-warnings-pref is off
- (void)removeNotes:(NSArray *)noteArray {
	NSEnumerator *enumerator = [noteArray objectEnumerator];
	NoteObject *note;

	[undoManager beginUndoGrouping];
	while ((note = [enumerator nextObject])) {
		[self removeNote:note];
	}
	[undoManager endUndoGrouping];
	if (![[self undoManager] isUndoing] && ![[self undoManager] isRedoing])
		[undoManager setActionName:[NSString stringWithFormat:NSLocalizedString(@"Delete %d Notes", @"undo action name for deleting notes"), [noteArray count]]];

}

- (void)removeNote:(NoteObject *)aNoteObject {
	//reset linking labels and their notes


	[aNoteObject disconnectLabels];
	[aNoteObject abortEditingInExternalEditor];

	[allNotes removeObjectIdenticalTo:aNoteObject];
	DeletedNoteObject *deletedNote = [self _addDeletedNote:aNoteObject];

	updateForVerifiedDeletedNote(deletionManager, aNoteObject);

	notesChanged = YES;

	//force-write any cached note changes to make sure that their LSNs are smaller than this deleted note's LSN
	[self synchronizeNoteChanges:nil];

	//we do this after removing it from the array to avoid re-discovering a removed file
	if ([notationPrefs notesStorageFormat] != SingleDatabaseFormat) {
		[aNoteObject removeFileFromDirectory];
	}
	//add journal removal event
	if (walWriter && ![walWriter writeRemovalForNote:aNoteObject]) {
		NSLog(@"Couldn't log note removal");
	}

	//a removal command will be sent to sync services if aNoteObject contains a matching syncServicesMD dict
	//(e.g., already been synced at least once)
	//make sure we use the same deleted note that was added to the list of deleted notes, to simplify record-keeping
	//if the note didn't have metadata, try to sync it anyway so that the service knows this note shouldn't be created
	[self schedulePushToAllSyncServicesForNote:deletedNote ? deletedNote : [DeletedNoteObject deletedNoteWithNote:aNoteObject]];

	[self _registerDeletionUndoForNote:aNoteObject];

	//delete note from bookmarks, too
	[[prefsController bookmarksController] removeBookmarkForNote:aNoteObject];

	//rebuild the prefix tree, as this note may have been a prefix of another, or vise versa
	[self updateTitlePrefixConnections];


	[self refilterNotes];
}

- (void)_purgeAlreadyDistributedDeletedNotes {
	//purge deletedNotes of objects without any more syncMD entries;
	//once a note has been deleted from all services, there's no need to keep it around anymore

	NSUInteger i = 0;
	NSArray *dnArray = [deletedNotes allObjects];
	for (i = 0; i < [dnArray count]; i++) {
		DeletedNoteObject *dnObj = dnArray[i];
		if (![[dnObj syncServicesMD] count]) {
			[deletedNotes removeObject:dnObj];
			notesChanged = YES;
		}
	}
	//NSLog(@"%s: deleted notes left: %@", _cmd, deletedNotes);
}

- (DeletedNoteObject *)_addDeletedNote:(id <SynchronizedNote>)aNote {
	//currently coupled to -[allNotes removeObjectIdenticalTo:]
	//don't need to remember this deleted note unless it was already synced with some service
	//furthermore, after that deleted note has been remotely-removed from all services with which it was previously synced,
	//can it be purged from this database once and for all?
	//e.g., each successful syncservice deletion would also remove that service's entry from syncServicesMD
	//when syncServicesMD was empty, it would be removed from the set
	//but what about synchronization systems without explicit delete APIs?

	if ([[aNote syncServicesMD] count]) {
		//it is important to use the actual deleted note if one is passed
		DeletedNoteObject *deletedNote = [aNote isKindOfClass:[DeletedNoteObject class]] ? aNote : [DeletedNoteObject deletedNoteWithNote:aNote];
		[deletedNotes addObject:deletedNote];
		notesChanged = YES;
		return deletedNote;
	}
	return nil;
}

- (void)removeSyncMDFromDeletedNotesInSet:(NSSet *)notesToOrphan forService:(NSString *)serviceName {
	NSMutableSet *matchingNotes = [deletedNotes setIntersectedWithSet:notesToOrphan];
	[matchingNotes makeObjectsPerformSelector:@selector(removeAllSyncMDForService:) withObject:serviceName];
}

- (void)_registerDeletionUndoForNote:(NoteObject *)aNote {
	[undoManager registerUndoWithTarget:self selector:@selector(addNewNote:) object:aNote];
	if (![undoManager isUndoing] && ![undoManager isRedoing])
		[undoManager setActionName:[NSString stringWithFormat:NSLocalizedString(@"Delete quotemark%@quotemark", @"undo action name for deleting a single note"), aNote.title]];
}


- (void)setUndoManager:(NSUndoManager *)anUndoManager {
	undoManager = anUndoManager;
}

- (NSUndoManager *)undoManager {
	return undoManager;
}

- (void)updateDateStringsIfNecessary {

	unsigned int currentHours = hoursFromAbsoluteTime(CFAbsoluteTimeGetCurrent());
	BOOL isHorizontalLayout = [prefsController horizontalLayout];

	if (currentHours != lastCheckedDateInHours || isHorizontalLayout != lastLayoutStyleGenerated) {
		lastCheckedDateInHours = currentHours;
		lastLayoutStyleGenerated = (int) isHorizontalLayout;

		id <NotationControllerDelegate> delegate = self.delegate;

		[delegate notationListMightChange:self];
		resetCurrentDayTime();
		[allNotes makeObjectsPerformSelector:@selector(updateDateStrings)];
		[delegate notationListDidChange:self];
	}
}

- (void)makeForegroundTextColorMatchGlobalPrefs {
	NSColor *prefsFGColor = [notationPrefs foregroundColor];
	if (prefsFGColor) {
		NSColor *fgColor = [[NSApp delegate] foregrndColor];
		[self setForegroundTextColor:fgColor];
		//NSColor *fgColor = [prefsController foregroundTextColor];

		//if (!ColorsEqualWith8BitChannels(prefsFGColor, fgColor)) {
		//	[self setForegroundTextColor:fgColor];
		//}
	}
}

- (void)setForegroundTextColor:(NSColor *)fgColor {
	//do not update the notes in any other way, nor the database, other than also setting this color in notationPrefs
	//foreground color is archived only for practicality, and should be for display only
	NSAssert(fgColor != nil, @"foreground color cannot be nil");

	[allNotes makeObjectsPerformSelector:@selector(setForegroundTextColorOnly:) withObject:fgColor];

	[notationPrefs setForegroundTextColor:fgColor];
}

- (void)restyleAllNotes {
	NSFont *baseFont = [notationPrefs baseBodyFont];
	NSAssert(baseFont != nil, @"base body font from notation prefs should ALWAYS be valid!");

	[allNotes makeObjectsPerformSelector:@selector(updateUnstyledTextWithBaseFont:) withObject:baseFont];

	[notationPrefs setBaseBodyFont:[prefsController noteBodyFont]];
}

//used by BookmarksController

- (NoteObject *)noteForUUIDBytes:(CFUUIDBytes *)bytes {
	NSUInteger noteIndex = [allNotes indexOfNoteWithUUIDBytes:bytes];
	if (noteIndex != NSNotFound) return allNotes[noteIndex];
	return nil;
}

- (void)updateLabelConnectionsAfterDecoding {
	[allNotes makeObjectsPerformSelector:@selector(updateLabelConnectionsAfterDecoding)];
}

//re-searching for all notes each time a label is added or removed is unnecessary, I think
- (void)note:(NoteObject *)note didAddLabelSet:(NSSet *)labelSet {
	[self.allLabels unionSet:labelSet];

	NSMutableSet *existingLabels = [self.allLabels setIntersectedWithSet:labelSet];
	[existingLabels makeObjectsPerformSelector:@selector(addNote:) withObject:note];
	[note replaceMatchingLabelSet:existingLabels]; //link back for the existing note, so that it knows about the other notes in this label
}

- (void)note:(NoteObject *)note didRemoveLabelSet:(NSSet *)labelSet {
	[self.allLabels minusSet:labelSet];

	//we narrow down the set to make sure that we operate on the actual objects within it, and note the objects used as prototypes
	//these will be any labels that were shared by notes other than this one
	NSMutableSet *existingLabels = [self.allLabels setIntersectedWithSet:labelSet];
	[existingLabels makeObjectsPerformSelector:@selector(removeNote:) withObject:note];

	//[self refilterNotes];
}

- (BOOL)filterNotesFromString:(NSString *)string {
	id <NotationControllerDelegate> delegate = self.delegate;

	[delegate notationListMightChange:self];
	if ([self filterNotesFromUTF8String:string.lowercaseString.UTF8String forceUncached:NO]) {
		[delegate notationListDidChange:self];

		return YES;
	}

	return NO;
}

- (void)refilterNotes {
	id <NotationControllerDelegate> delegate = self.delegate;
	[delegate notationListMightChange:self];
	[self filterNotesFromUTF8String:(currentFilterStr ? currentFilterStr : "") forceUncached:YES];
	[delegate notationListDidChange:self];
}

- (BOOL)filterNotesFromUTF8String:(const char *)searchString forceUncached:(BOOL)forceUncached {
	BOOL stringHasExistingPrefix = YES;
	BOOL didFilterNotes = NO;
	size_t oldLen = 0, newLen = 0;
	NSUInteger initialCount = [self.filteredNotesList count];

	NSAssert(searchString != NULL, @"filterNotesFromUTF8String requires a non-NULL argument");

	newLen = strlen(searchString);

	//PHASE 1: determine whether notes can be searched from where they are--if not, start on all the notes
	if (!currentFilterStr || forceUncached || ((oldLen = strlen(currentFilterStr)) > newLen) ||
			strncmp(currentFilterStr, searchString, oldLen)) {

		//the search must be re-initialized; our strings don't have the same prefix

		[self.filteredNotesList setArray:allNotes];

		stringHasExistingPrefix = NO;
		lastWordInFilterStr = 0;
		didFilterNotes = YES;

		//		NSLog(@"filter: scanning all notes");
	}


	//PHASE 2: actually search for notes
	NoteFilterContext filterContext;

	//if there is a quote character in the string, use that as a delimiter, as we will search by phrase
	//perhaps we could add some additional delimiters like punctuation marks here
	char *token, *separators = (strchr(searchString, '"') ? "\"" : " :\t\r\n");
	manglingString = replaceString(manglingString, searchString);

	if (!didFilterNotes || newLen > 0) {
		//only bother searching each note if we're actually searching for something
		//otherwise, filtered notes already reflect all-notes-state

		char *preMangler = manglingString + lastWordInFilterStr;
		while ((token = strsep(&preMangler, separators))) {

			if (*token != '\0') {
				//if this is the same token that we had scanned previously
				filterContext.useCachedPositions = stringHasExistingPrefix && (token == manglingString + lastWordInFilterStr);
				filterContext.needle = token;

				NSMutableArray *newArray = [NSMutableArray arrayWithCapacity:self.filteredNotesList.count];

				for (id obj in self.filteredNotesList) {
					if (noteContainsUTF8String(obj, &filterContext)) {
						[newArray addObject:obj];
					}
				}

				if (newArray.count < self.filteredNotesList.count) {
					[self.filteredNotesList setArray:newArray];
					didFilterNotes = YES;
				}

				lastWordInFilterStr = token - manglingString;
			}
		}
	}

	//PHASE 4: autocomplete based on results
	//even if the controller didn't filter, the search string could have changed its representation wrt spacing
	//which will still influence note title prefixes
	selectedNoteIndex = NSNotFound;

	if (newLen && [prefsController autoCompleteSearches]) {
		[self.filteredNotesList enumerateObjectsUsingBlock:^(NoteObject *note, NSUInteger i, BOOL *stop) {
			//because we already searched word-by-word up there, this is just way simpler
			if (noteTitleHasPrefixOfUTF8String(note, searchString, newLen)) {
				selectedNoteIndex = i;
				//this note matches, but what if there are other note-titles that are prefixes of both this one and the search string?
				//find the first prefix-parent of which searchString is also a prefix
				NSUInteger prefixParentIndex = NSNotFound;

				for (NoteObject *obj in note.prefixParents) {
					if (noteTitleHasPrefixOfUTF8String(obj, searchString, newLen) &&
							(prefixParentIndex = [self.filteredNotesList indexOfObjectIdenticalTo:obj]) != NSNotFound) {
						//figure out where this prefix parent actually is in the list--if it actually is in the list, that is
						//otherwise look at the next prefix parent, etc.
						//the prefix parents array should always be alpha-sorted, so the shorter prefixes will always be first
						selectedNoteIndex = prefixParentIndex;
						break;
					}
				}

				*stop = YES;
			}
		}];
	}

	currentFilterStr = replaceString(currentFilterStr, searchString);

	if (!initialCount && initialCount == self.filteredNotesList.count)
		return NO;

	return didFilterNotes;
}

- (NSUInteger)preferredSelectedNoteIndex {
	return selectedNoteIndex;
}

- (NSArray *)noteTitlesPrefixedByString:(NSString *)prefixString indexOfSelectedItem:(NSInteger *)anIndex {
	NSMutableArray *objs = [NSMutableArray arrayWithCapacity:[allNotes count]];
	const char *searchString = prefixString.lowercaseString.UTF8String;
	NSUInteger i, titleLen, strLen = strlen(searchString), j = 0, shortestTitleLen = UINT_MAX;

	for (i = 0; i < [allNotes count]; i++) {
		NoteObject *thisNote = allNotes[i];
		if (noteTitleHasPrefixOfUTF8String(thisNote, searchString, strLen)) {
			[objs addObject:thisNote.title];
			if (anIndex && (titleLen = thisNote.title.length) < shortestTitleLen) {
				*anIndex = j;
				shortestTitleLen = titleLen;
			}
			j++;
		}
	}
	return objs;
}

- (NoteObject *)noteObjectAtFilteredIndex:(NSUInteger)noteIndex {
	if (noteIndex < self.filteredNotesList.count)
		return self.filteredNotesList[noteIndex];
	return nil;
}

- (NSArray *)notesAtIndexes:(NSIndexSet *)indexSet {
	return [self.filteredNotesList objectsAtIndexes:indexSet];
}

//O(n^2) at best, but at least we're dealing with C arrays

- (NSIndexSet *)indexesOfNotes:(NSArray *)noteArray {
	return [self.filteredNotesList indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
		return ([noteArray indexOfObjectIdenticalTo:obj] != NSNotFound);
	}];
}

- (NSUInteger)indexInFilteredListForNoteIdenticalTo:(NoteObject *)note {
	return [self.filteredNotesList indexOfObjectIdenticalTo:note];
}

- (NSUInteger)totalNoteCount {
	return [allNotes count];
}

- (NoteAttributeColumn *)sortColumn {
	return sortColumn;
}

- (void)setSortColumn:(NoteAttributeColumn *)col {

	sortColumn = col;

	[self sortAndRedisplayNotes];
}

//re-sort without refiltering, to avoid removing notes currently being edited
- (void)sortAndRedisplayNotes {
	id <NotationControllerDelegate> delegate = self.delegate;
	[delegate notationListMightChange:self];

	NoteAttributeColumn *col = sortColumn;
	if (col) {
		BOOL reversed = [prefsController tableIsReverseSorted];
		NSInteger (*sortFunction)(id *, id *) = (reversed ? col.reverseSortingFunction : col.sortingFunction);
		NSInteger (*stringSortFunction)(id *, id *) = (reversed ? compareTitleStringReverse : compareTitleString);

		[allNotes sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(id obj1, id obj2) {
			return stringSortFunction(&obj1, &obj2);
		}];

		if (sortFunction != stringSortFunction) {
			[allNotes sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(id obj1, id obj2) {
				return sortFunction(&obj1, &obj2);
			}];
		}


		if (self.filteredNotesList.count != [allNotes count]) {

			[self.filteredNotesList sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(id obj1, id obj2) {
				return stringSortFunction(&obj1, &obj2);
			}];

			if (sortFunction != stringSortFunction) {
				[self.filteredNotesList sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(id obj1, id obj2) {
					return sortFunction(&obj1, &obj2);
				}];
			}

		} else {
			//mirror from allNotes; filteredNotesList is not filtered
			[self.filteredNotesList setArray:allNotes];
		}

		[delegate notationListDidChange:self];
	}
}

- (void)resortAllNotes {

	NoteAttributeColumn *col = sortColumn;

	if (col) {
		BOOL reversed = [prefsController tableIsReverseSorted];

		NSInteger (*sortFunction)(id *, id *) = (reversed ? col.reverseSortingFunction : col.sortingFunction);
		NSInteger (*stringSortFunction)(id *, id *) = (reversed ? compareTitleStringReverse : compareTitleString);

		[allNotes sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(id obj1, id obj2) {
			return stringSortFunction(&obj1, &obj2);
		}];

		if (sortFunction != stringSortFunction) {
			[allNotes sortWithOptions:NSSortStable usingComparator:^NSComparisonResult(id obj1, id obj2) {
				return sortFunction(&obj1, &obj2);
			}];
		}
	}
}

- (float)titleColumnWidth {
	return titleColumnWidth;
}

- (void)regeneratePreviewsForColumn:(NSTableColumn *)col visibleFilteredRows:(NSRange)rows forceUpdate:(BOOL)force {

	float width = [col width] - [NSScroller scrollerWidthForControlSize:NSRegularControlSize];

	if (force || roundf(width) != roundf(titleColumnWidth)) {
		titleColumnWidth = width;

		//regenerate previews for visible rows immediately and post a delayed message to regenerate previews for all rows
		if (rows.length > 0) {
			[[self.filteredNotesList objectsAtIndexes:[NSIndexSet indexSetWithIndexesInRange:rows]] makeObjectsPerformSelector:@selector(updateTablePreviewString)];
		}

		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(regenerateAllPreviews) object:nil];
		[self performSelector:@selector(regenerateAllPreviews) withObject:nil afterDelay:0.0];
	}
}

- (void)regenerateAllPreviews {
	[allNotes makeObjectsPerformSelector:@selector(updateTablePreviewString)];
}

- (NotationPrefs *)notationPrefs {
	return notationPrefs;
}

- (SyncSessionController *)syncSessionController {
	return syncSessionController;
}

- (void)invalidateCachedLabelImages {
	//used when the list font size changes
	if (!self.labelImages) [self.labelImages removeAllObjects];
}

- (NSImage *)cachedLabelImageForWord:(NSString *)aWord highlighted:(BOOL)isHighlighted {
	if (!self.labelImages) self.labelImages = [[NSMutableDictionary alloc] init];

	NSString *imgKey = [[aWord lowercaseString] stringByAppendingFormat:@", %d", isHighlighted];
	NSImage *img = self.labelImages[imgKey];
	if (!img) {
		//generate the image and add it to labelImages under imgKey
		float tableFontSize = [[GlobalPrefs defaultPrefs] tableFontSize] - 1.0;

		NSDictionary *attrs = @{NSFontAttributeName : [NSFont systemFontOfSize:tableFontSize]};
		NSSize wordSize = [aWord sizeWithAttributes:attrs];
		NSRect wordRect = NSMakeRect(0, 0, roundf(wordSize.width + 4.0), roundf(tableFontSize * 1.3));

		//peter hosey's suggestion, rather than doing setWindingRule: and appendBezierPath: as before:
		//http://stackoverflow.com/questions/4742773/why-wont-helvetica-neue-bold-glyphs-draw-as-a-normal-subpath-in-nsbezierpath

		img = [[NSImage alloc] initWithSize:wordRect.size];
		[img lockFocus];

		CGContextRef context = (CGContextRef) ([[NSGraphicsContext currentContext] graphicsPort]);
		CGContextBeginTransparencyLayer(context, NULL);

		CGContextClipToRect(context, NSRectToCGRect(wordRect));

		NSBezierPath *backgroundPath = [NSBezierPath bezierPathWithRoundRectInRect:wordRect radius:2.0f];
		[(isHighlighted ? [NSColor whiteColor] : [NSColor colorWithCalibratedWhite:0.55 alpha:1.0]) setFill];
		[backgroundPath fill];

		[[NSGraphicsContext currentContext] setCompositingOperation:NSCompositeSourceOut];
		[aWord drawWithRect:(NSRect) {{2.0, 3.0}, wordRect.size} options:NSStringDrawingUsesFontLeading attributes:attrs];

		CGContextEndTransparencyLayer(context);

		[img unlockFocus];

		self.labelImages[imgKey] = img;
	}
	return img;
}

- (void)dealloc {

	[notationPrefs setDelegate:nil];
	for (NoteObject *note in allNotes) {
		note.delegate = nil;
	}

	if (fsCatInfoArray)
		free(fsCatInfoArray);
	if (HFSUniNameArray)
		free(HFSUniNameArray);
}

#pragma mark - 

- (NSArray *)labelTitlesPrefixedByString:(NSString *)prefix indexOfSelectedItem:(NSInteger *)anIndex minusWordSet:(NSSet *)antiSet {

	NSMutableArray *objs = [self.allLabels.allObjects mutableCopy];
	NSMutableArray *titles = [NSMutableArray arrayWithCapacity:self.allLabels.count];

	[objs sortUsingComparator:^NSComparisonResult(id obj1, id obj2) {
		return compareLabel(&obj1, &obj2);
	}];

	NSUInteger titleLen, j = 0, shortestTitleLen = UINT_MAX;

	for (LabelObject *label in objs) {
		NSString *title = titleOfLabel(label);

		if ([title rangeOfString:prefix options:NSCaseInsensitiveSearch | NSAnchoredSearch range:NSMakeRange(0, prefix.length)].location != NSNotFound) {
			if (![antiSet containsObject:title]) {
				[titles addObject:title];
				if (anIndex && (titleLen = title.length) < shortestTitleLen) {
					*anIndex = j;
					shortestTitleLen = titleLen;
				}
				j++;
			}
		}
	}

	return titles;
}

- (void)syncSettingsChangedForService:(NSString *)serviceName {

	//reset credentials
	[syncSessionController invalidateSyncService:serviceName];

	//reset timer and prepare for the next sync
	[NSObject cancelPreviousPerformRequestsWithTarget:syncSessionController selector:@selector(initializeService:) object:serviceName];
	[syncSessionController performSelector:@selector(initializeService:) withObject:serviceName afterDelay:2];

}

#pragma mark - NSTableViewDataSource

#pragma mark -
#pragma mark ***** Required Methods (unless bindings are used) *****

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
	return self.filteredNotesList.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
	NoteAttributeColumn *col = (NoteAttributeColumn *) tableColumn;
	if (!col.attributeFunction) return nil;
	return col.attributeFunction(tableView, self.filteredNotesList[row], row);
}

#pragma mark - NSTableViewDataSource (Optional)

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
	//allow the tableview to override the selector destination for this object value
	NoteAttributeColumn *col = (NoteAttributeColumn *) tableColumn;
	SEL colAttributeMutator = [(NotesTableView *) tableView attributeSetterForColumn:col];
	objc_msgSend(self.filteredNotesList[row], colAttributeMutator ? colAttributeMutator : col.mutatingSelector, object);
}

//- (void)tableView:(NSTableView *)tableView sortDescriptorsDidChange:(NSArray *)oldDescriptors;
//- (id <NSPasteboardWriting>)tableView:(NSTableView *)tableView pasteboardWriterForRow:(NSInteger)row NS_AVAILABLE_MAC(10_7);
//- (void)tableView:(NSTableView *)tableView draggingSession:(NSDraggingSession *)session willBeginAtPoint:(NSPoint)screenPoint forRowIndexes:(NSIndexSet *)rowIndexes NS_AVAILABLE_MAC(10_7);
//- (void)tableView:(NSTableView *)tableView draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)screenPoint operation:(NSDragOperation)operation NS_AVAILABLE_MAC(10_7);
//- (void)tableView:(NSTableView *)tableView updateDraggingItemsForDrag:(id <NSDraggingInfo>)draggingInfo NS_AVAILABLE_MAC(10_7);
//- (BOOL)tableView:(NSTableView *)tableView writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard *)pboard;
//- (NSDragOperation)tableView:(NSTableView *)tableView validateDrop:(id <NSDraggingInfo>)info proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)dropOperation;
//- (BOOL)tableView:(NSTableView *)tableView acceptDrop:(id <NSDraggingInfo>)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)dropOperation;
//- (NSArray *)tableView:(NSTableView *)tableView namesOfPromisedFilesDroppedAtDestination:(NSURL *)dropDestination forDraggedRowsWithIndexes:(NSIndexSet *)indexSet;

#pragma mark - NotesObjectDelegate

- (void)noteDidUpdateContents:(NoteObject *)note {
	id <NotationControllerDelegate> delegate = self.delegate;
	[delegate contentsUpdatedForNote:note];
}

#pragma mark -

- (void)setNoteDatabaseURL:(NSURL *)noteDatabaseURL {
	if (noteDatabaseURL == _noteDatabaseURL) return;
	_noteDatabaseURL = noteDatabaseURL;
}

- (void)setNoteDirectoryURL:(NSURL *)noteDirectoryURL {
	if (noteDirectoryURL == _noteDirectoryURL) return;
	_noteDirectoryURL = noteDirectoryURL;
	
}

@end
