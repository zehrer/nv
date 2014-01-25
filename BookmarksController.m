//
//  BookmarksController.m
//  Notation
//
//  Created by Zachary Schneirov on 1/21/07.

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


#import "BookmarksController.h"
#import "NoteObject.h"
#import "GlobalPrefs.h"
#import "AppController.h"
#import "NSString_NV.h"
#import "NSCollection_utils.h"

static NSString *BMSearchStringKey = @"SearchString";
static NSString *BMNoteUUIDStringKey = @"NoteUUIDString";

@interface NoteBookmark ()

@property (nonatomic, weak) BookmarksController *controller;

@end

@implementation NoteBookmark

- (id)initWithDictionary:(NSDictionary*)aDict {
	if (aDict) {
		NSString *uuidString = aDict[BMNoteUUIDStringKey];
		if (uuidString) {
			return (self = [self initWithNoteUUID:[[NSUUID alloc] initWithUUIDString:uuidString] searchString:aDict[BMSearchStringKey]]);
		} else {
			NSLog(@"NoteBookmark init: supplied nil uuidString");
		}
	} else {
		NSLog(@"NoteBookmark init: supplied nil dictionary; couldn't init");
	}
	return nil;
}

- (id)initWithNoteUUID:(NSUUID *)aUUID searchString:(NSString*)aString {
	if ((self = [super init])) {
		UUID = aUUID;
		searchString = [aString copy];
	}
	
	return self;
}

- (id)initWithNoteObject:(NoteObject*)aNote searchString:(NSString*)aString {
	if (!aNote) {
		NSLog(@"NoteBookmark init: supplied nil note");
		return nil;
	}
    
	if ((self = [super init])) {
		noteObject = aNote;
		searchString = [aString copy];
		UUID = aNote.uniqueNoteID;
	}
	return self;
}


- (NSString*)searchString {
	return searchString;
}

- (void)validateNoteObject {
	NoteObject *newNote = nil;
	
	//if we already had a valid note and our uuidBytes don't resolve to the same note
	//then use that new note from the delegate. in 100% of the cases newNote should be nil
	if (noteObject && (newNote = [self.controller noteWithUUID:UUID]) != noteObject) {
		noteObject = newNote;
	}
}

- (NoteObject*)noteObject {
	if (!noteObject) noteObject = [self.controller noteWithUUID:UUID];
	return noteObject;
}

- (NSDictionary*)dictionaryRep {
	return @{BMSearchStringKey: searchString,
		BMNoteUUIDStringKey: UUID.UUIDString};
}

- (NSString *)description {
	NoteObject *note = [self noteObject];
	if (note) {
		NSString *title = note.titleString;
		return [searchString length] ? [NSString stringWithFormat:@"%@ [%@]", title, searchString] : title;
	}
	return nil;
}

- (NSUInteger)hash {
    return [noteObject hash];
}

@end


#define MovedBookmarksType @"NVMovedBookmarksType"

@implementation BookmarksController

- (id)init {
	if ((self = [super init])) {
		bookmarks = [[NSMutableArray alloc] init];
		isSelectingProgrammatically = isRestoringSearch = NO;
		
		prefsController = [GlobalPrefs defaultPrefs];
	}
	return self;
}

- (void)awakeFromNib {
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tableViewSelectionDidChange:) 
												   name:NSTableViewSelectionDidChangeNotification object:bookmarksTableView];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(tableViewSelectionDidChange:) 
												 name:NSTableViewSelectionIsChangingNotification object:bookmarksTableView];
//	[window setFloatingPanel:YES];
	[window setDelegate:self];
	[bookmarksTableView setDelegate:self];
	[bookmarksTableView setTarget:self];
	[bookmarksTableView setDoubleAction:@selector(doubleClicked:)];
	
	[bookmarksTableView registerForDraggedTypes:@[MovedBookmarksType]];
}

- (void)dealloc {
	[window setDelegate:nil];
	[bookmarksTableView setDelegate:nil];
	[bookmarks makeObjectsPerformSelector:@selector(setDelegate:) withObject:nil];
	
}

- (id)initWithBookmarks:(NSArray*)array {
	if ((self = [self init])) {
		unsigned int i;
		for (i=0; i<[array count]; i++) {
			NSDictionary *dict = array[i];
			NoteBookmark *bookmark = [[NoteBookmark alloc] initWithDictionary:dict];
            if (bookmark) {
                bookmark.controller = self;
                [bookmarks addObject:bookmark];
            }
		}
	}

	return self;
}

