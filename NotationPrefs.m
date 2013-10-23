//
//  NotationPrefs.m
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

#import "AppController.h"
#import "NotationPrefs.h"
#import "GlobalPrefs.h"
#import "NSString_NV.h"
#import "SimplenoteSession.h"
#import "NSCollection_utils.h"
#import "NotationPrefsViewController.h"
#import "NSData_transformations.h"
#import "NotationFileManager.h"
#import "SecureTextEntryManager.h"
#import "DiskUUIDEntry.h"
#import "NSMutableData+NVAESEncryption.h"
#include <CoreServices/CoreServices.h>
#include <ApplicationServices/ApplicationServices.h>

#define DEFAULT_HASH_ITERATIONS 8000
#define DEFAULT_KEY_LENGTH 256

#define KEYCHAIN_SERVICENAME "Notational Velocity"

NSString *NotationPrefsDidChangeNotification = @"NotationPrefsDidChangeNotification";

@interface NotationPrefs ()

@property (nonatomic, strong) NSMutableArray *seenDiskUUIDEntries;
@property (nonatomic, strong) NSData *masterSalt;
@property (nonatomic, strong) NSData *dataSessionSalt;
@property (nonatomic, strong) NSData *verifierKey;
@property (nonatomic, strong) NSMutableDictionary *mutableSyncServiceAccounts;

@end

@implementation NotationPrefs

@synthesize epochIteration = epochIteration;
@synthesize doesEncryption = doesEncryption;
@synthesize storesPasswordInKeychain = storesPasswordInKeychain;
@synthesize secureTextEntry = secureTextEntry;
@synthesize keyLengthInBits = keyLengthInBits;
@synthesize hashIterationCount = hashIterationCount;
@synthesize baseBodyFont = baseBodyFont;
@synthesize foregroundColor = foregroundColor;
@synthesize confirmFileDeletion = confirmFileDeletion;
@synthesize keychainDatabaseIdentifier = keychainDatabaseIdentifier;
@synthesize seenDiskUUIDEntries = seenDiskUUIDEntries;
@synthesize masterSalt = masterSalt;
@synthesize dataSessionSalt = dataSessionSalt;
@synthesize verifierKey = verifierKey;
@synthesize delegate = delegate;
@synthesize mutableSyncServiceAccounts = syncServiceAccounts;
@synthesize firstTimeUsed = firstTimeUsed;
@synthesize preferencesChanged = preferencesChanged;
@synthesize notesStorageFormat = notesStorageFormat;

static NSMutableDictionary *ServiceAccountDictInit(NotationPrefs *prefs, NSString* serviceName) {
	NSMutableDictionary *accountDict = prefs.mutableSyncServiceAccounts[serviceName];
	if (!accountDict) {
		accountDict = [[NSMutableDictionary alloc] init];
		prefs.mutableSyncServiceAccounts[accountDict] = serviceName;
	}
	return accountDict;
}

+ (int)appVersion {
	return [[[NSBundle mainBundle] infoDictionary][@"CFBundleVersion"] intValue];
}

- (id)init {
    if ((self = [super init])) {
		allowedTypes = NULL;
		
		unsigned int i;
		for (i=0; i<4; i++) {
			typeStrings[i] = [NotationPrefs defaultTypeStringsForFormat:i];
			pathExtensions[i] = [NotationPrefs defaultPathExtensionsForFormat:i];
			chosenExtIndices[i] = 0;
		}
		
		confirmFileDeletion = YES;
		storesPasswordInKeychain = secureTextEntry = doesEncryption = NO;
		syncServiceAccounts = [[NSMutableDictionary alloc] init];
		seenDiskUUIDEntries = [[NSMutableArray alloc] init];
		notesStorageFormat = NVDatabaseFormatSingle;
		hashIterationCount = DEFAULT_HASH_ITERATIONS;
		keyLengthInBits = DEFAULT_KEY_LENGTH;
		baseBodyFont = [[GlobalPrefs defaultPrefs] noteBodyFont];
		foregroundColor = [[NSApp delegate] foregrndColor];
		epochIteration = 0;
		
		[self updateOSTypesArray];
		
		firstTimeUsed = preferencesChanged = YES;
		
    }
    return self;
}

