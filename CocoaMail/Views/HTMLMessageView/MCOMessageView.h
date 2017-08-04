//
//  MCOMessageView.h
//
//  Created by DINH Viêt Hoà on 1/19/13.
//  Copyright (c) 2013 MailCore. All rights reserved.
//

#include <MailCore/MailCore.h>
//#import <POP/POP.h>

@protocol MCOMessageViewDelegate;

@class Mail;

@interface MCOMessageView : UIView <UIWebViewDelegate>

@property (nonatomic, copy) NSString* html;
@property (nonatomic, copy) Mail* mail;
@property (nonatomic, weak) id <MCOMessageViewDelegate> delegate;
@property (nonatomic) BOOL isConversation;

-(void) setBgrdColor:(UIColor*)color;

@end

@protocol MCOMessageViewDelegate <NSObject>

@optional

-(void) webViewLoaded:(UIWebView*)webView;
-(void) openWebURL:(NSURL*)url;
-(void) openLongURL:(NSURL*)url;
-(void) openContentID:(NSString*)cid;
-(void) openLongContentID:(NSString*)cid;
-(void) partForUniqueID:(NSString*)partID completed:(void (^)(NSData * data))completedBlock;
-(void) scrollTo:(CGPoint)offset;

@end
