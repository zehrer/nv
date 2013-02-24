//
//  BookmarksController.h
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

@class NoteObject;

@protocol NoteBookmarkDelegate <NSObject>

- (NoteObject *)noteWithUUIDBytes:(CFUUIDBytes)bytes;

@end

@interface NoteBookmark : NSObject {
	NSString *searchString;
	CFUUIDBytes uuidBytes;
	NoteObject *noteObject;
}

- (id)initWithDictionary:(NSDictionary *)aDict;

- (id)initWithNoteObject:(NoteObject *)aNote searchString:(NSString *)aString;

- (id)initWithNoteUUIDBytes:(CFUUIDBytes)bytes searchString:(NSString *)aString;

- (NSString *)searchString;

- (NoteObject *)noteObject;

- (void)validateNoteObject;

- (NSDictionary *)dictionaryRep;

@property(nonatomic, weak) id <NoteBookmarkDelegate> delegate;

@end

/*
 menu is as follows
 
 Add to Saved Searches (filters duplicates)
 Remove from Saved Searches (enabled as necessary)
 Clear All Saved Searches
 --------
 search string A cmd-1
 search string B cmd-2
 search string C cmd-3
 ...
 search string J cmd-shift-1
 
 
 each item stores both the filter and the last selected note for that filter
 where the last selected note is updated whenever the filter is currently "in-play"
 */

@class GlobalPrefs;
@class BookmarksController;

@protocol BookmarksControllerDelegate <NSObject>

- (void)bookmarksController:(BookmarksController *)controller restoreNoteBookmark:(NoteBookmark *)aBookmark inBackground:(BOOL)inBG;

- (NSMenu *)statBarMenu;

@property (nonatomic, readonly) NoteObject *currentNote;

- (NSString *)fieldSearchString;

@end

@protocol BookmarksControllerDataSource <NSObject>

- (NoteObject *)noteForUUIDBytes:(CFUUIDBytes *)bytes;

@end

@interface BookmarksController : NSObject <NSWindowDelegate, NSTableViewDelegate, NSTableViewDataSource, NoteBookmarkDelegate> {
	//model
	NSMutableArray *bookmarks;

	BOOL isRestoringSearch, isSelectingProgrammatically;

	GlobalPrefs *prefsController;

	IBOutlet NSButton *addBookmarkButton;
	IBOutlet NSButton *removeBookmarkButton;
	IBOutlet NSTableView *bookmarksTableView;
	IBOutlet NSPanel *window;

	NSMenuItem *showHideBookmarksItem;

	NoteBookmark *currentBookmark;
}

- (id)initWithBookmarks:(NSArray *)array;

- (NSArray *)dictionaryReps;

- (NoteObject *)noteWithUUIDBytes:(CFUUIDBytes)bytes;

- (void)removeBookmarkForNote:(NoteObject *)aNote;

- (void)selectBookmarkInTableView:(NoteBookmark *)bookmark;

- (BOOL)restoreNoteBookmark:(NoteBookmark *)bookmark inBackground:(BOOL)inBG;

- (void)restoreBookmark:(id)sender;

- (void)clearAllBookmarks:(id)sender;

- (void)hideBookmarks:(id)sender;

- (void)showBookmarks:(id)sender;

- (void)restoreWindowFromSave;

- (void)loadWindowIfNecessary;

- (void)addBookmark:(id)sender;

- (void)removeBookmark:(id)sender;

- (void)regenerateBookmarksMenu;

- (BOOL)isVisible;

- (void)updateBookmarksUI;

@property(nonatomic, weak) id <BookmarksControllerDelegate> delegate;
@property(nonatomic, weak) id <BookmarksControllerDataSource> dataSource;

@end
