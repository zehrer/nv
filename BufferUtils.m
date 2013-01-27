/*
 *  BufferUtils.c
 *  Notation
 *
 *  Created by Zachary Schneirov on 1/15/06.
 */

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


#include "BufferUtils.h"

static const unsigned char gsToLowerMap[256] = {
		'\0', 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, '\t',
		'\n', 0x0b, 0x0c, '\r', 0x0e, 0x0f, 0x10, 0x11, 0x12, 0x13,
		0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1a, 0x1b, 0x1c, 0x1d,
		0x1e, 0x1f, ' ', '!', '"', '#', '$', '%', '&', '\'',
		'(', ')', '*', '+', ',', '-', '.', '/', '0', '1',
		'2', '3', '4', '5', '6', '7', '8', '9', ':', ';',
		'<', '=', '>', '?', '@', 'a', 'b', 'c', 'd', 'e',
		'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm', 'n', 'o',
		'p', 'q', 'r', 's', 't', 'u', 'v', 'w', 'x', 'y',
		'z', '[', '\\', ']', '^', '_', '`', 'a', 'b', 'c',
		'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm',
		'n', 'o', 'p', 'q', 'r', 's', 't', 'u', 'v', 'w',
		'x', 'y', 'z', '{', '|', '}', '~', 0x7f, 0x80, 0x81,
		0x82, 0x83, 0x84, 0x85, 0x86, 0x87, 0x88, 0x89, 0x8a, 0x8b,
		0x8c, 0x8d, 0x8e, 0x8f, 0x90, 0x91, 0x92, 0x93, 0x94, 0x95,
		0x96, 0x97, 0x98, 0x99, 0x9a, 0x9b, 0x9c, 0x9d, 0x9e, 0x9f,
		0xa0, 0xa1, 0xa2, 0xa3, 0xa4, 0xa5, 0xa6, 0xa7, 0xa8, 0xa9,
		0xaa, 0xab, 0xac, 0xad, 0xae, 0xaf, 0xb0, 0xb1, 0xb2, 0xb3,
		0xb4, 0xb5, 0xb6, 0xb7, 0xb8, 0xb9, 0xba, 0xbb, 0xbc, 0xbd,
		0xbe, 0xbf, 0xc0, 0xc1, 0xc2, 0xc3, 0xc4, 0xc5, 0xc6, 0xc7,
		0xc8, 0xc9, 0xca, 0xcb, 0xcc, 0xcd, 0xce, 0xcf, 0xd0, 0xd1,
		0xd2, 0xd3, 0xd4, 0xd5, 0xd6, 0xd7, 0xd8, 0xd9, 0xda, 0xdb,
		0xdc, 0xdd, 0xde, 0xdf, 0xe0, 0xe1, 0xe2, 0xe3, 0xe4, 0xe5,
		0xe6, 0xe7, 0xe8, 0xe9, 0xea, 0xeb, 0xec, 0xed, 0xee, 0xef,
		0xf0, 0xf1, 0xf2, 0xf3, 0xf4, 0xf5, 0xf6, 0xf7, 0xf8, 0xf9,
		0xfa, 0xfb, 0xfc, 0xfd, 0xfe, 0xff};

#if !defined(MIN)
#define MIN(A,B)	({ __typeof__(A) __a = (A); __typeof__(B) __b = (B); __a < __b ? __a : __b; })
#endif

#if !defined(MAX)
#define MAX(A,B)	({ __typeof__(A) __a = (A); __typeof__(B) __b = (B); __a < __b ? __b : __a; })
#endif

static u_int32_t u8_nextchar(const char *s, size_t *i);

char *replaceString(char *oldString, const char *newString) {
	size_t newLen = strlen(newString) + 1;

	//realloc is smart enough to do better memory management than we can do right here
	char *resizedString = (char *) realloc(oldString, newLen);
	memmove(resizedString, newString, newLen);

	return resizedString;
}

int IsZeros(const void *s1, size_t n) {
	if (n != 0) {
		const unsigned char *p1 = s1;

		do {
			if (*p1++ != 0)
				return (0);
		} while (--n != 0);
	}
	return (1);
}

