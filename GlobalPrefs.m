//
//  GlobalPrefs.m
//  Notation
//
//  Created by Zachary Schneirov on 1/31/06.

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


#import "GlobalPrefs.h"
#import "NSData_transformations.h"
#import "NotationPrefs.h"
#import "BookmarksController.h"
#import "AttributedPlainText.h"
#import "NotesTableView.h"
#import "PTHotKey.h"
#import "PTKeyCombo.h"
#import "PTHotKeyCenter.h"
#import "NSString_NV.h"
#import "AppController.h"
#import "BufferUtils.h"

static NSString *DirectoryAliasKey = @"DirectoryAlias";
static NSString *AutoCompleteSearchesKey = @"AutoCompleteSearches";
static NSString *TableFontSizeKey = @"TableFontPointSize";
static NSString *TableIsReverseSortedKey = @"TableIsReverseSorted";
static NSString *TableColumnsHaveBodyPreviewKey = @"TableColumnsHaveBodyPreview";
static NSString *NoteBodyFontKey = @"NoteBodyFont";
static NSString *ConfirmNoteDeletionKey = @"ConfirmNoteDeletion";
static NSString *CheckSpellingInNoteBodyKey = @"CheckSpellingInNoteBody";
static NSString *TextReplacementInNoteBodyKey = @"TextReplacementInNoteBody";
static NSString *QuitWhenClosingMainWindowKey = @"QuitWhenClosingMainWindow";
static NSString *TabKeyIndentsKey = @"TabKeyIndents";
static NSString *PastePreservesStyleKey = @"PastePreservesStyle";
static NSString *AutoFormatsDoneTagKey = @"AutoFormatsDoneTag";
static NSString *AutoFormatsListBulletsKey = @"AutoFormatsListBullets";
static NSString *AutoSuggestLinksKey = @"AutoSuggestLinks";
static NSString *AutoIndentsNewLinesKey = @"AutoIndentsNewLines";
static NSString *HighlightSearchTermsKey = @"HighlightSearchTerms";
static NSString *SearchTermHighlightColorKey = @"SearchTermHighlightColor";
static NSString *ForegroundTextColorKey = @"ForegroundTextColor";
static NSString *BackgroundTextColorKey = @"BackgroundTextColor";
static NSString *UseSoftTabsKey = @"UseSoftTabs";
static NSString *NumberOfSpacesInTabKey = @"NumberOfSpacesInTab";
static NSString *MakeURLsClickableKey = @"MakeURLsClickable";
static NSString *AppActivationKeyCodeKey = @"AppActivationKeyCode";
static NSString *AppActivationModifiersKey = @"AppActivationModifiers";
static NSString *HorizontalLayoutKey = @"HorizontalLayout";
static NSString *BookmarksKey = @"Bookmarks";
static NSString *LastScrollOffsetKey = @"LastScrollOffset";
static NSString *LastSearchStringKey = @"LastSearchString";
static NSString *LastSelectedNoteUUIDBytesKey = @"LastSelectedNoteUUIDBytes";
static NSString *LastSelectedPreferencesPaneKey = @"LastSelectedPrefsPane";
//elasticthreads prefs
static NSString *StatusBarItem = @"StatusBarItem";
static NSString	*ShowDockIcon = @"ShowDockIcon";
static NSString	*KeepsMaxTextWidth = @"KeepsMaxTextWidth";
static NSString	*NoteBodyMaxWidth = @"NoteBodyMaxWidth";
static NSString	*ColorScheme = @"ColorScheme";
static NSString *UseMarkdownImportKey = @"UseMarkdownImport";
static NSString *UseReadabilityKey = @"UseReadability";
static NSString *ShowGridKey = @"ShowGrid";
static NSString *AlternatingRowsKey = @"AlternatingRows";
static NSString *RTLKey = @"rtl";
static NSString *ShowWordCount = @"ShowWordCount";
static NSString *markupPreviewMode = @"markupPreviewMode";
static NSString *UseAutoPairing = @"UseAutoPairing";
static NSString *UsesMarkdownCompletions = @"UsesMarkdownCompletions";
//static NSString *PasteClipboardOnNewNoteKey = @"PasteClipboardOnNewNote";

NSString *NVPTFPboardType = @"Notational Velocity Poor Text Format";

NSString *HotKeyAppToFrontName = @"bring Notational Velocity to the foreground";

static NSString *const NVTableColumnsVisibleKey = @"NVTableColumnsVisible";
static NSString *const NVTableColumnsVisibleLegacyKey = @"NoteAttributesVisible";
static NSString *const NVTableSortColumnKey = @"NVTableSortColumn";
static NSString *const NVTableSortColumnLegacyKey = @"TableSortColumn";

@implementation GlobalPrefs

