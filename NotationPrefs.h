//
//  NotationPrefs.h
//  Notation
//
//  Created by Zachary Schneirov on 4/1/06.

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
#import "NotationController.h"
#import "NotationTypes.h"

/* this class is responsible for managing all preferences specific to a notational database,
including encryption, file formats, synchronization, passwords management, and others */

#define EPOC_ITERATION 4

extern NSString *NotationPrefsDidChangeNotification;

@interface NotationPrefs : NSObject {
	
	NSUInteger chosenExtIndices[4];
    NSMutableArray *typeStrings[4], *pathExtensions[4];
    OSType *allowedTypes;
	
	@private 
	//masterKey is not to be stored anywhere
	NSData *masterKey;
}

+ (int)appVersion;
+ (NSMutableArray*)defaultTypeStringsForFormat:(int)formatID;
+ (NSMutableArray*)defaultPathExtensionsForFormat:(int)formatID;
- (BOOL)preferencesChanged;
@property (nonatomic, strong) NSColor *foregroundColor;
@property (nonatomic, strong) NSFont *baseBodyFont;

@property (nonatomic, readonly) BOOL firstTimeUsed;
@property (nonatomic, readonly) BOOL preferencesChanged;

@property (nonatomic) BOOL storesPasswordInKeychain;
@property (nonatomic) NVDatabaseFormat notesStorageFormat;
@property (nonatomic, readonly) BOOL confirmFileDeletion;
@property (nonatomic) BOOL doesEncryption;
@property (nonatomic, readonly) NSDictionary *syncServiceAccounts;
- (NSDictionary*)syncAccountForServiceName:(NSString*)serviceName;
- (NSString*)syncPasswordForServiceName:(NSString*)serviceName;
- (NSUInteger)syncFrequencyInMinutesForServiceName:(NSString*)serviceName;
- (BOOL)syncNotesShouldMergeForServiceName:(NSString*)serviceName;
- (BOOL)syncServiceIsEnabled:(NSString*)serviceName;
@property (nonatomic, readonly) NSUInteger keyLengthInBits;
@property (nonatomic, readonly) NSUInteger hashIterationCount;
@property (nonatomic, readonly) UInt32 epochIteration;
- (BOOL)firstTimeUsed;
@property (nonatomic) BOOL secureTextEntry;

- (void)forgetKeychainIdentifier;
@property (nonatomic, readonly) NSString *keychainDatabaseIdentifier;
- (NSString *)setKeychainDatabaseIdentifier;
- (SecKeychainItemRef)currentKeychainItem;
- (NSData*)passwordDataFromKeychain;
- (void)removeKeychainData;
- (void)setKeychainData:(NSData*)data;

- (void)setPreferencesAreStored;
- (void)setStoresPasswordInKeychain:(BOOL)value;
- (BOOL)canLoadPassphraseData:(NSData*)passData;
- (BOOL)canLoadPassphrase:(NSString*)pass;
- (void)setPassphraseData:(NSData*)passData inKeychain:(BOOL)inKeychain;
- (void)setPassphraseData:(NSData *)passData inKeychain:(BOOL)inKeychain withIterations:(NSInteger)iterationCount;
- (BOOL)encryptDataInNewSession:(NSMutableData*)data;
- (BOOL)decryptDataWithCurrentSettings:(NSMutableData*)data;
- (NSData*)WALSessionKey;

- (BOOL)shouldDisplaySheetForProposedFormat:(NSInteger)proposedFormat;
- (void)noteFilesCleanupSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo;
- (void)setConfirmsFileDeletion:(BOOL)value;
- (const char*)keychainSyncAccountNameForService:(NSString*)serviceName;
- (void)setSyncUsername:(NSString*)username forService:(NSString*)serviceName;
- (void)setSyncPassword:(NSString*)password forService:(NSString*)serviceName;
- (void)setSyncFrequency:(NSUInteger)frequencyInMinutes forService:(NSString*)serviceName;
- (void)setSyncEnabled:(BOOL)isEnabled forService:(NSString*)serviceName;
- (void)setSyncShouldMerge:(BOOL)shouldMerge inCurrentAccountForService:(NSString*)serviceName;
- (void)removeSyncPasswordForService:(NSString*)serviceName;

- (UInt32)tableIndexOfDiskUUID:(CFUUIDRef)UUIDRef;
- (void)checkForKnownRedundantSyncConduitsAtPath:(NSString*)dbPath;

+ (NSString*)pathExtensionForFormat:(NSInteger)format;

//used to view tableviews
- (NSString*)typeStringAtIndex:(NSInteger)typeIndex;
- (NSString*)pathExtensionAtIndex:(NSInteger)pathIndex;
- (NSUInteger)indexOfChosenPathExtension;
- (NSString*)chosenPathExtensionForFormat:(NSInteger)format;
- (NSUInteger)typeStringsCount;
- (NSUInteger)pathExtensionsCount;

//used to edit tableviews
- (void)addAllowedPathExtension:(NSString*)extension;
- (BOOL)removeAllowedPathExtensionAtIndex:(NSUInteger)extensionIndex;
- (BOOL)setChosenPathExtensionAtIndex:(NSUInteger)extensionIndex;
- (BOOL)addAllowedType:(NSString*)type;
- (void)removeAllowedTypeAtIndex:(NSUInteger)index;
- (BOOL)setExtension:(NSString*)newExtension atIndex:(unsigned int)oldIndex;
- (BOOL)setType:(NSString*)newType atIndex:(unsigned int)oldIndex;

- (BOOL)pathExtensionAllowed:(NSString *)anExtension forFormat:(NSInteger)formatID;

//actually used while searching for files
- (void)updateOSTypesArray;
- (BOOL)catalogEntryAllowed:(NoteCatalogEntry*)catEntry;

@property (nonatomic, weak) id delegate;

@end

@interface NotationPrefs (DelegateMethods)

- (void)databaseEncryptionSettingsChanged;
- (void)syncSettingsChangedForService:(NSString*)serviceName;
- (void)databaseSettingsChangedFromOldFormat:(int)oldFormat;

@end
