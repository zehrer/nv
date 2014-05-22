//
//  ExternalEditorListController.m
//  Notation
//
//  Created by Zachary Schneirov on 3/14/11.

/*Copyright (c) 2010, Zachary Schneirov. All rights reserved.
 This file is part of Notational Velocity.
 
 Notational Velocity is free software: you can redistribute it and/or modify
 it under the terms of the GNU General Public License as published by
 the Free Software Foundation, either version 3 of the License, or
 (at your option) any later version.
 
 Notational Velocity is distributed in the hope that it will be useful,
 but WITHOUT ANY WARRANTY; without even the implied warranty of
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 GNU General Public License for more details.
 
 You should have received a copy of the GNU General Public License
 along with Notational Velocity.  If not, see <http://www.gnu.org/licenses/>. */


#import "ExternalEditorListController.h"
#import "NoteObject.h"
#import "NotationController.h"
#import "NotationPrefs.h"
#import "NSBezierPath_NV.h"
#import "AppController.h"

static NSString *UserEEIdentifiersKey = @"UserEEIdentifiers";
static NSString *DefaultEEIdentifierKey = @"DefaultEEIdentifier";
NSString *ExternalEditorsChangedNotification = @"ExternalEditorsChanged";

@interface ExternalEditorListController () <NSMenuDelegate>

@end

@implementation ExternalEditor

- (id)initWithBundleID:(NSString*)aBundleIdentifier resolvedURL:(NSURL*)aURL {
	if ((self = [self init])) {
		bundleIdentifier = aBundleIdentifier;
		resolvedURL = aURL;
		
		NSAssert(resolvedURL || bundleIdentifier, @"the bundle identifier and URL cannot both be nil");
		if (!bundleIdentifier) {
			if (!(bundleIdentifier = [[[NSBundle bundleWithPath:[aURL path]] bundleIdentifier] copy])) {
				NSLog(@"initWithBundleID:resolvedURL: URL does not seem to point to a valid bundle");
				return nil;
			}
		}
	}
	return self;
}

- (BOOL)canEditNoteDirectly:(NoteObject*)aNote {
	NSAssert(aNote != nil, @"aNote is nil");

	//for determining whether this potentially non-ODB-editor can open a non-plain-text file
	//process: does pathExtension key exist in knownPathExtensions dict?
	//if not, check this path extension w/ launch services
	//then add a corresponding YES/NO NSNumber value to the knownPathExtensions dict

	//but first, this editor can't handle any path if it's not actually installed
	if (![self isInstalled]) return NO;
	
	//and if this note isn't actually stored in a separate file, then obviously it can't be opened directly
	if ([[aNote delegate] currentNoteStorageFormat] == NVDatabaseFormatSingle) return NO;
	
	//and if aNote is in plaintext format and this editor is ODB-capable, then it should also be a general-purpose texteditor
	//conversely ODB editors should never be allowed to open non-plain-text documents; for some reason LSCanURLAcceptURL claims they can do that
	//one exception known: writeroom can edit rich-text documents
	if (([self isODBEditor] && ![bundleIdentifier hasPrefix:@"com.hogbaysoftware.WriteRoom"]) || [bundleIdentifier hasPrefix:@"com.multimarkdown.composer.mac"]) {
		return aNote.currentFormatID == NVDatabaseFormatPlain;
	}
		
	if (!knownPathExtensions) knownPathExtensions = [NSMutableDictionary new];
	NSString *extension = aNote.filename.pathExtension.lowercaseString;
	NSNumber *canHandleNumber = knownPathExtensions[extension];
	
	if (!canHandleNumber) {
		NSString *path = [aNote noteFilePath];
	
		Boolean canAccept = false;
		OSStatus err = LSCanURLAcceptURL((__bridge CFURLRef)[NSURL fileURLWithPath:path], (__bridge CFURLRef)[self resolvedURL], kLSRolesEditor, kLSAcceptAllowLoginUI, &canAccept);
		if (noErr != err) {
			NSLog(@"LSCanURLAcceptURL '%@' err: %d", path, err);
		}
		knownPathExtensions[extension] = @((BOOL)canAccept);
		
		return (BOOL)canAccept;
	}
	
	return [canHandleNumber boolValue];
}

- (BOOL)canEditAllNotes:(NSArray*)notes {
	NSUInteger i = 0;
	for (i=0; i<[notes count]; i++) {
		if (![self isODBEditor] && ![self canEditNoteDirectly:notes[i]])
			return NO;
	}
	return YES;
}