- (NSArray*)dictionaryReps {
	
	NSMutableArray *array = [NSMutableArray arrayWithCapacity:[bookmarks count]];
	unsigned int i;
	for (i=0; i<[bookmarks count]; i++) {
		NSDictionary *dict = [bookmarks[i] dictionaryRep];
		if (dict) [array addObject:dict];
	}
	
	return array;
}

- (void)setDataSource:(id<BookmarksControllerDataSource>)dataSource
{
	_dataSource = dataSource;
	[bookmarks makeObjectsPerformSelector:@selector(validateNoteObject)];
}

- (NoteObject*)noteWithUUID:(NSUUID *)UUID {
	
	return [self.dataSource noteForUUID:UUID];
}

- (void)removeBookmarkForNote:(NoteObject*)aNote {
	unsigned int i;

	for (i=0; i<[bookmarks count]; i++) {
		if ([bookmarks[i] noteObject] == aNote) {
			[bookmarks removeObjectAtIndex:i];
			
			[self updateBookmarksUI];
			break;
		}
	}
}


- (void)regenerateBookmarksMenu {
	
	NSMenu *menu = [NSApp mainMenu];
	NSMenu *bookmarksMenu = [[menu itemWithTag:103] submenu];
	while ([bookmarksMenu numberOfItems]) {
		[bookmarksMenu removeItemAtIndex:0];
	}
	
	
	NSMenu *menu2 = [self.delegate statBarMenu];
	NSMenu *bkSubMenu = [[menu2  itemWithTag:901] submenu];
	while ([bkSubMenu numberOfItems]) {
		[bkSubMenu removeItemAtIndex:0];
	}
		
	NSMenuItem *theMenuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Show Bookmarks",@"menu item title for showing bookmarks") 
														  action:@selector(showBookmarks:) keyEquivalent:@"0"];
	[theMenuItem setTarget:self];
	[bookmarksMenu addItem:theMenuItem];
	theMenuItem = [theMenuItem copy];
	[bkSubMenu addItem:theMenuItem];
	[bookmarksMenu addItem:[NSMenuItem separatorItem]];
	[bkSubMenu addItem:[NSMenuItem separatorItem]];
		
	theMenuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Add to Bookmarks",@"menu item title for bookmarking a note") 
											  action:@selector(addBookmark:) keyEquivalent:@"D"];
	[theMenuItem setTarget:self];
	[bookmarksMenu addItem:theMenuItem];
	theMenuItem = [theMenuItem copy];
	[bkSubMenu addItem:theMenuItem];
	
	if ([bookmarks count] > 0) {
		[bookmarksMenu addItem:[NSMenuItem separatorItem]];
		[bkSubMenu addItem:[NSMenuItem separatorItem]];
	}
	
	unsigned int i;
	for (i=0; i<[bookmarks count]; i++) {

		NoteBookmark *bookmark = bookmarks[i];
		NSString *description = [bookmark description];
		if (description) {
			theMenuItem = [[NSMenuItem alloc] initWithTitle:description action:@selector(restoreBookmark:) 
											   keyEquivalent:[NSString stringWithFormat:@"%d", (i % 9) + 1]];
			if (i > 8) [theMenuItem setKeyEquivalentModifierMask:NSCommandKeyMask | NSShiftKeyMask];
			if (i > 17) [theMenuItem setKeyEquivalentModifierMask:NSCommandKeyMask | NSShiftKeyMask | NSControlKeyMask];
			[theMenuItem setRepresentedObject:bookmark];
			[theMenuItem setTarget:self];
			[bookmarksMenu addItem:theMenuItem];
			theMenuItem = [theMenuItem copy];
			[bkSubMenu addItem:theMenuItem];
		}
	}
}

- (void)updateBookmarksUI {
	
	[prefsController saveCurrentBookmarksFromSender:self];
	
	[self regenerateBookmarksMenu];
	
	[bookmarksTableView reloadData];
}

- (void)selectBookmarkInTableView:(NoteBookmark*)bookmark {
	if (bookmarksTableView && bookmark) {
		//find bookmark index and select
		NSUInteger bmIndex = [bookmarks indexOfObjectIdenticalTo:bookmark];
		if (bmIndex != NSNotFound) {
			isSelectingProgrammatically = YES;
			[bookmarksTableView selectRowIndexes:[NSIndexSet indexSetWithIndex:bmIndex] byExtendingSelection:NO];
			isSelectingProgrammatically = NO;
			[removeBookmarkButton setEnabled:YES];
		}
	}
}

- (BOOL)validateMenuItem:(NSMenuItem*)menuItem {
	//need to fix this for better style detection
	
	SEL action = [menuItem action];
	if (action == @selector(addBookmark:)) {
		
		return ([bookmarks count] < 27 && [self.delegate selectedNoteObject]);
	}
	
	return YES;
}

