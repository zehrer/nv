//
//  NoteObject.m
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


#import "NoteObject.h"
#import "GlobalPrefs.h"
#import "LabelObject.h"
#import "NotationController.h"
#import "AttributedPlainText.h"
#import "NSString_CustomTruncation.h"
#import "NSFileManager_NV.h"
#import "NotationSyncServiceManager.h"
#import "SyncSessionController.h"
#import "ExternalEditorListController.h"
#import "NSData_transformations.h"
#import "NSCollection_utils.h"
#import "UnifiedCell.h"
#import "LabelColumnCell.h"
#import "ODBEditor.h"
#import "NSString_NV.h"
#import "NSURL+Notation.h"
#import "NSDate+Notation.h"
#import "NoteCatalogEntry.h"
#import "NSError+Notation.h"

#if __LP64__
// Needed for compatability with data created by 32bit app
typedef struct NSRange32 {
	unsigned int location;
	unsigned int length;
} NSRange32;
#else
typedef NSRange NSRange32;
#endif

@interface NoteObject () {
	NSMutableAttributedString *_contentString;
	NSURL *_noteFileURL; // temporary while we migrate away from FSRef
}

@property(nonatomic, copy, readwrite) NSString *filename;
@property(nonatomic, readwrite) NoteStorageFormat storageFormat;
@property(nonatomic, readwrite) UInt32 fileSize;
@property(nonatomic, copy, readwrite) NSString *title;
@property(nonatomic, copy, readwrite) NSString *labels;
@property(nonatomic, readwrite) NSStringEncoding fileEncoding;
@property(nonatomic, strong, readwrite) NSMutableArray *prefixParents;

@property(nonatomic, strong, readwrite) NSDate *contentModificationDate;
@property(nonatomic, strong, readwrite) NSDate *attributesModificationDate;


@end

@implementation NoteObject

//syncing w/ server and from journal;

@synthesize filename = filename;
@synthesize storageFormat = currentFormatID;
@synthesize fileSize = logicalSize;
@synthesize title = titleString;
@synthesize labels = labelString;
@synthesize fileEncoding = fileEncoding;
@synthesize prefixParents = prefixParentNotes;

- (id)init {
	if ((self = [super init])) {

		currentFormatID = SingleDatabaseFormat;
		fileEncoding = NSUTF8StringEncoding;
		selectedRange = NSMakeRange(NSNotFound, 0);

		//other instance variables initialized on demand
	}

	return self;
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	[self invalidateFSRef];

	if (perDiskInfoGroups)
		free(perDiskInfoGroups);
}

- (void)setDelegate:(id <NoteObjectDelegate, NTNFileManager>)theDelegate {
	_delegate = theDelegate;

	id <NoteObjectDelegate, NTNFileManager> localDelegate = self.delegate;
	if (localDelegate) {
		//do things that ought to have been done during init, but were not possible due to lack of delegate information
		if (!self.filename) self.filename = [localDelegate uniqueFilenameForTitle:titleString fromNote:self];
		if (!tableTitleString && !didUnarchive) [self updateTablePreviewString];
		if (!labelSet && !didUnarchive) [self updateLabelConnectionsAfterDecoding];
	}
}

- (NSDate *)attributesModificationDate {
	if (!_attributesModificationDate) {
		if (perDiskInfoGroupCount) {
			id <NoteObjectDelegate, NTNFileManager> localDelegate = self.delegate;
			if (!localDelegate) return nil;

			//init from delegate based on disk table index
			NSUInteger i, tableIndex = [localDelegate diskUUIDIndex];

			for (i = 0; i < perDiskInfoGroupCount; i++) {
				//check if this date has actually been initialized; this entry could be here only because -setFileNoteID: was called
				if (perDiskInfoGroups[i].diskIDIndex == tableIndex && !UTCDateTimeIsEmpty(perDiskInfoGroups[i].attrTime)) {
					UTCDateTime time = perDiskInfoGroups[i].attrTime;
					_attributesModificationDate = [NSDate datewithUTCDateTime: &time];
					break;
				}
			}
		}

		//this note doesn't have a file-modified date, so initialize a fairly reasonable one here
		if (!_attributesModificationDate) {
			self.attributesModificationDate = self.contentModificationDate;
		}
	}
	return _attributesModificationDate;
}

NSInteger compareDateModified(id *a, id *b) {
	NoteObject *aObj = *(NoteObject **)a;
	NoteObject *bObj = *(NoteObject **)b;
	return [aObj.modificationDate compare: bObj.modificationDate];
}

NSInteger compareDateCreated(id *a, id *b) {
	NoteObject *aObj = *(NoteObject **)a;
	NoteObject *bObj = *(NoteObject **)b;
	return [aObj.creationDate compare: bObj.creationDate];
}

NSInteger compareLabelString(id *a, id *b) {
	return (NSInteger) CFStringCompare((CFStringRef) (*(NoteObject **) a).labels,
			(CFStringRef) (*(NoteObject **) b).labels, kCFCompareCaseInsensitive);
}

NSInteger compareTitleString(id *a, id *b) {
	//add kCFCompareNumerically to options for natural order sort
	CFComparisonResult stringResult = CFStringCompare((CFStringRef) (*(NoteObject **) a).title,
			(CFStringRef) (*(NoteObject **) b).title,
			kCFCompareCaseInsensitive);
	if (stringResult == kCFCompareEqualTo) {

		NSInteger dateResult = compareDateCreated(a, b);
		if (!dateResult)
			return compareUniqueNoteIDBytes(a, b);

		return dateResult;
	}

	return (NSInteger) stringResult;
}

- (NSComparisonResult)compareTitleStrings:(NoteObject *)other {
	NSComparisonResult result = [self.title caseInsensitiveCompare: other.title];
	
	if (result == NSOrderedSame) {
		__weak id weakSelf = self;

		result = compareDateCreated(&weakSelf, &other);
		if (!result) {
			result = compareUniqueNoteIDBytes(&weakSelf, &other);
		}

		if (result > 0)
			result = NSOrderedDescending;
		else if (result < 0)
			result = NSOrderedAscending;
		else
			result = NSOrderedSame;
	}

	return result;
}

NSInteger compareUniqueNoteIDBytes(id *a, id *b) {
	return memcmp((&(*(NoteObject **) a)->uniqueNoteIDBytes), (&(*(NoteObject **) b)->uniqueNoteIDBytes), sizeof(CFUUIDBytes));
}


NSInteger compareDateModifiedReverse(id *a, id *b) {
	NoteObject *aObj = *(NoteObject **)a;
	NoteObject *bObj = *(NoteObject **)b;
	return [bObj.modificationDate compare: aObj.modificationDate];
}

NSInteger compareDateCreatedReverse(id *a, id *b) {
	NoteObject *aObj = *(NoteObject **)a;
	NoteObject *bObj = *(NoteObject **)b;
	return [bObj.creationDate compare: aObj.creationDate];
}

NSInteger compareLabelStringReverse(id *a, id *b) {
	return (NSInteger) CFStringCompare((CFStringRef) (*(NoteObject **) b).labels,
			(CFStringRef) (*(NoteObject **) a).labels, kCFCompareCaseInsensitive);
}

NSInteger compareTitleStringReverse(id *a, id *b) {
	CFComparisonResult stringResult = CFStringCompare((CFStringRef) (*(NoteObject **) b).title,
			(CFStringRef) (*(NoteObject **) a).title,
			kCFCompareCaseInsensitive);

	if (stringResult == kCFCompareEqualTo) {
		NSInteger dateResult = compareDateCreatedReverse(a, b);
		if (!dateResult)
			return compareUniqueNoteIDBytes(b, a);

		return dateResult;
	}
	return (NSInteger) stringResult;
}

NSInteger compareFileSize(id *a, id *b) {
	return (*(NoteObject **) a)->logicalSize - (*(NoteObject **) b)->logicalSize;
}


#include "SynchronizedNoteMixIns.h"

//DefColAttrAccessor(wordCountOfNote, wordCountString)
DefColAttrAccessor(titleOfNote2, titleString)
DefColAttrAccessor(dateCreatedStringOfNote, dateCreatedString)
DefColAttrAccessor(dateModifiedStringOfNote, dateModifiedString)

force_inline id
tableTitleOfNote(NotesTableView *tv, NoteObject *note, NSInteger
row) {
	if (note->tableTitleString) return note->tableTitleString;
	return note.title;
}
force_inline id
properlyHighlightingTableTitleOfNote(NotesTableView *tv, NoteObject *note, NSInteger
row) {
	if (note->tableTitleString) {
		if ([tv isRowSelected:row]) {
			return [note->tableTitleString string];
		}
		return note->tableTitleString;
	}
	return note.title;
}

