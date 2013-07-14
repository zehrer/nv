//
//  NSError+NVError.h
//  Notation
//
//  Created by Zach Waldowski on 7/14/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import <Foundation/Foundation.h>

extern NSString *const NVErrorDomain;

typedef NS_ENUM(NSInteger, NVError) {
	NVErrorCoderMistake = -818,
	NVErrorJournaling = -819,
	NVErrorWriteJournal = -820,
	NVErrorAuthentication = -821,
	NVErrorCompression = -822,
	NVErrorPasswordCancel = -823,
	NVErrorDataFormatting = -824,
	NVErrorItemVerify = -825
};

//faux carbon errors
#define kCoderErr NVErrorCoderMistake
#define kJournalingError NVErrorJournaling
#define kWriteJournalErr NVErrorWriteJournal
#define kNoAuthErr NVErrorAuthentication
#define kCompressionErr NVErrorCompression
#define kPassCanceledErr NVErrorPasswordCancel
#define kDataFormattingErr NVErrorDataFormatting
#define kItemVerifyErr NVErrorItemVerify

@interface NSError (NVError)

+ (instancetype)nv_errorWithCode:(NVError)errorCode;

@end
