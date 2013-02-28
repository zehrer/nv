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
//ET NV4

#import "AppController.h"
#import "GlobalPrefs.h"
#import "AppController_Importing.h"
#import "PrefsWindowController.h"
#import "NoteAttributeColumn.h"
#import "NotationSyncServiceManager.h"
#import "NotationDirectoryManager.h"
#import "NSString_NV.h"
#import "EncodingsManager.h"
#import "ExporterManager.h"
#import "ExternalEditorListController.h"
#import "LinkingEditor.h"
#import "EmptyView.h"
#import "DualField.h"
#import "TitlebarButton.h"
#import "SyncSessionController.h"
#import "MultiplePageView.h"
#import "InvocationRecorder.h"
#import "LinearDividerShader.h"
#import "SecureTextEntryManager.h"
#import "TagEditingManager.h"
#import "NotesTableHeaderCell.h"
#import "DFView.h"
#import "StatusItemView.h"
#import "PreviewController.h"
#import "ETClipView.h"
#import "WordCountToken.h"
#import <objc/message.h>
#import "NSString_CustomTruncation.h"
#import "NSError+Notation.h"
#import "NTNMainWindowController.h"
#import "NotationFileManager.h"

int ModFlagger;
int popped;
BOOL splitViewAwoke;
BOOL isEd;

static const CGFloat kMinNotesListDimension = 100.0f;
static const CGFloat kMinEditorDimension = 200.0f;
static const CGFloat kMaxNotesListDimension = 600.0f;

@interface NSObject ()

- (void)_removeLinkFromMenu:(NSMenu *)menu;

@end

@interface AppController () <GlobalPrefsResponder>

@end

@implementation AppController

@synthesize currentNote = currentNote;

- (id)init {
	if ((self = [super init])) {
		splitViewAwoke = NO;
		windowUndoManager = [[NSUndoManager alloc] init];

		previewController = [[PreviewController alloc] init];

		NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
		[nc addObserver:previewController selector:@selector(requestPreviewUpdate:) name:@"TextView has changed contents" object:self];
		[nc addObserver:self selector:@selector(toggleAttachedWindow:) name:@"NVShouldActivate" object:nil];
		[nc addObserver:self selector:@selector(toggleAttachedMenu:) name:@"StatusItemMenuShouldDrop" object:nil];
		[nc addObserver:self selector:@selector(togDockIcon:) name:@"AppShouldToggleDockIcon" object:nil];
		[nc addObserver:self selector:@selector(resetModTimers:) name:@"ModTimersShouldReset" object:nil];

		// Setup URL Handling
		NSAppleEventManager *appleEventManager = [NSAppleEventManager sharedAppleEventManager];
		[appleEventManager setEventHandler:self andSelector:@selector(handleGetURLEvent:withReplyEvent:) forEventClass:kInternetEventClass andEventID:kAEGetURL];

		dividerShader = [[LinearDividerShader alloc] initWithBaseColors:self];
		isCreatingANote = isFilteringFromTyping = typedStringIsCached = NO;
		typedString = @"";
	}
	return self;
}

- (void)awakeFromNib {
	theFieldEditor = [[NSTextView alloc] initWithFrame:[window frame]];
	[theFieldEditor setFieldEditor:YES];
	[self updateFieldAttributes];

	nsSplitView.nextKeyView = notesTableView;

	ETClipView *newClipView = [[ETClipView alloc] initWithFrame:[[textScrollView contentView] frame]];
	[newClipView setDrawsBackground:NO];
	[textScrollView setContentView:(ETClipView *) newClipView];
	[textScrollView setDocumentView:textView];
	[notesScrollView setTranslatesAutoresizingMaskIntoConstraints:NO];

	[nsSplitView adjustSubviews];
	[nsSplitView needsDisplay];
	[mainView setNeedsDisplay:YES];
	splitViewAwoke = YES;

	[notesScrollView setBorderType:NSNoBorder];
	[textScrollView setBorderType:NSNoBorder];
	prefsController = [GlobalPrefs defaultPrefs];
	[NSColor setIgnoresAlpha:NO];

	//For ElasticThreads' fullscreen implementation.
	[self setDualFieldInToolbar];
	[notesTableView setDelegate:self];
	[field setDelegate:self];
	[textView setDelegate:self];

	// Create elasticthreads' NSStatusItem.
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"StatusBarItem"]) {
		float width = 25.0f;
		CGFloat height = [[NSStatusBar systemStatusBar] thickness];
		NSRect viewFrame = NSMakeRect(0.0f, 0.0f, width, height);
		statusItem = [[NSStatusBar systemStatusBar] statusItemWithLength:width];
		cView = [[StatusItemView alloc] initWithFrame:viewFrame];
		[statusItem setView:cView];
	}

	currentPreviewMode = [[NSUserDefaults standardUserDefaults] integerForKey:@"markupPreviewMode"];
	if (currentPreviewMode == MarkdownPreview) {
		[multiMarkdownPreview setState:NSOnState];
	} else if (currentPreviewMode == MultiMarkdownPreview) {
		[multiMarkdownPreview setState:NSOnState];
	} else if (currentPreviewMode == TextilePreview) {
		[textilePreview setState:NSOnState];
	}

	[NSApp setServicesProvider:self];
	outletObjectAwoke(self);
}

//really need make AppController a subclass of NSWindowController and stick this junk in windowDidLoad
- (void)setupViewsAfterAppAwakened {
	static BOOL awakenedViews = NO;
	isEd = NO;
	if (!awakenedViews) {
		//NSLog(@"all (hopefully relevant) views awakend!");
		[self _configureDividerForCurrentLayout];

		CGFloat dim = nsSplitView.isVertical ? notesScrollView.frame.size.height : notesScrollView.frame.size.width;
		CGFloat newDim = dim;

		if (dim < 200.0) {
			if (([nsSplitView frame].size.height < 600.0) && ([nsSplitView frame].size.height - 400 > dim)) {
				newDim = [nsSplitView frame].size.height - 450.0;
			} else if ([nsSplitView frame].size.height >= 600.0) {
				newDim = 150.0;
			}
		}

		if (newDim != dim) {
			[nsSplitView setPosition:newDim ofDividerAtIndex:0];
		}

		[textScrollView addSubview:editorStatusView positioned:NSWindowAbove relativeTo:textScrollView];
		[editorStatusView setFrame:[textScrollView frame]];

		[nsSplitView adjustSubviews];
		[notesTableView restoreColumns];

		[field setNextKeyView:textView];
		[textView setNextKeyView:field];
		[window setAutorecalculatesKeyViewLoop:NO];

		[self updateRTL];


		[self setEmptyViewState:YES];
		ModFlagger = 0;
		popped = 0;
		userScheme = [[NSUserDefaults standardUserDefaults] integerForKey:@"ColorScheme"];
		if (userScheme == 0) {
			[self setBWColorScheme:self];
		} else if (userScheme == 1) {
			[self setLCColorScheme:self];
		} else if (userScheme == 2) {
			[self setUserColorScheme:self];
		}

		if (![NSApp isActive]) {
			[NSApp activateIgnoringOtherApps:YES];
		}
		awakenedViews = YES;
	}
}

//what a hack
void outletObjectAwoke(id sender) {
	static NSMutableSet *awokenOutlets = nil;
	if (!awokenOutlets) awokenOutlets = [[NSMutableSet alloc] initWithCapacity:5];

	[awokenOutlets addObject:sender];

	AppController *appDelegate = (AppController *) [NSApp delegate];

	if ((appDelegate) && ([awokenOutlets containsObject:appDelegate] &&
			[awokenOutlets containsObject:appDelegate->notesTableView] &&
			[awokenOutlets containsObject:appDelegate->textView] &&
			[awokenOutlets containsObject:appDelegate->editorStatusView]) && (splitViewAwoke)) {
		// && [awokenOutlets containsObject:appDelegate->splitView])
		[appDelegate setupViewsAfterAppAwakened];
	}
}


- (void)applicationDidFinishLaunching:(NSNotification *)aNote {
	self.viewController = [NTNMainWindowController new];
	[self.viewController showWindow: self];

	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"ShowDockIcon"]) {
		[[NSApplication sharedApplication] setActivationPolicy:NSApplicationActivationPolicyRegular];
	}

	//on tiger dualfield is often not ready to add tracking tracks until this point:

	[field setTrackingRect];
	NSDate *before = [NSDate date];
	prefsWindowController = [[PrefsWindowController alloc] init];

	NSError *nsErr = nil;
	NotationController *newNotation = nil;
	NSData *bookmarkData = [prefsController bookmarkDataForDefaultDirectory];

	NSString *subMessage = @"";

	BOOL showError = YES;
	NSString *location = nil;

	//if the option key is depressed, go straight to picking a new notes folder location
	if (kCGEventFlagMaskAlternate == (CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState) & NSDeviceIndependentModifierFlagsMask)) {
		showError = NO;
	} else {
		if (bookmarkData) {
			newNotation = [[NotationController alloc] initWithBookmarkData: bookmarkData error: &nsErr];
			subMessage = NSLocalizedString(@"Please choose a different folder in which to store your notes.", nil);
		} else {
			newNotation = [[NotationController alloc] initWithDefaultDirectoryWithError: &nsErr];
			subMessage = NSLocalizedString(@"Please choose a folder in which your notes will be stored.", nil);
		}

		//no need to display an alert if the error wasn't real
		if (nsErr.code == NTNPasswordEntryCanceledError) {
			showError = NO;
		} else {
			location = bookmarkData ? newNotation.noteDirectoryURL.path : NSLocalizedString(@"your Application Support directory", nil);
		}
	}

	NSURL *newURL = nil;

	while (!newNotation) {
		if (location && !newURL) newURL = [NSURL fileURLWithPath: location];

		BOOL result = YES;
		if (showError) {
			NSString *reason = [NSString reasonStringFromCarbonFSError: (int)nsErr.code];
			result = (NSRunAlertPanel([NSString stringWithFormat:NSLocalizedString(@"Unable to initialize notes database in \n%@ because %@.", nil), newURL, reason], subMessage, NSLocalizedString(@"Choose another folder", nil), NSLocalizedString(@"Quit", nil), NULL) == NSAlertDefaultReturn);
		}

		if (result) {
			//show nsopenpanel, defaulting to current default notes dir
			if (!(newURL = [prefsWindowController getNewNotesURLFromOpenPanel])) {
				//they cancelled the open panel, or it was unable to get the URL of the file
				[NSApp terminate:self];
				return;
			} else if ((newNotation = [[NotationController alloc] initWithDirectory: newURL error:&nsErr])) {
				//have to make sure bookmark data is saved from setNotationController
				newNotation.bookmarkNeedsUpdating = YES;
				break;
			}
		} else {
			[NSApp terminate:self];
			return;
		}
	}

	[self setNotationController:newNotation];

	NSLog(@"load time: %g, ", [[NSDate date] timeIntervalSinceDate:before]);
	//	NSLog(@"version: %s", PRODUCT_NAME);

	//import old database(s) here if necessary
	[AlienNoteImporter importBlorOrHelpFilesIfNecessaryIntoNotation:newNotation];

	if (pathsToOpenOnLaunch) {
		[notationController openFiles:pathsToOpenOnLaunch];//autorelease
		pathsToOpenOnLaunch = nil;
	}

	if (URLToInterpretOnLaunch) {
		[self interpretNVURL:URLToInterpretOnLaunch];
		URLToInterpretOnLaunch = nil;
	}

	//tell us..
	[prefsController registerWithTarget:self forChangesInSettings:
			@selector(setBookmarkDataForDefaultDirectory:sender:),  //when someone wants to load a new database
			@selector(setSortedTableColumnKey:reversed:sender:),  //when sorting prefs changed
			@selector(setNoteBodyFont:sender:),  //when to tell notationcontroller to restyle its notes
			@selector(setForegroundTextColor:sender:),  //ditto
			@selector(setBackgroundTextColor:sender:),  //ditto
			@selector(setTableFontSize:sender:),  //when to tell notationcontroller to regenerate the (now potentially too-short) note-body previews
			@selector(addTableColumn:sender:),  //ditto
			@selector(removeTableColumn:sender:),  //ditto
			@selector(setTableColumnsShowPreview:sender:),  //when to tell notationcontroller to generate or disable note-body previews
			@selector(setConfirmNoteDeletion:sender:),  //whether "delete note" should have an ellipsis
			@selector(setAutoCompleteSearches:sender:), nil];   //when to tell notationcontroller to build its title-prefix connections

	// Delay to the next runloop
	dispatch_async(dispatch_get_main_queue(), ^{
		[[prefsController bookmarksController] setDelegate:self];
		[[prefsController bookmarksController] restoreWindowFromSave];
		[[prefsController bookmarksController] updateBookmarksUI];
		[self updateNoteMenus];
		[textView setupFontMenu];
		[prefsController registerAppActivationKeystrokeWithHandler:^{
			[self toggleNVActivation];
		}];
		[notationController updateLabelConnectionsAfterDecoding];
		[notationController checkIfNotationIsTrashed];
		[[SecureTextEntryManager sharedInstance] checkForIncompatibleApps];

		//connect sparkle programmatically to avoid loading its framework at nib awake;

		if (!NSClassFromString(@"SUUpdater")) {
			NSString *frameworkPath = [[[NSBundle bundleForClass:[self class]] privateFrameworksPath] stringByAppendingPathComponent:@"Sparkle.framework"];
			if ([[NSBundle bundleWithPath:frameworkPath] load]) {
				id updater = objc_msgSend(NSClassFromString(@"SUUpdater"), NSSelectorFromString(@"sharedUpdater"));
				[sparkleUpdateItem setTarget:updater];
				[sparkleUpdateItem setAction:NSSelectorFromString(@"checkForUpdates:")];
				NSMenuItem *siSparkle = [statBarMenu itemWithTag:902];
				[siSparkle setTarget:updater];
				[siSparkle setAction:NSSelectorFromString(@"checkForUpdates:")];
				if (![[prefsController notationPrefs] firstTimeUsed]) {
					//don't do anything automatically on the first launch; afterwards, check every 4 days, as specified in Info.plist
					objc_msgSend(updater, NSSelectorFromString(@"setAutomaticallyChecksForUpdates:"), YES);
				}
			} else {
				NSLog(@"Could not load %@!", frameworkPath);
			}
		}

		[fsMenuItem setEnabled:YES];
		[fsMenuItem setHidden:NO];

		[window setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];
		[NSApp setPresentationOptions:NSApplicationPresentationFullScreen];

		[statBarMenu insertItem: [fsMenuItem copy] atIndex:12];

		if (![prefsController showWordCount]) {
			[wordCounter setHidden:NO];
		} else {
			[wordCounter setHidden:YES];
		}
	});
}