- (void)sendCallbacks:(SEL)selector originalSender:(id)originalSender
{
	[defaults synchronize];
	
	if (originalSender == self) return;

	[self notifyCallbacksForSelector:selector excludingSender:originalSender];
}

- (id)init {
	if ((self = [super init])) {

		selectorObservers = [[NSMutableDictionary alloc] init];

		defaults = [NSUserDefaults standardUserDefaults];

		[defaults registerDefaults:@{AutoSuggestLinksKey: @YES,
			AutoFormatsDoneTagKey: @YES,
			AutoIndentsNewLinesKey: @YES,
			AutoFormatsListBulletsKey: @YES,
			UseSoftTabsKey: @NO,
			NumberOfSpacesInTabKey: @4,
			PastePreservesStyleKey: @YES,
			TabKeyIndentsKey: @YES,
			ConfirmNoteDeletionKey: @YES,
			CheckSpellingInNoteBodyKey: @YES,
			TextReplacementInNoteBodyKey: @NO,
			AutoCompleteSearchesKey: @YES,
			QuitWhenClosingMainWindowKey: @YES,
			HorizontalLayoutKey: @NO,
			MakeURLsClickableKey: @YES,
			HighlightSearchTermsKey: @YES,
			TableColumnsHaveBodyPreviewKey: @YES,
			LastScrollOffsetKey: @0.0,
			LastSelectedPreferencesPaneKey: @"General",
			StatusBarItem: @NO,
			KeepsMaxTextWidth: @NO,
			NoteBodyMaxWidth: @660.0f,
			ColorScheme: @2,
            ShowDockIcon: @YES,
			RTLKey: @NO,
            ShowWordCount: @YES,
            markupPreviewMode: @MultiMarkdownPreview,
			UseMarkdownImportKey: @NO,
			UseReadabilityKey: @NO,
            ShowGridKey: @YES,
            AlternatingRowsKey: @NO,
            UseAutoPairing: @NO,
            UsesMarkdownCompletions: @NO,

			NoteBodyFontKey: [NSArchiver archivedDataWithRootObject:
			 [NSFont fontWithName:@"Helvetica" size:12.0f]],

			ForegroundTextColorKey: [NSArchiver archivedDataWithRootObject:[NSColor blackColor]],
			BackgroundTextColorKey: [NSArchiver archivedDataWithRootObject:[NSColor whiteColor]],

			SearchTermHighlightColorKey: [NSArchiver archivedDataWithRootObject:
			 [NSColor colorWithCalibratedRed:0.945 green:0.702 blue:0.702 alpha:1.0f]],

			TableFontSizeKey: [NSNumber numberWithFloat:[NSFont smallSystemFontSize]],
			NVTableColumnsVisibleKey: @(NVTableColumnOptionTitle | NVTableColumnOptionDateModified),
			NVTableSortColumnLegacyKey: @(NVTableColumnOptionDateModified),
			TableIsReverseSortedKey: @YES}];

		autoCompleteSearches = [defaults boolForKey:AutoCompleteSearchesKey];
	}
	return self;
}

+ (GlobalPrefs *)defaultPrefs {
	static GlobalPrefs *prefs = nil;
	if (!prefs)
		prefs = [[GlobalPrefs alloc] init];
	return prefs;
}


- (void)registerWithTarget:(id)sender forChangesInSettings:(SEL)firstSEL, ... {
	NSAssert(firstSEL != NULL, @"need at least one selector");

	if ([sender respondsToSelector:(@selector(settingChangedForSelectorString:))]) {

		va_list argList;
		va_start(argList, firstSEL);
		SEL aSEL = firstSEL;
		do {
			NSString *selectorKey = NSStringFromSelector(aSEL);

			NSMutableArray *senders = selectorObservers[selectorKey];
			if (!senders) {
				senders = [[NSMutableArray alloc] initWithCapacity:1];
				selectorObservers[selectorKey] = senders;
			}
			[senders addObject:sender];
//            [senders release];
		} while (( aSEL = va_arg( argList, SEL) ) != nil);
		va_end(argList);

	} else {
		NSLog(@"%@: target %@ does not respond to callback selector!", NSStringFromSelector(_cmd), [sender description]);
	}
}

- (void)registerForSettingChange:(SEL)selector withTarget:(id)sender {
	[self registerWithTarget:sender forChangesInSettings:selector, nil];
}

- (void)unregisterForNotificationsFromSelector:(SEL)selector sender:(id)sender {
	NSString *selectorKey = NSStringFromSelector(selector);

	NSMutableArray *senders = selectorObservers[selectorKey];
	if (senders) {
		[senders removeObjectIdenticalTo:sender];

		if (![senders count])
			[selectorObservers removeObjectForKey:selectorKey];
	} else {
		NSLog(@"Selector %@ has no observers?", NSStringFromSelector(selector));
	}
}

