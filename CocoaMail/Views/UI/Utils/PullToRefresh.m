//
//  PullToRefresh.m
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 19/08/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "PullToRefresh.h"

#import "ViewController.h"
#import "Accounts.h"


@interface PullToRefresh ()

@property (nonatomic, weak) UIActivityIndicatorView* pullToRefresh;
@property (nonatomic, weak) UIView* pullToRefreshSupport;


@end

@implementation PullToRefresh

-(void) scrollViewDidScroll:(UIScrollView*)scrollView
{
    if (self.pullToRefresh.isAnimating) {
        return;
    }
    
    if (scrollView.contentOffset.y < (-scrollView.contentInset.top- 0 - self.delta)) {
        
        if (self.pullToRefresh == nil ) {
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
            UIActivityIndicatorView* av = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
            [av stopAnimating];
            av.center = CGPointMake(scrollView.frame.size.width / 2, -35 + self.delta);
            [scrollView addSubview:av];
            
            self.pullToRefresh = av;
            
        }
        
        self.pullToRefresh.hidden = NO;
        
        CGFloat limite = -scrollView.contentInset.top - 60;
        CGFloat pourc = scrollView.contentOffset.y / limite;
        
        if (pourc>1) {
            pourc = 1.f;
        }
        
        pourc = pourc * pourc;
        self.pullToRefresh.transform = CGAffineTransformScale(CGAffineTransformMakeRotation(M_PI_2), pourc, pourc);
    }
    else {
        self.pullToRefresh.hidden = YES;
    }
}

-(void) scrollViewDidEndDragging:(UIScrollView*)scrollView
{
    if (scrollView.contentOffset.y < (-scrollView.contentInset.top-60)) {
        
        [self.pullToRefresh startAnimating];
        [ViewController animateCocoaButtonRefresh:YES];
        
        //[scrollView setContentOffset:scrollView.contentOffset animated:NO];
        
        UIEdgeInsets lastInset = scrollView.contentInset;
        
        UIEdgeInsets newInset = scrollView.contentInset;
        newInset.top += 65;
        
        [UIView animateWithDuration:0.2 animations:^{
            scrollView.contentInset = newInset;
        }];
        
        // fake async
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [ViewController animateCocoaButtonRefresh:YES];
            [self.pullToRefresh stopAnimating];
            scrollView.contentInset = lastInset;
            [[Accounts sharedInstance].currentAccount refreshCurrentFolder];
            [[Accounts sharedInstance].currentAccount showProgress];
            
        });
        // TODO true one
    }
}


@end
