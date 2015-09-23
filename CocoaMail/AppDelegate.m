//
//  AppDelegate.m
//  CocoaMail
//
//  Created by Christopher Hockley on 19/08/15.
//  Copyright (c) 2015 Christopher Hockley. All rights reserved.
//

#import "AppDelegate.h"

#import "MailListViewController.h"

#import "AppSettings.h"
#import "EmailProcessor.h"
#import "SearchRunner.h"
#import "ImapSync.h"

#import "GlobalDBFunctions.h"

#import "Reachability.h"
#import <DropboxSDK/DropboxSDK.h>
#import <Instabug/Instabug.h>

@implementation AppDelegate

- (BOOL)application:(UIApplication *)application willFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    if ([AppSettings reset]) {
        [self resetApp];
    }
    
    //TOOD:IAP
    [self activatePurchasedFeatures];
    
    [Instabug startWithToken:@"745ee58bde267456dafb4be700be1924" captureSource:IBGCaptureSourceUIKit invocationEvent:IBGInvocationEventShake];
    
    UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:UIUserNotificationTypeAlert | UIUserNotificationTypeBadge | UIUserNotificationTypeSound categories:nil];
    [application registerUserNotificationSettings:settings];
    [application registerForRemoteNotifications];
    
    [application setMinimumBackgroundFetchInterval:UIApplicationBackgroundFetchIntervalMinimum];
    
    DBSession *dbSession = [[DBSession alloc] initWithAppKey:@"hqbpjnlap118jqh" appSecret:@"mhdjbn703ama4wf" root:kDBRootDropbox];
    [DBSession setSharedSession:dbSession];
    
    [[Accounts sharedInstance] setCurrentAccountIdx:[AppSettings defaultAccount]-1];
    
    NSString *driveScope = @"https://mail.google.com/";
    NSArray *currentScopes = [GIDSignIn sharedInstance].scopes;
    [GIDSignIn sharedInstance].scopes = [currentScopes arrayByAddingObject:driveScope];
    
    NSError* configureError;
    [[GGLContext sharedInstance] configureWithError: &configureError];
    NSAssert(!configureError, @"Error configuring Google services: %@", configureError);
    
    [GIDSignIn sharedInstance].delegate = self;
    
    /*if ([AppSettings numActiveAccounts] == 0) {
        UIStoryboard *storyboard = self.window.rootViewController.storyboard;
        UIViewController *rootViewController = [storyboard instantiateViewControllerWithIdentifier:@"LoginID"];
        self.window.rootViewController = rootViewController;
        [self.window makeKeyAndVisible];
    }*/
    
    return YES;
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)options
{
    [self.window makeKeyAndVisible];
    
    return YES;
}

- (void)applicationWillTerminate:(UIApplication *)application
{
    EmailProcessor *em = [EmailProcessor getSingleton];
    em.shuttingDown = YES;
    
    SearchRunner *sem = [SearchRunner getSingleton];
    [sem cancel];
    
    // write unwritten changes to user defaults to disk
    [NSUserDefaults resetStandardUserDefaults];
}

- (void)applicationWillResignActive:(UIApplication *)application{}

- (void)applicationDidBecomeActive:(UIApplication *)application
{
    if (([AppSettings numActiveAccounts])>0) {
        for (NSInteger i = 0 ; i < [AppSettings numActiveAccounts];i++) {
            NSInteger accountIndex = [AppSettings numAccountForIndex:i];
            [[ImapSync sharedServices:accountIndex] saveCachedData];
            
            if ([AppSettings badgeCount] == 1) {
                [UIApplication sharedApplication].applicationIconBadgeNumber = 0;
            }
        }
    }else{
        [UIApplication sharedApplication].applicationIconBadgeNumber = 0;
    }
}

- (void)application:(UIApplication *)application performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler
{
    if ([[Reachability reachabilityForInternetConnection] currentReachabilityStatus] == NotReachable )
    {
        completionHandler(UIBackgroundFetchResultNoData);
    }
    else if ([self.window.rootViewController isKindOfClass:[ViewController class]])
    {
        [(ViewController *)self.window.rootViewController refreshWithCompletionHandler:^(BOOL didReceiveNewPosts) {
            if (didReceiveNewPosts) {
                completionHandler(UIBackgroundFetchResultNewData);
            
                if ([AppSettings badgeCount] == 1) {
                    [UIApplication sharedApplication].applicationIconBadgeNumber = 1;
                }
            }
            else
            {
                completionHandler(UIBackgroundFetchResultNoData);
            }
        }];
    }
    else
    {
        completionHandler(UIBackgroundFetchResultNoData);
    }
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation
{
    if ([[GIDSignIn sharedInstance] handleURL:url sourceApplication:sourceApplication annotation:annotation]) {
        return YES;
    }
    
    if ([[DBSession sharedSession] handleOpenURL:url]) {
        if ([[DBSession sharedSession] isLinked]) {
            CCMLog(@"App linked successfully!");
            // At this point you can start making API calls
        }
        
        return YES;
    }
    
    // Add whatever other url handling code your app requires here
    return NO;
}

- (void)signIn:(GIDSignIn *)signIn
didSignInForUser:(GIDGoogleUser *)user
     withError:(NSError *)error {
    NSString *idToken = user.authentication.accessToken; // Safe to send to the server
    NSString *name = user.profile.name;
    NSString *email = user.profile.email;
    
    // [START_EXCLUDE]
    NSDictionary *statusText = @{@"accessToken":idToken,@"email":email,@"name":name};
    [[NSNotificationCenter defaultCenter]
     postNotificationName:@"ToggleAuthUINotification"
     object:nil
     userInfo:statusText];
    // [END_EXCLUDE]
    
    if (!error && idToken) {
        NSInteger accountNum = [AppSettings numAccountForEmail:email];
        if(accountNum == -1){
            accountNum = [AppSettings numAccounts]+1;
        }
            
        [AppSettings setOAuth:idToken accountNum:accountNum];
    }
}

#pragma mark - Settings

- (void)activatePurchasedFeatures
{
    [AppSettings setFeaturePurchased:@"Premium"];
}

- (void)resetApp
{
    // reset - delete all data and settings
    [AppSettings setReset:NO];
    for (int i = 0; i < [AppSettings numActiveAccounts]; i++) {
        NSInteger accountIndex = [AppSettings numAccountForIndex:i];
        [AppSettings setUsername:@"" accountNum:accountIndex];
        [AppSettings setPassword:@"" accountNum:accountIndex];
        [AppSettings setOAuth:@"" accountNum:accountIndex];
        [AppSettings setIdentifier:@"" accountNum:accountIndex];
        [AppSettings setAccountDeleted:YES accountNum:accountIndex];
    }
    
    [AppSettings setDataInitVersion];
    [AppSettings setFirstSync:YES];
    [AppSettings setGlobalDBVersion:0];
    
    [AppSettings setNumAccounts:0];
    
    [GlobalDBFunctions deleteAll];
}

@end
