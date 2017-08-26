//
//  CCMStatus.m
//  CocoaMail
//
//  Created by Christopher Hockley on 01/08/14.
//  Copyright (c) 2014 Christopher Hockley. All rights reserved.
//

#import "CCMStatus.h"
#import "Accounts.h"
#import "UserSettings.h"

@interface CCMStatus () {
    UIWindow *_statusWindow;
    UIView *_backgroundView;
    UILabel *_statusLabel;
    BOOL dissmissed;
    NSMutableArray* _messageQueue;
}

@end

@implementation CCMStatus

-(id) init
{
    self = [super init];
    
    if (self) {
        [self setupDefaultApperance];
        _messageQueue = [[NSMutableArray alloc] init];
    }
    return self;
}

-(void) setupDefaultApperance
{
    _statusWindow = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, [[UIScreen mainScreen] bounds].size.width, 20)];
    _statusWindow.windowLevel = UIWindowLevelStatusBar;
    _statusWindow.backgroundColor = [UIColor clearColor];
    _statusWindow.alpha = 0.0;
    _statusWindow.opaque = NO;
    _statusWindow.userInteractionEnabled = NO;
    
    _backgroundView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, [[UIScreen mainScreen] bounds].size.width, 20)];
    _backgroundView.backgroundColor = [UIColor whiteColor];
    _backgroundView.userInteractionEnabled = NO;
    
    _statusLabel = [[UILabel alloc] initWithFrame:_backgroundView.bounds];
    _statusLabel.textColor = [UIColor whiteColor];
    _statusLabel.numberOfLines = 1;
    _statusLabel.font = [UIFont systemFontOfSize:13.0];
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.opaque = NO;
    _statusLabel.userInteractionEnabled = NO;
    [_backgroundView addSubview:_statusLabel];
    
    dissmissed = NO;
    [_statusWindow addSubview:_backgroundView];
}

+(id) sharedCCMStatus
{
    static CCMStatus *_sharedCCMStatus = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedCCMStatus = [[CCMStatus alloc] init];
    });
    
    return _sharedCCMStatus;
}

+(void) showStatus:(NSString *)status dismissAfter:(NSTimeInterval)interval code:(NSInteger)code
{
    [[CCMStatus sharedCCMStatus] showStatus:status dismissAfter:interval code:code];
}

+(void) dismiss
{
    [[CCMStatus sharedCCMStatus] dismissAfter:0];
}

#pragma mark - private

-(void) showStatus:(NSString *)status dismissAfter:(NSTimeInterval)interval code:(NSInteger)code
{
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        
        if (self->_statusWindow.hidden) {
            self->_backgroundView.backgroundColor = [Accounts sharedInstance].currentAccount.user.color;
            
            [self setStatus:status code:code];
            [self dismissAfter:interval];
            self->_statusWindow.hidden = NO;
            
            CGRect frame = self->_backgroundView.frame;
            frame.origin.y = frame.origin.y - 20;
            self->_backgroundView.frame = frame;
            
            [UIView animateWithDuration:0.2 animations:^{
                self->_statusWindow.alpha = 1;
            } completion:^(BOOL finished) {
                [UIView animateWithDuration:0.2 animations:^{
                    self->_backgroundView.alpha = 1;
                    
                    CGRect frame = self->_backgroundView.frame;
                    frame.origin.y = frame.origin.y + 20;
                    
                    self->_backgroundView.frame = frame;
                }];
            }];
        }
        else{
            [self->_messageQueue insertObject:@{status:@(interval), status:@(code)} atIndex:0];
        }
        
    }];
}

-(void) _dismiss
{
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        
        if (self->_messageQueue.count == 0) {
            [UIView animateWithDuration:0.5 animations:^{
                
                self->_backgroundView.alpha = 0.0;
                
            } completion:^(BOOL finished) {
                
                [UIView animateWithDuration:0.2 animations:^{
                    
                    self->_statusWindow.alpha = 0.0;
                    
                } completion:^(BOOL finished) {
                    
                    self->_statusWindow.hidden = YES;
                    [[[[UIApplication sharedApplication] delegate] window] makeKeyWindow];
                }];
            }];
        }
        else {
            NSDictionary* statusDic = [[self->_messageQueue lastObject] copy];
            [self->_messageQueue removeLastObject];
            
            [UIView animateWithDuration:0.1 animations:^{
                //_backgroundView.alpha = 0.0;
            } completion:^(BOOL finished) {
                [self setStatus:[[statusDic allKeys] firstObject] code:[[[statusDic allValues] lastObject] intValue]];
                [self dismissAfter:[[[statusDic allValues] firstObject] intValue]];
                [UIView animateWithDuration:0.1 animations:^{
                    //_backgroundView.alpha = 1;
                }];
            }];
        }
        
    }];
}

-(void) dismissAfter:(NSTimeInterval)interval
{
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        [self _dismiss];
    });
}

#pragma mark - properties
-(void) setStatus:(NSString *)status code:(NSInteger)code
{
    _status = status;
    
    NSMutableAttributedString *str= [[NSMutableAttributedString alloc] init];
    
    if (code != 0) {
        NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
        if (code == 1) {
            attachment.image = [UIImage imageNamed:@"mail_ok"];
        }
        else if (code == 2) {
            attachment.image = [UIImage imageNamed:@"mail_wrong"];
        }
        
        CGFloat offsetY = -0.0;
        
        attachment.bounds = CGRectMake(0, offsetY, attachment.image.size.width, attachment.image.size.height);
        
        NSAttributedString *attachmentAttrString = [NSAttributedString attributedStringWithAttachment:attachment];
        [str appendAttributedString:attachmentAttrString];
        
        [str appendAttributedString:[[NSMutableAttributedString alloc] initWithString:@" "]];
    }
    

    [str appendAttributedString:[[NSMutableAttributedString alloc] initWithString:status]];
    
    NSMutableParagraphStyle * paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.lineBreakMode = _statusLabel.lineBreakMode;
    paragraphStyle.alignment = NSTextAlignmentCenter;
    [str addAttributes:@{
                         NSFontAttributeName:_statusLabel.font,
                         NSParagraphStyleAttributeName:paragraphStyle
                         } range:NSMakeRange(0, str.length)];
    
    
    _statusLabel.attributedText = str;
    
    /*CGRect rect =[str boundingRectWithSize:CGSizeMake([[UIScreen mainScreen] bounds].size.width, 20)
     options:NSStringDrawingUsesLineFragmentOrigin
     context:nil];*/
     
    CGRect statusLabelFrame = _statusLabel.frame;
    statusLabelFrame.size.height = 20;
}

@end
