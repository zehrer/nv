/* URLGetter */

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

@interface URLGetter : NSObject
{
    IBOutlet NSButton *cancelButton;
    IBOutlet NSTextField *objectURLStatus;
    IBOutlet NSProgressIndicator *progress;
    IBOutlet NSTextField *progressStatus;
    IBOutlet NSPanel *window;
	
	NSURL *url;
	NSURLDownload *downloader;
	NSString *downloadPath, *tempDirectory;
	
	BOOL isIndicating, isImporting;
	
	long long totalReceivedByteCount, maxExpectedByteCount;
}

- (id)initWithURL:(NSURL*)aUrl completionBlock:(void(^)(URLGetter *getter, NSString *filename))block;

- (IBAction)start;
- (IBAction)cancelDownload:(id)sender;

- (NSURL*)url;

@property (nonatomic, copy, readonly) void(^completionBlock)(URLGetter *getter, NSString *filename);

- (void)stopProgressIndication;
- (void)startProgressIndication:(id)sender;
- (void)updateProgress;
- (NSString*)downloadPath;

- (void)endDownloadWithPath:(NSString*)path;

@end