- (void)notifyCallbacksForSelector:(SEL)selector excludingSender:(id)sender {
	NSArray *observers = nil;
	id observer = nil;

	NSString *selectorKey = NSStringFromSelector(selector);

	if ((observers = selectorObservers[selectorKey])) {
		unsigned int i;

		for (i=0; i<[observers count]; i++) {

			if ((observer = observers[i]) != sender && observer)
				[observer performSelector:@selector(settingChangedForSelectorString:) withObject:selectorKey];
		}
	}
}

- (void)setNotationPrefs:(NotationPrefs*)newNotationPrefs sender:(id)sender {
	notationPrefs = newNotationPrefs;

	[self resolveNoteBodyFontFromNotationPrefsFromSender:sender];


	[self sendCallbacks:_cmd originalSender:sender];
}

- (NotationPrefs*)notationPrefs {
	return notationPrefs;
}

- (BOOL)autoCompleteSearches {
	return autoCompleteSearches;
}

- (void)setAutoCompleteSearches:(BOOL)value sender:(id)sender {
	autoCompleteSearches = value;
	[defaults setBool:value forKey:AutoCompleteSearchesKey];

	[self sendCallbacks:_cmd originalSender:sender];
}

- (void)setTabIndenting:(BOOL)value sender:(id)sender {
    [defaults setBool:value forKey:TabKeyIndentsKey];

    [self sendCallbacks:_cmd originalSender:sender];
}
- (BOOL)tabKeyIndents {
    return [defaults boolForKey:TabKeyIndentsKey];
}

- (void)setUseTextReplacement:(BOOL)value sender:(id)sender {
    [defaults setBool:value forKey:TextReplacementInNoteBodyKey];

    [self sendCallbacks:_cmd originalSender:sender];
}

- (BOOL)useTextReplacement {
    return [defaults boolForKey:TextReplacementInNoteBodyKey];
}

- (void)setCheckSpellingAsYouType:(BOOL)value sender:(id)sender {
    [defaults setBool:value forKey:CheckSpellingInNoteBodyKey];

    [self sendCallbacks:_cmd originalSender:sender];
}

- (BOOL)checkSpellingAsYouType {
    return [defaults boolForKey:CheckSpellingInNoteBodyKey];
}

- (void)setConfirmNoteDeletion:(BOOL)value sender:(id)sender {
    [defaults setBool:value forKey:ConfirmNoteDeletionKey];

	[self sendCallbacks:_cmd originalSender:sender];
}
- (BOOL)confirmNoteDeletion {
    return [defaults boolForKey:ConfirmNoteDeletionKey];
}

- (void)setQuitWhenClosingWindow:(BOOL)value sender:(id)sender {
    [defaults setBool:value forKey:QuitWhenClosingMainWindowKey];

	[self sendCallbacks:_cmd originalSender:sender];
}
- (BOOL)quitWhenClosingWindow {
    return [defaults boolForKey:QuitWhenClosingMainWindowKey];
}

- (void)setAppActivationKeyCombo:(PTKeyCombo*)aCombo sender:(id)sender {
	if (aCombo) {
		appActivationKeyCombo = aCombo;

		[[self appActivationHotKey] setKeyCombo:appActivationKeyCombo];

		[defaults setInteger:[aCombo keyCode] forKey:AppActivationKeyCodeKey];
		[defaults setInteger:[aCombo modifiers] forKey:AppActivationModifiersKey];

		[self sendCallbacks:_cmd originalSender:sender];
	}
}

- (PTHotKey*)appActivationHotKey {
	if (!appActivationHotKey) {
		appActivationHotKey = [[PTHotKey alloc] init];
		[appActivationHotKey setName:HotKeyAppToFrontName];
		[appActivationHotKey setKeyCombo:[self appActivationKeyCombo]];
	}

	return appActivationHotKey;
}

- (PTKeyCombo*)appActivationKeyCombo {
	if (!appActivationKeyCombo) {
		appActivationKeyCombo = [[PTKeyCombo alloc] initWithKeyCode:[[defaults objectForKey:AppActivationKeyCodeKey] intValue]
														  modifiers:[[defaults objectForKey:AppActivationModifiersKey] intValue]];
	}
	return appActivationKeyCombo;
}

- (BOOL)registerAppActivationKeystrokeWithTarget:(id)target selector:(SEL)selector {
	PTHotKey *hotKey = [self appActivationHotKey];

	[hotKey setTarget:target];
	[hotKey setAction:selector];

	[[PTHotKeyCenter sharedCenter] unregisterHotKeyForName:HotKeyAppToFrontName];

	return [[PTHotKeyCenter sharedCenter] registerHotKey:hotKey];
}

- (void)setPastePreservesStyle:(BOOL)value sender:(id)sender {
    [defaults setBool:value forKey:PastePreservesStyleKey];

	[self sendCallbacks:_cmd originalSender:sender];
}

