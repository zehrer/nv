//
//  AlienNoteImporter.m
//  Notation
//
//  Created by Zachary Schneirov on 11/15/06.

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


#import "AlienNoteImporter.h"
#import "StickiesDocument.h"
#import "URLGetter.h"
#import "GlobalPrefs.h"
#import "AttributedPlainText.h"
#import "NSData_transformations.h"
#import "NSCollection_utils.h"
#import "NSString_NV.h"
#import "NSFileManager_NV.h"
#import "NotationPrefs.h"
#import "NotationController.h"
#import "NoteObject.h"
#import <Quartz/Quartz.h>

NSString *PasswordWasRetrievedFromKeychainKey = @"PasswordRetrievedFromKeychain";
NSString *RetrievedPasswordKey = @"RetrievedPassword";
NSString *ShouldImportCreationDates = @"ShouldImportCreationDates";

@interface AlienNoteImporter (Private)
- (NSArray*)_importStickies:(NSString*)filename;
- (NSArray*)_importTSVFile:(NSString*)filename;
- (NSArray*)_importCSVFile:(NSString*)filename;
- (NSArray*)_importDelimitedFile:(NSString*)filename withDelimiter:(NSString*)delimiter;
@end

@implementation AlienNoteImporter

- (void)sharedInit
{
	shouldGrabCreationDates = NO;
	documentSettings = [[NSMutableDictionary alloc] init];
}

- (id)init {
	if ((self = [super init])) {
		shouldGrabCreationDates = NO;
		documentSettings = [[NSMutableDictionary alloc] init];
	}
	return self;
}

+ (void)importHelpFilesIfNecessaryIntoNotation:(NotationController*)notation {
	GlobalPrefs *prefsController = [GlobalPrefs defaultPrefs];
	NotationPrefs *prefs = [prefsController notationPrefs];
	if ([prefs firstTimeUsed]) {
		//add localized RTF help notes (how do we handle initializing a new NV copy when the owner just wants to re-sync from web? they will get new help notes each time?)
		NSArray *paths = [[NSBundle mainBundle] pathsForResourcesOfType:@"nvhelp" inDirectory:nil];
		NSArray *helpNotes = [[[AlienNoteImporter alloc] initWithStoragePaths:paths] importedNotes];
		if ([helpNotes count] > 0) {
			[notation addNotes:helpNotes];
			[[notation delegate] notation:notation revealNote:[helpNotes lastObject] options:NVEditNoteToReveal];
		}
	}
}

- (id)initWithStoragePaths:(NSArray*)filenames {
	if (!filenames) return nil;
	
	if ((self = [super init])) {
		source = filenames;
		importerSelector = @selector(notesWithPaths:);
		[self sharedInit];
	}
	return self;
}

- (id)initWithStoragePath:(NSString*)filename {
	if (!filename) return nil;
	
	if ((self = [self init])) {
		source = filename;
		
		//auto-detect based on bundle/extension/metadata
		NSDictionary *pathAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filename error:NULL];
		if ([[filename pathExtension] caseInsensitiveCompare:@"rtfd"] != NSOrderedSame &&
			[[pathAttributes objectForKey:NSFileType] isEqualToString:NSFileTypeDirectory]) {
			
			importerSelector = @selector(notesInDirectory:);
		} else {
			importerSelector = @selector(notesInFile:);
		}
		
		[self sharedInit];
	}
	return self;
}


- (NSDictionary*)documentSettings {
	return documentSettings;
}

- (NSView*)accessoryView {
	if (!importAccessoryView) {
		if (![NSBundle loadNibNamed:@"ImporterAccessory" owner:self])  {
			NSLog(@"Failed to load ImporterAccessory.nib");
			NSBeep();
			return nil;
		}
	}
	return importAccessoryView;
}

