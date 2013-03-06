//
//  NTNMainWindowController.m
//  Notation
//
//  Created by Zachary Waldowski on 2/22/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import "NTNMainWindowController.h"
#import "NTNSplitView.h"
#import "NTNEditorStatusView.h"
#import "GlobalPrefs.h"
#import "NTNNotesListTableView.h"
#import "NTNDualTextField.h"
#import "NoteObject.h"
#import "NTNEditorView.h"
#import "NotationController.h"

NSString *const NTNTextFindContextDidChangeNotification = @"NTNTextFindContextDidChangeNotification";
NSString *const NTNTextEditorDidChangeContentsNotification = @"NTNTextEditorDidChangeContentsNotification";

@interface NTNMainWindowController () <NSWindowDelegate, NSToolbarDelegate, NSTextFieldDelegate, NTNSplitViewDelegate, GlobalPrefsResponder, NSTableViewDelegate> {
	NSLayoutManager *_layoutManager;
	BOOL _searchTextIsCached;
}

@property (nonatomic, readonly) NSLayoutManager *layoutManager;
@property (nonatomic, copy) NSString *cachedSearchText;

#warning TODO
@property (nonatomic) BOOL dualFieldIsVisible;

#warning TODO
@property (nonatomic) BOOL isFilteringFromTyping;

#warning TODO
@property (nonatomic) BOOL isCreatingNote;

#warning TODO
@property (nonatomic, strong) NoteObject *currentNote;

@end

@implementation NTNMainWindowController

- (id)init {
	return [self initWithWindowNibName: NSStringFromClass([self class])];
}

- (id)initWithWindow:(NSWindow *)window
{
    self = [super initWithWindow:window];
    if (self) {
        // Initialization code here.
    }
    
    return self;
}

- (void)awakeFromNib {
	[super awakeFromNib];
	
	[self.splitView setAutosaveName: @"nvALTMainSplitView"];
    [self.splitView setMinSize:150 ofSubviewAtIndex:0];
	[self.splitView setMinSize:200 ofSubviewAtIndex:1];
	[self.splitView setMaxSize:600 ofSubviewAtIndex:0];
	[self.splitView setCanCollapse:YES subviewAtIndex:0];
	[self.splitView setDividerThickness: 9.75];

	[[GlobalPrefs defaultPrefs] registerWithTarget: self forChangesInSettings: @selector(setHorizontalLayout:sender:), nil];
}

- (void)windowDidLoad
{
    [super windowDidLoad];

	self.notesListStatusView.notesNumber = NSNotFound;
	self.editorStatusView.notesNumber = -1;
	self.notesListStatusView.backgroundColor = [NSColor controlBackgroundColor];
	self.editorStatusView.backgroundColor = [NSColor controlBackgroundColor];

	[self ntn_configureDividerForCurrentLayout];
    // Implement this method to handle any initialization after your window controller's window has been loaded from its nib file.
}

#pragma mark - Actions

- (IBAction)focusOnSearchField:(id)sender {
	
}

- (void)ntn_configureDividerForCurrentLayout {
	BOOL horiz = [[GlobalPrefs defaultPrefs] horizontalLayout];

	if (self.notesListIsCollapsed) {
		self.notesListScrollView.hidden = NO;
		[self.splitView adjustSubviews];
		self.splitView.vertical = horiz;
		self.notesListScrollView.hidden = YES;
	} else {
		self.splitView.vertical = horiz;
		/*if (![self dualFieldIsVisible]) {
			[self setDualFieldIsVisible:YES];
		}*/
	}

	self.notesListTableView.gridStyleMask = [[GlobalPrefs defaultPrefs] showGrid] ? NSTableViewSolidHorizontalGridLineMask : NSTableViewGridNone;
	self.notesListTableView.usesAlternatingRowBackgroundColors = [[GlobalPrefs defaultPrefs] alternatingRows];
}

- (void)ntn_editorViewUpdate {
	[[NSNotificationCenter defaultCenter] postNotificationName: NTNTextEditorDidChangeContentsNotification object:self];
}

- (void)ntn_updateWordCount {
#warning TODO
}

- (void)ntn_updateWordCount:(BOOL)shouldDoIt {
#warning TODO
}

- (void)ntn_updateRTL {
	if ([[GlobalPrefs defaultPrefs] rtl]) {
		[self.editorView setBaseWritingDirection:NSWritingDirectionRightToLeft range:NSMakeRange(0, self.editorView.string.length)];
	} else {
		[self.editorView setBaseWritingDirection:NSWritingDirectionLeftToRight range:NSMakeRange(0, self.editorView.string.length)];
	}
}