- (void)handleGetURLEvent:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent {

	NSURL *fullURL = [NSURL URLWithString:[[event paramDescriptorForKeyword:keyDirectObject] stringValue]];

	if (notationController) {
		if (![self interpretNVURL:fullURL])
			NSBeep();
	} else {
		URLToInterpretOnLaunch = fullURL;
	}
}

- (void)setNotationController:(NotationController *)newNotation {

	if (newNotation) {
		if (notationController) {
			[notationController stopSyncServices];
			[[NSNotificationCenter defaultCenter] removeObserver:self name:SyncSessionsChangedVisibleStatusNotification
														  object:[notationController syncSessionController]];
			[notationController stopFileNotifications];
			if ([notationController flushAllNoteChanges])
				[notationController closeJournal];
		}

		NotationController *oldNotation = notationController;
		notationController = newNotation;

		if (oldNotation) {
			[notesTableView abortEditing];
			[prefsController setLastSearchString:[self fieldSearchString] selectedNote:currentNote
						scrollOffsetForTableView:notesTableView sender:self];
			//if we already had a notation, appController should already be bookmarksController's delegate
			[[prefsController bookmarksController] performSelector:@selector(updateBookmarksUI) withObject:nil afterDelay:0.0];
		}
		[notationController setSortColumn:[notesTableView noteAttributeColumnForIdentifier:[prefsController sortedTableColumnKey]]];
		[notesTableView setDataSource:notationController];
		[notesTableView setLabelsListSource:notationController];
		[notationController setDelegate:self];

		//allow resolution of UUIDs to NoteObjects from saved searches
		[[prefsController bookmarksController] setDataSource:notationController];

		//update the list using the new notation and saved settings
		[self restoreListStateUsingPreferences];

		//window's undomanager could be referencing actions from the old notation object
		[[window undoManager] removeAllActions];
		[notationController setUndoManager:[window undoManager]];

		if ([notationController bookmarkNeedsUpdating]) {
			[prefsController setBookmarkDataForDefaultDirectory: [notationController bookmarkDataForNoteDirectory] sender: self];
		}
		if ([prefsController tableColumnsShowPreview] || [prefsController horizontalLayout]) {
			[self _forceRegeneratePreviewsForTitleColumn];
			[notesTableView setNeedsDisplay:YES];
		}
		[titleBarButton setMenu:[[notationController syncSessionController] syncStatusMenu]];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(syncSessionsChangedVisibleStatus:)
													 name:SyncSessionsChangedVisibleStatusNotification
												   object:[notationController syncSessionController]];
		[notationController performSelector:@selector(startSyncServices) withObject:nil afterDelay:0.0];

		if ([[notationController notationPrefs] secureTextEntry]) {
			[[SecureTextEntryManager sharedInstance] enableSecureTextEntry];
		} else {
			[[SecureTextEntryManager sharedInstance] disableSecureTextEntry];
		}

		[field selectText:nil];

	}
}

- (BOOL)applicationOpenUntitledFile:(NSApplication *)sender {
	if (![prefsController quitWhenClosingWindow]) {
		[self bringFocusToControlField:nil];
		return YES;
	}

	return NO;
}

- (NSToolbarItem *)toolbar:(NSToolbar *)theToolbar itemForItemIdentifier:(NSString *)itemIdentifier willBeInsertedIntoToolbar:(BOOL)flag {
	return [itemIdentifier isEqualToString:@"DualField"] ? dualFieldItem : nil;
}

- (NSArray *)toolbarAllowedItemIdentifiers:(NSToolbar *)theToolbar {
	return [self toolbarDefaultItemIdentifiers:theToolbar];
}

- (NSArray *)toolbarDefaultItemIdentifiers:(NSToolbar *)theToolbar {
	return @[@"DualField"];
}


- (BOOL)validateMenuItem:(NSMenuItem *)menuItem {
	SEL selector = [menuItem action];
	NSInteger numberSelected = [notesTableView numberOfSelectedRows];
	NSInteger tag = [menuItem tag];

	if ((tag == TextilePreview) || (tag == MarkdownPreview) || (tag == MultiMarkdownPreview)) {
		// Allow only one Preview mode to be selected at every one time
		[menuItem setState:((tag == currentPreviewMode) ? NSOnState : NSOffState)];
		return YES;
	} else if (selector == @selector(printNote:) ||
			selector == @selector(deleteNote:) ||
			selector == @selector(exportNote:) ||
			selector == @selector(tagNote:)) {

		return (numberSelected > 0);

	} else if (selector == @selector(renameNote:) ||
			selector == @selector(copyNoteLink:)) {

		return (numberSelected == 1);

	} else if (selector == @selector(revealNote:)) {

		return (numberSelected == 1) && [notationController currentNoteStorageFormat] != SingleDatabaseFormat;

	} else if (selector == @selector(toggleCollapse:)) {


		if ([nsSplitView isSubviewCollapsed:notesScrollView]) {
			[menuItem setTitle:NSLocalizedString(@"Expand Notes List", @"menu item title for expanding notes list")];
		} else {

			[menuItem setTitle:NSLocalizedString(@"Collapse Notes List", @"menu item title for collapsing notes list")];

			if (!currentNote) {
				return NO;
			}
		}
	} else if ((selector == @selector(toggleFullScreen:)) || (selector == @selector(switchFullScreen:))) {

		if ([NSApp presentationOptions] > 0) {
			[menuItem setTitle:NSLocalizedString(@"Exit Full Screen", @"menu item title for exiting fullscreen")];
		} else {

			[menuItem setTitle:NSLocalizedString(@"Enter Full Screen", @"menu item title for entering fullscreen")];

		}

	} else if (selector == @selector(fixFileEncoding:)) {

		return (currentNote != nil && currentNote.storageFormat == PlainTextFormat && ![currentNote contentsWere7Bit]);
	} else if (selector == @selector(editNoteExternally:)) {
		return (numberSelected > 0) && [[menuItem representedObject] canEditAllNotes:[notationController notesAtIndexes:[notesTableView selectedRowIndexes]]];
	}
	return YES;
}

- (void)updateNoteMenus {
	NSMenu *notesMenu = [[[NSApp mainMenu] itemWithTag:NOTES_MENU_ID] submenu];

	NSInteger menuIndex = [notesMenu indexOfItemWithTarget:self andAction:@selector(deleteNote:)];
	NSMenuItem *deleteItem = nil;
	if (menuIndex > -1 && (deleteItem = [notesMenu itemAtIndex:menuIndex])) {
		NSString *trailingQualifier = [prefsController confirmNoteDeletion] ? NSLocalizedString(@"...", @"ellipsis character") : @"";
		[deleteItem setTitle:[NSString stringWithFormat:@"%@%@",
														NSLocalizedString(@"Delete", nil), trailingQualifier]];
	}

	[notesMenu setSubmenu:[[ExternalEditorListController sharedInstance] addEditNotesMenu] forItem:[notesMenu itemWithTag:88]];
	NSMenu *viewMenu = [[[NSApp mainMenu] itemWithTag:VIEW_MENU_ID] submenu];

	menuIndex = [viewMenu indexOfItemWithTarget:notesTableView andAction:@selector(toggleNoteBodyPreviews:)];
	NSMenuItem *bodyPreviewItem = nil;
	if (menuIndex > -1 && (bodyPreviewItem = [viewMenu itemAtIndex:menuIndex])) {
		[bodyPreviewItem setTitle:[prefsController tableColumnsShowPreview] ?
				NSLocalizedString(@"Hide Note Previews in Title", @"menu item in the View menu to turn off note-body previews in the Title column") :
				NSLocalizedString(@"Show Note Previews in Title", @"menu item in the View menu to turn on note-body previews in the Title column")];
	}
	menuIndex = [viewMenu indexOfItemWithTarget:self andAction:@selector(switchViewLayout:)];
	NSMenuItem *switchLayoutItem = nil;
	NSString *switchStr = [prefsController horizontalLayout] ?
			NSLocalizedString(@"Switch to Vertical Layout", @"title of alternate view layout menu item") :
			NSLocalizedString(@"Switch to Horizontal Layout", @"title of view layout menu item");

	if (menuIndex > -1 && (switchLayoutItem = [viewMenu itemAtIndex:menuIndex])) {
		[switchLayoutItem setTitle:switchStr];
	}
	// add to elasticthreads' statusbar menu
	menuIndex = [statBarMenu indexOfItemWithTarget:self andAction:@selector(switchViewLayout:)];
	if (menuIndex > -1) {
		NSMenuItem *anxItem = [statBarMenu itemAtIndex:menuIndex];
		[anxItem setTitle:switchStr];
	}
}

- (void)_forceRegeneratePreviewsForTitleColumn {
	[notationController regeneratePreviewsForColumn:[notesTableView noteAttributeColumnForIdentifier:NoteTitleColumnString]
								visibleFilteredRows:[notesTableView rowsInRect:[notesTableView visibleRect]] forceUpdate:YES];

}

- (void)_configureDividerForCurrentLayout {
	isEd = NO;
	BOOL horiz = [prefsController horizontalLayout];

	if ([nsSplitView isSubviewCollapsed:notesScrollView]) {
		[notesScrollView setHidden:NO];
		[nsSplitView adjustSubviews];
		[nsSplitView setVertical:horiz];
		[notesScrollView setHidden:YES];
	} else {
		[nsSplitView setVertical:horiz];
		if (![self dualFieldIsVisible]) {
			[self setDualFieldIsVisible:YES];
		}
	}

	[nsSplitView adjustSubviews];
}

- (IBAction)switchViewLayout:(id)sender {
	if ([mainView isInFullScreenMode]) {
		wasVert = YES;
	}
	NVViewLocationContext *ctx = [notesTableView viewingLocation];
	ctx.pivotRowWasEdge = NO;

	CGFloat colW = notesScrollView.frame.size.width;
	if (![nsSplitView isVertical]) {
		colW += 30.0f;
	} else {
		colW -= 30.0f;
	}

	[prefsController setHorizontalLayout:![prefsController horizontalLayout] sender:self];
	[notationController updateDateStringsIfNecessary];
	[self _configureDividerForCurrentLayout];
	[nsSplitView setPosition:colW ofDividerAtIndex:0];
	[notationController regenerateAllPreviews];
	[nsSplitView adjustSubviews];

	[notesTableView setViewingLocation:ctx];
	[notesTableView makeFirstPreviouslyVisibleRowVisibleIfNecessary];

	[self updateNoteMenus];

	[notesTableView setBackgroundColor:backgrndColor];
	[notesTableView setNeedsDisplay];
}

- (void)createFromSelection:(NSPasteboard *)pboard userData:(NSString *)userData error:(NSString **)error {
	if (!notationController || ![self addNotesFromPasteboard:pboard]) {
		*error = NSLocalizedString(@"Error: Couldn't create a note from the selection.", @"error message to set during a Service call when adding a note failed");
	}
}


- (IBAction)renameNote:(id)sender {
	if ([nsSplitView isSubviewCollapsed:notesScrollView]) {
		[self toggleCollapse:sender];
	}
	//edit the first selected note
	isEd = YES;

	[notesTableView editRowAtColumnWithIdentifier:NoteTitleColumnString];
}

- (void)deleteAlertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo {

	id retainedDeleteObj = (__bridge id) contextInfo;

	if (returnCode == NSAlertDefaultReturn) {
		//delete! nil-msgsnd-checking

		//ensure that there are no pending edits in the tableview,
		//lest editing end with the same field editor and a different selected note
		//resulting in the renaming of notes in adjacent rows
		[notesTableView abortEditing];

		if ([retainedDeleteObj isKindOfClass:[NSArray class]]) {
			[notationController removeNotes:retainedDeleteObj];
		} else if ([retainedDeleteObj isKindOfClass:[NoteObject class]]) {
			[notationController removeNote:retainedDeleteObj];
		}

		if ([[alert suppressionButton] state] == NSOnState) {
			[prefsController setConfirmNoteDeletion:NO sender:self];
		}
	}
}


- (IBAction)deleteNote:(id)sender {

	NSIndexSet *indexes = [notesTableView selectedRowIndexes];
	if ([indexes count] > 0) {
		id deleteObj = [indexes count] > 1 ? (id) ([notationController notesAtIndexes:indexes]) : (id) ([notationController noteObjectAtFilteredIndex:[indexes firstIndex]]);

		if ([prefsController confirmNoteDeletion]) {
			NSString *warnString = currentNote ? [NSString stringWithFormat: NSLocalizedString(@"Delete the note titled quotemark%@quotemark?", @"alert title when asked to delete a note"), currentNote.title] :
					[NSString stringWithFormat: NSLocalizedString(@"Delete %d notes?", @"alert title when asked to delete multiple notes"), [indexes count]];

			NSAlert *alert = [NSAlert alertWithMessageText:warnString defaultButton:NSLocalizedString(@"Delete", @"name of delete button") alternateButton:NSLocalizedString(@"Cancel", @"name of cancel button") otherButton:nil informativeTextWithFormat:NSLocalizedString(@"Press Command-Z to undo this action later.", @"informational delete-this-note? text")];
			[alert setShowsSuppressionButton:YES];

			[alert beginSheetModalForWindow:window modalDelegate:self didEndSelector:@selector(deleteAlertDidEnd:returnCode:contextInfo:) contextInfo:(__bridge void *) deleteObj];
		} else {
			//just delete the notes outright
			SEL cmd = [indexes count] > 1 ? @selector(removeNotes:) : @selector(removeNote:);
			objc_msgSend(notationController, cmd, deleteObj);
		}
	}
}

