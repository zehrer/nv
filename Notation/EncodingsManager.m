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


#import "EncodingsManager.h"
#import "NoteObject.h"
#import "NotationFileManager.h"
#import "NSString_NV.h"
#import "NSDate+Notation.h"

@implementation EncodingsManager

static const NSStringEncoding AllowedEncodings[] = {
		/* Western */
		NSISOLatin1StringEncoding,            // ISO Latin 1
		(NSStringEncoding) 0x80000203,        // ISO Latin 3
		(NSStringEncoding) 0x8000020F,        // ISO Latin 9
		NSMacOSRomanStringEncoding,            // Mac
		NSWindowsCP1252StringEncoding,        // Windows
		/* Baltic */
		(NSStringEncoding) -1,
		(NSStringEncoding) 0x8000020D,        // ISO Latin 7
		(NSStringEncoding) 0x80000507,        // Windows
		/* Central European */
		(NSStringEncoding) -1,
		NSISOLatin2StringEncoding,            // ISO Latin 2
		(NSStringEncoding) 0x80000204,        // ISO Latin 4
		(NSStringEncoding) 0x8000001D,        // Mac
		NSWindowsCP1250StringEncoding,        // Windows
		/* Cyrillic */
		(NSStringEncoding) -1,
		(NSStringEncoding) 0x80000A02,        // KOI8-R
		(NSStringEncoding) 0x80000205,        // ISO Latin 5
		(NSStringEncoding) 0x80000007,        // Mac
		NSWindowsCP1251StringEncoding,        // Windows
		/* Japanese */
		(NSStringEncoding) -1,                // Divider
		(NSStringEncoding) 0x80000A01,        // ShiftJIS
		NSISO2022JPStringEncoding,            // ISO-2022-JP
		NSJapaneseEUCStringEncoding,        // EUC
		(NSStringEncoding) 0x80000001,        // Mac
		NSShiftJISStringEncoding,            // Windows
		/* Simplified Chinese */
		(NSStringEncoding) -1,                // Divider
		(NSStringEncoding) 0x80000632,        // GB 18030
		(NSStringEncoding) 0x80000631,        // GBK
		(NSStringEncoding) 0x80000930,        // EUC
		(NSStringEncoding) 0x80000019,        // Mac
		(NSStringEncoding) 0x80000421,        // Windows
		/* Traditional Chinese */
		(NSStringEncoding) -1,                // Divider
		(NSStringEncoding) 0x80000A03,        // Big5
		(NSStringEncoding) 0x80000A06,        // Big5 HKSCS
		(NSStringEncoding) 0x80000931,        // EUC
		(NSStringEncoding) 0x80000002,        // Mac
		(NSStringEncoding) 0x80000423,        // Windows
		/* Korean */
		(NSStringEncoding) -1,                // Divider
		(NSStringEncoding) 0x80000940,        // EUC
		(NSStringEncoding) 0x80000003,        // Mac
		(NSStringEncoding) 0x80000422,        // Windows
		/* Hebrew */
		(NSStringEncoding) -1,                // Divider
		(NSStringEncoding) 0x80000208,        // ISO-8859-8
		(NSStringEncoding) 0x80000005,        // Mac
		(NSStringEncoding) 0x80000505,        // Windows
		/* End */ 0};


+ (EncodingsManager *)sharedManager {
	static dispatch_once_t onceToken;
	static EncodingsManager *sharedManager = nil;
	dispatch_once(&onceToken, ^{
		sharedManager = [[EncodingsManager alloc] init];
	});
	return sharedManager;
}

- (BOOL)checkUnicode {

	if (NSUnicodeStringEncoding == currentEncoding || NSUTF8StringEncoding == currentEncoding) {

		NSString *alertTitleString = NSLocalizedString(@"quotemark%@quotemark is a Unicode file and not directly interpretable using plain text encodings.",
		@"alert title when converting from unicode");
		if (NSRunAlertPanel([NSString stringWithFormat:alertTitleString, note.filename],
				NSLocalizedString(@"If you wish to convert it, you must open and re-save the file in an external editor.", "alert description when converting from unicode"),
				NSLocalizedString(@"OK", nil), NSLocalizedString(@"Open in TextEdit", @"title of button for opening the current note in text edit"), NULL) != NSAlertDefaultReturn) {
			NSURL *resolvedURL = note.noteFileURL;
			if (![resolvedURL checkResourceIsReachableAndReturnError: NULL]) {
				NSRunAlertPanel(NSLocalizedString(@"Could not locate the note file.", nil), NSLocalizedString(@"Does it still exist?", nil),
								NSLocalizedString(@"I'll Go See", @"... if it exists"), NULL, NULL);
			} else {
				[[NSWorkspace sharedWorkspace] openURLs: @[resolvedURL] withAppBundleIdentifier: @"com.apple.TextEdit" options: NSWorkspaceLaunchDefault additionalEventParamDescriptor: NULL launchIdentifiers: NULL];
			}
		}

		return YES;
	}

	return NO;
}

