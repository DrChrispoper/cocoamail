//
//  EditCocoaButtonView.h
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 05/09/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import <UIKit/UIKit.h>

@class Account;

@interface EditCocoaButtonView : UIView

@property (nonatomic, strong) Account* account;

+(instancetype) editCocoaButtonViewForAccount:(Account*)account;

-(void) becomeFirstResponder;

@property (nonatomic, copy) void (^cocobuttonUpdated)(void);


@end
