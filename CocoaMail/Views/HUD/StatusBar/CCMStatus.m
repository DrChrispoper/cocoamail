//
//  CCMStatus.m
//  CocoaMail
//
//  Created by Christopher Hockley on 01/08/14.
//  Copyright (c) 2014 Christopher Hockley. All rights reserved.
//

#import "CCMStatus.h"

@interface CCMStatus (){
    UIWindow *_statusWindow;
    UIView *_backgroundView;
    UILabel *_statusLabel;
    BOOL dissmissed;
}

@end

@implementation CCMStatus

- (id)init{
    self = [super init];
    if (self) {
        [self setupDefaultApperance];
    }
    return self;
}

- (void)setupDefaultApperance{
    _statusWindow = [[UIWindow alloc] initWithFrame:CGRectMake(0, 0, [[UIScreen mainScreen] bounds].size.width, 20)];
    _statusWindow.windowLevel = UIWindowLevelStatusBar;
    _statusWindow.backgroundColor = [UIColor clearColor];
    _statusWindow.alpha = 0.0;
    _statusWindow.opaque = NO;
    _statusWindow.userInteractionEnabled = YES;
    
    _backgroundView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, [[UIScreen mainScreen] bounds].size.width, 20)];
    _backgroundView.backgroundColor = [UIColor whiteColor];
    
    _statusLabel = [[UILabel alloc] initWithFrame:_backgroundView.bounds];
    _statusLabel.textColor = [UIColor blackColor];
    _statusLabel.numberOfLines = 1;
    _statusLabel.font = [UIFont systemFontOfSize:13.0];
    _statusLabel.textAlignment = NSTextAlignmentCenter;
    _statusLabel.opaque = NO;
    _statusLabel.userInteractionEnabled = YES;
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

+(void) showLoadingWithStatus:(NSString *)status
{
    [[CCMStatus sharedCCMStatus] showLoadingWithStatus:status];
}

+(void) showStatus:(NSString *)status
{
    [[CCMStatus sharedCCMStatus] showStatus:status];
}

+(void) dismiss
{
    [[CCMStatus sharedCCMStatus] dismiss];
}

+(void) dismissAfter:(NSTimeInterval)interval
{
    [[CCMStatus sharedCCMStatus] dismissAfter:interval];
}

+(void) dismissAfter:(NSTimeInterval)interval thenStatus:(NSString *)status
{
    [[CCMStatus sharedCCMStatus] dismissAfter:interval thenStatus:status];
}

#pragma mark - private

-(void) showStatus:(NSString *)status
{
    if (_statusWindow.hidden) {
        [self setStatus:status];
        _statusWindow.hidden = NO;
        [UIView animateWithDuration:0.2 animations:^{
            _statusWindow.alpha = 1;
        } completion:^(BOOL finished) {
            [UIView animateWithDuration:0.05 animations:^{
                _backgroundView.alpha = 1;
            }];
        }];
    }
    else{
        [UIView animateWithDuration:0.1 animations:^{
            _backgroundView.alpha = 0.0;
        } completion:^(BOOL finished) {
            [self setStatus:status];
            [UIView animateWithDuration:0.1 animations:^{
                _backgroundView.alpha = 1;
            }];
        }];
    }
}

-(void) dismiss
{
    [UIView animateWithDuration:0.5 animations:^{
        
        _backgroundView.alpha = 0.0;
        
    } completion:^(BOOL finished) {
        
        [UIView animateWithDuration:0.2 animations:^{
            
            _statusWindow.alpha = 0.0;
            
        } completion:^(BOOL finished) {
            
            _statusWindow.hidden = YES;
            [[[[UIApplication sharedApplication] delegate] window] makeKeyWindow];
        }];
    }];
}

-(void) dismissAfter:(NSTimeInterval)interval
{
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        [self dismiss];
    });
}

-(void) dismissAfter:(NSTimeInterval)interval thenStatus:(NSString *)status
{
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        if(!dissmissed){
            [self showStatus:status];
        }
    });
}

#pragma mark - properties
-(void) setStatus:(NSString *)status
{
    _status = status;
    _statusLabel.text = status;
    
    [self layout];
}

-(void) layout
{
    NSMutableParagraphStyle * paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.lineBreakMode = _statusLabel.lineBreakMode;
    
    CGRect rect =[_status boundingRectWithSize:CGSizeMake([[UIScreen mainScreen] bounds].size.width, 20)
                                       options:NSStringDrawingUsesLineFragmentOrigin
                                    attributes:@{
                                                 NSFontAttributeName:_statusLabel.font,
                                                 NSParagraphStyleAttributeName:paragraphStyle
                                                 }
                                       context:nil];
 
    CGRect statusLabelFrame = _statusLabel.frame;
    statusLabelFrame.size.width = rect.size.width;
}

@end