- (void)importNotesFromDialogAroundWindow:(NSWindow*)mainWindow receptionDelegate:(id)receiver {
	NSOpenPanel *openPanel = [NSOpenPanel openPanel];
	[openPanel setCanChooseFiles:YES];
	[openPanel setAllowsMultipleSelection:YES];
	[openPanel setCanChooseDirectories:YES];
	[openPanel setPrompt:NSLocalizedString(@"Import",@"title of button in import dialog")];
	[openPanel setTitle:NSLocalizedString(@"Import Notes",@"title of import dialog")];
	[openPanel setMessage:NSLocalizedString(@"Select files and folders from which to import notes.",@"import dialog message")];
	[openPanel setAccessoryView:[self accessoryView]];
	[grabCreationDatesButton setState:[[NSUserDefaults standardUserDefaults] boolForKey:ShouldImportCreationDates]];
	
	
	[openPanel beginSheetModalForWindow:mainWindow completionHandler:^(NSInteger result) {
		id delegate = receiver;
		
		if (delegate && [delegate respondsToSelector:@selector(noteImporter:importedNotes:)]) {
			
			if (result == NSOKButton) {
				shouldGrabCreationDates = [grabCreationDatesButton state] == NSOnState;
				[[NSUserDefaults standardUserDefaults] setBool:shouldGrabCreationDates forKey:ShouldImportCreationDates];
				NSArray *paths = [openPanel.URLs valueForKey:@"path"];
				NSArray *notes = [self notesWithPaths:paths];
				if (notes && [notes count])
					[delegate noteImporter:self importedNotes:notes];
				else
					NSRunAlertPanel(NSLocalizedString(@"None of the selected files could be imported.",nil),
									NSLocalizedString(@"Please choose other files.",nil), NSLocalizedString(@"OK",nil),nil,nil);
			}
		} else {
			NSLog(@"Where's my note importing delegate?");
			NSBeep();
		}
		
	}];
}

- (void)URLGetter:(URLGetter*)getter returnedDownloadedFile:(NSString*)filename {
	
	BOOL foundNotes = NO;
	if ([receptionDelegate respondsToSelector:@selector(noteImporter:importedNotes:)]) {

		if (filename) {
			NSArray *notes = [self notesInFile:filename];
			if ([notes count]) {
				NSMutableAttributedString *content = [[GlobalPrefs defaultPrefs] pastePreservesStyle] ? [[[notes lastObject] contentString] mutableCopy] :
													  [[NSMutableAttributedString alloc] initWithString:[[[notes lastObject] contentString] string]];
				if ([[[content string] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] length]) {
					//only add string if it has at least one non-whitespace character
					NSUInteger prefixedSourceLength = [[content prefixWithSourceString:[[getter url] absoluteString]] length];
					[content santizeForeignStylesForImporting];
					
					[[notes lastObject] setContentString:content];
					if ([getter userData]) [[notes lastObject] setTitleString:[getter userData]];
					
					//prefixing should push existing selections forward:
					NSRange selRange = [[notes lastObject] lastSelectedRange];
					if (selRange.length && prefixedSourceLength)
						[[notes lastObject] setSelectedRange:NSMakeRange(selRange.location + prefixedSourceLength, selRange.length)];
					
					[receptionDelegate noteImporter:self importedNotes:notes];
					
					foundNotes = YES;
				}
			}
		}
		if (!foundNotes) {	
			//no notes recovered from downloaded file--just add the URL as a string?
			NSString *urlString = [[getter url] absoluteString];
			if (urlString) {
				NSMutableAttributedString *newString = [[NSMutableAttributedString alloc] initWithString:urlString];
				[newString santizeForeignStylesForImporting];
				
				NoteObject *noteObject = [[NoteObject alloc] initWithNoteBody:newString title:[getter userData] ? [getter userData] : urlString
																	 delegate:nil format:NVDatabaseFormatSingle labels:nil];
				
				[receptionDelegate noteImporter:self importedNotes:[NSArray arrayWithObject:noteObject]];
			}
		}			
		
	} else {
		NSLog(@"Where's my note importing delegate?");
		NSBeep();
	}
	
	
}

- (void)importURLInBackground:(NSURL*)aURL linkTitle:(NSString*)linkTitle receptionDelegate:(id)receiver {
	
	receptionDelegate = receiver;
		
	
	(void)[[URLGetter alloc] initWithURL:aURL delegate:self userData:linkTitle];
}

- (NSArray*)importedNotes {
	if (!importerSelector) return nil;
	return [self performSelector:importerSelector withObject:source];
}

