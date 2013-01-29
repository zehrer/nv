//
//  NotationFileManager.m
//  Notation
//
//  Created by Zachary Schneirov on 4/9/06.

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


#import "NotationFileManager.h"
#import "NSString_NV.h"
#import "NSFileManager_NV.h"
#import "GlobalPrefs.h"
#import "NSData_transformations.h"
#import "NSURL+Notation.h"
#import "NoteCatalogEntry.h"
#import "NSDate+Notation.h"

#import <CommonCrypto/CommonCrypto.h>

NSString *NotesDatabaseFileName = @"Notes & Settings";

@interface NotationController ()

@property (nonatomic, copy, readwrite) NSURL *noteDatabaseURL;
@property (nonatomic, copy, readwrite) NSURL *noteDirectoryURL;

@end

@implementation NotationController (NotationFileManager)

+ (NSURL *)createDirectoryIfNotPresentWithName:(NSString *)subName inDirectory:(NSURL *)directory error:(out NSError **)outError {
	NSURL *URL = [directory URLByAppendingPathComponent: subName isDirectory: YES];
	if (![URL checkResourceIsReachableAndReturnError: NULL]) {
		NSError *error = nil;
		if ([[NSFileManager defaultManager] createDirectoryAtURL: URL withIntermediateDirectories: YES attributes: nil error: &error]) {
			return URL;
		} else {
			if (outError) *outError = error;
			return nil;
		}
	}
	return URL;
}

// Create a version 3 UUID; derived using "name" via MD5 checksum.
static void uuid_create_md5_from_name(unsigned char result_uuid[16], const void *name, int namelen) {

	static unsigned char FSUUIDNamespaceSHA1[16] = {
			0xB3, 0xE2, 0x0F, 0x39, 0xF2, 0x92, 0x11, 0xD6,
			0x97, 0xA4, 0x00, 0x30, 0x65, 0x43, 0xEC, 0xAC
	};

	CC_MD5_CTX c;

	CC_MD5_Init(&c);
	CC_MD5_Update(&c, FSUUIDNamespaceSHA1, sizeof(FSUUIDNamespaceSHA1));
	CC_MD5_Update(&c, name, namelen);
	CC_MD5_Final(result_uuid, &c);

	result_uuid[6] = (result_uuid[6] & 0x0F) | 0x30;
	result_uuid[8] = (result_uuid[8] & 0x3F) | 0x80;
}

- (void)initializeDiskUUIDIfNecessary {
	//create a CFUUIDRef that identifies the volume this database sits on

	//don't bother unless we will be reading notes as separate files; otherwise there's no need to track the source of the attr mod dates
	//maybe disk UUIDs will be used in the future for something else; at that point this check should be altered

	if (!diskUUID && [self currentNoteStorageFormat] != SingleDatabaseFormat) {

		id uuidString = nil;
		[self.noteDirectoryURL getResourceValue: &uuidString forKey: NSURLVolumeUUIDStringKey error: NULL];
		if (uuidString) diskUUID = CFUUIDCreateFromString(NULL, (__bridge CFStringRef)uuidString);

		if (!diskUUID) {
			// all other checks failed; just use the volume's creation date
			NSDate *date = nil;
			[self.noteDirectoryURL getResourceValue: &date forKey: NSURLVolumeCreationDateKey error: NULL];
			if (date) {
				// UTCDateTime
				UTCDateTime dateTime;
				[date getUTCDateTime: &dateTime];
				dateTime.highSeconds = CFSwapInt16HostToBig(dateTime.highSeconds);
				dateTime.lowSeconds = CFSwapInt32HostToBig(dateTime.lowSeconds);
				dateTime.fraction = CFSwapInt16HostToBig(dateTime.fraction);

				CFUUIDBytes uuidBytes;
				uuid_create_md5_from_name((void *) &uuidBytes, (void *) &dateTime, sizeof(UTCDateTime));

				diskUUID = CFUUIDCreateFromUUIDBytes(NULL, uuidBytes);
			} else {
				NSLog(@"can't even get the volume creation date -- what are you trying to do to me?");
				return;
			}
		}

		diskUUIDIndex = [notationPrefs tableIndexOfDiskUUID:diskUUID];
	}
}

- (NSUInteger)diskUUIDIndex {
	return diskUUIDIndex;
}

- (NSURL *)refreshFileURLIfNecessary:(NSURL *)URL withName:(NSString *)filename error: (NSError **)err {
	if (!URL || ![self fileInNotesDirectoryIsOwnedByUs: URL]) {
		return [self.noteDirectoryURL URLByAppendingPathComponent: filename];
	}
	return URL;
}