- (BOOL)pastePreservesStyle {

    return [defaults boolForKey:PastePreservesStyleKey];
}

- (void)setAutoFormatsDoneTag:(BOOL)value sender:(id)sender {
    [defaults setBool:value forKey:AutoFormatsDoneTagKey];

	[self sendCallbacks:_cmd originalSender:sender];
}
- (BOOL)autoFormatsDoneTag {
	return [defaults boolForKey:AutoFormatsDoneTagKey];
}
- (BOOL)autoFormatsListBullets {
	return [defaults boolForKey:AutoFormatsListBulletsKey];
}
- (void)setAutoFormatsListBullets:(BOOL)value sender:(id)sender {
	[defaults setBool:value forKey:AutoFormatsListBulletsKey];

	[self sendCallbacks:_cmd originalSender:sender];
}

- (BOOL)autoIndentsNewLines {
	return [defaults boolForKey:AutoIndentsNewLinesKey];
}
- (void)setAutoIndentsNewLines:(BOOL)value sender:(id)sender {
	[defaults setBool:value forKey:AutoIndentsNewLinesKey];

	[self sendCallbacks:_cmd originalSender:sender];
}

- (void)setLinksAutoSuggested:(BOOL)value sender:(id)sender {
    [defaults setBool:value forKey:AutoSuggestLinksKey];

	[self sendCallbacks:_cmd originalSender:sender];
}
- (BOOL)linksAutoSuggested {
    return [defaults boolForKey:AutoSuggestLinksKey];
}

- (void)setMakeURLsClickable:(BOOL)value sender:(id)sender {
	[defaults setBool:value forKey:MakeURLsClickableKey];

	[self sendCallbacks:_cmd originalSender:sender];
}
- (BOOL)URLsAreClickable {
	return [defaults boolForKey:MakeURLsClickableKey];
}

- (void)setRTL:(BOOL)value sender:(id)sender {
	[defaults setBool:value forKey:RTLKey];

	[self sendCallbacks:_cmd originalSender:sender];
}
- (BOOL)rtl {
	return [defaults boolForKey:RTLKey];
}

- (BOOL)showWordCount{
	return [defaults boolForKey:ShowWordCount];
}

- (void)setShowWordCount:(BOOL)value{
	[defaults setBool:value forKey:ShowWordCount];
}

- (void)setUseMarkdownImport:(BOOL)value sender:(id)sender {
	[defaults setBool:value forKey:UseMarkdownImportKey];

	[self sendCallbacks:_cmd originalSender:sender];
}
- (BOOL)useMarkdownImport {
	return [defaults boolForKey:UseMarkdownImportKey];
}
- (void)setUseReadability:(BOOL)value sender:(id)sender {
	[defaults setBool:value forKey:UseReadabilityKey];

	[self sendCallbacks:_cmd originalSender:sender];
}
- (BOOL)useReadability {
	return [defaults boolForKey:UseReadabilityKey];
}

- (void)setShowGrid:(BOOL)value sender:(id)sender {
	[defaults setBool:value forKey:ShowGridKey];

	[self sendCallbacks:_cmd originalSender:sender];
}
- (BOOL)showGrid {
	return [defaults boolForKey:ShowGridKey];
}
- (void)setAlternatingRows:(BOOL)value sender:(id)sender {
	[defaults setBool:value forKey:AlternatingRowsKey];

	[self sendCallbacks:_cmd originalSender:sender];
}
- (BOOL)alternatingRows {
	return [defaults boolForKey:AlternatingRowsKey];
}

- (void)setUseAutoPairing:(BOOL)value{
    [defaults setBool:value forKey:UseAutoPairing];
}

- (BOOL)useAutoPairing{
	return [defaults boolForKey:UseAutoPairing];
}

- (void)setShouldHighlightSearchTerms:(BOOL)shouldHighlight sender:(id)sender {
	[defaults setBool:shouldHighlight forKey:HighlightSearchTermsKey];

	[self sendCallbacks:_cmd originalSender:sender];
}
- (BOOL)highlightSearchTerms {
	return [defaults boolForKey:HighlightSearchTermsKey];
}

- (void)setSearchTermHighlightColor:(NSColor*)color sender:(id)sender {
	if (color) {

		searchTermHighlightAttributes = nil;

		[defaults setObject:[NSArchiver archivedDataWithRootObject:color] forKey:SearchTermHighlightColorKey];

		[self sendCallbacks:_cmd originalSender:sender];
	}
}

