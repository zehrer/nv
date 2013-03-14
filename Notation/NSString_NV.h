//
//  NSString_NV.h
//  Notation
//
//  Created by Zachary Schneirov on 1/13/06.

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

@class NoteObject;

@interface NSString (NV)

extern void resetCurrentDayTime();

+ (NSString *)ntn_relativeDateStringWithDate:(NSDate *)date;

CFDateFormatterRef simplenoteDateFormatter(NSInteger lowPrecision);

+ (NSString *)simplenoteDateWithAbsoluteTime:(CFAbsoluteTime)absTime;

- (CFAbsoluteTime)absoluteTimeFromSimplenoteDate;

- (CFArrayRef)copyRangesOfWordsInString:(NSString *)findString inRange:(NSRange)limitRange;

+ (NSString *)customPasteboardTypeOfCode:(NSInteger)code;

- (NSString *)stringAsSafePathExtension;

- (NSString *)filenameExpectingAdditionalCharCount:(NSInteger)charCount;

- (NSString *)fourCharTypeString;

- (BOOL)isAMachineDirective;

- (void)copyItemToPasteboard:(id)sender;

- (NSString *)syntheticTitleAndSeparatorWithContext:(NSString **)sepStr bodyLoc:(NSUInteger *)bodyLoc maxTitleLen:(NSUInteger)maxTitleLen;

- (NSString *)syntheticTitleAndSeparatorWithContext:(NSString **)sepStr bodyLoc:(NSUInteger *)bodyLoc
										   oldTitle:(NSString *)oldTitle maxTitleLen:(NSUInteger)maxTitleLen;

- (NSString *)syntheticTitleAndTrimmedBody:(NSString **)newBody;

+ (NSString *)tabbifiedStringWithNumberOfSpaces:(NSUInteger)origNumSpaces tabWidth:(NSUInteger)tabWidth usesTabs:(BOOL)usesTabs;

- (NSUInteger)numberOfLeadingSpacesFromRange:(NSRange *)range tabWidth:(NSUInteger)tabWidth;

BOOL IsHardLineBreakUnichar(unichar uchar, NSString *str, NSUInteger charIndex);

- (NSString *)ntn_copyLowercaseASCIIString;

- (NSString *)stringWithPercentEscapes;

- (BOOL)superficiallyResemblesAnHTTPURL;

+ (NSString *)reasonStringFromCarbonFSError:(OSStatus)err;

- (NSArray *)labelCompatibleWords;

- (NSData *)decodeBase64;

@property(nonatomic, readonly) BOOL ntn_containsHighASCII;
@property(nonatomic, readonly) BOOL couldCopyLowercaseASCIIString;

//- (NSTextView*)textViewWithFrame:(NSRect*)theFrame;

+ (NSString *)ntn_stringWithRandomizedFileName;

- (void)ntn_enumerateRangesOfString:(NSString *)aString options:(NSStringCompareOptions)opts range:(NSRange)searchRange usingBlock:(void (^)(NSRange, BOOL *))block;

@end

@interface NSMutableString (NV)
- (void)replaceTabsWithSpacesOfWidth:(NSInteger)tabWidth;

+ (NSMutableString *)ntn_newShortLivedStringFromURL:(NSURL *)URL;

+ (NSMutableString *)ntn_newShortLivedStringFromData:(NSData *)data guessedEncoding:(out NSStringEncoding *)outEncoding withURL:(NSURL *)URL;

@end

@interface NSScanner (NV)
- (void)scanContextualSeparator:(NSString **)sepStr withPrecedingString:(NSString *)firstLine;
@end

@interface NSCharacterSet (NV)

+ (NSCharacterSet *)labelSeparatorCharacterSet;

+ (NSCharacterSet *)listBulletsCharacterSet;

@end


@interface NSEvent (NV)
- (unichar)firstCharacter;

- (unichar)firstCharacterIgnoringModifiers;
@end
