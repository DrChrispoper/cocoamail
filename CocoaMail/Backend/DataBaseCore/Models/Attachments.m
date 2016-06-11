//
//  Attachments.m
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 17/08/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "Attachments.h"
#import "UserSettings.h"
#import "Accounts.h"
#import "ViewController.h"
#import "CCMAttachment.h"
#import "ImapSync.h"
#import "Reachability.h"
#import "StringUtil.h"
#import "AppSettings.h"
#import <AVFoundation/AVFoundation.h>

@implementation Attachment

-(NSString*) stringSize
{
    double convertedValue = self.size;
    
    if (self.size == 0) {
        return @"Link";
    }
    
    int multiplyFactor = 0;
    
    NSArray* tokens = @[@"bytes", @"KB", @"MB", @"GB", @"TB"];
    
    while (convertedValue > 1024) {
        convertedValue /= 1024;
        multiplyFactor++;
    }
    
    return [NSString stringWithFormat:@"%4.2f %@", convertedValue, tokens[multiplyFactor]];
}

-(UIImage*) miniature
{
    if (!self.image) {
        
        self.mimeType = [self.mimeType lowercaseString];
        
        if ([self.mimeType  isEqualToString:@"application/msword"] ||
           [self.mimeType isEqualToString:@"application/vnd.oasis.opendocument.text"]||
           [self.mimeType rangeOfString:@"text/"].location != NSNotFound) {
            self.image = [UIImage imageNamed:@"pj_text"];
        }
        else if([self.mimeType isEqualToString:@"application/pdf"]) {
            return [UIImage imageNamed:@"pj_pdf"];
        }
        else if([self.mimeType rangeOfString:@"image/"].location != NSNotFound) {
            if (self.data) {
                self.image = [UIImage imageWithData:self.data];
            }
            else {
                self.image = [UIImage imageNamed:@"pj_photo"];
            }
        }
        else if([self.mimeType rangeOfString:@"audio/"].location != NSNotFound) {
            self.image = [UIImage imageNamed:@"pj_audio"];
        }
        else if([self.mimeType rangeOfString:@"video/"].location != NSNotFound) {
            if (self.data) {
                NSString* filePath = [StringUtil filePathInDocumentsDirectoryForAttachmentFileName:self.fileName];
                
                [self.data writeToFile:filePath atomically:YES];
                
                NSURL* URL = [NSURL fileURLWithPath:filePath];
                
                AVURLAsset* asset = [[AVURLAsset alloc] initWithURL:URL options:nil];
                AVAssetImageGenerator* generate = [[AVAssetImageGenerator alloc] initWithAsset:asset];
                generate.appliesPreferredTrackTransform = TRUE;
                NSError* err = NULL;
                CMTime time = CMTimeMake(1, 60);
                CGImageRef imgRef = [generate copyCGImageAtTime:time actualTime:NULL error:&err];
                
                if (!err) {
                    self.image = [[UIImage alloc] initWithCGImage:imgRef];
                }
            }
            else {
                self.image = [UIImage imageNamed:@"pj_video"];
            }
        }
        else if([self.mimeType rangeOfString:@"zip"].location != NSNotFound || [self.mimeType rangeOfString:@"compressed"].location != NSNotFound){
            self.image = [UIImage imageNamed:@"pj_packed"];
        }
        else if ([self.mimeType rangeOfString:@"powerpoint"].location != NSNotFound) {
            self.image = [UIImage imageNamed:@"pj_powerpoint"];
        }
        else if ([self.mimeType rangeOfString:@"excel"].location != NSNotFound) {
            self.image = [UIImage imageNamed:@"pj_tabler"];
        }
        else if ([self.mimeType rangeOfString:@"3d"].location != NSNotFound) {
            self.image = [UIImage imageNamed:@"pj_3d"];
        }
        else if ([self.mimeType rangeOfString:@"vcard"].location != NSNotFound) {
            self.image = [UIImage imageNamed:@"pj_vcard"];
        }
        else if ([self.mimeType rangeOfString:@"font"].location != NSNotFound) {
            self.image = [UIImage imageNamed:@"pj_font"];
        }
        else {
            self.image = [UIImage imageNamed:@"pj_other"];
        }
    }
    
    return self.image;
}

-(void) loadLocalFile
{
    NSFileManager* fileManager = [NSFileManager defaultManager];
    NSString* localPath = [NSTemporaryDirectory() stringByAppendingPathComponent:self.fileName];
    
    if ([fileManager fileExistsAtPath:localPath]) {
        self.data = [fileManager contentsAtPath:localPath];
        self.size = [self.data length];
    }
}


