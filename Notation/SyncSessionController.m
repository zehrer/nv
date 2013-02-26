//
//  SyncSessionController.m
//  Notation
//

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


#import "SyncSessionController.h"
#import "InvocationRecorder.h"
#import "NotationDirectoryManager.h"
#import "SimplenoteSession.h"
#include <IOKit/pwr_mgt/IOPMLib.h>

NSString *SyncSessionsChangedVisibleStatusNotification = @"SSCVSN";

@implementation SyncSessionController

static void SleepCallBack(void *refcon, io_service_t y, natural_t messageType, void *messageArgument);

- (id)initWithSyncDelegate:(id)aSyncDelegate notationPrefs:(NotationPrefs *)prefs {
	if ((self = [super init])) {
		if (!(syncDelegate = aSyncDelegate)) {
			NSLog(@"%@: need syncDelegate!", NSStringFromSelector(_cmd));
			return nil;
		}
		if (!(notationPrefs = prefs)) {
			NSLog(@"%@: need notationPrefs!", NSStringFromSelector(_cmd));
			return nil;
		}
		syncServiceTimers = [[NSMutableDictionary alloc] init];
	}
	return self;
}

//these two methods must return parallel arrays:

+ (NSArray *)allServiceNames {
	static NSArray *allNames = nil;
	if (!allNames) allNames = @[SimplenoteServiceName];
	return allNames;
}

+ (NSArray *)allServiceClasses {
	static NSArray *allClasses = nil;
	if (!allClasses) allClasses = @[NSClassFromString(@"SimplenoteSession")];

	return allClasses;
}

- (void)setSyncDelegate:(id)aDelegate {
	syncDelegate = aDelegate;
}

- (id)syncDelegate {
	return syncDelegate;
}

static void SleepCallBack(void *refcon, io_service_t y, natural_t messageType, void *messageArgument) {

	SyncSessionController *controller = (__bridge SyncSessionController *) refcon;
	InvocationRecorder *invRecorder = nil;

	switch (messageType) {
		case kIOMessageSystemWillSleep:
			[[(invRecorder = [InvocationRecorder invocationRecorder]) prepareWithInvocationTarget:controller] endDelayingSleepWithMessage:messageArgument];

			if (![controller waitForUncommitedChangesWithInvocation:[invRecorder invocation]]) {
				//if we don't have to wait, then do not delay sleep
				[controller endDelayingSleepWithMessage:messageArgument];
			} else {
				NSLog(@"delaying sleep for uncommitted changes");
			}
			break;
		case kIOMessageCanSystemSleep:
			//pevent idle sleep if a session is currently running
			if ([controller hasRunningSessions]) {
				IOCancelPowerChange(controller->fRootPort, (long) messageArgument);
			} else {
				IOAllowPowerChange(controller->fRootPort, (long) messageArgument);
			}
			break;
		case kIOMessageSystemHasPoweredOn:
			//after waking from sleep, probably don't need to do anything as the services' network reachability check(s) ought to run later, anyway
			break;
	}
}

- (void)endDelayingSleepWithMessage:(void *)messageArgument {
	//NSLog(@"allow powerchange under port %X for '%d'", fRootPort, (long)messageArgument);
	IOAllowPowerChange(fRootPort, (long) messageArgument);
}

- (void)_registerPowerChangeCallbackIfNecessary {
	if (!notifyPortRef) {
		if ((fRootPort = IORegisterForSystemPower((__bridge void *) self, &notifyPortRef, SleepCallBack, &deregisteringNotifier))) {
			CFRunLoopAddSource(CFRunLoopGetCurrent(), IONotificationPortGetRunLoopSource(notifyPortRef), kCFRunLoopCommonModes);
			//NSLog(@"registered for power change under port %X", fRootPort);
		} else {
			NSLog(@"error: IORegisterForSystemPower");
		}
	}
}

- (void)unregisterPowerChangeCallback {
	if (notifyPortRef) {
		CFRunLoopRemoveSource(CFRunLoopGetCurrent(), IONotificationPortGetRunLoopSource(notifyPortRef), kCFRunLoopCommonModes);

		IODeregisterForSystemPower(&deregisteringNotifier);
		IOServiceClose(fRootPort);
		IONotificationPortDestroy(notifyPortRef);
		//NSLog(@"unregistered for power change under port %X", fRootPort);
		fRootPort = 0;
		notifyPortRef = NULL;
	}
}

