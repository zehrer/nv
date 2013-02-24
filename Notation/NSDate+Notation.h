//
//  NSDate+Notation.h
//  Notation
//
//  Created by Zachary Waldowski on 1/25/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSDate (Notation)

+ (NSDate *)dateWithUTCDateTime:(const UTCDateTime *)utc;
- (void)getUTCDateTime:(out UTCDateTime *)utc;

@end