void modp_tolower_copy(char *dest, const char *str, size_t len) {
	size_t i;
	unsigned long long eax, ebx;
	const uint8_t *ustr = (const uint8_t *) str;
	const size_t leftover = len % 4;
	const size_t imax = len / 4;
	const uint32_t *s = (const uint32_t *) str;
	unsigned long long *d = (unsigned long long *) dest;
	for (i = 0; i != imax; ++i) {
		eax = s[i];
		/*
		 * This is based on the algorithm by Paul Hsieh
		 * http://www.azillionmonkeys.com/qed/asmexample.html
		 */
#if __LP64__ || NS_BUILD_32_LIKE_64
		ebx = (0x7f7f7f7f7f7f7f7fllu & eax) + 0x2525252525252525llu;
		ebx = (0x7f7f7f7f7f7f7f7fllu & ebx) + 0x1a1a1a1a1a1a1a1allu;
		ebx = ((ebx & ~eax) >> 2) & 0x2020202020202020llu;
#else
		ebx = (0x7f7f7f7fu & eax) + 0x25252525u;
		ebx = (0x7f7f7f7fu & ebx) + 0x1a1a1a1au;
		ebx = ((ebx & ~eax) >> 2)  & 0x20202020u;
#endif
		*d++ = eax + ebx;
	}

	i = imax * 4;
	dest = (char *) d;
	switch (leftover) {
#if __LP64__ || NS_BUILD_32_LIKE_64
		case 7:
			*dest++ = (char) gsToLowerMap[ustr[i++]];
		case 6:
			*dest++ = (char) gsToLowerMap[ustr[i++]];
		case 5:
			*dest++ = (char) gsToLowerMap[ustr[i++]];
		case 4:
			*dest++ = (char) gsToLowerMap[ustr[i++]];
#endif
		case 3:
			*dest++ = (char) gsToLowerMap[ustr[i++]];
		case 2:
			*dest++ = (char) gsToLowerMap[ustr[i++]];
		case 1:
			*dest++ = (char) gsToLowerMap[ustr[i]];
		case 0:
			*dest = '\0';
	}
}


int ContainsUInteger(const NSUInteger *uintArray, size_t count, NSUInteger auint) {
	size_t i;
	for (i = 0; i < count; i++) {
		if (uintArray[i] == auint) return 1;
	}
	return 0;
}

unsigned DumbWordCount(const void *s1, size_t len) {

	unsigned count = len > 0;
	//we could do a lot more here, but we don't.
	const void *ptr = s1;
	while ((ptr = memchr(ptr + 1, 0x20, len))) {
		count++;
	}
//	printf("bacon: %u\n", count);

	return count;
}

#if 0
//this does not use the user's defined date styles
const double dayInSeconds = 86400.0;
enum {ThisDay = 0, NextDay, PriorDay};
CFStringRef GetRelativeDateStringFromTimeAndLocaleInfo(CFAbsoluteTime time, CFStringRef *designations, char **months) {
    static CFAbsoluteTime currentDay = 0.0;
    if (currentDay == 0.0)
	currentDay = ceil(CFAbsoluteTimeGetCurrent() / dayInSeconds) * dayInSeconds;

    CFGregorianDate unitsDate = CFAbsoluteTimeGetGregorianDate(time, NULL);
    
    CFAbsoluteTime timeDay = ceil(time / dayInSeconds) * dayInSeconds;
    if (timeDay == currentDay) {
	return designations[ThisDay];
    } else if (timeDay == currentDay + dayInSeconds) {
	return designations[NextDay];
    } else if (timeDay == currentDay - dayInSeconds) {
	return designations[PriorDay];
    }
    
    return CFStringCreateWithFormat(kCFAllocatorDefault, NULL, CFSTR("%s %u, %u  %u:%u %s"), 
				    months[unitsDate.month], unitsDate.day, unitsDate.year, unitsDate.hour, unitsDate.minute, amppmStr);
}
#endif

COMPILE_ASSERT(sizeof(PerDiskInfo) == 16, PER_DISK_INFO_MUST_BE_16_BYTES);

void CopyPerDiskInfoGroupsToOrder(PerDiskInfo **flippedGroups, NSUInteger *existingCount, const uint8_t *perDiskGroupsBuffer, size_t bufferSize, NSInteger toHostOrder) {
	//for decoding and encoding an array of PerDiskInfo structs as a single buffer
	//swap between host order and big endian
	//resizes flippedPairs if it is too small (based on *existingCount)

	NSUInteger i, count = bufferSize / sizeof(PerDiskInfo);

	*flippedGroups = calloc(count, sizeof(PerDiskInfo));
	PerDiskInfo *perDiskGroups = (PerDiskInfo *)perDiskGroupsBuffer;
	PerDiskInfo *newGroups = *flippedGroups;

	//does this need to flip the entire struct, too?
	if (toHostOrder) {
		for (i = 0; i < count; i++) {
			PerDiskInfo group = perDiskGroups[i];
			newGroups[i].attrTime.highSeconds = CFSwapInt16BigToHost(group.attrTime.highSeconds);
			newGroups[i].attrTime.lowSeconds = CFSwapInt32BigToHost(group.attrTime.lowSeconds);
			newGroups[i].attrTime.fraction = CFSwapInt16BigToHost(group.attrTime.fraction);
			newGroups[i].diskIDIndex = CFSwapInt32BigToHost(group.diskIDIndex);
		}
	} else {
		for (i = 0; i < count; i++) {
			PerDiskInfo group = perDiskGroups[i];
			newGroups[i].attrTime.highSeconds = CFSwapInt16HostToBig(group.attrTime.highSeconds);
			newGroups[i].attrTime.lowSeconds = CFSwapInt32HostToBig(group.attrTime.lowSeconds);
			newGroups[i].attrTime.fraction = CFSwapInt16HostToBig(group.attrTime.fraction);
			newGroups[i].diskIDIndex = CFSwapInt32HostToBig(group.diskIDIndex);
		}
	}
}