- (NSColor*)searchTermHighlightColorRaw:(BOOL)isRaw {

	NSData *theData = [defaults dataForKey:SearchTermHighlightColorKey];
	if (theData) {
		NSColor *color = (NSColor *)[NSUnarchiver unarchiveObjectWithData:theData];
		if (isRaw) return color;
		if (color) {
			//nslayoutmanager temporary attributes don't seem to like alpha components, so synthesize translucency using the bg color
			NSColor *fauxAlphaSTHC = [[color colorUsingColorSpaceName:NSCalibratedRGBColorSpace] colorWithAlphaComponent:1.0];
			return [fauxAlphaSTHC blendedColorWithFraction:(1.0 - [color alphaComponent]) ofColor:[self backgroundTextColor]];
		}
	}

	return nil;
}

- (NSDictionary*)searchTermHighlightAttributes {
	NSColor *highlightColor = nil;

	if (!searchTermHighlightAttributes && (highlightColor = [self searchTermHighlightColorRaw:NO])) {
		searchTermHighlightAttributes = @{NSBackgroundColorAttributeName: highlightColor};
	}
	return searchTermHighlightAttributes;

}

- (void)setSoftTabs:(BOOL)value sender:(id)sender {
	[defaults setBool:value forKey:UseSoftTabsKey];

	[self sendCallbacks:_cmd originalSender:sender];
}

- (BOOL)softTabs {
	return [defaults boolForKey:UseSoftTabsKey];
}

- (NSInteger)numberOfSpacesInTab {
	return [defaults integerForKey:NumberOfSpacesInTabKey];
}

BOOL ColorsEqualWith8BitChannels(NSColor *c1, NSColor *c2) {
	//sometimes floating point numbers really don't like to be compared to each other

	CGFloat pRed, pGreen, pBlue, gRed, gGreen, gBlue, pAlpha, gAlpha;
	[[c1 colorUsingColorSpaceName:NSCalibratedRGBColorSpace] getRed:&pRed green:&pGreen blue:&pBlue alpha:&pAlpha];
	[[c2 colorUsingColorSpaceName:NSCalibratedRGBColorSpace] getRed:&gRed green:&gGreen blue:&gBlue alpha:&gAlpha];

#define SCR(__ch) ((int)roundf(((__ch) * 255.0)))

	return (SCR(pRed) == SCR(gRed) && SCR(pBlue) == SCR(gBlue) && SCR(pGreen) == SCR(gGreen) && SCR(pAlpha) == SCR(gAlpha));
}

- (void)resolveNoteBodyFontFromNotationPrefsFromSender:(id)sender {

	NSFont *prefsFont = [notationPrefs baseBodyFont];
	if (prefsFont) {
		NSFont *noteFont = [self noteBodyFont];

		if (![[prefsFont fontName] isEqualToString:[noteFont fontName]] ||
			[prefsFont pointSize] != [noteFont pointSize]) {

			NSLog(@"archived notationPrefs base font does not match current global default font!");
			[self _setNoteBodyFont:prefsFont];

			[self sendCallbacks:_cmd originalSender:sender];
		}
	}
}

- (void)_setNoteBodyFont:(NSFont*)aFont {
	NSFont *oldFont = noteBodyFont;
	noteBodyFont = aFont;

	noteBodyParagraphStyle = nil;

	noteBodyAttributes = nil; //cause method to re-update

	[defaults setObject:[NSArchiver archivedDataWithRootObject:noteBodyFont] forKey:NoteBodyFontKey];

	//restyle any PTF data on the clipboard to the new font
	NSData *ptfData = [[NSPasteboard generalPasteboard] dataForType:NVPTFPboardType];
	NSMutableAttributedString *newString = [[NSMutableAttributedString alloc] initWithRTF:ptfData documentAttributes:nil];

	[newString restyleTextToFont:noteBodyFont usingBaseFont:oldFont];

	if ((ptfData = [newString RTFFromRange:NSMakeRange(0, [newString length]) documentAttributes:nil])) {
		[[NSPasteboard generalPasteboard] setData:ptfData forType:NVPTFPboardType];
	}
}

- (void)setNoteBodyFont:(NSFont*)aFont sender:(id)sender {

	if (aFont) {
		[self _setNoteBodyFont:aFont];

		[self sendCallbacks:_cmd originalSender:sender];
	}
}

- (NSFont*)noteBodyFont {
	BOOL triedOnce = NO;

	if (!noteBodyFont) {
		while (1) {
			@try {
				noteBodyFont = [NSUnarchiver unarchiveObjectWithData:[defaults objectForKey:NoteBodyFontKey]];
			} @catch (NSException *e) {
				NSLog(@"Error trying to unarchive default note body font (%@, %@)", [e name], [e reason]);
			}

			if ((!noteBodyFont || ![noteBodyFont isKindOfClass:[NSFont class]]) && !triedOnce) {
				triedOnce = YES;
				[defaults removeObjectForKey:NoteBodyFontKey];
			} else {
				break;
			}
		}
	}

    return noteBodyFont;
}

