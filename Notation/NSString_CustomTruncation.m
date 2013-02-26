//
//  NSString_CustomTruncation.m
//  Notation
//
//  Created by Zachary Schneirov on 1/12/11.

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


#import "NSString_CustomTruncation.h"
#import "GlobalPrefs.h"
#import "BufferUtils.h"

static const u_int32_t offsetsFromUTF8[6] = {
	0x00000000UL, 0x00003080UL, 0x000E2080UL,
	0x03C82080UL, 0xFA082080UL, 0x82082080UL
};

#define isutf(c) (((c)&0xC0)!=0x80)

/* reads the next utf-8 sequence out of a string, updating an index */
static force_inline u_int32_t u8_nextchar(const char *s, size_t *i)  {
	u_int32_t ch = 0;
	size_t sz = 0;

	do {
		ch <<= 6;
		ch += (unsigned char) s[(*i)];
		sz++;
	} while (s[*i] && (++(*i)) && !isutf(s[*i]));
	ch -= offsetsFromUTF8[sz - 1];

	return ch;
}

static void replace_breaks_utf8(char *s, size_t up_to_len) {
	//needed to detect NSLineSeparatorCharacter and NSParagraphSeparatorCharacter

	if (!s) return;

	size_t i = 0, lasti = 0;
	u_int32_t c;

	while (i < up_to_len && s[i]) {
		c = u8_nextchar(s, &i);

		//get rid of any kind of funky whitespace-esq character
		if (c == 0x0009 || c == 0x000a || c == 0x000d || c == 0x0003 || c == 0x2029 || c == 0x2028 || c == 0x000c) {
			//fill in the entire UTF sequence with spaces
			char *cur_s = (char *) &s[lasti];
			//			printf("\n");
			do {
				//				printf("%X ", (u_int32_t)*cur_s);
				*cur_s = ' ';
			} while (++cur_s < &s[i]);
		}
		lasti = i;
	}
}

static void replace_breaks(char *str, size_t up_to_len) {
	//traverses string to up_to_len chars or NULL, whichever comes first
	//replaces any occurance of \n, \r, or \t with a space

	if (!str) return;

	size_t i = 0;
	int c;
	char *s = str;
	do {
		c = *s;
		if (c == 0x0009 || c == 0x000a || c == 0x000d || c == 0x0003 || c == 0x000c) {
			*s = ' ';
		}
	} while (++i < up_to_len && *(s++) != 0);
}

@implementation NSString (CustomTruncation)

static NSMutableParagraphStyle *LineBreakingStyle();

static NSDictionary *GrayTextAttributes();

static NSDictionary *LineTruncAttributes();

static size_t EstimatedCharCountForWidth(float upToWidth);

