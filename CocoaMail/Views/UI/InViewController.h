//
//  InViewController.h
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 26/08/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "UIGlobal.h"
#import "WhiteBlurNavBar.h"
#import "ViewController.h"
#import "PullToRefresh.h"


@interface InViewController : UIViewController

@property (nonatomic, weak) WhiteBlurNavBar* navBar;

-(void) setupNavBarWith:(UINavigationItem*)item overMainScrollView:(UIScrollView*)mainScrollView;
-(void) setupSimpleNavBarWith:(UINavigationItem*)item andWidth:(CGFloat)width;
-(UIBarButtonItem*) backButtonInNavBar;
-(void) addPullToRefreshWithDelta:(CGFloat)delta;


-(void) cleanBeforeGoingBack;
-(BOOL) haveCocoaButton;

-(NSArray*) nextViewControllerInfos;

// if the subclass use this methods, call super
-(void) scrollViewDidScroll:(UIScrollView *)scrollView;
-(void) scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate;


@end