- (NSArray*)notesWithPaths:(NSArray*)paths {
	if ([paths isKindOfClass:[NSArray class]]) {
		
		NSMutableArray *array = [NSMutableArray array];
		NSFileManager *fileMan = [NSFileManager defaultManager];
		unsigned int i;
		for (i=0; i<[paths count]; i++) {
			NSString *path = [paths objectAtIndex:i];
			NSArray *notes = nil;
			
			NSDictionary *pathAttributes = [fileMan attributesOfItemAtPath:path error:NULL];
			if ([[path pathExtension] caseInsensitiveCompare:@"rtfd"] != NSOrderedSame &&
				[[pathAttributes objectForKey:NSFileType] isEqualToString:NSFileTypeDirectory]) {
				notes = [self notesInDirectory:path];
			} else {
				notes = [self notesInFile:path];
			}
			
			if (notes)
				[array addObjectsFromArray:notes];
		}
		
		return array;
	} else {
		NSLog(@"notesWithPaths: has the wrong kind of object!");
	}
	
	return nil;
}

//auto-detect based on file type/extension/header
//if unable to find, revert to spotlight importer
- (NoteObject*)noteWithFile:(NSString*)filename {
	//RTF, Text, Word, HTML, and anything else we can do without too much effort
	NSString *extension = [[filename pathExtension] lowercaseString];
	NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:filename error:NULL];
	unsigned long fileType = [[attributes objectForKey:NSFileHFSTypeCode] unsignedLongValue];
	NSString *sourceIdentifierString = nil;
	
	NSMutableAttributedString *attributedStringFromData = nil;

	if (fileType == HTML_TYPE_ID || [extension isEqualToString:@"htm"] || [extension isEqualToString:@"html"] || [extension isEqualToString:@"shtml"]) {
		//should convert to text with markdown here
        if ([[GlobalPrefs defaultPrefs] useMarkdownImport]) {
			if ([[GlobalPrefs defaultPrefs] useReadability] || [self shouldUseReadability]) {
				attributedStringFromData = [[NSMutableAttributedString alloc] initWithString:[self contentUsingReadability:filename] 
																				  attributes:[[GlobalPrefs defaultPrefs] noteBodyAttributes]];
			} else {
				attributedStringFromData = [[NSMutableAttributedString alloc] initWithString:[self markdownFromHTMLFile:filename] 
																				  attributes:[[GlobalPrefs defaultPrefs] noteBodyAttributes]];
			}
        } else {
			attributedStringFromData = [[NSMutableAttributedString alloc] initWithHTML:[NSData uncachedDataFromFile:filename] 
                                                                               options:[NSDictionary optionsDictionaryWithTimeout:10.0] documentAttributes:NULL];
        }		
	} else if (fileType == RTF_TYPE_ID || [extension isEqualToString:@"rtf"] || [extension isEqualToString:@"nvhelp"] || [extension isEqualToString:@"rtx"]) {
		attributedStringFromData = [[NSMutableAttributedString alloc] initWithRTF:[NSData uncachedDataFromFile:filename] documentAttributes:NULL];
		
	} else if (fileType == RTFD_TYPE_ID || [extension isEqualToString:@"rtfd"]) {
		NSFileWrapper *wrapper = [[NSFileWrapper alloc] initWithPath:filename];
		if ([[attributes objectForKey:NSFileType] isEqualToString:NSFileTypeDirectory])
			attributedStringFromData = [[NSMutableAttributedString alloc] initWithRTFDFileWrapper:wrapper documentAttributes:NULL];
		else
			attributedStringFromData = [[NSMutableAttributedString alloc] initWithRTFD:[NSData uncachedDataFromFile:filename] documentAttributes:NULL];
		
	} else if (fileType == WORD_DOC_TYPE_ID || [extension isEqualToString:@"doc"]) {
		attributedStringFromData = [[NSMutableAttributedString alloc] initWithDocFormat:[NSData uncachedDataFromFile:filename] documentAttributes:NULL];
		
	} else if ([extension isEqualToString:@"docx"] || [extension isEqualToString:@"webarchive"]) {
		//make it guess for us, but if it's a webarchive we'll get the URL
		NSData *data = [NSData uncachedDataFromFile:filename];
		NSString *path = [data pathURLFromWebArchive];
		attributedStringFromData = [[NSMutableAttributedString alloc] initWithData:data options:nil documentAttributes:NULL error:NULL];
		
		if ([path length] > 0 && [attributedStringFromData length] > 0)
			sourceIdentifierString = path;
	} else if (fileType == PDF_TYPE_ID || [extension isEqualToString:@"pdf"]) {
		//try PDFKit loading lazily
		@try {
            PDFDocument *doc = [[PDFDocument alloc] initWithURL:[NSURL fileURLWithPath:filename]];
            if (doc) {
                PDFSelection *sel = [doc selectionForEntireDocument];
                if (sel) {
                    attributedStringFromData = [[NSMutableAttributedString alloc] initWithAttributedString:[sel attributedString]];
                    //maybe we could check pages and boundsForPage: to try to determine where a line was soft-wrapped in the document?
                } else {
                    NSLog(@"Couldn't get entire doc selection for PDF");
                }
            } else {
                NSLog(@"Couldn't parse data into PDF");
            }
		} @catch (NSException *e) {
			NSLog(@"Error importing PDF %@ (%@, %@)", filename, [e name], [e reason]);
		}
	} else if (fileType == TEXT_TYPE_ID || [extension isEqualToString:@"txt"] || [extension isEqualToString:@"text"] ||
			   [filename UTIOfFileConformsToType:@"public.plain-text"]) {
		
		NSMutableString *stringFromData = [NSMutableString newShortLivedStringFromFile:filename];
		if (stringFromData) {
			attributedStringFromData = [[NSMutableAttributedString alloc] initWithString:stringFromData 
																			  attributes:[[GlobalPrefs defaultPrefs] noteBodyAttributes]];
		}
		
	}
	// else {
		//try spotlight importer if on 10.4
	//}
		

	if (attributedStringFromData) {
		[attributedStringFromData trimLeadingWhitespace];
		[attributedStringFromData removeAttachments];
		
		NSString *processedFilename = [[filename lastPathComponent] stringByDeletingPathExtension];
		NSUInteger bodyLoc = 0, prefixedSourceLength = 0;
		NSString *title = [[attributedStringFromData string] syntheticTitleAndSeparatorWithContext:NULL bodyLoc:&bodyLoc maxTitleLen:36];
		
		//if the synthetic title (generally the first line of the content) is shorter than the filename itself, just use the filename as the title
		//(or if this is a special case and we know the filename should be used)
		if ([processedFilename length] > [title length] || [extension isEqualToString:@"nvhelp"] || [title isAMachineDirective] || 
			[title isEqualToString:NSLocalizedString(@"Untitled Note", @"Title of a nameless note")]) {
			title = processedFilename;
			bodyLoc = 0;
		} else {
			title = [title stringByAppendingFormat:@" (%@)", processedFilename];
		}
		if ([sourceIdentifierString length])
			prefixedSourceLength = [[attributedStringFromData prefixWithSourceString:sourceIdentifierString] length];
		[attributedStringFromData santizeForeignStylesForImporting];
		
		NSUInteger attributedStringLength = attributedStringFromData.length;
		
		//transfer any openmeta tags associated with this file as tags for the new note
		NSArray *openMetaTags = [[NSFileManager defaultManager] getOpenMetaTagsAtFSPath:[filename fileSystemRepresentation]];
		
		//we do not also use filename as uniqueFilename, as we are only importing--not taking ownership
		NoteObject *noteObject = [[NoteObject alloc] initWithNoteBody:attributedStringFromData title:title delegate:nil 
															   format:NVDatabaseFormatSingle labels:[openMetaTags componentsJoinedByString:@" "]];
		if (noteObject) {
			if (bodyLoc > 0 && attributedStringLength >= bodyLoc + prefixedSourceLength) [noteObject setSelectedRange:NSMakeRange(prefixedSourceLength, bodyLoc)];
			if (shouldGrabCreationDates) {
				[noteObject setDateAdded:CFDateGetAbsoluteTime((CFDateRef)[attributes objectForKey:NSFileCreationDate])];
			}
			[noteObject setDateModified:CFDateGetAbsoluteTime((CFDateRef)[attributes objectForKey:NSFileModificationDate])];
			
			return noteObject;
		} else {
			NSLog(@"couldn't generate note object from imported attributed string??");
		}
		
	}
	return nil;
}