- (NSString *)truncatedPreviewStringOfLength:(NSUInteger)bodyCharCount {
	CFStringRef cfSelf = (__bridge CFStringRef)self;
	//try to get the underlying C-string buffer and copy only part of it
	//this won't be exact because chars != bytes, but that's alright because it is expected to be further truncated by an NSTextFieldCell
	CFStringEncoding bodyPreviewEncoding = CFStringGetFastestEncoding(cfSelf);
	const char *cStrPtr = CFStringGetCStringPtr(cfSelf, bodyPreviewEncoding);
	char *bodyPreviewBuffer = calloc(bodyCharCount + 1, sizeof(char));
	CFIndex usedBufLen = bodyCharCount;

	if (bodyCharCount > 1) {
		if (cStrPtr && kCFStringEncodingUTF8 != bodyPreviewEncoding && kCFStringEncodingUnicode != bodyPreviewEncoding) {
			//only attempt to copy the buffer directly if the fastest encoding is not a unicode variant
			memcpy(bodyPreviewBuffer, cStrPtr, bodyCharCount);
		} else {
			bodyPreviewEncoding = kCFStringEncodingUTF8;
			if ([self length] == bodyCharCount) {
				//if this is supposed to be the entire string, don't waffle around
				const char *fullUTF8String = [self UTF8String];
				usedBufLen = bodyCharCount = strlen(fullUTF8String);
				bodyPreviewBuffer = realloc(bodyPreviewBuffer, bodyCharCount + 1);
				memcpy(bodyPreviewBuffer, fullUTF8String, bodyCharCount + 1);
			} else if (!CFStringGetBytes(cfSelf, CFRangeMake(0, bodyCharCount), bodyPreviewEncoding, ' ', FALSE,
										  (UInt8 *) bodyPreviewBuffer, bodyCharCount + 1, &usedBufLen)) {
				NSLog(@"can't get utf8 string from '%@' (charcount: %lu)", self, (unsigned long) bodyCharCount);
				free(bodyPreviewBuffer);
				return nil;
			}
			
		}
	}

	
	
	//if bodyPreviewBuffer is a UTF-8 encoded string, then examine the string one UTF-8 sequence at a time to catch multi-byte breaks
	if (bodyPreviewEncoding == kCFStringEncodingUTF8) {
		replace_breaks_utf8(bodyPreviewBuffer, bodyCharCount);
	} else {
		replace_breaks(bodyPreviewBuffer, bodyCharCount);
	}

	NSString *truncatedBodyString = [[NSString alloc] initWithBytesNoCopy:bodyPreviewBuffer length:usedBufLen encoding:CFStringConvertEncodingToNSStringEncoding(bodyPreviewEncoding) freeWhenDone:YES];
	if (!truncatedBodyString) {
		free(bodyPreviewBuffer);
		NSLog(@"can't create cfstring from '%@' (cstr lens: %lu/%ld) with encoding %u (fastest = %u)", self, (unsigned long) bodyCharCount, (long) usedBufLen, bodyPreviewEncoding, bodyPreviewEncoding);
		return nil;
	}
	return truncatedBodyString;
}

static NSMutableDictionary *titleTruncAttrs = nil;

void ResetFontRelatedTableAttributes() {
	titleTruncAttrs = nil;
}

static NSMutableParagraphStyle *LineBreakingStyle() {
	static NSMutableParagraphStyle *lineBreaksStyle = nil;
	if (!lineBreaksStyle) {
		lineBreaksStyle = [[NSMutableParagraphStyle alloc] init];
		[lineBreaksStyle setLineBreakMode:NSLineBreakByTruncatingTail];
		[lineBreaksStyle setTighteningFactorForTruncation:0.0];
	}
	return lineBreaksStyle;
}

static NSDictionary *GrayTextAttributes() {
	static NSDictionary *grayTextAttributes = nil;
	if (!grayTextAttributes) grayTextAttributes = @{NSForegroundColorAttributeName : [NSColor grayColor]};
	return grayTextAttributes;
}

static NSDictionary *LineTruncAttributes() {
	static NSDictionary *lineTruncAttributes = nil;
	if (!lineTruncAttributes) lineTruncAttributes = @{NSParagraphStyleAttributeName : LineBreakingStyle()};
	return lineTruncAttributes;
}

NSDictionary *LineTruncAttributesForTitle() {
	if (!titleTruncAttrs) {
		GlobalPrefs *prefs = [GlobalPrefs defaultPrefs];
		unsigned int bitmap = [prefs tableColumnsBitmap];
		float fontSize = [prefs tableFontSize];
		BOOL usesBold = ColumnIsSet(NoteLabelsColumn, bitmap) || ColumnIsSet(NoteDateCreatedColumn, bitmap) ||
				ColumnIsSet(NoteDateModifiedColumn, bitmap) || [prefs tableColumnsShowPreview];

		titleTruncAttrs = [@{NSParagraphStyleAttributeName : [LineBreakingStyle() mutableCopy],
				NSFontAttributeName : (usesBold ? [NSFont boldSystemFontOfSize:fontSize] : [NSFont systemFontOfSize:fontSize])} mutableCopy];

		if (ColumnIsSet(NoteDateCreatedColumn, bitmap) || ColumnIsSet(NoteDateModifiedColumn, bitmap)) {
			//account for right-"aligned" date string, which will be relatively constant, so this can be cached
			[titleTruncAttrs[NSParagraphStyleAttributeName] setTailIndent:fontSize * -4.6]; //avg of -55 for ~11-12 font size
		}
	}
	return titleTruncAttrs;
}

static size_t EstimatedCharCountForWidth(float upToWidth) {
	return (size_t) (upToWidth / ([[GlobalPrefs defaultPrefs] tableFontSize] / 2.5f));
}

