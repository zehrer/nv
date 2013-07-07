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


#import "ExporterManager.h"
#import "NoteObject.h"
#import "NotationPrefs.h"
#import "NSString_NV.h"
#import "GlobalPrefs.h"

@implementation ExporterManager

+ (ExporterManager *)sharedManager {
	static ExporterManager *man = nil;
	if (!man)
		man = [[ExporterManager alloc] init];
	return man;
}

- (void)awakeFromNib {
	
	NVDatabaseFormat storageFormat = [[[GlobalPrefs defaultPrefs] notationPrefs] notesStorageFormat];
	[formatSelectorPopup selectItemWithTag:storageFormat];
}

- (IBAction)formatSelectorChanged:(id)sender {
	//NSSavePanel *panel = (NSSavePanel *)[sender window];
	//int storageFormat = [[formatSelectorPopup selectedItem] tag];
    //[panel setRequiredFileType:[NotationPrefs pathExtensionForFormat:storageFormat]];
}

- (void)exportNotes:(NSArray*)notes forWindow:(NSWindow*)window {
	
	if (!accessoryView) {
		if (![NSBundle loadNibNamed:@"ExporterManager" owner:self]) {
			NSLog(@"Failed to load ExporterManager.nib");
			NSBeep();
			return;
		}
	}
	
	BOOL isOpen = NO;
	if ([notes count] > 1) {
		isOpen = YES;
	} else if ([notes count] != 1) {
		NSRunAlertPanel(NSLocalizedString(@"No notes were selected for exporting.",nil),
						NSLocalizedString(@"You must select at least one note to export.",nil), NSLocalizedString(@"OK",nil), NULL, NULL);
		return;
	}
	
	NSOpenPanel *openPanel = nil;
	NSSavePanel *savePanel = nil;
	if (isOpen) {
		openPanel = [NSOpenPanel openPanel];
	} else {
		savePanel = [NSSavePanel savePanel];
	}
	
	void (^completion)(NSInteger) = ^(NSInteger returnCode){
		if (returnCode == NSFileHandlingPanelOKButton && notes) {
			//write notes in chosen format
			NSUInteger i;
			NSInteger result;
			NVDatabaseFormat storageFormat = [[formatSelectorPopup selectedItem] tag];
			NSURL *directory = nil;
			NSString *filename = nil;
			BOOL overwriteNotes = NO;
			
			if (isOpen) {
				directory = [openPanel URL];
			} else {
				NSURL *URL = [savePanel URL];
				filename = [URL lastPathComponent];
				directory = [URL URLByDeletingLastPathComponent];
				
				NSAssert([notes count] == 1, @"We returned from a save panel with more than one note?!");
				
				//user wanted us to overwrite this one--otherwise dialog would have been cancelled
				if ([URL checkResourceIsReachableAndReturnError:NULL]) {
					overwriteNotes = YES;
				}
				
				if ([filename compare:[[notes lastObject] filename] options:NSCaseInsensitiveSearch] != NSOrderedSame) {
					//undo any POSIX-safe crap NSSavePanel gave us--otherwise FSCreateFileUnicode will fail
					filename = [filename stringByReplacingOccurrencesOfString:@":" withString:@"/"];
				}
			}
			
			FSRef directoryRef;
			if (!directory || !CFURLGetFSRef((CFURLRef)directory, &directoryRef)) {
				NSRunAlertPanel([NSString stringWithFormat:NSLocalizedString(@"The notes couldn't be exported because the directory quotemark%@quotemark couldn't be accessed.",nil), [directory.path stringByAbbreviatingWithTildeInPath]], @"", NSLocalizedString(@"OK",nil), nil, nil);
				return;
			}
			
			//re-uniqify file names here (if [notes count] > 1)?
			
			for (i=0; i<[notes count]; i++) {
				BOOL lastNote = i != [notes count] - 1;
				NoteObject *note = [notes objectAtIndex:i];
				
				OSStatus err = [note exportToDirectoryRef:&directoryRef withFilename:filename usingFormat:storageFormat overwrite:overwriteNotes];
				
				if (err == dupFNErr) {
					//ask about overwriting
					NSString *existingName = filename ?: note.filename;
					existingName = [[existingName stringByDeletingPathExtension] stringByAppendingPathExtension:[NotationPrefs pathExtensionForFormat:storageFormat]];
					result = NSRunAlertPanel([NSString stringWithFormat:NSLocalizedString(@"A file named quotemark%@quotemark already exists.",nil), existingName],
											 NSLocalizedString(@"Replace its current contents with that of the note?", @"replace the file's contents?"),
											 NSLocalizedString(@"Replace",nil), NSLocalizedString(@"Don't Replace",nil), lastNote ? NSLocalizedString(@"Replace All",nil) : nil, nil);
					if (result == NSAlertDefaultReturn || result == NSAlertOtherReturn) {
						if (result == NSAlertOtherReturn) overwriteNotes = YES;
						err = [note exportToDirectoryRef:&directoryRef withFilename:filename usingFormat:storageFormat overwrite:YES];
					} else continue;
				}
				
				if (err != noErr) {
					NSString *exportErrorTitleString = [NSString stringWithFormat:NSLocalizedString(@"The note quotemark%@quotemark couldn't be exported because %@.",nil), note.titleString, [NSString reasonStringFromCarbonFSError:err]];
					if (!lastNote) {
						NSRunAlertPanel(exportErrorTitleString, nil, NSLocalizedString(@"OK",nil), nil, nil, nil);
					} else {
						result = NSRunAlertPanel(exportErrorTitleString, NSLocalizedString(@"Continue exporting?", @"alert title for exporter interruption"),
												 NSLocalizedString(@"Continue", @"(exporting notes?)"), NSLocalizedString(@"Stop Exporting", @"(notes?)"), nil);
						if (result != NSAlertDefaultReturn) break;
					}
				}
			}
			
			FNNotify(&directoryRef, kFNDirectoryModifiedMessage, kFNNoImplicitAllSubscription);
			
		}
	};
	
	if (isOpen) {
		[openPanel setAccessoryView:accessoryView];
		[openPanel setCanCreateDirectories:YES];
		[openPanel setCanChooseFiles:NO];
		[openPanel setCanChooseDirectories:YES];
		[openPanel setPrompt:NSLocalizedString(@"Export",@"title of button to export notes from folder selection dialog")];
		[openPanel setTitle:NSLocalizedString(@"Export Notes", @"title of export notes dialog")];
		[openPanel setMessage:[NSString stringWithFormat:NSLocalizedString(@"Choose a folder into which %d notes will be exported",nil), [notes count]]];
		[openPanel beginSheetModalForWindow:window completionHandler:completion];
	} else {
		[savePanel setAccessoryView:accessoryView];
		[savePanel setCanCreateDirectories:YES];
		[savePanel setCanSelectHiddenExtension:YES];
		
		[self formatSelectorChanged:formatSelectorPopup];
		
		NSString *filename = [[notes lastObject] filename];
		filename = [filename stringByDeletingPathExtension];
		filename = [filename stringByAppendingPathExtension:[NotationPrefs pathExtensionForFormat:[[formatSelectorPopup selectedItem] tag]]];
		[savePanel setNameFieldStringValue:filename];
		
		[savePanel beginSheetModalForWindow:window completionHandler:completion];
	}
}

@end
