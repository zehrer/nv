//
//  NoteObject.h
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


#import <Cocoa/Cocoa.h>
#import "NotationController.h"
#import "BufferUtils.h"
#import "SynchronizedNoteProtocol.h"
#import "NotationTypes.h"

@class LabelObject;
@class WALStorageController;
@class NotesTableView;
@class ExternalEditor;

typedef struct _NoteFilterContext {
	char* needle;
	BOOL useCachedPositions;
} NoteFilterContext;

@protocol NoteObjectDelegate;

@interface NoteObject : NSObject <NSCoding, SynchronizedNote> {
	NSMutableSet *labelSet; //if this note's title is "Chicken Shack menu listing", its prefix parent might have the title "Chicken Shack"
	
	//for syncing to text file
	NSUInteger perDiskInfoGroupCount;
	BOOL shouldWriteToFile, didUnarchive;
	
	//not determined until it's time to read to or write from a text file
	FSRef *noteFileRef;
	
	//more metadata
	NSRange selectedRange;
	
	//each note has its own undo manager--isn't that nice?
	NSUndoManager *undoManager;
}

@property (nonatomic) CFAbsoluteTime modifiedDate;
@property (nonatomic) CFAbsoluteTime createdDate;
@property (nonatomic, readonly) NVDatabaseFormat currentFormatID;
@property (nonatomic, readonly) UInt32 logicalSize;
@property (nonatomic, readonly) UInt32 nodeID;

@property (nonatomic, readonly) UTCDateTime fileModifiedDate;

@property (nonatomic, copy) NSAttributedString *contentString;
@property (nonatomic, copy, readonly) NSString *filename;
@property (nonatomic, copy) NSString *titleString;
@property (nonatomic, copy, readonly) NSAttributedString *tableTitleString;
@property (nonatomic, copy) NSString *labelString;

@property (nonatomic, assign) UTCDateTime *attrsModifiedDate;
@property (nonatomic, strong) NSMutableArray *prefixParentNotes;

@property (nonatomic, readonly) NSString *modifiedDateString;
@property (nonatomic, readonly) NSString *createdDateString;

@property (nonatomic, weak) id <NoteObjectDelegate> delegate;

- (id)initWithNoteBody:(NSAttributedString *)bodyText title:(NSString *)aNoteTitle
              delegate:(id)aDelegate format:(NVDatabaseFormat)formatID labels:(NSString*)aLabelString;
- (id)initWithCatalogEntry:(NoteCatalogEntry*)entry delegate:(id)aDelegate;

- (NSSet*)labelSet;
- (void)replaceMatchingLabelSet:(NSSet*)aLabelSet;
- (void)replaceMatchingLabel:(LabelObject*)label;
- (void)updateLabelConnectionsAfterDecoding;
- (void)updateLabelConnections;
- (void)disconnectLabels;
- (BOOL)_setLabelString:(NSString*)newLabelString;
- (NSMutableSet*)labelSetFromCurrentString;
- (NSArray*)orderedLabelTitles;
- (NSSize)sizeOfLabelBlocks;
- (void)_drawLabelBlocksInRect:(NSRect)aRect rightAlign:(BOOL)onRight highlighted:(BOOL)isHighlighted getSizeOnly:(NSSize*)reqSize;
- (void)drawLabelBlocksInRect:(NSRect)aRect rightAlign:(BOOL)onRight highlighted:(BOOL)isHighlighted;

- (void)setSyncObjectAndKeyMD:(NSDictionary*)aDict forService:(NSString*)serviceName;
- (void)removeAllSyncMDForService:(NSString*)serviceName;
//- (void)removeKey:(NSString*)aKey forService:(NSString*)serviceName;
- (void)updateWithSyncBody:(NSString*)newBody andTitle:(NSString*)newTitle;
- (void)registerModificationWithOwnedServices;

@property (nonatomic, readonly) NSStringEncoding fileEncoding;
- (OSStatus)writeCurrentFileEncodingToFSRef:(FSRef*)fsRef;
- (void)_setFileEncoding:(NSStringEncoding)encoding;
- (BOOL)setFileEncodingAndReinterpret:(NSStringEncoding)encoding;
- (BOOL)upgradeToUTF8IfUsingSystemEncoding;
- (BOOL)upgradeEncodingToUTF8;
- (BOOL)updateFromFile;
- (BOOL)updateFromCatalogEntry:(NoteCatalogEntry*)catEntry;
- (BOOL)updateFromData:(NSMutableData *)data inFormat:(NVDatabaseFormat)fmt;

- (OSStatus)writeFileDatesAndUpdateTrackingInfo;

- (NSURL*)uniqueNoteLink;
- (NSString*)noteFilePath;
- (void)invalidateFSRef;

- (BOOL)writeUsingJournal:(WALStorageController*)wal;

- (BOOL)writeUsingCurrentFileFormatIfNecessary;
- (BOOL)writeUsingCurrentFileFormatIfNonExistingOrChanged;
- (BOOL)writeUsingCurrentFileFormat;
- (void)makeNoteDirtyUpdateTime:(BOOL)updateTime updateFile:(BOOL)updateFile;

