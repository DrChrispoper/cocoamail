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
#import "DateUtil.h"
#import "CCMStatus.h"

#import "GlobalDBFunctions.h"

#import "Reachability.h"
#import <DropboxSDK/DropboxSDK.h>
#import <Instabug/Instabug.h>

@implementation AppDelegate

-(BOOL) application:(UIApplication*)application willFinishLaunchingWithOptions:(NSDictionary*)launchOptions
{
    
    if ([AppSettings reset]) {
        [self resetApp];
    }
    
    [Instabug startWithToken:@"745ee58bde267456dafb4be700be1924"
               captureSource:IBGCaptureSourceUIKit
             invocationEvent:IBGInvocationEventScreenshot];
    
    // First, create an action
    UIMutableUserNotificationAction *acceptAction = [self createAction];
    
    // Second, create a category and tie those actions to it (only the one action for now)
    UIMutableUserNotificationCategory *inviteCategory = [self createCategory:@[acceptAction]];
    
    // Third, register those settings with our new notification category
    [self registerSettings:inviteCategory];
    
    [application setMinimumBackgroundFetchInterval:UIApplicationBackgroundFetchIntervalMinimum];
    
    DBSession* dbSession = [[DBSession alloc] initWithAppKey:@"hqbpjnlap118jqh" appSecret:@"mhdjbn703ama4wf" root:kDBRootDropbox];
    [DBSession setSharedSession:dbSession];
    
    [Accounts sharedInstance];
    
    [self registerGoogleSignIn];
    
    return YES;
}

-(BOOL) application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)options
{
    [self.window makeKeyAndVisible];
    
    return YES;
}

- (void)application:(UIApplication *)application didReceiveLocalNotification:(UILocalNotification *)notification
{
    CCMLog(@"Two");

    for (NSInteger accountIndex = 0 ; accountIndex < [AppSettings numActiveAccounts];accountIndex++) {
        [[ImapSync sharedServices:accountIndex] saveCachedData];
    }
    
    if (notification && application.applicationState == 1) {
        NSNumber *index = [notification.userInfo objectForKey:@"index"];
        NSInteger accountIndex = [AppSettings indexForAccount:[[notification.userInfo objectForKey:@"accountNum"] integerValue]];
        Conversation* conversation = [[[Accounts sharedInstance] getAccount:accountIndex] getConversationForIndex:[index integerValue]];
        
        CCMLog(@"Opening email:%@", [conversation firstMail].title);
        CCMLog(@"Application state:%ld", (long)application.applicationState);
        
        [[ImapSync sharedServices:accountIndex] saveCachedData];
        [[NSNotificationCenter defaultCenter] postNotificationName:kPRESENT_CONVERSATION_NOTIFICATION
                                                            object:nil
                                                          userInfo:@{kPRESENT_CONVERSATION_KEY:conversation}];
        
    }
    

}

-(void) applicationWillTerminate:(UIApplication*)application
{
    EmailProcessor* em = [EmailProcessor getSingleton];
    em.shuttingDown = YES;
    
    SearchRunner* sem = [SearchRunner getSingleton];
    [sem cancel];
    
    // write unwritten changes to user defaults to disk
    [NSUserDefaults resetStandardUserDefaults];
}

-(void) applicationWillResignActive:(UIApplication*)application
{
}

-(void) applicationWillEnterForeground:(UIApplication *)application
{
}

-(void) applicationDidBecomeActive:(UIApplication*)application
{
    if ([AppSettings numActiveAccounts] > 0) {
        for (NSInteger accountIndex = 0 ; accountIndex < [AppSettings numActiveAccounts];accountIndex++) {
            [[ImapSync sharedServices:accountIndex] saveCachedData];
        }
    } else {
        [UIApplication sharedApplication].applicationIconBadgeNumber = 0;
    }
}

