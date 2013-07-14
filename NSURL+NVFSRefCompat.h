//
//  NSURL+NVFSRefCompat.h
//  Notation
//
//  Created by Zach Waldowski on 7/14/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSURL (NVFSRefCompat)

- (BOOL)nv_getFSRef:(FSRef *)ref;
+ (instancetype)nv_URLFromFSRef:(FSRef *)ref;

@end
