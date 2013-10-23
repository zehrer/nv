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
#import "WALController.h"
#import "NotationController.h"
#import "NotationPrefs.h"
#import "AttributedPlainText.h"
#import "NSString_CustomTruncation.h"
#import "NSFileManager_NV.h"
#include "BufferUtils.h"
#import "NotationFileManager.h"
#import "NotationSyncServiceManager.h"
#import "SyncServiceSessionProtocol.h"
#import "SyncSessionController.h"
#import "ExternalEditorListController.h"
#import "NSData_transformations.h"
#import "NSCollection_utils.h"
#import "NotesTableView.h"
#import "UnifiedCell.h"
#import "LabelColumnCell.h"
#import "ODBEditor.h"
#import "NoteAttributeColumn.h"
#import "NSError+NVError.h"
#import "NSURL+NVFSRefCompat.h"

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
	PerDiskInfo *perDiskInfoGroups;
	NSMutableAttributedString *contentString;
}

@property (nonatomic, readonly) FSRef *noteFileRef;

@end

@implementation NoteObject

@synthesize modifiedDate = modifiedDate, createdDate = createdDate;
@synthesize logSequenceNumber = logSequenceNumber;
@synthesize currentFormatID = currentFormatID;
@synthesize logicalSize = logicalSize;
@synthesize fileModifiedDate = fileModifiedDate;
@synthesize fileEncoding = fileEncoding;
@synthesize syncServicesMD = syncServicesMD;
@synthesize filename = filename;
@synthesize titleString = titleString;
@synthesize labelString = labelString;
@synthesize nodeID = nodeID;
@synthesize attrsModifiedDate = attrsModifiedDate;
@synthesize prefixParentNotes = prefixParentNotes;
@synthesize modifiedDateString = dateModifiedString, createdDateString = dateCreatedString;
@synthesize tableTitleString = tableTitleString;
@synthesize noteFileRef = noteFileRef;