- (id <SyncServiceSession>)_sessionForSyncService:(NSString *)serviceName {
	//map names to sync service sessions, creating them if necessary
	NSAssert(serviceName != nil, @"servicename is required");

	if (!syncServiceSessions) syncServiceSessions = [[NSMutableDictionary alloc] initWithCapacity:1];

	id <SyncServiceSession> session = syncServiceSessions[serviceName];

	if (!session) {
		if ([serviceName isEqualToString:SimplenoteServiceName]) {

			if (![notationPrefs syncServiceIsEnabled:SimplenoteServiceName]) return nil;

			SimplenoteSession *snSession = [[SimplenoteSession alloc] initWithNotationPrefs:notationPrefs];
			if (snSession) {
				syncServiceSessions[serviceName] = snSession;
				[snSession setDelegate:syncDelegate];
				//owned by syncServiceSessions
			}
			return snSession;
		} /* else if ([serviceName isEqualToString:SimpletextServiceName]) {
		   
		   //init and return other services here
		   
		} */ else {
			NSLog(@"%@: unknown service named '%@'", NSStringFromSelector(_cmd), serviceName);
		}
	}
	return session;
}

- (void)invalidateSyncService:(NSString *)serviceName {
	id <SyncServiceSession> session = syncServiceSessions[serviceName];

	//ensure that reachability is unscheduled if dealloc of session does not occur here
	if ([(SimplenoteSession *)session respondsToSelector:@selector(invalidateReachabilityRefs)])
		[(SimplenoteSession *)session performSelector:@selector(invalidateReachabilityRefs)];

	[session stop];
	[session setDelegate:nil];
	[syncServiceSessions removeObjectForKey:serviceName];

	[syncServiceTimers[serviceName] invalidate];
	[syncServiceTimers removeObjectForKey:serviceName];

	//can't unregister power-change-callback here because network interruptions could extend sleep via dissociating the notifier
}

- (void)initializeService:(NSString *)serviceName {
	[self queueStatusNotification];

	id <SyncServiceSession> session = [self _sessionForSyncService:serviceName];
	if (session) {
		if (!syncServiceTimers[serviceName]) {

			NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:[notationPrefs syncFrequencyInMinutesForServiceName:serviceName] * 60.0
															  target:self selector:@selector(handleSyncServiceTimer:) userInfo:session repeats:YES];
			syncServiceTimers[serviceName] = timer;
		}

		[self _registerPowerChangeCallbackIfNecessary];

		//start syncing now
		[session startFetchingListForFullSync];
	}
}

- (void)handleSyncServiceTimer:(NSTimer *)aTimer {
	id <SyncServiceSession> session = [aTimer userInfo];
	NSAssert([session conformsToProtocol:@protocol(SyncServiceSession)], @"incorrect userinfo object from sync timer");

	//file notifications are not always caught without user activity; let's make sure the directory is always in sync
	//this will have the side effect of showing the deletion-warning sheet at potentially unexpected times
	if ([syncDelegate respondsToSelector:@selector(synchronizeNotesFromDirectory)])
		[syncDelegate synchronizeNotesFromDirectory];

	[session startFetchingListForFullSync];
}

- (void)disableService:(NSString *)serviceName {
	//stops the service, turns it off, and removes the password
	[self invalidateSyncService:serviceName];
	[notationPrefs setSyncEnabled:NO forService:serviceName];
	[notationPrefs removeSyncPasswordForService:serviceName];
	//remove password to prevent instant reactivation of whatever alert ultimately prompted this action, if the user re-enables the service
	//should not need this; this class should control sync prefs directly, or at least syncprefs objs
	[[NSNotificationCenter defaultCenter] postNotificationName:NotationPrefsDidChangeNotification object:nil];
}

- (void)invalidateAllServices {
	NSArray *svcs = [[syncServiceSessions allKeys] copy];
	NSUInteger i = 0;
	for (i = 0; i < [svcs count]; i++) [self invalidateSyncService:svcs[i]];
}

- (void)initializeAllServices {
	NSArray *svcs = [[self class] allServiceNames];
	NSUInteger i = 0;
	for (i = 0; i < [svcs count]; i++) [self initializeService:svcs[i]];
}