- (NSArray*)notesInDirectory:(NSString*)filename {
	
	//recurse through all subdirectories calling notesInFile where appropriate and collecting arrays into one
	//NSDirectoryEnumerator *enumerator  = [[NSFileManager defaultManager] enumeratorAtPath:filename];
	NSArray *filenames = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:filename error:NULL];
	NSEnumerator *enumerator = [filenames objectEnumerator];
	
	NSMutableArray *array = [NSMutableArray array];
	
	NSString *curObject = nil;
	NSFileManager *fileMan = [NSFileManager defaultManager];
	while ((curObject = [enumerator nextObject])) {
		@autoreleasepool {
		
			NSString *itemPath = [filename stringByAppendingPathComponent:curObject];
				
			if ([[[fileMan attributesOfItemAtPath:itemPath error:NULL] objectForKey:NSFileType] isEqualToString:NSFileTypeRegular]) {
				NSArray *notes = [self notesInFile:itemPath];
				if (notes)
					[array addObjectsFromArray:notes];
			}
		}
	}
	
	return array;
}

- (NSArray*)notesInFile:(NSString*)filename {
	NSString *extension = [[filename pathExtension] lowercaseString];
	
	if ([extension isEqualToString:@"blor"]) {
		return nil;
	} else if ([[filename lastPathComponent] isEqualToString:@"StickiesDatabase"]) {
		return [self _importStickies:filename];
	} else if ([extension isEqualToString:@"tsv"]) {
        return [self _importTSVFile:filename];
	} else if ([extension isEqualToString:@"csv"]) {
        return [self _importCSVFile:filename];
	} else {
		NoteObject *note = [self noteWithFile:filename];
		if (note)
			return [NSArray arrayWithObject:note];
	}
	return nil;
}

