/*
 * You need to have the OpenSSL header files (as well as the location of their
 * include directory given to Project Builder) for this to compile.  For it
 * to link, add /usr/lib/libcrypto.dylib and /usr/lib/libssl.dylib to the linked
 * frameworks.
 */
/* NSData_crypto.h */

#import <Foundation/Foundation.h>

@interface NSData (NVUtilities)

- (NSMutableData *)compressedData;

- (NSMutableData *)compressedDataAtLevel:(int)level;

- (NSMutableData *)uncompressedData;

- (BOOL)isCompressedFormat;

+ (NSMutableData *)randomDataOfLength:(NSUInteger)len;

- (NSMutableData *)derivedKeyOfLength:(NSUInteger)len salt:(NSData *)salt iterations:(NSUInteger)count;

- (unsigned long)CRC32;

- (NSData *)SHA1Digest;

- (NSData *)MD5Digest;

- (NSData *)BrokenMD5Digest;

- (NSString *)pathURLFromWebArchive;

- (NSMutableString *)newStringUsingBOMReturningEncoding:(NSStringEncoding *)encoding;

+ (NSData *)uncachedDataFromFile:(NSString *)filename;

- (NSString *)encodeBase64;

@end

@interface NSMutableData (NVCryptoRelated)
- (void)reverseBytes;

- (BOOL)encryptAESDataWithKey:(NSData *)key iv:(NSData *)iv;

- (BOOL)decryptAESDataWithKey:(NSData *)key iv:(NSData *)iv;

@end