- (IBAction)copyNoteLink:(id)sender {
	NSIndexSet *indexes = [notesTableView selectedRowIndexes];

	if ([indexes count] == 1) {
		[[[[[notationController notesAtIndexes:indexes] lastObject]
				uniqueNoteLink] absoluteString] copyItemToPasteboard:nil];
	}
}

- (IBAction)exportNote:(id)sender {
	NSIndexSet *indexes = [notesTableView selectedRowIndexes];

	NSArray *notes = [notationController notesAtIndexes:indexes];

	[notationController synchronizeNoteChanges:nil];
	[[ExporterManager sharedManager] exportNotes:notes forWindow:window];
}

- (IBAction)revealNote:(id)sender {
	NSIndexSet *indexes = [notesTableView selectedRowIndexes];
	NSURL *URL = nil;
	if ([indexes count] != 1 || !(URL = [[notationController noteObjectAtFilteredIndex:[indexes lastIndex]] noteFileURL])) {
		NSBeep();
		return;
	}
	[[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs: @[URL]];
}

- (IBAction)editNoteExternally:(id)sender {
	ExternalEditor *ed = [sender representedObject];
	if ([ed isKindOfClass:[ExternalEditor class]]) {
		NSIndexSet *indexes = [notesTableView selectedRowIndexes];
		if (kCGEventFlagMaskAlternate == (CGEventSourceFlagsState(kCGEventSourceStateCombinedSessionState) & NSDeviceIndependentModifierFlagsMask)) {
			//allow changing the default editor directly from Notes menu
			[[ExternalEditorListController sharedInstance] setDefaultEditor:ed];
		}
		//force-write any queued changes to disk in case notes are being stored as separate files which might be opened directly by the method below
		[notationController synchronizeNoteChanges:nil];
		[[notationController notesAtIndexes:indexes] makeObjectsPerformSelector:@selector(editExternallyUsingEditor:) withObject:ed];
	} else {
		NSBeep();
	}
}

- (IBAction)printNote:(id)sender {
	NSIndexSet *indexes = [notesTableView selectedRowIndexes];

	[MultiplePageView printNotes:[notationController notesAtIndexes:indexes] forWindow:window];
}

- (IBAction)tagNote:(id)sender {

	if ([nsSplitView isSubviewCollapsed:notesScrollView]) {
		[self toggleCollapse:sender];
	}
	//if single note, add the tag column if necessary and then begin editing

	NSIndexSet *indexes = [notesTableView selectedRowIndexes];

	if ([indexes count] > 1) {
		//Multiple Notes selected, use ElasticThreads' multitagging implementation
		TagEditer = [[TagEditingManager alloc] init];
		[TagEditer setDel:self];
		@try {
			cTags = [[self commonLabels] copy];
			if ([cTags count] > 0) {
				[TagEditer setTF:[cTags componentsJoinedByString:@","]];
			} else {
				[TagEditer setTF:@""];
			}
			[TagEditer popTP:self];
		}
		@catch (NSException *e) {
			NSLog(@"multitag excep this: %@", [e name]);
		}
	} else if ([indexes count] == 1) {
		isEd = YES;
		[notesTableView editRowAtColumnWithIdentifier:NoteLabelsColumnString];
	}
}

- (IBAction)importNotes:(id)sender {
	[[[AlienNoteImporter alloc] init] importNotesFromDialogAroundWindow: window completion: ^(NSArray *notes) {
		[notationController addNotes: notes];
	}];
}

- (void)settingChangedForSelectorString:(NSString *)selectorString {
	if ([selectorString isEqualToString:SEL_STR(setBookmarkDataForDefaultDirectory:sender:)]) {
		// defaults changed for the database location -- load the new one!
		NSError *anErr = nil;
		NotationController *newNotation = nil;
		NSData *newData = [prefsController bookmarkDataForDefaultDirectory];

		if (newData) {
			if ((newNotation = [[NotationController alloc] initWithBookmarkData: newData error:&anErr])) {
				[self setNotationController:newNotation];

			} else {

				//set bookmark data back
				NSData *oldData = [notationController bookmarkDataForNoteDirectory];
				[prefsController setBookmarkDataForDefaultDirectory: oldData sender:self];

				//display alert with err--could not set notation directory
				NSURL *homeFolder = [NSURL fileURLWithPath: NSHomeDirectory() isDirectory: YES];
				NSURL *URL = [NSURL URLByResolvingBookmarkData: newData options: NSURLBookmarkResolutionWithoutUI | NSURLBookmarkResolutionWithoutMounting relativeToURL: homeFolder bookmarkDataIsStale: NULL error: NULL];
				NSString *reason = [NSString reasonStringFromCarbonFSError: (int)anErr.code];
				NSRunAlertPanel([NSString stringWithFormat:NSLocalizedString(@"Unable to initialize notes database in \n%@ because %@.", nil), URL, reason], NSLocalizedString(@"Reverting to current location.", nil),
								NSLocalizedString(@"OK", nil), NULL, NULL);
			}
		}
	} else if ([selectorString isEqualToString:SEL_STR(setSortedTableColumnKey : reversed:sender :)]) {
		NoteAttributeColumn *oldSortCol = [notationController sortColumn];
		NoteAttributeColumn *newSortCol = [notesTableView noteAttributeColumnForIdentifier:[prefsController sortedTableColumnKey]];
		BOOL changedColumns = oldSortCol != newSortCol;

		NVViewLocationContext *ctx;
		if (changedColumns) {
			ctx = [notesTableView viewingLocation];
			ctx.pivotRowWasEdge = NO;
		}

		[notationController setSortColumn:newSortCol];

		if (changedColumns) [notesTableView setViewingLocation:ctx];

	} else if ([selectorString isEqualToString:SEL_STR(setNoteBodyFont :sender :)]) {

		[notationController restyleAllNotes];
		if (currentNote) {
			[self contentsUpdatedForNote:currentNote];
		}
	} else if ([selectorString isEqualToString:SEL_STR(setForegroundTextColor :sender :)]) {
		if (userScheme != 2) {
			[self setUserColorScheme:self];
		} else {
			[self setForegrndColor:[prefsController foregroundTextColor]];
			[self updateColorScheme];
		}
	} else if ([selectorString isEqualToString:SEL_STR(setBackgroundTextColor :sender :)]) {
		if (userScheme != 2) {
			[self setUserColorScheme:self];
		} else {
			[self setBackgrndColor:[prefsController backgroundTextColor]];
			[self updateColorScheme];
		}

	} else if ([selectorString isEqualToString:SEL_STR(setTableFontSize :sender :)] || [selectorString isEqualToString:SEL_STR(setTableColumnsShowPreview :sender :)]) {

		ResetFontRelatedTableAttributes();
		[notesTableView updateTitleDereferencorState];
		//[notationController invalidateAllLabelPreviewImages];
		[self _forceRegeneratePreviewsForTitleColumn];

		if ([selectorString isEqualToString:SEL_STR(setTableColumnsShowPreview :sender :)]) [self updateNoteMenus];

		[notesTableView performSelector:@selector(reloadData) withObject:nil afterDelay:0];
	} else if ([selectorString isEqualToString:SEL_STR(addTableColumn :sender :)] || [selectorString isEqualToString:SEL_STR(removeTableColumn :sender :)]) {

		ResetFontRelatedTableAttributes();
		[self _forceRegeneratePreviewsForTitleColumn];
		[notesTableView performSelector:@selector(reloadDataIfNotEditing) withObject:nil afterDelay:0];

	} else if ([selectorString isEqualToString:SEL_STR(setConfirmNoteDeletion :sender :)]) {
		[self updateNoteMenus];
	} else if ([selectorString isEqualToString:SEL_STR(setAutoCompleteSearches :sender :)]) {
		if ([prefsController autoCompleteSearches])
			[notationController updateTitlePrefixConnections];

	}

}

- (void)tableView:(NSTableView *)tableView didClickTableColumn:(NSTableColumn *)tableColumn {
//    NSLog(@"dickclicktablecol");
	if (tableView == notesTableView) {
		//this sets global prefs options, which ultimately calls back to us
		[notesTableView setStatusForSortedColumn:tableColumn];
	}
}

- (BOOL)tableView:(NSTableView *)tableView shouldShowCellExpansionForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
	return ![[tableColumn identifier] isEqualToString:NoteTitleColumnString];
}

