//
//  NSObject+NVSwizzle.h
//  Notation
//
//  Created by Zach Waldowski on 7/14/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSObject (NVSwizzle)

+ (BOOL)nv_swizzleMethod:(SEL)oldSel withMethod:(SEL)newSel;
+ (BOOL)nv_swizzleMethod:(SEL)oldSel withBlock:(id)block;

@end
