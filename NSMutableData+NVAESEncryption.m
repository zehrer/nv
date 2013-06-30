//
//  NSMutableData+NVAESEncryption.m
//  Notation
//
//  Created by Zach Waldowski on 6/30/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import "NSMutableData+NVAESEncryption.h"
#import <CommonCrypto/CommonCrypto.h>

static BOOL NVInPlaceCryptAESData(NSMutableData *data, CCOperation op, NSData *key, NSData *iv) {
	size_t originalLength = data.length;
	
	// check IV and key lengths
	if (key.length != kCCKeySizeAES256) {
		NSLog(@"key length was wrong: %lu", key.length);
		return NO;
	}
	
	if (iv.length != kCCBlockSizeAES128) {
		NSLog(@"initialization vector length was wrong: %lu", iv.length);
		return NO;
	}
	
	__block size_t outputLength = 0;
	
	CCCryptorStatus(^perform)(void) = ^{
		return CCCrypt(op, kCCAlgorithmAES, kCCOptionPKCS7Padding,
					   key.bytes, key.length, iv.bytes,
					   data.bytes, originalLength,
					   data.mutableBytes, data.length, &outputLength);
	};
	
	CCCryptorStatus status = perform();
	
	if (status == kCCBufferTooSmall) {
		data.length = outputLength;
		status = perform();
	}
	
	if (status != kCCSuccess) {
		NSLog(@"unable to encrypt/decrypt");
		return NO;
	}
	
	data.length = outputLength;
	return YES;
}

@implementation NSMutableData (NVAESEncryption)

- (BOOL)nv_encryptDataWithKey:(NSData*)key iv:(NSData*)iv {
	return NVInPlaceCryptAESData(self, kCCEncrypt, key, iv);
}

- (BOOL)nv_decryptDataWithKey:(NSData*)key iv:(NSData*)iv {
	return NVInPlaceCryptAESData(self, kCCDecrypt, key, iv);
}

@end
