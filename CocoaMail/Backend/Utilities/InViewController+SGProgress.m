//
//  UINavigationController+SGProgress.m
//  NavigationProgress
//
//  Created by Shawn Gryschuk on 2013-09-19.
//  Copyright (c) 2013 Shawn Gryschuk. All rights reserved.
//

#import "InViewController+SGProgress.h"
#import "SGProgressView.h"

#define SGMaskColor [UIColor colorWithWhite:0 alpha:0.4]

CGFloat const SGProgressBarHeight = 2.5;

@implementation InViewController (SGProgress)

- (SGProgressView *)progressView
{
	SGProgressView *_progressView;
	for (UIView *subview in [self.navBar subviews])
	{
		if ([subview isKindOfClass:[SGProgressView class]])
		{
			_progressView = (SGProgressView *)subview;
		}
	}

	if (!_progressView)
	{
		CGRect slice, remainder;
		CGRectDivide(self.navBar.bounds, &slice, &remainder, SGProgressBarHeight, CGRectMaxYEdge);
		_progressView = [[SGProgressView alloc] initWithFrame:slice];
		_progressView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleTopMargin;
		[self.navBar addSubview:_progressView];
	}

	return _progressView;
}

- (void)resetTitle
{
	BOOL titleChanged = [[[NSUserDefaults standardUserDefaults] objectForKey:kSGProgressTitleChanged] boolValue];

	if(titleChanged)
	{
		NSString *oldTitle = [[NSUserDefaults standardUserDefaults] objectForKey:kSGProgressOldTitle];
		//add animation
		self.navigationItem.title = oldTitle;
	}

	[[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:NO] forKey:kSGProgressTitleChanged];
	[[NSUserDefaults standardUserDefaults] setObject:@"" forKey:kSGProgressOldTitle];
	[[NSUserDefaults standardUserDefaults] synchronize];

}

- (void)changeSGProgressWithTitle:(NSString *)title
{
	BOOL titleAlreadyChanged = [[[NSUserDefaults standardUserDefaults] objectForKey:kSGProgressTitleChanged] boolValue];
	if(!titleAlreadyChanged)
	{
		NSString *oldTitle = self.navigationItem.title;
		[[NSUserDefaults standardUserDefaults] setObject:oldTitle forKey:kSGProgressOldTitle];
		[[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithBool:YES] forKey:kSGProgressTitleChanged];
		[[NSUserDefaults standardUserDefaults] synchronize];

		//add animation
		self.navigationItem.title = title;
	}
}

#pragma mark user functions

- (void)showSGProgress
{
	[self showSGProgressWithDuration:3];
}

- (void)showSGProgressWithDuration:(float)duration
{
	SGProgressView *progressView = [self progressView];

	[UIView animateWithDuration:duration delay:0 options:UIViewAnimationOptionCurveEaseIn animations:^{
		progressView.progress = 1;
	} completion:^(BOOL finished) {
		[UIView animateWithDuration:0.5 animations:^{
			progressView.alpha = 0;
		} completion:^(BOOL finished) {
			[progressView removeFromSuperview];
			[self resetTitle];
		}];
	}];
}

- (void)showSGProgressWithDuration:(float)duration andTintColor:(UIColor *)tintColor
{
	[[self progressView] setTintColor:tintColor];
	[self showSGProgressWithDuration:duration];
}

- (void)showSGProgressWithDuration:(float)duration andTintColor:(UIColor *)tintColor andTitle:(NSString *)title
{
	[self changeSGProgressWithTitle:title];
	[self showSGProgressWithDuration:duration andTintColor:tintColor];
}

- (void)finishSGProgress
{
	SGProgressView *progressView = [self progressView];
	[UIView animateWithDuration:0.1 animations:^{
		progressView.progress = 1;
        [self cancelSGProgress];
	}];
}

- (void)cancelSGProgress
{
	SGProgressView *progressView = [self progressView];
	[UIView animateWithDuration:0.5 animations:^{
		progressView.alpha = 0;
	} completion:^(BOOL finished) {
		[progressView removeFromSuperview];
		[self resetTitle];
	}];
}

- (void)setSGProgressPercentage:(float)percentage
{
	SGProgressView *progressView = [self progressView];

	[UIView animateWithDuration:0.1 delay:0 options:UIViewAnimationOptionCurveLinear animations:^{
		progressView.progress = percentage / 100.f;

	} completion:^(BOOL finished) {
		if (percentage >= 100)
		{
			[UIView animateWithDuration:0.5 animations:^{
				progressView.alpha = 0;
			} completion:^(BOOL finished) {
				[progressView removeFromSuperview];
				[self resetTitle];
			}];
		}
	}];
}

- (void)setSGProgressPercentage:(float)percentage andTitle:(NSString *)title
{
	[self changeSGProgressWithTitle:title];
	[self setSGProgressPercentage:percentage];
}

- (void)setSGProgressPercentage:(float)percentage andTintColor:(UIColor *)tintColor
{
	[[self progressView] setTintColor:tintColor];
	[self setSGProgressPercentage:percentage];
}


@end