- (void)schedulePushToAllInitializedSessionsForNote:(id <SynchronizedNote>)aNote {
	[[syncServiceSessions allValues] makeObjectsPerformSelector:@selector(schedulePushForNote:) withObject:aNote];
}

- (NSArray *)activeSessions {
	return [syncServiceSessions allValues];
}

- (void)menuNeedsUpdate:(NSMenu *)menu {
	[self _updateMenuWithCurrentStatus:menu];
}

- (void)_updateMenuWithCurrentStatus:(NSMenu *)aMenu {
	[aMenu removeAllItems];

	//BUG: on Tiger this creates an extra item that appears at the _bottom_ of the pulldown,
	//but on Leopard and above the first item is rightly used as the "title" of the button
	[aMenu addItem:[NSMenuItem separatorItem]];

	//for each service that NV can handle, add a section to the menu with information about its current session, if one exists
	NSArray *svcs = [[self class] allServiceNames];
	NSUInteger i = 0;
	for (i = 0; i < [svcs count]; i++) {
		Class class = [[self class] allServiceClasses][i];
		NSString *serviceName = svcs[i];
		BOOL isEnabled = [notationPrefs syncServiceIsEnabled:serviceName];

		//"<Name>" (if disabled, "<Name>: Disabled")
		NSMenuItem *serviceHeaderItem = [[NSMenuItem alloc] initWithTitle:isEnabled ? [class localizedServiceTitle] :
				[NSString stringWithFormat:NSLocalizedString(@"%@: Disabled", @"<Sync Service Name>: Disabled"), [class localizedServiceTitle]]
																   action:nil keyEquivalent:@""];
		[serviceHeaderItem setEnabled:NO];
		[aMenu addItem:serviceHeaderItem];

		id <SyncServiceSession> session = syncServiceSessions[serviceName];
		if (session) {
			NSArray *tasks = [[session activeTasks] allObjects];
			if ([tasks count]) {
				//one item per task
				NSUInteger j = 0;
				for (j = 0; j < [tasks count]; j++) {
					NSMenuItem *taskItem = [[NSMenuItem alloc] initWithTitle:[tasks[j] statusText] action:NULL keyEquivalent:@""];
					[taskItem setEnabled:NO];
					[aMenu addItem:taskItem];
				}
			} else {
				//use the session-level status
				NSMenuItem *sessionStatusItem = [[NSMenuItem alloc] initWithTitle:[session statusText] action:NULL keyEquivalent:@""];
				[sessionStatusItem setEnabled:NO];
				[aMenu addItem:sessionStatusItem];
			}

			//now for the ACTION items:
			[aMenu addItem:[NSMenuItem separatorItem]];

			//if running "stop"; otherwise, "sync":
			if ([session isRunning]) {
				NSMenuItem *stopItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Stop Synchronizing", nil) action:@selector(stop) keyEquivalent:@""];
				[stopItem setEnabled:YES];
				[stopItem setTarget:session];
				[aMenu addItem:stopItem];
			} else {
				NSMenuItem *syncItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Synchronize Now", nil) action:@selector(startFetchingListForFullSyncManual) keyEquivalent:@""];
				[syncItem setEnabled:YES];
				[syncItem setTarget:session];
				[aMenu addItem:syncItem];
			}


		} else {
			//can't provide any information other than enabled/disabled
			//if enabled, a message that the user or password is missing
			//if neither is missing, a generic error that ought never appear
			NSDictionary *acctDict = [notationPrefs syncAccountForServiceName:serviceName];
			NSMenuItem *badItem = nil;
			if (!acctDict[@"username"] || !acctDict[@"password"]) {
				badItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Incorrect login and password", @"sync status menu msg") action:nil keyEquivalent:@""];
			} else if (isEnabled) {
				badItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"Session could not be created", nil) action:nil keyEquivalent:@""];
			}
			[badItem setEnabled:NO];
			if (badItem) [aMenu addItem:badItem];
		}
		if (i < [svcs count] - 1) {
			[aMenu addItem:[NSMenuItem separatorItem]];
		}

	}
}

