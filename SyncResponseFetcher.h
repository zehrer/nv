//
//  SyncResponseFetcher.h
//  Notation
//
//  Created by Zachary Schneirov on 11/29/09.

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

@class SyncResponseFetcher;

@protocol SyncResponseFetcherDelegate <NSObject>

- (void)syncResponseFetcher:(SyncResponseFetcher*)fetcher receivedData:(NSData*)data returningError:(NSString*)errString;

@end

//carries out a single request
@interface SyncResponseFetcher : NSObject {

	NSMutableData *receivedData;
	NSData *dataToSend;
	NSString *dataToSendContentType;
	NSURLConnection *urlConnection;
	NSURL *requestURL;
	NSDictionary *headers;
	id representedObject;
	
	NSString *lastErrorMessage;
	NSInteger lastStatusCode;
	
	NSInvocation *successInvocation;
	BOOL isRunning, didCancel;
}

- (id)initWithURL:(NSURL*)aURL bodyStringAsUTF8B64:(NSString*)stringToEncode delegate:(id <SyncResponseFetcherDelegate>)aDelegate;
- (id)initWithURL:(NSURL*)aURL POSTData:(NSData*)POSTData delegate:(id <SyncResponseFetcherDelegate>)aDelegate;
- (id)initWithURL:(NSURL*)aURL POSTData:(NSData*)POSTData contentType:(NSString*)contentType delegate:(id <SyncResponseFetcherDelegate>)aDelegate;
- (void)setRepresentedObject:(id)anObject;
- (id)representedObject;
- (NSInvocation*)successInvocation;
- (NSURL*)requestURL;
- (NSDictionary*)headers;
- (NSInteger)statusCode;
- (NSString*)errorMessage;
- (void)_fetchDidFinishWithError:(NSString*)anErrString;
- (BOOL)start;
- (BOOL)startWithSuccessInvocation:(NSInvocation*)anInvocation;
- (BOOL)isRunning;
- (BOOL)didCancel;
- (void)cancel;

@property (nonatomic, weak, readonly) id <SyncResponseFetcherDelegate> delegate;

@end