- (IBAction)showHelpDocument:(id)sender {
	NSString *path = nil;

	switch ([sender tag]) {
		case 1:        //shortcuts
			path = [[NSBundle mainBundle] pathForResource:NSLocalizedString(@"Excruciatingly Useful Shortcuts", nil) ofType:@"nvhelp" inDirectory:nil];
		case 2:        //acknowledgments
			if (!path) path = [[NSBundle mainBundle] pathForResource:@"Acknowledgments" ofType:@"txt" inDirectory:nil];
			[[NSWorkspace sharedWorkspace] openURLs:@[[NSURL fileURLWithPath:path]] withAppBundleIdentifier:@"com.apple.TextEdit"
											options:NSWorkspaceLaunchDefault additionalEventParamDescriptor:nil launchIdentifiers:NULL];
			break;
		case 3:        //product site
			[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:NSLocalizedString(@"SiteURL", nil)]];
			break;
		case 4:        //development site
			[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://notational.net/development"]];
			break;
		case 5:     //nvALT home
			[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://brettterpstra.com/project/nvalt/"]];
			break;
		case 6:     //ElasticThreads
			[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://elasticthreads.tumblr.com/nv"]];
			break;
		case 7:     //Brett Terpstra
			[[NSWorkspace sharedWorkspace] openURL:[NSURL URLWithString:@"http://brettterpstra.com"]];
			break;
		default:
			NSBeep();
	}
}

- (void)application:(NSApplication *)sender openFiles:(NSArray *)filenames {

	if (notationController)
		[notationController openFiles:filenames];
	else
		pathsToOpenOnLaunch = [filenames mutableCopyWithZone:nil];

	[NSApp replyToOpenOrPrint:[filenames count] ? NSApplicationDelegateReplySuccess : NSApplicationDelegateReplyFailure];
}

- (void)applicationWillBecomeActive:(NSNotification *)aNotification {

	SpaceSwitchingContext thisSpaceSwitchCtx;
	CurrentContextForWindowNumber([window windowNumber], &thisSpaceSwitchCtx);
	//what if the app is switched-to in another way? then the last-stored spaceSwitchCtx will cause us to return to the wrong app
	//unfortunately this notification occurs only after NV has become the front process, but we can still verify the space number

	if (thisSpaceSwitchCtx.userSpace != spaceSwitchCtx.userSpace ||
			thisSpaceSwitchCtx.windowSpace != spaceSwitchCtx.windowSpace) {
		//forget the last space-switch info if it's effectively different from how we're switching into the app now
		bzero(&spaceSwitchCtx, sizeof(SpaceSwitchingContext));
	}
}

- (void)applicationDidBecomeActive:(NSNotification *)aNotification {
	[notationController checkJournalExistence];

	if ([notationController currentNoteStorageFormat] != SingleDatabaseFormat)
		[notationController performSelector:@selector(synchronizeNotesFromDirectory) withObject:nil afterDelay:0.0];
	[cView setActiveIcon:self];
	[notationController updateDateStringsIfNecessary];
}

- (void)applicationWillResignActive:(NSNotification *)aNotification {
	//sync note files when switching apps so user doesn't have to guess when they'll be updated
	[notationController synchronizeNoteChanges:nil];
	[cView setInactiveIcon:self];
//	[self resetModTimers];
	[[NSNotificationCenter defaultCenter] postNotificationName:@"ModTimersShouldReset" object:nil];

}

- (NSMenu *)applicationDockMenu:(NSApplication *)sender {
	static NSMenu *dockMenu = nil;
	if (!dockMenu) {
		dockMenu = [[NSMenu alloc] initWithTitle:@"NV Dock Menu"];
		[[dockMenu addItemWithTitle:NSLocalizedString(@"Add New Note from Clipboard", @"menu item title in dock menu") action:@selector(paste:) keyEquivalent:@""] setTarget:notesTableView];
	}
	return dockMenu;
}

- (void)cancel:(id)sender {
	//fallback for when other views are hidden/removed during toolbar collapse
	[self cancelOperation:sender];
}

- (void)cancelOperation:(id)sender {
	//simulate a search for nothing
	if ([window isKeyWindow]) {
		if ([textView textFinderIsVisible]) {
			[[NSNotificationCenter defaultCenter] postNotificationName:@"TextFinderShouldHide" object:self];
			return;
		}
		[field setStringValue:@""];
		typedStringIsCached = NO;

		[notationController filterNotesFromString:@""];

		[notesTableView deselectAll:sender];
		[self setDualFieldIsVisible:YES];
//		[self _expandToolbar];

		[field selectText:sender];
		[[field cell] setShowsClearButton:NO];
	} else if ([[TagEditer tagPanel] isKeyWindow]) {  //<--this is for ElasticThreads' multitagging window
		[TagEditer closeTP:self];
	}
}

//- (BOOL)textView:(NSTextView *)aTextView doCommandBySelector:(SEL)aSelector{
//    NSLog(@"AtextView:%@ doCommand:%@",[aTextView description],NSStringFromSelector(aSelector));
//    return NO;
//}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)aTextView doCommandBySelector:(SEL)command {
//    NSLog(@"BtextView:%@ doCommand:%@",[aTextView description],NSStringFromSelector(command));
	if (control == (NSControl *) field) {

		isEd = NO;
		//backwards-searching is slow enough as it is, so why not just check this first?
		if (command == @selector(deleteBackward:))
			return NO;

		if (command == @selector(moveDown:) || command == @selector(moveUp:) ||
				//catch shift-up/down selection behavior
				command == @selector(moveDownAndModifySelection:) ||
				command == @selector(moveUpAndModifySelection:) ||
				command == @selector(moveToBeginningOfDocumentAndModifySelection:) ||
				command == @selector(moveToEndOfDocumentAndModifySelection:)) {

			BOOL singleSelection = ([notesTableView numberOfRows] == 1 && [notesTableView numberOfSelectedRows] == 1);
			[notesTableView keyDown:[window currentEvent]];

			NSUInteger strLen = [[aTextView string] length];
			if (!singleSelection && [aTextView selectedRange].length != strLen) {
				[aTextView setSelectedRange:NSMakeRange(0, strLen)];
			}

			return YES;
		}

		if ((command == @selector(insertTab:) || command == @selector(insertTabIgnoringFieldEditor:))) {
			//[self setEmptyViewState:NO];
			if (![[aTextView string] length]) {
				return YES;
			}
			if (!currentNote && [notationController preferredSelectedNoteIndex] != NSNotFound && [prefsController autoCompleteSearches]) {
				//if the current note is deselected and re-searching would auto-complete this search, then allow tab to trigger it
				[self searchForString:[self fieldSearchString]];
				return YES;
			} else if ([textView isHidden]) {
				return YES;
			}

			[window makeFirstResponder:textView];

			//don't eat the tab!
			return NO;
		}
		if (command == @selector(moveToBeginningOfDocument:)) {
			[notesTableView selectRowAndScroll:0];
			return YES;
		}
		if (command == @selector(moveToEndOfDocument:)) {
			[notesTableView selectRowAndScroll:[notesTableView numberOfRows] - 1];
			return YES;
		}

		if (command == @selector(moveToBeginningOfLine:) || command == @selector(moveToLeftEndOfLine:)) {
			[aTextView moveToBeginningOfDocument:nil];
			return YES;
		}
		if (command == @selector(moveToEndOfLine:) || command == @selector(moveToRightEndOfLine:)) {
			[aTextView moveToEndOfDocument:nil];
			return YES;
		}

		if (command == @selector(moveToBeginningOfLineAndModifySelection:) || command == @selector(moveToLeftEndOfLineAndModifySelection:)) {

			if ([aTextView respondsToSelector:@selector(moveToBeginningOfDocumentAndModifySelection:)]) {
				[(id) aTextView performSelector:@selector(moveToBeginningOfDocumentAndModifySelection:)];
				return YES;
			}
		}
		if (command == @selector(moveToEndOfLineAndModifySelection:) || command == @selector(moveToRightEndOfLineAndModifySelection:)) {
			if ([aTextView respondsToSelector:@selector(moveToEndOfDocumentAndModifySelection:)]) {
				[(id) aTextView performSelector:@selector(moveToEndOfDocumentAndModifySelection:)];
				return YES;
			}
		}

		//we should make these two commands work for linking editor as well
		if (command == @selector(deleteToMark:)) {
			[aTextView deleteWordBackward:nil];
			return YES;
		}
		if (command == NSSelectorFromString(@"noop:")) {
			//control-U is not set to anything by default, so we have to check the event itself for noops
			NSEvent *event = [window currentEvent];
			if ([event modifierFlags] & NSControlKeyMask) {
				if ([event firstCharacterIgnoringModifiers] == 'u') {
					//in 1.1.1 this deleted the entire line, like tcsh. this is more in-line with bash
					[aTextView deleteToBeginningOfLine:nil];
					return YES;
				}
			}
		}

	} else if (control == (NSControl *) notesTableView) {

		if (command == @selector(insertNewline:)) {
			//hit return in cell
			//NSLog(@"herehere");
			isEd = NO;
			[window makeFirstResponder:textView];
			return YES;
		}
	} else if (control == [TagEditer tagField]) {

		if (command == @selector(insertNewline:)) {
			if ([aTextView selectedRange].length > 0) {
				NSString *theLabels = [TagEditer newMultinoteLabels];
				if (![theLabels hasSuffix:@" "]) {
					theLabels = [theLabels stringByAppendingString:@" "];
				}
				[TagEditer setTF:theLabels];
				[aTextView setSelectedRange:NSMakeRange(theLabels.length, 0)];
				return YES;
			}
		} else if (command == @selector(insertTab:)) {
			if ([aTextView selectedRange].length > 0) {
				NSString *theLabels = [TagEditer newMultinoteLabels];
				if (![theLabels hasSuffix:@" "]) {
					theLabels = [theLabels stringByAppendingString:@" "];
				}
				[TagEditer setTF:theLabels];
				[aTextView setSelectedRange:NSMakeRange(theLabels.length, 0)];
			}
			return YES;
		} else {
			if ((command == @selector(deleteBackward:)) || (command == @selector(deleteForward:))) {
				wasDeleting = YES;
			}
			return NO;
		}
	} else {

		NSLog(@"%@/%@ got %@", [control description], [aTextView description], NSStringFromSelector(command));
		isEd = NO;
	}

	return NO;
}

- (void)_setCurrentNote:(NoteObject *)aNote {
	//save range of old current note
	//we really only want to save the insertion point position if it's currently invisible
	//how do we test that?
	BOOL wasAutomatic = NO;
	NSRange currentRange = [textView selectedRangeWasAutomatic:&wasAutomatic];
	if (!wasAutomatic) [currentNote setSelectedRange:currentRange];

	//regenerate content cache before switching to new note
	[currentNote updateContentCacheCStringIfNecessary];


	currentNote = aNote;
}

- (NSString *)fieldSearchString {
	NSString *typed = [self typedString];
	if (typed) return typed;

	if (!currentNote) return [field stringValue];

	return nil;
}

- (NSString *)typedString {
	if (typedStringIsCached)
		return typedString;

	return nil;
}

- (void)cacheTypedStringIfNecessary:(NSString *)aString {
	if (!typedStringIsCached) {
		typedString = [(aString ? aString : [field stringValue]) copy];
		typedStringIsCached = YES;
	}
}

//from fieldeditor
- (void)controlTextDidChange:(NSNotification *)aNotification {

	if ([aNotification object] == field) {
//        [self resetModTimers];
//        [[NSNotificationCenter defaultCenter] postNotificationName:@"ModTimersShouldReset" object:nil];
		typedStringIsCached = NO;
		isFilteringFromTyping = YES;

		NSTextView *fieldEditor = [aNotification userInfo][@"NSFieldEditor"];
		NSString *fieldString = [fieldEditor string];

		BOOL didFilter = [notationController filterNotesFromString:fieldString];

		if ([fieldString length] > 0) {
			[field setSnapbackString:nil];


			NSUInteger preferredNoteIndex = [notationController preferredSelectedNoteIndex];

			//lastLengthReplaced depends on textView:shouldChangeTextInRange:replacementString: being sent before controlTextDidChange: runs
			if ([prefsController autoCompleteSearches] && preferredNoteIndex != NSNotFound && ([field lastLengthReplaced] > 0)) {

				[notesTableView selectRowAndScroll:preferredNoteIndex];

				if (didFilter) {
					//current selection may be at the same row, but note at that row may have changed
					[self displayContentsForNoteAtIndex:preferredNoteIndex];
				}

				NSAssert(currentNote != nil, @"currentNote must not--cannot--be nil!");

				NSRange typingRange = [fieldEditor selectedRange];

				//fill in the remaining characters of the title and select
				if ([field lastLengthReplaced] > 0 && typingRange.location < currentNote.title.length) {

					[self cacheTypedStringIfNecessary:fieldString];

					NSAssert([fieldString isEqualToString:[fieldEditor string]], @"I don't think it makes sense for fieldString to change");

					NSString *remainingTitle = [currentNote.title substringFromIndex:typingRange.location];
					typingRange.length = [fieldString length] - typingRange.location;
					typingRange.length = MAX(typingRange.length, 0U);

					[fieldEditor replaceCharactersInRange:typingRange withString:remainingTitle];
					typingRange.length = [remainingTitle length];
					[fieldEditor setSelectedRange:typingRange];
				}

			} else {
				//auto-complete is off, search string doesn't prefix any title, or part of the search string is being removed
				goto selectNothing;
			}
		} else {
			//selecting nothing; nothing typed
			selectNothing:
					isFilteringFromTyping = NO;
			[notesTableView deselectAll:nil];

			//reloadData could have already de-selected us, and hence this notification would not be sent from -deselectAll:
			[self processChangedSelectionForTable:notesTableView];
		}

		isFilteringFromTyping = NO;

	} else if ([TagEditer isMultitagging]) { //<--for elasticthreads multitagging
		if (!isAutocompleting && !wasDeleting) {
			isAutocompleting = YES;
			NSTextView *editor = (NSTextView *) [[TagEditer tagPanel] fieldEditor:YES forObject:[TagEditer tagField]];
			NSRange selRange = [editor selectedRange];
			NSString *tagString = [TagEditer newMultinoteLabels];
			NSString *searchString = tagString;
			if (selRange.length > 0) {
				searchString = [searchString substringWithRange:selRange];
			}
			searchString = [[searchString componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@", "]] lastObject];
			selRange = [tagString rangeOfString:searchString options:NSBackwardsSearch];
			NSArray *theTags = [notesTableView labelCompletionsForString:searchString index:0];
			if ((theTags) && ([theTags count] > 0) && (![theTags[0] isEqualToString:@""])) {
				NSString *useStr;
				for (useStr in theTags) {
					if ([tagString rangeOfString:useStr].location == NSNotFound) {
						break;
					}
				}
				if (useStr) {
					tagString = [tagString substringToIndex:selRange.location];
					tagString = [tagString stringByAppendingString:useStr];
					selRange = NSMakeRange(selRange.location + selRange.length, useStr.length - searchString.length);
					[TagEditer setTF:tagString];
					[editor setSelectedRange:selRange];
				}
			}
			isAutocompleting = NO;
//            [tagString release];
		}
		wasDeleting = NO;
	}
}

- (void)tableViewSelectionIsChanging:(NSNotification *)aNotification {


	BOOL allowMultipleSelection = NO;
	NSEvent *event = [window currentEvent];

//    [self resetModTimers];
	[[NSNotificationCenter defaultCenter] postNotificationName:@"ModTimersShouldReset" object:nil];
	NSEventType type = [event type];
	//do not allow drag-selections unless a modifier is pressed
	if (type == NSLeftMouseDragged || type == NSLeftMouseDown) {
		NSUInteger flags = [event modifierFlags];
		if ((flags & NSShiftKeyMask) || (flags & NSCommandKeyMask)) {
			allowMultipleSelection = YES;
		}
	}

	if (allowMultipleSelection != [notesTableView allowsMultipleSelection]) {
		//we may need to hack some hidden NSTableView instance variables to improve mid-drag flags-changing
		//NSLog(@"set allows mult: %d", allowMultipleSelection);

		[notesTableView setAllowsMultipleSelection:allowMultipleSelection];

		//we need this because dragging a selection back to the same note will nto trigger a selectionDidChange notification
		[self performSelector:@selector(setTableAllowsMultipleSelection) withObject:nil afterDelay:0];
	}

	if ([window firstResponder] != notesTableView) {
		//occasionally changing multiple selection ability in-between selecting multiple items causes total deselection
		[window makeFirstResponder:notesTableView];
	}

	[self processChangedSelectionForTable:[aNotification object]];
}

