//
//  MCOMessageView.h
//
//  Created by DINH Viêt Hoà on 1/19/13.
//  Copyright (c) 2013 MailCore. All rights reserved.
//

#include <MailCore/MailCore.h>
#import <POP/POP.h>

@protocol MCOMessageViewDelegate;

@class Mail;

@interface MCOMessageView : UIView <UIWebViewDelegate>

@property (nonatomic, copy) NSString* html;
@property (nonatomic, copy) Mail* mail;
@property (nonatomic, weak) id <MCOMessageViewDelegate> delegate;


@end

@protocol MCOMessageViewDelegate <NSObject>

@optional

-(void) webViewLoaded:(UIWebView*)webView;
-(void) openWebURL:(NSURL*)url;
-(MCOAttachment*) partForUniqueID:(NSString*)partID;


@end