-(void) application:(UIApplication*)application performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler
{
    
    if ([[Reachability reachabilityForInternetConnection] currentReachabilityStatus] == NotReachable ) {
        completionHandler(UIBackgroundFetchResultNoData);
    }
    else if ([self.window.rootViewController isKindOfClass:[ViewController class]]) {
        [(ViewController*)self.window.rootViewController refreshWithCompletionHandler:^(BOOL didReceiveNewPosts) {
            if (didReceiveNewPosts) {
                completionHandler(UIBackgroundFetchResultNewData);
            
                if ([AppSettings badgeCount] == 1) {
                    [UIApplication sharedApplication].applicationIconBadgeNumber = 1;
                }
            } else {
                completionHandler(UIBackgroundFetchResultNoData);
            }
        }];
    } else {
        completionHandler(UIBackgroundFetchResultNoData);
    }
}

- (void)application:(UIApplication *)application handleActionWithIdentifier:(NSString *)identifier forLocalNotification:(UILocalNotification *)notification completionHandler:(void (^)())completionHandler {
    
    if ([identifier isEqualToString:@"DELETE_IDENTIFIER"]) {
        // handle it
        NSLog(@"Delete Cached Email");
        
        NSNumber *index = [notification.userInfo objectForKey:@"index"];
        NSInteger accountIndex = [AppSettings indexForAccount:[[notification.userInfo objectForKey:@"accountNum"] integerValue]];
        Conversation* conversation = [[[Accounts sharedInstance] getAccount:accountIndex] getConversationForIndex:[index integerValue]];
        
        CCMLog(@"Email in account:%d (%d)", [[conversation firstMail].email.uids[0] account], [conversation firstMail].email.accountNum);

        [[[Accounts sharedInstance] getAccount:accountIndex] moveConversation:conversation from:FolderTypeWith(FolderTypeInbox, 0) to:FolderTypeWith(FolderTypeDeleted, 0)];
    }
    
    // Call this when you're finished
    completionHandler();
}

-(BOOL) application:(UIApplication*)application openURL:(NSURL*)url sourceApplication:(NSString*)sourceApplication annotation:(id)annotation
{
    if ([[GIDSignIn sharedInstance] handleURL:url sourceApplication:sourceApplication annotation:annotation]) {
        return YES;
    }
    
    if ([[DBSession sharedSession] handleOpenURL:url]) {
        NSDictionary* statusText = @{@"cloudServiceName":@"Dropbox"};
        [[NSNotificationCenter defaultCenter]
         postNotificationName:@"AuthNotification"
         object:nil
         userInfo:statusText];
        
        return YES;
    }
    
    NSFileManager *filemgr = [NSFileManager defaultManager];
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString* inboxPath = [documentsDirectory stringByAppendingPathComponent:@"Inbox"];
    NSArray *dirFiles = [filemgr contentsOfDirectoryAtPath:inboxPath error:nil];
    
    if (dirFiles.count > 0) {
        Mail* mail = [Mail newMailFormCurrentAccount];
        
        for (NSString* fileName in dirFiles) {
            Attachment* attach = [[Attachment alloc]init];
            attach.fileName = fileName;
            
            NSString* localPath = [inboxPath stringByAppendingPathComponent:fileName];
            
            if ([filemgr fileExistsAtPath:localPath]) {
                attach.data = [filemgr contentsAtPath:localPath];
                attach.size = [attach.data length];
            }
            
            if (mail.attachments == nil) {
                mail.attachments = @[attach];
            }
            else {
                NSMutableArray* ma = [mail.attachments mutableCopy];
                [ma addObject:attach];
                mail.attachments = ma;
            }
        }
        
        for (NSString* fileName in dirFiles) {
            NSString* localPath = [inboxPath stringByAppendingPathComponent:fileName];
            [filemgr removeItemAtPath:localPath error:nil];
        }

        
        [[NSNotificationCenter defaultCenter] postNotificationName:kPRESENT_EDITMAIL_NOTIFICATION object:nil userInfo:@{kPRESENT_MAIL_KEY:mail}];
    }
    // Add whatever other url handling code your app requires here
    return NO;
}

