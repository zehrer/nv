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


#import "KeyDerivationManager.h"
#import "AttributedPlainText.h"
#import "NotationPrefs.h"
#import "KeyDerivationDelaySlider.h"
#import "NSData_transformations.h"

@implementation KeyDerivationManager

- (id)initWithNotationPrefs:(NotationPrefs*)prefs {
    if ((self = [self init])) {
        notationPrefs = prefs;
        
        //compute initial test duration for the current iteration number
        crapData = [@"random crap" dataUsingEncoding:NSASCIIStringEncoding];
        crapSalt = [NSData randomDataOfLength:256];
        
        lastHashIterationCount = [notationPrefs hashIterationCount];
        lastHashDuration = [self delayForHashIterations:lastHashIterationCount];
        
        if (![self init]) {
            return nil;
        }
    }
	return self;
}

- (void)awakeFromNib {
	//let the user choose a delay between 25 ms and 3 1/2 secs
	[slider setMinValue:0.025];
	[slider setMaxValue:3.5];
	
	
	__weak typeof(self) weakSelf = self;
	slider.onMouseUpBlock = ^(KeyDerivationDelaySlider *aSlider){
		typeof(&*weakSelf) strongSelf = weakSelf;
		
		double duration = [aSlider doubleValue];
		strongSelf->lastHashIterationCount = [strongSelf estimatedIterationsForDuration:duration];
		
		if (duration > 0.7) [strongSelf->iterationEstimatorProgress startAnimation:nil];
		strongSelf->lastHashDuration = [strongSelf delayForHashIterations:strongSelf->lastHashIterationCount];
		if (duration > 0.7) [strongSelf->iterationEstimatorProgress stopAnimation:nil];
		
		//update slider for correction
		[aSlider setDoubleValue:strongSelf->lastHashDuration];
		
		[strongSelf updateToolTip];
	};
	[slider setDoubleValue:lastHashDuration];
	[self sliderChanged:slider];
	
	[self updateToolTip];
}

- (id)init {
	if ((self = [super init])) {
		if (!view) {
			if (![NSBundle loadNibNamed:@"KeyDerivationManager" owner:self])  {
				NSLog(@"Failed to load KeyDerivationManager.nib");
				NSBeep();
				return nil;
			}
		}
	}
		
	return self;
}


- (NSView*)view {
	return view;
}

- (NSInteger)hashIterationCount {
	return lastHashIterationCount;
}

- (void)updateToolTip {
	[slider setToolTip:[NSString stringWithFormat:NSLocalizedString(@"PBKDF2 iterations: %d", nil), lastHashIterationCount]];
}

- (IBAction)sliderChanged:(id)sender {
	[hashDurationField setAttributedStringValue:[NSAttributedString timeDelayStringWithNumberOfSeconds:[sender doubleValue]]];
}

- (NSTimeInterval)delayForHashIterations:(NSInteger)count {
	NSDate *before = [NSDate date];
	[crapData derivedKeyOfLength:[notationPrefs keyLengthInBits]/8 salt:crapSalt iterations:count];
	return [[NSDate date] timeIntervalSinceDate:before];
}

- (int)estimatedIterationsForDuration:(double)duration {
	//we could compute several hash durations at varying counts and use polynomial interpolation, but that may be overkill
	
	int count = (int)((duration * (double)lastHashIterationCount) / (double)lastHashDuration);
	
	int minCount = MAX(2000, count);
	//on a 1GHz machine, don't make them wait more than a minute
	return MIN(minCount, 9000000);
}

@end