- (NSMenu *)syncStatusMenu {
	if (!statusMenu) {
		statusMenu = [[NSMenu alloc] initWithTitle:@"Sync Status"];
		[statusMenu setAutoenablesItems:NO];
		[statusMenu setDelegate:self];
	}
	return statusMenu;
}

- (BOOL)hasRunningSessions {
	NSArray *sessions = [syncServiceSessions allValues];
	NSUInteger i = 0;
	for (i = 0; i < [sessions count]; i++) {
		if ([sessions[i] isRunning]) return YES;
	}
	return NO;
}

- (BOOL)hasErrors {
	NSArray *svcs = [[self class] allServiceNames];
	NSUInteger i = 0;
	for (i = 0; i < [svcs count]; i++) {
		NSString *serviceName = svcs[i];
		if ([notationPrefs syncServiceIsEnabled:serviceName]) {
			//only report errors for those services with which the user is expecting (or hoping) to sync
			id <SyncServiceSession> session = syncServiceSessions[serviceName];
			if (!session) return YES;
			if (![session isRunning]) {
				//report errors for only stopped sessions
				if ([session lastError]) return YES;
			}
		}
	}
	return NO;
}

- (void)queueStatusNotification {
	//send an alert telling people to check our -hasErrors and -hasRunningSessions methods
	NSNotification *aNote = [NSNotification notificationWithName:SyncSessionsChangedVisibleStatusNotification object:self];
	[[NSNotificationQueue defaultQueue] enqueueNotification:aNote postingStyle:NSPostWhenIdle coalesceMask:NSNotificationCoalescingOnName forModes:nil];
}

- (NSString *)changeCommittingErrorMessage {
	return lastUncomittedChangeResultMessage;
}

- (void)invokeUncommmitedWaitCallbackIfNecessaryReturningError:(NSString *)errString {
	if ([uncommittedWaitInvocations count]) {
		lastUncomittedChangeResultMessage = [errString copy];
		if ([errString length] || ![self hasRunningSessions]) {
			//fail on the first occur that occurs; currently doesn't provide an opportunity for continuing to sync with other non-failed svcs
			[uncommittedWaitInvocations makeObjectsPerformSelector:@selector(invoke)];
			[uncommittedWaitInvocations removeAllObjects];
		}
	}
}


- (BOOL)waitForUncommitedChangesWithInvocation:(NSInvocation *)anInvocation {
	// push any uncommitted notes for all sessions, so that those will then be running
	// if we didn't have to push for any of the sessions AND none of the sessions are running, then return right away; there are no changes left to send

	// syncDelegate invokes anInvocation when any currently running sessions have stopped and no sessions have any more uncommited notes
	// it must call invokeUncommmitedWaitCallbackIfNecessary from -syncSession:didStopWithError:

	NSAssert(anInvocation != nil, @"cannot wait without an ending invocation");
	ComparableInvocation *cInvocation = [[ComparableInvocation alloc] initWithInvocation:anInvocation];
	if ([uncommittedWaitInvocations containsObject:cInvocation]) {
		NSLog(@"%@: already waiting for %@", NSStringFromSelector(_cmd), anInvocation);
		return YES; //we're already waiting for this invocation
	}

	lastUncomittedChangeResultMessage = nil;

	BOOL willNeedToWait = NO;
	NSArray *sessions = [syncServiceSessions allValues];
	NSUInteger i = 0;
	for (i = 0; i < [sessions count]; i++) {
		id <SyncServiceSession> session = sessions[i];
		if ([session hasUnsyncedChanges]) {

			//if the session has an error, the last reachability status is bad, and nothing is currently in progress, then skip pushing for it
			if ([session reachabilityFailed] && [session lastError] && ![session isRunning]) {
				NSLog(@"%@: skipped %@ due to assumed reachability status", NSStringFromSelector(_cmd), session);
				continue;
			}

			if (!(![session pushSyncServiceChanges] && ![session isRunning])) {
				willNeedToWait = YES;
				if (!uncommittedWaitInvocations) uncommittedWaitInvocations = [[NSMutableSet alloc] initWithCapacity:1];
				[uncommittedWaitInvocations addObject:cInvocation];
			}
		}
	}

	return willNeedToWait;
}


- (void)dealloc {

	[self unregisterPowerChangeCallback];

	syncServiceSessions = nil;
	uncommittedWaitInvocations = nil;

}

@end
