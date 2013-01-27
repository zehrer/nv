//
//  NotationController.h
//  Notation
//
//  Created by Zachary Schneirov on 12/19/05.

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


#import "WALController.h"
#import "NotationPrefs.h"
#import "NotesTableView.h"
#import "BookmarksController.h"
#import "NoteObject.h"

@class DeletedNoteObject;
@class SyncSessionController;
@class NotationPrefs;
@class NoteAttributeColumn;
@class NoteBookmark;
@class DeletionManager;
@class GlobalPrefs;
@class NotationController;
@class NoteCatalogEntry;

typedef NS_OPTIONS(NSInteger, NVNoteRevealOptions) {
	NVDefaultReveal = 0,
	NVDoNotChangeScrollPosition = 1,
	NVOrderFrontWindow = 2,
	NVEditNoteToReveal = 4
};

@protocol NotationControllerDelegate <NSObject>

- (BOOL)notationListShouldChange:(NotationController *)someNotation;

- (void)notationListMightChange:(NotationController *)someNotation;

- (void)notationListDidChange:(NotationController *)someNotation;

- (void)notation:(NotationController *)notation revealNote:(NoteObject *)note options:(NVNoteRevealOptions)opts;

- (void)notation:(NotationController *)notation revealNotes:(NSArray *)notes;

- (void)contentsUpdatedForNote:(NoteObject *)aNoteObject;

- (void)titleUpdatedForNote:(NoteObject *)aNoteObject;

- (void)rowShouldUpdate:(NSInteger)affectedRow;

@end

@interface NotationController : NSObject <NSTableViewDataSource, NVPreferencesDelegate, NVLabelsListSource, BookmarksControllerDataSource, NoteObjectDelegate> {
	NSMutableArray *allNotes;
	GlobalPrefs *prefsController;
	SyncSessionController *syncSessionController;
	DeletionManager *deletionManager;

	float titleColumnWidth;
	NoteAttributeColumn *sortColumn;

	NSUInteger selectedNoteIndex;
	char *currentFilterStr, *manglingString;
	NSInteger lastWordInFilterStr;

	BOOL directoryChangesFound;

	NotationPrefs *notationPrefs;

	NSMutableSet *deletedNotes;

	FSCatalogInfo *fsCatInfoArray;
	HFSUniStr255 *HFSUniNameArray;

	FSEventStreamRef noteDirEventStreamRef;
	BOOL eventStreamStarted;

	NSUInteger lastCheckedDateInHours;
	int lastLayoutStyleGenerated;
	long blockSize;
	struct statfs *statfsInfo;
	NSUInteger diskUUIDIndex;
	CFUUIDRef diskUUID;
	FSRef noteDirectoryRef, noteDatabaseRef;
	AliasHandle aliasHandle;
	BOOL aliasNeedsUpdating;
	OSStatus lastWriteError;
	NSError *_lastWriteNSError;

	WALStorageController *walWriter;
	NSMutableSet *unwrittenNotes;
	BOOL notesChanged;
	NSTimer *changeWritingTimer;
	NSUndoManager *undoManager;

	NSURL *_noteDirectoryURL, *_noteDatabaseURL;
}

@property(nonatomic, strong) NSMutableArray *filteredNotesList;
@property(nonatomic, strong) NSCountedSet *allLabels, *filteredLabels;

@property (nonatomic, strong, readonly) NSFileManager *fileManager;

@property (nonatomic, readonly) NSURL *noteDirectoryURL;
@property (nonatomic, readonly) NSURL *noteDatabaseURL;

- (id)init;

- (id)initWithAliasData:(NSData *)data error:(out NSError **)err;

- (id)initWithDefaultDirectoryWithError:(out NSError **)err;

- (id)initWithDirectoryRef:(FSRef *)directoryRef error:(out NSError **)err;

- (void)setAliasNeedsUpdating:(BOOL)needsUpdate;

- (BOOL)aliasNeedsUpdating;

- (NSData *)aliasDataForNoteDirectory;

