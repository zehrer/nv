//
//  NSDate+Notation.m
//  Notation
//
//  Created by Zachary Waldowski on 1/25/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import "NSDate+Notation.h"

static NSDate *NTNCarbonReferenceDate() {
	static dispatch_once_t onceToken;
	static NSDate * carbonReferenceDate = nil;
	dispatch_once(&onceToken, ^{
        carbonReferenceDate = [[NSCalendarDate alloc] initWithYear: 1904 month: 1 day: 1 hour: 0 minute: 0 second: 0 timeZone: [NSTimeZone timeZoneForSecondsFromGMT: 0]];
	});
	return carbonReferenceDate;
}

@implementation NSDate (Notation)

+ (NSDate *)dateWithUTCDateTime:(const UTCDateTime *)utc {
	NSParameterAssert(utc);
	NSTimeInterval utcTime = *(unsigned long long*)utc / 65536.0;
	return [NTNCarbonReferenceDate() dateByAddingTimeInterval: utcTime];
}

- (void)getUTCDateTime:(out UTCDateTime *)utc {
	NSParameterAssert(utc);
	*(unsigned long long *)utc = [self timeIntervalSinceDate: NTNCarbonReferenceDate()] * 65536.0;
}

- (NSUInteger)ntn_hoursSinceReferenceDate {
		return floor(self.timeIntervalSinceReferenceDate / 3600.0);
}

@end