- (void)setTableAllowsMultipleSelection {
	[notesTableView setAllowsMultipleSelection:YES];
	//NSLog(@"allow mult: %d", [notesTableView allowsMultipleSelection]);
	//[textView setNeedsDisplay:YES];
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification {
	[[NSNotificationCenter defaultCenter] postNotificationName:@"TextFindContextDidChange" object:self];
	isEd = NO;
	NSEventType type = [[window currentEvent] type];
	if (type != NSKeyDown && type != NSKeyUp) {
		[self performSelector:@selector(setTableAllowsMultipleSelection) withObject:nil afterDelay:0];
	}

	[self processChangedSelectionForTable:[aNotification object]];
}

- (void)processChangedSelectionForTable:(NSTableView *)table {
	NSInteger selectedRow = [table selectedRow];
	NSInteger numberSelected = [table numberOfSelectedRows];

	NSTextView *fieldEditor = (NSTextView *) [field currentEditor];

	if (table == (NSTableView *) notesTableView) {

		if (selectedRow > -1 && numberSelected == 1) {
			//if it is uncached, cache the typed string only if we are selecting a note

			[self cacheTypedStringIfNecessary:[fieldEditor string]];

			//add snapback-button here?
			if (!isFilteringFromTyping && !isCreatingANote)
				[field setSnapbackString:typedString];

			if ([self displayContentsForNoteAtIndex:selectedRow]) {

				[[field cell] setShowsClearButton:YES];

				//there doesn't seem to be any situation in which a note will be selected
				//while the user is typing and auto-completion is disabled, so should be OK

				if (!isFilteringFromTyping) {
					//	if ([toolbar isVisible]) {
					if ([self dualFieldIsVisible]) {
						if (fieldEditor) {
							//the field editor has focus--select text, too
							fieldEditor.string = currentNote.title;
							NSUInteger strLen = currentNote.title.length;
							if (strLen != [fieldEditor selectedRange].length)
								[fieldEditor setSelectedRange:NSMakeRange(0, strLen)];
						} else {
							//this could be faster
							field.stringValue = currentNote.title;
						}
					} else {
						window.title = currentNote.title;
					}
				}
			}
			return;
		}
	}

	if (!isFilteringFromTyping) {
		if (currentNote) {
			//selected nothing and something is currently selected

			[self _setCurrentNote:nil];
			[field setShowsDocumentIcon:NO];

			if (typedStringIsCached) {
				//restore the un-selected state, but only if something had been first selected to cause that state to be saved
				[field setStringValue:typedString];
			}
			[textView setString:@""];
		}
		//[self _expandToolbar];
		[self setDualFieldIsVisible:YES];
		[mainView setNeedsDisplay:YES];
		if (!currentNote) {
			if (selectedRow == -1 && (!fieldEditor || [window firstResponder] != fieldEditor)) {
				//don't select the field if we're already there
				[window makeFirstResponder:field];
				fieldEditor = (NSTextView *) [field currentEditor];
			}
			if (fieldEditor && [fieldEditor selectedRange].length)
				[fieldEditor setSelectedRange:NSMakeRange([[fieldEditor string] length], 0)];


			//remove snapback-button from dual field here?
			[field setSnapbackString:nil];

			if (!numberSelected && savedSelectedNotes) {
				//savedSelectedNotes needs to be empty after de-selecting all notes,
				//to ensure that any delayed list-resorting does not re-select savedSelectedNotes

				savedSelectedNotes = nil;
			}
		}
	}
	[self setEmptyViewState:currentNote == nil];
	[field setShowsDocumentIcon:currentNote != nil];
	[[field cell] setShowsClearButton:currentNote != nil || [[field stringValue] length]];
}


- (BOOL)setNoteIfNecessary {
	if (currentNote == nil) {
		[notesTableView selectRowAndScroll:0];
		return (currentNote != nil);
	}
	return YES;
}

- (void)setEmptyViewState:(BOOL)state {
	//return;

	//int numberSelected = [notesTableView numberOfSelectedRows];
	//BOOL enable = /*numberSelected != 1;*/ state;

	[self postTextUpdate];
	[self updateWordCount:(![prefsController showWordCount])];
	[textView setHidden:state];
	[editorStatusView setHidden:!state];

	if (state) {
		[editorStatusView setLabelStatus:[notesTableView numberOfSelectedRows]];
		if ([nsSplitView isSubviewCollapsed:notesScrollView]) {
			[self toggleCollapse:self];
		}
	}
}

- (BOOL)displayContentsForNoteAtIndex:(NSInteger)noteIndex {
	NoteObject *note = [notationController noteObjectAtFilteredIndex:noteIndex];
	if (note != currentNote) {
		[self setEmptyViewState:NO];
		[field setShowsDocumentIcon:YES];

		//actually load the new note
		[self _setCurrentNote:note];

		NSRange firstFoundTermRange = NSMakeRange(NSNotFound, 0);
		NSRange noteSelectionRange = currentNote.selectedRange;

		if (noteSelectionRange.location == NSNotFound ||
				NSMaxRange(noteSelectionRange) > [[note contentString] length]) {
			//revert to the top; selection is invalid
			noteSelectionRange = NSMakeRange(0, 0);
		}

		//[textView beginInhibitingUpdates];
		//scroll to the top first in the old note body if necessary, because the text will (or really ought to) have already been laid-out
		//if ([textView visibleRect].origin.y > 0)
		//	[textView scrollRangeToVisible:NSMakeRange(0,0)];

		if (![textView didRenderFully]) {
			//NSLog(@"redisplay because last note was too long to finish before we switched");
			[textView setNeedsDisplayInRect:[textView visibleRect] avoidAdditionalLayout:YES];
		}

		//restore string
		[[textView textStorage] setAttributedString:[note contentString]];
		[self postTextUpdate];
		[self updateWordCount:(![prefsController showWordCount])];
		//[textView setAutomaticallySelectedRange:NSMakeRange(0,0)];

		//highlight terms--delay this, too
		if (noteIndex != [notationController preferredSelectedNoteIndex])
			firstFoundTermRange = [textView highlightTermsTemporarilyReturningFirstRange:typedString avoidHighlight:
					![prefsController highlightSearchTerms]];

		//if there was nothing selected, select the first found range
		if (!noteSelectionRange.length && firstFoundTermRange.location != NSNotFound)
			noteSelectionRange = firstFoundTermRange;

		//select and scroll
		[textView setAutomaticallySelectedRange:noteSelectionRange];
		[textView scrollRangeToVisible:noteSelectionRange];

		//NSString *words = noteIndex != [notationController preferredSelectedNoteIndex] ? typedString : nil;
		//[textView setFutureSelectionRange:noteSelectionRange highlightingWords:words];

		[self updateRTL];

		return YES;
	}

	return NO;
}

//from linkingeditor
- (void)textDidChange:(NSNotification *)aNotification {
	id textObject = [aNotification object];
	//[self resetModTimers];
	if (textObject == textView) {
		[currentNote setContentString:[textView textStorage]];
		[self postTextUpdate];
		[self updateWordCount:(![prefsController showWordCount])];
	}
	[[NSNotificationCenter defaultCenter] postNotificationName:@"TextFindContextDidChange" object:self];
}

- (void)textDidBeginEditing:(NSNotification *)aNotification {
	if ([aNotification object] == textView) {
		[textView removeHighlightedTerms];
		[self createNoteIfNecessary];
	}/*else if ([aNotification object] == notesTableView) {
         NSLog(@"ntv tdbe2");
    }*/
}

/*
 - (void)controlTextDidBeginEditing:(NSNotification *)aNotification{
 NSLog(@"controltextdidbegin");
 }

- (void)textShouldBeginEditing:(NSNotification *)aNotification {
	
    NSLog(@"ntv textshould2");
    
} */

- (void)textDidEndEditing:(NSNotification *)aNotification {
	if ([aNotification object] == textView) {
		//save last selection range for currentNote?
		//[currentNote setSelectedRange:[textView selectedRange]];

		//we need to set this here as we could return to searching before changing notes
		//and the next time the note would change would be when searching had triggered it
		//which would be too late
		[currentNote updateContentCacheCStringIfNecessary];
	}
}

- (NSMenu *)textView:(NSTextView *)view menu:(NSMenu *)menu forEvent:(NSEvent *)event atIndex:(NSUInteger)charIndex {
//    NSLog(@"textview menu for event");
	NSInteger idx;
	if ((idx = [menu indexOfItemWithTarget:nil andAction:@selector(_removeLinkFromMenu:)]) > -1)
		[menu removeItemAtIndex:idx];
	if ((idx = [menu indexOfItemWithTarget:nil andAction:@selector(orderFrontLinkPanel:)]) > -1)
		[menu removeItemAtIndex:idx];
	return menu;
}

- (NSArray *)textView:(NSTextView *)aTextView completions:(NSArray *)words
  forPartialWordRange:(NSRange)charRange indexOfSelectedItem:(NSInteger *)anIndex {
	NSArray *noteTitles = [notationController noteTitlesPrefixedByString:[[aTextView string] substringWithRange:charRange] indexOfSelectedItem:anIndex];
	return noteTitles;
}


- (IBAction)fieldAction:(id)sender {

	[self createNoteIfNecessary];
	[window makeFirstResponder:textView];

}

- (NSUndoManager *)windowWillReturnUndoManager:(NSWindow *)sender {

	if ([sender firstResponder] == textView) {
		if (currentNote) {
			NSLog(@"windowWillReturnUndoManager should not be called when textView is first responder on Tiger or higher");
		}

		NSUndoManager *undoMan = [self undoManagerForTextView:textView];
		if (undoMan)
			return undoMan;
	}
	return windowUndoManager;
}

- (NSUndoManager *)undoManagerForTextView:(NSTextView *)aTextView {
	if (aTextView == textView && currentNote)
		return [currentNote undoManager];

	return nil;
}

- (NoteObject *)createNoteIfNecessary {

	if (!currentNote) {
		//this assertion not yet valid until labels list changes notes list
		NSAssert([notesTableView numberOfSelectedRows] != 1, @"cannot create a note when one is already selected");

		[textView setTypingAttributes:[prefsController noteBodyAttributes]];
		[textView setFont:[prefsController noteBodyFont]];

		isCreatingANote = YES;
		NSString *title = [[field stringValue] length] ? [field stringValue] : NSLocalizedString(@"Untitled Note", @"Title of a nameless note");
		NSAttributedString *attributedContents = [textView textStorage] ? [textView textStorage] : [[NSAttributedString alloc] initWithString:@"" attributes:
				[prefsController noteBodyAttributes]];
		NoteObject *note = [[NoteObject alloc] initWithNoteBody:attributedContents title:title delegate:notationController
														 format:[notationController currentNoteStorageFormat] labels:nil];
		[notationController addNewNote:note];

		isCreatingANote = NO;
		return note;
	}

	return currentNote;
}

- (void)restoreListStateUsingPreferences {
	//to be invoked after loading a notationcontroller

	NSString *searchString = [prefsController lastSearchString];
	if ([searchString length])
		[self searchForString:searchString];
	else
		[notationController refilterNotes];

	CFUUIDBytes bytes = [prefsController UUIDBytesOfLastSelectedNote];
	NSUInteger idx = [self revealNote:[notationController noteForUUIDBytes:&bytes] options:NVDoNotChangeScrollPosition];
	//scroll using saved scrollbar position
	[notesTableView scrollRowToVisible:NSNotFound == idx ? 0 : idx withVerticalOffset:[prefsController scrollOffsetOfLastSelectedNote]];
}

- (NSUInteger)revealNote:(NoteObject *)note options:(NVNoteRevealOptions)opts {
	if (note) {
		NSUInteger selectedNoteIndex = [notationController indexInFilteredListForNoteIdenticalTo:note];

		if (selectedNoteIndex == NSNotFound) {
			NSLog(@"Note was not visible--showing all notes and trying again");
			[self cancelOperation:nil];

			selectedNoteIndex = [notationController indexInFilteredListForNoteIdenticalTo:note];
		}

		if (selectedNoteIndex != NSNotFound) {
			if (opts & NVDoNotChangeScrollPosition) { //select the note only
				[notesTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:selectedNoteIndex] byExtendingSelection:NO];
			} else {
				[notesTableView selectRowAndScroll:selectedNoteIndex];
			}
		}

		if (opts & NVEditNoteToReveal) {
			[window makeFirstResponder:textView];
		}
		if (opts & NVOrderFrontWindow) {
			//for external url-handling, often the app will already have been brought to the foreground
			if (![NSApp isActive]) {
				CurrentContextForWindowNumber([window windowNumber], &spaceSwitchCtx);
				[NSApp activateIgnoringOtherApps:YES];
			}
			if (![window isKeyWindow])
				[window makeKeyAndOrderFront:nil];
		}
		return selectedNoteIndex;
	} else {
		[notesTableView deselectAll:self];
		return NSNotFound;
	}
}

- (void)notation:(NotationController *)notation revealNote:(NoteObject *)note options:(NVNoteRevealOptions)opts {
	[self revealNote:note options:opts];
}

- (void)notation:(NotationController *)notation revealNotes:(NSArray *)notes {

	NSIndexSet *indexes = [notation indexesOfNotes:notes];
	if ([notes count] != [indexes count]) {
		[self cancelOperation:nil];

		indexes = [notation indexesOfNotes:notes];
	}
	if ([indexes count]) {
		[notesTableView selectRowIndexes:indexes byExtendingSelection:NO];
		[notesTableView scrollRowToVisible:[indexes firstIndex]];
	}
}

- (void)searchForString:(NSString *)string {

	if (string) {

		//problem: this won't work when the toolbar (and consequently the searchfield) is hidden;
		//and neither will the controlTextDidChange implementation
		//[self _expandToolbar];

		[self setDualFieldIsVisible:YES];
		[mainView setNeedsDisplay:YES];
		[window makeFirstResponder:field];
		NSTextView *fieldEditor = (NSTextView *) [field currentEditor];
		NSRange fullRange = NSMakeRange(0, [[fieldEditor string] length]);
		if ([fieldEditor shouldChangeTextInRange:fullRange replacementString:string]) {
			[fieldEditor replaceCharactersInRange:fullRange withString:string];
			[fieldEditor didChangeText];
		} else {
			NSLog(@"I shouldn't change text?");
		}
	}
}

- (void)bookmarksController:(BookmarksController *)controller restoreNoteBookmark:(NoteBookmark *)aBookmark inBackground:(BOOL)inBG {
	if (aBookmark) {
		[self searchForString:[aBookmark searchString]];
		[self revealNote:[aBookmark noteObject] options:!inBG ? NVOrderFrontWindow : 0];
	}
}

#pragma mark - NSSplitViewDelegate

- (BOOL)splitView:(NSSplitView *)splitView canCollapseSubview:(NSView *)subview {
	if (notesScrollView == subview) {
		return currentNote != nil;
	}
	return NO;
}

- (CGFloat)splitView:(NSSplitView *)aSplitView constrainMinCoordinate:(CGFloat)proposedMinimumPosition ofSubviewAt:(NSInteger)dividerIndex {
	return MAX(proposedMinimumPosition, kMinNotesListDimension);
}

- (CGFloat)splitView:(NSSplitView *)aSplitView constrainMaxCoordinate:(CGFloat)proposedMaximumPosition ofSubviewAt:(NSInteger)dividerIndex {
	return MIN(proposedMaximumPosition - kMinEditorDimension, kMaxNotesListDimension);
}

// mail.app-like resizing behavior wrt item selections
- (void)splitView:(NSSplitView *)splitView resizeSubviewsWithOldSize:(NSSize)oldSize {
	if (![prefsController horizontalLayout]) {
		[notesTableView makeFirstPreviouslyVisibleRowVisibleIfNecessary];
	}

	[splitView adjustSubviews];
}

- (BOOL)splitView:(NSSplitView *)splitView shouldAdjustSizeOfSubview:(NSView *)view {
	if ([view isEqual:notesScrollView] && splitView.window.inLiveResize) return NO;
	return YES;
}

#pragma mark -

