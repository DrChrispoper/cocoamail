//
//  PullToRefresh.m
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 19/08/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "PullToRefresh.h"
#import "UserSettings.h"
#import "ViewController.h"
#import "Accounts.h"
#import "ImapSync.h"

@interface PullToRefresh ()

@property (nonatomic, weak) UIActivityIndicatorView* pullToRefresh;
@property (nonatomic, weak) UIView* pullToRefreshSupport;
@property (nonatomic) UIEdgeInsets lastInset;

@property (nonatomic, weak) UIScrollView* sv;


@end

@implementation PullToRefresh

-(void) scrollViewDidScroll:(UIScrollView*)scrollView
{
    UIActivityIndicatorView* strongPullToRefresh = self.pullToRefresh;
    
    if (strongPullToRefresh.isAnimating) {
        return;
    }
    
    if (scrollView.contentOffset.y < (-scrollView.contentInset.top- 0 - self.delta)) {
        
        if (strongPullToRefresh == nil ) {
            /*
            UIView* support = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 44, 44)];
            support.layer.cornerRadius = 22.;
            support.layer.masksToBounds = YES;
            support.backgroundColor = [[Accounts sharedInstance] currentAccount].userColor;
            
            UIActivityIndicatorView* av = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
            [av stopAnimating];
            av.center = CGPointMake(22, 22);
            
            support.center = CGPointMake(scrollView.frame.size.width / 2, -35 + self.delta);
            
            [support addSubview:av];
            
            [scrollView addSubview:support];
            
            self.pullToRefreshSupport = support;
             */
            UIActivityIndicatorView* av = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
            av.color = [Accounts sharedInstance].currentAccount.user.color;
            [av stopAnimating];
            av.center = CGPointMake(scrollView.frame.size.width / 2, -35 + self.delta);
            [scrollView addSubview:av];
            
            strongPullToRefresh = av;
        }
        
        strongPullToRefresh.hidden = NO;
        
        CGFloat limite = -scrollView.contentInset.top - 60;
        CGFloat pourc = scrollView.contentOffset.y / limite;
        
        if (pourc>1.f) {
            pourc = 1.f;
        }
        
        pourc = pourc * pourc;
        //self.pullToRefresh.transform = CGAffineTransformMakeRotation(M_PI_2);
        strongPullToRefresh.transform = CGAffineTransformScale(CGAffineTransformMakeRotation(M_PI_2), pourc, pourc);
    }
    else {
        strongPullToRefresh.hidden = YES;
    }
}

-(void) scrollViewDidEndDragging:(UIScrollView*)scrollView
{
    if (scrollView.contentOffset.y < (-scrollView.contentInset.top-60)) {
        
        DDLogInfo(@"START OF PULL-TO-REFRESH");
        
        [self.pullToRefresh startAnimating];
        
        [scrollView setContentOffset:scrollView.contentOffset animated:NO];
        
        self.lastInset = scrollView.contentInset;
        
        UIEdgeInsets newInset = scrollView.contentInset;
        newInset.top += 65;
        
        [UIView animateWithDuration:0.2 animations:^{
            scrollView.contentInset = newInset;
        }];
        
        self.sv = scrollView;
        
        [[Accounts sharedInstance].currentAccount refreshCurrentFolder];
        //[[Accounts sharedInstance].currentAccount localFetchMore:NO];
        //[ImapSync runInboxUnread:[Accounts sharedInstance].currentAccount.user completed:^{}];
    }
}

-(void) stopAnimating
{
    [self.pullToRefresh stopAnimating];
    
    if (self.sv) {
        self.sv.contentInset = self.lastInset;
    }
}

@end