- (BOOL)restoreNoteBookmark:(NoteBookmark*)bookmark inBackground:(BOOL)inBG{
	if (bookmark) {

		if (currentBookmark != bookmark) {
			currentBookmark = bookmark;
		}
		
		//communicate with revealer here--tell it to search for this string and highlight note
		isRestoringSearch = YES;
		
		//BOOL inBG = ([[window currentEvent] modifierFlags] & NSCommandKeyMask) == 0;
		[self.delegate bookmarksController:self restoreNoteBookmark:bookmark inBackground:inBG];
		[self selectBookmarkInTableView:bookmark];
		
		isRestoringSearch = NO;

		return YES;
	}
	return NO;
}

- (void)restoreBookmark:(id)sender {
	[self restoreNoteBookmark:[sender representedObject] inBackground:NO];
}

- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex {
	if ([[aTableColumn identifier] isEqualToString:@"description"]) {
		NSString *description = [bookmarks[rowIndex] description];
		if (description) 
			return description;
		return [NSString stringWithFormat:NSLocalizedString(@"(Unknown Note) [%@]",nil), [bookmarks[rowIndex] searchString]];
	}
	
	static NSString *shiftCharStr = nil, *cmdCharStr = nil, *ctrlCharStr = nil;
	if (!cmdCharStr) {
		unichar ch = 0x2318;
		cmdCharStr = [NSString stringWithCharacters:&ch length:1];
		ch = 0x21E7;
		shiftCharStr = [NSString stringWithCharacters:&ch length:1];
		ch = 0x2303;
		ctrlCharStr = [NSString stringWithCharacters:&ch length:1];
	}
	
	return [NSString stringWithFormat:@"%@%@%@ %ld", rowIndex > 17 ? ctrlCharStr : @"", rowIndex > 8 ? shiftCharStr : @"", cmdCharStr, (rowIndex % 9) + 1];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
    return self.dataSource ? [bookmarks count] : 0;
}

- (BOOL)tableView:(NSTableView *)aTableView shouldEditTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex {
	return NO;
}