- (id)initWithCoder:(NSCoder*)decoder {
    if ([super init]) {
		NSAssert([decoder allowsKeyedCoding], @"Keyed decoding only!");
		
		//if we're initializing from an archive, we've obviously been run at least once before
		firstTimeUsed = NO;
		
		preferencesChanged = NO;
		
		epochIteration = [decoder decodeInt32ForKey:@keypath(self.epochIteration)];
		notesStorageFormat = [decoder decodeIntForKey:@keypath(self.notesStorageFormat)];
		doesEncryption = [decoder decodeBoolForKey:@keypath(self.doesEncryption)];
		storesPasswordInKeychain = [decoder decodeBoolForKey:@keypath(self.storesPasswordInKeychain)];
		secureTextEntry = [decoder decodeBoolForKey:@keypath(self.secureTextEntry)];
		
		if (!(hashIterationCount = [decoder decodeIntForKey:@keypath(self.hashIterationCount)]))
			hashIterationCount = DEFAULT_HASH_ITERATIONS;
		if (!(keyLengthInBits = [decoder decodeIntForKey:@keypath(self.keyLengthInBits)]))
			keyLengthInBits = DEFAULT_KEY_LENGTH;
		
		@try {
			baseBodyFont = [decoder decodeObjectForKey:@keypath(self.baseBodyFont)];
		} @catch (NSException *e) {
			NSLog(@"Error trying to unarchive default base body font (%@, %@)", [e name], [e reason]);
		}
		if (!baseBodyFont || ![baseBodyFont isKindOfClass:[NSFont class]]) {
			baseBodyFont = [[GlobalPrefs defaultPrefs] noteBodyFont];
			NSLog(@"setting base body to current default: %@", baseBodyFont);
			preferencesChanged = YES;
		}
		//foregroundColor does not receive the same treatment as basebodyfont; in the event of a discrepancy between global and per-db settings,
		//the former is applied to the notes in the database, while the latter is restored from the database itself
		@try {
			foregroundColor = [decoder decodeObjectForKey:@keypath(self.foregroundColor)];
		} @catch (NSException *e) {
			NSLog(@"Error trying to unarchive foreground text color (%@, %@)", [e name], [e reason]);
		}
		if (!foregroundColor || ![foregroundColor isKindOfClass:[NSColor class]]) {
			//foregroundColor = [[[GlobalPrefs defaultPrefs] foregroundTextColor] retain];
			
			foregroundColor = [[NSApp delegate] foregrndColor];
			preferencesChanged = YES;
		}
		
		confirmFileDeletion = [decoder decodeBoolForKey:@keypath(self.confirmFileDeletion)];
		
		unsigned int i;
		for (i=0; i<4; i++) {
			
			if (!(typeStrings[i] = [decoder decodeObjectForKey:[NSString stringWithFormat:@"typeStrings.%d", i]]))
				typeStrings[i] = [NotationPrefs defaultTypeStringsForFormat:i];
			if (!(pathExtensions[i] = [decoder decodeObjectForKey:[NSString stringWithFormat:@"pathExtensions.%d", i]]))
				pathExtensions[i] = [NotationPrefs defaultPathExtensionsForFormat:i];
			chosenExtIndices[i] = [decoder decodeIntForKey:[NSString stringWithFormat:@"chosenExtIndices.%d", i]];
		}
		
		if (!(syncServiceAccounts = [[decoder decodeObjectForKey:@keypath(self.syncServiceAccounts)] mutableCopy]))
			syncServiceAccounts = [[NSMutableDictionary alloc] init];
		keychainDatabaseIdentifier = [decoder decodeObjectForKey:@keypath(self.keychainDatabaseIdentifier)];
		
		if (!(seenDiskUUIDEntries = [decoder decodeObjectForKey:@keypath(self.seenDiskUUIDEntries)]))
			seenDiskUUIDEntries = [[NSMutableArray alloc] init];
		
		masterSalt = [decoder decodeObjectForKey:@keypath(self.masterSalt)];
		dataSessionSalt = [decoder decodeObjectForKey:@keypath(self.dataSessionSalt)];
		verifierKey = [decoder decodeObjectForKey:@keypath(self.verifierKey)];
		
		doesEncryption = doesEncryption && verifierKey && masterSalt;
		
		[self updateOSTypesArray];
    }
	
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
	NSAssert([coder allowsKeyedCoding], @"Keyed encoding only!");
	
	/* epochIteration:
	 0: First NSArchiver (was unused--maps to 0)
	 1: First NSKeyedArchiver
	 2: First syncServicesMD and date created/modified syncing to files
	 3: tracking of file size and attribute mod dates, font foreground colors, openmeta labels
	 */
	[coder encodeInt32:EPOC_ITERATION forKey:@keypath(self.epochIteration)];
	
	[coder encodeInteger:notesStorageFormat forKey:@keypath(self.notesStorageFormat)];
	[coder encodeBool:doesEncryption forKey:@keypath(self.doesEncryption)];
	[coder encodeBool:storesPasswordInKeychain forKey:@keypath(self.storesPasswordInKeychain)];
	[coder encodeInteger:hashIterationCount forKey:@keypath(self.hashIterationCount)];
	[coder encodeInteger:keyLengthInBits forKey:@keypath(self.keyLengthInBits)];
	[coder encodeBool:secureTextEntry forKey:@keypath(self.secureTextEntry)];
	
	[coder encodeBool:confirmFileDeletion forKey:@keypath(self.confirmFileDeletion)];
	[coder encodeObject:baseBodyFont forKey:@keypath(self.baseBodyFont)];
	[coder encodeObject:foregroundColor forKey:@keypath(self.foregroundColor)];
	
	NSUInteger i;
	for (i=0; i<4; i++) {	
		[coder encodeObject:typeStrings[i] forKey:[NSString stringWithFormat:@"typeStrings.%lu", (unsigned long)i]];
		[coder encodeObject:pathExtensions[i] forKey:[NSString stringWithFormat:@"pathExtensions.%lu", (unsigned long)i]];
		[coder encodeInteger:chosenExtIndices[i] forKey:[NSString stringWithFormat:@"chosenExtIndices.%lu",(unsigned long)i]];
	}
	
	[coder encodeObject:[self syncServiceAccountsForArchiving] forKey:@keypath(self.syncServiceAccounts)];
	
	[coder encodeObject:keychainDatabaseIdentifier forKey:@keypath(self.keychainDatabaseIdentifier)];
	
	[coder encodeObject:seenDiskUUIDEntries forKey:@keypath(self.seenDiskUUIDEntries)];
	
	[coder encodeObject:masterSalt forKey:@keypath(self.masterSalt)];
	[coder encodeObject:dataSessionSalt forKey:@keypath(self.dataSessionSalt)];
	[coder encodeObject:verifierKey forKey:@keypath(self.verifierKey)];
}