-(void) signIn:(GIDSignIn*)signIn
didSignInForUser:(GIDGoogleUser*)user
     withError:(NSError*)error
{
    if (!error) {
    NSString* accessToken = user.authentication.accessToken; // Safe to send to the server
    NSString* name = user.profile.name;
    NSString* email = user.profile.email;
    
    // [START_EXCLUDE]
    NSDictionary* statusText = @{@"accessToken":accessToken, @"email":email, @"name":name};
    [[NSNotificationCenter defaultCenter]
     postNotificationName:@"ToggleAuthUINotification"
     object:nil
     userInfo:statusText];
    // [END_EXCLUDE]
    
    if (!error && accessToken) {
        NSInteger accountIndex = [AppSettings accountIndexForEmail:email];
        
        if (accountIndex != -1) {
            if (![accessToken isEqualToString:[AppSettings oAuth:accountIndex]]) {
                [AppSettings setOAuth:accessToken accountIndex:accountIndex];
                [[ImapSync doLogin:accountIndex] subscribeError:^(NSError *error) {
                    CCMLog(@"connection error");
                } completed:^{}];
            }
        }
    }
    }
    else {
        CCMLog(@"Erorr signing in %@",error.localizedDescription);
    }
}

#pragma mark - Settings

-(void) resetApp
{
    // reset - delete all data and settings
    [AppSettings setReset:NO];
    for (int accountIndex = 0; accountIndex < [AppSettings numActiveAccounts]; accountIndex++) {
        //NSInteger accountIndex = [AppSettings numAccountForIndex:i];
        [AppSettings setUsername:@"" accountIndex:accountIndex];
        [AppSettings setPassword:@"" accountIndex:accountIndex];
        [AppSettings setOAuth:@"" accountIndex:accountIndex];
        [AppSettings setIdentifier:@"" accountIndex:accountIndex];
        [AppSettings setAccountDeleted:YES accountIndex:accountIndex];
    }
    
    [AppSettings setDataInitVersion];
    //[AppSettings setFirstSync:YES];
    [AppSettings setGlobalDBVersion:0];
    
    //[AppSettings setNumAccounts:0];
    
    [GlobalDBFunctions deleteAll];
}

#pragma mark - Notifications

- (UIMutableUserNotificationAction *)createAction {
    UIMutableUserNotificationAction *acceptAction = [[UIMutableUserNotificationAction alloc] init];
    acceptAction.identifier = @"DELETE_IDENTIFIER";
    acceptAction.title = NSLocalizedString(@"quick-swipe.delete",@"Lock screeen swipe");
    
    // Given seconds, not minutes, to run in the background
    acceptAction.activationMode = UIUserNotificationActivationModeBackground;
    
    // If YES the actions is red
    acceptAction.destructive = YES;
    
    // If YES requires passcode, but does not unlock the device
    acceptAction.authenticationRequired = NO;
    
    return acceptAction;
}

- (UIMutableUserNotificationCategory *)createCategory:(NSArray *)actions {
    UIMutableUserNotificationCategory *mailCategory = [[UIMutableUserNotificationCategory alloc] init];
    mailCategory.identifier = @"MAIL_CATEGORY";
    
    // You can define up to 4 actions in the 'default' context
    // On the lock screen, only the first two will be shown
    // If you want to specify which two actions get used on the lockscreen, use UIUserNotificationActionContextMinimal
    [mailCategory setActions:actions forContext:UIUserNotificationActionContextDefault];
    
    // These would get set on the lock screen specifically
    // [inviteCategory setActions:@[declineAction, acceptAction] forContext:UIUserNotificationActionContextMinimal];
    
    return mailCategory;
}

- (void)registerSettings:(UIMutableUserNotificationCategory *)category {
    UIUserNotificationType types = (UIUserNotificationTypeAlert | UIUserNotificationTypeBadge | UIUserNotificationTypeSound);
    
    NSSet *categories = [NSSet setWithObjects:category, nil];
    UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:types categories:categories];
    
    [[UIApplication sharedApplication] registerUserNotificationSettings:settings];
}

#pragma mark - Google Sign In

-(void) registerGoogleSignIn
{
    NSString* driveScope = @"https://mail.google.com/";
    NSArray* currentScopes = [GIDSignIn sharedInstance].scopes;
    [GIDSignIn sharedInstance].scopes = [currentScopes arrayByAddingObject:driveScope];
    
    NSError* configureError;
    [[GGLContext sharedInstance] configureWithError:&configureError];
    NSAssert(!configureError, @"Error configuring Google services: %@", configureError);
    
    [GIDSignIn sharedInstance].delegate = self;
}

@end