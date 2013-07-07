//
//  PTHotKey.h
//  Protein
//
//  Created by Quentin Carnicelli on Sat Aug 02 2003.
//  Copyright (c) 2003 Quentin D. Carnicelli. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Carbon/Carbon.h>
#import "PTKeyCombo.h"

@interface PTHotKey : NSObject

@property (nonatomic, copy) NSString *name;
@property (nonatomic) EventHotKeyRef carbonHotKey;
@property (nonatomic, strong) PTKeyCombo *keyCombo;
@property (nonatomic, weak) id target;
@property (nonatomic) SEL action;

- (void)invoke;

@end