- (NSImage*)iconImage {
	if (!iconImg) {
		FSRef appRef;
		if (CFURLGetFSRef((CFURLRef)[self resolvedURL], &appRef))
			iconImg = [NSImage smallIconForFSRef:&appRef];
	}
	return iconImg;
}

- (NSString*)displayName {
	if (!displayName) {
		CFStringRef outString = NULL;
		LSCopyDisplayNameForURL((__bridge CFURLRef)[self resolvedURL], &outString);
		displayName = (__bridge NSString *)outString;
	}
	return displayName;
}

- (NSURL*)resolvedURL {
	if (!resolvedURL && !installCheckFailed) {
		CFURLRef outURL = NULL;
		OSStatus err = LSFindApplicationForInfo(kLSUnknownCreator, (__bridge CFStringRef)bundleIdentifier, NULL, NULL, &outURL);
		resolvedURL = (__bridge NSURL *)outURL;
		
		if (kLSApplicationNotFoundErr == err) {
			installCheckFailed = YES;
		} else if (noErr != err) {
			NSLog(@"LSFindApplicationForInfo error for bundle identifier '%@': %d", bundleIdentifier, err);
		}
	}
	return resolvedURL;
}

- (BOOL)isInstalled {
	return [self resolvedURL] != nil;
}

- (BOOL)isODBEditor {
	return [[ExternalEditorListController ODBAppIdentifiers] containsObject:bundleIdentifier];
}

- (NSString*)bundleIdentifier {
	return bundleIdentifier;
}

- (NSString*)description {
	return [bundleIdentifier stringByAppendingFormat:@" (URL: %@)", resolvedURL];
}

- (NSUInteger)hash {
	return [bundleIdentifier hash];
}
- (BOOL)isEqual:(id)otherEntry {
	return [[otherEntry bundleIdentifier] isEqualToString:bundleIdentifier];
}
- (NSComparisonResult)compareDisplayName:(ExternalEditor *)otherEd {
    return [[self displayName] caseInsensitiveCompare:[otherEd displayName]];
}




@end

@implementation ExternalEditorListController

+ (ExternalEditorListController*)sharedInstance {
    static dispatch_once_t onceToken;
    static ExternalEditorListController *sharedInstance = nil;
    dispatch_once(&onceToken, ^{
        sharedInstance = [[ExternalEditorListController alloc] initWithUserDefaults];
    });
    return sharedInstance;
}

- (void)commonInit
{
    userEditorList = [[NSMutableArray alloc] init];
}

- (id)initWithUserDefaults {
    self = [super init];
	if (self) {
        [self commonInit];
        
		// TextEdit is not an ODB editor, but can be used to open files directly
        [[NSUserDefaults standardUserDefaults] registerDefaults:@{UserEEIdentifiersKey: @[@"com.apple.TextEdit"]}];
	
		[self _initDefaults];
	}
	return self;
}

- (id)init {
    self = [super init];
	if (self) {
        [self commonInit];
	}
	return self;
}

- (void)_initDefaults {
	NSArray *userIdentifiers = [[NSUserDefaults standardUserDefaults] arrayForKey:UserEEIdentifiersKey];
	
	NSUInteger i = 0;
	for (i=0; i<[userIdentifiers count]; i++) {
		ExternalEditor *ed = [[ExternalEditor alloc] initWithBundleID:userIdentifiers[i] resolvedURL:nil];
		[userEditorList addObject:ed];
	}
	
	//initialize the default editor if one has not already been set or if the identifier was somehow lost from the list
	if (![self editorIsMember:[self defaultExternalEditor]] || ![[self defaultExternalEditor] isInstalled]) {
		if ([[self _installedODBEditors] count]) {
			[self setDefaultEditor:[[self _installedODBEditors] lastObject]];
		}
	}
}

- (NSArray*)_installedODBEditors {
	if (!_installedODBEditors) {
		_installedODBEditors = [[NSMutableArray alloc] initWithCapacity:5];
		
		NSArray *ODBApps = [[[self class] ODBAppIdentifiers] allObjects];
		NSUInteger i = 0;
		for (i=0; i<[ODBApps count]; i++) {
			ExternalEditor *ed = [[ExternalEditor alloc] initWithBundleID:ODBApps[i] resolvedURL:nil];
			if ([ed isInstalled]) {
				[_installedODBEditors addObject:ed];
			}
		}
		[_installedODBEditors sortUsingSelector:@selector(compareDisplayName:)];
	}
	return _installedODBEditors;
}

