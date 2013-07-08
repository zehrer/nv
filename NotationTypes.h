//
//  NotationTypes.h
//  Notation
//
//  Created by Zach Waldowski on 7/5/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef NS_ENUM(NSInteger, NVDatabaseFormat) {
	NVDatabaseFormatSingle = 0,
    NVDatabaseFormatPlain,
    NVDatabaseFormatRTF,
	NVDatabaseFormatHTML,
    NVDatabaseFormatDOC,
    NVDatabaseFormatDOCX
};

#pragma mark - UI columns

typedef NS_ENUM(NSInteger, NVUIAttribute) {
    NVUIAttributeTitle,
    NVUIAttributeLabels,
    NVUIAttributeDateModified,
    NVUIAttributeDateCreated,
    NVUIAttributeNotePreview
};
extern NSUInteger const NVUIAttributeCount;

typedef NS_OPTIONS(NSInteger, NVTableColumnOption) {
	NVTableColumnOptionNone = 0,
	NVTableColumnOptionTitle = (1 << NVUIAttributeTitle),
	NVTableColumnOptionLabels = (1 << NVUIAttributeLabels),
	NVTableColumnOptionDateModified = (1 << NVUIAttributeDateModified),
	NVTableColumnOptionDateCreated = (1 << NVUIAttributeDateCreated),
	NVTableColumnOptionAll = NVTableColumnOptionTitle | NVTableColumnOptionLabels | NVTableColumnOptionDateModified | NVTableColumnOptionDateCreated
};

extern BOOL NVTableColumnEnabled(NVTableColumnOption opt, NVUIAttribute col);
extern NVTableColumnOption NVUIAttributeOption(NVUIAttribute attr);

extern void NVUIAttributeEachColumn(void(^block)(NVUIAttribute));

extern NSArray *NVTableColumnIdentifiersForOption(NVTableColumnOption opt);
extern NSUInteger NVTableColumnCountForOption(NVTableColumnOption opt);
extern NVTableColumnOption NVTableColumnOptionForIdentifiers(NSArray *identifiers);
extern NSString *NVUIAttributeIdentifier(NVUIAttribute col);
extern NVUIAttribute NVUIAttributeForIdentifier(NSString *identifier);
extern NSString *NVUIAttributeLocalizedValue(NVUIAttribute col);

#pragma mark -
