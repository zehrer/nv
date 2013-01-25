//
//  NSURL+Notation.h
//  Notation
//
//  Created by Zachary Waldowski on 1/25/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

@interface NSURL (Notation)

+ (NSURL *)URLWithFSRef:(const FSRef *)ref;
- (BOOL)getFSRef:(out FSRef *)outRef;

@end