- (NSDictionary*)noteBodyAttributes {
	NSFont *bodyFont = [self noteBodyFont];
	if (!noteBodyAttributes && bodyFont) {
		//NSLog(@"notebody att2");

		NSMutableDictionary *attrs = [NSMutableDictionary dictionaryWithObjectsAndKeys:bodyFont, NSFontAttributeName, nil];

		//not storing the foreground color in each note will make the database smaller, and black is assumed when drawing text
		//NSColor *fgColor = [self foregroundTextColor];
		NSColor *fgColor = [[NSApp delegate] foregrndColor];

		if (!ColorsEqualWith8BitChannels([NSColor blackColor], fgColor)) {
			attrs[NSForegroundColorAttributeName] = fgColor;
		}
		// background text color is handled directly by the NSTextView subclass and so does not need to be stored here
		if ([self _bodyFontIsMonospace]) {

		//	NSLog(@"notebody att3");
			NSParagraphStyle *pStyle = [self noteBodyParagraphStyle];
			if (pStyle)
				attrs[NSParagraphStyleAttributeName] = pStyle;
		}
	   /*NSTextWritingDirectionEmbedding*/
		//[NSArray arrayWithObjects:[NSNumber numberWithInt:0], [NSNumber numberWithInt:0], nil], @"NSWritingDirection", //for auto-LTR-RTL text
		noteBodyAttributes = attrs;
	}else {
		//NSLog(@"notebody att4");
		NSMutableDictionary *attrs = [NSMutableDictionary dictionaryWithObjectsAndKeys:bodyFont, NSFontAttributeName, nil];
		NSColor *fgColor = [[NSApp delegate] foregrndColor];

		//	if (!ColorsEqualWith8BitChannels([NSColor blackColor], fgColor)) {
		attrs[NSForegroundColorAttributeName] = fgColor;
		noteBodyAttributes = attrs;
		//	}
	}

	return noteBodyAttributes;
}

- (BOOL)_bodyFontIsMonospace {
	NSString *name = [noteBodyFont fontName];
	return (([noteBodyFont isFixedPitch] || [name caseInsensitiveCompare:@"Osaka-Mono"] == NSOrderedSame) &&
			[name caseInsensitiveCompare:@"MS-PGothic"] != NSOrderedSame);
}

- (NSParagraphStyle*)noteBodyParagraphStyle {
	NSFont *bodyFont = [self noteBodyFont];

	if (!noteBodyParagraphStyle && bodyFont) {
		NSInteger numberOfSpaces = [self numberOfSpacesInTab];
		NSMutableString *sizeString = [[NSMutableString alloc] initWithCapacity:numberOfSpaces];
		while (numberOfSpaces--) {
			[sizeString appendString:@" "];
		}
		NSDictionary *sizeAttribute = @{NSFontAttributeName: bodyFont};
		float sizeOfTab = [sizeString sizeWithAttributes:sizeAttribute].width;

		noteBodyParagraphStyle = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];

		NSTextTab *textTabToBeRemoved;
		NSEnumerator *enumerator = [[noteBodyParagraphStyle tabStops] objectEnumerator];
		while ((textTabToBeRemoved = [enumerator nextObject])) {
			[noteBodyParagraphStyle removeTabStop:textTabToBeRemoved];
		}
		//[paragraphStyle setHeadIndent:sizeOfTab]; //for soft-indents, this would probably have to be applied contextually, and heaven help us for soft tabs

		[noteBodyParagraphStyle setDefaultTabInterval:sizeOfTab];
	}

	return noteBodyParagraphStyle;
}

- (void)setForegroundTextColor:(NSColor*)aColor sender:(id)sender {
	if (aColor) {
		noteBodyAttributes = nil;

		[defaults setObject:[NSArchiver archivedDataWithRootObject:aColor] forKey:ForegroundTextColorKey];

		[self sendCallbacks:_cmd originalSender:sender];
	}
}

- (NSColor*)foregroundTextColor {
	NSData *theData = [defaults dataForKey:ForegroundTextColorKey];
	if (theData) return (NSColor *)[NSUnarchiver unarchiveObjectWithData:theData];
	return nil;
}

- (void)setBackgroundTextColor:(NSColor*)aColor sender:(id)sender {

	if (aColor) {
		//highlight color is based on blended-alpha version of background color
		//(because nslayoutmanager temporary attributes don't seem to like alpha components)
		//so it's necessary to invalidate the effective cache of that computed highlight color
		searchTermHighlightAttributes = nil;

		[defaults setObject:[NSArchiver archivedDataWithRootObject:aColor] forKey:BackgroundTextColorKey];

		[self sendCallbacks:_cmd originalSender:sender];
	}
}

- (NSColor*)backgroundTextColor {
	//don't need to cache the unarchived color, as it's not used in a random-access pattern

	NSData *theData = [defaults dataForKey:BackgroundTextColorKey];
	if (theData) return (NSColor *)[NSUnarchiver unarchiveObjectWithData:theData];

	return nil;
}