- (void)ntn_setStatusViewVisible:(BOOL)visible {

	[self ntn_editorViewUpdate];
	[self ntn_updateWordCount:(![[GlobalPrefs defaultPrefs] showWordCount])];
	//self.editorView.hidden = visible;
	self.editorStatusView.hidden = !visible;

	if (visible) {
		self.editorStatusView.notesNumber = self.notesListTableView.numberOfSelectedRows;
		if (self.notesListIsCollapsed) {
#warning TODO
			//[self toggleCollapse:self];
		}
	}
}

- (BOOL)ntn_displayContentsForSelectedNote {
	NoteObject *note = self.notesListController.selectedObjects[0];
	if ([note isEqual: self.currentNote]) return NO;

	GlobalPrefs *prefs = [GlobalPrefs defaultPrefs];

	[self ntn_setStatusViewVisible: NO];
	//[self.dualField setShowsDocumentIcon: YES];
	
	// actually load the new note
	self.currentNote = note;


	NSRange firstFoundTermRange = NSMakeRange(NSNotFound, 0);
	NSRange noteSelectionRange = self.currentNote.selectedRange;

	if (noteSelectionRange.location == NSNotFound || NSMaxRange(noteSelectionRange) > note.contentString.length) {
		//revert to the top; selection is invalid
		noteSelectionRange = NSMakeRange(0, 0);
	}

	if (!self.editorView.didRenderFully) {
		[self.editorView setNeedsDisplayInRect: self.editorView.visibleRect avoidAdditionalLayout:YES];
	}

	//restore string
	self.editorView.textStorage.attributedString = self.currentNote.contentString;
	
	[self ntn_editorViewUpdate];
	[self ntn_updateWordCount:(!prefs.showWordCount)];

	//highlight terms--delay this, too

	if (self.notesListTableView.selectedRow != self.notationController.preferredSelectedNoteIndex)
		firstFoundTermRange = [self.editorView highlightTermsTemporarilyReturningFirstRange: self.cachedSearchText avoidHighlight: !prefs.highlightSearchTerms];

	//if there was nothing selected, select the first found range
	if (!noteSelectionRange.length && firstFoundTermRange.location != NSNotFound)
		noteSelectionRange = firstFoundTermRange;

	//select and scroll
	[self.editorView setAutomaticallySelectedRange:noteSelectionRange];
	[self.editorView scrollRangeToVisible:noteSelectionRange];

	[self ntn_updateRTL];

	return YES;
#warning TODO
}

- (void)ntn_processChangedSelectionForTableView:(NTNNotesListTableView *)tableView {
	if ([tableView isEqual: self.notesListTableView]) {
		if (tableView.selectedRowIndexes.count == 1) {
			// if it is uncached, cache the typed string only if we are selecting a note
			[self ntn_cacheSearchStringIfNecessary];

			//add snapback-button here?
			if (!self.isFilteringFromTyping && !self.isCreatingNote)
				self.dualField.snapbackText = self.cachedSearchText;

			if ([self ntn_displayContentsForSelectedNote]) {
				//there doesn't seem to be any situation in which a note will be selected
				//while the user is typing and auto-completion is disabled, so should be OK
				if (!self.isFilteringFromTyping) {
					if (self.dualFieldIsVisible) {
						NSTextView *fieldEditor = (id)self.dualField.currentEditor;
						if (fieldEditor) {
							//the field editor has focus--select text, too
							fieldEditor.string = self.currentNote.title;
							NSUInteger strLen = self.currentNote.title.length;
							if (strLen != fieldEditor.selectedRange.length)
								fieldEditor.selectedRange = NSMakeRange(0, strLen);
						} else {
							self.dualField.stringValue = self.currentNote.title;
						}
					} else {
						self.window.title = self.currentNote.title;
					}
				}
			}
			return;
		}
	}

	if (!self.isFilteringFromTyping) {
		if (self.currentNote) {
			/*//selected nothing and something is currently selected
			 [self _setCurrentNote:nil];
			 [field setShowsDocumentIcon:NO];

			 if (typedStringIsCached) {
			 //restore the un-selected state, but only if something had been first selected to cause that state to be saved
			 [field setStringValue:typedString];
			 }
			 [textView setString:@""];*/
		}

		self.dualFieldIsVisible = YES;
		[self.window.contentView setNeedsDisplay: YES];

		if (!self.currentNote) {
			/*if (selectedRow == -1 && (!fieldEditor || [window firstResponder] != fieldEditor)) {
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
			 }*/
		}
	}

	[self ntn_setStatusViewVisible: (self.currentNote == nil)];
	//[self.dualField setShowsDocumentIcon:currentNote != nil];

}

#pragma mark - Accessors

- (void)setNotationController:(NotationController *)notationController {
	_notationController = notationController;
	if (_notationController) {
		self.notesListStatusView.hidden = YES;
	}
}

