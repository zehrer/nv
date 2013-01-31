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

#import "BufferUtils.h"
#import "SynchronizedNoteProtocol.h"
#import "NotationPrefs.h"
#import "NTNFileManager.h"

@class LabelObject;
@class WALStorageController;
@class NotesTableView;
@class ExternalEditor;
@class NoteCatalogEntry;

typedef struct _NoteFilterContext {
	char *needle;
	BOOL useCachedPositions;
} NoteFilterContext;

@class NoteObject;

@protocol NoteObjectDelegate <NSObject>

- (void)note:(NoteObject *)note didAddLabelSet:(NSSet *)labelSet;

- (void)note:(NoteObject *)note didRemoveLabelSet:(NSSet *)labelSet;

- (void)note:(NoteObject *)note attributeChanged:(NSString *)attribute;

- (void)updateLinksToNote:(NoteObject *)aNoteObject fromOldName:(NSString *)oldname;

- (void)noteDidNotWrite:(NoteObject *)note errorCode:(OSStatus)error;
- (void)noteDidNotWrite:(NoteObject *)note error:(NSError *)error;

- (float)titleColumnWidth;

- (void)scheduleWriteForNote:(NoteObject *)note;

- (void)noteDidUpdateContents:(NoteObject *)note;


- (NoteStorageFormat)currentNoteStorageFormat;

- (NSImage *)cachedLabelImageForWord:(NSString *)aWord highlighted:(BOOL)isHighlighted;

@end

@protocol SynchronizedNoteObjectDelegate <NoteObjectDelegate, NSObject>

- (void)schedulePushToAllSyncServicesForNote:(id <SynchronizedNote>)aNote;

@end

@interface NoteObject : NSObject <NSCoding, SynchronizedNote> {
	NSString *titleString, *labelString;

	BOOL contentsWere7Bit, contentCacheNeedsUpdate;
	//if this note's title is "Chicken Shack menu listing", its prefix parent might have the title "Chicken Shack"
	NSMutableArray *prefixParentNotes;

	//for syncing to text file
	NSString *filename;
	PerDiskInfo *perDiskInfoGroups;
	NSUInteger perDiskInfoGroupCount;
	NoteStorageFormat currentFormatID;
	NSStringEncoding fileEncoding;
	BOOL shouldWriteToFile, didUnarchive;

	//for storing in write-ahead-log
	unsigned int logSequenceNumber;

	//the first for syncing w/ NV server, as the ID cannot be encrypted
	CFUUIDBytes uniqueNoteIDBytes;

	NSMutableDictionary *syncServicesMD;
}

- (NSComparisonResult)compareDateModified:(NoteObject *)other;

- (NSComparisonResult)compareDateCreated:(NoteObject *)other;

- (NSComparisonResult)compareLabels:(NoteObject *)other;

- (NSComparisonResult)compareTitles:(NoteObject *)other;

//syncing w/ server and from journal
- (CFUUIDBytes *)uniqueNoteIDBytes;

- (NSDictionary *)syncServicesMD;

- (unsigned int)logSequenceNumber;

- (void)incrementLSN;

- (BOOL)youngerThanLogObject:(id <SynchronizedNote>)obj;

//syncing w/ files in directory
@property(nonatomic, copy, readonly) NSString *filename;
@property(nonatomic, readonly) NoteStorageFormat storageFormat;
@property(nonatomic, readonly) NSUInteger fileSize;
@property(nonatomic, copy, readonly) NSString *title;
@property(nonatomic, copy, readonly) NSString *labels;
@property(nonatomic, readonly) NSStringEncoding fileEncoding;
@property(nonatomic, strong, readonly) NSMutableArray *prefixParents;

@property (nonatomic, copy) NSDate *creationDate;
@property (nonatomic, copy) NSDate *modificationDate;
@property (nonatomic, copy, readonly) NSDate *contentModificationDate;
@property (nonatomic, copy, readonly) NSDate *attributesModificationDate;

@property (nonatomic, copy, readonly) NSURL *noteFileURL;

- (id)tableTitleOfNote;

- (id)unifiedCellSingleLineForTableView:(NotesTableView *)tv row:(NSInteger)row;

- (id)unifiedCellForTableView:(NotesTableView *)tv row:(NSInteger)row;

- (id)labelColumnCellForTableView:(NotesTableView *)tv row:(NSInteger)row;

@property (nonatomic, copy, readonly) NSString *dateCreatedString;
@property (nonatomic, copy, readonly) NSString *dateModifiedString;

id wordCountOfNote(NotesTableView *tv, NoteObject *note, NSInteger row);

