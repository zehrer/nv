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
@synthesize logSequenceNumber = logSequenceNumber;
@synthesize originalNote = originalNote;
@synthesize uniqueNoteID = uniqueNoteID;

+ (id)deletedNoteWithNote:(id <SynchronizedNote>)aNote {
	return [[DeletedNoteObject alloc] initWithExistingObject:aNote];
}

- (id)initWithExistingObject:(id<SynchronizedNote>)note {
    if ((self = [super init])) {
		uniqueNoteID = [note uniqueNoteID];
		syncServicesMD = [[note syncServicesMD] mutableCopy];
		logSequenceNumber = [note logSequenceNumber];
		//not serialized: for runtime lookup purposes only
		originalNote = note;
    }
    return self;
}

- (id)initWithCoder:(NSCoder*)decoder {
    if ((self = [super init])) {
		if ([decoder containsValueForKey:@keypath(self.uniqueNoteID)]) {
			self.uniqueNoteID = [decoder decodeObjectForKey:@keypath(self.uniqueNoteID)];
		} else if ([decoder containsValueForKey:@"uniqueNoteIDBytes"]) {
			NSUInteger decodedUUIDByteCount = 0;
			const uint8_t *decodedUUIDBytes = [decoder decodeBytesForKey:@"uniqueNoteIDBytes" returnedLength:&decodedUUIDByteCount];
			self.uniqueNoteID = decodedUUIDBytes ? [[NSUUID alloc] initWithUUIDBytes:decodedUUIDBytes] : [NSUUID UUID];
		}
		syncServicesMD = [decoder decodeObjectForKey:@keypath(self.syncServicesMD)];
		logSequenceNumber = [decoder decodeInt32ForKey:@keypath(self.logSequenceNumber)];
    }
    return self;
}

- (void)encodeWithCoder:(NSCoder *)coder {
	uuid_t bytes;
	[self.uniqueNoteID getUUIDBytes:bytes];
	[coder encodeBytes:(const uint8_t *)&bytes length:sizeof(uuid_t) forKey:@"uniqueNoteIDBytes"];
	[coder encodeObject:syncServicesMD forKey:@keypath(self.syncServicesMD)];
	[coder encodeInt32:logSequenceNumber forKey:@keypath(self.logSequenceNumber)];
}

- (NSString*)description {
	return [NSString stringWithFormat:@"DeletedNoteObj(%@) %@", self.uniqueNoteID.UUIDString, syncServicesMD];
}

- (void)setSyncObjectAndKeyMD:(NSDictionary*)aDict forService:(NSString*)serviceName {
	NSMutableDictionary *dict = [syncServicesMD objectForKey:serviceName];
	if (!dict) {
		dict = [[NSMutableDictionary alloc] initWithDictionary:aDict];
		if (!syncServicesMD) syncServicesMD = [[NSMutableDictionary alloc] init];
		[syncServicesMD setObject:dict forKey:serviceName];
	} else {
		[dict addEntriesFromDictionary:aDict];
	}
}
- (void)removeAllSyncMDForService:(NSString*)serviceName {
	[syncServicesMD removeObjectForKey:serviceName];
}
- (void)incrementLSN {
    logSequenceNumber++;
}
- (BOOL)youngerThanLogObject:(id<SynchronizedNote>)obj {
	return [self logSequenceNumber] < [obj logSequenceNumber];
}

- (NSUInteger)hash {
	return self.uniqueNoteID.hash;
}
- (BOOL)isEqual:(id <SynchronizedNote>)otherNote {
	if (!otherNote) return NO;
	if (![otherNote conformsToProtocol:@protocol(SynchronizedNote)]) return NO;
	return [self.uniqueNoteID isEqual:[otherNote uniqueNoteID]];
}


@end