- (NSLayoutManager *)layoutManager {
	if (!_layoutManager) {
		_layoutManager = [NSLayoutManager new];
	}
	return _layoutManager;
}

- (void)ntn_cacheSearchStringIfNecessary {
	if (!_searchTextIsCached) {
		self.cachedSearchText = self.dualField.stringValue;
		_searchTextIsCached = YES;
	}
}

- (NSString *)cachedSearchText {
	if (_searchTextIsCached) return _cachedSearchText;
	return nil;
}

- (void)setCurrentNote:(NoteObject *)aNote {
	//save range of old current note
	//we really only want to save the insertion point position if it's currently invisible
	//how do we test that?
	BOOL wasAutomatic = NO;
	NSRange currentRange = [self.editorView getSelectedRangeWasAutomatic: &wasAutomatic];
	if (!wasAutomatic) self.currentNote.selectedRange = currentRange;

	//regenerate content cache before switching to new note
	[self.currentNote updateContentCacheCStringIfNecessary];

	_currentNote = aNote;
}

- (BOOL)notesListIsCollapsed {
	return [self.splitView isSubviewCollapsed: self.notesListScrollView.superview];
}

#pragma mark - GlobalPrefsResponder

- (void)settingChangedForSelectorString:(NSString *)selectorString {
	if ([selectorString isEqualToString: NSStringFromSelector(@selector(setHorizontalLayout:sender:))]) {
		CGFloat colW = self.notesListScrollView.frame.size.width;
		if (![self.splitView isVertical]) {
			colW += 30.0f;
		} else {
			colW -= 30.0f;
		}

		[self ntn_configureDividerForCurrentLayout];

		/*	if ([mainView isInFullScreenMode]) {
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
		 [notesTableView setNeedsDisplay];*/
	} else if ([selectorString isEqualToString: NSStringFromSelector(@selector(setShowGrid:sender:))]) {
		self.notesListTableView.gridStyleMask = [[GlobalPrefs defaultPrefs] showGrid] ? NSTableViewSolidHorizontalGridLineMask : NSTableViewGridNone;
	} else if ([selectorString isEqualToString: NSStringFromSelector(@selector(setAlternatingRows:sender:))]) {
		self.notesListTableView.usesAlternatingRowBackgroundColors = [[GlobalPrefs defaultPrefs] alternatingRows];
	}
}

#pragma mark - NSWindowDelegate

#pragma mark - NSToolbarDelegate

#pragma mark - NSTextFieldDelegate

#pragma mark - NTNSplitViewDelegate

#pragma mark - NSTableViewDelegate

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row {
	GlobalPrefs *prefs = [GlobalPrefs defaultPrefs];
	BOOL horiz = [prefs horizontalLayout];
	NSFont *font = [NSFont systemFontOfSize: [prefs tableFontSize]];
	
	CGFloat tableFontHeight = [self.layoutManager defaultLineHeightForFont:font];
	CGFloat h[4] = {(tableFontHeight * 3.0 + 5.0f), (tableFontHeight * 2.0 + 6.0f), (tableFontHeight + 2.0f), tableFontHeight + 2.0f};
	return horiz ? ([prefs tableColumnsShowPreview] ? h[0] : (ColumnIsSet(NoteLabelsColumn, [prefs tableColumnsBitmap]) ? h[1] : h[2])) : h[3];
}

- (void)tableViewSelectionIsChanging:(NSNotification *)notification {
	NTNNotesListTableView *tableView = notification.object;

	BOOL allowMultipleSelection = NO;
	NSEvent *event = self.window.currentEvent;

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

	if (allowMultipleSelection != tableView.allowsMultipleSelection) {
		//we may need to hack some hidden NSTableView instance variables to improve mid-drag flags-changing
		//NSLog(@"set allows mult: %d", allowMultipleSelection);
		tableView.allowsMultipleSelection = allowMultipleSelection;

		//we need this because dragging a selection back to the same note will nto trigger a selectionDidChange notification
		dispatch_async(dispatch_get_main_queue(), ^{
			tableView.allowsMultipleSelection = YES;
		});
	}

	if (![tableView isEqual: self.window.firstResponder]) {
		// occasionally changing multiple selection ability in-between selecting multiple items causes total deselection
		[self.window makeFirstResponder: tableView];
	}
}

- (void)tableViewSelectionDidChange:(NSNotification *)notification {
	NTNNotesListTableView *tableView = notification.object;

	[[NSNotificationCenter defaultCenter] postNotificationName: NTNTextFindContextDidChangeNotification object:self];
	
	NSEventType type = self.window.currentEvent.type;
	if (type != NSKeyDown && type != NSKeyUp) {
		dispatch_async(dispatch_get_main_queue(), ^{
			tableView.allowsMultipleSelection = YES;
		});
	}

	[self ntn_processChangedSelectionForTableView: tableView];
}

@end