BOOL noteContainsUTF8String(NoteObject *note, NoteFilterContext *context);

BOOL noteTitleHasPrefixOfUTF8String(NoteObject *note, const char *fullString, size_t stringLen);

BOOL noteTitleIsAPrefixOfOtherNoteTitle(NoteObject *longerNote, NoteObject *shorterNote);

@property(nonatomic, weak) id <NoteObjectDelegate, NTNFileManager> delegate;

- (id)initWithNoteBody:(NSAttributedString *)bodyText title:(NSString *)aNoteTitle
			  delegate:(id <NoteObjectDelegate, NTNFileManager>)aDelegate format:(NoteStorageFormat)formatID labels:(NSString *)aLabelString;

- (id)initWithCatalogEntry:(NoteCatalogEntry *)entry delegate:(id <NoteObjectDelegate, NTNFileManager>)aDelegate;

@property (nonatomic, copy, readonly) NSSet *labelSet;

- (void)replaceMatchingLabelSet:(NSSet *)aLabelSet;

- (void)replaceMatchingLabel:(LabelObject *)label;

- (void)updateLabelConnectionsAfterDecoding;

- (void)updateLabelConnections;

- (void)disconnectLabels;

- (void)setLabelString:(NSString *)newLabels;

- (NSMutableSet *)labelSetFromCurrentString;

- (NSArray *)orderedLabelTitles;

- (NSSize)sizeOfLabelBlocks;

- (void)drawLabelBlocksInRect:(NSRect)aRect rightAlign:(BOOL)onRight highlighted:(BOOL)isHighlighted;

- (void)setSyncObjectAndKeyMD:(NSDictionary *)aDict forService:(NSString *)serviceName;

- (void)removeAllSyncMDForService:(NSString *)serviceName;

- (void)updateWithSyncBody:(NSString *)newBody andTitle:(NSString *)newTitle;

- (void)registerModificationWithOwnedServices;

- (BOOL)setFileEncodingAndReinterpret:(NSStringEncoding)encoding;

- (BOOL)upgradeToUTF8IfUsingSystemEncoding;

- (BOOL)upgradeEncodingToUTF8;

- (BOOL)updateFromFile;

- (BOOL)updateFromCatalogEntry:(NoteCatalogEntry *)catEntry;

- (BOOL)updateFromData:(NSMutableData *)data inFormat:(int)fmt;

- (BOOL)writeFileDatesAndUpdateTrackingInfo;

- (NSURL *)uniqueNoteLink;

- (void)invalidateURL;

- (BOOL)writeUsingJournal:(WALStorageController *)wal;

- (BOOL)writeUsingCurrentFileFormatIfNecessary;

- (BOOL)writeUsingCurrentFileFormatIfNonExistingOrChanged;

- (BOOL)writeUsingCurrentFileFormat;

- (void)makeNoteDirtyUpdateTime:(BOOL)updateTime updateFile:(BOOL)updateFile;

- (void)moveFileToTrash;

- (BOOL)removeUsingJournal:(WALStorageController *)wal;

- (BOOL)exportToDirectory:(NSURL *)directory filename:(NSString *)userFilename format:(NoteStorageFormat)storageFormat overwrite:(BOOL)overwrite error:(out NSError **)outError;

- (NSRange)nextRangeForWords:(NSArray *)words options:(NSStringCompareOptions)opts range:(NSRange)inRange;

- (void)editExternallyUsingEditor:(ExternalEditor *)ed;

- (void)abortEditingInExternalEditor;

- (void)setFilenameFromTitle;

- (void)setFilename:(NSString *)aString withExternalTrigger:(BOOL)externalTrigger;

- (void)setTitleString:(NSString *)aNewTitle;

- (void)updateTablePreviewString;

- (void)initContentCacheCString;

- (void)updateContentCacheCStringIfNecessary;

@property(nonatomic, strong) NSAttributedString *contentString;

- (NSAttributedString *)printableStringRelativeToBodyFont:(NSFont *)bodyFont;

- (NSString *)combinedContentWithContextSeparator:(NSString *)sepWContext;

- (void)setForegroundTextColorOnly:(NSColor *)aColor;

- (void)resanitizeContent;

- (void)updateUnstyledTextWithBaseFont:(NSFont *)baseFont;

- (void)updateDateStrings;

@property (nonatomic) NSRange selectedRange;

- (BOOL)contentsWere7Bit;

- (void)addPrefixParentNote:(NoteObject *)aNote;

- (void)removeAllPrefixParentNotes;

@property (nonatomic, strong, readonly) NSUndoManager *undoManager;

@end