- (void)tableViewColumnDidResize:(NSNotification *)aNotification {
	NoteAttributeColumn *col = [aNotification userInfo][@"NSTableColumn"];
	if ([[col identifier] isEqualToString:NoteTitleColumnString]) {
		[notationController regeneratePreviewsForColumn:col visibleFilteredRows:[notesTableView rowsInRect:[notesTableView visibleRect]] forceUpdate:NO];

		[NSObject cancelPreviousPerformRequestsWithTarget:notesTableView selector:@selector(reloadDataIfNotEditing) object:nil];
		[notesTableView performSelector:@selector(reloadDataIfNotEditing) withObject:nil afterDelay:0.0];
	}
}

- (NSSize)windowWillResize:(NSWindow *)theWindow toSize:(NSSize)proposedFrameSize {
	if ([prefsController horizontalLayout]) {
		[notesTableView makeFirstPreviouslyVisibleRowVisibleIfNecessary];
	}
	return proposedFrameSize;
}

#pragma mark -


//the notationcontroller must call notationListShouldChange: first 
//if it's going to do something that could mess up the tableview's field eidtor
- (BOOL)notationListShouldChange:(NotationController *)someNotation {

	if (someNotation == notationController) {
		if ([notesTableView currentEditor])
			return NO;
	}

	return YES;
}

- (void)notationListMightChange:(NotationController *)someNotation {

	if (!isFilteringFromTyping) {
		if (someNotation == notationController) {
			//deal with one notation at a time

			if ([notesTableView numberOfSelectedRows] > 0) {
				NSIndexSet *indexSet = [notesTableView selectedRowIndexes];

				savedSelectedNotes = [someNotation notesAtIndexes:indexSet];
			}

			listUpdateViewCtx = [notesTableView viewingLocation];
		}
	}
}

- (void)notationListDidChange:(NotationController *)someNotation {

	if (someNotation == notationController) {
		//deal with one notation at a time

		[notesTableView reloadData];
		//[notesTableView noteNumberOfRowsChanged];

		if (!isFilteringFromTyping) {
			if (savedSelectedNotes) {
				NSIndexSet *indexes = [someNotation indexesOfNotes:savedSelectedNotes];
				savedSelectedNotes = nil;

				[notesTableView selectRowIndexes:indexes byExtendingSelection:NO];
			}

			[notesTableView setViewingLocation:listUpdateViewCtx];
		}
	}
}

- (void)titleUpdatedForNote:(NoteObject *)aNoteObject {
	if (aNoteObject == currentNote) {
		//	if ([toolbar isVisible]) {
		if ([self dualFieldIsVisible]) {
			field.stringValue = currentNote.title;
		} else {
			window.title = currentNote.title;
		}
	}
	[[prefsController bookmarksController] updateBookmarksUI];
}

- (void)contentsUpdatedForNote:(NoteObject *)aNoteObject {
	if (aNoteObject == currentNote) {

		[[textView textStorage] setAttributedString:[aNoteObject contentString]];
		[self postTextUpdate];
		[self updateWordCount:(![prefsController showWordCount])];
	}
}

- (void)rowShouldUpdate:(NSInteger)affectedRow {
	NSRect rowRect = [notesTableView rectOfRow:affectedRow];
	NSRect visibleRect = [notesTableView visibleRect];

	if (NSContainsRect(visibleRect, rowRect) || NSIntersectsRect(visibleRect, rowRect)) {
		[notesTableView setNeedsDisplayInRect:rowRect];
	}
}

- (void)syncSessionsChangedVisibleStatus:(NSNotification *)aNotification {
	SyncSessionController *syncSessionController = [aNotification object];
	if ([syncSessionController hasErrors]) {
		[titleBarButton setStatusIconType:AlertIcon];
	} else if ([syncSessionController hasRunningSessions]) {
		[titleBarButton setStatusIconType:SynchronizingIcon];
	} else {
		[titleBarButton setStatusIconType:[[NSUserDefaults standardUserDefaults] boolForKey:@"ShowSyncMenu"] ? DownArrowIcon : NoIcon];
	}
}


- (IBAction)fixFileEncoding:(id)sender {
	if (currentNote) {
		[notationController synchronizeNoteChanges:nil];

		[[EncodingsManager sharedManager] showPanelForNote:currentNote];
	}
}


- (void)windowDidResignKey:(NSNotification *)notification {
	[[NSNotificationCenter defaultCenter] postNotificationName:@"ModTimersShouldReset" object:nil];
	if ([notification object] == [TagEditer tagPanel]) {  //<--this is for ElasticThreads' multitagging window

		if ([TagEditer isMultitagging]) {
			//   BOOL tagExists = YES;
			[TagEditer closeTP:self];
			if (cTags) {
				cTags = nil;
			}
		}
	}

}

- (void)windowWillClose:(NSNotification *)aNotification {

//	[self resetModTimers];
	[[NSNotificationCenter defaultCenter] postNotificationName:@"ModTimersShouldReset" object:nil];
	if ([prefsController quitWhenClosingWindow]) {
		[NSApp terminate:nil];
	}
}

- (void)_finishSyncWait {
	//always post to next runloop to ensure that a sleep-delay response invocation, if one is also queued, runs before this one
	//if the app quits before the sleep-delay response posts, then obviously sleep will be delayed by quite a bit
	[self performSelector:@selector(syncWaitQuit:) withObject:nil afterDelay:0];
}

- (IBAction)syncWaitQuit:(id)sender {
	//need this variable to allow overriding the wait
	waitedForUncommittedChanges = YES;
	NSString *errMsg = [[notationController syncSessionController] changeCommittingErrorMessage];
	if ([errMsg length]) NSRunAlertPanel(NSLocalizedString(@"Changes could not be uploaded.", nil), errMsg, @"Quit", nil, nil);

	[NSApp terminate:nil];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
	//if a sync session is still running, then wait for it to finish before sending terminatereply
	//otherwise, if there are unsynced notes to send, then push them right now and wait until session is no longer running
	//use waitForUncommitedChangesWithTarget:selector: and provide a callback to send NSTerminateNow

	InvocationRecorder *invRecorder = [InvocationRecorder invocationRecorder];
	[[invRecorder prepareWithInvocationTarget:self] _finishSyncWait];

	if (!waitedForUncommittedChanges &&
			[[notationController syncSessionController] waitForUncommitedChangesWithInvocation:[invRecorder invocation]]) {

		[[NSApp windows] makeObjectsPerformSelector:@selector(orderOut:) withObject:nil];
		[syncWaitPanel center];
		[syncWaitPanel makeKeyAndOrderFront:nil];
		[syncWaitSpinner startAnimation:nil];
		//use NSTerminateCancel instead of NSTerminateLater because we need the runloop functioning in order to receive start/stop sync notifications
		return NSTerminateCancel;
	}
	return NSTerminateNow;
}

- (void)applicationWillTerminate:(NSNotification *)aNotification {
	if (notationController) {
		//only save the state if the notation instance has actually loaded; i.e., don't save last-selected-note if we quit from a PW dialog
		BOOL wasAutomatic = NO;
		NSRange currentRange = [textView selectedRangeWasAutomatic:&wasAutomatic];
		if (!wasAutomatic) [currentNote setSelectedRange:currentRange];

		[currentNote updateContentCacheCStringIfNecessary];

		[prefsController setLastSearchString:[self fieldSearchString] selectedNote:currentNote
					scrollOffsetForTableView:notesTableView sender:self];

		[prefsController saveCurrentBookmarksFromSender:self];
	}

	[[NSApp windows] makeObjectsPerformSelector:@selector(close)];
	[notationController stopFileNotifications];

	//wait for syncing to finish, showing a progress bar

	if ([notationController flushAllNoteChanges])
		[notationController closeJournal];
	else
		NSLog(@"Could not flush database, so not removing journal");

	[prefsController synchronize];
}

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[[NSStatusBar systemStatusBar] removeStatusItem:statusItem];
	[self postTextUpdate];

}

- (IBAction)showPreferencesWindow:(id)sender {
	[prefsWindowController showWindow:sender];
}

- (void)toggleNVActivation {

	if ([NSApp isActive] && [window isMainWindow]) {

		SpaceSwitchingContext laterSpaceSwitchCtx;
		CurrentContextForWindowNumber([window windowNumber], &laterSpaceSwitchCtx);

		if (!CompareContextsAndSwitch(&spaceSwitchCtx, &laterSpaceSwitchCtx)) {
			//hide only if we didn't need to or weren't able to switch spaces
			[NSApp hide:self];
		}
		//clear the space-switch context that we just looked at, to ensure it's not reused inadvertently
		bzero(&spaceSwitchCtx, sizeof(SpaceSwitchingContext));
		return;
	}
	[self bringFocusToControlField:self];
}

- (IBAction)bringFocusToControlField:(id)sender {
	//For ElasticThreads' fullscreen mode use this if/else otherwise uncomment the expand toolbar

	[[NSNotificationCenter defaultCenter] postNotificationName:@"TextFinderShouldHide" object:sender];
	if ([nsSplitView isSubviewCollapsed:notesScrollView]) {
		[self toggleCollapse:self];
	} else if (![self dualFieldIsVisible]) {

		[self setDualFieldIsVisible:YES];
	}

	[field selectText:sender];

	if (![NSApp isActive]) {
		CurrentContextForWindowNumber([window windowNumber], &spaceSwitchCtx);
		[NSApp activateIgnoringOtherApps:YES];
	}
	if (![window isMainWindow]) [window makeKeyAndOrderFront:sender];
	[self setEmptyViewState:currentNote == nil];
	isEd = NO;
}

- (NSWindow *)window {
	return window;
}

#pragma mark ElasticThreads methods



- (void)setIsEditing:(BOOL)inBool {
	isEd = inBool;
}

- (void)tableView:(NSTableView *)aTableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex {
	//NSUInteger rowInt =  rowIndex;

	if ([[notesTableView selectedRowIndexes] containsIndex:rowIndex]) {
		if (isEd) {
			[aCell setTextColor:foregrndColor];
		} else {
			[aCell setTextColor:[NSColor whiteColor]];
		}
	} else {
		[aCell setTextColor:foregrndColor];
	}
}

- (NSMenu *)statBarMenu {
	return statBarMenu;
}

- (void)toggleAttachedWindow:(NSNotification *)aNotification {
	if (![window isKeyWindow]) {
		//	[self focusOnCtrlFld:self];
		if (![window isMainWindow]) [window makeKeyAndOrderFront:self];
		[NSApp activateIgnoringOtherApps:YES];
	} else {
		[NSApp hide:[aNotification object]];
		//	[statusItem popUpStatusItemMenu:statBarMenu];
		//	return YES;
	}
}

- (void)toggleAttachedMenu:(NSNotification *)aNotification {
	[statusItem popUpStatusItemMenu:statBarMenu];

}


- (NSArray *)commonLabels {
	NSCharacterSet *tagSeparators = [NSCharacterSet characterSetWithCharactersInString:@", "];
	NSArray *retArray = @[@""];
	NSIndexSet *indexes = [notesTableView selectedRowIndexes];
	NSEnumerator *noteEnum = [[notationController notesAtIndexes:indexes] objectEnumerator];
	NoteObject *aNote = [noteEnum nextObject];
	NSString *existTags = aNote.labels;
	NSSet *tagsForNote = nil;
	NSMutableSet *commonTags = [NSMutableSet setWithCapacity:1];
	NSArray *tagArray = nil;
	if (![existTags isEqualToString:@""]) {
		tagArray = [existTags componentsSeparatedByCharactersInSet:tagSeparators];
		[commonTags addObjectsFromArray:tagArray];

		while (((aNote = [noteEnum nextObject])) && ([commonTags count] > 0)) {
			existTags = aNote.labels;
			if (![existTags isEqualToString:@""]) {
				tagArray = [existTags componentsSeparatedByCharactersInSet:tagSeparators];
				@try {
					if ([tagArray count] > 0) {
						tagsForNote = [NSSet setWithArray:tagArray];
						if ([commonTags intersectsSet:tagsForNote]) {
							[commonTags intersectSet:tagsForNote];
						} else {
							[commonTags removeAllObjects];
							break;
						}

					} else {
						[commonTags removeAllObjects];
						break;
					}
				}
				@catch (NSException *e) {
					NSLog(@"intersect EXCEPT: %@", [e description]);
					[commonTags removeAllObjects];
					break;
				}
			} else {
				[commonTags removeAllObjects];
				break;
			}
		}
		if ([commonTags count] > 0) {
			retArray = [commonTags allObjects];
		}
	}
	return retArray;
}

- (IBAction)multiTag:(id)sender {
	NSCharacterSet *tagSeparators = [NSCharacterSet characterSetWithCharactersInString:@", "];
	NSString *existTagString;
	NSMutableArray *theTags = [[NSMutableArray alloc] init];
	NSString *thisTag = [TagEditer newMultinoteLabels];
	NSArray *newTags = [[thisTag componentsSeparatedByCharactersInSet:tagSeparators] copy];
	for (thisTag in newTags) {
		if (([thisTag hasPrefix:@" "]) || ([thisTag hasSuffix:@" "])) {
			thisTag = [thisTag stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		}
		if (([thisTag hasPrefix:@","]) || ([thisTag hasSuffix:@","])) {
			thisTag = [thisTag stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@","]];
		}
		if (![thisTag isEqualToString:@""]) {
			[theTags addObject:thisTag];
		}
	}
	if ([theTags count] < 1) {
		[theTags addObject:@""];
	}

	NoteObject *aNote;
	NSArray *selNotes = [notationController notesAtIndexes:[notesTableView selectedRowIndexes]];
	for (aNote in selNotes) {
		existTagString = aNote.labels;

		NSMutableArray *finalTags = [[NSMutableArray alloc] init];
		[finalTags addObjectsFromArray:theTags];
		NSArray *existingTags = [existTagString componentsSeparatedByCharactersInSet:tagSeparators];
		for (thisTag in existingTags) {
			if (([thisTag hasPrefix:@" "]) || ([thisTag hasSuffix:@" "])) {
				thisTag = [thisTag stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
			}

			if ((![theTags containsObject:thisTag]) && (![cTags containsObject:thisTag]) && (![thisTag isEqualToString:@""])) {
				[finalTags addObject:thisTag];
			}
		}
		NSString *newTagsString = [finalTags componentsJoinedByString:@" "];
		if (([newTagsString hasPrefix:@","]) || ([newTagsString hasSuffix:@","])) {
			newTagsString = [newTagsString stringByTrimmingCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@","]];
		}
		[aNote setLabelString:newTagsString];
	}
	[TagEditer closeTP:self];
}

