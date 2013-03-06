//
//  NTNNotesListTableView.m
//  Notation
//
//  Created by Zachary Waldowski on 2/27/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import "NTNNotesListTableView.h"

@interface NTNNotesListTableView ()

@end

@implementation NTNNotesListTableView

- (void)ntn_sharedInit {

}

- (id)initWithFrame:(NSRect)frame
{
    if ((self = [super initWithFrame:frame])) {
        [self ntn_sharedInit];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder {
	if ((self = [super initWithCoder: aDecoder])) {
		[self ntn_sharedInit];
	}
	return self;
}

@end
