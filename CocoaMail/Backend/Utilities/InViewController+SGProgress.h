//
//  UINavigationController+SGProgress.h
//  NavigationProgress
//
//  Created by Shawn Gryschuk on 2013-09-19.
//  Copyright (c) 2013 Shawn Gryschuk. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "InViewController.h"

#define kSGProgressTitleChanged @"kSGProgressTitleChanged"
#define kSGProgressOldTitle @"kSGProgressOldTitle"

@interface InViewController (SGProgress)

- (void)showSGProgress;
- (void)showSGProgressWithDuration:(float)duration;
- (void)showSGProgressWithDuration:(float)duration andTintColor:(UIColor *)tintColor;
- (void)showSGProgressWithDuration:(float)duration andTintColor:(UIColor *)tintColor andTitle:(NSString *)title;

- (void)finishSGProgress;
- (void)cancelSGProgress;

- (void)setSGProgressPercentage:(float)percentage;
- (void)setSGProgressPercentage:(float)percentage andTitle:(NSString *)title;
- (void)setSGProgressPercentage:(float)percentage andTintColor:(UIColor *)tintColor;


@end
