//
//  DeletedNoteObject.m
//  Notation
//
//  Created by Zachary Schneirov on 4/16/06.

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


#import "DeletedNoteObject.h"
#import "NSString_NV.h"

@implementation DeletedNoteObject

@synthesize syncServicesMD = syncServicesMD;
@synthesize uniqueNoteIDBytes = uniqueNoteIDBytes;
@synthesize logSequenceNumber = logSequenceNumber;
@synthesize originalNote = originalNote;

+ (id)deletedNoteWithNote:(id <SynchronizedNote>)aNote {
	return [[[DeletedNoteObject alloc] initWithExistingObject:aNote] autorelease];
}

- (id)initWithExistingObject:(id<SynchronizedNote>)note {
    if ((self = [super init])) {
		CFUUIDBytes *bytes = [note uniqueNoteIDBytesPtr];
		uniqueNoteIDBytes = *bytes;
		syncServicesMD = [[note syncServicesMD] mutableCopy];
		logSequenceNumber = [note logSequenceNumber];
		//not serialized: for runtime lookup purposes only
		originalNote = [note retain];
    }
    return self;
}

- (id)initWithCoder:(NSCoder*)decoder {
    if ((self = [super init])) {
		if ([decoder allowsKeyedCoding]) {
			NSUInteger decodedByteCount;
			const uint8_t *decodedBytes = [decoder decodeBytesForKey:@keypath(self.uniqueNoteIDBytes) returnedLength:&decodedByteCount];
			memcpy(&uniqueNoteIDBytes, decodedBytes, MIN(decodedByteCount, sizeof(CFUUIDBytes)));
			syncServicesMD = [[decoder decodeObjectForKey:@keypath(self.syncServicesMD)] retain];
			logSequenceNumber = [decoder decodeInt32ForKey:@keypath(self.logSequenceNumber)];
		} else {
			[decoder decodeValueOfObjCType:@encode(CFUUIDBytes) at:&uniqueNoteIDBytes];
			syncServicesMD = [[decoder decodeObject] retain];
			[decoder decodeValueOfObjCType:@encode(unsigned int) at:&logSequenceNumber];
		}
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
	
	if ([coder allowsKeyedCoding]) {
		[coder encodeBytes:(const uint8_t *)&uniqueNoteIDBytes length:sizeof(CFUUIDBytes) forKey:@keypath(self.uniqueNoteIDBytes)];
		[coder encodeObject:syncServicesMD forKey:@keypath(self.syncServicesMD)];
		[coder encodeInt32:logSequenceNumber forKey:@keypath(self.logSequenceNumber)];
	} else {
		[coder encodeValueOfObjCType:@encode(CFUUIDBytes) at:&uniqueNoteIDBytes];
		[coder encodeObject:syncServicesMD];
		[coder encodeValueOfObjCType:@encode(unsigned int) at:&logSequenceNumber];
	}
}

- (NSString*)description {
	return [NSString stringWithFormat:@"DeletedNoteObj(%@) %@", [NSString uuidStringWithBytes:uniqueNoteIDBytes], syncServicesMD];
}

- (void)setSyncObjectAndKeyMD:(NSDictionary*)aDict forService:(NSString*)serviceName {
	NSMutableDictionary *dict = [syncServicesMD objectForKey:serviceName];
	if (!dict) {
		dict = [[NSMutableDictionary alloc] initWithDictionary:aDict];
		if (!syncServicesMD) syncServicesMD = [[NSMutableDictionary alloc] init];
		[syncServicesMD setObject:dict forKey:serviceName];
		[dict release];
	} else {
		[dict addEntriesFromDictionary:aDict];
	}
}
- (void)removeAllSyncMDForService:(NSString*)serviceName {
	[syncServicesMD removeObjectForKey:serviceName];
}
- (CFUUIDBytes *)uniqueNoteIDBytesPtr {
    return &uniqueNoteIDBytes;
}
- (void)incrementLSN {
    logSequenceNumber++;
}
- (BOOL)youngerThanLogObject:(id<SynchronizedNote>)obj {
	return [self logSequenceNumber] < [obj logSequenceNumber];
}

- (NSUInteger)hash {
	//XOR successive native-WORDs of CFUUIDBytes
	NSUInteger finalHash = 0;
	NSUInteger i, *noteIDBytesPtr = (NSUInteger *)&uniqueNoteIDBytes;
	for (i = 0; i<sizeof(CFUUIDBytes) / sizeof(NSUInteger); i++) {
		finalHash ^= *noteIDBytesPtr++;
	}
	return finalHash;
}
- (BOOL)isEqual:(id)otherNote {
	CFUUIDBytes *otherBytes = [(id <SynchronizedNote>)otherNote uniqueNoteIDBytesPtr];
	return memcmp(otherBytes, &uniqueNoteIDBytes, sizeof(CFUUIDBytes)) == 0;
}

- (void)dealloc {
	[syncServicesMD release];
	[originalNote release];
	[super dealloc];
}

@end
