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

@property(nonatomic, readonly) NSUInteger diskUUIDIndex;

- (BOOL)fileInNotesDirectoryIsOwnedByUs:(NSURL *)URL;

- (OSStatus)fileInNotesDirectory:(FSRef *)childRef isOwnedByUs:(BOOL *)owned hasCatalogInfo:(FSCatalogInfo *)info;

- (NSMutableData *)dataFromFileInNotesDirectory:(FSRef *)childRef forFilename:(NSString *)filename;
- (NSMutableData *)dataFromFileInNotesDirectory:(FSRef *)childRef forCatalogEntry:(NoteCatalogEntry *)catEntry;

- (OSStatus)noteFileRenamed:(FSRef *)childRef fromName:(NSString *)oldName toName:(NSString *)newName;

- (NSURL *)notesDirectoryContainsFile:(NSString *)filename returningFSRef:(FSRef *)childRef;
- (NSURL *)notesDirectoryContainsFile:(NSString *)filename;

- (OSStatus)refreshFileRefIfNecessary:(FSRef *)childRef withName:(NSString *)filename charsBuffer:(UniChar *)charsBuffer;

- (NSURL *)refreshFileURLIfNecessary:(NSURL *)URL withName:(NSString *)filename error: (NSError **)err;

- (OSStatus)createFileIfNotPresentInNotesDirectory:(FSRef *)childRef forFilename:(NSString *)filename fileWasCreated:(BOOL *)created;
- (NSURL *)createFileWithNameIfNotPresentInNotesDirectory:(NSString *)filename created:(BOOL *)created error: (out NSError **)outError;

- (NSURL *)writeDataToNotesDirectory:(NSData *)data withName:(NSString *)filename verifyUsingBlock:(BOOL(^)(NSURL *, NSError **))block error:(NSError **)outError;

- (NSURL *)moveFileToTrash:(NSURL *)childURL forFilename:(NSString *)filename error:(out NSError **)outError;

- (NSURL *)URLForFileInNotesDirectory:(NSString *)filename;

@end