- (void)dealloc {
    if (allowedTypes)
		free(allowedTypes);
}

+ (NSMutableArray*)defaultTypeStringsForFormat:(int)formatID {
    switch (formatID) {
	case NVDatabaseFormatSingle:
	    return [NSMutableArray arrayWithCapacity:0];
	case NVDatabaseFormatPlain:
	    return [NSMutableArray arrayWithObjects:(__bridge_transfer id)UTCreateStringForOSType(TEXT_TYPE_ID),
			(__bridge_transfer id)UTCreateStringForOSType(UTXT_TYPE_ID), nil];
	case NVDatabaseFormatRTF:
	    return [NSMutableArray arrayWithObjects:(__bridge_transfer id)UTCreateStringForOSType(RTF_TYPE_ID), nil];
	case NVDatabaseFormatHTML:
	    return [NSMutableArray arrayWithObjects:(__bridge_transfer id)UTCreateStringForOSType(HTML_TYPE_ID), nil];
	case NVDatabaseFormatDOC:
		return [NSMutableArray arrayWithObjects:(__bridge_transfer id)UTCreateStringForOSType(WORD_DOC_TYPE_ID), nil];
	default:
	    NSLog(@"Unknown format ID: %d", formatID);
    }
    
    return [NSMutableArray arrayWithCapacity:0];
}

+ (NSMutableArray*)defaultPathExtensionsForFormat:(int)formatID {
    switch (formatID) {
	case NVDatabaseFormatSingle:
	    return [NSMutableArray arrayWithCapacity:0];
	case NVDatabaseFormatPlain:
	    return [NSMutableArray arrayWithObjects:@"txt", @"text", @"utf8", @"taskpaper", nil];
	case NVDatabaseFormatRTF:
	    return [NSMutableArray arrayWithObjects:@"rtf", nil];
	case NVDatabaseFormatHTML:
	    return [NSMutableArray arrayWithObjects:@"html", @"htm", nil];
	case NVDatabaseFormatDOC:
		return [NSMutableArray arrayWithObjects:@"doc", nil];
	case NVDatabaseFormatDOCX:
		return [NSMutableArray arrayWithObjects:@"docx", nil];
	default:
	    NSLog(@"Unknown format ID: %d", formatID);
    }
    
    return [NSMutableArray arrayWithCapacity:0];
}

- (NSDictionary*)syncServiceAccounts {
	return [syncServiceAccounts copy];
}

- (NSDictionary*)syncAccountForServiceName:(NSString*)serviceName {
	return syncServiceAccounts[serviceName];
}

- (NSString*)syncPasswordForServiceName:(NSString*)serviceName {
	//if non-existing, fetch from keychain and cache
	
	NSMutableDictionary *accountDict = ServiceAccountDictInit(self, serviceName);
	
	NSString *password = accountDict[@"password"];
	if (password) return password;
	
	//fetch keychain
	void *passwordData = NULL;
	UInt32 passwordLength = 0;
	SecKeychainItemRef returnedItem = NULL;	
	
	const char *kcSyncAccountName = [self keychainSyncAccountNameForService:serviceName];
	if (!kcSyncAccountName) return nil;
	
	OSStatus err = SecKeychainFindGenericPassword(NULL, strlen(KEYCHAIN_SERVICENAME), KEYCHAIN_SERVICENAME,
												  (UInt32)strlen(kcSyncAccountName), kcSyncAccountName, &passwordLength, &passwordData, &returnedItem);
	if (err != noErr) {
		NSLog(@"Error finding keychain password for service account %@: %d\n", serviceName, err);
		return nil;
	}
	password = [[NSString alloc] initWithBytes:passwordData length:passwordLength encoding:NSUTF8StringEncoding];
	
	//cache password found in keychain
	accountDict[@"password"] = password;
	
	SecKeychainItemFreeContent(NULL, passwordData);
	return password;
}

- (NSDictionary*)syncServiceAccountsForArchiving {
	NSMutableDictionary *tempDict = [syncServiceAccounts mutableCopy];
	
	NSEnumerator *enumerator = [tempDict objectEnumerator];
	NSMutableDictionary *account = nil;
	while ((account = [enumerator nextObject])) {
		
		if (![(NSString*)account[@"username"] length]) {
			//don't store the "enabled" flag if the account has no username
			//give password the benefit of the doubt as it may eventually become available via the keychain
			[account removeObjectForKey:@"enabled"];
		}
		[account removeObjectForKey:@"password"];
	}
	return tempDict;
}

- (BOOL)syncNotesShouldMergeForServiceName:(NSString*)serviceName {
	NSDictionary *accountDict = [self syncAccountForServiceName:serviceName];
	NSString *username = accountDict[@"username"];
	return username && [accountDict[@"shouldmerge"] isEqualToString:username];
}

- (NSUInteger)syncFrequencyInMinutesForServiceName:(NSString*)serviceName {
	NSUInteger freq = MIN([[[self syncAccountForServiceName:serviceName] objectForKey:@"frequency"] unsignedIntValue], 30U);
	return freq == 0 ? 5 : freq;
}

- (BOOL)syncServiceIsEnabled:(NSString*)serviceName {
	return [[self syncAccountForServiceName:serviceName][@"enabled"] boolValue];
}

- (void)setPreferencesAreStored {
	preferencesChanged = NO;
}

- (void)setForegroundColor:(NSColor*)aColor {
	foregroundColor = aColor;
	
	preferencesChanged = YES;
}