+ (NSSet*)ODBAppIdentifiers {
	static NSSet *_ODBAppIdentifiers = nil;
	if (!_ODBAppIdentifiers) 
		_ODBAppIdentifiers = [[NSSet alloc] initWithObjects:
							  @"de.codingmonkeys.SubEthaEdit", @"com.barebones.bbedit", @"com.barebones.textwrangler", 
							  @"com.macromates.textmate", @"com.transtex.texeditplus", @"jp.co.artman21.JeditX", @"org.gnu.Aquamacs", 
							  @"org.smultron.Smultron", @"com.peterborgapps.Smultron", @"org.fraise.Fraise", @"com.aynimac.CotEditor", @"com.macrabbit.cssedit", 
							  @"com.talacia.Tag", @"org.skti.skEdit", @"com.cgerdes.ji", @"com.optima.PageSpinner", @"com.hogbaysoftware.WriteRoom", 
							  @"com.hogbaysoftware.WriteRoom.mac", @"org.vim.MacVim", @"com.forgedit.ForgEdit", @"com.tacosw.TacoHTMLEdit", @"com.macrabbit.espresso", @"com.sublimetext.2",@"com.metaclassy.byword",@"jp.informationarchitects.WriterForMacOSX", nil];
	return _ODBAppIdentifiers;
}

- (void)addUserEditorFromDialog:(id)sender {
	
	//always send menuChanged notification because this class is the target of its menus, 
	//so the notification is the only way to maintain a consistent selected item in PrefsWindowController
	[self performSelector:@selector(menusChanged) withObject:nil afterDelay:0.0];
	
	NSOpenPanel *openPanel = [NSOpenPanel openPanel];
    [openPanel setResolvesAliases:YES];
    [openPanel setAllowsMultipleSelection:NO];
	[openPanel setDirectoryURL:[NSURL fileURLWithPath:@"/Applications"]];
	[openPanel setAllowedFileTypes:@[(id)kUTTypeApplication]];
    
    if ([openPanel runModal] == NSOKButton) {
		NSURL *appURL = [openPanel URL];
		
		if (!appURL) {
            NSBeep();
            NSLog(@"Unable to add external editor");
        }
		
		ExternalEditor *ed = [[ExternalEditor alloc] initWithBundleID:nil resolvedURL:appURL];
        if (ed) {
            //check against lists of all known editors, installed or not
            if (![self editorIsMember:ed]) {
                [userEditorList addObject:ed];
                [[NSUserDefaults standardUserDefaults] setObject:[self userEditorIdentifiers] forKey:UserEEIdentifiersKey];
            }
            
            [self setDefaultEditor:ed];
        } else {
            NSBeep();
            NSLog(@"Unable to add external editor");
        }
    }
}

- (void)resetUserEditors:(id)sender {
	[userEditorList removeAllObjects];
	
	[[NSUserDefaults standardUserDefaults] removeObjectForKey:UserEEIdentifiersKey];
	
	[self _initDefaults];
	
	[self menusChanged];
}

- (NSArray*)userEditorIdentifiers {
	//for storing in nsuserdefaults
	//extract bundle identifiers
	
	NSMutableArray *array = [NSMutableArray arrayWithCapacity:[userEditorList count]];
	NSUInteger i = 0;
	for (i=0; i<[userEditorList count]; i++) {
		[array addObject:[userEditorList[i] bundleIdentifier]];
	}

	return array;
}


- (BOOL)editorIsMember:(ExternalEditor*)anEditor {
	//does the editor exist in any of the lists?
	return [userEditorList containsObject:anEditor] || [[ExternalEditorListController ODBAppIdentifiers] containsObject:[anEditor bundleIdentifier]];
}

- (NSMenu*)addEditorPrefsMenu {
	if (!editorPrefsMenus) editorPrefsMenus = [NSMutableSet new];
	NSMenu *aMenu = [[NSMenu alloc] initWithTitle:@"External Editors Menu"];
	[aMenu setAutoenablesItems:NO];
	[aMenu setDelegate:self];
	[editorPrefsMenus addObject:aMenu];
	[self _updateMenu:aMenu];
	return aMenu;
}

