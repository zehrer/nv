//
//  NoteCatalogEntry.h
//  Notation
//
//  Created by Zachary Waldowski on 1/25/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

@interface NoteCatalogEntry : NSObject

@property (nonatomic) UInt32 logicalSize;
@property (nonatomic) OSType fileType;

@property (nonatomic, copy) NSString *filename;
@property (nonatomic, copy) NSDate *creationDate;
@property (nonatomic, copy) NSDate *contentModificationDate;
@property (nonatomic, copy) NSDate *attributeModificationDate;

@end
