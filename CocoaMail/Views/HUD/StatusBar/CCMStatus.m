//
//  CCMStatus.m
//  CocoaMail
//
//  Created by Christopher Hockley on 01/08/14.
//  Copyright (c) 2014 Christopher Hockley. All rights reserved.
//

#import "CCMStatus.h"

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
    _statusLabel.textColor = [UIColor blackColor];
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

+(void) showStatus:(NSString *)status dismissAfter:(NSTimeInterval)interval
{
    [[CCMStatus sharedCCMStatus] showStatus:status dismissAfter:interval];
}

+(void) dismiss
{
    [[CCMStatus sharedCCMStatus] dismiss];
}

#pragma mark - private

-(void) showStatus:(NSString *)status dismissAfter:(NSTimeInterval)interval
{
    if (_statusWindow.hidden) {
        [self setStatus:status];
        [self dismissAfter:interval];
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
        [_messageQueue insertObject:@{status:@(interval)} atIndex:0];
    }
}

-(void) dismiss
{
    if (_messageQueue.count == 0) {
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
    else {
        NSDictionary* statusDic = [_messageQueue lastObject];
        [_messageQueue removeLastObject];
        
        [UIView animateWithDuration:0.1 animations:^{
            //_backgroundView.alpha = 0.0;
        } completion:^(BOOL finished) {
            [self setStatus:[[statusDic allKeys] firstObject]];
            [self dismissAfter:[[[statusDic allValues] firstObject] intValue]];
            [UIView animateWithDuration:0.1 animations:^{
                //_backgroundView.alpha = 1;
            }];
        }];
    }
}

-(void) dismissAfter:(NSTimeInterval)interval
{
    dispatch_time_t popTime = dispatch_time(DISPATCH_TIME_NOW, (int64_t)(interval * NSEC_PER_SEC));
    dispatch_after(popTime, dispatch_get_main_queue(), ^(void){
        [self dismiss];
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