- (void)doubleClicked:(id)sender {
	NSInteger row = [bookmarksTableView selectedRow];
	if (row > -1) [self restoreNoteBookmark:bookmarks[row] inBackground:NO];
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification {
	if (!isRestoringSearch && !isSelectingProgrammatically) {
		NSInteger row = [bookmarksTableView selectedRow];
		if (row > -1) {
			if (bookmarks[row] != currentBookmark) {
				[self restoreNoteBookmark:bookmarks[row] inBackground:YES];
			}
		}
		
		[removeBookmarkButton setEnabled: row > -1];
	}
}

- (BOOL)tableView:(NSTableView *)tv writeRows:(NSArray*)rows toPasteboard:(NSPasteboard*)pboard {
    NSArray *typesArray = @[MovedBookmarksType];
	
	[pboard declareTypes:typesArray owner:self];
    [pboard setPropertyList:rows forType:MovedBookmarksType];
	
    return YES;
}

- (NSDragOperation)tableView:(NSTableView*)tv validateDrop:(id <NSDraggingInfo>)info proposedRow:(NSInteger)row
	   proposedDropOperation:(NSTableViewDropOperation)op {
    
    NSDragOperation dragOp = ([info draggingSource] == bookmarksTableView) ? NSDragOperationMove : NSDragOperationCopy;
	
    [tv setDropRow:row dropOperation:NSTableViewDropAbove];
	
    return dragOp;
}

- (BOOL)tableView:(NSTableView*)tv acceptDrop:(id <NSDraggingInfo>)info row:(NSInteger)row dropOperation:(NSTableViewDropOperation)op {
    if (row < 0)
		row = 0;
    
    if ([info draggingSource] == bookmarksTableView) {
		NSArray *rows = [[info draggingPasteboard] propertyListForType:MovedBookmarksType];
		NSInteger theRow = [rows[0] intValue];
		
		id object = bookmarks[theRow];
		
		if (row != theRow + 1 && row != theRow) {
			NoteBookmark* selectedBookmark = nil;
			NSInteger selRow = [bookmarksTableView selectedRow];
			if (selRow > -1) selectedBookmark = bookmarks[selRow];
			
			if (row < theRow)
				[bookmarks removeObjectAtIndex:theRow];
			
			if (row <= (int)[bookmarks count])
				[bookmarks insertObject:object atIndex:row];
			else
				[bookmarks addObject:object];
			
			if (row > theRow)
				[bookmarks removeObjectAtIndex:theRow];
			
			
			[self updateBookmarksUI];
			[self selectBookmarkInTableView:selectedBookmark];
			
			return YES;
		}
		return NO;
    }
	
	return NO;
}

- (NSRect)windowWillUseStandardFrame:(NSWindow *)sender defaultFrame:(NSRect)defaultFrame {
	
	float oldHeight = 0.0;
	float newHeight = 0.0;
	NSRect newFrame = [sender frame];
	NSSize intercellSpacing = [bookmarksTableView intercellSpacing];
	
	newHeight = MAX(1, [bookmarksTableView numberOfRows]) * ([bookmarksTableView rowHeight] + intercellSpacing.height);
	oldHeight = [[[bookmarksTableView enclosingScrollView] contentView] frame].size.height;
	newHeight = [sender frame].size.height - oldHeight + newHeight;
	
	//adjust origin so the window sticks to the upper left
	newFrame.origin.y = newFrame.origin.y + newFrame.size.height - newHeight;
	
	newFrame.size.height = newHeight;
	return newFrame;
}

- (void)windowWillClose:(NSNotification *)notification {
	[showHideBookmarksItem setAction:@selector(showBookmarks:)];
	[showHideBookmarksItem setTitle:NSLocalizedString(@"Show Bookmarks",@"menu item title")];
}

- (BOOL)isVisible {
	return [window isVisible];
}

- (void)hideBookmarks:(id)sender {
	
	[window close];	
}

- (void)restoreWindowFromSave {
	if ([[NSUserDefaults standardUserDefaults] boolForKey:@"BookmarksVisible"]) {
		[self loadWindowIfNecessary];
		[window orderBack:nil];
	}
}

- (void)loadWindowIfNecessary {
	if (!window) {
		if (![NSBundle loadNibNamed:@"SavedSearches" owner:self])  {
			NSLog(@"Failed to load SavedSearches.nib");
			NSBeep();
			return;
		}
		[bookmarksTableView setDataSource:self];
		[bookmarksTableView reloadData];
	}	
}

- (void)showBookmarks:(id)sender {
	[self loadWindowIfNecessary];
	
	[bookmarksTableView reloadData];
	[window makeKeyAndOrderFront:self];
	
	showHideBookmarksItem = sender;
	[sender setAction:@selector(hideBookmarks:)];
	[sender setTitle:NSLocalizedString(@"Hide Bookmarks",@"menu item title")];

	//highlight searches as appropriate while the window is open
	//selecting a search restores it
}

- (void)clearAllBookmarks:(id)sender {
	if (NSRunAlertPanel(NSLocalizedString(@"Remove all bookmarks?",@"alert title when clearing bookmarks"), 
						NSLocalizedString(@"You cannot undo this action.",nil), 
						NSLocalizedString(@"Remove All Bookmarks",nil), NSLocalizedString(@"Cancel",nil), NULL) == NSAlertDefaultReturn) {

		[bookmarks removeAllObjects];
	
		[self updateBookmarksUI];
	}
}

- (void)addBookmark:(id)sender {
	
	if (![self.delegate selectedNoteObject]) {
		
		NSRunAlertPanel(NSLocalizedString(@"No note selected.",@"alert title when bookmarking no note"), NSLocalizedString(@"You must select a note before it can be added as a bookmark.",nil), NSLocalizedString(@"OK",nil), nil, NULL);
		
	} else if ([bookmarks count] < 27) {
		NSString *newString = [[self.delegate fieldSearchString] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
		
		NoteBookmark *bookmark = [[NoteBookmark alloc] initWithNoteObject:[self.delegate selectedNoteObject] searchString:newString];
		if (bookmark) {
			
			NSUInteger existingIndex = [bookmarks indexOfObject:bookmark];
			if (existingIndex != NSNotFound) {
				//show them what they've already got
				NoteBookmark *existingBookmark = bookmarks[existingIndex];
				if ([window isVisible]) [self selectBookmarkInTableView:existingBookmark];
			} else {
				bookmark.controller = self;
				[bookmarks addObject:bookmark];
				[self updateBookmarksUI];
				if ([window isVisible]) [self selectBookmarkInTableView:bookmark];
			}
		}
	} else {
		//there are only so many numbers and modifiers
		NSRunAlertPanel(NSLocalizedString(@"Too many bookmarks.",nil), NSLocalizedString(@"You cannot create more than 26 bookmarks. Try removing some first.",nil), NSLocalizedString(@"OK",nil), nil, NULL);
	}
}

- (void)removeBookmark:(id)sender {
	
	NoteBookmark *bookmark = nil;
	NSInteger row = [bookmarksTableView selectedRow];
	if (row > -1) {
		bookmark = bookmarks[row];
		[bookmarks removeObjectIdenticalTo:bookmark];
		[self updateBookmarksUI];
	}
}

@end
