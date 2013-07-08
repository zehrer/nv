//
//  NotationTypes.m
//  Notation
//
//  Created by Zach Waldowski on 7/5/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import "NotationTypes.h"

#pragma mark - UI columns

static NSString *const NVUIAttributeTitleIdentifier = @"Title";
static NSString *const NVUIAttributeLabelsIdentifier = @"Tags";
static NSString *const NVUIAttributeDateModifiedIdentifier = @"Date Modified";
static NSString *const NVUIAttributeDateCreatedIdentifier = @"Date Added";
static NSString *const NVUIAttributePreviewIdentifier = @"Note Preview";

NSUInteger const NVUIAttributeCount = 5;

static void NVUIAttributeEach(void(^block)(NVUIAttribute)) {
	if (!block) return;
	for (NSUInteger i = 0; i < NVUIAttributeCount; i++) {
		block(i);
	}
}

void NVUIAttributeEachColumn(void(^block)(NVUIAttribute)) {
	if (!block) return;
	NVUIAttributeEach(^(NVUIAttribute attr) {
		if (attr == NVUIAttributeNotePreview) return;
		block(attr);
	});
}

extern BOOL NVTableColumnEnabled(NVTableColumnOption opt, NVUIAttribute col) {
	return ((NVUIAttributeOption(col) & opt) != 0);
}

extern NVTableColumnOption NVUIAttributeOption(NVUIAttribute attr) {
	if (attr == NVUIAttributeNotePreview) return NVTableColumnOptionNone;
	return (1 << attr);
}

NSArray *NVTableColumnIdentifiersForOption(NVTableColumnOption opt) {
	NSMutableArray *array = [NSMutableArray arrayWithCapacity:NVUIAttributeCount];
	
	NVUIAttributeEach(^(NVUIAttribute attr){
		if (NVTableColumnEnabled(opt, attr)) {
			[array addObject:NVUIAttributeIdentifier(attr)];
		}
	});
	
	return array;
}

extern NSUInteger NVTableColumnCountForOption(NVTableColumnOption opt)
{
	__block NSUInteger count = 0;
	
	NVUIAttributeEach(^(NVUIAttribute attr){
		if (NVTableColumnEnabled(opt, attr)) {
			count++;
		}
	});
	
	return count;
}

extern NVTableColumnOption NVTableColumnOptionForIdentifiers(NSArray *identifiers)
{
	if (!identifiers || !identifiers.count) return NVTableColumnOptionNone;
	
	NVTableColumnOption opt = NVTableColumnOptionNone;
	
	if ([identifiers containsObject:NVUIAttributeTitleIdentifier])
		opt |= NVTableColumnOptionTitle;
	if ([identifiers containsObject:NVUIAttributeLabelsIdentifier])
		opt |= NVTableColumnOptionLabels;
	if ([identifiers containsObject:NVUIAttributeDateModifiedIdentifier])
		opt |= NVTableColumnOptionDateModified;
	if ([identifiers containsObject:NVUIAttributeDateCreatedIdentifier])
		opt |= NVTableColumnOptionDateCreated;
	
	return opt;
}

extern NSString *NVUIAttributeIdentifier(NVUIAttribute col) {
	switch (col) {
		case NVUIAttributeTitle:		return NVUIAttributeTitleIdentifier;
		case NVUIAttributeLabels:		return NVUIAttributeLabelsIdentifier;
		case NVUIAttributeDateModified:	return NVUIAttributeDateModifiedIdentifier;
		case NVUIAttributeDateCreated:	return NVUIAttributeDateCreatedIdentifier;
		case NVUIAttributeNotePreview:	return NVUIAttributePreviewIdentifier;
	}
}

extern NVUIAttribute NVUIAttributeForIdentifier(NSString *identifier) {
	if (!identifier || ![identifier isKindOfClass:[NSString class]] || !identifier.length) return NVUIAttributeTitle;
	
	static dispatch_once_t onceToken;
	static NSDictionary *columns;
	dispatch_once(&onceToken, ^{
		columns = @{
			NVUIAttributeTitleIdentifier: @(NVUIAttributeTitle),
			NVUIAttributeLabelsIdentifier: @(NVUIAttributeLabels),
			NVUIAttributeDateModifiedIdentifier: @(NVUIAttributeDateModified),
			NVUIAttributeDateCreatedIdentifier: @(NVUIAttributeDateCreated),
			NVUIAttributePreviewIdentifier: @(NVUIAttributeNotePreview)
		};
	});
	return [columns[identifier] integerValue];
}

extern NSString *NVUIAttributeLocalizedValue(NVUIAttribute col)
{
	return [[NSBundle mainBundle] localizedStringForKey:NVUIAttributeIdentifier(col) value:@"" table:nil];
}
