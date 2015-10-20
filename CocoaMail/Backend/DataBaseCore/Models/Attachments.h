//
//  Attachments.h
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 17/08/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "CCMAttachment.h"

@protocol CCMAttachmentViewDelegate;


@interface Attachment : CCMAttachment

@property (nonatomic, strong) NSString* imageName;
-(NSString*) stringSize;
@property (nonatomic, strong) UIImage* image;

-(UIImage*) miniature;
-(void) loadLocalFile;


@end

typedef enum : NSUInteger {
    AttachmentViewActionNone,
    AttachmentViewActionDonwload,
    AttachmentViewActionDelete,
    AttachmentViewActionGlobalTap
} AttachmentViewAction;


@interface AttachmentView : UIView

-(instancetype) initWithWidth:(CGFloat)width leftMarg:(CGFloat)margin;

-(void) fillWith:(Attachment*)attach;
-(void) addActionTarget:(id)target selector:(SEL)selector andTag:(NSInteger)tag;

-(void) buttonActionType:(AttachmentViewAction)type;

-(void) beginActionDownload:(Attachment*)att;
-(void) doneDownloading;

@property (nonatomic, weak) id <CCMAttachmentViewDelegate> delegate;


@end

@protocol CCMAttachmentViewDelegate <NSObject>

-(void) shareAttachment:(Attachment*)att;


@end
