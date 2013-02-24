/*
 *  BufferUtils.h
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

#define UTCDateTimeIsEmpty(__UTCDT) (*(int64_t*)&((__UTCDT)) == 0LL)

typedef struct _PerDiskInfo {

	//index in a table of disk UUIDs; should be the disk from which this time was gathered
	//the disk UUIDs table is tracked separately in FrozenNotation; it should only ever be appended-to
	UInt32 diskIDIndex;

	//catalog node ID of a file - UNUSED
	UInt32 nodeID__unused;

	//the attribute modification time of a file
	UTCDateTime attrTime;

} PerDiskInfo;

char *replaceString(char *oldString, const char *newString);

void CopyPerDiskInfoGroupsToOrder(PerDiskInfo **flippedGroups, NSUInteger *existingCount, const uint8_t *perDiskGroupsBuffer, size_t bufferSize, NSInteger toHostOrder);
