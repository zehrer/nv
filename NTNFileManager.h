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

- (NSMutableData *)dataForFilenameInNotesDirectory:(NSString *)filename URL:(out NSURL **)outURL;
- (NSMutableData *)dataForCatalogEntryInNotesDirectory:(NoteCatalogEntry *)catEntry URL:(out NSURL **)outURL;

- (NSURL *)noteFileRenamed:(NSURL *)noteFileURL fromName:(NSString *)oldName toName:(NSString *)newName error:(out NSError **)outError;

- (NSURL *)notesDirectoryContainsFile:(NSString *)filename returningFSRef:(FSRef *)childRef;
- (NSURL *)notesDirectoryContainsFile:(NSString *)filename;

- (NSURL *)refreshFileURLIfNecessary:(NSURL *)URL withName:(NSString *)filename error: (NSError **)err;

- (NSURL *)createFileWithNameIfNotPresentInNotesDirectory:(NSString *)filename created:(BOOL *)created error: (out NSError **)outError;

- (NSURL *)writeDataToNotesDirectory:(NSData *)data withName:(NSString *)filename verifyUsingBlock:(BOOL(^)(NSURL *, NSError **))block error:(NSError **)outError;

- (NSURL *)moveFileToTrash:(NSURL *)childURL forFilename:(NSString *)filename error:(out NSError **)outError;

- (NSURL *)URLForFileInNotesDirectory:(NSString *)filename;

@end
