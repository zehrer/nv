//
//  TagEditingManager.m
//  Notation
//
//  Created by elasticthreads on 10/15/10.
//

@interface TagEditingManager : NSObject {

	IBOutlet NSPanel *tagPanel;
	IBOutlet NSTextField *tagField;
	BOOL isHappening;
}

- (void)awakeFromNib;

- (NSString *)newMultinoteLabels;

- (void)setTF:(NSString *)inString;

- (void)popTP:(id)sender;

- (void)closeTP:(id)sender;

- (void)setDel:(id)sender;

- (NSPanel *)tagPanel;

- (NSTextField *)tagField;

- (BOOL)isMultitagging;

@end