@end


@interface AttachmentView ()

@property (nonatomic, weak) UILabel* name;
@property (nonatomic, weak) UILabel* extention;
@property (nonatomic, weak) UILabel* size;
@property (nonatomic, weak) UIImageView* mini;
@property (nonatomic, weak) UIButton* btn;
@property (nonatomic, weak) UIButton* cellBtn;
@property (nonatomic, strong) Attachment* att;

@property (nonatomic) NSInteger internalState;
@property (nonatomic, weak) UIImageView* circleView;

@property (nonatomic) BOOL fakeIgnoreNextEnd;

@property (nonatomic, strong) MCOIMAPFetchContentOperation* op;


@end

@implementation AttachmentView

-(instancetype) initWithWidth:(CGFloat)width leftMarg:(CGFloat)margin
{
    CGRect frame = CGRectMake(0, 0, width, 72);
    
    self = [super initWithFrame:frame];
    
    self.backgroundColor = [UIColor whiteColor];
    
    
    const CGFloat posX = 64 + margin;
    
    UILabel* n = [[UILabel alloc] initWithFrame:CGRectMake(posX, 17, width - posX - 44, 20)];
    n.font = [UIFont systemFontOfSize:16];
    n.textColor = [UIColor blackColor];
    n.backgroundColor = [UIColor clearColor];//self.backgroundColor;
    [self addSubview:n];
    n.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.name = n;
    
    UILabel* s = [[UILabel alloc] initWithFrame:CGRectMake(posX, 38, width - posX - 44, 20)];
    s.font = [UIFont systemFontOfSize:12];
    s.textColor = [UIColor colorWithWhite:0.47 alpha:1.0];
    s.backgroundColor = [UIColor clearColor];//self.backgroundColor;
    [self addSubview:s];
    s.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    self.size = s;
    
    UIImageView* iv = [[UIImageView alloc] initWithFrame:CGRectMake(posX-60, 11, 50, 50)];
    iv.backgroundColor = [UIColor clearColor];//self.backgroundColor;
    iv.contentMode = UIViewContentModeScaleAspectFit;
    [self addSubview:iv];
    iv.autoresizingMask = UIViewAutoresizingFlexibleRightMargin;
    self.mini = iv;
    
    UILabel* e = [[UILabel alloc] initWithFrame:CGRectMake(posX-60, 11, 50, 50)];
    e.textAlignment = NSTextAlignmentCenter;
    e.font = [UIFont systemFontOfSize:16];
    e.textColor = [UIColor whiteColor];
    e.backgroundColor = [UIColor clearColor];
    [self addSubview:e];
    e.autoresizingMask = UIViewAutoresizingFlexibleRightMargin;
    self.extention = e;
    [self.extention setHidden:YES];
    
    UIButton* d = [[UIButton alloc] initWithFrame:CGRectMake(width-33.f-10.f, 20.f, 33.f, 33.f)];
    d.backgroundColor = [UIColor clearColor];//self.backgroundColor;
    [self addSubview:d];
    d.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    self.btn = d;
    
    UIButton* tapAttach = [[UIButton alloc] initWithFrame:CGRectMake(0, 1.f, self.frame.size.width - 32, 71.f)];
    tapAttach.layer.cornerRadius = 8.f;
    tapAttach.backgroundColor = [UIColor clearColor];
    tapAttach.layer.masksToBounds = YES;
    
    [self addSubview:tapAttach];
    
    self.cellBtn = tapAttach;
    
    return self;
    
}