- (void)showPanelForNote:(NoteObject *)aNote {
	currentEncoding = aNote.fileEncoding;

	note = aNote;

	_URL = nil;

	id <NoteObjectDelegate, NTNFileManager> localNoteDelegate = note.delegate;
	NSURL *newURL = nil;
	if (!(noteData = [localNoteDelegate dataForFilenameInNotesDirectory: note.filename URL: &newURL])) {
		NSRunAlertPanel([NSString stringWithFormat:NSLocalizedString(@"Error: unable to read the contents of the file quotemark%@.quotemark", nil), aNote.filename],
				NSLocalizedString(@"The file may no longer exist or has incorrect permissions.", nil), NSLocalizedString(@"OK", nil), NULL, NULL);
		return;
	} else {
		_URL = newURL;
	}

	if (![self checkUnicode]) {

		if (!window) {
			if (![NSBundle loadNibNamed:@"EncodingsManager" owner:self]) {
				NSLog(@"Failed to load EncodingsManager.nib");
				NSBeep();
				return;
			}
		}

		[helpStringField setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Notational Velocity should assume the file quotemark%@quotemark was saved with the encoding:", nil), note.filename]];
		[encodingsPopUpButton setMenu:[self textConversionsMenu]];

		//setup panel for given note
		if ([self tryToUpdateTextForEncoding:currentEncoding]) {
			[NSApp rbl_beginSheet:window modalForWindow:[[NSApp delegate] window] completionHandler:^(NSInteger returnCode) {
				note = nil;
			}];
		} else {
			//this shouldn't happen
		}
	}
}


- (NSMenu *)textConversionsMenu {
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@""];
	NSMenuItem *menuItem = nil;
	unsigned int i = 0;

	for (i = 0; AllowedEncodings[i]; i++) {
		NSStringEncoding thisEncoding = AllowedEncodings[i];

		if (thisEncoding == (NSStringEncoding) -1) {
			[menu addItem:[NSMenuItem separatorItem]];
			continue;
		}

		menuItem = [[NSMenuItem alloc] initWithTitle:[NSString localizedNameOfStringEncoding:thisEncoding]
											  action:@selector(setFileEncodingFromMenu:) keyEquivalent:@""];
		if (currentEncoding == thisEncoding)
			[menuItem setState:NSOnState];

		NSString *noteString = (__bridge_transfer NSString *)CFStringCreateFromExternalRepresentation(NULL, (__bridge CFDataRef) noteData,
				CFStringConvertNSStringEncodingToEncoding(thisEncoding));
		//make sure that the conversion works both ways
		[menuItem setEnabled:(noteString != nil && [noteString canBeConvertedToEncoding:thisEncoding])];

		[menuItem setTag:(int) thisEncoding];
		[menuItem setTarget:self];
		[menu addItem:menuItem];
	}

	[menu setAutoenablesItems:NO];

	return menu;
}


- (void)setFileEncodingFromMenu:(id)sender {
	if ([sender isKindOfClass:[NSMenuItem class]]) {

		NSStringEncoding newEncoding = [sender tag];

		//preview conversion in text view
		if (![self tryToUpdateTextForEncoding:newEncoding]) {

			//set it back to the current encoding--this one doesn't work
			[encodingsPopUpButton selectItemWithTag:(int) currentEncoding];
		}
	} else {
		NSLog(@"Unknown class sent msg to change encoding: %@", [sender description]);
	}
}

- (BOOL)tryToUpdateTextForEncoding:(NSStringEncoding)encoding {

	NSString *stringFromData = (__bridge_transfer NSString *)CFStringCreateFromExternalRepresentation(NULL, (__bridge CFDataRef) noteData, CFStringConvertNSStringEncodingToEncoding(encoding));

	if (stringFromData) {
		NSAttributedString *attributedStringFromData = [[NSAttributedString alloc] initWithString:stringFromData];
		NSTextStorage *storage = [textView textStorage];
		[storage setAttributedString:attributedStringFromData];


		currentEncoding = encoding;

		[encodingsPopUpButton selectItemWithTag:(int) currentEncoding];

		return YES;
	} else {
		NSRunAlertPanel([NSString stringWithFormat:@"%@ is not a valid encoding for this text file.",
												   [NSString localizedNameOfStringEncoding:encoding]], NSLocalizedString(@"Please try another encoding.", @"prompt for choosing an incompatible text encoding"),
				NSLocalizedString(@"OK", nil), NULL, NULL);
	}


	return NO;
}

- (IBAction)cancelAction:(id)sender {
	[NSApp endSheet:window returnCode:0];
	[window close];
}

- (IBAction)chooseEncoding:(id)sender {
}

- (BOOL)shouldUpdateNoteFromDisk {

	NSDate *diskModification = nil;
	NSError *error = nil;
	if (![note.noteFileURL getResourceValue: &diskModification forKey: NSURLContentModificationDateKey error: &error]) {
		NSRunAlertPanel(error.description, error.localizedFailureReason, NSLocalizedString(@"OK", nil), nil, nil);
		return NO;
	}

	NSDate *noteModification = note.contentModificationDate;
	if ([noteModification isGreaterThan: diskModification]) {
		NSInteger result = NSRunCriticalAlertPanel([NSString stringWithFormat:NSLocalizedString(@"The note quotemark%@quotemark is newer than its file on disk.", nil), note.title],
												   NSLocalizedString(@"If you update this note with re-interpreted data from the file, you may overwrite your changes.", nil),
												   NSLocalizedString(@"Don't Update", @"don't update the note from its file on disk"),
												   NSLocalizedString(@"Overwrite Note", @"...from file on disk"), NULL);
		if (result == NSAlertDefaultReturn) {
			NSLog(@"not updating");
			return NO;
		} else {
			NSLog(@"user wants to update");
		}
	}

	return YES;
}

- (IBAction)okAction:(id)sender {

	//check whether file mod. date of note is older than mod. date on disk
	if ([self shouldUpdateNoteFromDisk]) {
		[note setFileEncodingAndReinterpret:currentEncoding];
		[[NSApp delegate] contentsUpdatedForNote:note];
	}

	[NSApp endSheet:window returnCode:1];
	[window close];
}

@end
