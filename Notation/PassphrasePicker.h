/* PassphrasePicker */

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

@class NotationPrefs;
@class KeyDerivationManager;

@class PassphrasePicker;

@protocol PassphrasePickerDelegate <NSObject>

- (void)passphrasePicker:(PassphrasePicker *)picker choseAPassphrase:(BOOL)success;

@end

@interface PassphrasePicker : NSObject {
	IBOutlet NSButton *cancelNewButton;
	IBOutlet NSPanel *newPassphraseWindow, *window;
	IBOutlet NSSecureTextField *newPasswordField;
	IBOutlet NSButton *okNewButton;
	IBOutlet NSButton *rememberNewButton;
	IBOutlet NSSecureTextField *verifyNewPasswordField;
	IBOutlet NSButton *disclosureButton;
	IBOutlet NSTextField *advancedHelpField;
	IBOutlet NSView *dismissalButtonsView, *upperButtonsView, *advancedView;

	KeyDerivationManager *keyDerivation;
	NotationPrefs *notationPrefs;
}

@property(nonatomic, weak) id <PassphrasePickerDelegate> delegate;

- (IBAction)discloseAdvancedSettings:(id)sender;

- (void)showAroundWindow:(NSWindow *)mainWindow resultDelegate:(id <PassphrasePickerDelegate>)aDelegate;

- (IBAction)cancelNewPassword:(id)sender;

- (IBAction)okNewPassword:(id)sender;

- (id)initWithNotationPrefs:(NotationPrefs *)prefs;
@end
