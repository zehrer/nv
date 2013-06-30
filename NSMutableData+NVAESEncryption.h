//
//  NSMutableData+NVAESEncryption.h
//  Notation
//
//  Created by Zach Waldowski on 6/30/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSMutableData (NVAESEncryption)

- (BOOL)nv_encryptDataWithKey:(NSData*)key iv:(NSData*)iv;
- (BOOL)nv_decryptDataWithKey:(NSData*)key iv:(NSData*)iv;

@end
