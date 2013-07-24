//
//  NVCatalogEntry.h
//  Notation
//
//  Created by Zach Waldowski on 7/14/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NVCatalogEntry : NSObject

@property (nonatomic) OSType fileType;
@property (nonatomic) OSType nodeID;

@property (nonatomic, copy) NSString *fileName;
@property (nonatomic, copy) NSData *resourceIdentifier;
@property (nonatomic, copy) NSNumber *fileSize;
@property (nonatomic, copy) NSDate *creationDate;
@property (nonatomic, copy) NSDate *contentModifiedDate;
@property (nonatomic, copy) NSDate *attributeModifiedDate;

@end