//LineTruncAttributesForTags would be variable, depending on the note; each preview string will have its own copy of the nsdictionary

- (NSAttributedString *)attributedMultiLinePreviewFromBodyText:(NSAttributedString *)bodyText upToWidth:(float)upToWidth intrusionWidth:(float)intWidth {
	//first line is title, truncated to a shorter width to account for date/time, using a negative -[NSMutableParagraphStyle setTailIndent:] value
	//next "two" lines are wrapped body text, with a character-count estimation of essentially double that of a single-line preview
	//also with an independent tailindent to account for a separately-drawn tags-string, if tags exist
	//upToWidth will be used to manually truncate note-bodies only, and should be the full column width available
	//intWidth will typically be the width of the tags string or other representation

	size_t bodyCharCount = (EstimatedCharCountForWidth(upToWidth) * 2) - EstimatedCharCountForWidth(intWidth);
	bodyCharCount = MIN(bodyCharCount, [bodyText length]);

	NSString *truncatedBodyString = [[bodyText string] truncatedPreviewStringOfLength:bodyCharCount];
	if (!truncatedBodyString) return nil;

	NSMutableString *unattributedPreview = [[NSMutableString alloc] initWithCapacity:bodyCharCount + [self length] + 2];

	[unattributedPreview appendString:self];
	[unattributedPreview appendString:@"\n"];
	[unattributedPreview appendString:truncatedBodyString];

	NSMutableAttributedString *attributedStringPreview = [[NSMutableAttributedString alloc] initWithString:unattributedPreview];

	//title is black (no added colors) and truncated with LineTruncAttributesForTitle()
	//body is gray and truncated with a variable tail indent, depending on intruding tags

	NSDictionary *bodyTruncDict = @{NSParagraphStyleAttributeName : [LineBreakingStyle() mutableCopy], NSForegroundColorAttributeName : [NSColor grayColor]};
	//set word-wrapping to let -[NSCell setTruncatesLastVisibleLine:] work
	[bodyTruncDict[NSParagraphStyleAttributeName] setLineBreakMode:NSLineBreakByWordWrapping];

	if (intWidth > 0.0) {
		//there are tags; add an appropriately-sized tail indent to the body
		[bodyTruncDict[NSParagraphStyleAttributeName] setTailIndent:-intWidth];
	}

	[attributedStringPreview addAttributes:LineTruncAttributesForTitle() range:NSMakeRange(0, [self length])];
	[attributedStringPreview addAttributes:bodyTruncDict range:NSMakeRange([self length] + 1, [unattributedPreview length] - ([self length] + 1))];


	return attributedStringPreview;
}

- (NSAttributedString *)attributedSingleLineTitle {
	//show only a single line, with a tail indent large enough for both the date and tags (if there are any)
	//because this method displays the title only, manual truncation isn't really necessary
	//the highlighted version of this string should be bolded

	NSMutableAttributedString *titleStr = [[NSMutableAttributedString alloc] initWithString:self attributes:LineTruncAttributesForTitle()];

	return titleStr;
}


- (NSAttributedString *)attributedSingleLinePreviewFromBodyText:(NSAttributedString *)bodyText upToWidth:(float)upToWidth {

	//compute the char count for this note based on the width of the title column and the length of the receiver
	size_t bodyCharCount = EstimatedCharCountForWidth(upToWidth) - [self length];
	bodyCharCount = MIN(bodyCharCount, [bodyText length]);

	NSString *truncatedBodyString = [[bodyText string] truncatedPreviewStringOfLength:bodyCharCount];
	if (!truncatedBodyString) return nil;

	NSMutableString *unattributedPreview = [self mutableCopy];
	NSString *delimiter = NSLocalizedString(@" option-shift-dash ", @"title/description delimiter");
	[unattributedPreview appendString:delimiter];
	[unattributedPreview appendString:truncatedBodyString];

	NSMutableAttributedString *attributedStringPreview = [[NSMutableAttributedString alloc] initWithString:unattributedPreview attributes:LineTruncAttributes()];
	[attributedStringPreview addAttributes:GrayTextAttributes() range:NSMakeRange([self length], [unattributedPreview length] - [self length])];


	return attributedStringPreview;
}


@end