- (BOOL)notesDirectoryIsTrashed {
	NSURL *trashURL = [self.fileManager URLForDirectory: NSTrashDirectory inDomain:NSUserDomainMask appropriateForURL: nil create:YES error: NULL];
	if (!trashURL) return NO;
	NSURL *stdNoteDirectory = self.noteDirectoryURL;
	return [stdNoteDirectory.path hasPrefix: trashURL.path];
}

- (NSURL *)notesDirectoryContainsFile:(NSString *)filename {
	if (!filename) return nil;
	return [self.noteDirectoryURL URLByAppendingPathComponent: filename];
}

- (BOOL)renameAndForgetNoteDatabaseFile:(NSString *)newfilename {
	//this method does not move the note database file; for now it is used in cases of upgrading incompatible files
	NSURL *newURL = [self.noteDatabaseURL.URLByDeletingLastPathComponent URLByAppendingPathComponent: newfilename];
	NSError *error = nil;
	if ([self.fileManager moveItemAtURL: self.noteDatabaseURL toURL: newURL error: &error]) {
		self.noteDatabaseURL = newURL;
		return YES;
	}

	self.noteDatabaseURL = nil;
	return NO;
}

- (BOOL)removeSpuriousDatabaseFileNotes {
	//remove any notes that might have been made out of the database or write-ahead-log files by accident
	//but leave the files intact; ensure only that they are also remotely unsynced
	//returns true if at least one note was removed, in which case allNotes should probably be refiltered

	NSUInteger i = 0;
	NoteObject *dbNote = nil, *walNote = nil;

	for (i = 0; i < [allNotes count]; i++) {
		NoteObject *obj = allNotes[i];

		if (!dbNote && [obj.filename isEqualToString:NotesDatabaseFileName])
			dbNote = obj;
		if (!walNote && [obj.filename isEqualToString:@"Interim Note-Changes"])
			walNote = obj;
	}
	if (dbNote) {
		[allNotes removeObjectIdenticalTo:dbNote];
		[self _addDeletedNote:dbNote];
	}
	if (walNote) {
		[allNotes removeObjectIdenticalTo:walNote];
		[self _addDeletedNote:walNote];
	}
	return walNote || dbNote;
}