- (NSString *) contentUsingReadability: (NSString *)htmlFile
{
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *readabilityPath;
    readabilityPath = [bundle pathForAuxiliaryExecutable: @"readability.py"];
	
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath: readabilityPath];
	
	NSArray *arguments;
    arguments = [NSArray arrayWithObjects: htmlFile, nil];
    [task setArguments: arguments];
	
	NSPipe *rpipe;
    rpipe = [NSPipe pipe];
    [task setStandardOutput: rpipe];
	
    NSFileHandle *file;
    file = [rpipe fileHandleForReading];
	
    [task launch];
    [task waitUntilExit];
	
    NSData *data = [file readDataToEndOfFile];
	
    NSString *string;
    string = [[NSString alloc] initWithData: data
								   encoding: NSUTF8StringEncoding];

	return [self markdownFromSource:string];
}

- (NSString *) markdownFromHTMLFile: (NSString *)htmlFile
{
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *readabilityPath;
    readabilityPath = [bundle pathForAuxiliaryExecutable: @"html2text.py"];
	
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath: readabilityPath];
	
	NSArray *arguments;
    arguments = [NSArray arrayWithObjects: htmlFile, nil];
    [task setArguments: arguments];
	
	NSPipe *rpipe;
    rpipe = [NSPipe pipe];
    [task setStandardOutput: rpipe];
	
    NSFileHandle *file;
    file = [rpipe fileHandleForReading];
	
    [task launch];
    [task waitUntilExit];
	
    NSData *data = [file readDataToEndOfFile];
	
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (NSString *) markdownFromSource: (NSString *)htmlString
{
    NSBundle *bundle = [NSBundle mainBundle];
    NSString *readabilityPath;
    readabilityPath = [bundle pathForAuxiliaryExecutable: @"html2text.py"];
	
    NSTask *task = [[NSTask alloc] init];
    [task setLaunchPath: readabilityPath];
	
    NSPipe *readPipe = [NSPipe pipe];
    NSFileHandle *readHandle = [readPipe fileHandleForReading];
	
    NSPipe *writePipe = [NSPipe pipe];
    NSFileHandle *writeHandle = [writePipe fileHandleForWriting];
	
    [task setStandardInput: writePipe];
    [task setStandardOutput: readPipe];
	
    [task launch];
	
    [writeHandle writeData: [htmlString dataUsingEncoding: NSUTF8StringEncoding]];
    [writeHandle closeFile];
	
    NSMutableData *data = [[NSMutableData alloc] init];
    NSData *readData;
	
    while ((readData = [readHandle availableData])
           && [readData length]) {
        [data appendData: readData];
    }
	
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}
-(BOOL)shouldUseReadability
{
    return shouldUseReadability;
}

-(void) setShouldUseReadability:(BOOL)value
{
	shouldUseReadability = value;
}

@end

@implementation AlienNoteImporter (Private)

