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


#import <Cocoa/Cocoa.h>
#import "WALController.h"
#import "NotationTypes.h"
#import "BookmarksController.h"

#import <CoreServices/CoreServices.h>

@class NoteObject;
@class DeletedNoteObject;
@class SyncSessionController;
@class NotationPrefs;
@class NoteAttributeColumn;
@class DeletionManager;
@class GlobalPrefs;
@class NVCatalogEntry;

@protocol NotationControllerDelegate;

extern inline NSComparisonResult NVComparisonResult(NSInteger result);

typedef struct _NoteCatalogEntry {
    UTCDateTime lastModified;
	UTCDateTime lastAttrModified;
    UInt32 logicalSize;
    OSType fileType;
    UInt32 nodeID;
    CFMutableStringRef filename;
    UniChar *filenameChars;
    UniCharCount filenameCharCount;
} NoteCatalogEntry;

@interface NotationController : NSObject <BookmarksControllerDataSource> {
	GlobalPrefs *prefsController;
	SyncSessionController *syncSessionController;
	DeletionManager *deletionManager;
	
	float titleColumnWidth;
    
    NSUInteger selectedNoteIndex;
    NSString *currentFilter;
    
	BOOL directoryChangesFound;
    
    NotationPrefs *notationPrefs;
	
	NSMutableSet *deletedNotes;
    
    FSCatalogInfo *fsCatInfoArray;
    HFSUniStr255 *HFSUniNameArray;

	FSEventStreamRef noteDirEventStreamRef;
	BOOL eventStreamStarted;
	    
    size_t catEntriesCount, totalCatEntriesCount;
    NoteCatalogEntry *catalogEntries, **sortedCatalogEntries;
    
	unsigned int lastCheckedDateInHours;
	int lastLayoutStyleGenerated;
	struct statfs *statfsInfo;
	unsigned int diskUUIDIndex;
	NSUUID *diskUUID;
    FSRef noteDirectoryRef, noteDatabaseRef;
    AliasHandle aliasHandle;
    BOOL aliasNeedsUpdating;
    NSError *lastWriteError;
    
    WALStorageController *walWriter;
    NSMutableSet *unwrittenNotes;
	BOOL notesChanged;
	NSTimer *changeWritingTimer;
	NSUndoManager *undoManager;
}

@property (nonatomic, readonly) NSArray *notes;
@property (nonatomic, readonly) NSArray *filteredNotes;

- (id)init;
- (id)initWithAliasData:(NSData*)data error:(OSStatus*)err;
- (id)initWithDefaultDirectoryReturningError:(OSStatus*)err;
- (id)initWithDirectoryRef:(FSRef*)directoryRef error:(OSStatus*)err;
- (void)setAliasNeedsUpdating:(BOOL)needsUpdate;
- (BOOL)aliasNeedsUpdating;
- (NSData*)aliasDataForNoteDirectory;
- (BOOL)readAndInitializeSerializedNotes:(out NSError **)err;
- (void)processRecoveredNotes:(NSMapTable *)table;
- (BOOL)initializeJournaling;
- (void)handleJournalError;
- (void)checkJournalExistence;
- (void)closeJournal;
- (BOOL)flushAllNoteChanges;
- (void)flushEverything;

- (void)upgradeDatabaseIfNecessary;

@property (nonatomic, weak) id <NotationControllerDelegate> delegate;

- (void)databaseEncryptionSettingsChanged;
- (void)databaseSettingsChangedFromOldFormat:(NVDatabaseFormat)oldFormat;

- (NVDatabaseFormat)currentNoteStorageFormat;
- (void)synchronizeNoteChanges:(NSTimer*)timer;

