//
//  NSError+Notation.h
//  Notation
//
//  Created by Zachary Waldowski on 1/25/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

extern NSString *const NTNErrorDomain;

enum {
	NTNDeserializationError = -818,
	NTNJournalingError = -819,
	NTNWriteJournalError = -820,
	NTNPermissionError = -821,
	NTNCompressionError = -822,
	NTNPasswordEntryCanceledError = -823,
	NTNDataFormattingError = -824,
	NTNItemVerificationError = -825
};

@interface NSError (Notation)

+ (NSError *)ntn_errorWithCode:(NSInteger)code carbon:(BOOL)carbonOrNTN;

@end
