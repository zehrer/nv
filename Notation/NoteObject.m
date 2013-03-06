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

@interface NoteObject () {
	NSMutableAttributedString *_mutableContentString;

	NSMutableSet *_labelSet;

	//each note has its own undo manager--isn't that nice?
	NSUndoManager *_undoManager;
}

@property(nonatomic, copy, readwrite) NSString *filename;
@property(nonatomic, readwrite) NoteStorageFormat storageFormat;
@property(nonatomic, readwrite) NSUInteger fileSize;
@property(nonatomic, copy, readwrite) NSString *title;
@property(nonatomic, copy, readwrite) NSString *labels;
@property(nonatomic, readwrite) NSStringEncoding fileEncoding;
@property(nonatomic, strong, readwrite) NSMutableArray *prefixParents;

@property(nonatomic, copy, readwrite) NSDate *contentModificationDate;
@property(nonatomic, copy, readwrite) NSDate *attributesModificationDate;

@property(nonatomic, copy, readwrite) NSURL *noteFileURL;

@property (nonatomic, strong) NSAttributedString *tableTitleString;

@property (nonatomic, copy, readwrite) NSString *dateCreatedString;
@property (nonatomic, copy, readwrite) NSString *dateModifiedString;

@end

@implementation NoteObject

//syncing w/ server and from journal;

@synthesize filename = filename;
@synthesize storageFormat = currentFormatID;
@synthesize title = titleString;
@synthesize labels = labelString;
@synthesize fileEncoding = fileEncoding;
@synthesize prefixParents = prefixParentNotes;

- (id)init {
	if ((self = [super init])) {

		currentFormatID = SingleDatabaseFormat;
		fileEncoding = NSUTF8StringEncoding;
		self.selectedRange = NSMakeRange(NSNotFound, 0);

		//other instance variables initialized on demand
	}

	return self;
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];

	if (perDiskInfoGroups)
		free(perDiskInfoGroups);
}

- (void)setDelegate:(id <NoteObjectDelegate, NTNFileManager>)theDelegate {
	_delegate = theDelegate;

	id <NoteObjectDelegate, NTNFileManager> localDelegate = self.delegate;
	if (localDelegate) {
		//do things that ought to have been done during init, but were not possible due to lack of delegate information
		if (!self.filename) self.filename = [localDelegate uniqueFilenameForTitle:titleString fromNote:self];
		if (!self.tableTitleString && !didUnarchive) [self updateTablePreviewString];
		if (!_labelSet && !didUnarchive) [self updateLabelConnectionsAfterDecoding];
	}
}

