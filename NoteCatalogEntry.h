//
//  NoteCatalogEntry.h
//  Notation
//
//  Created by Zachary Waldowski on 1/25/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

@interface NoteCatalogEntry : NSObject

@property (nonatomic) UTCDateTime lastModified;
@property (nonatomic) UTCDateTime lastAttrModified;
@property (nonatomic) UInt32 logicalSize;
@property (nonatomic) OSType fileType;
@property (nonatomic) UInt32 nodeID;
@property (nonatomic) CFMutableStringRef filename;
@property (nonatomic) UniChar *filenameChars;
@property (nonatomic) UniCharCount filenameCharCount;

@end