- (NSArray*)_importStickies:(NSString*)filename {
	NSMutableArray *stickyNotes = nil;
	NS_DURING
		NSData *stickyData = [NSData uncachedDataFromFile:filename];
		NSUnarchiver *unarchiver = [[NSUnarchiver alloc] initForReadingWithData:stickyData];
		[unarchiver decodeClassName:@"Document" asClassName:@"StickiesDocument"];
		stickyNotes = [unarchiver decodeObject];
	NS_HANDLER
		stickyNotes = nil;
		NSLog(@"Error parsing stickies database: %@", [localException reason]);
	NS_ENDHANDLER
	
	if (stickyNotes && [stickyNotes isKindOfClass:[NSMutableArray class]]) {
		NSMutableArray *notes = [NSMutableArray arrayWithCapacity:[stickyNotes count]];
		
		unsigned int i;
		for (i=0; i<[stickyNotes count]; i++) {
			StickiesDocument *doc = [stickyNotes objectAtIndex:i];
			if ([doc isKindOfClass:[StickiesDocument class]]) {
				NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithRTFD:[doc RTFDData] documentAttributes:NULL];
				[attributedString removeAttachments];
				[attributedString santizeForeignStylesForImporting];
				NSString *syntheticTitle = [attributedString trimLeadingSyntheticTitle];
				
				NoteObject *noteObject = [[NoteObject alloc] initWithNoteBody:attributedString title:syntheticTitle 
																	  delegate:nil format:NVDatabaseFormatSingle labels:nil];
				if (noteObject) {
					[noteObject setDateAdded:CFDateGetAbsoluteTime((CFDateRef)[doc creationDate])];
					[noteObject setDateModified:CFDateGetAbsoluteTime((CFDateRef)[doc modificationDate])];

					[notes addObject:noteObject];
				} else {
					NSLog(@"couldn't generate note object from sticky note??");
				}
			} else {
				NSLog(@"Sticky document is wrong: %@", [doc description]);
			}
		}
		
		
		return notes;
	} else {
		NSLog(@"Sticky notes array is wrong: %@", [stickyNotes description]);
	}
	
	return nil;
}

- (NSArray*)_importTSVFile:(NSString*)filename {
	return [self _importDelimitedFile:filename withDelimiter:@"\t"];
}
- (NSArray*)_importCSVFile:(NSString*)filename {
	return [self _importDelimitedFile:filename withDelimiter:@","];
}

- (NSArray*)_importDelimitedFile:(NSString*)filename withDelimiter:(NSString*)delimiter {
	
	NSMutableString *contents = [NSMutableString newShortLivedStringFromFile:filename];
	if (!contents) return nil;
    
    // normalize newlines
    [contents replaceOccurrencesOfString:@"\r\n" withString:@"\n" options:0 range:NSMakeRange(0, [contents length])];
    [contents replaceOccurrencesOfString:@"\r" withString:@"\n" options:0 range:NSMakeRange(0, [contents length])];
    
    NSMutableArray *notes = [NSMutableArray array];
    NSArray *lines = [contents componentsSeparatedByString:@"\n"];
    NSEnumerator *en = [lines objectEnumerator];
    NSString *curLine;
	
	CFAbsoluteTime now = CFAbsoluteTimeGetCurrent();
	
    // Assume first entry in line is note title and any other entries go in the note body
    while ((curLine = [en nextObject])) {
        NSArray *fields = [curLine componentsSeparatedByString:delimiter];
        NSUInteger count = [fields count];
        if (count > 1) {
            NSMutableString *s = [NSMutableString string];
            NSUInteger i;
            for (i = 1; i < count; ++i) {
                NSString *entry = [fields objectAtIndex:i];
                if ([entry length] > 0)
                    [s appendString:[NSString stringWithFormat:@"%@\n", entry]];
            }
            
            if (0 == [s length])
                continue;
            
            NSString *title = [fields objectAtIndex:0];
			NSMutableAttributedString *attributedBody = [[NSMutableAttributedString alloc] initWithString:s attributes:[[GlobalPrefs defaultPrefs] noteBodyAttributes]];
			[attributedBody addLinkAttributesForRange:NSMakeRange(0, [attributedBody length])];
			[attributedBody addStrikethroughNearDoneTagsForRange:NSMakeRange(0, [attributedBody length])];
			
            NoteObject *note = [[NoteObject alloc] initWithNoteBody:attributedBody title:title delegate:nil format:NVDatabaseFormatSingle labels:nil];
			if (note) {
				now += 1.0; //to ensure a consistent sort order
				[note setDateAdded:now];
				[note setDateModified:now];
				[notes addObject:note];
			}
        }
    }
    
    return (notes);
}
@end