force_inline id
labelColumnCellForNote(NotesTableView *tv, NoteObject *note, NSInteger
row) {

	LabelColumnCell *cell = [[tv tableColumnWithIdentifier:NoteLabelsColumnString] dataCellForRow:row];
	[cell setNoteObject:note];

	return note.labels;
}

force_inline id
unifiedCellSingleLineForNote(NotesTableView *tv, NoteObject *note, NSInteger
row) {

	id obj = note->tableTitleString ? (id) note->tableTitleString : note.title;

	UnifiedCell *cell = [[tv tableColumns][0] dataCellForRow:row];
	[cell setNoteObject:note];
	[cell setPreviewIsHidden:YES];

	return obj;
}

force_inline id
unifiedCellForNote(NotesTableView *tv, NoteObject *note, NSInteger
row) {
	//snow leopard is stricter about applying the default highlight-attributes (e.g., no shadow unless no paragraph formatting)
	//so add the shadow here for snow leopard on selected rows

	UnifiedCell *cell = [[tv tableColumns][0] dataCellForRow:row];
	[cell setNoteObject:note];
	[cell setPreviewIsHidden:NO];

	BOOL rowSelected = [tv isRowSelected:row];
	BOOL drawShadow = YES;

	id obj = note->tableTitleString ? (rowSelected ? (id) AttributedStringForSelection(note->tableTitleString, drawShadow) :
			(id) note->tableTitleString) : note.title;


	return obj;
}

//make notationcontroller should send setDelegate: and setLabelString: (if necessary) to each note when unarchiving this way

//there is no measurable difference in speed when using decodeValuesOfObjCTypes, oddly enough
//the overhead of the _decodeObject* C functions must be significantly greater than the objc_msgSend and argument passing overhead
#define DECODE_INDIVIDUALLY 1

