//
//  NSFileManager_NV.m
//  Notation
//
//  Created by Zachary Schneirov on 12/31/10.

/*Copyright (c) 2010, Zachary Schneirov. All rights reserved.
  Redistribution and use in source and binary forms, with or without modification, are permitted 
  provided that the following conditions are met:
   - Redistributions of source code must retain the above copyright notice, this list of conditions 
     and the following disclaimer.
   - Redistributions in binary form must reproduce the above copyright notice, this list of 
     conditions and the following disclaimer in the documentation and/or other materials provided with
     the distribution.
   - Neither the name of Notational Velocity nor the names of its contributors may be used to endorse 
     or promote products derived from this software without specific prior written permission. */


#import "NSFileManager_NV.h"
#include <sys/xattr.h>

static NSError *NVTErrorForPOSIXError(int err, NSURL *URL) {

	NSInteger code = -1;
	switch (err) {
		case EPERM: code = NSFileWriteNoPermissionError; break;
		case EROFS: code = NSFileWriteVolumeReadOnlyError; break;
		case EINVAL:
		case ENOTDIR:
		case ENAMETOOLONG:
		case ELOOP:
		case EFAULT: code = NSFileWriteInvalidFileNameError; break;
		case ENOSPC: code = NSFileWriteOutOfSpaceError; break;
		case ENOENT: code = NSFileNoSuchFileError; break;
		case ETXTBSY: code = NSFileLockingError; break;
		case EACCES:
		case ENOTSUP: code = NSFileWriteNoPermissionError; break;
		case EEXIST: code = NSFileWriteFileExistsError; break;
		case EIO: code =  NSFileWriteUnknownError; break;
		case ENOATTR:
		case ERANGE:
		case E2BIG: code = NSFileWriteUnknownError; break;
		default: break;
	}

	if (code == -1) {
		return [NSError errorWithDomain: NSPOSIXErrorDomain code: err userInfo: @{NSURLErrorKey: URL}];
	} else {
		return [NSError errorWithDomain: NSCocoaErrorDomain code: code userInfo: @{
				   NSUnderlyingErrorKey: [NSError errorWithDomain: NSPOSIXErrorDomain code: err userInfo: nil],
						  NSURLErrorKey: URL}];
	}
}

@implementation NSFileManager (NV)

+ (id <NSCoding, NSCopying>)getOpenMetaTagsForItemAtURL:(NSURL *)URL error:(out NSError **)outError {
	//return convention: empty tags should be an empty array;
	//for files that have never been tagged, or that have had their tags removed, return
	//files might lose their metadata if edited externally or synced without being first encoded

	if (!URL || !URL.isFileURL) return nil;

	// If the object passed in has no data - is a string of length 0 or an array or dict with 0 objects, then we remove the data at the key.
	static const char *inKeyNameC = "com.apple.metadata:kMDItemOMUserTags";

	const char *itemPath = URL.path.fileSystemRepresentation;

	NSMutableData *data = nil;

	ssize_t dataSize = getxattr (itemPath, inKeyNameC, NULL, SIZE_MAX, 0, 0);
	if (dataSize > 0)
	{
		data = [NSMutableData dataWithLength: dataSize];
		getxattr (itemPath, inKeyNameC, [data mutableBytes], dataSize, 0, 0);
	} else {
		// I get EINVAL sometimes when setting/getting xattrs on afp servers running 10.5. When I get this error, I find that everything is working correctly... so it seems to make sense to ignore them
		// EINVAL means invalid argument. I know that the args are fine.
		if ((errno != ENOATTR) && (errno != EINVAL) && outError) // it is not an error to have no attribute set
			*outError = NVTErrorForPOSIXError(errno, URL);

		return nil;
	}

	// ok, we have some data
	NSPropertyListFormat formatFound;
	NSError *error = nil;
	id outObject = [NSPropertyListSerialization propertyListWithData: data options: NSPropertyListImmutable format: &formatFound error: &error];
	if (!outObject) {
		if (outError) *outError = error;
		return nil;
	}
	return outObject;
}