- (void)moveFileToTrash;
- (void)removeFileFromDirectory;
- (BOOL)removeUsingJournal:(WALStorageController*)wal;

- (OSStatus)exportToDirectoryRef:(FSRef *)directoryRef withFilename:(NSString *)userFilename usingFormat:(NVDatabaseFormat)storageFormat overwrite:(BOOL)overwrite;
- (NSRange)nextRangeForWords:(NSArray*)words options:(unsigned)opts range:(NSRange)inRange;
- (void)editExternallyUsingEditor:(ExternalEditor*)ed;
- (void)abortEditingInExternalEditor;

- (void)setFilenameFromTitle;
- (void)setFilename:(NSString*)aString withExternalTrigger:(BOOL)externalTrigger;
- (BOOL)_setTitleString:(NSString*)aNewTitle;
- (void)setTitleString:(NSString*)aNewTitle;
- (void)updateTablePreviewString;
- (NSAttributedString*)printableStringRelativeToBodyFont:(NSFont*)bodyFont;
- (NSString*)combinedContentWithContextSeparator:(NSString*)sepWContext;
- (void)setForegroundTextColorOnly:(NSColor*)aColor;
- (void)_resanitizeContent;
- (void)updateUnstyledTextWithBaseFont:(NSFont*)baseFont;
- (void)updateDateStrings;
- (void)setDateModified:(CFAbsoluteTime)newTime;
- (void)setDateAdded:(CFAbsoluteTime)newTime;
- (void)setSelectedRange:(NSRange)newRange;
- (NSRange)lastSelectedRange;
- (void)addPrefixParentNote:(NoteObject*)aNote;
- (void)removeAllPrefixParentNotes;
- (void)previewUsingMarked;

- (NSUndoManager*)undoManager;
- (void)_undoManagerDidChange:(NSNotification *)notification;

#pragma mark - Comparators

- (NSComparisonResult)compare:(NoteObject *)other;
- (NSComparisonResult)compareCreatedDate:(NoteObject *)other;
- (NSComparisonResult)compareModifiedDate:(NoteObject *)other;
- (NSComparisonResult)compareUniqueNoteID:(NoteObject *)other;

+ (NSComparisonResult(^)(id, id))comparatorForAttribute:(NVUIAttribute)attribute reversed:(BOOL)reversed;

- (BOOL)titleIsPrefixOfOtherNoteTitle:(NoteObject *)shorter;

@end

// this is quite the glorious mess
@protocol NoteObjectDelegate <NSObject>

- (void)note:(NoteObject*)note didAddLabelSet:(NSSet*)labelSet;
- (void)note:(NoteObject*)note didRemoveLabelSet:(NSSet*)labelSet;
- (void)note:(NoteObject*)note attributeChanged:(NVUIAttribute)attribute;
- (void)noteDidNotWrite:(NoteObject*)note errorCode:(OSStatus)error;

- (void)noteDidUpdateContents:(NoteObject*)note;

- (NSString*)uniqueFilenameForTitle:(NSString*)title fromNote:(NoteObject*)note; // NotationFileManager
- (NVDatabaseFormat)currentNoteStorageFormat;
@property (nonatomic, readonly) UInt32 diskUUIDIndex;
@property (nonatomic, readonly) long blockSize;

- (NSMutableData*)dataFromFileInNotesDirectory:(FSRef*)childRef forFilename:(NSString*)filename;
- (OSStatus)fileInNotesDirectory:(FSRef*)childRef isOwnedByUs:(BOOL*)owned hasCatalogInfo:(FSCatalogInfo *)info;

- (float)titleColumnWidth;

- (BOOL)notesDirectoryContainsFile:(NSString*)filename returningFSRef:(FSRef*)childRef;

- (OSStatus)noteFileRenamed:(FSRef*)childRef fromName:(NSString*)oldName toName:(NSString*)newName;

- (OSStatus)storeDataAtomicallyInNotesDirectory:(NSData*)data withName:(NSString*)filename destinationRef:(FSRef*)destRef
							   verifyUsingBlock:(OSStatus(^)(FSRef *, NSString *))verifier;

- (OSStatus)refreshFileRefIfNecessary:(FSRef *)childRef withName:(NSString *)filename charsBuffer:(UniChar*)charsBuffer;

- (NSImage*)cachedLabelImageForWord:(NSString*)aWord highlighted:(BOOL)isHighlighted;

- (OSStatus)createFileIfNotPresentInNotesDirectory:(FSRef*)childRef forFilename:(NSString*)filename fileWasCreated:(BOOL*)created;
- (void)schedulePushToAllSyncServicesForNote:(id <SynchronizedNote>)aNote;
- (NSMutableData*)dataFromFileInNotesDirectory:(FSRef*)childRef forCatalogEntry:(NoteCatalogEntry*)catEntry;
- (OSStatus)moveFileToTrash:(FSRef *)childRef forFilename:(NSString*)filename;
- (void)scheduleWriteForNote:(NoteObject*)note;

@end
