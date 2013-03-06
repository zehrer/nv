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
#import "NSDate+Notation.h"

char *replaceString(char *oldString, const char *newString) {
	size_t newLen = strlen(newString) + 1;

	//realloc is smart enough to do better memory management than we can do right here
	char *resizedString = (char *) realloc(oldString, newLen);
	memmove(resizedString, newString, newLen);

	return resizedString;
}

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
			newGroups[i].nodeID = CFSwapInt32BigToHost(group.nodeID);
			newGroups[i].diskIDIndex = CFSwapInt32BigToHost(group.diskIDIndex);
		}
	} else {
		for (i = 0; i < count; i++) {
			PerDiskInfo group = perDiskGroups[i];
			newGroups[i].attrTime.highSeconds = CFSwapInt16HostToBig(group.attrTime.highSeconds);
			newGroups[i].attrTime.lowSeconds = CFSwapInt32HostToBig(group.attrTime.lowSeconds);
			newGroups[i].attrTime.fraction = CFSwapInt16HostToBig(group.attrTime.fraction);
			newGroups[i].nodeID = CFSwapInt32HostToBig(group.nodeID);
			newGroups[i].diskIDIndex = CFSwapInt32HostToBig(group.diskIDIndex);
		}
	}
}
