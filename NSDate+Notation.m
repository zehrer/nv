//
//  NSDate+Notation.m
//  Notation
//
//  Created by Zachary Waldowski on 1/25/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import "NSDate+Notation.h"

static NSTimeInterval CarbonReferenceDate()
{
	static dispatch_once_t onceToken;
	static NSTimeInterval carbonReferenceDate = 0;
	dispatch_once(&onceToken, ^{
        NSTimeZone *gmt = [NSTimeZone timeZoneWithAbbreviation:@"GMT"];
        NSDate *ref = [[NSCalendarDate alloc] initWithYear: 1904 month: 1 day: 1
													  hour: 0 minute: 0 second: 0 timeZone: gmt];
        carbonReferenceDate = [ref timeIntervalSinceReferenceDate];
	});
	return carbonReferenceDate;
}

@implementation NSDate (Notation)

+ (NSDate *)dateWithUTCDateTime:(const UTCDateTime *)utc {
	NSTimeInterval utcTime = *(unsigned long long*)utc / 65536.0;
    return [NSDate dateWithTimeIntervalSinceReferenceDate: CarbonReferenceDate() + utcTime];
}

- (void)getUTCDateTime:(out UTCDateTime *)utc {
	NSParameterAssert(utc);
	*(unsigned long long *)utc = (self.timeIntervalSinceReferenceDate - CarbonReferenceDate()) * 65536.0;
}

@end
