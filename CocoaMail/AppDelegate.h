//
//  AppDelegate.h
//  CocoaMail
//
//  Created by Christopher Hockley on 19/08/15.
//  Copyright (c) 2015 Christopher Hockley. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <Google/SignIn.h>


@interface AppDelegate : UIResponder <UIApplicationDelegate, GIDSignInDelegate>

@property (strong, nonatomic) UIWindow* window;


@end

