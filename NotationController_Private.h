//
//  NotationController_Private.h
//  Notation
//
//  Created by Zach Waldowski on 7/14/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import "NotationController.h"

@interface NotationController () {
	NSFileManager *_fileManager;
}

@property (nonatomic, strong, readwrite) NSFileManager *fileManager;

@end
