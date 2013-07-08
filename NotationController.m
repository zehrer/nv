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
#import "NoteObject.h"
#import "DeletedNoteObject.h"
#import "NSString_NV.h"
#import "NSFileManager_NV.h"
#import "BufferUtils.h"
#import "GlobalPrefs.h"
#import "NotationPrefs.h"
#import "NoteAttributeColumn.h"
#import "FrozenNotation.h"
#import "AlienNoteImporter.h"
#import "ODBEditor.h"
#import "NotationFileManager.h"
#import "NotationSyncServiceManager.h"
#import "NotationDirectoryManager.h"
#import "SyncSessionController.h"
#import "BookmarksController.h"
#import "DeletionManager.h"
#import "LabelObject.h"
#import "NoteObject.h"
#import "GlobalPrefs.h"
#import "NSBezierPath_NV.h"
#import "NSCollection_utils.h"
#import "NoteAttributeColumn.h"
#import "nvaDevConfig.h"
#import "NSMutableOrderedSet+NVFiltering.h"
#import <objc/message.h>

inline NSComparisonResult NVComparisonResult(NSInteger result) {
	if (result < 0) return NSOrderedAscending;
	if (result > 0) return NSOrderedDescending;
	return NSOrderedSame;
}

@interface NotationController ()

@property (nonatomic, strong) NSMutableDictionary *labelImages;

@end

@implementation NotationController

- (id)init {
    if (self = [super init]) {
		directoryChangesFound = notesChanged = aliasNeedsUpdating = NO;
		
		allNotes = [[NSMutableArray alloc] init]; //<--the authoritative list of all memory-accessible notes
		deletedNotes = [[NSMutableSet alloc] init];
		prefsController = [GlobalPrefs defaultPrefs];
		notesList = [[NSMutableOrderedSet alloc] init];
		deletionManager = [[DeletionManager alloc] initWithNotationController:self];
		
		selectedNoteIndex = NSNotFound;
		
		fsCatInfoArray = NULL;
		HFSUniNameArray = NULL;
		catalogEntries = NULL;
		sortedCatalogEntries = NULL;
		catEntriesCount = totalCatEntriesCount = 0;

		bzero(&noteDatabaseRef, sizeof(FSRef));
		bzero(&noteDirectoryRef, sizeof(FSRef));
		volumeSupportsExchangeObjects = -1;
		
		lastLayoutStyleGenerated = -1;
		lastCheckedDateInHours = hoursFromAbsoluteTime(CFAbsoluteTimeGetCurrent());
		blockSize = 0;
		
		lastWriteError = noErr;
		unwrittenNotes = [[NSMutableSet alloc] init];
		_allLabels = [[NSCountedSet alloc] init];
    }
    return self;
}


- (id)initWithAliasData:(NSData*)data error:(OSStatus*)err {
    OSStatus anErr = noErr;
    
    if (data && (anErr = PtrToHand([data bytes], (Handle*)&aliasHandle, [data length])) == noErr) {	
        FSRef targetRef;
        Boolean changed;
        
        if ((anErr = FSResolveAliasWithMountFlags(NULL, aliasHandle, &targetRef, &changed, 0)) == noErr) {
            if (self = [self initWithDirectoryRef:&targetRef error:&anErr]) {
                aliasNeedsUpdating = changed;
                *err = noErr;
                
                return self;
            }
        }
    }
    
    *err = anErr;
    
    return nil;
}

- (id)initWithDefaultDirectoryReturningError:(OSStatus*)err {
    FSRef targetRef;
    
    OSStatus anErr = noErr;
    if ((anErr = [NotationController getDefaultNotesDirectoryRef:&targetRef]) == noErr) {
		
		if ((self = [self initWithDirectoryRef:&targetRef error:&anErr])) {
			*err = noErr;
			return self;
		}
    }
    
    *err = anErr;
    
    return nil;
}

- (id)initWithDirectoryRef:(FSRef*)directoryRef error:(OSStatus*)err {
    
    *err = noErr;
    
    if (self = [self init]) {
		aliasNeedsUpdating = YES; //we don't know if we have an alias yet
		
		noteDirectoryRef = *directoryRef;
		
		//check writable and readable perms, warning user if necessary
		
		//first read cache file
		OSStatus anErr = noErr;
		if ((anErr = [self _readAndInitializeSerializedNotes]) != noErr) {
			*err = anErr;
			return nil;
		}
		
		//set up the directory subscription, if necessary
		//and sync based on notes in directory and their mod. dates
		[self databaseSettingsChangedFromOldFormat:[notationPrefs notesStorageFormat]];
		if (!walWriter) {
			*err = kJournalingError;
			return nil;
		}
		
		[self upgradeDatabaseIfNecessary];
		
		[self updateTitlePrefixConnections];
    }
    
    return self;
}

- (id)delegate {
	return delegate;
}