- (void)setBaseBodyFont:(NSFont*)aFont {
	baseBodyFont = aFont;
		
	preferencesChanged = YES;
}

- (void)forgetKeychainIdentifier {
	
	keychainDatabaseIdentifier = nil;
	
	preferencesChanged = YES;
}

- (NSString *)setKeychainDatabaseIdentifier {
	if (!keychainDatabaseIdentifier) {
		keychainDatabaseIdentifier = [[NSUUID UUID] UUIDString];
		
		preferencesChanged = YES;
	}
	
	return [keychainDatabaseIdentifier copy];
}

- (SecKeychainItemRef)currentKeychainItem {
	SecKeychainItemRef returnedItem = NULL;
	
	const char *accountName = [[self setKeychainDatabaseIdentifier] UTF8String];
	
	OSStatus err = SecKeychainFindGenericPassword(NULL, strlen(KEYCHAIN_SERVICENAME), KEYCHAIN_SERVICENAME,
											 (UInt32)strlen(accountName), accountName, NULL, NULL, &returnedItem);
	if (err != noErr)
		return NULL;
	
	return returnedItem;
}

- (void)removeKeychainData {
	SecKeychainItemRef itemRef = [self currentKeychainItem];
	if (itemRef) {
		OSStatus err = SecKeychainItemDelete(itemRef);
		if (err != noErr)
			NSLog(@"Error deleting keychain item: %d", err);
		CFRelease(itemRef);
	}
}

- (NSData*)passwordDataFromKeychain {
	void *passwordData = NULL;
	UInt32 passwordLength = 0;
	const char *accountName = [[self setKeychainDatabaseIdentifier] UTF8String];
	SecKeychainItemRef returnedItem = NULL;	
	
	OSStatus err = SecKeychainFindGenericPassword(NULL,
												  strlen(KEYCHAIN_SERVICENAME), KEYCHAIN_SERVICENAME,
												  (UInt32)strlen(accountName), accountName,
												  &passwordLength, &passwordData,
												  &returnedItem);
	if (err != noErr) {
		NSLog(@"Error finding keychain password for account %s: %d\n", accountName, err);
		return nil;
	}
	NSData *data = [NSData dataWithBytes:passwordData length:passwordLength];
	
	bzero(passwordData, passwordLength);
	
	SecKeychainItemFreeContent(NULL, passwordData);
	
	return data;
}

- (void)setKeychainData:(NSData*)data {
	
	OSStatus status = noErr;
	
	SecKeychainItemRef itemRef = [self currentKeychainItem];
	if (itemRef) {
		//modify existing data; item already exists
		
		const char *accountName = [[self setKeychainDatabaseIdentifier] UTF8String];
		
		SecKeychainAttribute attrs[] = {
		{ kSecAccountItemAttr, (UInt32)strlen(accountName), (char*)accountName },
		{ kSecServiceItemAttr, strlen(KEYCHAIN_SERVICENAME), (char*)KEYCHAIN_SERVICENAME } };
		
		const SecKeychainAttributeList attributes = { sizeof(attrs) / sizeof(attrs[0]), attrs };
		
		if (noErr != (status = SecKeychainItemModifyAttributesAndData(itemRef, &attributes, (UInt32)[data length], [data bytes]))) {
			NSLog(@"Error modifying keychain data with new passphrase-data: %d", status);
		}
		
		CFRelease(itemRef);
	} else {
		const char *accountName = [[self setKeychainDatabaseIdentifier] UTF8String];
		
		//add new data; item does not exist
		if (noErr != (status = SecKeychainAddGenericPassword(NULL, strlen(KEYCHAIN_SERVICENAME), KEYCHAIN_SERVICENAME,
															 (UInt32)strlen(accountName), accountName, (UInt32)[data length], [data bytes], NULL))) {
			NSLog(@"Error adding new passphrase item to keychain: %d", status);
		}
	}
}

- (void)setStoresPasswordInKeychain:(BOOL)value {
	storesPasswordInKeychain = value;
	preferencesChanged = YES;
	
	if (!storesPasswordInKeychain)
		[self removeKeychainData];
}

- (BOOL)canLoadPassphraseData:(NSData*)passData {
	
	NSInteger keyLength = keyLengthInBits/8;
	
	//compute master key given stored salt and # of iterations
	NSData *computedMasterKey = [passData derivedKeyOfLength:keyLength salt:masterSalt iterations:hashIterationCount];

	//compute verify key given "verify" salt and 1 iteration
	NSData *verifySalt = [NSData dataWithBytesNoCopy:VERIFY_SALT length:sizeof(VERIFY_SALT) freeWhenDone:NO];
	NSData *computedVerifyKey = [computedMasterKey derivedKeyOfLength:keyLength salt:verifySalt iterations:1];
	
	//check against verify key data
	if ([computedVerifyKey isEqualToData:verifierKey]) {
		//if computedMasterKey is good, and we don't already have a master key, then this is it
		if (!masterKey)
			masterKey = computedMasterKey;
		
		return YES;
	}
	
	return NO;
	
}

- (BOOL)canLoadPassphrase:(NSString*)pass {
	return [self canLoadPassphraseData:[pass dataUsingEncoding:NSUTF8StringEncoding]];
}

