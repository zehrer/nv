//
//  NotationController+DataSource.m
//  Notation
//
//  Created by Zach Waldowski on 7/8/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import "NotationController+DataSource.h"
#import "NotesTableView.h"
#import "NoteAttributeColumn.h"
#import "GlobalPrefs.h"
#import "NoteObject.h"
#import "UnifiedCell.h"
#import "LabelColumnCell.h"

@implementation NotationController (DataSource)

- (void)tableView:(NotesTableView *)tv setObjectValue:(id)value forTableColumn:(NoteAttributeColumn *)col row:(NSInteger)row {
	NoteObject *note = self.filteredNotes[row];
	
	if (col.attribute == NVUIAttributeTitle) {
		if (prefsController.horizontalLayout && tv.lastEventActivatedTagEdit) {
			[note setLabelString:value];
		} else {
			[note setTitleString:value];
		}
	} else if (col.attribute == NVUIAttributeLabels) {
		[note setLabelString:value];
	}
}

- (id)tableView:(NotesTableView *)tv objectValueForTableColumn:(NoteAttributeColumn *)col row:(NSInteger)row {
	NoteObject *note = self.filteredNotes[row];
	
	switch (col.attribute) {
		case NVUIAttributeTitle: {
			if (prefsController.horizontalLayout) {
				if (prefsController.tableColumnsShowPreview) {
					UnifiedCell *cell = [col dataCellForRow:row];
					[cell setNoteObject:note];
					[cell setPreviewIsHidden:NO];
					return [tv isRowSelected:row] ? AttributedStringForSelection(note.tableTitleString, YES) : note.tableTitleString;
				} else {
					return note.tableTitleString;
				}
			} else {
				if (prefsController.tableColumnsShowPreview) {
					return (tv.activeStyle && [tv isRowSelected:row]) ? note.tableTitleString.string : note.tableTitleString;
				} else {
					return note.titleString;
				}
			}
		}
		case NVUIAttributeLabels: {
			LabelColumnCell *cell = [col dataCellForRow:row];
			[cell setNoteObject:note];
			return note.labelString;
		}
		case NVUIAttributeDateModified: {
			return note.modifiedDateString;
		};
		case NVUIAttributeDateCreated: {
			return note.createdDateString;
		};
		default: return nil;
	}
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView {
	return self.filteredNotes.count;
}

@end
