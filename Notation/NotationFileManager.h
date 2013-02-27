//
//  NotationFileManager.h
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


#import "NotationController.h"
#import "BufferUtils.h"
#import "NTNFileManager.h"

extern NSString *NotesDatabaseFileName;

@interface NotationController (NotationFileManager) <NTNFileManager>

- (void)initializeDiskUUIDIfNecessary;

- (BOOL)notesDirectoryIsTrashed;

- (BOOL)renameAndForgetNoteDatabaseFile:(NSString *)newfilename;

- (BOOL)removeSpuriousDatabaseFileNotes;

- (void)relocateNotesDirectory;

- (NSString *)uniqueFilenameForTitle:(NSString *)title fromNote:(NoteObject *)note;

- (void)notifyOfChangedTrash;

@end