- (void)setDualFieldInToolbar {
	NSView *dualSV = [field superview];
	[dualFieldView removeFromSuperviewWithoutNeedingDisplay];
	[dualSV removeFromSuperviewWithoutNeedingDisplay];
	dualFieldItem = [[NSToolbarItem alloc] initWithItemIdentifier:@"DualField"];
	[dualFieldItem setView:dualSV];
	[dualFieldItem setMaxSize:NSMakeSize(FLT_MAX, [dualSV frame].size.height)];
	[dualFieldItem setMinSize:NSMakeSize(50.0f, [dualSV frame].size.height)];
	[dualFieldItem setLabel:NSLocalizedString(@"Search or Create", @"placeholder text in search/create field")];

	toolbar = [[NSToolbar alloc] initWithIdentifier:@"NVToolbar"];
	[toolbar setAllowsUserCustomization:NO];
	[toolbar setAutosavesConfiguration:NO];
	[toolbar setDisplayMode:NSToolbarDisplayModeIconOnly];
	[toolbar setShowsBaselineSeparator:YES];
	[toolbar setDelegate:self];
	[window setToolbar:toolbar];

	[window setShowsToolbarButton:NO];
	titleBarButton = [[TitlebarButton alloc] initWithFrame:NSMakeRect(0, 0, 19.0, 19.0) pullsDown:YES];
	[titleBarButton addToWindow:window];

	[field setDelegate:self];
	[self setDualFieldIsVisible:[self dualFieldIsVisible]];
}

- (void)setDualFieldInView {
	NSView *dualSV = [field superview];
//	BOOL dfIsVis = [self dualFieldIsVisible];
	[dualSV removeFromSuperviewWithoutNeedingDisplay];
	//NSView *wView = [window contentView];
	NSSize wSize = [mainView frame].size;
	wSize.height = wSize.height - 38;
	[nsSplitView setFrameSize:wSize];
	NSRect dfViewFrame = [nsSplitView frame];
	dfViewFrame.size.height = 40;
	dfViewFrame.origin.y = [mainView frame].origin.y + [nsSplitView frame].size.height - 1;
	dualFieldView = [[DFView alloc] initWithFrame:dfViewFrame];
	[mainView addSubview:dualFieldView];
	NSRect dsvFrame = [dualSV frame];
	dsvFrame.origin.y += 4;
	dsvFrame.size.width = wSize.width * 0.986;
	dsvFrame.origin.x = (wSize.width * 0.007);
	[dualSV setFrame:dsvFrame];
	[dualFieldView addSubview:dualSV];
	[field setDelegate:self];
	[self setDualFieldIsVisible:[self dualFieldIsVisible]];


}

- (void)setDualFieldIsVisible:(BOOL)isVis {
//    NSLog(@"settin' df vis:%d",isVis);
	if (isVis) {
		[window setTitle:@"nvALT"];
		if (currentNote) field.stringValue = currentNote.title;

		if ([mainView isInFullScreenMode]) {
			NSSize wSize = [mainView frame].size;
			wSize.height = wSize.height - 38;
			[nsSplitView setFrameSize:wSize];
			[dualFieldView setHidden:NO];
			[nsSplitView adjustSubviews];
			[mainView setNeedsDisplay:YES];
		} else {
			[toolbar setVisible:YES];
			//  [self _expandToolbar];
		}
		[window setInitialFirstResponder:field];

	} else {
		if (currentNote) window.title = currentNote.title;

		if ([mainView isInFullScreenMode]) {
			[dualFieldView setHidden:YES];
			[nsSplitView setFrameSize:[mainView frame].size];
			[nsSplitView adjustSubviews];
			[mainView setNeedsDisplay:YES];
		} else {
			// [self _collapseToolbar];
			[toolbar setVisible:NO];
		}
		[window setInitialFirstResponder:textView];
	}

	[[NSUserDefaults standardUserDefaults] setBool:!isVis forKey:@"ToolbarHidden"];

}

- (BOOL)dualFieldIsVisible {
	return ![[NSUserDefaults standardUserDefaults] boolForKey:@"ToolbarHidden"];
}

- (IBAction)toggleCollapse:(id)sender {
	if ([nsSplitView isSubviewCollapsed:notesScrollView]) {
		[self setDualFieldIsVisible:YES];
		[notesScrollView setHidden:NO];
	} else {
		[self setDualFieldIsVisible:NO];
		[notesScrollView setHidden:YES];
		[window makeFirstResponder:textView];
	}
	[nsSplitView adjustSubviews];
	[mainView setNeedsDisplay:YES];
}

/*
 - (NSApplicationPresentationOptions)window:(NSWindow *)window 
 willUseFullScreenPresentationOptions:(NSApplicationPresentationOptions)rect{
 return NSApplicationPresentationFullScreen | NSApplicationPresentationAutoHideMenuBar |NSApplicationPresentationAutoHideToolbar | NSApplicationPresentationHideDock;
 #endif
 }
 */

- (void)windowWillEnterFullScreen:(NSNotification *)aNotification {
	//   / [window setCollectionBehavior:NSWindowCollectionBehaviorFullScreenPrimary];
	wasDFVisible = [self dualFieldIsVisible];
	if (![nsSplitView isVertical]) {
		[self switchViewLayout:self];
		wasVert = NO;
	} else {
		wasVert = YES;
		//[splitView adjustSubviews];
	}

}

- (void)windowDidEnterFullScreen:(NSNotification *)aNotification {
	if (!wasDFVisible) {
		[self performSelector:@selector(postToggleToolbar:) withObject:@NO afterDelay:0.0001];
	}
}

- (void)windowWillExitFullScreen:(NSNotification *)aNotification {
	wasDFVisible = [self dualFieldIsVisible];
	if ((!wasVert) && ([nsSplitView isVertical])) {
		[self switchViewLayout:self];
	}
}

- (void)windowDidExitFullScreen:(NSNotification *)notification {
	if (wasDFVisible != [nsSplitView isSubviewCollapsed:notesScrollView]) {
		if (!wasDFVisible) {
			[self performSelector:@selector(postToggleToolbar:) withObject:@NO afterDelay:0.0001];

		} else {
			[self performSelector:@selector(postToggleToolbar:) withObject:@YES afterDelay:0.0001];
		}
	}
}

- (void)postToggleToolbar:(NSNumber *)boolNum {
	[self setDualFieldIsVisible:[boolNum boolValue]];
}

- (BOOL)isInFullScreen {
	return (([window styleMask] & NSFullScreenWindowMask) > 0);

}

- (IBAction)switchFullScreen:(id)sender {
	[window toggleFullScreen:nil];
}

- (IBAction)setBWColorScheme:(id)sender {
	userScheme = 0;
	[[NSUserDefaults standardUserDefaults] setInteger:userScheme forKey:@"ColorScheme"];
	[self setForegrndColor:[NSColor colorWithCalibratedRed:0.0f green:0.0f blue:0.0f alpha:1.0f]];
	[self setBackgrndColor:[NSColor colorWithCalibratedRed:1.0f green:1.0f blue:1.0f alpha:1.0f]];
	NSMenu *mainM = [NSApp mainMenu];
	NSMenu *viewM = [[mainM itemWithTitle:@"View"] submenu];
	mainM = [[viewM itemWithTitle:@"Color Schemes"] submenu];
	viewM = [[statBarMenu itemWithTitle:@"Color Schemes"] submenu];
	[[mainM itemAtIndex:0] setState:1];
	[[mainM itemAtIndex:1] setState:0];
	[[mainM itemAtIndex:2] setState:0];

	[[viewM itemAtIndex:0] setState:1];
	[[viewM itemAtIndex:1] setState:0];
	[[viewM itemAtIndex:2] setState:0];
	[self updateColorScheme];
}

- (IBAction)setLCColorScheme:(id)sender {
	userScheme = 1;
	[[NSUserDefaults standardUserDefaults] setInteger:userScheme forKey:@"ColorScheme"];
	[self setForegrndColor:[NSColor colorWithCalibratedRed:0.172f green:0.172f blue:0.172f alpha:1.0f]];
	[self setBackgrndColor:[NSColor colorWithCalibratedRed:0.874f green:0.874f blue:0.874f alpha:1.0f]];
	NSMenu *mainM = [NSApp mainMenu];
	NSMenu *viewM = [[mainM itemWithTitle:@"View"] submenu];
	mainM = [[viewM itemWithTitle:@"Color Schemes"] submenu];
	viewM = [[statBarMenu itemWithTitle:@"Color Schemes"] submenu];
	[[mainM itemAtIndex:0] setState:0];
	[[mainM itemAtIndex:1] setState:1];
	[[mainM itemAtIndex:2] setState:0];

	[[viewM itemAtIndex:0] setState:0];
	[[viewM itemAtIndex:1] setState:1];
	[[viewM itemAtIndex:2] setState:0];
	[self updateColorScheme];
}

- (IBAction)setUserColorScheme:(id)sender {
	userScheme = 2;
	[[NSUserDefaults standardUserDefaults] setInteger:userScheme forKey:@"ColorScheme"];
	[self setForegrndColor:[prefsController foregroundTextColor]];
	[self setBackgrndColor:[prefsController backgroundTextColor]];
	NSMenu *mainM = [NSApp mainMenu];
	NSMenu *viewM = [[mainM itemWithTitle:@"View"] submenu];
	mainM = [[viewM itemWithTitle:@"Color Schemes"] submenu];
	viewM = [[statBarMenu itemWithTitle:@"Color Schemes"] submenu];
	[[mainM itemAtIndex:0] setState:0];
	[[mainM itemAtIndex:1] setState:0];
	[[mainM itemAtIndex:2] setState:1];

	[[viewM itemAtIndex:0] setState:0];
	[[viewM itemAtIndex:1] setState:0];
	[[viewM itemAtIndex:2] setState:1];
	//NSLog(@"foreground col is: %@",[foregrndColor description]);
	//NSLog(@"background col is: %@",[backgrndColor description]);
	[self updateColorScheme];
}

- (void)updateColorScheme {
	@try {
		[mainView setBackgroundColor:backgrndColor];
		[notesTableView setBackgroundColor:backgrndColor];

		[self updateFieldAttributes];
		[NotesTableHeaderCell setForegroundColor:foregrndColor];
		//[editorStatusView setBackgroundColor:backgrndColor];
		//		[editorStatusView setNeedsDisplay:YES];
		//	[field setTextColor:foregrndColor];
		[textView updateTextColors];
		[notationController setForegroundTextColor:foregrndColor];
		if (currentNote) {
			[self contentsUpdatedForNote:currentNote];
		}
		[dividerShader updateColors:backgrndColor];
		[nsSplitView setNeedsDisplay:YES];
	}
	@catch (NSException *e) {
		NSLog(@"setting SCheme EXception : %@", [e name]);
	}
}

- (void)updateFieldAttributes {
	if (!foregrndColor) {
		foregrndColor = [self foregrndColor];
	}
	if (!backgrndColor) {
		backgrndColor = [self backgrndColor];
	}
	fieldAttributes = @{NSBackgroundColorAttributeName : [textView selectionColorForForegroundColor:foregrndColor backgroundColor:backgrndColor]};

	if (isEd) {
		[theFieldEditor setDrawsBackground:NO];
		// [theFieldEditor setBackgroundColor:backgrndColor];
		[theFieldEditor setSelectedTextAttributes:fieldAttributes];
		[theFieldEditor setInsertionPointColor:foregrndColor];
		//   [notesTableView setNeedsDisplay:YES];

	}

}

- (void)setBackgrndColor:(NSColor *)inColor {
	backgrndColor = inColor;
}

- (void)setForegrndColor:(NSColor *)inColor {
	foregrndColor = inColor;
}

- (NSColor *)backgrndColor {
	if (!backgrndColor) {
		NSColor *theColor;// = [NSColor redColor];
		if (!userScheme) {
			userScheme = [[NSUserDefaults standardUserDefaults] integerForKey:@"ColorScheme"];
		}
		if (userScheme == 0) {
			theColor = [NSColor colorWithCalibratedRed:1.0f green:1.0f blue:1.0f alpha:1.0f];
		} else if (userScheme == 1) {
			theColor = [NSColor colorWithCalibratedRed:0.874f green:0.874f blue:0.874f alpha:1.0f];
		} else if (userScheme == 2) {
			NSData *theData = [[NSUserDefaults standardUserDefaults] dataForKey:@"BackgroundTextColor"];
			if (theData) {
				theColor = (NSColor *) [NSUnarchiver unarchiveObjectWithData:theData];
			} else {
				theColor = [prefsController backgroundTextColor];
			}

		} else {
			theColor = [NSColor whiteColor];
		}
		[self setBackgrndColor:theColor];

		return theColor;
	} else {
		return backgrndColor;
	}

}