- (BOOL)tableColumnsShowPreview {
	return [defaults boolForKey:TableColumnsHaveBodyPreviewKey];
}

- (void)setTableColumnsShowPreview:(BOOL)showPreview sender:(id)sender {
	[defaults setBool:showPreview forKey:TableColumnsHaveBodyPreviewKey];

	[self sendCallbacks:_cmd originalSender:sender];
}

- (float)tableFontSize {
	return [defaults floatForKey:TableFontSizeKey];
}

- (void)setTableFontSize:(float)fontSize sender:(id)sender {
	[defaults setFloat:fontSize forKey:TableFontSizeKey];

	[self sendCallbacks:_cmd originalSender:sender];
}

- (NVTableColumnOption)visibleTableColumnsWithCount:(out NSUInteger *)outCount {
	if (visibleTableColumns == NVTableColumnOptionNone) {
		NSArray *legacy = [defaults arrayForKey:NVTableColumnsVisibleLegacyKey];
		if (legacy) {
			visibleTableColumns = NVTableColumnOptionForIdentifiers(legacy);
			[defaults setInteger:visibleTableColumns forKey:NVTableColumnsVisibleKey];
			[defaults removeObjectForKey:NVTableColumnsVisibleLegacyKey];
			[defaults synchronize];
		} else {
			visibleTableColumns = [defaults integerForKey:NVTableColumnsVisibleKey];
		}
	}
	
	NSUInteger count = NVTableColumnCountForOption(visibleTableColumns);
	if (outCount) *outCount = count;
	
	if (!count) {
		[self addTableColumn:NVUIAttributeTitle sender:self];
	}
	
	return visibleTableColumns;
}

- (NVTableColumnOption)visibleTableColumns {
	return [self visibleTableColumnsWithCount:NULL];
}

- (void)removeTableColumn:(NVUIAttribute)column sender:(id)sender {
	visibleTableColumns &= ~NVUIAttributeOption(column);
	[defaults setInteger:visibleTableColumns forKey:NVTableColumnsVisibleKey];
	[self sendCallbacks:_cmd originalSender:sender];
}

- (void)addTableColumn:(NVUIAttribute)column sender:(id)sender {
	if (![self visibleTableColumnsIncludes:column]) {
		visibleTableColumns |= NVUIAttributeOption(column);
		[defaults setInteger:visibleTableColumns forKey:NVTableColumnsVisibleKey];
		[self sendCallbacks:_cmd originalSender:sender];
	}
}

- (NSUInteger)numberOfVisibleTableColumns {
	NSUInteger count;
	[self visibleTableColumnsWithCount:&count];
	return count;
}

- (BOOL)visibleTableColumnsIncludes:(NVUIAttribute)column {
	return NVTableColumnEnabled(self.visibleTableColumns, column);
}

- (NVUIAttribute)sortedTableColumn
{
	NSString *legacy = [defaults objectForKey:NVTableSortColumnLegacyKey];
	if (legacy) {
		[defaults setInteger:NVUIAttributeForIdentifier(legacy) forKey:NVTableSortColumnKey];
		[defaults removeObjectForKey:NVTableSortColumnLegacyKey];
	}
	return [defaults integerForKey:NVTableSortColumnKey];
}

- (void)setSortedTableColumn:(NVUIAttribute)attribute reversed:(BOOL)reversed sender:(id)sender
{
	[defaults setBool:reversed forKey:TableIsReverseSortedKey];
    [defaults setObject:@(attribute) forKey:NVTableSortColumnKey];
	[self sendCallbacks:_cmd originalSender:sender];
}

- (BOOL)tableIsReverseSorted {
    return [defaults boolForKey:TableIsReverseSortedKey];
}

- (void)setHorizontalLayout:(BOOL)value sender:(id)sender {
	if ([self horizontalLayout] != value) {
		[defaults setBool:value forKey:HorizontalLayoutKey];

		[self sendCallbacks:_cmd originalSender:sender];
	}
}
- (BOOL)horizontalLayout {
	return [defaults boolForKey:HorizontalLayoutKey];
}

- (NSString*)lastSelectedPreferencesPane {
	return [defaults stringForKey:LastSelectedPreferencesPaneKey];
}
- (void)setLastSelectedPreferencesPane:(NSString*)pane sender:(id)sender {
	[defaults setObject:pane forKey:LastSelectedPreferencesPaneKey];

	[self sendCallbacks:_cmd originalSender:sender];
}