- (NSDate *)attributesModificationDate {
	if (!_attributesModificationDate) {
		if (perDiskInfoGroupCount) {
			id <NoteObjectDelegate, NTNFileManager> localDelegate = self.delegate;
			if (localDelegate) {
				//init from delegate based on disk table index
				NSUInteger i, tableIndex = [localDelegate diskUUIDIndex];

				for (i = 0; i < perDiskInfoGroupCount; i++) {
					//check if this date has actually been initialized; this entry could be here only because -setFileNoteID: was called
					if (perDiskInfoGroups[i].diskIDIndex == tableIndex && !UTCDateTimeIsEmpty(perDiskInfoGroups[i].attrTime)) {
						UTCDateTime time = perDiskInfoGroups[i].attrTime;
						_attributesModificationDate = [NSDate dateWithUTCDateTime: &time];
						break;
					}
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

- (NSComparisonResult)compareDateModified:(NoteObject *)other {
	return [self.modificationDate compare: other.modificationDate];
}

- (NSComparisonResult)compareDateCreated:(NoteObject *)other {
	return [self.creationDate compare: other.creationDate];
}

- (NSComparisonResult)compareLabels:(NoteObject *)other {
	return [self.labels caseInsensitiveCompare: other.labels];
}

NSInteger compareUniqueNoteIDs(__unsafe_unretained id *a, __unsafe_unretained id *b) {
	NoteObject *aObj = *a;
	NoteObject *bObj = *b;
	uuid_t aBytes;
	uuid_t bBytes;
	[aObj.uniqueNoteID getUUIDBytes: aBytes];
	[bObj.uniqueNoteID getUUIDBytes: bBytes];
	return memcmp(&aBytes, &bBytes, sizeof(uuid_t));
}

- (NSComparisonResult)compareTitles:(NoteObject *)other {
	NSComparisonResult result = [self.title caseInsensitiveCompare: other.title];
	
	if (result == NSOrderedSame) {
		result = [self compareDateCreated: other];
		if (!result) {
			__unsafe_unretained id weakSelf = self;
			__unsafe_unretained id weakOther = other;
			result = compareUniqueNoteIDs(&weakSelf, &weakOther);
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

- (void)setSyncObjectAndKeyMD:(NSDictionary *) aDict forService:(NSString*)serviceName {
	NSMutableDictionary *dict = syncServicesMD[serviceName];
	if (!dict) {
		dict = [[NSMutableDictionary alloc] initWithDictionary:aDict];
		if (!syncServicesMD) syncServicesMD = [[NSMutableDictionary alloc] init];
		syncServicesMD[serviceName] = dict;
	} else {
		[dict addEntriesFromDictionary:
		 aDict];
	}
}

- (void)removeAllSyncMDForService:(NSString *)serviceName {
	[syncServicesMD removeObjectForKey: serviceName];
}

- (NSDictionary*)syncServicesMD {
	return syncServicesMD;
}

- (unsigned int)logSequenceNumber {
	return logSequenceNumber;
}

- (void)incrementLSN {
	logSequenceNumber++;
}

- (BOOL)youngerThanLogObject:(id < SynchronizedNote >)obj {
	return [self logSequenceNumber] < [obj logSequenceNumber];
}

- (NSUInteger)hash {
	//XOR successive native-WORDs of UUID bytes
	NSUInteger finalHash = 0;
	uuid_t bytes;
	[self.uniqueNoteID getUUIDBytes: bytes];
	NSUInteger *noteIDBytes = (NSUInteger *)&bytes;
	for (NSUInteger i = 0; i < sizeof(uuid_t) / sizeof(NSUInteger); i++) {
		finalHash ^= noteIDBytes[i];
	}
	return finalHash;
}

- (BOOL)isEqual:(id)otherNote {
	if ([otherNote conformsToProtocol: @protocol(SynchronizedNote)]) {
		return [[otherNote uniqueNoteID] isEqual: self.uniqueNoteID];
	}
	return [super isEqual: otherNote];
}

- (id)tableTitleOfNote {
	return self.tableTitleString ?: self.title;
}

- (id)labelColumnCellForTableView:(NotesTableView *)tv row:(NSInteger)row {
	LabelColumnCell *cell = [[tv tableColumnWithIdentifier:NoteLabelsColumnString] dataCellForRow:row];
	[cell setNoteObject:self];
	return self.labels;
}

- (id)unifiedCellSingleLineForTableView:(NotesTableView *)tv row:(NSInteger)row {
	id obj = self.tableTitleString ?: self.title;

	UnifiedCell *cell = [[tv tableColumns][0] dataCellForRow:row];
	[cell setNoteObject: self];
	[cell setPreviewIsHidden:YES];

	return obj;
}

- (id)unifiedCellForTableView:(NotesTableView *)tv row:(NSInteger)row {
	//snow leopard is stricter about applying the default highlight-attributes (e.g., no shadow unless no paragraph formatting)
	//so add the shadow here for snow leopard on selected rows

	UnifiedCell *cell = [[tv tableColumns][0] dataCellForRow:row];
	[cell setNoteObject: self];
	[cell setPreviewIsHidden:NO];

	BOOL rowSelected = [tv isRowSelected:row];
	BOOL drawShadow = YES;

	return self.tableTitleString ? (rowSelected ? AttributedStringForSelection(self.tableTitleString, drawShadow) : self.tableTitleString) : self.title;
}

// make notationcontroller should send setDelegate: and setLabelString: (if necessary) to each note when unarchiving this way
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

			NSRange selectedRange;
			selectedRange.location = [decoder decodeIntegerForKey:@"selectionRangeLocation"];
			selectedRange.length = [decoder decodeIntegerForKey:@"selectionRangeLength"];
			self.selectedRange = selectedRange;
			
			contentsWere7Bit = [decoder decodeBoolForKey:VAR_STR(contentsWere7Bit)];

			logSequenceNumber = [decoder decodeInt32ForKey:VAR_STR(logSequenceNumber)];

			currentFormatID = [decoder decodeInt32ForKey:VAR_STR(currentFormatID)];
			self.fileSize = [decoder decodeIntegerForKey: VAR_STR(logicalSize)];

			if ([decoder containsValueForKey: VAR_STR(contentModificationDate)]) {
				_contentModificationDate = [decoder decodeObjectForKey: VAR_STR(contentModificationDate)];
			} else if ([decoder containsValueForKey: VAR_STR(fileModifiedDate)]) {
				UTCDateTime time;
				int64_t oldDate = [decoder decodeInt64ForKey:VAR_STR(fileModifiedDate)];
				memcpy(&time, &oldDate, sizeof(int64_t));
				_contentModificationDate = [NSDate dateWithUTCDateTime: &time];
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
			const uint8_t *decodedUUIDBytesPtr = [decoder decodeBytesForKey:VAR_STR(uniqueNoteIDBytes) returnedLength:&decodedUUIDByteCount];
			if (decodedUUIDByteCount == sizeof(uuid_t)) _uniqueNoteID = [[NSUUID alloc] initWithUUIDBytes: decodedUUIDBytesPtr];

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
	// nvALT duplicates
	[coder encodeDouble: self.modificationDate.timeIntervalSinceReferenceDate forKey: @"modifiedDate"];
	[coder encodeDouble: self.creationDate.timeIntervalSinceReferenceDate forKey: @"createdDate"];

	[coder encodeObject: self.modificationDate forKey: VAR_STR(modificationDate)];
	[coder encodeObject: self.creationDate forKey: VAR_STR(creationDate)];
	[coder encodeInteger: self.selectedRange.location forKey:@"selectionRangeLocation"];
	[coder encodeInteger: self.selectedRange.length forKey:@"selectionRangeLength"];
	[coder encodeBool:contentsWere7Bit forKey:VAR_STR(contentsWere7Bit)];

	[coder encodeInt32:logSequenceNumber forKey:VAR_STR(logSequenceNumber)];

	[coder encodeInt32:currentFormatID forKey:VAR_STR(currentFormatID)];

	[coder encodeInteger: self.fileSize forKey:VAR_STR(logicalSize)];

	[coder encodeObject: self.contentModificationDate forKey: VAR_STR(contentModificationDate)];
	[coder encodeObject: self.attributesModificationDate forKey: VAR_STR(attributesModificationDate)];

	[coder encodeInteger:fileEncoding forKey:VAR_STR(fileEncoding)];

	uuid_t bytes;
	[self.uniqueNoteID getUUIDBytes: bytes];
	[coder encodeBytes: (const uint8_t *)&bytes length: sizeof(uuid_t) forKey: VAR_STR(uniqueNoteIDBytes)];
	
	[coder encodeObject:syncServicesMD forKey:VAR_STR(syncServicesMD)];

	[coder encodeObject:titleString forKey:VAR_STR(titleString)];
	[coder encodeObject:labelString forKey:VAR_STR(labelString)];
	[coder encodeObject:self.contentString forKey:VAR_STR(contentString)];
	[coder encodeObject:filename forKey:VAR_STR(filename)];

	UTCDateTime time;
	[self.contentModificationDate getUTCDateTime: &time];
	[coder encodeInt64:*(int64_t*)&time forKey:VAR_STR(fileModifiedDate)];
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

		_uniqueNoteID = [NSUUID UUID];

		self.creationDate = self.modificationDate = [NSDate date];
		self.dateModifiedString = [NSString relativeDateStringWithAbsoluteTime: self.modificationDate.timeIntervalSinceReferenceDate];
		self.contentModificationDate = self.modificationDate;

		if (localDelegate) [self updateTablePreviewString];
	}

	return self;
}

//only get the URLs until we absolutely need them
- (id)initWithCatalogEntry:(NoteCatalogEntry *)entry delegate:(id<NoteObjectDelegate,NTNFileManager>)aDelegate {
	NSParameterAssert(aDelegate);

	if ((self = [self init])) {
		self.delegate = aDelegate;
		id <NoteObjectDelegate, NTNFileManager> localDelegate = aDelegate;
		self.filename = entry.filename;
		self.storageFormat = [localDelegate currentNoteStorageFormat];
		self.contentModificationDate = entry.contentModificationDate;
		self.attributesModificationDate = entry.attributeModificationDate;
		self.fileSize = entry.fileSize;
		self.creationDate = entry.creationDate;
		_uniqueNoteID = [NSUUID UUID];

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
			self.dateModifiedString = [NSString relativeDateStringWithAbsoluteTime: self.modificationDate.timeIntervalSinceReferenceDate];
		}
	}

	[self updateTablePreviewString];

	return self;

}

- (NSAttributedString *)contentString {
	return [_mutableContentString copy];
}

//assume any changes have been synchronized with undomanager
- (void)setContentString:(NSAttributedString *)attributedString {
	if (attributedString) {
		if (!_mutableContentString)
			_mutableContentString = [attributedString mutableCopy];
		else
			[_mutableContentString setAttributedString:attributedString];

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
		contentsWere7Bit = self.contentString.string.ntn_containsHighASCII;
	}
}

- (void)initContentCacheCString {
	if (contentsWere7Bit) {
		if (!self.contentString.string.couldCopyLowercaseASCIIString) contentsWere7Bit = NO;
	} else {
		contentsWere7Bit = self.contentString ? !self.contentString.string.ntn_containsHighASCII : NO;
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
			self.tableTitleString = [titleString attributedMultiLinePreviewFromBodyText:self.contentString upToWidth:[localDelegate titleColumnWidth]
																	intrusionWidth:labelBlockSize.width];
		} else {
			self.tableTitleString = [titleString attributedSingleLinePreviewFromBodyText:self.contentString upToWidth:[localDelegate titleColumnWidth]];
		}
	} else {
		if ([prefs horizontalLayout]) {
			self.tableTitleString = [titleString attributedSingleLineTitle];
		} else {
			self.tableTitleString = nil;
		}
	}
}

- (void)setTitleString:(NSString *)aNewTitle {
	if ([self _setTitleString:aNewTitle]) {
		//do you really want to do this when the format is a single DB and the file on disk hasn't been removed?
		//the filename could get out of sync if we lose the URL and we could end up with a second file after note is rewritten

		//solution: don't change the name in that case and allow its new name to be generated
		//when the format is changed and the file rewritten?
		id <NoteObjectDelegate, NTNFileManager> localDelegate = self.delegate;

		//however, the filename is used for exporting and potentially other purposes, so we should also update
		//it if we know that is has no currently existing (older) counterpart in the notes directory

		//woe to the exporter who also left the note files in the notes directory after switching to a singledb format
		//his note names might not be up-to-date
		if ([localDelegate currentNoteStorageFormat] != SingleDatabaseFormat ||
				!(self.noteFileURL = [localDelegate notesDirectoryContainsFile: filename])) {
			
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
			if (!(self.noteFileURL = [localDelegate noteFileRenamed: self.noteFileURL fromName: oldName toName: filename error: NULL])) {
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
	[_mutableContentString removeAttribute:NSForegroundColorAttributeName range:NSMakeRange(0, self.contentString.length)];
	if (aColor) {
		[_mutableContentString addAttribute:NSForegroundColorAttributeName value:aColor range:NSMakeRange(0, self.contentString.length)];
	}
}

- (void)resanitizeContent {
	[_mutableContentString santizeForeignStylesForImporting];

	[self _setTitleString: [titleString ntn_normalizedString]];

	id <NoteObjectDelegate, NTNFileManager> localDelegate = self.delegate;
	if (localDelegate && [localDelegate currentNoteStorageFormat] == RTFTextFormat)
		[self makeNoteDirtyUpdateTime:NO updateFile:YES];
}

//how do we write a thousand RTF files at once, repeatedly? 

- (void)updateUnstyledTextWithBaseFont:(NSFont *)baseFont {

	if ([_mutableContentString restyleTextToFont:[[GlobalPrefs defaultPrefs] noteBodyFont] usingBaseFont:baseFont] > 0) {
		[self.undoManager removeAllActions];

		id <NoteObjectDelegate, NTNFileManager> localDelegate = self.delegate;
		if (localDelegate && [localDelegate currentNoteStorageFormat] == RTFTextFormat)
			[self makeNoteDirtyUpdateTime:NO updateFile:YES];
	}
}

- (void)updateDateStrings {
	self.dateCreatedString = [NSString relativeDateStringWithAbsoluteTime: self.creationDate.timeIntervalSinceReferenceDate];
	self.dateModifiedString = [NSString relativeDateStringWithAbsoluteTime: self.modificationDate.timeIntervalSinceReferenceDate];
}

- (void)setCreationDate:(NSDate *)creationDate {
	_creationDate = creationDate;
	self.dateCreatedString = [NSString relativeDateStringWithAbsoluteTime: self.creationDate.timeIntervalSinceReferenceDate];
}

- (void)setModificationDate:(NSDate *)modificationDate {
	_modificationDate = modificationDate;
	self.dateModifiedString = [NSString relativeDateStringWithAbsoluteTime: self.modificationDate.timeIntervalSinceReferenceDate];
}


- (void)setSelectedRange:(NSRange)newRange {
	//if (!newRange.length) newRange = NSMakeRange(0,0);

	//don't save the range if it's invalid, it's equal to the current range, or the entire note is selected
	if ((newRange.location != NSNotFound) && !NSEqualRanges(newRange, self.selectedRange) &&
			!NSEqualRanges(newRange, NSMakeRange(0, self.contentString.length))) {
		//	NSLog(@"saving: old range: %@, new range: %@", NSStringFromRange(selectedRange), NSStringFromRange(newRange));
		_selectedRange = newRange;
		[self makeNoteDirtyUpdateTime:NO updateFile:NO];
	}
}

//these two methods let us get the actual label objects in use by other notes
//they assume that the label string already contains the title of the label object(s); that there is only replacement and not addition
- (void)replaceMatchingLabelSet:(NSSet *)aLabelSet {
	[_labelSet minusSet:aLabelSet];
	[_labelSet unionSet:aLabelSet];
}

- (void)replaceMatchingLabel:(LabelObject *)aLabel {
	// just in case this is actually the same label

	//remove the old label and add the new one; if this is the same one, well, too bad
	[_labelSet removeObject:aLabel];
	[_labelSet addObject:aLabel];
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
		NSMutableSet *oldLabelSet = _labelSet;
		NSMutableSet *newLabelSet = [self labelSetFromCurrentString];

		if (!oldLabelSet) {
			oldLabelSet = _labelSet = [[NSMutableSet alloc] initWithCapacity:[newLabelSet count]];
		}

		//what's left-over
		NSMutableSet *oldLabels = [oldLabelSet mutableCopy];
		[oldLabels minusSet:newLabelSet];

		//what wasn't there last time
		NSMutableSet *newLabels = newLabelSet;
		[newLabels minusSet:oldLabelSet];

		//update the currently known labels
		[_labelSet minusSet:oldLabels];
		[_labelSet unionSet:newLabels];

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
		[localDelegate note:self didRemoveLabelSet:_labelSet];
		_labelSet = nil;
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

	uuid_t uuid;
	[self.uniqueNoteID getUUIDBytes: uuid];
	idsDict[@"NV"] = [[NSData dataWithBytes:&uuid length: sizeof(uuid_t)] encodeBase64];

	return [NSURL URLWithString:[@"nv://find/" stringByAppendingFormat:@"%@/?%@", [titleString stringWithPercentEscapes],
																	   [idsDict URLEncodedString]]];
}

- (void)invalidateURL {
	self.noteFileURL = nil;
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
	id <NoteObjectDelegate, NTNFileManager> localDelegate = self.delegate;

	if (!(self.noteFileURL = [localDelegate createFileWithNameIfNotPresentInNotesDirectory: filename created: &fileWasCreated error: NULL])) {
		return NO;
	}

	if (fileWasCreated) {
		NSLog(@"writing note %@, because it didn't exist", titleString);
		return [self writeUsingCurrentFileFormat];
	}

	//createFileWithNameIfNotPresentInNotesDirectory: works by name, so if this file is not owned by us at this point, it was a race with moving it
	NSDate *timeOnDisk = nil;
	if (![self.noteFileURL getResourceValue: &timeOnDisk forKey: NSURLContentModificationDateKey error: NULL]) return NO;

	NSDate *lastTime = self.contentModificationDate;

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

		if (!(self.noteFileURL = [localDelegate writeDataToNotesDirectory: formattedData withName: filename verifyUsingBlock: NULL error: &error])) {
			NSLog(@"Unable to save note file %@", filename);
			[localDelegate noteDidNotWrite:self error: error];
			return NO;
		}
		
		//if writing plaintext set the file encoding with setxattr
		if (PlainTextFormat == formatID) {
			[NSFileManager setTextEncoding: self.fileEncoding ofItemAtURL: self.noteFileURL];
		}

		[NSFileManager setOpenMetaTags: self.orderedLabelTitles forItemAtURL: self.noteFileURL error: NULL];

		//always hide the file extension for all types
		[self.noteFileURL setResourceValue: @YES forKey: NSURLHasHiddenExtensionKey error: NULL];
		
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
	// refreshFileURLIfNecessary: self.noteFileURL withName:filename
	// charsBuffer:chars]; instead, for now, it is not called in any situations
	// where the URL might accidentally point to a moved file
	NSError *error = nil;
	do {
		if (error || !self.noteFileURL) {
			if (!(self.noteFileURL = [localDelegate notesDirectoryContainsFile: filename])) return NO;
		}
		[self.noteFileURL setResourceValues: attributes error: &error];
	} while (error.code == NSFileNoSuchFileError);

	if (error) {
		NSLog(@"could not set catalog info: %@", error);
		return NO;
		
	}

	//regardless of whether setting resource values was successful, the file mod date could still have changed
	if (!(attributes = [self.noteFileURL resourceValuesForKeys: @[NSURLContentModificationDateKey, NSURLAttributeModificationDateKey, NSURLFileSizeKey, NSURLCreationDateKey] error: &error])) {
		NSLog(@"Unable to get new modification date of file %@: %@", filename, error);
		return NO;
	}

	self.contentModificationDate = attributes[NSURLContentModificationDateKey];
	self.attributesModificationDate = attributes[NSURLAttributeModificationDateKey];
	self.fileSize = [attributes[NSURLFileSizeKey] unsignedIntegerValue];

	NSDate *createDate = attributes[NSURLCreationDateKey];
	if ([self.creationDate compare: createDate] == NSOrderedDescending) {
		self.creationDate = createDate;
	}

	return YES;
}

- (BOOL)upgradeToUTF8IfUsingSystemEncoding {
	if ([NSString defaultCStringEncoding] == fileEncoding)
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

		if (!(self.noteFileURL = [localDelegate refreshFileURLIfNecessary: self.noteFileURL withName: filename error: NULL])) {
			return NO;
		}

		if (![NSFileManager setTextEncoding: self.fileEncoding ofItemAtURL: self.noteFileURL]) return NO;

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
	NSURL *newURL = nil;
	NSMutableData *data = nil;
	if ((data = [localDelegate dataForFilenameInNotesDirectory: self.filename URL: &newURL])) {
		self.noteFileURL = newURL;
	} else {
		NSLog(@"Couldn't update note from file on disk");
		return NO;
	}

	if ([self updateFromData:data inFormat:currentFormatID]) {
		NSDictionary *attributes = nil;
		NSError *error = nil;
		
		if ((attributes = [self.noteFileURL resourceValuesForKeys: @[NSURLContentModificationDateKey, NSURLAttributeModificationDateKey, NSURLFileSizeKey, NSURLCreationDateKey] error: &error])) {
			self.contentModificationDate = attributes[NSURLContentModificationDateKey];
			self.attributesModificationDate = attributes[NSURLAttributeModificationDateKey];
			self.fileSize = [attributes[NSURLFileSizeKey] unsignedIntegerValue];

			NSDate *createDate = attributes[NSURLCreationDateKey];
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
	NSURL *newURL = nil;
	NSMutableData *data = nil;
	if ((data = [localDelegate dataForFilenameInNotesDirectory: catEntry.filename URL: &newURL])) {
		self.noteFileURL = newURL;
	} else {
		NSLog(@"Couldn't update note from file on disk given catalog entry");
		return NO;
	}

	if (![self updateFromData:data inFormat:currentFormatID])
		return NO;

	[self setFilename: catEntry.filename withExternalTrigger:YES];

	self.contentModificationDate = catEntry.contentModificationDate;
	self.attributesModificationDate = catEntry.attributeModificationDate;
	self.fileSize = catEntry.fileSize;

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
		NSDictionary *attributes = [self.noteFileURL resourceValuesForKeys: @[NSURLCreationDateKey, NSURLContentModificationDateKey, NSURLAttributeModificationDateKey] error: NULL];

		if (attributes) {
			if (!self.creationDate) self.creationDate = attributes[NSURLCreationDateKey];

			if (didRestoreLabels) {
				self.contentModificationDate = attributes[NSURLContentModificationDateKey];
				self.attributesModificationDate = attributes[NSURLAttributeModificationDateKey];
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
			if ((stringFromData = [NSMutableString ntn_newShortLivedStringFromData: data guessedEncoding: &fileEncoding withURL: self.noteFileURL])) {
				attributedStringFromData = [[NSMutableAttributedString alloc] initWithString:stringFromData attributes:[[GlobalPrefs defaultPrefs] noteBodyAttributes]];
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

	_mutableContentString = attributedStringFromData;
	[_mutableContentString santizeForeignStylesForImporting];

	//[contentString setAttributedString:attributedStringFromData];
	contentCacheNeedsUpdate = YES;
	[self updateContentCacheCStringIfNecessary];
	[self.undoManager removeAllActions];

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
	[self.undoManager removeAllActions];

	[self setTitleString:newTitle];
}

- (void)moveFileToTrash {
	id <NoteObjectDelegate, NTNFileManager> localDelegate = self.delegate;
	NSError *err = nil;
	NSURL *URL = nil;
	if ((URL = [localDelegate moveFileToTrash: self.noteFileURL forFilename: filename error: &err])) {
		//file's gone! don't assume it's not coming back. if the storage format was not single-db, this note better be removed
		//currentFormatID = SingleDatabaseFormat;
		self.noteFileURL = URL;
	} else {
		NSLog(@"Couldn't move file to trash: %@", err);
	}
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
	if (localDelegate && updateTime) {
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
	return [_labelSet copy];
}

- (NSUndoManager *)undoManager {
	if (!_undoManager) {
		_undoManager = [[NSUndoManager alloc] init];

		id center = [NSNotificationCenter defaultCenter];
		[center addObserver:self selector:@selector(_undoManagerDidChange:)
					   name:NSUndoManagerDidUndoChangeNotification
					 object:_undoManager];

		[center addObserver:self selector:@selector(_undoManagerDidChange:)
					   name:NSUndoManagerDidRedoChangeNotification
					 object:_undoManager];
	}

	return _undoManager;
}

- (void)_undoManagerDidChange:(NSNotification *)notification {
	[self makeNoteDirtyUpdateTime:YES updateFile:YES];
	//queue note to be synchronized to disk (and network if necessary)
}

@end