- (NSColor *)foregrndColor {
	if (!foregrndColor) {
		NSColor *theColor = [NSColor blackColor];
		if (!userScheme) {
			userScheme = [[NSUserDefaults standardUserDefaults] integerForKey:@"ColorScheme"];
		}

		if (userScheme == 0) {
			theColor = [NSColor colorWithCalibratedRed:0.0f green:0.0f blue:0.0f alpha:1.0f];
		} else if (userScheme == 1) {
			theColor = [NSColor colorWithCalibratedRed:0.142f green:0.142f blue:0.142f alpha:1.0f];
		} else if (userScheme == 2) {

			NSData *theData = [[NSUserDefaults standardUserDefaults] dataForKey:@"ForegroundTextColor"];
			if (theData) {
				theColor = (NSColor *) [NSUnarchiver unarchiveObjectWithData:theData];
			} else {
				theColor = [prefsController foregroundTextColor];
			}
		}
		[self setForegrndColor:theColor];
		return theColor;
	} else {
		return foregrndColor;
	}

}

- (void)updateWordCount:(BOOL)doIt {
	//NSLog(@"updating wordcount");
	if (doIt) {
		/*  NSArray *selRange = [textView selectedRanges];
		 // NSLog(@"selRange is :%@",[selRange description]);
		  int theCount = 0;
		  if (([selRange count]>1)||([[selRange objectAtIndex:0] rangeValue].length>0)) {
			  for (id aRange in selRange) {
				  NSRange bRange = [aRange rangeValue];
				  NSString *aStr = [[textView string] substringWithRange: bRange];
				  if ([aStr length]>0) {
						aStr = [aStr stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
					  if ([aStr length]>0) {
						  for (id bStr in [aStr componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]) {
							  if ([bStr length]>0) {
								  theCount += 1;
							  }
						  }
					  }
				  }
			  }
		  }else{*/

		NSTextStorage *noteStorage = [textView textStorage];
		NSUInteger theCount = [[noteStorage words] count];

		// }
		if (theCount > 0) {
			[wordCounter setStringValue:[[NSString stringWithFormat:@"%ld", theCount] stringByAppendingString:@" words"]];
		} else {
			[wordCounter setStringValue:@""];
		}
	}
}

- (void)popWordCount:(BOOL)showIt {
//    NSUInteger testInt=NSFlagsChanged|NSMouseMoved|NSMouseEntered|NSMouseExited|NSScrollWheel;
	NSUInteger curEv = [[NSApp currentEvent] type];
	if ((curEv == NSFlagsChanged) || (curEv == NSMouseMoved) || (curEv == NSMouseEntered) || (curEv == NSMouseExited) || (curEv == NSScrollWheel)) {
		if (showIt) {
			if (([wordCounter isHidden]) && ([prefsController showWordCount])) {
				[self updateWordCount:YES];
				[wordCounter setHidden:NO];
				popped = 1;
			}
		} else {
			if ((![wordCounter isHidden]) && ([prefsController showWordCount])) {
				[wordCounter setHidden:YES];
				[wordCounter setStringValue:@""];
				popped = 0;
			}
		}
	}
//    else{
//    NSLog(@"not flagschanged on popWord:%lu",[[NSApp currentEvent] type]);
//    }
}

- (IBAction)toggleWordCount:(id)sender {


	[prefsController synchronize];
	if ([prefsController showWordCount]) {
		[self updateWordCount:YES];
		[wordCounter setHidden:NO];

		popped = 1;
	} else {
		[wordCounter setHidden:YES];
		[wordCounter setStringValue:@""];
		popped = 0;
	}

	if (![[sender className] isEqualToString:@"NSMenuItem"]) {
		[prefsController setShowWordCount:![prefsController showWordCount]];
	}

}

- (void)flagsChanged:(NSEvent *)theEvent {

	//	if (ModFlagger>=0) {
	// NSLog(@"flagschanged :>%@<",theEvent);
	if ((ModFlagger == 0) && (popped == 0) && ([theEvent modifierFlags] & NSAlternateKeyMask) && (([theEvent keyCode] == 58) || ([theEvent keyCode] == 61))) { //option down&NSKeyDownMask
		ModFlagger = 1;
		modifierTimer = [NSTimer scheduledTimerWithTimeInterval:1.2
														 target:self
													   selector:@selector(updateModifier:)
													   userInfo:@"option"
														repeats:NO];

	} else if ((ModFlagger == 0) && (popped == 0) && ([theEvent modifierFlags] & NSControlKeyMask) && (([theEvent keyCode] == 59) || ([theEvent keyCode] == 62))) { //control down
		ModFlagger = 2;
		modifierTimer = [NSTimer scheduledTimerWithTimeInterval:1.2
														 target:self
													   selector:@selector(updateModifier:)
													   userInfo:@"control"
														repeats:NO];

	} else {
		[[NSNotificationCenter defaultCenter] postNotificationName:@"ModTimersShouldReset" object:nil];
	}
}

- (void)updateModifier:(NSTimer *)theTimer {
	if ([theTimer isValid]) {
		// NSLog(@"updatemod modflag :>%d< popped:%d",ModFlagger,popped);
		if ((ModFlagger > 0) && (popped == 0)) {
			if ([[theTimer userInfo] isEqualToString:@"option"]) {
				[self popWordCount:YES];
				popped = 1;
			} else if ([[theTimer userInfo] isEqualToString:@"control"]) {
				[self popPreview:YES];
				popped = 2;
			}
		}
		[theTimer invalidate];
	}
}

- (void)resetModTimers:(NSNotification *)notification {


	if ((ModFlagger > 0) || (popped > 0)) {
		ModFlagger = 0;
		if (modifierTimer) {
			if ([modifierTimer isValid]) {
				[modifierTimer invalidate];
			}
			modifierTimer = nil;
		}
		if (popped == 1) {
			[self performSelector:@selector(popWordCount:) withObject:NO afterDelay:0.1];
		} else if (popped == 2) {
			[self performSelector:@selector(popPreview:) withObject:NO afterDelay:0.1];
		}
		popped = 0;
	}
}


#pragma mark Preview-related and to be extracted into separate files
- (void)popPreview:(BOOL)showIt {
//    NSLog(@"current event is :%@",[[NSApp currentEvent] description]);
	NSUInteger curEv = [[NSApp currentEvent] type];
	if ((curEv == NSFlagsChanged) || (curEv == NSMouseMoved) || (curEv == NSMouseEntered) || (curEv == NSMouseExited) || (curEv == NSScrollWheel)) {
		if ([previewToggler state] == 0) {
			if (showIt) {
				if (![previewController previewIsVisible]) {
					[self togglePreview:self];
				}
				popped = 2;
			} else {
				if ([previewController previewIsVisible]) {
					[self togglePreview:self];
				}
				popped = 0;
			}
		}
	}
//    else{
//        
//        NSLog(@"not flagschanged on popPre:%lu",[[NSApp currentEvent] type]);
//    }
}


- (IBAction)togglePreview:(id)sender {
	BOOL doIt = (currentNote != nil);
	if ([previewController previewIsVisible]) {
		doIt = YES;
	}
	if ([[sender className] isEqualToString:@"NSMenuItem"]) {
		[sender setState:![sender state]];
	}
	if (doIt) {
		[previewController togglePreview:self];
	}
}

- (void)ensurePreviewIsVisible {
	if (![[previewController window] isVisible]) {
		[previewController togglePreview:self];
	}
}

- (IBAction)toggleSourceView:(id)sender {
	[self ensurePreviewIsVisible];
	[previewController switchTabs:self];
}

- (IBAction)savePreview:(id)sender {
	[self ensurePreviewIsVisible];
	[previewController saveHTML:self];
}

- (IBAction)sharePreview:(id)sender {
	[self ensurePreviewIsVisible];
	[previewController shareAsk:self];
}

- (IBAction)lockPreview:(id)sender {
	if (![previewController previewIsVisible])
		return;
	if ([previewController isPreviewSticky]) {
		[previewController makePreviewNotSticky:self];
	} else {
		[previewController makePreviewSticky:self];
	}
}

- (IBAction)printPreview:(id)sender {
	[self ensurePreviewIsVisible];
	[previewController printPreview:self];
}

- (void)postTextUpdate {

	[[NSNotificationCenter defaultCenter] postNotificationName:@"TextView has changed contents" object:self];
}

- (IBAction)selectPreviewMode:(id)sender {
	NSMenuItem *previewItem = sender;
	currentPreviewMode = [previewItem tag];

	// update user defaults
	[[NSUserDefaults standardUserDefaults] setObject:@(currentPreviewMode)
											  forKey:@"markupPreviewMode"];

	[self postTextUpdate];
}

- (id)windowWillReturnFieldEditor:(NSWindow *)sender toObject:(id)client {

	if (isEd) {
		// NSLog(@"window will return client is :%@",client);

		if (!fieldAttributes) {
			[self updateFieldAttributes];
		} else {
			if (!foregrndColor) {
				foregrndColor = [self foregrndColor];
			}
			if (!backgrndColor) {
				backgrndColor = [self backgrndColor];
			}
			[theFieldEditor setDrawsBackground:NO];
			// [theFieldEditor setBackgroundColor:backgrndColor];
			[theFieldEditor setSelectedTextAttributes:fieldAttributes];
			[theFieldEditor setInsertionPointColor:foregrndColor];

			// [notesTableView setNeedsDisplay:YES];
		}
	} else {//if (client==field) {
		[theFieldEditor setDrawsBackground:NO];
		[theFieldEditor setSelectedTextAttributes:@{NSBackgroundColorAttributeName : [NSColor selectedTextBackgroundColor]}];
		[theFieldEditor setInsertionPointColor:[NSColor blackColor]];
	}
	// NSLog(@"window first is :%@",[window firstResponder]);
	//NSLog(@"client is :%@",client);
	//}


	return theFieldEditor;
	//[super windowWillReturnFieldEditor:sender toObject:client];
}

- (void)updateRTL {
	if ([prefsController rtl]) {
		[textView setBaseWritingDirection:NSWritingDirectionRightToLeft range:NSMakeRange(0, [[textView string] length])];
	} else {
		[textView setBaseWritingDirection:NSWritingDirectionLeftToRight range:NSMakeRange(0, [[textView string] length])];
	}
}

- (void)refreshNotesList {
	[notesTableView setNeedsDisplay:YES];
}

- (BOOL)performKeyEquivalent:(NSEvent *)theEvent {
	NSLog(@"perform key AC");
//    [self resetModTimers];
	[[NSNotificationCenter defaultCenter] postNotificationName:@"ModTimersShouldReset" object:nil];
	return YES;
}

#pragma mark toggleDock
- (void)togDockIcon:(NSNotification *)notification {
	BOOL showIt = [[notification object] boolValue];
	if (showIt) {
		[self performSelectorOnMainThread:@selector(reactivateAfterDelay) withObject:nil waitUntilDone:NO];
	} else {
		[self performSelectorOnMainThread:@selector(relaunchAfterDelay) withObject:nil waitUntilDone:NO];

	}
}

- (void)relaunchAfterDelay {

	[self performSelector:@selector(relaunchNV:) withObject:self afterDelay:0.22];
}

- (void)relaunchNV:(id)sender {
	id fullPath = [[NSBundle mainBundle] executablePath];
	NSArray *arg = @[];
	[NSTask launchedTaskWithLaunchPath:fullPath arguments:arg];
	[NSApp terminate:sender];
}

- (void)reactivateAfterDelay {
	[NSApp hide:self];
	[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
	[self performSelector:@selector(reActivate:) withObject:self afterDelay:0.16];
}

- (void)reActivate:(id)sender {
	[NSApp activateIgnoringOtherApps:YES];
}

#pragma mark NSPREDICATE TO FIND MARKDOWN REFERENCE LINKS
- (IBAction)testThing:(id)sender {
//    NSString *testString=@"not []http://sdfas as\n\not [][]\n not [](http://)\n     a   [a ref]: http://nytimes.com \n squirels [another ref]: http://google.com    \n http://squarshit \n how's tthat http his lorem ipsum";
//    
//    NSArray *foundLinks=[self referenceLinksInString:testString];
//    if (foundLinks&&([foundLinks count]>0)) {
//        NSLog(@"found'em:%@",[foundLinks description]);
//    }else{
//        NSLog(@"didn't find shit");
//    }
}

- (NSArray *)referenceLinksInString:(NSString *)contentString {
	NSString *wildString = @"*[*]:*http*"; //This is where you define your match string.
	NSPredicate *matchPred = [NSPredicate predicateWithFormat:@"SELF LIKE[cd] %@", wildString];
	/*
	 Breaking it down:
	 SELF is the string your testing
	 [cd] makes the test case insensitive
	 LIKE is one of the predicate search possiblities. It's NOT regex, but lets you use wildcards '?' for one character and '*' for any number of characters
	 MATCH (not used) is what you would use for Regex. And you'd set it up similiar to LIKE. I don't really know regex, and I can't quite get it to work. But that might be because I don't know regex.
	 %@ you need to pass in the search string like this, rather than just embedding it in the format string. so DON'T USE something like [NSPredicate predicateWithFormat:@"SELF LIKE[cd] *[*]:*http*"]
	 */

	NSMutableArray *referenceLinks = [NSMutableArray new];

	//enumerateLinesUsing block seems like a good way to go line by line thru the note and test each line for the regex match of a reference link. Downside is that it uses blocks so requires 10.6+. Let's get it to work and then we can figure out a Leopard friendly way of doing this; which I don't think will be a problem (famous last words).
	[contentString enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
		if ([matchPred evaluateWithObject:line]) {
			//            NSLog(@"%@ matched",line);
			NSString *theRef = line;
			//theRef=[line substring...]  here you want to parse out and get just the name of the reference link we'd want to offer up to the user in the autocomplete
			//and maybe trim out whitespace
			theRef = [theRef stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
			//check to make sure its not empty
			if (![theRef isEqualToString:@""]) {
				[referenceLinks addObject:theRef];
			}
		}
	}];
	//create an immutable array safe for returning
	NSArray *returnArray = @[];
	//see if we found anything
	if (referenceLinks && ([referenceLinks count] > 0)) {
		returnArray = [referenceLinks copy];
	}
	return returnArray;
}

@end