- (BOOL)encryptDataInNewSession:(NSMutableData*)data {
	//ideally we would vary AES algo between 128 and 256 bits depending on key length, 
	//and scale beyond with triplets, quintuplets, and septuplets--but key is not currently user-settable

	//create new dataSessionSalt and key here
	dataSessionSalt = [NSData randomDataOfLength:256];
	
	NSData *dataSessionKey = [masterKey derivedKeyOfLength:keyLengthInBits/8 salt:dataSessionSalt iterations:1];
	
	return [data nv_encryptDataWithKey:dataSessionKey iv:[dataSessionSalt subdataWithRange:NSMakeRange(0, 16)]];
}
- (BOOL)decryptDataWithCurrentSettings:(NSMutableData*)data {
	
	NSData *dataSessionKey = [masterKey derivedKeyOfLength:keyLengthInBits/8 salt:dataSessionSalt iterations:1];
	
	return [data nv_decryptDataWithKey:dataSessionKey iv:[dataSessionSalt subdataWithRange:NSMakeRange(0, 16)]];
}

- (void)setPassphraseData:(NSData*)passData inKeychain:(BOOL)inKeychain {
	[self setPassphraseData:passData inKeychain:inKeychain withIterations:hashIterationCount];
}

- (void)setPassphraseData:(NSData *)passData inKeychain:(BOOL)inKeychain withIterations:(NSInteger)iterationCount {
	
	hashIterationCount = iterationCount;
	NSUInteger keyLength = keyLengthInBits/8;
	
	//generate and set random salt
	masterSalt = [NSData randomDataOfLength:256];

	//compute and set master key given salt and # of iterations
	masterKey = [passData derivedKeyOfLength:keyLength salt:masterSalt iterations:hashIterationCount];
	
	//compute and set verify key from master key
	NSData *verifySalt = [NSData dataWithBytesNoCopy:VERIFY_SALT length:sizeof(VERIFY_SALT) freeWhenDone:NO];
	verifierKey = [masterKey derivedKeyOfLength:keyLength salt:verifySalt iterations:1];

	//update keychain
	[self setStoresPasswordInKeychain:inKeychain];
	if (inKeychain)
		[self setKeychainData:passData];
	
	preferencesChanged = YES;
	
	if ([delegate respondsToSelector:@selector(databaseEncryptionSettingsChanged)])
		[delegate databaseEncryptionSettingsChanged];
}

- (NSData*)WALSessionKey {
	#define CONST_WAL_KEY "This is a 32 byte temporary key"
	NSData *sessionSalt = [NSData dataWithBytesNoCopy:LOG_SESSION_SALT length:sizeof(LOG_SESSION_SALT) freeWhenDone:NO];
	
	if (!doesEncryption)
		return [NSData dataWithBytesNoCopy:CONST_WAL_KEY length:sizeof(CONST_WAL_KEY) freeWhenDone:NO];

	return [masterKey derivedKeyOfLength:keyLengthInBits/8 salt:sessionSalt iterations:1];
}

- (void)setNotesStorageFormat:(NVDatabaseFormat)formatID {
	if (formatID != notesStorageFormat) {
		NVDatabaseFormat oldFormat = notesStorageFormat;
		notesStorageFormat = formatID;	
		preferencesChanged = YES;
		
		[self updateOSTypesArray];
		
		if ([delegate respondsToSelector:@selector(databaseSettingsChangedFromOldFormat:)])
			[(NotationController *)delegate databaseSettingsChangedFromOldFormat:oldFormat];
		
		//should notationprefs need to do this?
		if ([delegate respondsToSelector:@selector(flushEverything)])
			[delegate flushEverything];
	}
}

- (BOOL)shouldDisplaySheetForProposedFormat:(NSInteger)proposedFormat {
	BOOL notesExist = YES;
	
	if ([delegate respondsToSelector:@selector(totalNoteCount)])
		notesExist = [delegate totalNoteCount] > 0;

	return (proposedFormat == NVDatabaseFormatSingle && notesStorageFormat != NVDatabaseFormatSingle && notesExist);
}

- (void)noteFilesCleanupSheetDidEnd:(NSWindow *)sheet returnCode:(int)returnCode contextInfo:(void *)contextInfo {
	id context = (__bridge id)contextInfo;
	
	NSAssert(contextInfo, @"No contextInfo passed to noteFilesCleanupSheetDidEnd");
	NSAssert([context respondsToSelector:@selector(notesStorageFormatInProgress)],
			 @"can't get notesStorageFormatInProgress method for changing");

	NVDatabaseFormat newNoteStorageFormat = [(__bridge NotationPrefsViewController*)contextInfo notesStorageFormatInProgress];
	
	if (returnCode != NSAlertAlternateReturn)
		//didn't cancel
		[self setNotesStorageFormat:newNoteStorageFormat];
	
	if (returnCode == NSAlertOtherReturn)
		//tell delegate to delete all its notes' files
		[delegate trashRemainingNoteFilesInDirectory];
	//but what if the files remain after switching to a single-db format--and then the user deletes a bunch of the files themselves?
	//should we switch the currentFormatIDs of those notes to single-db? I guess.
	
	if ([context respondsToSelector:@selector(notesStorageFormatDidChange)])
		[(NotationPrefsViewController*)context notesStorageFormatDidChange];
	
	if (returnCode != NSAlertAlternateReturn) {
		//run queued method
		NSAssert([context respondsToSelector:@selector(runQueuedStorageFormatChangeInvocation)],
				 @"can't get runQueuedStorageFormatChangeInvocation method for changing");

		[(NotationPrefsViewController*)context runQueuedStorageFormatChangeInvocation];
	}
}

- (void)setConfirmsFileDeletion:(BOOL)value {
    confirmFileDeletion = value;
    preferencesChanged = YES;
}

