//
//  InViewController+UIViewControllerPreviewing.h
//  CocoaMail
//
//  Created by Christopher Hockley on 16/01/16.
//  Copyright © 2016 Christopher Hockley. All rights reserved.
//

#import <UIKit/UIKit.h>

#import "MailListViewController.h"

@interface MailListViewController (UIViewControllerPreviewingDelegate)

- (void)check3DTouch;

- (UIViewController *)previewingContext:(id<UIViewControllerPreviewing>)previewingContext viewControllerForLocation:(CGPoint)location;

- (void)previewingContext:(id )previewingContext commitViewController: (UIViewController *)viewControllerToCommit;


@end