- (void)updateDateStringsIfNecessary;
- (void)makeForegroundTextColorMatchGlobalPrefs;
- (void)setForegroundTextColor:(NSColor*)aColor;
- (void)restyleAllNotes;
- (void)setUndoManager:(NSUndoManager*)anUndoManager;
- (NSUndoManager*)undoManager;
- (void)scheduleWriteForNote:(NoteObject*)note;
- (void)closeAllResources;
- (void)trashRemainingNoteFilesInDirectory;
- (void)checkIfNotationIsTrashed;
- (void)updateTitlePrefixConnections;
- (void)addNotes:(NSArray*)noteArray;
- (void)addNotesFromSync:(NSArray*)noteArray;
- (void)addNewNote:(NoteObject*)aNoteObject;
- (void)_addNote:(NoteObject*)aNoteObject;
- (void)removeNote:(NoteObject*)aNoteObject;
- (void)removeNotes:(NSArray*)noteArray;
- (DeletedNoteObject *)moveNoteToDeleted:(NoteObject *)note;
- (void)_purgeAlreadyDistributedDeletedNotes;
- (void)removeSyncMDFromDeletedNotesInSet:(NSSet*)notesToOrphan forService:(NSString*)serviceName;
- (DeletedNoteObject*)_addDeletedNote:(id<SynchronizedNote>)aNote;
- (void)_registerDeletionUndoForNote:(NoteObject*)aNote;
- (NoteObject*)addNoteFromCatalogEntry:(NoteCatalogEntry*)catEntry;

- (BOOL)openFiles:(NSArray*)filenames;

- (void)note:(NoteObject*)note didAddLabelSet:(NSSet*)labelSet;
- (void)note:(NoteObject*)note didRemoveLabelSet:(NSSet*)labelSet;

- (void)updateLabelConnectionsAfterDecoding;

- (void)refilterNotes;
- (BOOL)filterNotesFromString:(NSString*)string;
- (NSUInteger)preferredSelectedNoteIndex;
- (NSOrderedSet *)noteTitlesPrefixedByString:(NSString*)prefixString indexOfSelectedItem:(NSInteger *)anIndex;
- (NoteObject*)noteObjectAtFilteredIndex:(NSUInteger)noteIndex;
- (NSArray*)notesAtIndexes:(NSIndexSet*)indexSet;
- (NSIndexSet*)indexesOfNotes:(NSArray*)noteSet;
- (NSUInteger)indexInFilteredListForNoteIdenticalTo:(NoteObject*)note;
- (NSUInteger)totalNoteCount;

- (void)scheduleUpdateListForAttribute:(NVUIAttribute)attribute;
@property (nonatomic) NVUIAttribute sortAttribute;
- (void)resortAllNotes;
- (void)sortAndRedisplayNotes;

- (float)titleColumnWidth;
- (void)regeneratePreviewsForColumn:(NSTableColumn*)col visibleFilteredRows:(NSRange)rows forceUpdate:(BOOL)force;
- (void)regenerateAllPreviews;

- (NotationPrefs*)notationPrefs;
- (SyncSessionController*)syncSessionController;

@property(nonatomic, strong) NSCountedSet *allLabels;

- (NSArray*)labelTitlesPrefixedByString:(NSString*)prefixString indexOfSelectedItem:(NSInteger *)anIndex minusWordSet:(NSSet*)antiSet;

- (void)invalidateCachedLabelImages;
- (NSImage*)cachedLabelImageForWord:(NSString*)aWord highlighted:(BOOL)isHighlighted;

- (NoteObject *)noteForUUID:(NSUUID *)UUID;

// note object delegate - fix later
- (void)note:(NoteObject*)note attributeChanged:(NVUIAttribute)attribute;
- (void)note:(NoteObject*)note failedToWriteWithError:(NSError *)error;
- (void)noteDidUpdateContents:(NoteObject*)note;

@end


enum { NVDefaultReveal = 0, NVDoNotChangeScrollPosition = 1, NVOrderFrontWindow = 2, NVEditNoteToReveal = 4 };

@protocol NotationControllerDelegate <NSObject>

- (BOOL)notationListShouldChange:(NotationController*)someNotation;
- (void)notationListMightChange:(NotationController*)someNotation;
- (void)notationListDidChange:(NotationController*)someNotation;
- (void)notation:(NotationController*)notation revealNote:(NoteObject*)note options:(NSUInteger)opts;
- (void)notation:(NotationController*)notation revealNotes:(NSArray*)notes;

- (void)contentsUpdatedForNote:(NoteObject*)aNoteObject;
- (void)titleUpdatedForNote:(NoteObject*)aNoteObject;
- (void)rowShouldUpdate:(NSInteger)affectedRow;

@end
