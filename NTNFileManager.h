//
//  NTNFileManager.h
//  Notation
//
//  Created by Zachary Waldowski on 1/15/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import "NotationPrefs.h"

@class NoteObject;
@class NoteCatalogEntry;

@protocol NTNFileManager <NSObject>

- (NSString *)uniqueFilenameForTitle:(NSString *)title fromNote:(NoteObject *)note;

@property(nonatomic, readonly) long blockSize;
@property(nonatomic, readonly) NSUInteger diskUUIDIndex;

- (OSStatus)fileInNotesDirectory:(FSRef *)childRef isOwnedByUs:(BOOL *)owned hasCatalogInfo:(FSCatalogInfo *)info;

- (NSMutableData *)dataFromFileInNotesDirectory:(FSRef *)childRef forFilename:(NSString *)filename;

- (OSStatus)noteFileRenamed:(FSRef *)childRef fromName:(NSString *)oldName toName:(NSString *)newName;

- (NSURL *)notesDirectoryContainsFile:(NSString *)filename returningFSRef:(FSRef *)childRef;
- (NSURL *)notesDirectoryContainsFile:(NSString *)filename;

- (OSStatus)refreshFileRefIfNecessary:(FSRef *)childRef withName:(NSString *)filename charsBuffer:(UniChar *)charsBuffer;

- (OSStatus)createFileIfNotPresentInNotesDirectory:(FSRef *)childRef forFilename:(NSString *)filename fileWasCreated:(BOOL *)created;

- (NSURL *)writeDataToNotesDirectory:(NSData *)data withName:(NSString *)filename verifyUsingBlock:(BOOL(^)(NSURL *, NSError **))block error:(NSError **)outError;

- (NSMutableData *)dataFromFileInNotesDirectory:(FSRef *)childRef forCatalogEntry:(NoteCatalogEntry *)catEntry;

- (OSStatus)moveFileToTrash:(FSRef *)childRef forFilename:(NSString *)filename;

@end