- (void)setDelegate:(id)theDelegate {
	
	delegate = theDelegate;

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
			(void)[self renameAndForgetNoteDatabaseFile:@"Notes & Settings (old version from 2.0b)"];
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


- (OSStatus)_readAndInitializeSerializedNotes {

    OSStatus err = noErr;
	if ((err = [self createFileIfNotPresentInNotesDirectory:&noteDatabaseRef forFilename:NotesDatabaseFileName fileWasCreated:nil]) != noErr)
		return err;
	
	UInt64 fileSize = 0;
	char *notesData = NULL;
	if ((err = FSRefReadData(&noteDatabaseRef, BlockSizeForNotation(self), &fileSize, (void**)&notesData, noCacheMask)) != noErr)
		return err;
	
	FrozenNotation *frozenNotation = nil;
	
	if (fileSize > 0) {
		NSData *archivedNotation = [[NSData alloc] initWithBytesNoCopy:notesData length:fileSize freeWhenDone:NO];
		@try {
			frozenNotation = [NSKeyedUnarchiver unarchiveObjectWithData:archivedNotation];
		} @catch (NSException *e) {
			NSLog(@"Error unarchiving notes and preferences from data (%@, %@)", [e name], [e reason]);
			
			if (notesData)
				free(notesData);
			
			//perhaps this shouldn't be an error, but the user should instead have the option of overwriting the DB with a new one?
			return kCoderErr;
		}
	
	}
	
	
	
	if (!(notationPrefs = frozenNotation.prefs))
		notationPrefs = [[NotationPrefs alloc] init];
	[notationPrefs setDelegate:self];

	//notationPrefs will have the index of the current disk UUID (or we will add it otherwise) 
	//which will be used to determine which attr-mod-time to use for each note after decoding
	[self initializeDiskUUIDIfNecessary];
	
	
	syncSessionController = [[SyncSessionController alloc] initWithSyncDelegate:self notationPrefs:notationPrefs];
	
	//frozennotation will work out passwords, keychains, decryption, etc...
	if (!(allNotes = [frozenNotation unpackedNotesReturningError:&err])) {
		//notes could be nil because the user cancelled password authentication
		//or because they were corrupted, or for some other reason
		if (err != noErr)
			return err;
		
		allNotes = [[NSMutableArray alloc] init];
	} else {
		[allNotes makeObjectsPerformSelector:@selector(setDelegate:) withObject:self];
	}
	
	if (!(deletedNotes = [frozenNotation deletedNotes]))
	    deletedNotes = [[NSMutableSet alloc] init];
			
	[prefsController setNotationPrefs:notationPrefs sender:self];
	
	[self makeForegroundTextColorMatchGlobalPrefs];
	
	if(notesData)
	    free(notesData);
	
	return noErr;
}

- (BOOL)initializeJournaling {
    
    const UInt32 maxPathSize = 8 * 1024;
    const char *convertedPath = (char *)malloc(maxPathSize * sizeof(char));
    OSStatus err = noErr;
	NSData *walSessionKey = [notationPrefs WALSessionKey];
    
    //nvALT change to store Interim Note-Changes in ~/Library/Caches/
#if kUseCachesFolderForInterimNoteChanges
    NSString *cPath=[self createCachesFolder];
    if (cPath) {
        free((void *)convertedPath);
        convertedPath = [cPath UTF8String];
#else
    if ((err = FSRefMakePath(&noteDirectoryRef, convertedPath, maxPathSize)) == noErr) {
#endif
		//initialize the journal if necessary
		if (!(walWriter = [[WALStorageController alloc] initWithParentFSRep:convertedPath encryptionKey:walSessionKey])) {
			//journal file probably already exists, so try to recover it
			WALRecoveryController *walReader = [[WALRecoveryController alloc] initWithParentFSRep:convertedPath encryptionKey:walSessionKey];
			if (walReader) {
                
#if !kUseCachesFolderForInterimNoteChanges
                free((void *)convertedPath); convertedPath = NULL;
#endif
				
				BOOL databaseCouldNotBeFlushed = NO;
				NSMapTable *recoveredNotes = [walReader recoveredNotes];
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
				
				if (![walReader destroyLogFile]) {
					//couldn't delete the log file, so we can't create a new one
					NSLog(@"Unable to delete the old write-ahead-log file");
                    return NO;
				}
				
				if (!(walWriter = [[WALStorageController alloc] initWithParentFSRep:(char*)convertedPath encryptionKey:walSessionKey])) {
					//couldn't create a journal after recovering the old one
					//if databaseCouldNotBeFlushed is true here, then we've potentially lost notes; perhaps exchangeobjects would be better here?
					NSLog(@"Unable to create a new write-ahead-log after deleting the old one");
					return NO;
				}
				
				if ([recoveredNotes count] > 0) {
					if (databaseCouldNotBeFlushed) {
						//re-add the contents of recoveredNotes to walWriter; LSNs should take care of the order; no need to sort
						//this allows for an ever-growing journal in the case of broken database serialization
						//it should not be an acceptable condition for permanent use; hopefully an update would come soon
						//warn the user, perhaps
						[walWriter writeNoteObjects:NSAllMapTableValues(recoveredNotes)];
					}
					[self refilterNotes];
				}
			} else {
				NSLog(@"Unable to recover unsaved notes from write-ahead-log");
				//1) should we let the user attempt to remove it without recovery?
                free((void *)convertedPath); convertedPath = NULL;
                return NO;
			}
		}
		[walWriter setDelegate:self];
		
		return YES;
    } else {
		NSLog(@"FSRefMakePath error: %d", err);
        free((void *)convertedPath); convertedPath = NULL;
		return NO;
    }
}

//stick the newest unique recovered notes into allNotes
- (void)processRecoveredNotes:(NSMapTable *)table {
	NSMapEnumerator enumerator = NSEnumerateMapTable(table);
	CFUUIDBytes *objUUIDBytes = NULL;
	void *objectPtr = NULL;
	
	while (NSNextMapEnumeratorPair(&enumerator, (void **)&objUUIDBytes, &objectPtr)) {
		id<SynchronizedNote> obj = (__bridge id)objectPtr;
		NSUInteger existingNoteIndex = [allNotes indexOfNoteWithUUIDBytes:objUUIDBytes];
		
		if ([obj isKindOfClass:[DeletedNoteObject class]]) {
			
			if (existingNoteIndex != NSNotFound) {
				
				NoteObject *existingNote = [allNotes objectAtIndex:existingNoteIndex];
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
			
			if ([[allNotes objectAtIndex:existingNoteIndex] youngerThanLogObject:obj]) {
				// NSLog(@"replacing old note with new: %@", [[(NoteObject*)obj contentString] string]);
				
				[(NoteObject*)obj setDelegate:self];
				[(NoteObject*)obj updateLabelConnectionsAfterDecoding];
				[allNotes replaceObjectAtIndex:existingNoteIndex withObject:obj];
				notesChanged = YES;
			} else {
				// NSLog(@"note %@ is not being replaced because its LSN is %u, while the old note's LSN is %u",
				//  [[(NoteObject*)obj contentString] string], [(NoteObject*)obj logSequenceNumber], [[allNotes objectAtIndex:existingNoteIndex] logSequenceNumber]);
			}
		} else {
			//NSLog(@"Found new note: %@", [(NoteObject*)obj contentString]);
			
			[self _addNote:obj];
			[(NoteObject*)obj updateLabelConnectionsAfterDecoding];
		}
	}
	
	NSEndMapTableEnumeration(&enumerator);
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
		
		//purge attr-mod-times for old disk uuids here
		[self purgeOldPerDiskInfoFromNotes];
		
		
		NSData *serializedData = [FrozenNotation frozenDataWithExistingNotes:allNotes deletedNotes:deletedNotes prefs:notationPrefs];
		if (!serializedData) {
			
			NSLog(@"serialized data is nil!");
			return NO;
		}
		
		//we should have all journal records on disk by now
		//used to ensure a newly-written Notes & Settings file is valid before finalizing the save
		//read the file back from disk, deserialize it, decrypt and decompress it, and compare the notes roughly to our current notes
		if ([self storeDataAtomicallyInNotesDirectory:serializedData withName:NotesDatabaseFileName destinationRef:&noteDatabaseRef verifyUsingBlock:^OSStatus(FSRef *notesFileRef, NSString *filename) {
			NSDate *date = [NSDate date];
			
			NSAssert([filename isEqualToString:NotesDatabaseFileName], @"attempting to verify something other than the database");
			
			UInt64 fileSize = 0;
			char *notesData = NULL;
			OSStatus err = noErr;
			if ((err = FSRefReadData(notesFileRef, BlockSizeForNotation(self), &fileSize, (void**)&notesData, forceReadMask)) != noErr)
				return err;
			
			FrozenNotation *frozenNotation = nil;
			if (!fileSize) {
				if (notesData) free(notesData);
				return eofErr;
			}
			NSData *archivedNotation = [[NSData alloc] initWithBytesNoCopy:notesData length:fileSize freeWhenDone:NO];
			@try {
				frozenNotation = [NSKeyedUnarchiver unarchiveObjectWithData:archivedNotation];
			} @catch (NSException *e) {
				NSLog(@"(VERIFY) Error unarchiving notes and preferences from data (%@, %@)", [e name], [e reason]);
				if (notesData) free(notesData);
				return kCoderErr;
			}
			//unpack notes using the current NotationPrefs instance (not the just-unarchived one), with which we presumably just used to encrypt it
			NSMutableArray *notesToVerify = [frozenNotation unpackedNotesWithPrefs:notationPrefs returningError:&err];
			if (noErr != err) {
				if (notesData) free(notesData);
				return err;
			}
			//notes were unpacked--now roughly compare notesToVerify with allNotes, plus deletedNotes and notationPrefs
			if (!notesToVerify || [notesToVerify count] != [allNotes count] || [[frozenNotation deletedNotes] count] != [deletedNotes  count] ||
				[frozenNotation.prefs notesStorageFormat] != [notationPrefs notesStorageFormat] ||
				[frozenNotation.prefs hashIterationCount] != [notationPrefs hashIterationCount]) {
				if (notesData) free(notesData);
				return kItemVerifyErr;
			}
			unsigned int i;
			for (i=0; i<[notesToVerify count]; i++) {
				if ([[[notesToVerify objectAtIndex:i] contentString] length] != [[[allNotes objectAtIndex:i] contentString] length]) {
					if (notesData) free(notesData);
					return kItemVerifyErr;
				}
			}
			
			NSLog(@"verified %lu notes in %g s", [notesToVerify count], (float)[[NSDate date] timeIntervalSinceDate:date]);
			
			if (notesData) free(notesData);
			return noErr;
		}] != noErr) {
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
    
    if (delegate && !displayedAlert) {
	//we already have a delegate, so this must be a result of the format or file changing after initialization
	
	displayedAlert = YES;
	
	[self flushAllNoteChanges];
	
	NSRunAlertPanel(NSLocalizedString(@"Unable to create or access the Interim Note-Changes file. Is another copy of Notational Velocity currently running?",nil), 
			NSLocalizedString(@"Open Console in /Applications/Utilities/ for more information.",nil), NSLocalizedString(@"Quit",nil), NULL, NULL);
	
	
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
- (void)databaseSettingsChangedFromOldFormat:(NVDatabaseFormat)oldFormat {
	NVDatabaseFormat currentStorageFormat = [notationPrefs notesStorageFormat];
    
	if (!walWriter && ![self initializeJournaling]) {
		[self performSelector:@selector(handleJournalError) withObject:nil afterDelay:0.0];
	}
	
    if (currentStorageFormat == NVDatabaseFormatSingle) {
		
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

- (NVDatabaseFormat)currentNoteStorageFormat {
    return [notationPrefs notesStorageFormat];
}

- (void)noteDidNotWrite:(NoteObject*)note errorCode:(OSStatus)error {
    [unwrittenNotes addObject:note];
    
    if (error != lastWriteError) {
		NSRunAlertPanel([NSString stringWithFormat:NSLocalizedString(@"Changed notes could not be saved because %@.",
																	 @"alert title appearing when notes couldn't be written"), 
			[NSString reasonStringFromCarbonFSError:error]], @"", NSLocalizedString(@"OK",nil), NULL, NULL);
		
		lastWriteError = error;
    }
}

- (void)synchronizeNoteChanges:(NSTimer*)timer {
    
    if ([unwrittenNotes count] > 0) {
		lastWriteError = noErr;
		if ([notationPrefs notesStorageFormat] != NVDatabaseFormatSingle) {
			//to avoid mutation enumeration if writing this file triggers a filename change which then triggers another makeNoteDirty which then triggers another scheduleWriteForNote:
			//loose-coupling? what?
			[[unwrittenNotes copy] makeObjectsPerformSelector:@selector(writeUsingCurrentFileFormatIfNecessary)];
			
			//this always seems to call ourselves
			FNNotify(&noteDirectoryRef, kFNDirectoryModifiedMessage, kFNNoImplicitAllSubscription);
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

- (NSData*)aliasDataForNoteDirectory {
    NSData* theData = nil;
    
    FSRef userHomeFoundRef, *relativeRef = &userHomeFoundRef;
    
    if (aliasNeedsUpdating) {
		OSErr err = FSFindFolder(kUserDomain, kCurrentUserFolderType, kCreateFolder, &userHomeFoundRef);
		if (err != noErr) {
			relativeRef = NULL;
			NSLog(@"FSFindFolder error: %d", err);
		}
    }
	
    //re-fill handle from fsref if necessary, storing path relative to user directory
    if (aliasNeedsUpdating && FSNewAlias(relativeRef, &noteDirectoryRef, &aliasHandle ) != noErr)
		return nil;
	
    if (aliasHandle != NULL) {
		aliasNeedsUpdating = NO;
		
		HLock((Handle)aliasHandle);
		theData = [NSData dataWithBytes:*aliasHandle length:GetHandleSize((Handle) aliasHandle)];
		HUnlock((Handle)aliasHandle);
	    
		return theData;
    }
    
    return nil;
}

- (void)setAliasNeedsUpdating:(BOOL)needsUpdate {
	aliasNeedsUpdating = needsUpdate;
}

- (BOOL)aliasNeedsUpdating {
	return aliasNeedsUpdating;
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
		
		NSString *trashLocation = [[[NSFileManager defaultManager] pathWithFSRef:&noteDirectoryRef] stringByAbbreviatingWithTildeInPath];
		if (!trashLocation) trashLocation = @"unknown";
		NSInteger result = NSRunCriticalAlertPanel([NSString stringWithFormat:NSLocalizedString(@"Your notes directory (%@) appears to be in the Trash.",nil), trashLocation], 
											 NSLocalizedString(@"If you empty the Trash now, you could lose your notes. Relocate the notes to a less volatile folder?",nil),
											 NSLocalizedString(@"Relocate Notes",nil), NSLocalizedString(@"Quit",nil), NULL);
		if (result == NSAlertDefaultReturn)
			[self relocateNotesDirectory];
		else [NSApp terminate:nil];
	}
}

- (void)trashRemainingNoteFilesInDirectory {
	NSAssert([notationPrefs notesStorageFormat] == NVDatabaseFormatSingle, @"We shouldn't be removing files if the storage is not single-database");
	[allNotes makeObjectsPerformSelector:@selector(moveFileToTrash)];
	[self notifyOfChangedTrash];
}

- (void)updateLinksToNote:(NoteObject*)aNoteObject fromOldName:(NSString*)oldname {
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
	NSArray *allNotesAlpha = [allNotes sortedArrayWithOptions:NSSortStable|NSSortConcurrent usingComparator:^(NoteObject *obj1, NoteObject *obj2) {
		return [obj1 compare:obj2];
	}];
	[allNotes makeObjectsPerformSelector:@selector(removeAllPrefixParentNotes)];

	NSUInteger j, i = 0, count = [allNotesAlpha count];
	for (i=0; i<count - 1; i++) {
		NoteObject *shorterNote = [allNotesAlpha objectAtIndex:i];
		BOOL isAPrefix = NO;
		//scan all notes sorted beneath this one for matching prefixes
		j = i + 1;
		do {
			NoteObject *longerNote = [allNotesAlpha objectAtIndex:j];
			if ((isAPrefix = noteTitleIsAPrefixOfOtherNoteTitle(longerNote, shorterNote))) {
				[longerNote addPrefixParentNote:shorterNote];
			}
		} while (isAPrefix && ++j<count);
	}
}

- (void)addNewNote:(NoteObject*)note {
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
		if (! [[self undoManager] isUndoing] && ! [[self undoManager] isRedoing])
			[undoManager setActionName:[NSString stringWithFormat:NSLocalizedString(@"Create Note quotemark%@quotemark",@"undo action name for creating a single note"), note.titleString]];
	}
    
	[self resortAllNotes];
    [self refilterNotes];
    
    [delegate notation:self revealNote:note options:NVEditNoteToReveal | NVOrderFrontWindow];	
}

//do not update the view here (why not?)
- (NoteObject*)addNoteFromCatalogEntry:(NoteCatalogEntry*)catEntry {
	NoteObject *newNote = [[NoteObject alloc] initWithCatalogEntry:catEntry delegate:self];
	[self _addNote:newNote];
	
	[self schedulePushToAllSyncServicesForNote:newNote];
	
	directoryChangesFound = YES;
	
	return newNote;
}

- (void)addNotesFromSync:(NSArray*)noteArray {
	
	if (![noteArray count]) return; 
	
	unsigned int i;
	
	if ([[self undoManager] isUndoing]) [undoManager beginUndoGrouping];
	for (i=0; i<[noteArray count]; i++) {
		NoteObject * note = [noteArray objectAtIndex:i];
		
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

- (void)addNotes:(NSArray*)noteArray {
	
	if (![noteArray count]) return; 
	
	unsigned int i;
	
	if ([[self undoManager] isUndoing]) [undoManager beginUndoGrouping];
	for (i=0; i<[noteArray count]; i++) {
		NoteObject * note = [noteArray objectAtIndex:i];
		
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
		if (! [[self undoManager] isUndoing] && ! [[self undoManager] isRedoing])
			[undoManager setActionName:[NSString stringWithFormat:NSLocalizedString(@"Add %d Notes", @"undo action name for creating multiple notes"), [noteArray count]]];	
	}
	[self resortAllNotes];
	[self refilterNotes];
	
	if ([noteArray count] > 1)
		[delegate notation:self revealNotes:noteArray];
	else
		[delegate notation:self revealNote:[noteArray lastObject] options:NVOrderFrontWindow];
}

- (void)note:(NoteObject*)note attributeChanged:(NSString*)attribute {
	
	if ([attribute isEqualToString:NotePreviewString]) {
		if ([prefsController tableColumnsShowPreview]) {
			NSUInteger idx = [notesList indexOfObject:note];
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

- (BOOL)openFiles:(NSArray*)filenames {
	//reveal notes that already exist with any of these filenames
	//for paths left over that weren't in the notes-folder/database, import those files as new notes
	
	if (![filenames count]) return NO;
	
	NSArray *unknownPaths = filenames; //(this is not a requirement for -notesWithFilenames:unknownFiles:)
	
	if ([self currentNoteStorageFormat] != NVDatabaseFormatSingle) {
		//notes are stored as separate files, so if these paths are in the notes folder then NV can claim ownership over them
		
		//probably should sync directory here to make sure notesWithFilenames has the freshest data
		[self synchronizeNotesFromDirectory];
		
		NSSet *existingNotes = [self notesWithFilenames:filenames unknownFiles:&unknownPaths];
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



- (void)scheduleUpdateListForAttribute:(NSString*)attribute {
	
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(scheduleUpdateListForAttribute:) object:attribute];
	
	if ([[sortColumn identifier] isEqualToString:attribute]) {
		
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

- (void)scheduleWriteForNote:(NoteObject*)note {

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
- (void)_addNote:(NoteObject*)aNoteObject {
    [aNoteObject setDelegate:self];	
	
    [allNotes addObject:aNoteObject];
	[deletedNotes removeObject:aNoteObject];
    
    notesChanged = YES;
}

//the gateway methods must always show warnings, or else flash overlay window if show-warnings-pref is off
- (void)removeNotes:(NSArray*)noteArray {
	NSEnumerator *enumerator = [noteArray objectEnumerator];
	NoteObject* note;
	
	[undoManager beginUndoGrouping];
	while ((note = [enumerator nextObject])) {
		[self removeNote:note];
	}
	[undoManager endUndoGrouping];
	if (! [[self undoManager] isUndoing] && ! [[self undoManager] isRedoing])
		[undoManager setActionName:[NSString stringWithFormat:NSLocalizedString(@"Delete %d Notes",@"undo action name for deleting notes"), [noteArray count]]];
	
}

- (void)removeNote:(NoteObject*)aNoteObject {
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
    if ([notationPrefs notesStorageFormat] != NVDatabaseFormatSingle) {
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
	[self schedulePushToAllSyncServicesForNote: deletedNote ? deletedNote : [DeletedNoteObject deletedNoteWithNote:aNoteObject]];
    
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
	for (i = 0; i<[dnArray count]; i++) {
		DeletedNoteObject *dnObj = [dnArray objectAtIndex:i];
		if (![[dnObj syncServicesMD] count]) {
			[deletedNotes removeObject:dnObj];
			notesChanged = YES;
		}
	}
	//NSLog(@"%s: deleted notes left: %@", _cmd, deletedNotes);
}

- (DeletedNoteObject*)_addDeletedNote:(id<SynchronizedNote>)aNote {
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

- (void)removeSyncMDFromDeletedNotesInSet:(NSSet*)notesToOrphan forService:(NSString*)serviceName {
	NSMutableSet *matchingNotes = [deletedNotes setIntersectedWithSet:notesToOrphan];
	[matchingNotes makeObjectsPerformSelector:@selector(removeAllSyncMDForService:) withObject:serviceName];
}

- (void)_registerDeletionUndoForNote:(NoteObject*)aNote {	
	[undoManager registerUndoWithTarget:self selector:@selector(addNewNote:) object:aNote];			
	if (![undoManager isUndoing] && ![undoManager isRedoing])
		[undoManager setActionName:[NSString stringWithFormat:NSLocalizedString(@"Delete quotemark%@quotemark",@"undo action name for deleting a single note"), aNote.titleString]];
}			


- (void)setUndoManager:(NSUndoManager*)anUndoManager {
    undoManager = anUndoManager;
}

- (NSUndoManager*)undoManager {
    return undoManager;
}

- (void)updateDateStringsIfNecessary {
	
	unsigned int currentHours = hoursFromAbsoluteTime(CFAbsoluteTimeGetCurrent());
	BOOL isHorizontalLayout = [prefsController horizontalLayout];
	
	if (currentHours != lastCheckedDateInHours || isHorizontalLayout != lastLayoutStyleGenerated) {
		lastCheckedDateInHours = currentHours;
		lastLayoutStyleGenerated = (int)isHorizontalLayout;
		
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

- (void)setForegroundTextColor:(NSColor*)fgColor {
	//do not update the notes in any other way, nor the database, other than also setting this color in notationPrefs
	//foreground color is archived only for practicality, and should be for display only
	NSAssert(fgColor != nil, @"foreground color cannot be nil");

	[allNotes makeObjectsPerformSelector:@selector(setForegroundTextColorOnly:) withObject:fgColor];

    [notationPrefs setForegroundColor:fgColor];
}

- (void)restyleAllNotes {
	NSFont *baseFont = [notationPrefs baseBodyFont];
	NSAssert(baseFont != nil, @"base body font from notation prefs should ALWAYS be valid!");
	
	[allNotes makeObjectsPerformSelector:@selector(updateUnstyledTextWithBaseFont:) withObject:baseFont];
	
	[notationPrefs setBaseBodyFont:[prefsController noteBodyFont]];
}

//used by BookmarksController

- (NoteObject*)noteForUUIDBytes:(CFUUIDBytes*)bytes {
	NSUInteger noteIndex = [allNotes indexOfNoteWithUUIDBytes:bytes];
	if (noteIndex != NSNotFound) return [allNotes objectAtIndex:noteIndex];
	return nil;	
}

- (void)updateLabelConnectionsAfterDecoding {
	[allNotes makeObjectsPerformSelector:@selector(updateLabelConnectionsAfterDecoding)];
}

//re-searching for all notes each time a label is added or removed is unnecessary, I think
- (void)note:(NoteObject*)note didAddLabelSet:(NSSet*)labelSet {
	[self.allLabels unionSet:labelSet];
	
	NSMutableSet *existingLabels = [self.allLabels setIntersectedWithSet:labelSet];
    [existingLabels makeObjectsPerformSelector:@selector(addNote:) withObject:note];
    [note replaceMatchingLabelSet:existingLabels]; //link back for the existing note, so that it knows about the other notes in this label
}

- (void)note:(NoteObject*)note didRemoveLabelSet:(NSSet*)labelSet {
	[self.allLabels minusSet:labelSet];
    
	//could use this as an opportunity to remove counterparts in labelImages
    
    //we narrow down the set to make sure that we operate on the actual objects within it, and note the objects used as prototypes
    //these will be any labels that were shared by notes other than this one
    NSMutableSet *existingLabels = [self.allLabels setIntersectedWithSet:labelSet];
    [existingLabels makeObjectsPerformSelector:@selector(removeNote:) withObject:note];
}

- (BOOL)filterNotesFromString:(NSString*)string {
	
	[delegate notationListMightChange:self];
	if ([self _filterNotesFromString:string]) {
		[delegate notationListDidChange:self];
		
		return YES;
	}
	
	return NO;
}

- (void)refilterNotes {
	
    [delegate notationListMightChange:self];
    [self _filterNotesFromString:(currentFilter ?: @"")];
    [delegate notationListDidChange:self];
}
	
- (BOOL)_filterNotesFromString:(NSString *)string
{
	//const char *searchString = string.UTF8String;
	BOOL forceUncached = NO;
    BOOL didFilterNotes = NO;
    size_t oldLen = 0, newLen = 0;
	NSUInteger i, initialCount = notesList.count;
    
	NSAssert(string, @"_filterNotesFromString requires a non-nil argument");
	
	newLen = string.length;
    
	//PHASE 1: determine whether notes can be searched from where they are--if not, start on all the notes
    if (!currentFilter || forceUncached || ((oldLen = currentFilter.length) > newLen) || ![string hasPrefix: currentFilter]) {
		
		//the search must be re-initialized; our strings don't have the same prefix
		
		[notesList removeAllObjects];
		[notesList addObjectsFromArray:allNotes];
		
		didFilterNotes = YES;
    }
	
	//if there is a quote character in the string, use that as a delimiter, as we will search by phrase
	//perhaps we could add some additional delimiters like punctuation marks here
	NSCharacterSet *separators = ([string rangeOfString:@"\""].location == NSNotFound) ? [NSCharacterSet characterSetWithCharactersInString:@"\""] : [NSCharacterSet whitespaceAndNewlineCharacterSet];
    
    if (!didFilterNotes || newLen > 0) {
		//only bother searching each note if we're actually searching for something
		//otherwise, filtered notes already reflect all-notes-state
		
		NSArray *tokens = [string componentsSeparatedByCharactersInSet:separators];
		for (NSString *token in tokens) {
			NSUInteger preCount = notesList.count;
						
			[notesList nv_filterStableUsingBlock:^(NoteObject *obj){
				if ([obj.titleString nv_containsStringInsensitive:token]) return YES;
				if ([obj.contentString.string nv_containsStringInsensitive:token]) return YES;
				if ([obj.labelString nv_containsStringInsensitive:token]) return YES;
				return NO;
			}];
			
			if (notesList.count != preCount)
				didFilterNotes = YES;
		}
    }

	//PHASE 4: autocomplete based on results
	//even if the controller didn't filter, the search string could have changed its representation wrt spacing
	//which will still influence note title prefixes 
	selectedNoteIndex = NSNotFound;
	
    if (newLen && [prefsController autoCompleteSearches]) {

		for (i=0; i<notesList.count; i++) {
			//because we already searched word-by-word up there, this is just way simpler
			if ([[notesList[i] titleString] hasPrefix:string]) {
				selectedNoteIndex = i;
				//this note matches, but what if there are other note-titles that are prefixes of both this one and the search string?
				//find the first prefix-parent of which searchString is also a prefix
				NSUInteger j = 0, prefixParentIndex = NSNotFound;
				NSArray *prefixParents = [notesList[i] prefixParentNotes];
				
				for (j=0; j<[prefixParents count]; j++) {
					NoteObject *obj = [prefixParents objectAtIndex:j];
					
					if ([obj.titleString hasPrefix:string] && (prefixParentIndex = [notesList indexOfObject:obj]) != NSNotFound) {
						//figure out where this prefix parent actually is in the list--if it actually is in the list, that is
						//otherwise look at the next prefix parent, etc.
						//the prefix parents array should always be alpha-sorted, so the shorter prefixes will always be first
						selectedNoteIndex = prefixParentIndex;
						break;
					}
				}
				break;
			}
		}
    }
    
	currentFilter = [string copy];
	
	if (!initialCount && initialCount == notesList.count)
		return NO;
    
    return didFilterNotes;
}

- (NSUInteger)preferredSelectedNoteIndex {
    return selectedNoteIndex;
}

- (NSArray*)noteTitlesPrefixedByString:(NSString*)prefixString indexOfSelectedItem:(NSInteger *)anIndex {
	NSMutableArray *objs = [NSMutableArray arrayWithCapacity:[allNotes count]];
	const char *searchString = [prefixString lowercaseUTF8String];
	NSUInteger i, titleLen, strLen = strlen(searchString), j = 0, shortestTitleLen = UINT_MAX;

	for (i=0; i<[allNotes count]; i++) {
		NoteObject *thisNote = [allNotes objectAtIndex:i];
		if (noteTitleHasPrefixOfUTF8String(thisNote, searchString, strLen)) {
			NSString *title = thisNote.titleString;
			[objs addObject:title];
			if (anIndex && (titleLen = title.length) < shortestTitleLen) {
				*anIndex = j;
				shortestTitleLen = titleLen;
			}
			j++;
		}
	}
	return objs;
}

- (NoteObject*)noteObjectAtFilteredIndex:(NSUInteger)noteIndex {
	unsigned int theIndex = (unsigned int)noteIndex;
	
	if (theIndex < notesList.count)
		return notesList[theIndex];
	
	return nil;
}

- (NSArray*)notesAtIndexes:(NSIndexSet*)indexSet {
	return [notesList objectsAtIndexes:indexSet];
}

//O(n^2) at best, but at least we're dealing with C arrays

- (NSIndexSet*)indexesOfNotes:(NSArray*)noteArray {
	NSMutableIndexSet *noteIndexes = [[NSMutableIndexSet alloc] init];
	
	[noteArray enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
		NSUInteger noteIndex = [notesList indexOfObject:obj];
		
		if (noteIndex != NSNotFound)
			[noteIndexes addIndex:noteIndex];
	}];
	
	return [noteIndexes copy];
}

- (NSUInteger)indexInFilteredListForNoteIdenticalTo:(NoteObject*)note {
	return [notesList indexOfObject:note];
}

- (NSUInteger)totalNoteCount {
	return [allNotes count];
}

- (NoteAttributeColumn*)sortColumn {
	return sortColumn;
}

- (void)setSortColumn:(NoteAttributeColumn*)col { 
	
	sortColumn = col;
	
	[self sortAndRedisplayNotes];
}

//re-sort without refiltering, to avoid removing notes currently being edited
- (void)sortAndRedisplayNotes {
	
	[delegate notationListMightChange:self];

	NoteAttributeColumn *col = sortColumn;
	if (col) {
		BOOL isStringSort = [col.identifier isEqualToString:NoteTitleColumnString];
		BOOL reversed = [prefsController tableIsReverseSorted];
		NSComparisonResult(^comparator)(id, id) = reversed ? col.reverseComparator : col.comparator;
		
		[allNotes sortWithOptions:NSSortConcurrent|NSSortStable usingComparator:^(NoteObject *obj1, NoteObject *obj2) {
			return reversed ? [obj2 compare:obj1] : [obj1 compare:obj2];
		}];
		
		if (!isStringSort) {
			[allNotes sortWithOptions:NSSortConcurrent|NSSortStable usingComparator:comparator];
		}
		
		if ([notesList count] != [allNotes count]) {
			[notesList sortWithOptions:NSSortConcurrent|NSSortStable usingComparator:^(NoteObject *obj1, NoteObject *obj2) {
				return reversed ? [obj2 compare:obj1] : [obj1 compare:obj2];
			}];
			
			if (!isStringSort) {
				[notesList sortWithOptions:NSSortConcurrent|NSSortStable usingComparator:comparator];
			}
			
		} else {
			[notesList removeAllObjects];
			[notesList addObjectsFromArray:allNotes];
		}
		
		[delegate notationListDidChange:self];
	}
}

- (void)resortAllNotes {
	
	NoteAttributeColumn *col = sortColumn;
	
	if (col) {
		BOOL reversed = [prefsController tableIsReverseSorted];
		BOOL isStringSort = [col.identifier isEqualToString:NoteTitleColumnString];

		NSComparisonResult(^comparator)(id, id) = reversed ? col.reverseComparator : col.comparator;
		
		[allNotes sortWithOptions:NSSortConcurrent|NSSortStable usingComparator:^(NoteObject *obj1, NoteObject *obj2) {
			return reversed ? [obj2 compare:obj1] : [obj1 compare:obj2];
		}];
		
		if (!isStringSort) {
			[allNotes sortWithOptions:NSSortConcurrent|NSSortStable usingComparator:comparator];
		}
	}
}

- (float)titleColumnWidth {
	return titleColumnWidth;
}

- (void)regeneratePreviewsForColumn:(NSTableColumn*)col visibleFilteredRows:(NSRange)rows forceUpdate:(BOOL)force {
	
	float width = [col width] - [NSScroller scrollerWidthForControlSize:NSRegularControlSize];
	
	if (force || roundf(width) != roundf(titleColumnWidth)) {
		titleColumnWidth = width;
		
		//regenerate previews for visible rows immediately and post a delayed message to regenerate previews for all rows
		if (rows.length > 0) {
			NSIndexSet *set = [NSIndexSet indexSetWithIndexesInRange:rows];
			[[notesList objectsAtIndexes:set] makeObjectsPerformSelector:@selector(updateTablePreviewString)];
		}
		
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(regenerateAllPreviews) object:nil];
		[self performSelector:@selector(regenerateAllPreviews) withObject:nil afterDelay:0.0];
	}
}

- (void)regenerateAllPreviews {
	[allNotes makeObjectsPerformSelector:@selector(updateTablePreviewString)];
}

- (NotationPrefs*)notationPrefs {
	return notationPrefs;
}

- (SyncSessionController*)syncSessionController {
	return syncSessionController;
}

- (void)dealloc {
 
	[walWriter setDelegate:nil];
	[notationPrefs setDelegate:nil];
	[allNotes makeObjectsPerformSelector:@selector(setDelegate:) withObject:nil];

	if (fsCatInfoArray)
		free(fsCatInfoArray);
	if (HFSUniNameArray)
		free(HFSUniNameArray);
    if (catalogEntries)
		free(catalogEntries);
    if (sortedCatalogEntries)
		free(sortedCatalogEntries);
	
	
    
}
	
	

#pragma mark nvALT stuff
- (NSString *)createCachesFolder{
    NSString *path = nil;
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    if ([paths count])
    {
        NSString *bundleName =
        [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleIdentifier"];
        path = [[paths objectAtIndex:0] stringByAppendingPathComponent:bundleName];
        NSError *theError = nil;
        if ((path)&&([[NSFileManager defaultManager]createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:&theError])) {
//           NSLog(@"cache folder :>%@<",path);
            return path;

        }else{
            NSLog(@"error creating cache folder :>%@<",[theError description]);
        }
    }else{
        NSLog(@"Unable to find or create cache folder:\n%@", path);
    }
    return nil;
}
	
#pragma mark - Labels
	
- (NSArray*)labelTitlesPrefixedByString:(NSString*)prefixString indexOfSelectedItem:(NSInteger *)anIndex minusWordSet:(NSSet*)antiSet {
	
	NSMutableArray *objs = [[self.allLabels allObjects] mutableCopy];
	NSMutableArray *titles = [NSMutableArray arrayWithCapacity:[self.allLabels count]];
	
	[objs sortWithOptions:NSSortConcurrent usingComparator:^(LabelObject *obj1, LabelObject *obj2) {
		return [obj1.title caseInsensitiveCompare:obj2.title];
	}];
	
	CFStringRef prefix = (__bridge CFStringRef)prefixString;
	NSUInteger i, titleLen, j = 0, shortestTitleLen = UINT_MAX;
	
	for (i=0; i<[objs count]; i++) {
		CFStringRef title = (__bridge CFStringRef)[(LabelObject*)[objs objectAtIndex:i] title];
		
		if (CFStringFindWithOptions(title, prefix, CFRangeMake(0, CFStringGetLength(prefix)), kCFCompareAnchored | kCFCompareCaseInsensitive, NULL)) {
			
			if (![antiSet containsObject:(__bridge id)title]) {
				[titles addObject:(__bridge id)title];
				if (anIndex && (titleLen = CFStringGetLength(title)) < shortestTitleLen) {
					*anIndex = j;
					shortestTitleLen = titleLen;
				}
				j++;
			}
		}
	}
	return titles;
}

- (void)invalidateCachedLabelImages {
	//used when the list font size changes
	[self.labelImages removeAllObjects];
}
- (NSImage*)cachedLabelImageForWord:(NSString*)aWord highlighted:(BOOL)isHighlighted {
	if (!self.labelImages) self.labelImages = [NSMutableDictionary dictionary];
	
	NSString *imgKey = [[aWord lowercaseString] stringByAppendingFormat:@", %d", isHighlighted];
	NSImage *img = [self.labelImages objectForKey:imgKey];
	if (!img) {
		//generate the image and add it to labelImages under imgKey
		float tableFontSize = [[GlobalPrefs defaultPrefs] tableFontSize] - 1.0;
		NSDictionary *attrs = [NSDictionary dictionaryWithObject:[NSFont systemFontOfSize:tableFontSize] forKey:NSFontAttributeName];
		NSSize wordSize = [aWord sizeWithAttributes:attrs];
		NSRect wordRect = NSMakeRect(0, 0, roundf(wordSize.width + 4.0), roundf(tableFontSize * 1.3));
		
		//peter hosey's suggestion, rather than doing setWindingRule: and appendBezierPath: as before:
		//http://stackoverflow.com/questions/4742773/why-wont-helvetica-neue-bold-glyphs-draw-as-a-normal-subpath-in-nsbezierpath
		
		img = [[NSImage alloc] initWithSize:wordRect.size];
		[img lockFocus];
		
		CGContextRef context = (CGContextRef)([[NSGraphicsContext currentContext] graphicsPort]);
		CGContextBeginTransparencyLayer(context, NULL);
		
		CGContextClipToRect(context, NSRectToCGRect(wordRect));
		
		NSBezierPath *backgroundPath = [NSBezierPath bezierPathWithRoundRectInRect:wordRect radius:2.0f];
		[(isHighlighted ? [NSColor whiteColor] : [NSColor colorWithCalibratedWhite:0.55 alpha:1.0]) setFill];
		[backgroundPath fill];
		
		[[NSGraphicsContext currentContext] setCompositingOperation:NSCompositeSourceOut];
		[aWord drawWithRect:(NSRect){{2.0, 3.0}, wordRect.size} options:NSStringDrawingUsesFontLeading attributes:attrs];
		
		CGContextEndTransparencyLayer(context);
		
		[img unlockFocus];
		
		[self.labelImages setObject:img forKey:imgKey];
	}
	return img;
}
	
#pragma mark - Data source

- (void)tableView:(NSTableView *)aTableView setObjectValue:(id)anObject
forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex {
	// allow the tableview to override the selector destination for this object value
	void (^setter)(NoteObject *, id) = [(NotesTableView*)aTableView attributeSetterForColumn:aTableColumn];
	
	if (setter) {
		setter(notesList[rowIndex], anObject);
	}
}
	
- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex {
	return ((NoteAttributeColumn *)aTableColumn).objectAttributeFunction(aTableView, notesList[rowIndex], rowIndex);
}
	
- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
	return notesList.count;
}

@end


