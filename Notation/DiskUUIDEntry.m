//
//  DiskUUIDEntry.m
//  Notation
//
//  Created by Zachary Schneirov on 1/17/11.

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


#import "DiskUUIDEntry.h"

@implementation DiskUUIDEntry

@synthesize lastAccessed = lastAccessed;

- (id)initWithUUID:(NSUUID *)aUUID {
	NSParameterAssert(aUUID);
	if ((self = [super init])) {
		_UUID = aUUID;
		lastAccessed = [NSDate date];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
	NSAssert([coder allowsKeyedCoding], @"keyed-encoding only!");

	[coder encodeObject:lastAccessed forKey:VAR_STR(lastAccessed)];

	uuid_t bytes;
	[self.UUID getUUIDBytes: bytes];
	[coder encodeBytes:(const uint8_t *) &bytes length:sizeof(uuid_t) forKey:VAR_STR(uuidRef)];
}

- (id)initWithCoder:(NSCoder *)decoder {
	NSAssert([decoder allowsKeyedCoding], @"keyed-decoding only!");
	if ((self = [super init])) {

		lastAccessed = [decoder decodeObjectForKey:VAR_STR(lastAccessed)];

		NSUInteger decodedUUIDByteCount = 0;
		const uint8_t *decodedUUIDBytesPtr = [decoder decodeBytesForKey:VAR_STR(uuidRef) returnedLength:&decodedUUIDByteCount];
		if (decodedUUIDByteCount == sizeof(uuid_t)) _UUID = [[NSUUID alloc] initWithUUIDBytes: decodedUUIDBytesPtr];
		else return nil;
	}
	return self;
}

- (void)see {
	lastAccessed = [NSDate date];
}

- (NSString *)description {
	return [NSString stringWithFormat:@"DiskUUIDEntry(%@, %@)", lastAccessed, self.UUID.UUIDString];
}

- (NSUInteger)hash {
	return self.UUID.hash;
}

- (BOOL)isEqual:(id)otherEntry {
	return [self.UUID isEqual: [otherEntry UUID]];
}

@end
