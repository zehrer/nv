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


#import <Cocoa/Cocoa.h>
#import "NotationController_Private.h"
#import "BufferUtils.h"
#import "NoteObject.h"

extern NSString *NotesDatabaseFileName;

typedef union VolumeUUID {
	u_int32_t value[2];
	struct {
		u_int32_t high;
		u_int32_t low;
	} v;
} VolumeUUID;


@interface NotationController (NotationFileManager) <NoteObjectDelegate>

@property (nonatomic, strong, readonly) NSFileManager *fileManager;

OSStatus CreateDirectoryIfNotPresent(FSRef *parentRef, CFStringRef subDirectoryName, FSRef *childRef);
CFUUIDRef CopyHFSVolumeUUIDForMount(const char *mntonname);

@property (nonatomic, readonly) UInt32 diskUUIDIndex;
@property (nonatomic, readonly) long blockSize;

- (void)purgeOldPerDiskInfoFromNotes;
- (void)initializeDiskUUIDIfNecessary;

- (BOOL)notesDirectoryIsTrashed;

- (BOOL)notesDirectoryContainsFile:(NSString*)filename returningFSRef:(FSRef*)childRef;
- (OSStatus)refreshFileRefIfNecessary:(FSRef *)childRef withName:(NSString *)filename charsBuffer:(UniChar*)charsBuffer;

- (OSStatus)renameAndForgetNoteDatabaseFile:(NSString*)newfilename;
- (BOOL)removeSpuriousDatabaseFileNotes;

- (void)relocateNotesDirectory;

+ (OSStatus)getDefaultNotesDirectoryRef:(FSRef*)notesDir;

- (NSMutableData*)dataFromFileInNotesDirectory:(FSRef*)childRef forFilename:(NSString*)filename;
- (NSMutableData*)dataFromFileInNotesDirectory:(FSRef*)childRef forCatalogEntry:(NoteCatalogEntry*)catEntry;
- (NSMutableData*)dataFromFileInNotesDirectory:(FSRef*)childRef forFilename:(NSString*)filename fileSize:(UInt64)givenFileSize;
- (OSStatus)noteFileRenamed:(FSRef*)childRef fromName:(NSString*)oldName toName:(NSString*)newName;
- (NSString*)uniqueFilenameForTitle:(NSString*)title fromNote:(NoteObject*)note;
- (OSStatus)fileInNotesDirectory:(FSRef*)childRef isOwnedByUs:(BOOL*)owned hasCatalogInfo:(FSCatalogInfo *)info;
- (OSStatus)deleteFileInNotesDirectory:(FSRef*)childRef forFilename:(NSString*)filename;
- (OSStatus)createFileIfNotPresentInNotesDirectory:(FSRef*)childRef forFilename:(NSString*)filename fileWasCreated:(BOOL*)created;
- (BOOL)writeDataToNotesDirectory:(NSData*)data
							 name:(NSString*)filename
				   destinationRef:(FSRef*)destRef
							error:(out NSError **)outError;;
- (BOOL)writeDataToNotesDirectory:(NSData*)data
							 name:(NSString*)filename
				   destinationRef:(FSRef*)destRef
							error:(out NSError **)outError
				 verifyUsingBlock:(BOOL(^)(NSData *, NSError **))verifier;
+ (OSStatus)trashFolderRef:(FSRef*)trashRef forChild:(FSRef*)childRef;
- (OSStatus)moveFileToTrash:(FSRef *)childRef forFilename:(NSString*)filename;
- (void)notifyOfChangedTrash;
@end