- (id)initWithCoder:(NSCoder *)decoder {
	if ((self = [self init])) {

		if ([decoder allowsKeyedCoding]) {
			//(hopefully?) no versioning necessary here

			//for knowing when to delay certain initializations during launch (e.g., preview generation)
			didUnarchive = YES;

			if ([decoder containsValueForKey: VAR_STR(creationDate)]) {
				self.creationDate = [decoder decodeObjectForKey: VAR_STR(creationDate)];
			} else if ([decoder containsValueForKey: VAR_STR(createdDate)]) {
				CFAbsoluteTime time = [decoder decodeDoubleForKey:VAR_STR(createdDate)];
				self.creationDate = [NSDate dateWithTimeIntervalSinceReferenceDate: time];
			}

			if ([decoder containsValueForKey: VAR_STR(modificationDate)]) {
				self.modificationDate = [decoder decodeObjectForKey: VAR_STR(modificationDate)];
			} else if ([decoder containsValueForKey: VAR_STR(modifiedDate)]) {
				CFAbsoluteTime time = [decoder decodeDoubleForKey:VAR_STR(modifiedDate)];
				self.modificationDate = [NSDate dateWithTimeIntervalSinceReferenceDate: time];
			}

			selectedRange.location = [decoder decodeIntegerForKey:@"selectionRangeLocation"];
			selectedRange.length = [decoder decodeIntegerForKey:@"selectionRangeLength"];
			contentsWere7Bit = [decoder decodeBoolForKey:VAR_STR(contentsWere7Bit)];

			logSequenceNumber = [decoder decodeInt32ForKey:VAR_STR(logSequenceNumber)];

			currentFormatID = [decoder decodeInt32ForKey:VAR_STR(currentFormatID)];
			logicalSize = [decoder decodeInt32ForKey:VAR_STR(logicalSize)];

			if ([decoder containsValueForKey: VAR_STR(contentModificationDate)]) {
				_contentModificationDate = [decoder decodeObjectForKey: VAR_STR(contentModificationDate)];
			} else if ([decoder containsValueForKey: VAR_STR(fileModifiedDate)]) {
				UTCDateTime time;
				int64_t oldDate = [decoder decodeInt64ForKey:VAR_STR(fileModifiedDate)];
				memcpy(&time, &oldDate, sizeof(int64_t));
				_contentModificationDate = [NSDate datewithUTCDateTime: &time];
			}

			if ([decoder containsValueForKey: VAR_STR(attributesModificationDate)]) {
				_attributesModificationDate = [decoder decodeObjectForKey: VAR_STR(attributesModificationDate)];
			} else if ([decoder containsValueForKey: VAR_STR(perDiskInfoGroups)]) {
				NSUInteger decodedPerDiskByteCount = 0;
				const uint8_t *decodedPerDiskBytes = [decoder decodeBytesForKey:VAR_STR(perDiskInfoGroups) returnedLength:&decodedPerDiskByteCount];
				if (decodedPerDiskBytes && decodedPerDiskByteCount) {
					CopyPerDiskInfoGroupsToOrder(&perDiskInfoGroups, &perDiskInfoGroupCount, decodedPerDiskBytes, decodedPerDiskByteCount, 1);
				}
			}

			fileEncoding = [decoder decodeIntegerForKey:VAR_STR(fileEncoding)];

			NSUInteger decodedUUIDByteCount = 0;
			const uint8_t *decodedUUIDBytes = [decoder decodeBytesForKey:VAR_STR(uniqueNoteIDBytes) returnedLength:&decodedUUIDByteCount];
			if (decodedUUIDBytes) memcpy(&uniqueNoteIDBytes, decodedUUIDBytes, MIN(decodedUUIDByteCount, sizeof(CFUUIDBytes)));

			syncServicesMD = [decoder decodeObjectForKey:VAR_STR(syncServicesMD)];

			titleString = [decoder decodeObjectForKey:VAR_STR(titleString)];
			labelString = [decoder decodeObjectForKey:VAR_STR(labelString)];
			self.contentString = [decoder decodeObjectForKey:VAR_STR(contentString)];
			filename = [decoder decodeObjectForKey:VAR_STR(filename)];

		}

		//re-created at runtime to save space
		[self initContentCacheCString];

		if (!titleString && !self.contentString && !labelString) return nil;
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {

	if ([coder allowsKeyedCoding]) {

		[coder encodeObject: self.modificationDate forKey: VAR_STR(modificationDate)];
		[coder encodeObject: self.creationDate forKey: VAR_STR(creationDate)];
		[coder encodeInteger:selectedRange.location forKey:@"selectionRangeLocation"];
		[coder encodeInteger:selectedRange.length forKey:@"selectionRangeLength"];
		[coder encodeBool:contentsWere7Bit forKey:VAR_STR(contentsWere7Bit)];

		[coder encodeInt32:logSequenceNumber forKey:VAR_STR(logSequenceNumber)];

		[coder encodeInt32:currentFormatID forKey:VAR_STR(currentFormatID)];
		[coder encodeInt32:logicalSize forKey:VAR_STR(logicalSize)];

		[coder encodeObject: self.contentModificationDate forKey: VAR_STR(contentModificationDate)];
		[coder encodeObject: self.attributesModificationDate forKey: VAR_STR(attributesModificationDate)];

		[coder encodeInteger:fileEncoding forKey:VAR_STR(fileEncoding)];

		[coder encodeBytes:(const uint8_t *) &uniqueNoteIDBytes length:sizeof(CFUUIDBytes) forKey:VAR_STR(uniqueNoteIDBytes)];
		[coder encodeObject:syncServicesMD forKey:VAR_STR(syncServicesMD)];

		[coder encodeObject:titleString forKey:VAR_STR(titleString)];
		[coder encodeObject:labelString forKey:VAR_STR(labelString)];
		[coder encodeObject:self.contentString forKey:VAR_STR(contentString)];
		[coder encodeObject:filename forKey:VAR_STR(filename)];

	}
}

- (id)initWithNoteBody:(NSAttributedString *)bodyText title:(NSString *)aNoteTitle delegate:(id <NoteObjectDelegate, NTNFileManager>)aDelegate format:(NoteStorageFormat)formatID labels:(NSString *)aLabelString {
	//delegate optional here
	if ((self = [self init])) {

		if (!bodyText || !aNoteTitle) {
			return nil;
		}

		self.delegate = aDelegate;
		id <NoteObjectDelegate, NTNFileManager> localDelegate = aDelegate;

		self.contentString = [[NSMutableAttributedString alloc] initWithAttributedString:bodyText];
		[self initContentCacheCString];

		if (![self _setTitleString:aNoteTitle])
			titleString = NSLocalizedString(@"Untitled Note", @"Title of a nameless note");

		if (![self _setLabelString:aLabelString]) {
			labelString = @"";
		}

		currentFormatID = formatID;
		filename = [localDelegate uniqueFilenameForTitle:titleString fromNote:nil];

		CFUUIDRef uuidRef = CFUUIDCreate(kCFAllocatorDefault);
		uniqueNoteIDBytes = CFUUIDGetUUIDBytes(uuidRef);
		CFRelease(uuidRef);

		self.creationDate = self.modificationDate = [NSDate date];
		dateModifiedString = [NSString relativeDateStringWithAbsoluteTime: self.modificationDate.timeIntervalSinceReferenceDate];
		_contentModificationDate = self.modificationDate;

		if (localDelegate) [self updateTablePreviewString];
	}

	return self;
}

//only get the fsrefs until we absolutely need them
- (id)initWithCatalogEntry:(NoteCatalogEntry *)entry delegate:(id<NoteObjectDelegate,NTNFileManager>)aDelegate {
	NSParameterAssert(aDelegate);

	if ((self = [self init])) {
		self.delegate = aDelegate;
		id <NoteObjectDelegate, NTNFileManager> localDelegate = aDelegate;
		self.filename = (__bridge NSMutableString *)entry.filename;
		self.storageFormat = [localDelegate currentNoteStorageFormat];
		UTCDateTime lastModified = entry.lastModified;
		self.contentModificationDate = [NSDate datewithUTCDateTime: &lastModified];
		UTCDateTime lastAttrModified = entry.lastAttrModified;
		self.attributesModificationDate = [NSDate datewithUTCDateTime: &lastAttrModified];
		self.fileSize = entry.logicalSize;
		self.creationDate = entry.creationDate;

		CFUUIDRef uuidRef = CFUUIDCreate(kCFAllocatorDefault);
		uniqueNoteIDBytes = CFUUIDGetUUIDBytes(uuidRef);
		CFRelease(uuidRef);

		if (![self _setTitleString:[filename stringByDeletingPathExtension]])
			titleString = NSLocalizedString(@"Untitled Note", @"Title of a nameless note");

		labelString = @""; //set by updateFromCatalogEntry if there are openmeta extended attributes

		self.contentString = [[NSMutableAttributedString alloc] initWithString:@""];
		[self initContentCacheCString];

		if (![self updateFromCatalogEntry:entry]) {
			//just initialize a blank note for now; if the file becomes readable again we'll be updated
			//but if we make modifications, well, the original is toast
			//so warn the user here and offer to trash it?
			//perhaps also offer to re-interpret using another text encoding?

			//additionally, it is possible that the file was deleted before we could read it
		}
		if (!self.modificationDate || !self.creationDate) {
			self.modificationDate = self.creationDate = [NSDate date];
			dateModifiedString = [NSString relativeDateStringWithAbsoluteTime: self.modificationDate.timeIntervalSinceReferenceDate];
		}
	}

	[self updateTablePreviewString];

	return self;

}

//assume any changes have been synchronized with undomanager
- (void)setContentString:(NSAttributedString *)attributedString {
	if (attributedString) {
		if (!_contentString)
			_contentString = [attributedString mutableCopy];
		else
			[_contentString setAttributedString:attributedString];

		[self updateTablePreviewString];
		contentCacheNeedsUpdate = YES;
		//[self updateContentCacheCStringIfNecessary];

		id <NoteObjectDelegate, NTNFileManager> localDelegate = self.delegate;
		if (localDelegate) [localDelegate note:self attributeChanged:NotePreviewString];

		[self makeNoteDirtyUpdateTime:YES updateFile:YES];
	}
}

- (void)updateContentCacheCStringIfNecessary {
	if (contentCacheNeedsUpdate) {
		contentsWere7Bit = self.contentString.string.containsHighASCII;
	}
}

- (void)initContentCacheCString {
	if (contentsWere7Bit) {
		if (!self.contentString.string.couldCopyLowercaseASCIIString) contentsWere7Bit = NO;
	} else {
		contentsWere7Bit = self.contentString ? !self.contentString.string.containsHighASCII : NO;
	}
}

- (BOOL)contentsWere7Bit {
	return contentsWere7Bit;
}

- (NSString *)description {
	return syncServicesMD ? [NSString stringWithFormat:@"%@ / %@", titleString, syncServicesMD] : titleString;
}

- (NSString *)combinedContentWithContextSeparator:(NSString *)sepWContext {
	//combine title and body based on separator data usually generated by -syntheticTitleAndSeparatorWithContext:bodyLoc:
	//if separator does not exist or chars do not match trailing and leading chars of title and body, respectively,
	//then just delimit with a double-newline

	NSString *content = self.contentString.string;

	BOOL defaultJoin = NO;
	if (![sepWContext length] || ![content length] || ![titleString length] ||
			[titleString characterAtIndex:[titleString length] - 1] != [sepWContext characterAtIndex:0] ||
			[content characterAtIndex:0] != [sepWContext characterAtIndex:[sepWContext length] - 1]) {
		defaultJoin = YES;
	}

	NSString *separator = @"\n\n";

	//if the separator lacks any actual separating characters, then concatenate with an empty string
	if (!defaultJoin) {
		separator = [sepWContext length] > 2 ? [sepWContext substringWithRange:NSMakeRange(1, [sepWContext length] - 2)] : @"";
	}

	NSMutableString *combined = [[NSMutableString alloc] initWithCapacity:[content length] + [titleString length] + [separator length]];

	[combined appendString:titleString];
	[combined appendString:separator];
	[combined appendString:content];

	return combined;
}


- (NSAttributedString *)printableStringRelativeToBodyFont:(NSFont *)bodyFont {
	NSFont *titleFont = [NSFont fontWithName:[bodyFont fontName] size:[bodyFont pointSize] + 6.0f];

	NSDictionary *dict = @{NSFontAttributeName : titleFont};

	NSMutableAttributedString *largeAttributedTitleString = [[NSMutableAttributedString alloc] initWithString:titleString attributes:dict];

	NSAttributedString *noAttrBreak = [[NSAttributedString alloc] initWithString:@"\n\n\n" attributes:nil];
	[largeAttributedTitleString appendAttributedString:noAttrBreak];

	//other header things here, too? like date created/mod/printed? tags?
	NSMutableAttributedString *contentMinusColor = [[self contentString] mutableCopy];
	[contentMinusColor removeAttribute:NSForegroundColorAttributeName range:NSMakeRange(0, [contentMinusColor length])];

	[largeAttributedTitleString appendAttributedString:contentMinusColor];


	return largeAttributedTitleString;
}

- (void)updateTablePreviewString {
	//delegate required for this method
	GlobalPrefs *prefs = [GlobalPrefs defaultPrefs];
	id <NoteObjectDelegate, NTNFileManager> localDelegate = self.delegate;

	if ([prefs tableColumnsShowPreview]) {
		if ([prefs horizontalLayout]) {
			//is called for visible notes at launch and resize only, generation of images for invisible notes is delayed until after launch

			NSSize labelBlockSize = ColumnIsSet(NoteLabelsColumn, [prefs tableColumnsBitmap]) ? [self sizeOfLabelBlocks] : NSZeroSize;
			tableTitleString = [titleString attributedMultiLinePreviewFromBodyText:self.contentString upToWidth:[localDelegate titleColumnWidth]
																	intrusionWidth:labelBlockSize.width];
		} else {
			tableTitleString = [titleString attributedSingleLinePreviewFromBodyText:self.contentString upToWidth:[localDelegate titleColumnWidth]];
		}
	} else {
		if ([prefs horizontalLayout]) {
			tableTitleString = [titleString attributedSingleLineTitle];
		} else {
			tableTitleString = nil;
		}
	}
}

- (void)setTitleString:(NSString *)aNewTitle {
	if ([self _setTitleString:aNewTitle]) {
		//do you really want to do this when the format is a single DB and the file on disk hasn't been removed?
		//the filename could get out of sync if we lose the fsref and we could end up with a second file after note is rewritten

		//solution: don't change the name in that case and allow its new name to be generated
		//when the format is changed and the file rewritten?
		id <NoteObjectDelegate, NTNFileManager> localDelegate = self.delegate;

		//however, the filename is used for exporting and potentially other purposes, so we should also update
		//it if we know that is has no currently existing (older) counterpart in the notes directory

		//woe to the exporter who also left the note files in the notes directory after switching to a singledb format
		//his note names might not be up-to-date
		if ([localDelegate currentNoteStorageFormat] != SingleDatabaseFormat ||
				!(_noteFileURL = [localDelegate notesDirectoryContainsFile: filename returningFSRef: self.noteFileRef])) {
			
			[self setFilenameFromTitle];
		}

		//yes, the given extension could be different from what we had before
		//but makeNoteDirty will eventually cause it to be re-written in the current format
		//and thus the format ID will be changed if that was the case
		[self makeNoteDirtyUpdateTime:YES updateFile:YES];

		[self updateTablePreviewString];

		/*NSUndoManager *undoMan = [delegate undoManager];
		[undoMan registerUndoWithTarget:self selector:@selector(setTitleString:) object:oldTitle];
		if (![undoMan isUndoing] && ![undoMan isRedoing])
			[undoMan setActionName:[NSString stringWithFormat:@"Rename Note \"%@\"", titleString]];
		*/

		[localDelegate note:self attributeChanged:NoteTitleColumnString];
	}
}

- (BOOL)_setTitleString:(NSString *)aNewTitle {
	if (!aNewTitle || ![aNewTitle length] || (titleString && [aNewTitle isEqualToString:titleString]))
		return NO;

	titleString = [aNewTitle copy];

	return YES;
}

- (void)setFilenameFromTitle {
	id <NoteObjectDelegate, NTNFileManager> localDelegate = self.delegate;
	[self setFilename:[localDelegate uniqueFilenameForTitle:titleString fromNote:self] withExternalTrigger:NO];
}

- (void)setFilename:(NSString *)aString withExternalTrigger:(BOOL)externalTrigger {
	id <NoteObjectDelegate, NTNFileManager> localDelegate = self.delegate;

	if (!filename || ![aString isEqualToString:filename]) {
		NSString *oldName = filename;
		filename = [aString copy];

		if (!externalTrigger) {
			if ([localDelegate noteFileRenamed:self.noteFileRef fromName:oldName toName:filename] != noErr) {
				NSLog(@"Couldn't rename note %@", titleString);

				//revert name
				filename = oldName;
				return;
			}
		} else {
			[self _setTitleString:[aString stringByDeletingPathExtension]];

			[self updateTablePreviewString];
			[localDelegate note:self attributeChanged:NoteTitleColumnString];
		}

		[self makeNoteDirtyUpdateTime:YES updateFile:NO];

		[localDelegate updateLinksToNote:self fromOldName:oldName];
		//update all the notes that link to the old filename as well!!

	}
}

- (void)setForegroundTextColorOnly:(NSColor *)aColor {
	//called when notationPrefs font doesn't match globalprefs font, or user changes the font
	[_contentString removeAttribute:NSForegroundColorAttributeName range:NSMakeRange(0, self.contentString.length)];
	if (aColor) {
		[_contentString addAttribute:NSForegroundColorAttributeName value:aColor range:NSMakeRange(0, self.contentString.length)];
	}
}

- (void)_resanitizeContent {
	[_contentString santizeForeignStylesForImporting];

	//renormalize the title, in case it is still somehow derived from decomposed HFS+ filenames
	CFMutableStringRef normalizedString = CFStringCreateMutableCopy(NULL, 0, (CFStringRef) titleString);
	CFStringNormalize(normalizedString, kCFStringNormalizationFormC);

	[self _setTitleString:[(__bridge NSString *) normalizedString copy]];
	if (normalizedString) CFRelease(normalizedString);

	id <NoteObjectDelegate, NTNFileManager> localDelegate = self.delegate;
	if (localDelegate && [localDelegate currentNoteStorageFormat] == RTFTextFormat)
		[self makeNoteDirtyUpdateTime:NO updateFile:YES];
}

//how do we write a thousand RTF files at once, repeatedly? 

- (void)updateUnstyledTextWithBaseFont:(NSFont *)baseFont {

	if ([_contentString restyleTextToFont:[[GlobalPrefs defaultPrefs] noteBodyFont] usingBaseFont:baseFont] > 0) {
		[undoManager removeAllActions];

		id <NoteObjectDelegate, NTNFileManager> localDelegate = self.delegate;
		if (localDelegate && [localDelegate currentNoteStorageFormat] == RTFTextFormat)
			[self makeNoteDirtyUpdateTime:NO updateFile:YES];
	}
}

- (void)updateDateStrings {
	dateCreatedString = [NSString relativeDateStringWithAbsoluteTime: self.creationDate.timeIntervalSinceReferenceDate];
	dateModifiedString = [NSString relativeDateStringWithAbsoluteTime: self.modificationDate.timeIntervalSinceReferenceDate];
}

- (void)setCreationDate:(NSDate *)creationDate {
	_creationDate = creationDate;
	dateCreatedString = [NSString relativeDateStringWithAbsoluteTime: self.creationDate.timeIntervalSinceReferenceDate];
}

- (void)setModificationDate:(NSDate *)modificationDate {
	_modificationDate = modificationDate;
	dateModifiedString = [NSString relativeDateStringWithAbsoluteTime: self.modificationDate.timeIntervalSinceReferenceDate];
}


- (void)setSelectedRange:(NSRange)newRange {
	//if (!newRange.length) newRange = NSMakeRange(0,0);

	//don't save the range if it's invalid, it's equal to the current range, or the entire note is selected
	if ((newRange.location != NSNotFound) && !NSEqualRanges(newRange, selectedRange) &&
			!NSEqualRanges(newRange, NSMakeRange(0, self.contentString.length))) {
		//	NSLog(@"saving: old range: %@, new range: %@", NSStringFromRange(selectedRange), NSStringFromRange(newRange));
		selectedRange = newRange;
		[self makeNoteDirtyUpdateTime:NO updateFile:NO];
	}
}

- (NSRange)lastSelectedRange {
	return selectedRange;
}

//these two methods let us get the actual label objects in use by other notes
//they assume that the label string already contains the title of the label object(s); that there is only replacement and not addition
- (void)replaceMatchingLabelSet:(NSSet *)aLabelSet {
	[labelSet minusSet:aLabelSet];
	[labelSet unionSet:aLabelSet];
}

- (void)replaceMatchingLabel:(LabelObject *)aLabel {
	// just in case this is actually the same label

	//remove the old label and add the new one; if this is the same one, well, too bad
	[labelSet removeObject:aLabel];
	[labelSet addObject:aLabel];
}

- (void)updateLabelConnectionsAfterDecoding {
	if ([labelString length] > 0) {
		[self updateLabelConnections];
	}
}

- (void)updateLabelConnections {
	//find differences between previous labels and new ones
	id <NoteObjectDelegate, NTNFileManager> localDelegate = self.delegate;
	if (localDelegate) {
		NSMutableSet *oldLabelSet = labelSet;
		NSMutableSet *newLabelSet = [self labelSetFromCurrentString];

		if (!oldLabelSet) {
			oldLabelSet = labelSet = [[NSMutableSet alloc] initWithCapacity:[newLabelSet count]];
		}

		//what's left-over
		NSMutableSet *oldLabels = [oldLabelSet mutableCopy];
		[oldLabels minusSet:newLabelSet];

		//what wasn't there last time
		NSMutableSet *newLabels = newLabelSet;
		[newLabels minusSet:oldLabelSet];

		//update the currently known labels
		[labelSet minusSet:oldLabels];
		[labelSet unionSet:newLabels];

		//update our status within the list of all labels, adding or removing from the list and updating the labels where appropriate
		//these end up calling replaceMatchingLabel*
		[localDelegate note:self didRemoveLabelSet:oldLabels];
		[localDelegate note:self didAddLabelSet:newLabels];

	}
}

- (void)disconnectLabels {
	//when removing this note from NotationController, other LabelObjects as well as the label controller should know not to list it
	id <NoteObjectDelegate, NTNFileManager> localDelegate = self.delegate;
	if (localDelegate) {
		[localDelegate note:self didRemoveLabelSet:labelSet];
		labelSet = nil;
	} else {
		NSLog(@"not disconnecting labels because no delegate exists");
	}
}

- (BOOL)_setLabelString:(NSString *)newLabelString {
	if (newLabelString && ![newLabelString isEqualToString:labelString]) {

		labelString = [newLabelString copy];

		[self updateLabelConnections];
		return YES;
	}
	return NO;
}

- (void)setLabelString:(NSString *)newLabelString {

	if ([self _setLabelString:newLabelString]) {

		if ([[GlobalPrefs defaultPrefs] horizontalLayout]) {
			[self updateTablePreviewString];
		}

		[self makeNoteDirtyUpdateTime:YES updateFile:YES];
		//[self registerModificationWithOwnedServices];

		id <NoteObjectDelegate, NTNFileManager> localDelegate = self.delegate;
		[localDelegate note:self attributeChanged:NoteLabelsColumnString];
	}
}

- (NSMutableSet *)labelSetFromCurrentString {

	NSArray *words = [self orderedLabelTitles];
	NSMutableSet *newLabelSet = [NSMutableSet setWithCapacity:[words count]];

	unsigned int i;
	for (i = 0; i < [words count]; i++) {
		NSString *aWord = words[i];

		if ([aWord length] > 0) {
			LabelObject *aLabel = [[LabelObject alloc] initWithTitle:aWord];
			[aLabel addNote:self];
			[newLabelSet addObject:aLabel];
		}
	}

	return newLabelSet;
}


- (NSArray *)orderedLabelTitles {
	return [labelString labelCompatibleWords];
}

- (NSSize)sizeOfLabelBlocks {
	NSSize size = NSZeroSize;
	[self _drawLabelBlocksInRect:NSZeroRect rightAlign:NO highlighted:NO getSizeOnly:&size];
	return size;
}

- (void)drawLabelBlocksInRect:(NSRect)aRect rightAlign:(BOOL)onRight highlighted:(BOOL)isHighlighted {
	return [self _drawLabelBlocksInRect:aRect rightAlign:onRight highlighted:isHighlighted getSizeOnly:NULL];
}

- (void)_drawLabelBlocksInRect:(NSRect)aRect rightAlign:(BOOL)onRight highlighted:(BOOL)isHighlighted getSizeOnly:(NSSize *)reqSize {
	//used primarily by UnifiedCell, but also by LabelColumnCell, as well as to determine the width of all label-block-images for this note
	//iterate over words in orderedLabelTitles, retrieving images via -[NotationController cachedLabelImageForWord:highlighted:]
	//if right-align is enabled, then the label-images are queued on the first pass and drawn in reverse on the second

	float totalWidth = 0.0, height = 0.0;

	if (labelString.length) {
		NSPoint nextBoxPoint = onRight ? NSMakePoint(NSMaxX(aRect), aRect.origin.y) : aRect.origin;

		for (NSString *word in self.orderedLabelTitles) {
			if (word.length) {
				id <NoteObjectDelegate, NTNFileManager> localDelegate = self.delegate;
				NSImage *img = localDelegate ? [localDelegate cachedLabelImageForWord:word highlighted:isHighlighted] : nil;

				if (!reqSize) {
					if (onRight) {
						nextBoxPoint.x -= [img size].width + 4.0;
						[img compositeToPoint:nextBoxPoint operation:NSCompositeSourceOver];
					} else {
						[img compositeToPoint:nextBoxPoint operation:NSCompositeSourceOver];
						nextBoxPoint.x += [img size].width + 4.0;
					}
				} else {
					totalWidth += [img size].width + 4.0;
					height = MAX(height, [img size].height);
				}
			}
		}
	}

	if (reqSize) *reqSize = NSMakeSize(totalWidth, height);
}


- (NSURL *)uniqueNoteLink {

	NSArray *svcs = [[SyncSessionController class] allServiceNames];
	NSMutableDictionary *idsDict = [NSMutableDictionary dictionaryWithCapacity:[svcs count] + 1];

	//include all identifying keys in case the title changes later
	NSUInteger i = 0;
	for (i = 0; i < [svcs count]; i++) {
		NSString *syncID = syncServicesMD[svcs[i]][[[SyncSessionController allServiceClasses][i] nameOfKeyElement]];
		if (syncID) idsDict[svcs[i]] = syncID;
	}
	idsDict[@"NV"] = [[NSData dataWithBytes:&uniqueNoteIDBytes length:16] encodeBase64];

	return [NSURL URLWithString:[@"nv://find/" stringByAppendingFormat:@"%@/?%@", [titleString stringWithPercentEscapes],
																	   [idsDict URLEncodedString]]];
}

- (NSString *)noteFilePath {
	UniChar chars[256];
	id <NoteObjectDelegate, NTNFileManager> localDelegate = self.delegate;
	if (localDelegate && [localDelegate refreshFileRefIfNecessary: self.noteFileRef withName:filename charsBuffer:chars] == noErr)
		return self.noteFileURL.path;
	return nil;
}

- (void)invalidateFSRef {
	//bzero(&noteFileRef, sizeof(FSRef));
	if (noteFileRef)
		free(noteFileRef);
	noteFileRef = NULL;
}

- (BOOL)writeUsingCurrentFileFormatIfNecessary {
	//if note had been updated via makeNoteDirty and needed file to be rewritten
	if (shouldWriteToFile) {
		return [self writeUsingCurrentFileFormat];
	}
	return NO;
}

- (BOOL)writeUsingCurrentFileFormatIfNonExistingOrChanged {
	BOOL fileWasCreated = NO;
	BOOL fileIsOwned = NO;
	id <NoteObjectDelegate, NTNFileManager> localDelegate = self.delegate;

	if ((_noteFileURL = [localDelegate createFileWithNameIfNotPresentInNotesDirectory: filename created: &fileWasCreated error: NULL])) {
		[_noteFileURL getFSRef: self.noteFileRef];
	} else {
		return NO;
	}

	if (fileWasCreated) {
		NSLog(@"writing note %@, because it didn't exist", titleString);
		return [self writeUsingCurrentFileFormat];
	}

	//createFileWithNameIfNotPresentInNotesDirectory: works by name, so if this file is not owned by us at this point, it was a race with moving it
	FSCatalogInfo info;
	if (localDelegate && [localDelegate fileInNotesDirectory: self.noteFileRef isOwnedByUs:&fileIsOwned hasCatalogInfo:&info] != noErr)
		return NO;

	NSDate *lastTime = self.contentModificationDate;
	NSDate *timeOnDisk = [NSDate datewithUTCDateTime: &info.contentModDate];

	if ([lastTime isGreaterThan: timeOnDisk]) {
		NSLog(@"writing note %@, because it was modified", titleString);
		return [self writeUsingCurrentFileFormat];
	}

	return YES;
}

- (BOOL)writeUsingJournal:(WALStorageController *)wal {
	BOOL wroteAllOfNote = [wal writeEstablishedNote:self];

	if (wroteAllOfNote) {
		//update formatID to absolutely ensure we don't reload an earlier note back from disk, from text encoding menu, for example
		//currentFormatID = SingleDatabaseFormat;
	} else {
		id <NoteObjectDelegate, NTNFileManager> localDelegate = self.delegate;
		[localDelegate noteDidNotWrite:self errorCode:kWriteJournalErr];
	}

	return wroteAllOfNote;
}

- (BOOL)writeUsingCurrentFileFormat {

	NSData *formattedData = nil;
	NSError *error = nil;
	NSMutableAttributedString *contentMinusColor = nil;

	id <NoteObjectDelegate, NTNFileManager> localDelegate = self.delegate;
	NoteStorageFormat formatID = [localDelegate currentNoteStorageFormat];
	switch (formatID) {
		case SingleDatabaseFormat:
			//we probably shouldn't be here
			NSAssert(NO, @"Warning! Tried to write data for an individual note in single-db format!");

			return NO;
		case PlainTextFormat:

			if (!(formattedData = [self.contentString.string dataUsingEncoding:fileEncoding allowLossyConversion:NO])) {

				//just make the file unicode and ram it through
				//unicode is probably better than UTF-8, as it's more easily auto-detected by other programs via the BOM
				//but we can auto-detect UTF-8, so what the heck
				[self _setFileEncoding:NSUTF8StringEncoding];
				//maybe we could rename the file file.utf8.txt here
				NSLog(@"promoting to unicode (UTF-8)");
				formattedData = [self.contentString.string dataUsingEncoding:fileEncoding allowLossyConversion:YES];
			}
			break;
		case RTFTextFormat:
			contentMinusColor = [self.contentString mutableCopy];
			[contentMinusColor removeAttribute:NSForegroundColorAttributeName range:NSMakeRange(0, [contentMinusColor length])];
			formattedData = [contentMinusColor RTFFromRange:NSMakeRange(0, [contentMinusColor length]) documentAttributes:nil];

			break;
		case HTMLFormat:
			//export to HTML document here using NSHTMLTextDocumentType;
			formattedData = [self.contentString dataFromRange:NSMakeRange(0, self.contentString.length)
										   documentAttributes:@{NSDocumentTypeDocumentAttribute : NSHTMLTextDocumentType} error:&error];
			//our links will always be to filenames, so hopefully we shouldn't have to change anything
			break;
		default:
			NSLog(@"Attempted to write using unknown format ID: %ld", formatID);
			//return NO;
	}

	if (formattedData) {
		BOOL resetFilename = NO;
		if (!filename || currentFormatID != formatID) {
			//file will (probably) be renamed
			//NSLog(@"resetting the file name due to format change: to %d from %d", formatID, currentFormatID);
			[self setFilenameFromTitle];
			resetFilename = YES;
		}

		currentFormatID = formatID;

		//perhaps check here to see if the file was updated on disk before we had a chance to do it ourselves
		//see if the file's fileModDate (if it exists) is newer than this note's current fileModificationDate
		//could offer to merge or revert changes

		NSURL *newNoteFileURL = nil; // change this to the noteFileURL ivar one day
		if ((newNoteFileURL = [localDelegate writeDataToNotesDirectory: formattedData withName: filename verifyUsingBlock: NULL error: &error])) {
			[newNoteFileURL getFSRef: self.noteFileRef];
		} else {
			NSLog(@"Unable to save note file %@", filename);
			[localDelegate noteDidNotWrite:self error: error];
			return NO;
		}
		
		//if writing plaintext set the file encoding with setxattr
		if (PlainTextFormat == formatID) {
			(void) [self writeCurrentFileEncodingToFSRef: self.noteFileRef];
		}

		[NSFileManager setOpenMetaTags: self.orderedLabelTitles forItemAtURL: self.noteFileURL error: NULL];

		//always hide the file extension for all types
		LSSetExtensionHiddenForRef(self.noteFileRef, TRUE);

		if (!resetFilename) {
			//NSLog(@"resetting the file name just because.");
			[self setFilenameFromTitle];
		}

		[self writeFileDatesAndUpdateTrackingInfo];

		//finished writing to file successfully
		shouldWriteToFile = NO;


		//tell any external editors that we've changed

	} else {
		[localDelegate noteDidNotWrite:self errorCode:kDataFormattingErr];
		NSLog(@"Unable to convert note contents into format %ld", formatID);
		return NO;
	}

	return YES;
}

- (BOOL)writeFileDatesAndUpdateTrackingInfo {
	if (SingleDatabaseFormat == currentFormatID) return YES;
	id <NoteObjectDelegate, NTNFileManager> localDelegate = self.delegate;

	//sync the file's creation and modification date:
	NSDictionary *attributes = @{NSURLCreationDateKey: self.creationDate, NSURLContentModificationDateKey: self.modificationDate};

	// if this method is called anywhere else, then use [delegate
	// refreshFileRefIfNecessary: self.noteFileRef withName:filename
	// charsBuffer:chars]; instead, for now, it is not called in any situations
	// where the fsref might accidentally point to a moved file
	NSError *error = nil;
	do {
		if (error || !_noteFileURL) {
			if (!(_noteFileURL = [localDelegate notesDirectoryContainsFile: filename returningFSRef: self.noteFileRef])) return NO;
		}
		[self.noteFileURL setResourceValues: attributes error: &error];
	} while (error.code == NSFileNoSuchFileError);

	if (error) {
		NSLog(@"could not set catalog info: %@", error);
		return NO;
		
	}

	//regardless of whether FSSetCatalogInfo was successful, the file mod date could still have changed
	OSStatus err = noErr;
	FSCatalogInfo catInfo;

	if ((err = [localDelegate fileInNotesDirectory: self.noteFileRef isOwnedByUs:NULL hasCatalogInfo:&catInfo]) != noErr) {
		NSLog(@"Unable to get new modification date of file %@: %d", filename, err);
		return NO;
	}

	self.contentModificationDate = [NSDate datewithUTCDateTime: &catInfo.contentModDate];
	self.attributesModificationDate = [NSDate datewithUTCDateTime: &catInfo.attributeModDate];
	self.fileSize = (UInt32) (catInfo.dataLogicalSize & 0xFFFFFFFF);

	NSDate *createDate = [NSDate datewithUTCDateTime: &catInfo.createDate];
	if ([self.creationDate compare: createDate] == NSOrderedDescending) {
		self.creationDate = createDate;
	}

	return YES;
}

- (OSStatus)writeCurrentFileEncodingToFSRef:(FSRef *)fsRef {
	NSAssert(fsRef, @"cannot write file encoding to a NULL FSRef");
	//this is not the note's own fsRef; it could be anywhere

	NSURL *URL = [NSURL URLWithFSRef: fsRef];
	if ([NSFileManager setTextEncoding: fileEncoding ofItemAtURL: URL]) {
		return noErr;
	}

	return ioErr;
}

- (BOOL)upgradeToUTF8IfUsingSystemEncoding {
	if (CFStringConvertEncodingToNSStringEncoding(CFStringGetSystemEncoding()) == fileEncoding)
		return [self upgradeEncodingToUTF8];
	return NO;
}

- (BOOL)upgradeEncodingToUTF8 {
	//"convert" the file to have a UTF-8 encoding
	BOOL didUpgrade = YES;

	id <NoteObjectDelegate, NTNFileManager> localDelegate = self.delegate;

	if (NSUTF8StringEncoding != fileEncoding) {
		[self _setFileEncoding:NSUTF8StringEncoding];

		if (!contentsWere7Bit && PlainTextFormat == currentFormatID) {
			//this note exists on disk as a plaintext file, and its encoding is incompatible with UTF-8

			if ([localDelegate currentNoteStorageFormat] == PlainTextFormat) {
				//actual conversion is expected because notes are presently being maintained as plain text files

				NSLog(@"rewriting %@ as utf8 data", titleString);
				didUpgrade = [self writeUsingCurrentFileFormat];
			} else if ([localDelegate currentNoteStorageFormat] == SingleDatabaseFormat) {
				//update last-written-filemod time to guarantee proper encoding at next DB storage format switch,
				//in case this note isn't otherwise modified before that happens.
				//a side effect is that if the user switches to an RTF or HTML format,
				//this note will be written immediately instead of lazily upon the next modification
				_contentModificationDate = [NSDate date];
			}
		}
		//make note dirty to ensure these changes are saved
		[self makeNoteDirtyUpdateTime:NO updateFile:NO];
	}
	return didUpgrade;
}

- (void)_setFileEncoding:(NSStringEncoding)encoding {
	fileEncoding = encoding;
}

- (BOOL)setFileEncodingAndReinterpret:(NSStringEncoding)encoding {
	//"reinterpret" the file using this encoding, also setting the actual file's extended attributes to match
	BOOL updated = YES;

	if (encoding != fileEncoding) {
		[self _setFileEncoding:encoding];

		//write the file encoding extended attribute before updating from disk. why?
		//a) to ensure -updateFromData: finds the right encoding when re-reading the file, and
		//b) because the file is otherwise not being rewritten, and the extended attribute--if it existed--may have been different

		id <NTNFileManager, SynchronizedNoteObjectDelegate> localDelegate = (id) self.delegate;

		UniChar chars[256];
		if ([localDelegate refreshFileRefIfNecessary: self.noteFileRef withName:filename charsBuffer:chars] != noErr)
			return NO;

		if ([self writeCurrentFileEncodingToFSRef: self.noteFileRef] != noErr)
			return NO;

		if ((updated = [self updateFromFile])) {
			[self makeNoteDirtyUpdateTime:NO updateFile:NO];
			//need to update modification time manually
			[self registerModificationWithOwnedServices];
			[localDelegate schedulePushToAllSyncServicesForNote:self];
			//[[delegate delegate] contentsUpdatedForNote:self];
		}
	}

	return updated;
}

- (BOOL)updateFromFile {
	id <NoteObjectDelegate, NTNFileManager> localDelegate = self.delegate;
	NSMutableData *data = [localDelegate dataFromFileInNotesDirectory: self.noteFileRef forFilename:filename];
	if (!data) {
		NSLog(@"Couldn't update note from file on disk");
		return NO;
	}

	if ([self updateFromData:data inFormat:currentFormatID]) {
		FSCatalogInfo info;
		if ([localDelegate fileInNotesDirectory: self.noteFileRef isOwnedByUs:NULL hasCatalogInfo:&info] == noErr) {
			self.contentModificationDate = [NSDate datewithUTCDateTime: &info.contentModDate];
			self.attributesModificationDate = [NSDate datewithUTCDateTime: &info.attributeModDate];
			self.fileSize = (UInt32) (info.dataLogicalSize & 0xFFFFFFFF);

			NSDate *createDate = [NSDate datewithUTCDateTime: &info.createDate];
			if ([self.creationDate compare: createDate] == NSOrderedDescending) {
				self.creationDate = createDate;
			}

			return YES;
		}
	}
	return NO;
}

- (BOOL)updateFromCatalogEntry:(NoteCatalogEntry *)catEntry {
	BOOL didRestoreLabels = NO;

	id <NoteObjectDelegate, NTNFileManager> localDelegate = self.delegate;

	NSMutableData *data = [localDelegate dataFromFileInNotesDirectory: self.noteFileRef forCatalogEntry:catEntry];
	if (!data) {
		NSLog(@"Couldn't update note from file on disk given catalog entry");
		return NO;
	}

	if (![self updateFromData:data inFormat:currentFormatID])
		return NO;

	[self setFilename:(__bridge NSString *) catEntry.filename withExternalTrigger:YES];

	UTCDateTime lastModified = catEntry.lastModified;
	UTCDateTime lastAttrModified = catEntry.lastAttrModified;
	self.contentModificationDate = [NSDate datewithUTCDateTime: &lastModified];
	self.attributesModificationDate = [NSDate datewithUTCDateTime: &lastAttrModified];
	self.fileSize = catEntry.logicalSize;

	if ([self.creationDate compare: catEntry.creationDate] == NSOrderedDescending) {
		self.creationDate = catEntry.creationDate;
	}

	NSArray *openMetaTags = [NSFileManager getOpenMetaTagsForItemAtURL: self.noteFileURL error: NULL];
	if (openMetaTags) {
		//overwrite this note's labels with those from the file; merging may be the wrong thing to do here
		if ([self _setLabelString:[openMetaTags componentsJoinedByString:@" "]])
			[self updateTablePreviewString];
	} else if ([labelString length]) {
		//this file has either never had tags or has had them cleared by accident (e.g., non-user intervention)
		//so if this note still has tags, then restore them now.

		NSLog(@"restoring lost tags for %@", titleString);
		[NSFileManager setOpenMetaTags: self.orderedLabelTitles forItemAtURL: self.noteFileURL error: NULL];
		didRestoreLabels = YES;
	}

	self.modificationDate = self.contentModificationDate;

	if (!self.creationDate || didRestoreLabels) {
		//when reading files from disk for the first time, grab their creation date
		//or if this file has just been altered, grab its newly-changed modification dates

		FSCatalogInfo info;
		if ([localDelegate fileInNotesDirectory: self.noteFileRef isOwnedByUs:NULL hasCatalogInfo:&info] == noErr) {
			if (!self.creationDate) self.creationDate = [NSDate datewithUTCDateTime: &info.createDate];
			
			if (didRestoreLabels) {
				self.contentModificationDate = [NSDate datewithUTCDateTime: &info.contentModDate];
				self.attributesModificationDate = [NSDate datewithUTCDateTime: &info.attributeModDate];
			}
		}
	}

	return YES;
}

- (BOOL)updateFromData:(NSMutableData *)data inFormat:(int)fmt {

	if (!data) {
		NSLog(@"%@: Data is nil!", NSStringFromSelector(_cmd));
		return NO;
	}

	NSMutableString *stringFromData = nil;
	NSMutableAttributedString *attributedStringFromData = nil;
	//interpret based on format; text, rtf, html, etc...
	switch (fmt) {
		case SingleDatabaseFormat:
			//hmmmmm
			NSAssert(NO, @"Warning! Tried to update data from a note in single-db format!");

			break;
		case PlainTextFormat:
			//try to merge/re-match attributes?
			if ((stringFromData = [NSMutableString newShortLivedStringFromData:data ofGuessedEncoding:&fileEncoding withPath:NULL orWithFSRef: self.noteFileRef])) {
				attributedStringFromData = [[NSMutableAttributedString alloc] initWithString:stringFromData
																				  attributes:[[GlobalPrefs defaultPrefs] noteBodyAttributes]];
			} else {
				NSLog(@"String could not be initialized from data");
			}

			break;
		case RTFTextFormat:

			attributedStringFromData = [[NSMutableAttributedString alloc] initWithRTF:data documentAttributes:NULL];
			break;
		case HTMLFormat:

			attributedStringFromData = [[NSMutableAttributedString alloc] initWithHTML:data documentAttributes:NULL];
			[attributedStringFromData removeAttachments];

			break;
		default:
			NSLog(@"%@: Unknown format: %d", NSStringFromSelector(_cmd), fmt);
	}

	if (!attributedStringFromData) {
		NSLog(@"Couldn't make string out of data for note %@ with format %d", titleString, fmt);
		return NO;
	}

	_contentString = attributedStringFromData;
	[_contentString santizeForeignStylesForImporting];
	//NSLog(@"%s(%@): %@", _cmd, [self noteFilePath], [contentString string]);

	//[contentString setAttributedString:attributedStringFromData];
	contentCacheNeedsUpdate = YES;
	[self updateContentCacheCStringIfNecessary];
	[undoManager removeAllActions];

	[self updateTablePreviewString];

	//don't update the date modified here, as this could be old data


	return YES;
}

- (void)updateWithSyncBody:(NSString *)newBody andTitle:(NSString *)newTitle {

	NSMutableAttributedString *attributedBodyString = [[NSMutableAttributedString alloc] initWithString:newBody attributes:[[GlobalPrefs defaultPrefs] noteBodyAttributes]];
	[attributedBodyString addLinkAttributesForRange:NSMakeRange(0, [attributedBodyString length])];
	[attributedBodyString addStrikethroughNearDoneTagsForRange:NSMakeRange(0, [attributedBodyString length])];

	//should eventually sync changes back to disk:
	[self setContentString:attributedBodyString];

	//actions that user-editing via AppDelegate would have handled for us:
	[self updateContentCacheCStringIfNecessary];
	[undoManager removeAllActions];

	[self setTitleString:newTitle];
}

- (void)moveFileToTrash {
	id <NoteObjectDelegate, NTNFileManager> localDelegate = self.delegate;
	NSError *err = nil;
	NSURL *URL = nil;
	if ((URL = [localDelegate moveFileToTrash: self.noteFileURL forFilename: filename error: &err])) {
		//file's gone! don't assume it's not coming back. if the storage format was not single-db, this note better be removed
		//currentFormatID = SingleDatabaseFormat;
		_noteFileURL = URL;
		[URL getFSRef: self.noteFileRef];
	} else {
		NSLog(@"Couldn't move file to trash: %@", err);
	}
}

- (void)removeFileFromDirectory {
	[self moveFileToTrash];
}

- (BOOL)removeUsingJournal:(WALStorageController *)wal {
	return [wal writeRemovalForNote:self];
}

- (void)registerModificationWithOwnedServices {
	//mirror this note's current mod date to services with which it is already synced
	//there is no point calling this method unless the modification time is
	[[SyncSessionController allServiceClasses] makeObjectsPerformSelector:@selector(registerLocalModificationForNote:) withObject:self];
}

- (void)removeAllSyncServiceMD {
	//potentially dangerous
	[syncServicesMD removeAllObjects];
}


- (void)makeNoteDirtyUpdateTime:(BOOL)updateTime updateFile:(BOOL)updateFile {

	if (updateFile)
		shouldWriteToFile = YES;
	//else we don't turn file updating off--we might be overwriting the state of a previous note-dirty message

	id <NoteObjectDelegate, SynchronizedNoteObjectDelegate> localDelegate = (id) self.delegate;

	if (updateTime) {
		self.modificationDate = [NSDate date];

		if ([localDelegate currentNoteStorageFormat] == SingleDatabaseFormat) {
			//only set if we're not currently synchronizing to avoid re-reading old data
			//this will be updated again when writing to a file, but for now we have the newest version
			//we must do this to allow new notes to be written when switching formats, and for encodingmanager checks
			self.contentModificationDate = self.modificationDate;
		}
	}
	if (updateFile && updateTime) {
		//if this is a change that affects the actual content of a note such that we would need to updateFile
		//and the modification time was actually updated, then dirty the note with the sync services, too
		[self registerModificationWithOwnedServices];
		[localDelegate schedulePushToAllSyncServicesForNote:self];
	}

	//queue note to be written
	[localDelegate scheduleWriteForNote:self];

	//tell delegate that the date modified changed
	//[delegate note:self attributeChanged:NoteDateModifiedColumnString];
	//except we don't want this here, as it will cause unnecessary (potential) re-sorting and updating of list view while typing
	//so expect the delegate to know to schedule the same update itself
}

- (BOOL)exportToDirectory:(NSURL *)directoryURL filename:(NSString *)userFilename format:(NoteStorageFormat)storageFormat overwrite:(BOOL)overwrite error:(out NSError **)outError {
	NSData *formattedData = nil;
	NSError *error = nil;

	NSMutableAttributedString *contentMinusColor = [self.contentString mutableCopy];
	[contentMinusColor removeAttribute:NSForegroundColorAttributeName range:NSMakeRange(0, [contentMinusColor length])];

	switch (storageFormat) {
		case SingleDatabaseFormat:
			NSAssert(NO, @"Warning! Tried to export data in single-db format!?");
		case PlainTextFormat:
			if (!(formattedData = [[contentMinusColor string] dataUsingEncoding:fileEncoding allowLossyConversion:NO])) {
				[self _setFileEncoding:NSUTF8StringEncoding];
				NSLog(@"promoting to unicode (UTF-8) on export--probably because internal format is singledb");
				formattedData = [[contentMinusColor string] dataUsingEncoding:fileEncoding allowLossyConversion:YES];
			}
			break;
		case RTFTextFormat:
			formattedData = [contentMinusColor RTFFromRange:NSMakeRange(0, [contentMinusColor length]) documentAttributes:nil];
			break;
		case HTMLFormat:
			formattedData = [contentMinusColor dataFromRange:NSMakeRange(0, [contentMinusColor length])
										  documentAttributes:@{NSDocumentTypeDocumentAttribute : NSHTMLTextDocumentType} error:&error];
			break;
		case WordDocFormat:
			formattedData = [contentMinusColor docFormatFromRange:NSMakeRange(0, [contentMinusColor length]) documentAttributes:nil];
			break;
		case WordXMLFormat:
			formattedData = [contentMinusColor dataFromRange:NSMakeRange(0, [contentMinusColor length])
										  documentAttributes:@{NSDocumentTypeDocumentAttribute : NSWordMLTextDocumentType} error:&error];
			break;
		default:
			NSLog(@"Attempted to export using unknown format ID: %ld", storageFormat);
	}

	if (!formattedData) {
		if (outError) *outError = [NSError errorWithDomain: NTNErrorDomain code: NTNDataFormattingError userInfo: nil];
		return NO;
	}

	//can use our already-determined filename to write here
	//but what about file names that were the same except for their extension? e.g., .txt vs. .text
	//this will give them the same extension and cause an overwrite
	NSString *newextension = [NotationPrefs pathExtensionForFormat:storageFormat];
	NSString *newfilename = userFilename ? userFilename : [[filename stringByDeletingPathExtension] stringByAppendingPathExtension:newextension];
	//one last replacing, though if the unique file-naming method worked this should be unnecessary
	newfilename = [newfilename stringByReplacingOccurrencesOfString:@":" withString:@"/"];

	NSURL *fileURL = [directoryURL URLByAppendingPathComponent: newfilename];

	if ([formattedData writeToURL: fileURL options: overwrite ? NSDataWritingAtomic : NSDataWritingWithoutOverwriting  error: &error]) {
		if (storageFormat == PlainTextFormat)
			[NSFileManager setTextEncoding: self.fileEncoding ofItemAtURL: fileURL];

		[NSFileManager setOpenMetaTags: self.orderedLabelTitles forItemAtURL: fileURL error: NULL];

		//also export the note's modification and creation dates
		[fileURL setResourceValues: @{
			  NSURLCreationDateKey: self.creationDate,
   NSURLContentModificationDateKey: self.modificationDate }
							 error: NULL];

		return YES;

	}

	return NO;
}

- (void)editExternallyUsingEditor:(ExternalEditor *)ed {
	[[ODBEditor sharedODBEditor] editNote:self inEditor:ed context:nil];
}

- (void)abortEditingInExternalEditor {
	[[ODBEditor sharedODBEditor] abortAllEditingSessionsForClient:self];
}

- (void)odbEditor:(ODBEditor *)editor didModifyFile:(NSString *)path newFileLocation:(NSString *)newPath  context:(NSDictionary *)context {

	//read path/newPath into NSData and update note contents

	//can't use updateFromCatalogEntry because it would assign ownership via various metadata

	if ([self updateFromData:[NSMutableData dataWithContentsOfFile:path options:NSUncachedRead error:NULL] inFormat:PlainTextFormat]) {
		//reflect the temp file's changes directly back to the backing-store-file, database, and sync services
		[self makeNoteDirtyUpdateTime:YES updateFile:YES];
		id <NoteObjectDelegate, NTNFileManager> localDelegate = self.delegate;
		[localDelegate note:self attributeChanged:NotePreviewString];
		[localDelegate noteDidUpdateContents:self];
	} else {
		NSBeep();
		NSLog(@"odbEditor:didModifyFile: unable to get data from %@", path);
	}
}

- (void)odbEditor:(ODBEditor *)editor didClosefile:(NSString *)path context:(NSDictionary *)context {
	//remove the temp file
	[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

- (NSRange)nextRangeForWords:(NSArray *)words options:(NSStringCompareOptions)opts range:(NSRange)inRange {
	//opts indicate forwards or backwards, inRange allows us to continue from where we left off
	//return location of NSNotFound and length 0 if none of the words could be found inRange

	//an optimization would be to fall back on cached cString if contentsWere7Bit is true, but then we have to handle opts ourselves
	NSUInteger i;
	NSString *haystack = self.contentString.string;
	NSRange nextRange = NSMakeRange(NSNotFound, 0);
	for (i = 0; i < [words count]; i++) {
		NSString *word = words[i];
		if ([word length] > 0) {
			nextRange = [haystack rangeOfString:word options:opts range:inRange];
			if (nextRange.location != NSNotFound && nextRange.length)
				break;
		}
	}

	return nextRange;
}

BOOL noteContainsUTF8String(NoteObject *note, NoteFilterContext *context) {
	NSString *needleStr = @(context->needle);

	BOOL foundInTitle = ([note.title rangeOfString:needleStr options:NSCaseInsensitiveSearch].location != NSNotFound);
	BOOL foundInContents = ([note.contentString.string rangeOfString:needleStr options:NSCaseInsensitiveSearch].location != NSNotFound);
	BOOL foundInLabel = ([note.labels rangeOfString:needleStr options:NSCaseInsensitiveSearch].location != NSNotFound);

	return foundInContents || foundInTitle || foundInLabel;
}

BOOL noteTitleHasPrefixOfUTF8String(NoteObject *note, const char *fullString, size_t stringLen) {
	return [note.title hasPrefix:@(fullString)];
}

BOOL noteTitleIsAPrefixOfOtherNoteTitle(NoteObject *longerNote, NoteObject *shorterNote) {
	return [longerNote.title hasPrefix:shorterNote.title];
}

- (void)addPrefixParentNote:(NoteObject *)aNote {
	if (!prefixParentNotes) {
		prefixParentNotes = [@[aNote] mutableCopy];
	} else {
		[prefixParentNotes addObject:aNote];
	}
}

- (void)removeAllPrefixParentNotes {
	[prefixParentNotes removeAllObjects];
}

- (NSSet *)labelSet {
	return labelSet;
}

- (NSUndoManager *)undoManager {
	if (!undoManager) {
		undoManager = [[NSUndoManager alloc] init];

		id center = [NSNotificationCenter defaultCenter];
		[center addObserver:self selector:@selector(_undoManagerDidChange:)
					   name:NSUndoManagerDidUndoChangeNotification
					 object:undoManager];

		[center addObserver:self selector:@selector(_undoManagerDidChange:)
					   name:NSUndoManagerDidRedoChangeNotification
					 object:undoManager];
	}

	return undoManager;
}

- (void)_undoManagerDidChange:(NSNotification *)notification {
	[self makeNoteDirtyUpdateTime:YES updateFile:YES];
	//queue note to be synchronized to disk (and network if necessary)
}

- (FSRef *)noteFileRef {
	if (!noteFileRef) {
		noteFileRef = calloc(1, sizeof(FSRef));
	}
	return noteFileRef;
}

- (NSURL *)noteFileURL {
	// I know this is slow. Temporary.
	return [[NSURL URLWithFSRef: self.noteFileRef] fileReferenceURL];
}


@end
