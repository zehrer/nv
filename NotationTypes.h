//
//  NotationTypes.h
//  Notation
//
//  Created by Zach Waldowski on 7/5/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, NVDatabaseFormat) {
	NVDatabaseFormatSingle = 0,
	NVDatabaseFormatPlainText,
    NVDatabaseFormatRTF,
	NVDatabaseFormatHTML,
    NVDatabaseFormatDOC,
    NVDatabaseFormatDOCX
};