- (NSMenu*)addEditNotesMenu {
	if (!editNotesMenus) editNotesMenus = [NSMutableSet new];
	NSMenu *aMenu = [[NSMenu alloc] initWithTitle:@"Edit Note Menu"];
	[aMenu setAutoenablesItems:YES];
	[aMenu setDelegate:self];
	[editNotesMenus addObject:aMenu];
	[self _updateMenu:aMenu];
	return aMenu;
}

- (void)menusChanged {
    for (NSMenu *menu in editNotesMenus) {
        [self _updateMenu:menu];
    }
    
    for (NSMenu *menu in editorPrefsMenus) {
        [self _updateMenu:menu];
    }
    
	[[NSNotificationCenter defaultCenter] postNotification:[NSNotification notificationWithName:ExternalEditorsChangedNotification object:self]];
}

- (void)_updateMenu:(NSMenu*)theMenu {
	//for allowing the user to configure external editors in the preferences window

	[theMenu performSelector:@selector(removeAllItems)];
	
	BOOL isPrefsMenu = [editorPrefsMenus containsObject:theMenu];
	BOOL didAddItem = NO;
	NSMutableArray *editors = [NSMutableArray arrayWithArray:[self _installedODBEditors]];
	[editors addObjectsFromArray:[userEditorList filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"isInstalled == YES"]]];
	[editors sortUsingSelector:@selector(compareDisplayName:)];
	
	NSUInteger i = 0;
	for (i=0; i<[editors count]; i++) {
		ExternalEditor *ed = editors[i];
		
		//change action SEL based on whether this is coming from Notes menu or preferences window
		NSMenuItem *theMenuItem = isPrefsMenu ? 
			[[NSMenuItem alloc] initWithTitle:[ed displayName] action:@selector(setDefaultEditor:) keyEquivalent:@""] : 
			[[NSMenuItem alloc] initWithTitle:[ed displayName] action:@selector(editNoteExternally:) keyEquivalent:@""];
			
		if (!isPrefsMenu && [[self defaultExternalEditor] isEqual:ed]) {
			[theMenuItem setKeyEquivalent:@"E"];
			[theMenuItem setKeyEquivalentModifierMask: NSCommandKeyMask | NSShiftKeyMask];
		}
		//PrefsWindowController maintains default-editor selection by updating on ExternalEditorsChangedNotification
			
		[theMenuItem setTarget: isPrefsMenu ? self : [NSApp delegate]];
		
		[theMenuItem setRepresentedObject:ed];
//		
		if ([ed iconImage])
			[theMenuItem setImage:[ed iconImage]];
//
		[theMenu addItem:theMenuItem];
		didAddItem = YES;
	}

	if (!didAddItem) {
		//disabled placeholder menu item; will probably not be displayed, but would be necessary for preferences list
		NSMenuItem *theMenuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"(None)", @"description for no key combination") action:NULL keyEquivalent:@""];
		[theMenuItem setEnabled:NO];
		[theMenu addItem:theMenuItem];
	}
	if ([userEditorList count] > 1 && isPrefsMenu) {
		//if the user added at least one editor (in addition to the default TextEdit item), then allow items to be reset to their default
		[theMenu addItem:[NSMenuItem separatorItem]];
		
		NSMenuItem *theMenuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Reset", @"menu command to clear out custom external editors")
															  action:@selector(resetUserEditors:) keyEquivalent:@""];
		[theMenuItem setTarget:self];
		[theMenu addItem:theMenuItem];
	}
	[theMenu addItem:[NSMenuItem separatorItem]];

	NSMenuItem *theMenuItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Other...", @"title of menu item for selecting a different notes folder")
														  action:@selector(addUserEditorFromDialog:) keyEquivalent:@""];
	[theMenuItem setTarget:self];
	[theMenu addItem:theMenuItem];
}

- (ExternalEditor*)defaultExternalEditor {
	if (!defaultEditor) {
		NSString *defaultIdentifier = [[NSUserDefaults standardUserDefaults] stringForKey:DefaultEEIdentifierKey];
		if (defaultIdentifier)
			defaultEditor = [[ExternalEditor alloc] initWithBundleID:defaultIdentifier resolvedURL:nil];
	}
	return defaultEditor;
}

- (void)setDefaultEditor:(id)anEditor {
	if ((anEditor = ([anEditor isKindOfClass:[NSMenuItem class]] ? [anEditor representedObject] : anEditor))) {
		defaultEditor = anEditor;

		[[NSUserDefaults standardUserDefaults] setObject:[defaultEditor bundleIdentifier] forKey:DefaultEEIdentifierKey];
		
		[self menusChanged];
	}
}

@end