-(void) buttonActionType:(AttachmentViewAction)type
{
    switch (type) {
        case AttachmentViewActionNone:
            self.btn.hidden = YES;
            self.internalState = -1;
            break;
            
        case AttachmentViewActionDonwload:
        {
            [self.btn setImage:[UIImage imageNamed:@"download_off"] forState:UIControlStateNormal];
            [self.btn setImage:[UIImage imageNamed:@"download_on_stop"] forState:UIControlStateHighlighted];
            [self.btn addTarget:self action:@selector(_applyButtonDownload:) forControlEvents:UIControlEventTouchUpInside];
            self.internalState = 0;
            break;
        }
        case AttachmentViewActionGlobalTap:
        {
            self.btn.hidden = YES;
            [self.btn removeFromSuperview];
            
            UIButton* tapAttach = [[UIButton alloc] initWithFrame:CGRectMake(0, 1.f, self.frame.size.width - 32, 71.f)];
            tapAttach.layer.cornerRadius = 8.f;
            tapAttach.backgroundColor = [UIColor clearColor];
            tapAttach.layer.masksToBounds = YES;
            
            [tapAttach addTarget:self action:@selector(_touchButton:) forControlEvents:UIControlEventTouchDown];
            [tapAttach addTarget:self action:@selector(_touchButton:) forControlEvents:UIControlEventTouchDragEnter];
            [tapAttach addTarget:self action:@selector(_cancelTouchButton:) forControlEvents:UIControlEventTouchDragExit];
            [tapAttach addTarget:self action:@selector(_cancelTouchButton:) forControlEvents:UIControlEventTouchCancel];
            [tapAttach addTarget:self action:@selector(_applyButton:) forControlEvents:UIControlEventTouchUpInside];
            
            [self addSubview:tapAttach];
            
            self.btn = tapAttach;
            
            self.internalState = -1;
            break;
        }
        case AttachmentViewActionDelete:
        {
            UIImage* img = [[UIImage imageNamed:@"delete_off"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            [self.btn setImage:img forState:UIControlStateNormal];
            [self.btn setImage:nil forState:UIControlStateHighlighted];
            self.btn.tintColor = [[Accounts sharedInstance] currentAccount].user.color;
            self.internalState = -1;
            break;
        }
        default:
            self.internalState = -1;
            self.btn.hidden = NO;
            break;
    }
}

-(void) addActionTarget:(id)target selector:(SEL)selector andTag:(NSInteger)tag
{
    self.btn.tag = tag;
    [self.btn addTarget:target action:selector forControlEvents:UIControlEventTouchUpInside];
}

-(void) fillWith:(Attachment*)at
{
    self.att = at;
    self.name.text = at.fileName;
    self.size.text = [at stringSize];
    self.mini.image = [at miniature];
    self.extention.text = @"";
    
    /*if ([at.mimeType rangeOfString:@"image/"].location == NSNotFound && [at.mimeType rangeOfString:@"video/"].location == NSNotFound) {
        if ([at.fileName componentsSeparatedByString:@"."].count > 1) {
            NSString* ext = [[at.fileName componentsSeparatedByString:@"."] lastObject];
            self.extention.text = ext;
            [self.extention setHidden:NO];

        }
    }*/
    
    [self.cellBtn removeTarget:self action:@selector(_applyButtonDownload:) forControlEvents:UIControlEventTouchUpInside];
    [self.cellBtn removeTarget:self action:@selector(_openAttach:) forControlEvents:UIControlEventTouchUpInside];

    if (at.data) {
        [self.circleView removeFromSuperview];
        self.circleView = nil;
        
        self.internalState = 2;

        [self.btn setImage:[UIImage imageNamed:@"download_export_off"] forState:UIControlStateNormal];
        [self.btn setImage:[UIImage imageNamed:@"download_export_on"] forState:UIControlStateHighlighted];
        [self.btn addTarget:self action:@selector(_applyButtonDownload:) forControlEvents:UIControlEventTouchUpInside];
        
        [self.cellBtn addTarget:self action:@selector(_openAttach:) forControlEvents:UIControlEventTouchUpInside];
    }
    else {
        [self.cellBtn addTarget:self action:@selector(_applyButtonDownload:) forControlEvents:UIControlEventTouchUpInside];
        [self buttonActionType:AttachmentViewActionDonwload];

    }
}

-(void) _timerCercle:(NSTimer*)t
{
    if (self.internalState!=1) {
        [t invalidate];
    }
    
    [UIView animateWithDuration:0.5
                          delay:0
                        options:UIViewAnimationOptionCurveLinear
                     animations:^{
                         self.circleView.transform = CGAffineTransformRotate(self.circleView.transform, M_PI);
                     }
                     completion:nil];
    
}

-(void) beginActionDownload:(Attachment*)att
{
    if (self.internalState == 0) {
        [self _applyButtonDownload:self.btn];
        [self fetchAttachment:att];
    }
    else if (self.internalState == 2) {
        [self _applyButtonDownload:self.btn];
    }
}

-(void) doneDownloading
{
        if (self.fakeIgnoreNextEnd) {
            self.fakeIgnoreNextEnd = NO;
            return;
        }
        
        if (self.internalState==1) {
            [self.cellBtn removeTarget:self action:@selector(_applyButtonDownload:) forControlEvents:UIControlEventTouchUpInside];
            [self.cellBtn addTarget:self action:@selector(_openAttach:) forControlEvents:UIControlEventTouchUpInside];

            [self.circleView removeFromSuperview];
            self.circleView = nil;
            
            [self.btn setImage:[UIImage imageNamed:@"download_export_off"] forState:UIControlStateNormal];
            [self.btn setImage:[UIImage imageNamed:@"download_export_on"] forState:UIControlStateHighlighted];
            self.internalState = 2;
        }
}

-(void) _openAttach:(UIButton*)b
{
    [UIView animateWithDuration:.5 animations:^{
        self.layer.backgroundColor = [UIColor lightGrayColor].CGColor;
    } completion:^(BOOL finished) {
        self.layer.backgroundColor = [UIColor clearColor].CGColor;
    }];
    
    NSString* filePath = [StringUtil filePathInDocumentsDirectoryForAttachmentFileName:self.att.fileName];
    [self.att.data writeToFile:filePath atomically:YES];
    NSURL* URL = [NSURL fileURLWithPath:filePath];
    [self.delegate openURL:URL];
}

-(void) _applyButtonDownload:(UIButton*)b
{
    if (self.internalState == 0) {
    
        [UIView animateWithDuration:.5 animations:^{
            self.layer.backgroundColor = [UIColor lightGrayColor].CGColor;
        } completion:^(BOOL finished) {
            self.layer.backgroundColor = [UIColor clearColor].CGColor;
        }];
        
        self.internalState = 1;
    
        [self.btn setImage:[UIImage imageNamed:@"download_on_stop"] forState:UIControlStateNormal];
        
        
        UIImageView* cercle = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"download_on_circle"]];
        cercle.backgroundColor = [UIColor clearColor];
        [self.btn addSubview:cercle];
        self.circleView = cercle;
        
        NSTimer* t = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(_timerCercle:) userInfo:nil repeats:YES];
        [self _timerCercle:t];
        [self fetchAttachment:self.att];
    }
    else if (self.internalState==1) {
        self.internalState = 0;
        [self.op cancel];
        
        self.fakeIgnoreNextEnd = YES;
        
        [self.circleView removeFromSuperview];
        self.circleView = nil;
        
        [self.btn setImage:[UIImage imageNamed:@"download_off"] forState:UIControlStateNormal];
        [self.btn setImage:[UIImage imageNamed:@"download_on_stop"] forState:UIControlStateHighlighted];
        
    }
    else {
        // internalState == 2
        [self.delegate shareAttachment:self.att];
    }
}

