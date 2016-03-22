//
//  ViewController.h
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 14/07/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "InViewController.h"
#import "GTMOAuth2Authentication.h"

#define kPRESENT_FOLDER_NOTIFICATION @"kPRESENT_FOLDER_NOTIFICATION"
//#define kPRESENT_FOLDER_NAME @"kPRESENT_FOLDER_NAME"
#define kPRESENT_FOLDER_TYPE @"kPRESENT_FOLDER_TYPE"
#define kPRESENT_FOLDER_PERSON @"kPRESENT_FOLDER_PERSON"

#define kPRESENT_CONVERSATION_NOTIFICATION @"kPRESENT_CONVERSATION_NOTIFICATION"
#define kPRESENT_CONVERSATION_KEY @"kCONV_KEY"

#define kACCOUNT_CHANGED_NOTIFICATION @"kACCOUNT_CHANGED_NOTIFICATION"

#define kPRESENT_CONTACTS_NOTIFICATION @"kPRESENT_CONTACTS_NOTIFICATION"
#define kPRESENT_MAIL_KEY @"kPRESENT_MAIL_KEY"

#define kPRESENT_CONVERSATION_ATTACHMENTS_NOTIFICATION @"kPRESENT_CONVERSATION_ATTACHMENTS_NOTIFICATION"
//#define kPRESENT_CONVERSATION_KEY @"kCONV_KEY"

#define kPRESENT_EDITMAIL_NOTIFICATION @"kPRESENT_EDITMAIL_NOTIFICATION"
//#define kPRESENT_MAIL_KEY @"kPRESENT_MAIL_KEY"
#define kPRESENT_DROPBOX_NOTIFICATION @"kPRESENT_DROPBOX_NOTIFICATION"
#define kPRESENT_DELEGATE_KEY @"kDELEGATE_KEY"

#define kPRESENT_SETTINGS_NOTIFICATION @"kPRESENT_SETTINGS_NOTIFICATION"

#define kPRESENT_SEARCH_NOTIFICATION @"kPRESENT_SEARCH_NOTIFICATION"


#define kBACK_NOTIFICATION @"kBACK_NOTIFICATION"
#define kBACK_TO_INBOX_NOTIFICATION @"kBACK_TO_INBOX_NOTIFICATION"

#define kSETTINGS_CLOUD_NOTIFICATION @"kSETTINGS_CLOUD_NOTIFICATION"
#define kSETTINGS_KEY @"kSETTINGS_KEY"
#define kSETTINGS_MAIN_ACCOUNT_NOTIFICATION @"kSETTINGS_MAIN_ACCOUNT_NOTIFICATION"
#define kSETTINGS_SWIPE_NOTIFICATION @"kSETTINGS_SWIPE_NOTIFICATION"
#define kSETTINGS_NOTIF_NOTIFICATION @"kSETTINGS_NOTIF_NOTIFICATION"

#define kSETTINGS_ACCOUNT_NOTIFICATION @"kSETTINGS_ACCOUNT_NOTIFICATION"
#define kSETTINGS_ACCOUNT_SIGN_NOTIFICATION @"kSETTINGS_ACCOUNT_SIGN_NOTIFICATION"

#define kSETTINGS_ADD_ACCOUNT_NOTIFICATION @"kSETTINGS_ADD_ACCOUNT_NOTIFICATION"
#define kSETTINGS_CREDIT_NOTIFICATION @"kSETTINGS_CREDIT_NOTIFICATION"
#define kSETTINGS_CREDIT2_NOTIFICATION @"kSETTINGS_CREDIT2_NOTIFICATION"

#define kSETTINGS_SPAMTEST_NOTIFICATION @"kSETTINGS_SPAMTEST_NOTIFICATION"

#define kCREATE_FIRST_ACCOUNT_NOTIFICATION @"kCREATE_FIRST_ACCOUNT_NOTIFICATION"

#define kQUICK_ACTION_NOTIFICATION @"kQUICK_ACTION_NOTIFICATION"

typedef void (^CRefreshCompletionHandler) (BOOL didReceiveNewPosts) ;


@interface ViewController : UIViewController

@property (nonatomic, strong) UIPanGestureRecognizer* customPGR;

+(ViewController*) mainVC;

-(UIViewController*) topIVC;

+(void) refreshCocoaButton;

+(void) presentAlertWIP:(NSString*)message;
+(void) presentAlertOk:(NSString*)message;

-(void) closeCocoaButtonIfNeeded;

+(void) animateCocoaButtonRefresh:(BOOL)anim;

+(void) temporaryHideCocoaButton:(BOOL)hide;

-(void) refreshWithCompletionHandler:(CRefreshCompletionHandler)completionHandler;


@end