- (void)setDoesEncryption:(BOOL)value {
	BOOL oldValue = doesEncryption;
	doesEncryption = value;
	
	preferencesChanged = YES;

	if (!doesEncryption) {
		[self removeKeychainData];
	
		//clear out the verifier key and salt?
		 verifierKey = nil;
		 masterKey = nil;
	}
	
	if (oldValue != value) {
		if ([delegate respondsToSelector:@selector(databaseEncryptionSettingsChanged)])
			[delegate databaseEncryptionSettingsChanged];
	}
}

- (void)setSecureTextEntry:(BOOL)value {
	
	secureTextEntry = value;
	
	preferencesChanged = YES;
	
	SecureTextEntryManager *tem = [SecureTextEntryManager sharedInstance];
	
	if (secureTextEntry) {
		[tem enableSecureTextEntry];
		[tem checkForIncompatibleApps];
	} else {
		//"forget" that the user had disabled the warning dialog when disabling this feature permanently
		[[NSUserDefaults standardUserDefaults] removeObjectForKey:ShouldHideSecureTextEntryWarningKey];
		[tem disableSecureTextEntry];
	}
}

- (void)setSyncEnabled:(BOOL)isEnabled forService:(NSString*)serviceName {
	NSMutableDictionary *accountDict = ServiceAccountDictInit(self, serviceName);
	
	if ([self syncServiceIsEnabled:serviceName] != isEnabled) {
		accountDict[@"enabled"] = @(isEnabled);
		
		preferencesChanged = YES;
		[delegate syncSettingsChangedForService:serviceName];
	}
}

- (void)setSyncFrequency:(NSUInteger)frequencyInMinutes forService:(NSString*)serviceName {
	NSMutableDictionary *accountDict = ServiceAccountDictInit(self, serviceName);
	
	if ([self syncFrequencyInMinutesForServiceName:serviceName] != frequencyInMinutes) {
		accountDict[@"frequency"] = @(frequencyInMinutes);
		preferencesChanged = YES;
		[delegate syncSettingsChangedForService:serviceName];
	}
}

- (void)setSyncShouldMerge:(BOOL)shouldMerge inCurrentAccountForService:(NSString*)serviceName {
	NSMutableDictionary *accountDict = ServiceAccountDictInit(self, serviceName);
	
	if ([self syncNotesShouldMergeForServiceName:serviceName] != shouldMerge) {
		NSString *username = accountDict[@"username"];
		if (username) {
			NSLog(@"%@: %d, %@", NSStringFromSelector(_cmd), shouldMerge, username);
			if (shouldMerge) {
				accountDict[@"shouldmerge"] = username;
			} else {
				[accountDict removeObjectForKey:@"shouldmerge"];
			}
			preferencesChanged = YES;
		} else {
			NSLog(@"%@: no username found in %@", NSStringFromSelector(_cmd), serviceName);
		}
	}
}

- (void)setSyncUsername:(NSString*)username forService:(NSString*)serviceName {
	
	NSMutableDictionary *accountDict = ServiceAccountDictInit(self, serviceName);
	
	if (![accountDict[@"username"] isEqualToString:username]) {
		accountDict[@"username"] = username;
		
		preferencesChanged = YES;
		[delegate syncSettingsChangedForService:serviceName];
	}
}

- (const char*)keychainSyncAccountNameForService:(NSString*)serviceName {
	NSString *username = [self syncAccountForServiceName:serviceName][@"username"];
	return [username length] ? [[username stringByAppendingFormat:@"-%@", serviceName] UTF8String] : NULL;
}

- (void)setSyncPassword:(NSString*)password forService:(NSString*)serviceName {
	//a username _MUST_ already exist in the account dict in order for the password to be saved in the keychain
	
	NSMutableDictionary *accountDict = ServiceAccountDictInit(self, serviceName);
	
	if (![accountDict[@"password"] isEqualToString:password]) {
		accountDict[@"password"] = password;
		
		NSData *passwordData = [password dataUsingEncoding:NSUTF8StringEncoding];
		
		const char *kcSyncAccountName = [self keychainSyncAccountNameForService:serviceName];
		if (kcSyncAccountName) {
			//insert this password into the keychain for this service
			SecKeychainItemRef itemRef = NULL;
			if (SecKeychainFindGenericPassword(NULL, strlen(KEYCHAIN_SERVICENAME), KEYCHAIN_SERVICENAME, (UInt32)strlen(kcSyncAccountName), kcSyncAccountName, NULL, NULL, &itemRef) != noErr) {
				itemRef = NULL;
			}
			if (itemRef) {
				//modify existing data; item already exists
				SecKeychainAttribute attrs[] = {
					{ kSecAccountItemAttr, (UInt32)strlen(kcSyncAccountName), (char*)kcSyncAccountName },
					{ kSecServiceItemAttr, strlen(KEYCHAIN_SERVICENAME), (char*)KEYCHAIN_SERVICENAME } };
				
				const SecKeychainAttributeList attributes = { sizeof(attrs) / sizeof(attrs[0]), attrs };
				
				OSStatus status = noErr;
				if (noErr != (status = SecKeychainItemModifyAttributesAndData(itemRef, &attributes, (UInt32)[passwordData length], [passwordData bytes]))) {
					NSLog(@"Error modifying keychain data with different service password: %d", status);
				}
				CFRelease(itemRef);
			} else {
				//add new data; item does not exist
				OSStatus status = noErr;
				if (noErr != (status = SecKeychainAddGenericPassword(NULL, strlen(KEYCHAIN_SERVICENAME), KEYCHAIN_SERVICENAME,
																	 (UInt32)strlen(kcSyncAccountName), kcSyncAccountName, (UInt32)[passwordData length], [passwordData bytes], NULL))) {
					NSLog(@"Error adding new service password to keychain: %d", status);
				}
			}
		} else {
			NSLog(@"not storing password in keychain for %@ because a sync account name couldn't be created", serviceName);
		}
			
		preferencesChanged = YES;
		[delegate syncSettingsChangedForService:serviceName];
	}
}