+ (BOOL)setOpenMetaTags:(id <NSCoding, NSCopying>)object forItemAtURL:(NSURL *)URL error:(out NSError **)outError {
	if (!URL || !URL.isFileURL) return NO;

	// If the object passed in has no data - is a string of length 0 or an array or dict with 0 objects, then we remove the data at the key.
	static const char *key = "com.apple.metadata:kMDItemOMUserTags";

	// always set data as binary plist.
	NSData *dataToSend = nil;
	if (object) {
		NSError *err = nil;
		dataToSend = [NSPropertyListSerialization dataWithPropertyList: object format: NSPropertyListBinaryFormat_v1_0 options: 0 error: &err];
		if (!dataToSend) {
			if (outError) *outError = err;
			return NO;
		}
	}

	int returnVal = 0;
	if (dataToSend) {
		returnVal = setxattr(URL.path.fileSystemRepresentation, key, dataToSend.bytes, dataToSend.length, 0, 0);
	} else {
		returnVal = removexattr(URL.path.fileSystemRepresentation, key, 0);
	}

	if (returnVal < 0) {
		if (outError) *outError = NVTErrorForPOSIXError(errno, URL);
		return NO;
	}

	return YES;

}

+ (NSStringEncoding)textEncodingOfItemAtURL:(NSURL *)URL {
	if (!URL || !URL.isFileURL) return NO;

	static const char *inKeyNameC = "com.apple.TextEncoding";
	const char *itemPath = URL.path.fileSystemRepresentation;

	NSMutableData *data = nil;

	ssize_t dataSize = getxattr (itemPath, inKeyNameC, NULL, SIZE_MAX, 0, 0);
	if (dataSize > 0)
	{
		data = [NSMutableData dataWithLength: dataSize];
		getxattr (itemPath, inKeyNameC, [data mutableBytes], dataSize, 0, 0);
		NSString *encodingStr = [[NSString alloc] initWithData: data encoding: NSUTF8StringEncoding];

		if (!encodingStr.length) {
			NSLog(@"couldn't make attribute data from %@ into a string", URL);
			return NO;
		}
		NSArray *segs = [encodingStr componentsSeparatedByString:@";"];
		if ([segs count] >= 2 && [(NSString *) segs[1] length] > 1) {
			return CFStringConvertEncodingToNSStringEncoding([segs[1] intValue]);
		} else if ([(NSString *) segs[0] length] > 1) {
			CFStringEncoding theCFEncoding = CFStringConvertIANACharSetNameToEncoding((CFStringRef) segs[0]);
			if (theCFEncoding == kCFStringEncodingInvalidId) {
				NSLog(@"couldn't convert IANA charset");
				return NO;
			}
			return CFStringConvertEncodingToNSStringEncoding(theCFEncoding);
		}
	}
	return NO;
}

+ (BOOL)setTextEncoding:(NSStringEncoding)encoding ofItemAtURL:(NSURL *)URL {
	CFStringEncoding cfStringEncoding = CFStringConvertNSStringEncodingToEncoding(encoding);
	if (cfStringEncoding == kCFStringEncodingInvalidId) {
		NSLog(@"%@: encoding %lu is invalid!", NSStringFromSelector(_cmd), encoding);
		return NO;
	}

	NSString *textEncStr = [(NSString *) CFStringConvertEncodingToIANACharSetName(cfStringEncoding) stringByAppendingFormat:@";%@", [@(cfStringEncoding) stringValue]];

	if (setxattr(URL.path.fileSystemRepresentation, "com.apple.TextEncoding", textEncStr.UTF8String, textEncStr.length, 0, 0) < 0) {
		NSLog(@"couldn't set text encoding attribute of %@ to '%s': %d", URL, textEncStr.UTF8String, errno);
		return NO;
	}
	return YES;
}

@end
