//
//  NVViewLocationContext.h
//  Notation
//
//  Created by Zach Waldowski on 7/6/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NVViewLocationContext : NSObject

@property (nonatomic) BOOL pivotRowWasEdge;
@property (nonatomic, weak) id pivotObject;
@property (nonatomic) CGFloat verticalDistanceToPivotRow;

@end