- (void)setLastSearchString:(NSString*)string selectedNote:(id<SynchronizedNote>)aNote scrollOffsetForTableView:(NotesTableView*)tv sender:(id)sender {

	NSMutableString *stringMinusBreak = [string mutableCopy];
	[stringMinusBreak replaceOccurrencesOfString:@"\n" withString:@" " options:NSLiteralSearch range:NSMakeRange(0, [stringMinusBreak length])];

	[defaults setObject:stringMinusBreak forKey:LastSearchStringKey];

	NSString *uuidString = aNote.uniqueNoteID.UUIDString;

	[defaults setObject:uuidString forKey:LastSelectedNoteUUIDBytesKey];

	double offset = [tv distanceFromRow:[(NotationController*)[tv dataSource] indexInFilteredListForNoteIdenticalTo:(NoteObject *)aNote] forVisibleArea:[tv visibleRect]];
	[defaults setDouble:offset forKey:LastScrollOffsetKey];

	[self sendCallbacks:_cmd originalSender:sender];
}

- (NSString*)lastSearchString {
	return [defaults objectForKey:LastSearchStringKey];
}

- (NSUUID *)UUIDOfLastSelectedNote
{
	NSString *uuidString = [defaults objectForKey:LastSelectedNoteUUIDBytesKey];
	if (uuidString) {
		return [[NSUUID alloc] initWithUUIDString:uuidString];
	}
	return nil;
}

- (double)scrollOffsetOfLastSelectedNote {
	return [defaults doubleForKey:LastScrollOffsetKey];
}

- (void)saveCurrentBookmarksFromSender:(id)sender {
	//run this during quit and when saved searches change?
	NSArray *bookmarks = [bookmarksController dictionaryReps];
	if (bookmarks) {
		[defaults setObject:bookmarks forKey:BookmarksKey];
		[defaults setBool:[bookmarksController isVisible] forKey:@"BookmarksVisible"];
	}

	[self sendCallbacks:_cmd originalSender:sender];
}

- (BookmarksController*)bookmarksController {
	if (!bookmarksController) {
		bookmarksController = [[BookmarksController alloc] initWithBookmarks:[defaults arrayForKey:BookmarksKey]];
	}
	return bookmarksController;
}

- (void)setAliasDataForDefaultDirectory:(NSData*)alias sender:(id)sender {
    [defaults setObject:alias forKey:DirectoryAliasKey];

	[self sendCallbacks:_cmd originalSender:sender];
}

- (NSData*)aliasDataForDefaultDirectory {
    return [defaults dataForKey:DirectoryAliasKey];
}

- (NSString*)displayNameForDefaultDirectoryWithFSRef:(FSRef*)fsRef {

    if (!fsRef)
	return nil;

    if (IsZeros(fsRef, sizeof(FSRef))) {
	if (![[self aliasDataForDefaultDirectory] fsRefAsAlias:fsRef])
	    return nil;
    }
    CFStringRef displayName = NULL;
    if (LSCopyDisplayNameForRef(fsRef, &displayName) == noErr) {
		return (__bridge_transfer NSString*)displayName;
    }
    return nil;
}

- (NSString*)humanViewablePathForDefaultDirectory {
    //resolve alias to fsref
    FSRef targetRef;
    if ([[self aliasDataForDefaultDirectory] fsRefAsAlias:&targetRef]) {
	//follow the parent fsrefs up the tree, calling LSCopyDisplayNameForRef, hoping that the root is a drive name

	NSMutableArray *directoryNames = [NSMutableArray arrayWithCapacity:4];
	FSRef parentRef, *currentRef = &targetRef;

	OSStatus err = noErr;

	do {

	    if ((err = FSGetCatalogInfo(currentRef, kFSCatInfoNone, NULL, NULL, NULL, &parentRef)) == noErr) {

		CFStringRef displayName = NULL;
		if ((err = LSCopyDisplayNameForRef(currentRef, &displayName)) == noErr) {

		    if (displayName) {
				[directoryNames insertObject:(__bridge_transfer NSString *)displayName atIndex:0];
		    }
		}

		currentRef = &parentRef;
	    }
	} while (err == noErr);

	//build new string delimited by triangles like pages in its recent items menu
	return [directoryNames componentsJoinedByString:@" : "];

    }

    return nil;
}

- (void)synchronize {
    [defaults synchronize];
}



//elasticthreads' work

- (void)setManagesTextWidthInWindow:(BOOL)manageIt sender:(id)sender{
    [defaults setBool:manageIt forKey:KeepsMaxTextWidth];
	[self sendCallbacks:_cmd originalSender:sender];
}

- (BOOL)managesTextWidthInWindow{
	return [defaults boolForKey:KeepsMaxTextWidth];
}

- (CGFloat)maxNoteBodyWidth{

	return [[defaults objectForKey:NoteBodyMaxWidth]floatValue];
}

- (void)setMaxNoteBodyWidth:(CGFloat)maxWidth sender:(id)sender{
	[defaults setObject:[NSNumber numberWithFloat:maxWidth] forKey:NoteBodyMaxWidth];
//	[defaults synchronize];
	[self sendCallbacks:_cmd originalSender:sender];
}



@end