- (id)init {
    if (self = [super init]) {
	
		perDiskInfoGroups = calloc(1, sizeof(PerDiskInfo));
		perDiskInfoGroups[0].diskIDIndex = -1;
		perDiskInfoGroupCount = 1;
		
		currentFormatID = NVDatabaseFormatSingle;
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

- (void)setDelegate:(id <NoteObjectDelegate>)delegate {
	if (delegate) {
		_delegate = delegate;
		
		//do things that ought to have been done during init, but were not possible due to lack of delegate information
		if (!filename) filename = [[delegate uniqueFilenameForTitle:titleString fromNote:self] copy];
		if (!tableTitleString && !didUnarchive) [self updateTablePreviewString];
		if (!labelSet && !didUnarchive) [self updateLabelConnectionsAfterDecoding];
	}
}

- (FSRef *)noteFileRef
{
	if (!(noteFileRef)) {
		noteFileRef = (FSRef*)calloc(1, sizeof(FSRef));
	}
	return noteFileRef;
}

- (void)setAttrsModifiedDate:(UTCDateTime *)dateTime
{
	NSUInteger idx = SetPerDiskInfoWithTableIndex(dateTime, NULL, self.delegate.diskUUIDIndex,
												  &perDiskInfoGroups, &perDiskInfoGroupCount);
	attrsModifiedDate = &(perDiskInfoGroups[idx].attrTime);
}

- (UTCDateTime *)attrsModifiedDate
{
	//once unarchived, the disk UUID index won't change, so this pointer will always reflect the current attr mod time
	if (!attrsModifiedDate) {
		//init from delegate based on disk table index
		NSUInteger i, tableIndex = self.delegate.diskUUIDIndex;
		
		for (i=0; i<perDiskInfoGroupCount; i++) {
			//check if this date has actually been initialized; this entry could be here only because setNodeID was called
			if (perDiskInfoGroups[i].diskIDIndex == tableIndex && !UTCDateTimeIsEmpty(perDiskInfoGroups[i].attrTime)) {
				attrsModifiedDate = &(perDiskInfoGroups[i].attrTime);
				return attrsModifiedDate;
			}
		}
		//this note doesn't have a file-modified date, so initialize a fairly reasonable one here
		self.attrsModifiedDate = &fileModifiedDate;
	}
	return attrsModifiedDate;
}

- (void)setNodeID:(UInt32)cnid
{
	SetPerDiskInfoWithTableIndex(NULL, &cnid, self.delegate.diskUUIDIndex, &perDiskInfoGroups, &perDiskInfoGroupCount);
	nodeID = cnid;
}

- (UInt32)nodeID
{
	if (!nodeID) {
		NSUInteger i, tableIndex = self.delegate.diskUUIDIndex;
		
		for (i=0; i<perDiskInfoGroupCount; i++) {
			//check if this nodeID has actually been initialized; this entry could be here only because setAttrsModifiedDate was called
			if (perDiskInfoGroups[i].diskIDIndex == tableIndex && perDiskInfoGroups[i].nodeID != 0U) {
				nodeID = perDiskInfoGroups[i].nodeID;
				return nodeID;
			}
		}
		//this note doesn't have a file-modified date, so initialize something that at least won't repeat this lookup
		self.nodeID = 1;
	}
	return nodeID;
	
}

- (void)setSyncObjectAndKeyMD:(NSDictionary*)aDict forService:(NSString*)serviceName {
	NSMutableDictionary *dict = syncServicesMD[serviceName];
	if (!dict) {
		dict = [[NSMutableDictionary alloc] initWithDictionary:aDict];
		if (!syncServicesMD) syncServicesMD = [[NSMutableDictionary alloc] init];
		syncServicesMD[serviceName] = dict;
	} else {
		[dict addEntriesFromDictionary:aDict];
	}
}
- (void)removeAllSyncMDForService:(NSString*)serviceName {
	[syncServicesMD removeObjectForKey:serviceName];
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
- (BOOL)youngerThanLogObject:(id<SynchronizedNote>)obj {
	return [self logSequenceNumber] < [obj logSequenceNumber];
}

- (NSUInteger)hash {
	return self.uniqueNoteID.hash;
}
- (BOOL)isEqual:(id)otherNote {
	if (!otherNote) return NO;
	if (![otherNote conformsToProtocol:@protocol(SynchronizedNote)]) return NO;
	NSUUID *otherUUID = [(id <SynchronizedNote>)otherNote uniqueNoteID];
	return [self.uniqueNoteID isEqual:otherUUID];
}

- (NSAttributedString *)tableTitleString
{
	return tableTitleString ?: [[NSAttributedString alloc] initWithString:self.titleString];
}

//make notationcontroller should send setDelegate: and setLabelString: (if necessary) to each note when unarchiving this way

//there is no measurable difference in speed when using decodeValuesOfObjCTypes, oddly enough
//the overhead of the _decodeObject* C functions must be significantly greater than the objc_msgSend and argument passing overhead
#define DECODE_INDIVIDUALLY 1

- (id)initWithCoder:(NSCoder*)decoder {
	if (self = [self init]) {
		
		//(hopefully?) no versioning necessary here
		
		//for knowing when to delay certain initializations during launch (e.g., preview generation)
		didUnarchive = YES;
		
		modifiedDate = [decoder decodeDoubleForKey:@keypath(self.modifiedDate)];
		createdDate = [decoder decodeDoubleForKey:@keypath(self.createdDate)];
		selectedRange.location = [decoder decodeInt32ForKey:@"selectionRangeLocation"];
		selectedRange.length = [decoder decodeInt32ForKey:@"selectionRangeLength"];
		
		logSequenceNumber = [decoder decodeInt32ForKey:@keypath(self.logSequenceNumber)];
		
		currentFormatID = [decoder decodeInt32ForKey:@keypath(self.currentFormatID)];
		logicalSize = [decoder decodeInt32ForKey:@keypath(self.logicalSize)];
		
		int64_t fileModifiedDate64 = [decoder decodeInt64ForKey:@keypath(self.fileModifiedDate)];
		memcpy(&fileModifiedDate, &fileModifiedDate64, sizeof(int64_t));
		
		NSUInteger decodedPerDiskByteCount = 0;
		const uint8_t *decodedPerDiskBytes = [decoder decodeBytesForKey:@"perDiskInfoGroups" returnedLength:&decodedPerDiskByteCount];
		if (decodedPerDiskBytes && decodedPerDiskByteCount) {
			CopyPerDiskInfoGroupsToOrder(&perDiskInfoGroups, &perDiskInfoGroupCount, (PerDiskInfo *)decodedPerDiskBytes, decodedPerDiskByteCount, 1);
		}
		
		fileEncoding = [decoder decodeInt32ForKey:@keypath(self.fileEncoding)];
		
		if ([decoder containsValueForKey:@keypath(self.uniqueNoteID)]) {
			self.uniqueNoteID = [decoder decodeObjectForKey:@keypath(self.uniqueNoteID)];
		} else if ([decoder containsValueForKey:@"uniqueNoteIDBytes"]) {
			NSUInteger decodedUUIDByteCount = 0;
			const uint8_t *decodedUUIDBytes = [decoder decodeBytesForKey:@"uniqueNoteIDBytes" returnedLength:&decodedUUIDByteCount];
			self.uniqueNoteID = decodedUUIDBytes ? [[NSUUID alloc] initWithUUIDBytes:decodedUUIDBytes] : [NSUUID UUID];
		}
		
		syncServicesMD = [decoder decodeObjectForKey:@keypath(self.syncServicesMD)];
		
		titleString = [decoder decodeObjectForKey:@keypath(self.titleString)];
		labelString = [decoder decodeObjectForKey:@keypath(self.labelString)];
		contentString = [[NSMutableAttributedString alloc] initWithAttributedString: [decoder decodeObjectForKey:@keypath(self.contentString)]];
		filename = [[decoder decodeObjectForKey:@keypath(self.filename)] copy];
		
		dateCreatedString = [NSString relativeDateStringWithAbsoluteTime:createdDate];
		dateModifiedString = [NSString relativeDateStringWithAbsoluteTime:modifiedDate];
		
		if (!titleString && !contentString && !labelString) return nil;
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
		
	[coder encodeDouble:modifiedDate forKey:@keypath(self.modifiedDate)];
	[coder encodeDouble:createdDate forKey:@keypath(self.createdDate)];
	[coder encodeInt32:(unsigned int)selectedRange.location forKey:@"selectionRangeLocation"];
	[coder encodeInt32:(unsigned int)selectedRange.length forKey:@"selectionRangeLength"];
	[coder encodeBool:YES forKey:@"contentsWere7Bit"];
	
	[coder encodeInt32:logSequenceNumber forKey:@keypath(self.logSequenceNumber)];
	
	[coder encodeInteger:currentFormatID forKey:@keypath(self.currentFormatID)];
	[coder encodeInt32:logicalSize forKey:@keypath(self.logicalSize)];
	
	PerDiskInfo *flippedPerDiskInfoGroups = calloc(perDiskInfoGroupCount, sizeof(PerDiskInfo));
	CopyPerDiskInfoGroupsToOrder((PerDiskInfo**)&flippedPerDiskInfoGroups, &perDiskInfoGroupCount, perDiskInfoGroups, perDiskInfoGroupCount * sizeof(PerDiskInfo), 0);
	
	[coder encodeBytes:(const uint8_t *)flippedPerDiskInfoGroups length:perDiskInfoGroupCount * sizeof(PerDiskInfo) forKey:@"perDiskInfoGroups"];
	free(flippedPerDiskInfoGroups);
	
	[coder encodeInt64:*(int64_t*)&fileModifiedDate forKey:@keypath(self.fileModifiedDate)];
	[coder encodeInteger:fileEncoding forKey:@keypath(self.fileEncoding)];
	
	uuid_t bytes;
	[self.uniqueNoteID getUUIDBytes:bytes];
	[coder encodeBytes:(const uint8_t *)&bytes length:sizeof(uuid_t) forKey:@"uniqueNoteIDBytes"];
	
	[coder encodeObject:syncServicesMD forKey:@keypath(self.syncServicesMD)];
	
	[coder encodeObject:titleString forKey:@keypath(self.titleString)];
	[coder encodeObject:labelString forKey:@keypath(self.labelString)];
	[coder encodeObject:contentString forKey:@keypath(self.contentString)];
	[coder encodeObject:filename forKey:@keypath(self.filename)];
}

- (id)initWithNoteBody:(NSAttributedString *)bodyText title:(NSString *)aNoteTitle delegate:(id)delegate format:(NVDatabaseFormat)formatID labels:(NSString*)aLabelString {
	//delegate optional here
    if ((self = [self init])) {
		
		if (!bodyText || !aNoteTitle) {
			return nil;
		}
		_delegate = delegate;

		contentString = [[NSMutableAttributedString alloc] initWithAttributedString:bodyText];
		
		if (![self _setTitleString:aNoteTitle])
		    titleString = NSLocalizedString(@"Untitled Note", @"Title of a nameless note");
		
		if (![self _setLabelString:aLabelString]) {
			labelString = @"";
		}
		
		currentFormatID = formatID;
		filename = [[delegate uniqueFilenameForTitle:titleString fromNote:nil] copy];
		
		self.uniqueNoteID = [NSUUID UUID];
		
		createdDate = modifiedDate = CFAbsoluteTimeGetCurrent();
		dateCreatedString = dateModifiedString = [NSString relativeDateStringWithAbsoluteTime:modifiedDate];
		UCConvertCFAbsoluteTimeToUTCDateTime(modifiedDate, &fileModifiedDate);
		
		if (delegate)
			[self updateTablePreviewString];
    }
    
    return self;
}

//only get the fsrefs until we absolutely need them

- (id)initWithCatalogEntry:(NoteCatalogEntry*)entry delegate:(id)delegate {
	NSAssert(delegate, @"must supply a delegate");
    if ((self = [self init])) {
		_delegate = delegate;
		filename = [(__bridge NSString*)entry->filename copy];
		currentFormatID = [delegate currentNoteStorageFormat];
		fileModifiedDate = entry->lastModified;
		self.attrsModifiedDate = &(entry->lastAttrModified);
		self.nodeID = entry->nodeID;
		logicalSize = entry->logicalSize;
		
		self.uniqueNoteID = [NSUUID UUID];
		
		if (![self _setTitleString:[filename stringByDeletingPathExtension]])
			titleString = NSLocalizedString(@"Untitled Note", @"Title of a nameless note");
		
		labelString = @""; //set by updateFromCatalogEntry if there are openmeta extended attributes 
				
		contentString = [[NSMutableAttributedString alloc] initWithString:@""];
		
		[self updateFromCatalogEntry:entry];
		
		if (!modifiedDate || !createdDate) {
			modifiedDate = createdDate = CFAbsoluteTimeGetCurrent();
			dateModifiedString = dateCreatedString = [NSString relativeDateStringWithAbsoluteTime:createdDate];	
		}
    }
	
	[self updateTablePreviewString];
    
    return self;
}

//assume any changes have been synchronized with undomanager
- (void)setContentString:(NSAttributedString*)attributedString {
	[self setContentString:attributedString updateTime:YES];
}

- (void)setContentString:(NSAttributedString*)attributedString updateTime:(BOOL)updateTime {
	if (attributedString) {
		[contentString setAttributedString:attributedString];
		
		[self updateTablePreviewString];
		
		[_delegate note:self attributeChanged:NVUIAttributeNotePreview];
	
		[self makeNoteDirtyUpdateTime:updateTime updateFile:YES];
	}
}
- (NSAttributedString*)contentString {
	return [contentString copy];
}

- (NSString*)description {
	return syncServicesMD ? [NSString stringWithFormat:@"%@ / %@", titleString, syncServicesMD] : titleString;
}

- (NSString*)combinedContentWithContextSeparator:(NSString*)sepWContext {
	//combine title and body based on separator data usually generated by -syntheticTitleAndSeparatorWithContext:bodyLoc:
	//if separator does not exist or chars do not match trailing and leading chars of title and body, respectively,
	//then just delimit with a double-newline
	
	NSString *content = [contentString string];
	
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


- (NSAttributedString*)printableStringRelativeToBodyFont:(NSFont*)bodyFont {
	NSFont *titleFont = [NSFont fontWithName:[bodyFont fontName] size:[bodyFont pointSize] + 6.0f];
	
	NSDictionary *dict = @{NSFontAttributeName: titleFont};
	
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

	if ([prefs tableColumnsShowPreview]) {
		if ([prefs horizontalLayout]) {
			//is called for visible notes at launch and resize only, generation of images for invisible notes is delayed until after launch
			NSSize labelBlockSize = [prefs visibleTableColumnsIncludes:NVUIAttributeLabels] ? [self sizeOfLabelBlocks] : NSZeroSize;
			tableTitleString = [titleString attributedMultiLinePreviewFromBodyText:contentString upToWidth:[_delegate titleColumnWidth]
																	 intrusionWidth:labelBlockSize.width];
		} else {
			tableTitleString = [titleString attributedSingleLinePreviewFromBodyText:contentString upToWidth:[_delegate titleColumnWidth]];
		}
	} else {
		if ([prefs horizontalLayout]) {
			tableTitleString = [titleString attributedSingleLineTitle];
		} else {
			tableTitleString = nil;
		}
	}
}

- (void)setTitleString:(NSString*)aNewTitle {
    if ([self _setTitleString:aNewTitle]) {
		//do you really want to do this when the format is a single DB and the file on disk hasn't been removed?
		//the filename could get out of sync if we lose the fsref and we could end up with a second file after note is rewritten
		
		//solution: don't change the name in that case and allow its new name to be generated
		//when the format is changed and the file rewritten?
		
		//however, the filename is used for exporting and potentially other purposes, so we should also update
		//it if we know that is has no currently existing (older) counterpart in the notes directory
		
		//woe to the exporter who also left the note files in the notes directory after switching to a singledb format
		//his note names might not be up-to-date
		if ([_delegate currentNoteStorageFormat] != NVDatabaseFormatSingle ||
			![_delegate notesDirectoryContainsFile:filename returningFSRef:self.noteFileRef]) {
			
			[self setFilenameFromTitle];
		}
		
		//yes, the given extension could be different from what we had before
		//but makeNoteDirty will eventually cause it to be re-written in the current format
		//and thus the format ID will be changed if that was the case
		[self makeNoteDirtyUpdateTime:YES updateFile:YES];
		
		[self updateTablePreviewString];
		
		[_delegate note:self attributeChanged:NVUIAttributeTitle];
    }
}

- (BOOL)_setTitleString:(NSString*)aNewTitle {
    if (!aNewTitle || ![aNewTitle length] || (titleString && [aNewTitle isEqualToString:titleString]))
		return NO;

    titleString = [aNewTitle copy];
    
    return YES;
}

- (void)setFilenameFromTitle {
	[self setFilename:[_delegate uniqueFilenameForTitle:titleString fromNote:self] withExternalTrigger:NO];
}

- (void)setFilename:(NSString*)aString withExternalTrigger:(BOOL)externalTrigger {
    
    if (!filename || ![aString isEqualToString:filename]) {
		NSString *oldName = filename;
		filename = [aString copy];
		
		if (!externalTrigger) {
			if ([_delegate noteFileRenamed:self.noteFileRef fromName:oldName toName:filename] != noErr) {
				NSLog(@"Couldn't rename note %@", titleString);
				
				//revert name
				filename = oldName;
				return;
			}
		} else {
			[self _setTitleString:[aString stringByDeletingPathExtension]];	
			
			[self updateTablePreviewString];
			[_delegate note:self attributeChanged:NVUIAttributeTitle];
		}
		
		[self makeNoteDirtyUpdateTime:YES updateFile:NO];
		
    }
}

- (void)setForegroundTextColorOnly:(NSColor*)aColor {
	//called when notationPrefs font doesn't match globalprefs font, or user changes the font
	[contentString removeAttribute:NSForegroundColorAttributeName range:NSMakeRange(0, [contentString length])];
	if (aColor) {
		[contentString addAttribute:NSForegroundColorAttributeName value:aColor range:NSMakeRange(0, [contentString length])];
	}
}

- (void)_resanitizeContent {
	[contentString santizeForeignStylesForImporting];
	
	//renormalize the title, in case it is still somehow derived from decomposed HFS+ filenames
	CFMutableStringRef normalizedString = CFStringCreateMutableCopy(NULL, 0, (CFStringRef)titleString);
	CFStringNormalize(normalizedString, kCFStringNormalizationFormC);
	
	[self _setTitleString:(__bridge NSString*)normalizedString];
	CFRelease(normalizedString);
	
	if ([_delegate currentNoteStorageFormat] == NVDatabaseFormatRTF)
		[self makeNoteDirtyUpdateTime:NO updateFile:YES];
}

//how do we write a thousand RTF files at once, repeatedly? 

- (void)updateUnstyledTextWithBaseFont:(NSFont*)baseFont {

	if ([contentString restyleTextToFont:[[GlobalPrefs defaultPrefs] noteBodyFont] usingBaseFont:baseFont] > 0) {
		[undoManager removeAllActions];
		
		if ([_delegate currentNoteStorageFormat] == NVDatabaseFormatRTF)
			[self makeNoteDirtyUpdateTime:NO updateFile:YES];
	}
}

- (void)updateDateStrings {
	
	dateCreatedString = [NSString relativeDateStringWithAbsoluteTime:createdDate];
	dateModifiedString = [NSString relativeDateStringWithAbsoluteTime:modifiedDate];
}

- (void)setDateModified:(CFAbsoluteTime)newTime {
	modifiedDate = newTime;
	
	
	dateModifiedString = [NSString relativeDateStringWithAbsoluteTime:modifiedDate];
}

- (void)setDateAdded:(CFAbsoluteTime)newTime {
	createdDate = newTime;
	
	
	dateCreatedString = [NSString relativeDateStringWithAbsoluteTime:createdDate];	
}


- (void)setSelectedRange:(NSRange)newRange {
	//if (!newRange.length) newRange = NSMakeRange(0,0);
	
	//don't save the range if it's invalid, it's equal to the current range, or the entire note is selected
	if ((newRange.location != NSNotFound) && !NSEqualRanges(newRange, selectedRange) && 
		!NSEqualRanges(newRange, NSMakeRange(0, [contentString length]))) {
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
- (void)replaceMatchingLabelSet:(NSSet*)aLabelSet {
    [labelSet minusSet:aLabelSet];
    [labelSet unionSet:aLabelSet];
}

- (void)replaceMatchingLabel:(LabelObject*)aLabel {
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
	if (_delegate) {
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
		[_delegate note:self didRemoveLabelSet:oldLabels];
		[_delegate note:self didAddLabelSet:newLabels];
        
	}
}

- (void)disconnectLabels {
	//when removing this note from NotationController, other LabelObjects should know not to list it
	if (_delegate) {
		[_delegate note:self didRemoveLabelSet:labelSet];
		labelSet = nil;
	} else {
		NSLog(@"not disconnecting labels because no delegate exists");
	}
}

- (BOOL)_setLabelString:(NSString*)newLabelString {
	if (newLabelString && ![newLabelString isEqualToString:labelString]) {
		
		labelString = [newLabelString copy];
		
		[self updateLabelConnections];
		return YES;
	}
	return NO;
}

- (void)setLabelString:(NSString*)newLabelString {
	
	if ([self _setLabelString:newLabelString]) {
	
		if ([[GlobalPrefs defaultPrefs] horizontalLayout]) {
			[self updateTablePreviewString];
		}
		
		[self makeNoteDirtyUpdateTime:YES updateFile:YES];
		//[self registerModificationWithOwnedServices];
		
		[_delegate note:self attributeChanged:NVUIAttributeLabels];
	}
}

- (NSMutableSet*)labelSetFromCurrentString {
	
	NSArray *words = [self orderedLabelTitles];
	NSMutableSet *newLabelSet = [NSMutableSet setWithCapacity:[words count]];
	
	unsigned int i;
	for (i=0; i<[words count]; i++) {
		NSString *aWord = words[i];
		
		if ([aWord length] > 0) {
			LabelObject *aLabel = [[LabelObject alloc] initWithTitle:aWord];
			[aLabel addNote:self];
			
			[newLabelSet addObject:aLabel];
		}
	}
	
	return newLabelSet; 
}


- (NSArray*)orderedLabelTitles {
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

- (void)_drawLabelBlocksInRect:(NSRect)aRect rightAlign:(BOOL)onRight highlighted:(BOOL)isHighlighted getSizeOnly:(NSSize*)reqSize {
	//used primarily by UnifiedCell, but also by LabelColumnCell, as well as to determine the width of all label-block-images for this note
	//iterate over words in orderedLabelTitles, retrieving images via -[NotationController cachedLabelImageForWord:highlighted:]
	//if right-align is enabled, then the label-images are queued on the first pass and drawn in reverse on the second
	
	
	if (![labelString length]) {
		if (reqSize) *reqSize = NSZeroSize;
		return;
	}
	
	NSArray *words = [self orderedLabelTitles];
	if (![words count]) {
		if (reqSize) *reqSize = NSZeroSize;
		return;
	}
	
	CGFloat totalWidth = 0.0, height = 0.0;
	NSPoint nextBoxPoint = onRight ? NSMakePoint(NSMaxX(aRect), aRect.origin.y) : aRect.origin;
	NSMutableArray *images = reqSize || !onRight ? nil : [NSMutableArray arrayWithCapacity:[words count]];
	NSInteger i;
	
	for (i=0; i<(NSInteger)[words count]; i++) {
		NSString *word = words[i];
		if ([word length]) {
			NSImage *img = [_delegate cachedLabelImageForWord:word highlighted:isHighlighted];
			
			if (!reqSize) {
				if (onRight) {
					[images addObject:img];
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
	
	if (!reqSize) {
		if (onRight) {
			//draw images in reverse instead
			for (i = [images count] - 1; i>=0; i--) {
				NSImage *img = images[i];
				nextBoxPoint.x -= [img size].width + 4.0;
				[img compositeToPoint:nextBoxPoint operation:NSCompositeSourceOver];
			}
		}
	} else {
		if (reqSize) *reqSize = NSMakeSize(totalWidth, height);
	}
}


- (NSURL*)uniqueNoteLink {
		
	NSArray *svcs = [[SyncSessionController class] allServiceNames];
	NSMutableDictionary *idsDict = [NSMutableDictionary dictionaryWithCapacity:[svcs count] + 1];

	//include all identifying keys in case the title changes later
	NSUInteger i = 0;
	for (i=0; i<[svcs count]; i++) {
		NSString *syncID = syncServicesMD[svcs[i]][[[SyncSessionController allServiceClasses][i] nameOfKeyElement]];
		if (syncID) idsDict[svcs[i]] = syncID;
	}
	
	uuid_t uuid;
	[self.uniqueNoteID getUUIDBytes:uuid];
	NSData *uuidData = [NSData dataWithBytes:uuid length:sizeof(uuid_t)];
	
	idsDict[@"NV"] = [uuidData nv_stringByBase64Encoding];
	
	return [NSURL URLWithString:[@"nvalt://find/" stringByAppendingFormat:@"%@/?%@", [titleString stringWithPercentEscapes], 
								 [idsDict URLEncodedString]]];
}

- (NSString*)noteFilePath {
	UniChar chars[256];
	if ([_delegate refreshFileRefIfNecessary:self.noteFileRef withName:filename charsBuffer:chars] == noErr)
		return [[NSFileManager defaultManager] pathWithFSRef:self.noteFileRef];
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
	
    if ([_delegate createFileIfNotPresentInNotesDirectory:self.noteFileRef forFilename:filename fileWasCreated:&fileWasCreated] != noErr)
		return NO;
    
    if (fileWasCreated) {
		NSLog(@"writing note %@, because it didn't exist", titleString);
		return [self writeUsingCurrentFileFormat];
    }
    
	//createFileIfNotPresentInNotesDirectory: works by name, so if this file is not owned by us at this point, it was a race with moving it
    FSCatalogInfo info;
    if ([_delegate fileInNotesDirectory:self.noteFileRef isOwnedByUs:&fileIsOwned hasCatalogInfo:&info] != noErr)
		return NO;
    
    CFAbsoluteTime timeOnDisk, lastTime;
    OSStatus err = noErr;
    if ((err = (UCConvertUTCDateTimeToCFAbsoluteTime(&fileModifiedDate, &lastTime) == noErr)) &&
		(err = (UCConvertUTCDateTimeToCFAbsoluteTime(&info.contentModDate, &timeOnDisk) == noErr))) {
		
		if (lastTime > timeOnDisk) {
			NSLog(@"writing note %@, because it was modified", titleString);
			return [self writeUsingCurrentFileFormat];
		}
    } else {
		NSLog(@"Could not convert dates: %d", err);
		return NO;
    }
    
    return YES;
}

- (BOOL)writeUsingJournal:(WALStorageController*)wal {
    BOOL wroteAllOfNote = [wal writeEstablishedNote:self];
	
    if (!wroteAllOfNote) {
		[_delegate note:self failedToWriteWithError:[NSError nv_errorWithCode:NVErrorWriteJournal]];
	}
    
    return wroteAllOfNote;
}

- (BOOL)writeUsingCurrentFileFormat {

    NSData *formattedData = nil;
    NSError *error = nil;
	NSMutableAttributedString *contentMinusColor = nil;
	
    NVDatabaseFormat formatID = [_delegate currentNoteStorageFormat];
    switch (formatID) {
		case NVDatabaseFormatSingle:
			//we probably shouldn't be here
			NSAssert(NO, @"Warning! Tried to write data for an individual note in single-db format!");
			
			return NO;
		case NVDatabaseFormatPlain:
			
			if (!(formattedData = [[contentString string] dataUsingEncoding:fileEncoding allowLossyConversion:NO])) {
				
				//just make the file unicode and ram it through
				//unicode is probably better than UTF-8, as it's more easily auto-detected by other programs via the BOM
				//but we can auto-detect UTF-8, so what the heck
				[self _setFileEncoding:NSUTF8StringEncoding];
				//maybe we could rename the file file.utf8.txt here
				NSLog(@"promoting to unicode (UTF-8)");
				formattedData = [[contentString string] dataUsingEncoding:fileEncoding allowLossyConversion:YES];
			}
			break;
		case NVDatabaseFormatRTF:
			contentMinusColor = [contentString mutableCopy];
			[contentMinusColor removeAttribute:NSForegroundColorAttributeName range:NSMakeRange(0, [contentMinusColor length])];
			formattedData = [contentMinusColor RTFFromRange:NSMakeRange(0, [contentMinusColor length]) documentAttributes:nil];
			
			break;
		case NVDatabaseFormatHTML:
			//export to HTML document here using NSHTMLTextDocumentType;
			formattedData = [contentString dataFromRange:NSMakeRange(0, [contentString length]) 
									  documentAttributes:@{NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType} error:&error];
			//our links will always be to filenames, so hopefully we shouldn't have to change anything
			break;
		case NVDatabaseFormatDOC:
		case NVDatabaseFormatDOCX:
			NSLog(@"Attempted to write using unknown format ID: %ld", (long)formatID);
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
		
		if (![_delegate writeDataToNotesDirectory:formattedData name:filename destinationRef:self.noteFileRef error:&error]) {
			NSLog(@"Unable to save note file %@", filename);
			
			[_delegate note:self failedToWriteWithError:error];
			return NO;
		}
		
		//if writing plaintext set the file encoding with setxattr
		if (NVDatabaseFormatPlain == formatID) {
			[self writeCurrentFileEncodingToFSRef:self.noteFileRef];
		}
		
		NSFileManager *fileMan = [NSFileManager defaultManager];
		[fileMan setOpenMetaTags:[self orderedLabelTitles] atFSPath:[[fileMan pathWithFSRef:self.noteFileRef] fileSystemRepresentation]];
		
		//always hide the file extension for all types
		LSSetExtensionHiddenForRef(self.noteFileRef, TRUE);
		
		if (!resetFilename) {
			//NSLog(@"resetting the file name just because.");
			[self setFilenameFromTitle];
		}
		
		(void)[self writeFileDatesAndUpdateTrackingInfo];
		
		
		//finished writing to file successfully
		shouldWriteToFile = NO;
		
		
		//tell any external editors that we've changed
		
    } else {
		[_delegate note:self failedToWriteWithError:[NSError nv_errorWithCode:NVErrorDataFormatting]];
		NSLog(@"Unable to convert note contents into format %ld", (long)formatID);
		return NO;
    }
    
    return YES;
}

- (OSStatus)writeFileDatesAndUpdateTrackingInfo {
	if (NVDatabaseFormatSingle == currentFormatID) return noErr;
	
	//sync the file's creation and modification date:
	FSCatalogInfo catInfo;
	UCConvertCFAbsoluteTimeToUTCDateTime(createdDate, &catInfo.createDate);
	UCConvertCFAbsoluteTimeToUTCDateTime(modifiedDate, &catInfo.contentModDate);
	
	// if this method is called anywhere else, then use [delegate refreshFileRefIfNecessary:self.noteFileRef withName:filename charsBuffer:chars]; instead
	// for now, it is not called in any situations where the fsref might accidentally point to a moved file
	OSStatus err = noErr;
	do {
		if (noErr != err || IsZeros(self.noteFileRef, sizeof(FSRef))) {
			if (![_delegate notesDirectoryContainsFile:filename returningFSRef:self.noteFileRef]) return fnfErr;
		}
		err = FSSetCatalogInfo(self.noteFileRef, kFSCatInfoCreateDate | kFSCatInfoContentMod, &catInfo);
	} while (fnfErr == err);

	if (noErr != err) {
		NSLog(@"could not set catalog info: %d", err);
		return err;
	}
	
	//regardless of whether FSSetCatalogInfo was successful, the file mod date could still have changed
	
	if ((err = [_delegate fileInNotesDirectory:self.noteFileRef isOwnedByUs:NULL hasCatalogInfo:&catInfo]) != noErr) {
		NSLog(@"Unable to get new modification date of file %@: %d", filename, err);
		return err;
	}
	fileModifiedDate = catInfo.contentModDate;
	self.attrsModifiedDate = &catInfo.attributeModDate;
	self.nodeID = catInfo.nodeID;
	logicalSize = (UInt32)(catInfo.dataLogicalSize & 0xFFFFFFFF);
	
	return noErr;
}

- (OSStatus)writeCurrentFileEncodingToFSRef:(FSRef*)fsRef {
	NSAssert(fsRef, @"cannot write file encoding to a NULL FSRef");
	//this is not the note's own fsRef; it could be anywhere
	
	NSMutableData *pathData = [NSMutableData dataWithLength:4 * 1024];
	OSStatus err = noErr;
	if ((err = FSRefMakePath(fsRef, [pathData mutableBytes], (unsigned int)[pathData length])) == noErr) {
		[[NSFileManager defaultManager] setTextEncodingAttribute:fileEncoding atFSPath:[pathData bytes]];
	} else {
		NSLog(@"%@: error getting path from FSRef: %d (IsZeros: %d)", NSStringFromSelector(_cmd), err, IsZeros(fsRef, sizeof(fsRef)));
	}
	return err;
}

- (BOOL)upgradeToUTF8IfUsingSystemEncoding {
	if (CFStringConvertEncodingToNSStringEncoding(CFStringGetSystemEncoding()) == fileEncoding)
		return [self upgradeEncodingToUTF8];
	return NO;
}

- (BOOL)upgradeEncodingToUTF8 {
	//"convert" the file to have a UTF-8 encoding
	BOOL didUpgrade = YES;
	
	if (NSUTF8StringEncoding != fileEncoding) {
		[self _setFileEncoding:NSUTF8StringEncoding];
		
		if (currentFormatID == NVDatabaseFormatPlain) {
			// this note exists on disk as a plaintext file, and its encoding is incompatible with UTF-8
			
			if ([_delegate currentNoteStorageFormat] == NVDatabaseFormatPlain) {
				//actual conversion is expected because notes are presently being maintained as plain text files
				
				NSLog(@"rewriting %@ as utf8 data", titleString);
				didUpgrade = [self writeUsingCurrentFileFormat];
			} else if ([_delegate currentNoteStorageFormat] == NVDatabaseFormatSingle) {
				//update last-written-filemod time to guarantee proper encoding at next DB storage format switch,
				//in case this note isn't otherwise modified before that happens.
				//a side effect is that if the user switches to an RTF or HTML format,
				//this note will be written immediately instead of lazily upon the next modification
				if (UCConvertCFAbsoluteTimeToUTCDateTime(CFAbsoluteTimeGetCurrent(), &fileModifiedDate) != noErr)
					NSLog(@"%@: can't set file modification date from current date", NSStringFromSelector(_cmd));
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
		
		UniChar chars[256];
		if ([_delegate refreshFileRefIfNecessary:self.noteFileRef withName:filename charsBuffer:chars] != noErr)
			return NO;
		
		if ([self writeCurrentFileEncodingToFSRef:self.noteFileRef] != noErr)
			return NO;		
		
		if ((updated = [self updateFromFile])) {
			[self makeNoteDirtyUpdateTime:NO updateFile:NO];
			//need to update modification time manually
			[self registerModificationWithOwnedServices];
			[_delegate schedulePushToAllSyncServicesForNote:self];
			//[[delegate delegate] contentsUpdatedForNote:self];
		}
	}
	
	return updated;
}

- (BOOL)updateFromFile {
    NSMutableData *data = [_delegate dataFromFileInNotesDirectory:self.noteFileRef forFilename:filename];
    if (!data) {
		NSLog(@"Couldn't update note from file on disk");
		return NO;
    }
	
    if ([self updateFromData:data inFormat:currentFormatID]) {
		FSCatalogInfo info;
		if ([_delegate fileInNotesDirectory:self.noteFileRef isOwnedByUs:NULL hasCatalogInfo:&info] == noErr) {
			fileModifiedDate = info.contentModDate;
			self.attrsModifiedDate = &info.attributeModDate;
			self.nodeID = info.nodeID;
			logicalSize = (UInt32)(info.dataLogicalSize & 0xFFFFFFFF);
			
			return YES;
		}
    }
    return NO;
}

- (BOOL)updateFromCatalogEntry:(NoteCatalogEntry*)catEntry {
	BOOL didRestoreLabels = NO;
	
    NSMutableData *data = [_delegate dataFromFileInNotesDirectory:self.noteFileRef forCatalogEntry:catEntry];
    if (!data) {
		NSLog(@"Couldn't update note from file on disk given catalog entry");
		return NO;
    }
	    
    if (![self updateFromData:data inFormat:currentFormatID])
		return NO;
	
	[self setFilename:(__bridge NSString*)catEntry->filename withExternalTrigger:YES];
    
    fileModifiedDate = catEntry->lastModified;
	self.attrsModifiedDate = &catEntry->lastAttrModified;
	self.nodeID = catEntry->nodeID;
	logicalSize = catEntry->logicalSize;
	
	NSMutableData *pathData = [NSMutableData dataWithLength:4 * 1024];
	if (FSRefMakePath(self.noteFileRef, [pathData mutableBytes], (unsigned int)[pathData length]) == noErr) {
		
		NSArray *openMetaTags = [[NSFileManager defaultManager] getOpenMetaTagsAtFSPath:[pathData bytes]];
		if (openMetaTags) {
			//overwrite this note's labels with those from the file; merging may be the wrong thing to do here
			if ([self _setLabelString:[openMetaTags componentsJoinedByString:@" "]])
				[self updateTablePreviewString];
		} else if ([labelString length]) {
			//this file has either never had tags or has had them cleared by accident (e.g., non-user intervention)
			//so if this note still has tags, then restore them now.
			
			NSLog(@"restoring lost tags for %@", titleString);
			[[NSFileManager defaultManager] setOpenMetaTags:[self orderedLabelTitles] atFSPath:[pathData bytes]];
			didRestoreLabels = YES;
		}
	}
	
	OSStatus err = noErr;
	CFAbsoluteTime aModDate, aCreateDate;
	if (noErr == (err = UCConvertUTCDateTimeToCFAbsoluteTime(&fileModifiedDate, &aModDate))) {
		[self setDateModified:aModDate];
	}
	
	if (createdDate == 0.0 || didRestoreLabels) {
		//when reading files from disk for the first time, grab their creation date
		//or if this file has just been altered, grab its newly-changed modification dates
		
		FSCatalogInfo info;
		if ([_delegate fileInNotesDirectory:self.noteFileRef isOwnedByUs:NULL hasCatalogInfo:&info] == noErr) {
			if (createdDate == 0.0 && UCConvertUTCDateTimeToCFAbsoluteTime(&info.createDate, &aCreateDate) == noErr) {
				[self setDateAdded:aCreateDate];
			}
			if (didRestoreLabels) {
				fileModifiedDate = info.contentModDate;
				self.attrsModifiedDate = &info.attributeModDate;
			}
		}
	}
	
    return YES;
}

- (BOOL)updateFromData:(NSMutableData *)data inFormat:(NVDatabaseFormat)fmt {
    
    if (!data) {
		NSLog(@"%@: Data is nil!", NSStringFromSelector(_cmd));
		return NO;
    }
    
    NSMutableString *stringFromData = nil;
    NSMutableAttributedString *attributedStringFromData = nil;
    //interpret based on format; text, rtf, html, etc...
    switch (fmt) {
	case NVDatabaseFormatSingle:
	    //hmmmmm
		NSAssert(NO, @"Warning! Tried to update data from a note in single-db format!");
	    
	    break;
	case NVDatabaseFormatPlain:
		//try to merge/re-match attributes?
	    if ((stringFromData = [NSMutableString newShortLivedStringFromData:data ofGuessedEncoding:&fileEncoding withPath:NULL orWithFSRef:self.noteFileRef])) {
			attributedStringFromData = [[NSMutableAttributedString alloc] initWithString:stringFromData 
																			  attributes:[[GlobalPrefs defaultPrefs] noteBodyAttributes]];
	    } else {
			NSLog(@"String could not be initialized from data");
	    }
	    
	    break;
	case NVDatabaseFormatRTF:
	    
		attributedStringFromData = [[NSMutableAttributedString alloc] initWithRTF:data documentAttributes:NULL];
	    break;
	case NVDatabaseFormatHTML:

		attributedStringFromData = [[NSMutableAttributedString alloc] initWithHTML:data documentAttributes:NULL];
		[attributedStringFromData removeAttachments];
		
		break;
	case NVDatabaseFormatDOC:
	case NVDatabaseFormatDOCX:
	    NSLog(@"%@: Unknown format: %ld", NSStringFromSelector(_cmd), (long)fmt);
			break;
    }
    
    if (!attributedStringFromData) {
		NSLog(@"Couldn't make string out of data for note %@ with format %ld", titleString, (long)fmt);
		return NO;
    }
    
	contentString = attributedStringFromData;
	[contentString santizeForeignStylesForImporting];
	//NSLog(@"%s(%@): %@", _cmd, [self noteFilePath], [contentString string]);
	
	[undoManager removeAllActions];
	
	[self updateTablePreviewString];
    
	//don't update the date modified here, as this could be old data
    
    
    return YES;
}

- (void)updateWithSyncBody:(NSString*)newBody andTitle:(NSString*)newTitle {
	
	NSMutableAttributedString *attributedBodyString = [[NSMutableAttributedString alloc] initWithString:newBody attributes:[[GlobalPrefs defaultPrefs] noteBodyAttributes]];
	[attributedBodyString addLinkAttributesForRange:NSMakeRange(0, [attributedBodyString length])];
	[attributedBodyString addStrikethroughNearDoneTagsForRange:NSMakeRange(0, [attributedBodyString length])];
	
	//should eventually sync changes back to disk:
	[self setContentString:attributedBodyString updateTime:NO];

	//actions that user-editing via AppDelegate would have handled for us:
	[undoManager removeAllActions];

	[self setTitleString:newTitle];
}

- (void)moveFileToTrash {
	OSStatus err = noErr;
	if ((err = [_delegate moveFileToTrash:self.noteFileRef forFilename:filename]) != noErr) {
		NSLog(@"Couldn't move file to trash: %d", err);
	}
}

- (void)removeFileFromDirectory {
	[self moveFileToTrash];
}

- (BOOL)removeUsingJournal:(WALStorageController*)wal {
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
	
	if (updateTime) {
		[self setDateModified:CFAbsoluteTimeGetCurrent()];
		
		if ([_delegate currentNoteStorageFormat] == NVDatabaseFormatSingle) {
			//only set if we're not currently synchronizing to avoid re-reading old data
			//this will be updated again when writing to a file, but for now we have the newest version
			//we must do this to allow new notes to be written when switching formats, and for encodingmanager checks
			if (UCConvertCFAbsoluteTimeToUTCDateTime(modifiedDate, &fileModifiedDate) != noErr)
				NSLog(@"Unable to set file modification date from current date");
		}
	}
	if (updateFile && updateTime) {
		//if this is a change that affects the actual content of a note such that we would need to updateFile
		//and the modification time was actually updated, then dirty the note with the sync services, too
		[self registerModificationWithOwnedServices];
		[_delegate schedulePushToAllSyncServicesForNote:self];
	}
	
	//queue note to be written
    [_delegate scheduleWriteForNote:self];
}

- (BOOL)exportToDirectoryRef:(FSRef *)directoryRef withFilename:(NSString *)userFilename usingFormat:(NVDatabaseFormat)storageFormat overwrite:(BOOL)overwrite error:(out NSError **)outError
{
	NSData *formattedData = nil;
	NSError *error = nil;
	
	NSMutableAttributedString *contentMinusColor = [contentString mutableCopy];
	[contentMinusColor removeAttribute:NSForegroundColorAttributeName range:NSMakeRange(0, [contentMinusColor length])];
	
	switch (storageFormat) {
		case NVDatabaseFormatSingle:
			NSAssert(NO, @"Warning! Tried to export data in single-db format!?");
		case NVDatabaseFormatPlain:
			if (!(formattedData = [[contentMinusColor string] dataUsingEncoding:fileEncoding allowLossyConversion:NO])) {
				[self _setFileEncoding:NSUTF8StringEncoding];
				NSLog(@"promoting to unicode (UTF-8) on export--probably because internal format is singledb");
				formattedData = [[contentMinusColor string] dataUsingEncoding:fileEncoding allowLossyConversion:YES];
			}
			break;
		case NVDatabaseFormatRTF:
			formattedData = [contentMinusColor RTFFromRange:NSMakeRange(0, [contentMinusColor length]) documentAttributes:nil];
			break;
		case NVDatabaseFormatHTML:
			formattedData = [contentMinusColor dataFromRange:NSMakeRange(0, [contentMinusColor length])
										  documentAttributes:@{NSDocumentTypeDocumentAttribute: NSHTMLTextDocumentType} error:&error];
			break;
		case NVDatabaseFormatDOC:
			formattedData = [contentMinusColor docFormatFromRange:NSMakeRange(0, [contentMinusColor length]) documentAttributes:nil];
			break;
		case NVDatabaseFormatDOCX:
			formattedData = [contentMinusColor dataFromRange:NSMakeRange(0, [contentMinusColor length])
										  documentAttributes:@{NSDocumentTypeDocumentAttribute: NSWordMLTextDocumentType} error:&error];
			break;
		default:
			NSLog(@"Attempted to export using unknown format ID: %ld", (long)storageFormat);
    }
	
	if (!formattedData) {
		if (outError) *outError = [NSError nv_errorWithCode:NVErrorDataFormatting];
		return NO;
	}
	
	//can use our already-determined filename to write here
	//but what about file names that were the same except for their extension? e.g., .txt vs. .text
	//this will give them the same extension and cause an overwrite
	NSString *newextension = [NotationPrefs pathExtensionForFormat:storageFormat];
	NSString *newfilename = userFilename ? userFilename : [[filename stringByDeletingPathExtension] stringByAppendingPathExtension:newextension];
	//one last replacing, though if the unique file-naming method worked this should be unnecessary
	newfilename = [newfilename stringByReplacingOccurrencesOfString:@":" withString:@"/"];
	
	BOOL fileWasCreated = NO;
	
	FSRef fileRef;
	OSStatus err = FSCreateFileIfNotPresentInDirectory(directoryRef, &fileRef, (__bridge CFStringRef)newfilename, (Boolean*)&fileWasCreated);
	if (err != noErr) {
		NSLog(@"FSCreateFileIfNotPresentInDirectory: %d", err);
		if (outError) *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:err userInfo:nil];
		return NO;
	}
	
	if (!fileWasCreated && !overwrite) {
		NSLog(@"File already existed!");
		if (outError) *outError = [NSError errorWithDomain:NSOSStatusErrorDomain code:dupFNErr userInfo:nil];
		return dupFNErr;
	}
	
	NSURL *destinationURL = [NSURL nv_URLFromFSRef:&fileRef];
	if (![formattedData writeToURL:destinationURL options:0 error:&error]) {
		if (outError) *outError = error;
		return NO;
	}
	
	if (storageFormat == NVDatabaseFormatPlain) {
		[self writeCurrentFileEncodingToFSRef:&fileRef];
	}
	
	NSFileManager *fileMan = [NSFileManager defaultManager];
	[fileMan setOpenMetaTags:[self orderedLabelTitles] atFSPath:[[fileMan pathWithFSRef:&fileRef] fileSystemRepresentation]];
	
	//also export the note's modification and creation dates
	FSCatalogInfo catInfo;
	UCConvertCFAbsoluteTimeToUTCDateTime(createdDate, &catInfo.createDate);
	UCConvertCFAbsoluteTimeToUTCDateTime(modifiedDate, &catInfo.contentModDate);
	FSSetCatalogInfo(&fileRef, kFSCatInfoCreateDate | kFSCatInfoContentMod, &catInfo);
	
	if (outError) *outError = nil;
	return YES;
}

- (void)editExternallyUsingEditor:(ExternalEditor*)ed {
	[[ODBEditor sharedODBEditor] editNote:self inEditor:ed context:nil];
}

- (void)previewUsingMarked {
		NSWorkspace * ws = [NSWorkspace sharedWorkspace];
		[ws openFile:[self noteFilePath] withApplication:@"Marked" andDeactivate:NO];
}

- (void)abortEditingInExternalEditor {
	[[ODBEditor sharedODBEditor] abortAllEditingSessionsForClient:self];
}

-(void)odbEditor:(ODBEditor *)editor didModifyFile:(NSString *)path newFileLocation:(NSString *)newPath  context:(NSDictionary *)context {

	//read path/newPath into NSData and update note contents
	
	//can't use updateFromCatalogEntry because it would assign ownership via various metadata
	
	if ([self updateFromData:[NSMutableData dataWithContentsOfFile:path options:NSUncachedRead error:NULL] inFormat:NVDatabaseFormatPlain]) {
		//reflect the temp file's changes directly back to the backing-store-file, database, and sync services
		[self makeNoteDirtyUpdateTime:YES updateFile:YES];
		
		[_delegate note:self attributeChanged:NVUIAttributeNotePreview];
		[_delegate noteDidUpdateContents:self];
	} else {
		NSBeep();
		NSLog(@"odbEditor:didModifyFile: unable to get data from %@", path);
	}	
}
-(void)odbEditor:(ODBEditor *)editor didClosefile:(NSString *)path context:(NSDictionary *)context {
	//remove the temp file	
	[[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
}

- (NSRange)nextRangeForWords:(NSArray*)words options:(unsigned)opts range:(NSRange)inRange {
	//opts indicate forwards or backwards, inRange allows us to continue from where we left off
	//return location of NSNotFound and length 0 if none of the words could be found inRange
	
	unsigned int i;
	NSString *haystack = [contentString string];
	NSRange nextRange = NSMakeRange(NSNotFound, 0);
	for (i=0; i<[words count]; i++) {
		NSString *word = words[i];
		if ([word length] > 0) {
			nextRange = [haystack rangeOfString:word options:opts range:inRange];
			if (nextRange.location != NSNotFound && nextRange.length)
				break;
		}
	}

	return nextRange;
}

- (void)addPrefixParentNote:(NoteObject*)aNote {
	if (!prefixParentNotes) {
		prefixParentNotes = [[NSMutableArray alloc] initWithObjects:&aNote count:1];
	} else {
		[prefixParentNotes addObject:aNote];
	}
}
- (void)removeAllPrefixParentNotes {
	[prefixParentNotes removeAllObjects];
}

- (NSSet*)labelSet {
    return labelSet;
}

- (NSUndoManager*)undoManager {
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

#pragma mark - Comparators

- (NSComparisonResult)compare:(NoteObject *)other
{
	NSComparisonResult stringResult = [self.titleString caseInsensitiveCompare:other.titleString];
	if (stringResult == NSOrderedSame) {
		
		NSComparisonResult dateResult = [self compareCreatedDate:other];
		if (dateResult == NSOrderedSame)
			return [self compareUniqueNoteID:other];
		
		return dateResult;
	}
	
	return (NSInteger)stringResult;
}

- (NSComparisonResult)compareCreatedDate:(NoteObject *)other
{
	return NVComparisonResult(self.createdDate - other.createdDate);
}

- (NSComparisonResult)compareModifiedDate:(NoteObject *)other
{
	return NVComparisonResult(self.modifiedDate - other.modifiedDate);
	
}

- (NSComparisonResult)compareUniqueNoteID:(NoteObject *)other
{
	uuid_t left, right;
	[self.uniqueNoteID getUUIDBytes:left];
	[self.uniqueNoteID getUUIDBytes:right];
	return memcmp(&left, &right, sizeof(uuid_t));
}

- (BOOL)titleIsPrefixOfOtherNoteTitle:(NoteObject *)longer
{
	return [self.titleString rangeOfString:longer.titleString options:NSAnchoredSearch|NSDiacriticInsensitiveSearch|NSCaseInsensitiveSearch].location != NSNotFound;
}

+ (NSComparisonResult(^)(id, id))comparatorForAttribute:(NVUIAttribute)attribute reversed:(BOOL)reversed
{
	if (reversed) {
		switch (attribute) {
			case NVUIAttributeLabels:
				return ^(NoteObject *obj1, NoteObject *obj2){
					return [obj2.labelString caseInsensitiveCompare:obj1.labelString];
				};
			case NVUIAttributeDateModified:
				return ^(NoteObject *obj1, NoteObject *obj2){
					return [obj2 compareModifiedDate:obj1];
				};
			case NVUIAttributeDateCreated:
				return ^(NoteObject *obj1, NoteObject *obj2){
					return [obj2 compareCreatedDate:obj1];
				};
			default:
				return ^(NoteObject *obj1, NoteObject *obj2){
					return [obj2 compare:obj1];
				};
		}
	} else {
		switch (attribute) {
			case NVUIAttributeLabels:
				return ^(NoteObject *obj1, NoteObject *obj2){
					return [obj1.labelString caseInsensitiveCompare:obj2.labelString];
				};
			case NVUIAttributeDateModified:
				return ^(NoteObject *obj1, NoteObject *obj2){
					return [obj1 compareModifiedDate:obj2];
				};
			case NVUIAttributeDateCreated:
				return ^(NoteObject *obj1, NoteObject *obj2){
					return [obj1 compareCreatedDate:obj2];
				};
			default:
				return ^(NoteObject *obj1, NoteObject *obj2){
					return [obj1 compare:obj2];
				};
		}
	}
}

@end
