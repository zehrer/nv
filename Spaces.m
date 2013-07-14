/*
 *  Spaces.c
 *  Notation
 *
 *  Created by Zachary Schneirov on 1/22/11.
  Copyright (c) 2010, Zachary Schneirov. All rights reserved.
  Redistribution and use in source and binary forms, with or without modification, are permitted 
  provided that the following conditions are met:
   - Redistributions of source code must retain the above copyright notice, this list of conditions 
     and the following disclaimer.
   - Redistributions in binary form must reproduce the above copyright notice, this list of 
	 conditions and the following disclaimer in the documentation and/or other materials provided with
     the distribution.
   - Neither the name of Notational Velocity nor the names of its contributors may be used to endorse 
     or promote products derived from this software without specific prior written permission.
 */

#include "Spaces.h"

Boolean CurrentContextForWindowNumber(NSInteger windowNum, SpaceSwitchingContext *ctx) {
	if (!ctx) return false;
	
	CGSWorkspace windowSpace;
	CGError err = CGSGetWindowWorkspace(_CGSDefaultConnection(), (CGSWindow)windowNum, &windowSpace);
	if (err) {
		printf("CGSGetWindowWorkspace error: %d\n", err);
		return false;
	}
	
	CGSWorkspace currentSpace;
	err = CGSGetWorkspace(_CGSDefaultConnection(), &currentSpace);
	if (err) {
		printf("CGSGetWorkspace error: %d\n", err);
		return false;
	}
	
	//NSWorkspace runningApplications
	
	NSArray *runningApps = [[NSWorkspace sharedWorkspace] runningApplications];
	NSUInteger index = [runningApps indexOfObjectPassingTest:^(NSRunningApplication *app, NSUInteger idx, BOOL *stop) {
		if (app.isActive) {
			*stop = YES;
			return YES;
		}
		return NO;
	}];
	
	if (index == NSNotFound) {
		return false;
	}
	
	NSRunningApplication *app = runningApps[index];
	
	ctx->userSpace = currentSpace;
	ctx->windowSpace = windowSpace;
	ctx->frontPID = app.processIdentifier;
	
	return true;
}

Boolean CompareContextsAndSwitch(SpaceSwitchingContext *ctxBefore, SpaceSwitchingContext *ctxAfter) {
	if (!ctxBefore || !ctxAfter) {
		printf("null context\n");
		return false;
	}
	
	//contexts are equal; can't do anything
	if (!memcmp(ctxBefore, ctxAfter, sizeof(SpaceSwitchingContext))) {
		printf("equal contexts\n");
		return false;
	}
	
	//if windowspace-before is the same as both userspace-after and windowspace-after
	//and userspace-before was different from windowspace-before
	//and the frontprocess-before was different from frontprocess-after
	//then switch back to userspace-before by bringing the previous app to the front
	//i.e., NV was running in a different space and user switched it; now the user (may) need to switch back
	
	if (ctxBefore->windowSpace == ctxAfter->windowSpace && 
		ctxBefore->windowSpace == ctxAfter->userSpace && 
		ctxBefore->userSpace != ctxBefore->windowSpace &&
		ctxBefore->frontPID != ctxAfter->frontPID) {
		
		//activateWithOptions
		NSRunningApplication *app = [NSRunningApplication runningApplicationWithProcessIdentifier:ctxBefore->frontPID];
		if (!app) return false;
		
		return [app activateWithOptions:0];
	}
	
	//conditions not right for switch-back; presumably reverting to normal window-toggling
	return false;
}
