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


#import <Cocoa/Cocoa.h>


//carries out a single request

@interface SyncResponseFetcher : NSObject {

	NSMutableData *receivedData;
	NSData *dataToSend;
	NSString *dataToSendContentType;
	NSURLConnection *urlConnection;
	NSURL *requestURL;
	NSDictionary *headers;
	NSDictionary *requestHeaders;
	id representedObject;
	
	NSString *lastErrorMessage;
	NSInteger lastStatusCode;
	
	BOOL isRunning, didCancel;
}


- (id)initWithURL:(NSURL*)aURL bodyStringAsUTF8B64:(NSString*)stringToEncode completion:(void(^)(SyncResponseFetcher*, NSData*, NSString *))block;
- (id)initWithURL:(NSURL*)aURL POSTData:(NSData*)POSTData headers:(NSDictionary *)aHeaders completion:(void(^)(SyncResponseFetcher*, NSData*, NSString *))block;
- (id)initWithURL:(NSURL*)aURL POSTData:(NSData*)POSTData completion:(void(^)(SyncResponseFetcher*, NSData*, NSString *))block;
- (id)initWithURL:(NSURL*)aURL POSTData:(NSData*)POSTData headers:(NSDictionary *)aHeaders contentType:(NSString*)contentType completion:(void(^)(SyncResponseFetcher*, NSData*, NSString *))block;

- (void)setRepresentedObject:(id)anObject;
- (id)representedObject;
- (NSURL*)requestURL;
- (NSDictionary*)headers;
- (NSInteger)statusCode;
- (NSString*)errorMessage;
- (void)_fetchDidFinishWithError:(NSString*)anErrString;
- (BOOL)start;
- (BOOL)isRunning;
- (BOOL)didCancel;
- (void)cancel;

@property (nonatomic, copy) void(^completionBlock)(SyncResponseFetcher*, NSData*, NSString*);
@property (nonatomic, copy) void(^successBlock)(void);

@end