- (void)relocateNotesDirectory {

	while (1) {
		NSOpenPanel *openPanel = [NSOpenPanel openPanel];
		[openPanel setCanCreateDirectories:YES];
		[openPanel setCanChooseFiles:NO];
		[openPanel setCanChooseDirectories:YES];
		[openPanel setResolvesAliases:YES];
		[openPanel setAllowsMultipleSelection:NO];
		[openPanel setTreatsFilePackagesAsDirectories:NO];
		[openPanel setTitle:NSLocalizedString(@"Select a folder", nil)];
		[openPanel setPrompt:NSLocalizedString(@"Select", nil)];
		[openPanel setMessage:NSLocalizedString(@"Select a new location for your Notational Velocity notes.", nil)];

		if ([openPanel runModal] == NSOKButton) {
			NSURL *newURL = openPanel.URL;
			
			NSString *filename = newURL.path;
			if (filename) {

				FSRef newParentRef;
				CFURLRef url = CFURLCreateWithFileSystemPath(kCFAllocatorDefault, (__bridge CFStringRef) filename, kCFURLPOSIXPathStyle, true);
				if (!url || !CFURLGetFSRef(url, &newParentRef)) {
					NSRunAlertPanel(NSLocalizedString(@"Unable to create an FSRef from the chosen directory.", nil),
							NSLocalizedString(@"Your notes were not moved.", nil), NSLocalizedString(@"OK", nil), NULL, NULL);
					if (url) CFRelease(url);
					continue;
				}
				CFRelease(url);

				NSURL *oldURL = self.noteDirectoryURL;

				NSError *err = nil;
				if ([self.fileManager moveItemAtURL: self.noteDirectoryURL toURL: newURL error: &err]) {
					self.noteDirectoryURL = newURL;
				} else {
					NSRunAlertPanel([NSString stringWithFormat:NSLocalizedString(@"Couldn't move notes into the chosen folder because %@", nil), [err localizedDescription]], NSLocalizedString(@"Your notes were not moved.", nil), NSLocalizedString(@"OK", nil), NULL, NULL);
					continue;
				}

				if ([oldURL isEqualToFileURL: self.noteDirectoryURL]) {
					NSURL *homeFolder = [NSURL fileURLWithPath: NSHomeDirectory() isDirectory: YES];
					NSData *bookmarkData = [self.noteDirectoryURL bookmarkDataWithOptions: 0 includingResourceValuesForKeys: nil relativeToURL: homeFolder error: NULL];
					if (bookmarkData) [[GlobalPrefs defaultPrefs] setBookmarkDataForDefaultDirectory: bookmarkData sender: self];
					//we must quit now, as notes will very likely be re-initialized in the same place
					[NSApp terminate:nil];
					break;
				}

				//directory move successful! //show the user where new notes are
				[[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs: @[ self.noteDirectoryURL ]];

				break;
			} else {
				[NSApp terminate:nil];
				break;
			}
		} else {
			[NSApp terminate:nil];
			break;
		}
	}
}

+ (NSURL *)defaultNoteDirectoryURLReturningError:(out NSError **)outErr {
	NSError *err = nil;
	NSURL *appSupportURL = nil;
	NSURL *noteDirectoryURL = nil;

	if ((appSupportURL = [[NSFileManager defaultManager] URLForDirectory: NSApplicationSupportDirectory inDomain: NSUserDomainMask appropriateForURL: nil create: YES error: &err])) {
		if ((noteDirectoryURL = [self createDirectoryIfNotPresentWithName: @"Notational Data" inDirectory: appSupportURL error: &err])) {
			return noteDirectoryURL;
		}
	}

	if (outErr) *outErr = err;

	return nil;
}

//whenever a note uses this method to change its filename, we will have to re-establish all the links to it
- (NSString *)uniqueFilenameForTitle:(NSString *)title fromNote:(NoteObject *)note {
	//generate a unique filename based on title, varying numbers
	__block BOOL isUnique = YES;
	__block NSString *uniqueFilename = title;

	//remove illegal characters
	NSMutableString *sanitizedName = [[uniqueFilename stringByReplacingOccurrencesOfString:@":" withString:@"-"] mutableCopy];
	if ([sanitizedName characterAtIndex:0] == (unichar) '.') [sanitizedName replaceCharactersInRange:NSMakeRange(0, 1) withString:@"_"];
	uniqueFilename = [sanitizedName copy];

	//use the note's current format if the current default format is for a database; get the "ideal" extension for that format
	NoteStorageFormat noteFormat = [notationPrefs notesStorageFormat] || !note ? [notationPrefs notesStorageFormat] : note.storageFormat;
	NSString *extension = [notationPrefs chosenPathExtensionForFormat:noteFormat];

	//if the note's current extension is compatible with the storage format above, then use the existing extension instead
	if (note && note.filename && [notationPrefs pathExtensionAllowed:note.filename.pathExtension forFormat:noteFormat])
		extension = note.filename.pathExtension;

	//assume that we won't have more than 999 notes with the exact same name and of more than 247 chars
	uniqueFilename = [uniqueFilename filenameExpectingAdditionalCharCount:3 + [extension length] + 2];

	__block NSUInteger iteration = 0;
	do {
		isUnique = YES;

		//this ought to just use an nsset, but then we'd have to maintain a parallel data structure for marginal benefit
		//also, it won't quite work right for filenames with no (real) extensions and periods in their names
		[allNotes enumerateObjectsWithOptions:NSEnumerationConcurrent usingBlock:^(NoteObject *aNote, NSUInteger idx, BOOL *stop) {
			NSString *basefilename = [aNote.filename stringByDeletingPathExtension];

			if (note != aNote && [basefilename caseInsensitiveCompare:uniqueFilename] == NSOrderedSame) {
				isUnique = NO;

				uniqueFilename = [uniqueFilename stringByDeletingPathExtension];
				NSString *numberPath = [@(++iteration) stringValue];
				uniqueFilename = [uniqueFilename stringByAppendingPathExtension:numberPath];
				*stop = YES;
			}
		}];
	} while (!isUnique);

	return [uniqueFilename stringByAppendingPathExtension:extension];
}

- (NSURL *)noteFileRenamed:(NSURL *)noteFileURL fromName:(NSString *)oldName toName:(NSString *)newName error:(out NSError **)outError {
	if (![self currentNoteStorageFormat])
		return noteFileURL;

	NSError *error = nil;
	NSURL *oldURL = [self refreshFileURLIfNecessary: noteFileURL withName: oldName error: &error];
	NSURL *newURL = [self URLForFileInNotesDirectory: newName];

	if (oldURL && newURL) {
		if ([self.fileManager moveItemAtURL: oldURL toURL: newURL error: &error]) {
			return newURL;
		}
	}
	
	if (outError) *outError = error;
	return nil;
}

- (BOOL)fileInNotesDirectoryIsOwnedByUs:(NSURL *)URL {
	return [URL.URLByDeletingLastPathComponent isEqualToFileURL: self.noteDirectoryURL];
}

- (NSMutableData *)dataForFilenameInNotesDirectory:(NSString *)filename URL:(out NSURL **)outURL {
	NSURL *URL = [self URLForFileInNotesDirectory: filename];
	NSMutableData *data = [NSMutableData dataWithContentsOfURL: URL options: NSDataReadingUncached error: NULL];
	if (data && outURL) *outURL = URL;
	return data;
}

- (NSMutableData *)dataForCatalogEntryInNotesDirectory:(NoteCatalogEntry *)catEntry URL:(out NSURL **)outURL {
	return [self dataForFilenameInNotesDirectory: catEntry.filename URL: outURL];
}

- (NSURL *)createFileWithNameIfNotPresentInNotesDirectory:(NSString *)filename created:(BOOL *)created error:(out NSError **)outError {
	NSURL *URL = [self.noteDirectoryURL URLByAppendingPathComponent: filename];
	if (![URL checkResourceIsReachableAndReturnError: NULL]) {
		return [[NSData data] writeToURL: URL options: NSDataWritingWithoutOverwriting error: outError] ? URL : nil;
	}
	return URL;
}

//either name or destRef must be valid; destRef is declared invalid by filling the struct with 0

- (NSURL *)writeDataToNotesDirectory:(NSData *)data withName:(NSString *)filename verifyUsingBlock:(BOOL(^)(NSURL *, NSError **))block error:(NSError **)outError {
	NSURL *notesDatabaseURL = [self.noteDirectoryURL URLByAppendingPathComponent: filename];

	NSError *error = nil;

	NSURL *temporaryDatabaseFolder = [self.fileManager URLForDirectory: NSItemReplacementDirectory inDomain: NSUserDomainMask appropriateForURL: notesDatabaseURL create: YES error:&error];
	if (!temporaryDatabaseFolder) {
		NSLog(@"Error securing temporary file: %@", error);
		if (outError) *outError = error;
		return nil;
	}

	NSURL *temporaryDatabaseURL = [temporaryDatabaseFolder URLByAppendingPathComponent: filename];
	
	// write data to temporary file
	if (![data writeToURL: temporaryDatabaseURL options:0 error: &error]) {
		NSLog(@"Error writing to temporary file: %@", error);
		if (outError) *outError = error;
		return nil;
	}

	// before we try to swap the data contents of this temp file with the (possibly even soon-to-be-created) Notes & Settings file,
	// try to read it back and see if it can be decrypted and decoded:
	if (block) {
		if (!block(temporaryDatabaseURL, &error)) {
			NSLog(@"couldn't verify written notes, so not continuing to save");
			[self.fileManager removeItemAtURL: temporaryDatabaseURL error: NULL];
			if (outError) *outError = error;
			return nil;
		}
	}

	NSURL *newURL = nil;

	// if it exists, swap; otherwise, just move
	if ([notesDatabaseURL checkResourceIsReachableAndReturnError: NULL]) {
		if (![self.fileManager replaceItemAtURL: notesDatabaseURL withItemAtURL: temporaryDatabaseURL backupItemName: nil options: 0 resultingItemURL: &newURL error: &error]) {
			NSLog(@"error exchanging contents of temporary file with destination file %@: %@", filename, error);
			if (outError) *outError = error;
			return nil;
		}
	} else {
		if ([self.fileManager moveItemAtURL: temporaryDatabaseURL toURL: notesDatabaseURL error: &error]) {
			newURL = [notesDatabaseURL copy];
		} else {
			NSLog(@"error moving temporary file to destination file %@: %@", filename, error);
			if (outError) *outError = error;
			return nil;
		}
	}
	
	return newURL;
}

- (void)notifyOfChangedTrash {
	NSURL *sillyURL = [NSURL fileURLWithPath: [NSTemporaryDirectory() stringByAppendingPathComponent: [NSString ntn_stringWithRandomizedFileName]]];
	[self.fileManager createDirectoryAtURL: sillyURL withIntermediateDirectories: YES attributes: nil error: NULL];
	[self.fileManager trashItemAtURL: sillyURL resultingItemURL: NULL error: NULL];
}

- (NSURL *)moveFileToTrash:(NSURL *)childURL forFilename:(NSString *)filename error:(out NSError **)outError {
	NSError *error = nil;

	if ((childURL = [self refreshFileURLIfNecessary: childURL withName: filename error: &error])) {
		NSURL *outURL = nil;
		if (([self.fileManager trashItemAtURL: childURL resultingItemURL: &outURL error: &error])) {

			if (![self.noteDirectoryURL setResourceValue: [NSDate date] forKey: NSURLContentModificationDateKey error: &error]) {
				NSLog(@"couldn't touch modification date of file's parent folder: error %@", error);
			}
			return outURL;
		}
	}

	if (outError) *outError = error;
	return nil;
}

- (NSURL *)URLForFileInNotesDirectory:(NSString *)filename {
	return [self.noteDirectoryURL URLByAppendingPathComponent: filename];
}

@end