- (OSStatus)_readAndInitializeSerializedNotes;

- (void)processRecoveredNotes:(NSDictionary *)dict;

- (BOOL)initializeJournaling;

- (void)handleJournalError;

- (void)checkJournalExistence;

- (void)closeJournal;

- (BOOL)flushAllNoteChanges;

- (void)flushEverything;

- (void)upgradeDatabaseIfNecessary;

@property(nonatomic, weak) id <NotationControllerDelegate> delegate;

- (void)databaseEncryptionSettingsChanged;

- (void)databaseSettingsChangedFromOldFormat:(NoteStorageFormat)oldFormat;

- (NoteStorageFormat)currentNoteStorageFormat;

- (void)synchronizeNoteChanges:(NSTimer *)timer;

- (void)updateDateStringsIfNecessary;

- (void)makeForegroundTextColorMatchGlobalPrefs;

- (void)setForegroundTextColor:(NSColor *)aColor;

- (void)restyleAllNotes;

- (void)setUndoManager:(NSUndoManager *)anUndoManager;

- (NSUndoManager *)undoManager;

- (void)scheduleWriteForNote:(NoteObject *)note;

- (void)trashRemainingNoteFilesInDirectory;

- (void)checkIfNotationIsTrashed;

- (void)updateLinksToNote:(NoteObject *)aNoteObject fromOldName:(NSString *)oldname;

- (void)updateTitlePrefixConnections;

- (void)addNotes:(NSArray *)noteArray;

- (void)addNotesFromSync:(NSArray *)noteArray;

- (void)addNewNote:(NoteObject *)aNoteObject;

- (void)_addNote:(NoteObject *)aNoteObject;

- (void)removeNote:(NoteObject *)aNoteObject;

- (void)removeNotes:(NSArray *)noteArray;

- (void)_purgeAlreadyDistributedDeletedNotes;

- (void)removeSyncMDFromDeletedNotesInSet:(NSSet *)notesToOrphan forService:(NSString *)serviceName;

- (DeletedNoteObject *)_addDeletedNote:(id <SynchronizedNote>)aNote;

- (void)_registerDeletionUndoForNote:(NoteObject *)aNote;

- (NoteObject *)addNoteFromCatalogEntry:(NoteCatalogEntry *)catEntry;

- (BOOL)openFiles:(NSArray *)filenames;

- (void)updateLabelConnectionsAfterDecoding;

- (void)refilterNotes;

- (BOOL)filterNotesFromString:(NSString *)string;

- (BOOL)filterNotesFromUTF8String:(const char *)searchString forceUncached:(BOOL)forceUncached;

- (NSUInteger)preferredSelectedNoteIndex;

- (NSArray *)noteTitlesPrefixedByString:(NSString *)prefixString indexOfSelectedItem:(NSInteger *)anIndex;

- (NoteObject *)noteObjectAtFilteredIndex:(NSUInteger)noteIndex;

- (NSArray *)notesAtIndexes:(NSIndexSet *)indexSet;

- (NSIndexSet *)indexesOfNotes:(NSArray *)noteSet;

- (NSUInteger)indexInFilteredListForNoteIdenticalTo:(NoteObject *)note;

- (NSUInteger)totalNoteCount;

- (void)scheduleUpdateListForAttribute:(NSString *)attribute;

- (NoteAttributeColumn *)sortColumn;

- (void)setSortColumn:(NoteAttributeColumn *)col;

- (void)resortAllNotes;

- (void)sortAndRedisplayNotes;

- (float)titleColumnWidth;

- (void)regeneratePreviewsForColumn:(NSTableColumn *)col visibleFilteredRows:(NSRange)rows forceUpdate:(BOOL)force;

- (void)regenerateAllPreviews;
//- (void)invalidateAllLabelPreviewImages;

- (NotationPrefs *)notationPrefs;

- (SyncSessionController *)syncSessionController;

- (void)invalidateCachedLabelImages;

- (NSImage *)cachedLabelImageForWord:(NSString *)aWord highlighted:(BOOL)isHighlighted;

@end
