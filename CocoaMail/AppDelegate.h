//
//  AppDelegate.h
//  CocoaMail
//
//  Created by Christopher Hockley on 19/08/15.
//  Copyright (c) 2015 Christopher Hockley. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <UserNotifications/UserNotifications.h>
#import <GTMAppAuth/GTMAppAuth.h>

@interface AppDelegate : UIResponder <UIApplicationDelegate, UNUserNotificationCenterDelegate/*, GIDSignInDelegate*/>

@property (strong, nonatomic) UIWindow* window;
@property (strong, nonatomic) UIApplicationShortcutItem* launchedShortcutItem;

@property (strong, nonatomic) UILocalNotification* launchedNotification;        // Pre iOS 10.0
@property (strong, nonatomic) UNNotificationRequest* notificationRequest;       // For iOS 10.0+

// For Google App Authorization
@property(nonatomic, nullable) id<OIDAuthorizationFlowSession> currentAuthorizationFlow;

@end

