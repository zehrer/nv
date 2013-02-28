//
//  NTNNotesListTableView.m
//  Notation
//
//  Created by Zachary Waldowski on 2/27/13.
//  Copyright (c) 2013 elasticthreads. All rights reserved.
//

#import "NTNNotesListTableView.h"

static CGFloat const NTNLoadingStringFontSize = 16.0f;

@interface NTNNotesListTableView ()

@property (nonatomic, strong) NSString *loadingString;
@property (nonatomic, strong) NSDictionary *loadingStringAttributes;
@property (nonatomic) CGFloat loadingStringWidth;

@end

@implementation NTNNotesListTableView

- (void)ntn_sharedInit {

	self.loadingString = NSLocalizedString(@"Loading Notes...", nil);
	self.loadingStringAttributes = @{
		NSFontAttributeName: [NSFont fontWithName:@"Helvetica Neue" size: NTNLoadingStringFontSize],
		NSForegroundColorAttributeName: [NSColor colorWithCalibratedRed:0.0f green:0.0f blue:0.0f alpha:0.5f]
	};
	self.loadingStringWidth = [self.loadingString sizeWithAttributes: self.loadingStringAttributes].width;
	
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

- (void)drawRect:(NSRect)dirtyRect
{
	[super drawRect: dirtyRect];

	if (![self dataSource]) {
		NSSize size = self.bounds.size;

		BOOL didRotate;
		NSPoint center = NSMakePoint(size.width / 2.0, size.height / 2.0);
		if ((didRotate = self.loadingStringWidth + 10.0 > size.width)) {

			NSAffineTransform *translateTransform = [NSAffineTransform transform];
			[translateTransform translateXBy:center.x yBy:center.y];
			[translateTransform rotateByDegrees:90.0];
			[translateTransform translateXBy:-center.x yBy:-center.y];
			[NSGraphicsContext saveGraphicsState];
			[translateTransform concat];
		}

		[self.loadingString drawAtPoint:NSMakePoint(center.x - self.loadingStringWidth / 2.0, center.y - NTNLoadingStringFontSize / 2.0)
					   withAttributes: self.loadingStringAttributes];

		if (didRotate) [NSGraphicsContext restoreGraphicsState];
	}
}

@end
