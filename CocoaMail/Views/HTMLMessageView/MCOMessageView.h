//
//  MCOMessageView.h
//
//  Created by DINH Viêt Hoà on 1/19/13.
//  Copyright (c) 2013 MailCore. All rights reserved.
//

#include <MailCore/MailCore.h>
#import <POP/POP.h>

@protocol MCOMessageViewDelegate;


@interface MCOMessageView : UIView <UIWebViewDelegate>

@property (nonatomic, copy) NSString* html;
@property (nonatomic, weak) id <MCOMessageViewDelegate> delegate;


@end

@protocol MCOMessageViewDelegate <NSObject>

@optional
-(NSData*) MCOMessageView:(MCOMessageView*)view dataForPartWithUniqueID:(NSString*)partUniqueID;
-(void) MCOMessageView:(MCOMessageView*)view fetchDataForPartWithUniqueID:(NSString*)partUniqueID
     downloadedFinished:(void (^)(NSError* error))downloadFinished;

-(NSString*) MCOMessageView_templateForMainHeader:(MCOMessageView*)view;
-(NSString*) MCOMessageView_templateForImage:(MCOMessageView*)view;
-(NSString*) MCOMessageView_templateForAttachment:(MCOMessageView*)view;
-(NSString*) MCOMessageView_templateForMessage:(MCOMessageView*)view;
-(NSString*) MCOMessageView_templateForEmbeddedMessage:(MCOMessageView*)view;
-(NSString*) MCOMessageView_templateForEmbeddedMessageHeader:(MCOMessageView*)view;
-(NSString*) MCOMessageView_templateForAttachmentSeparator:(MCOMessageView*)view;

-(NSDictionary*) MCOMessageView:(MCOMessageView*)view templateValuesForPartWithUniqueID:(NSString*)uniqueID;
-(NSDictionary*) MCOMessageView:(MCOMessageView*)view templateValuesForHeader:(MCOMessageHeader*)header;
-(BOOL) MCOMessageView:(MCOMessageView*)view canPreviewPart:(MCOAbstractPart*)part;

-(NSString*) MCOMessageView:(MCOMessageView*)view filteredHTMLForPart:(NSString*)html;
-(NSString*) MCOMessageView:(MCOMessageView*)view filteredHTMLForMessage:(NSString*)html;
-(NSData*) MCOMessageView:(MCOMessageView*)view previewForData:(NSData*)data isHTMLInlineImage:(BOOL)isHTMLInlineImage;
-(void) webViewLoaded:(UIWebView*)webView;
-(void) openWebURL:(NSURL*)url;
-(MCOAttachment*) partForUniqueID:(NSString*)partID;


@end