- (void)removeSyncPasswordForService:(NSString*)serviceName {
	NSMutableDictionary *accountDict = ServiceAccountDictInit(self, serviceName);
	
	if (accountDict[@"password"]) {
		[accountDict removeObjectForKey:@"password"];
		
		const char *kcSyncAccountName = [self keychainSyncAccountNameForService:serviceName];
		if (kcSyncAccountName) {
			SecKeychainItemRef itemRef = NULL;
			if (SecKeychainFindGenericPassword(NULL, strlen(KEYCHAIN_SERVICENAME), KEYCHAIN_SERVICENAME, (UInt32)strlen(kcSyncAccountName), kcSyncAccountName, NULL, NULL, &itemRef) != noErr) {
				itemRef = NULL;
			}	
			if (itemRef) {
				OSStatus err = SecKeychainItemDelete(itemRef);
				if (err != noErr) NSLog(@"Error deleting keychain item for service %@: %d", serviceName, (int)err);
				CFRelease(itemRef);
			}
		} else {
			NSLog(@"not removing password for %@ because a keychain sync account name couldn't be created", serviceName);
		}
		
		[delegate syncSettingsChangedForService:serviceName];
	}
}

- (UInt32)tableIndexOfDiskUUID:(NSUUID *)UUID {
	//if this UUID doesn't yet exist, then add it and return the last index
	
	DiskUUIDEntry *diskEntry = [[DiskUUIDEntry alloc] initWithUUID:UUID];
	
	NSUInteger idx = [seenDiskUUIDEntries indexOfObject: diskEntry];
	if (NSNotFound != idx) {
		[seenDiskUUIDEntries[idx] see];
		return (UInt32)idx;
	}
	
	NSLog(@"saw new disk UUID: %@ (other disks are: %@)", diskEntry, seenDiskUUIDEntries);
	[seenDiskUUIDEntries addObject:diskEntry];
	
	preferencesChanged = YES;
	
	return (UInt32)[seenDiskUUIDEntries count] - 1;
}

- (void)checkForKnownRedundantSyncConduitsAtPath:(NSString*)dbPath {
	//is inside dropbox folder and notes are separate files
	//is set to sync with any service
	//then display warning
	
	NSArray *enabledValues = [[syncServiceAccounts allValues] objectsFromDictionariesForKey:@"enabled"];	
	if ([enabledValues containsObject:@YES] && NVDatabaseFormatSingle != notesStorageFormat) {
		//this DB is syncing with a service and is storing separate files; could it be syncing with anything else, too?
		
		//this logic will need to be more sophisticated anyway when multiple sync services are supported
		NSString *syncServiceTitle = [SimplenoteSession localizedServiceTitle];
		
		NSDictionary *stDict = [[NSUserDefaults standardUserDefaults] persistentDomainForName:@"com.hogbaysoftware.SimpleText"];
		NSString *simpleTextFolder = stDict[@"SyncedDocumentsPathKey"];
		if (!simpleTextFolder) simpleTextFolder = [NSHomeDirectory() stringByAppendingPathComponent:@"SimpleText"];
		//for dropbox, a 'select value from config where key = "dropbox_path";' sqlite query would be necessary to get the true path
		NSString *dropboxFolder = [NSHomeDirectory() stringByAppendingPathComponent:@"Dropbox"];
		
		NSString *offendingFileConduitName = nil;
		if ([[dbPath lowercaseString] hasPrefix:[simpleTextFolder lowercaseString]]) {
			offendingFileConduitName = NSLocalizedString(@"SimpleText", nil);
		} else if ([[dbPath lowercaseString] hasPrefix:[dropboxFolder lowercaseString]]) {
			offendingFileConduitName = NSLocalizedString(@"Dropbox", nil);
		}
		if (offendingFileConduitName) {
			NSRunAlertPanel([NSString stringWithFormat:NSLocalizedString(@"<Feedback loop warning title>", nil), offendingFileConduitName, syncServiceTitle], 
							[NSString stringWithFormat:NSLocalizedString(@"<Feedback loop warning message>", nil), syncServiceTitle], NSLocalizedString(@"OK", nil), nil, nil);
		}
	}
}

+ (NSString*)pathExtensionForFormat:(NSInteger)format {
    switch (format) {
	case NVDatabaseFormatSingle:
	case NVDatabaseFormatPlain:
	    
	    return @"txt";
	case NVDatabaseFormatRTF:
	    
	    return @"rtf";
	case NVDatabaseFormatHTML:
	    
	    return @"html";
	case NVDatabaseFormatDOC:
		
		return @"doc";
	case NVDatabaseFormatDOCX:
		
		return @"docx";
	default:
	    NSLog(@"storage format ID is unknown: %ld", (long)format);
    }
    
    return @"";
}

//for our nstableview data source
- (NSUInteger)typeStringsCount {
	if (typeStrings[notesStorageFormat])
		return [typeStrings[notesStorageFormat] count];
	
	return 0;
}
- (NSUInteger)pathExtensionsCount {
	if (pathExtensions[notesStorageFormat])
	    return [pathExtensions[notesStorageFormat] count];
	
	return 0;
}