-(void) _touchButton:(UIButton*)button
{
    button.backgroundColor = [[UIColor lightGrayColor] colorWithAlphaComponent:0.25];
}

-(void) _cancelTouchButton:(UIButton*)button
{
    button.backgroundColor = [UIColor clearColor];
}

-(void) _applyButton:(UIButton*)button
{
    [self _cancelTouchButton:button];
}

-(void) fetchAttachment:(Attachment*)att
{
    //if ([networkReachability currentReachabilityStatus] != NotReachable) {
        if (!att.data) {
            NSArray* uidEs = [UidEntry getUidEntriesWithMsgId:att.msgID];
            
            if (uidEs.count == 0 || ((UidEntry*)uidEs[0]).pk == 0) {
                CCMLog(@"Can't find the uid of Attachment");

                return;
            }
            
            UidEntry* uidE = uidEs[0];
            
            UserSettings* user = [AppSettings userWithNum:uidE.accountNum];
            
            NSString* folderName = [user folderServerName:uidE.folder];
            self.op = [[ImapSync sharedServices:user].imapSession fetchMessageAttachmentOperationWithFolder:folderName
                                                                                                                uid:uidE.uid
                                                                                                             partID:att.partID
                                                                                                           encoding:MCOEncodingBase64];
            
            UILabel* sizeTmp = self.size;
            
            self.op.progress = ^(unsigned int current, unsigned int maximum){
                if (maximum != 0) {
                    NSString *word = NSLocalizedString(@"attachment.dowload-progress",@"-percent- of -size-");
                    if (sizeTmp) {
                        sizeTmp.text = [NSString stringWithFormat:@"%u%% %@ %@", (current * 100 / maximum), word, [att stringSize]];
                    }
                }
            };
            
            dispatch_async([ImapSync sharedServices:user].s_queue, ^{
            [self.op start:^(NSError* error, NSData* partData) {
                if (error) {
                    CCMLog(@"%@", error);
                    return;
                }
                att.data = partData;
                [Attachment updateData:att];
                
                self.size.text = [att stringSize];
                
                att.image = nil;
                self.mini.image = [att miniature];
                
                if ([att.mimeType rangeOfString:@"image/"].location != NSNotFound || [att.mimeType rangeOfString:@"video/"].location != NSNotFound) {
                    self.extention.text = @"";
                }

                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    [self.delegate downloaded:att];
                    [self doneDownloading];
                }];
            }];
                
            });
        }
    //}
}


@end