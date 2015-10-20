//
//  InViewController.m
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 26/08/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "InViewController.h"

@interface InViewController ()

@property (nonatomic, strong) PullToRefresh *pullToRefresh;

@property (nonatomic, strong) NSDate *datePressDownBackButton;

@end

@implementation InViewController

- (UIBarButtonItem *)backButtonInNavBar {
    UIButton *back = [WhiteBlurNavBar navBarButtonWithImage:@"back_off" andHighlighted:@"back_on"];
    [back addTarget:self action:@selector(_pressUp) forControlEvents:UIControlEventTouchUpInside];
    [back addTarget:self action:@selector(_pressDown) forControlEvents:UIControlEventTouchDown];
    
    return [[UIBarButtonItem alloc] initWithCustomView:back];
}

- (void)_pressDown {
    self.datePressDownBackButton = [NSDate date];
}

- (void)_pressUp {
    if ([self.datePressDownBackButton timeIntervalSinceNow]>-1) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kBACK_NOTIFICATION object:nil];
    } else {
        [[NSNotificationCenter defaultCenter] postNotificationName:kBACK_TO_INBOX_NOTIFICATION object:nil];
    }
}

- (void)setupSimpleNavBarWith:(UINavigationItem *)item andWidth:(CGFloat)width {
    WhiteBlurNavBar *navBar = [[WhiteBlurNavBar alloc] initWithWidth:width];
    
    if (item.rightBarButtonItem==nil) {
        UIButton *back = [WhiteBlurNavBar navBarButtonWithImage:@"empty_pixel" andHighlighted:@"empty_pixel"];
        item.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:back];
    }

    if (item.leftBarButtonItem==nil) {
        UIButton *back = [WhiteBlurNavBar navBarButtonWithImage:@"empty_pixel" andHighlighted:@"empty_pixel"];
        item.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:back];
    }
    
    [navBar pushNavigationItem:item animated:NO];
    
    UIView *navBarSupport = [[UIView alloc] initWithFrame:navBar.bounds];
    navBarSupport.clipsToBounds = YES;
    [navBarSupport addSubview:navBar];
    
    [self.view addSubview:navBarSupport];
    self.navBar = navBar;
 
    self.navBar.frame = CGRectInset(self.navBar.frame, -3, 0);
    
    navBarSupport.backgroundColor = [UIColor whiteColor];
}

- (void)setupNavBarWith:(UINavigationItem *)item overMainScrollView:(UIScrollView *)mainScrollView {
    [self setupSimpleNavBarWith:item andWidth:mainScrollView.frame.size.width];
    
    UIView *navBarSupport = self.navBar.superview;
    navBarSupport.backgroundColor = [UIColor clearColor];
    
    [self.navBar createWhiteMaskOverView:mainScrollView withOffset:mainScrollView.contentInset.top];
}

- (void)addPullToRefreshWithDelta:(CGFloat)delta {
    self.pullToRefresh = [[PullToRefresh alloc] init];
    self.pullToRefresh.delta = delta;
}

#pragma  mark - Actions

- (void)cleanBeforeGoingBack {
    // clean delegates
}

- (BOOL)haveCocoaButton {
    return YES;
}

- (NSArray *)nextViewControllerInfos {
    return nil;
}

#pragma mark - Defaut Delegate

- (void)scrollViewDidScroll:(UIScrollView *)scrollView {
    [self.navBar computeBlur];
    [self.pullToRefresh scrollViewDidScroll:scrollView];
    
    if (!scrollView.isDecelerating) {
        [[ViewController mainVC] closeCocoaButtonIfNeeded];
    }
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate {
    [self.pullToRefresh scrollViewDidEndDragging:scrollView];
}

@end