- (NSString*)typeStringAtIndex:(NSInteger)typeIndex {

    return typeStrings[notesStorageFormat][typeIndex];
}
- (NSString*)pathExtensionAtIndex:(NSInteger)pathIndex {
    return pathExtensions[notesStorageFormat][pathIndex];
}
- (NSUInteger)indexOfChosenPathExtension {
	return chosenExtIndices[notesStorageFormat];
}
- (NSString*)chosenPathExtensionForFormat:(NSInteger)format {
	if (chosenExtIndices[format] >= [pathExtensions[format] count])
		return [NotationPrefs pathExtensionForFormat:format];
	
	return pathExtensions[format][chosenExtIndices[format]];
}

- (void)updateOSTypesArray {
    if (!typeStrings[notesStorageFormat])
	return;
    
    NSUInteger i, newSize = sizeof(OSType) * [typeStrings[notesStorageFormat] count];
    allowedTypes = (OSType*)realloc(allowedTypes, newSize);
	
    for (i=0; i<[typeStrings[notesStorageFormat] count]; i++)
		allowedTypes[i] = UTGetOSTypeFromString((__bridge CFStringRef)typeStrings[notesStorageFormat][i]);
}

- (void)addAllowedPathExtension:(NSString*)extension {
    
    NSString *actualExt = [extension stringAsSafePathExtension];
	[pathExtensions[notesStorageFormat] addObject:actualExt];
	
	preferencesChanged = YES;
}

- (BOOL)removeAllowedPathExtensionAtIndex:(NSUInteger)extensionIndex {

	if ([pathExtensions[notesStorageFormat] count] > 1 && extensionIndex < [pathExtensions[notesStorageFormat] count]) {
		[pathExtensions[notesStorageFormat] removeObjectAtIndex:extensionIndex];
		
		if (chosenExtIndices[notesStorageFormat] >= [pathExtensions[notesStorageFormat] count])
			chosenExtIndices[notesStorageFormat] = 0;
		
		preferencesChanged = YES;
		return YES;
	}
	return NO;
}
- (BOOL)setChosenPathExtensionAtIndex:(NSUInteger)extensionIndex {
	if ([pathExtensions[notesStorageFormat] count] > extensionIndex &&
		[pathExtensions[notesStorageFormat][extensionIndex] length]) {
		chosenExtIndices[notesStorageFormat] = extensionIndex;
		
		preferencesChanged = YES;
		return YES;
	}
	return NO;
}

- (BOOL)addAllowedType:(NSString*)type {
    
	if (type) {
		[typeStrings[notesStorageFormat] addObject:[type fourCharTypeString]];
		[self updateOSTypesArray];
		
		preferencesChanged = YES;
		return YES;
	}
	return NO;
}

- (void)removeAllowedTypeAtIndex:(NSUInteger)typeIndex {
	[typeStrings[notesStorageFormat] removeObjectAtIndex:typeIndex];
	[self updateOSTypesArray];
	
	preferencesChanged = YES;
}

- (BOOL)setExtension:(NSString*)newExtension atIndex:(unsigned int)oldIndex {
	
    if (oldIndex < [pathExtensions[notesStorageFormat] count]) {
		
		if ([newExtension length] > 0) { 
			pathExtensions[notesStorageFormat][oldIndex] = [newExtension stringAsSafePathExtension];
			
			preferencesChanged = YES;
		} else if (![(NSString*)pathExtensions[notesStorageFormat][oldIndex] length]) {
			return NO;
		}
    }
	
	return YES;
}

- (BOOL)setType:(NSString*)newType atIndex:(unsigned int)oldIndex {
	
    if (oldIndex < [typeStrings[notesStorageFormat] count]) {
		
		if ([newType length] > 0) {
			typeStrings[notesStorageFormat][oldIndex] = [newType fourCharTypeString];
			[self updateOSTypesArray];
				
			preferencesChanged = YES;
				
			return YES;
		}
		if (!UTGetOSTypeFromString((__bridge CFStringRef)typeStrings[notesStorageFormat][oldIndex])) {
			return NO;
		}
    }
	
	return YES;
}

- (BOOL)pathExtensionAllowed:(NSString *)anExtension forFormat:(NSInteger)formatID {
	NSUInteger i;
    for (i=0; i<[pathExtensions[formatID] count]; i++) {
		if ([anExtension compare:pathExtensions[formatID][i] 
						 options:NSCaseInsensitiveSearch] == NSOrderedSame) {
			return YES;
		}
    }
	return NO;
}

- (BOOL)catalogEntryAllowed:(NoteCatalogEntry*)catEntry {
    NSString *filename = (__bridge NSString*)catEntry->filename;
	
	if (![filename length])
		return NO;
	
	//ignore hidden files and our own database-related files (e.g. if by chance they are given a TEXT file type)
	if ([filename characterAtIndex:0] == '.') {
		return NO;
	}
	if ([filename isEqualToString:NotesDatabaseFileName]) {
		return NO;
	}
	if ([filename isEqualToString:@"Interim Note-Changes"]) {
		return NO;
	}
	
	if ([self pathExtensionAllowed:[filename pathExtension] forFormat:notesStorageFormat])
		return YES;
    
	NSUInteger i;
    for (i=0; i<[typeStrings[notesStorageFormat] count]; i++) {
		if (catEntry->fileType == allowedTypes[i]) {
			return YES;
		}
    }
    
    return NO;
    
}

@end
