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
#import "UserSettings.h"
#import "Draft.h"
#import <CocoaLumberjack/CocoaLumberjack.h>
#import "CCMDDLogFormatter.h"

#import <NotificationCenter/NotificationCenter.h>
#import <UserNotifications/UserNotifications.h>
#import <UserNotificationsUI/UserNotificationsUI.h>

NSString *const CCMCategoryIdentifier = @"com.cocoamail.newmail";
NSString *const CCMDeleteTriggerIdentifier = @"com.cocoamail.delete";



//#define USING_XCODECOLORS        // Define this to use XCodeColors (no longer supported in XCode 8)

#ifdef USING_FLURRY
#import "Flurry.h"
#endif

#ifdef USING_INSTABUG
#import <Instabug/Instabug.h>
#endif

#ifdef USING_INSTABUG_COCOALUMBERJACK
#import <Instabug-CocoaLumberjack/DDInstabugLogger.h>
#endif  // USING_INSTABUG

@implementation AppDelegate

-(BOOL) application:(UIApplication*)application willFinishLaunchingWithOptions:(NSDictionary*)launchOptions
{
    BOOL shouldPerformAdditionalDelegateHandling = TRUE;
    
#ifdef USING_INSTABUG
    [Instabug startWithToken:@"745ee58bde267456dafb4be700be1924" invocationEvent:IBGInvocationEventScreenshot];
    [Instabug setIntroMessageEnabled:NO];
    [Instabug setIBGLogPrintsToConsole:NO];
    [Instabug setNetworkLoggingEnabled:NO];
#endif
    
    // Initialize CocoaLumberjack logging system
    [self _initCocoaLumberjack ];
    
#ifdef USING_FLURRY
    // Initialize Flurry analytics
    [Flurry startSession:@"D67NTWY4V6RW5RFVMRGK"];
#endif
    
    [self _initNotifications];
    
    application.applicationSupportsShakeToEdit = YES;
    
    UIApplicationShortcutItem* shortcutItem = launchOptions[UIApplicationLaunchOptionsShortcutItemKey];
    if (shortcutItem) {
        self.launchedShortcutItem = shortcutItem;
        
        // This will block "performActionForShortcutItem:completionHandler" from being called.
        shouldPerformAdditionalDelegateHandling = FALSE;
    }
    
    [self createItemsWithIcons];
    
    // set the background fetch to trigger as often as possible
    NSTimeInterval numberOfSeconds = UIApplicationBackgroundFetchIntervalMinimum;
    DDLogInfo(@"Requesting MinimumBackgroundFetchInterval = %@ seconds.",@(numberOfSeconds));
    [application setMinimumBackgroundFetchInterval:numberOfSeconds];
    
    DBSession* dbSession = [[DBSession alloc] initWithAppKey:@"hqbpjnlap118jqh" appSecret:@"mhdjbn703ama4wf" root:kDBRootDropbox];
    [DBSession setSharedSession:dbSession];
    
//    [Accounts sharedInstance];  // Allocate the shared instance
    [[Accounts sharedInstance] getDrafts];
    
    //[self registerGoogleSignIn];
    
    return shouldPerformAdditionalDelegateHandling;
}


-(void) _initNotifications
{
    self.launchedNotification = nil;
    self.notificationRequest  = nil;
    
    if ( [UNUserNotificationCenter class] ) {   // If the class exists ...

        [self _setupUNNotifications];
        
    } else {
        // For pre-iOS 10.0
        
        DDLogInfo(@"UNUserNotificationCenter class does not exist, so using older notifications.");
        
        // First, create an action
        UIMutableUserNotificationAction *deleteMessageAction = [self createAction];
        
        // Second, create a category and tie those actions to it (only the one action for now)
        UIMutableUserNotificationCategory *newMessageCategory = [self createCategory:@[deleteMessageAction]];
        
        // Third, register those settings with our new notification category
        [self registerSettings:newMessageCategory];
    }
}

/**********************************/
/*** Initialize CocoaLumberjack ***/
/**********************************/
-(void) _initCocoaLumberjack
{

#ifdef USING_INSTABUG_COCOALUMBERJACK
    // This will log CocoaLumberjack into Instabug
    DDInstabugLogger *ibgLogger = [[DDInstabugLogger alloc] init];
    if ( ibgLogger ) {
        
        ibgLogger.logFormatter = [[CCMDDLogFormatter alloc] init];
        
        [DDLog addLogger:ibgLogger withLevel:DDLogLevelWarning];
    }
#endif // using Instabug
    
    // Send debug statements to the Xcode console (uses XcodeColor)
    DDTTYLogger *ttyLogger = [DDTTYLogger sharedInstance];
    if (ttyLogger) {
        ttyLogger.logFormatter = [[CCMDDLogFormatter alloc] init];
        
        [DDLog addLogger:ttyLogger]; // Send debug statements to the XCode Console, if available
    }
    
    DDLogInfo(@"USING STANDARD DD LOGGER.");
    
    // Send debug statements to the System Log (Console.app)
//    [DDLog addLogger:[DDASLLogger sharedInstance]];
    
    // Send debug info to log files
//    DDFileLogger *fileLogger = [[DDFileLogger alloc] init];     // File Logger
//    fileLogger.rollingFrequency = 60 * 60 * 24;                 // 24 hour rolling
//    fileLogger.logFileManager.maximumNumberOfLogFiles = 7;
//    [DDLog addLogger:fileLogger];
//    
//    DDLogFileInfo *lfi = [fileLogger currentLogFileInfo];
//    DDLogInfo(@"USING DD FILE LOGGER.");
//    DDLogInfo(@"LOG PATH: \"%@\"",[lfi filePath]);

    
#ifdef USING_INSTABUG
    DDLogInfo(@"USING INSTABUG");
#else
    DDLogInfo(@"NOT USING INSTABUG");
#endif
    
#ifdef USING_INSTABUG_COCOALUMBERJACK
    DDLogInfo(@"USING INSTABUG-COCOALUMBERJACK LOGGER");
#else
    DDLogInfo(@"NOT USING INSTABUG-COCOALUMBERJACK LOGGER");
#endif
    
    DDLogInfo(@"--------------------------------------------");
   
//    DDLogError(  @"Demo: DDLogError");    // Red
//    DDLogWarn(   @"Demo: DDLogWarn");     // Orange
//    DDLogInfo(   @"Demo: DDLogInfo");     // Green
//    DDLogDebug(  @"Demo: DDLogDebug");    // Cyan
//    DDLogVerbose(@"Demo: DDLogVerbose");  // Default (black)
}

-(BOOL) application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)options
{
    [self.window makeKeyAndVisible];
    
    [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"WebKitDiskImageCacheEnabled"];
    [[NSUserDefaults standardUserDefaults] synchronize];
    
    return YES;
}


+(void)_saveAllCachedData
{
    for (UserSettings* user in [AppSettings getSingleton].users) {
        // if user is not deleted
        if (!user.isDeleted) {
            // then save its cache
            [[ImapSync sharedServices:user] saveCachedData];
        }
    }
}

#pragma mark - notification received
// The method called prior to iOS v10.0
//      For iOS v10.0 and above we Use UserNotifications Framework's
//          -[UNUserNotificationCenterDelegate willPresentNotification:withCompletionHandler:] or
//          -[UNUserNotificationCenterDelegate didReceiveNotificationResponse:withCompletionHandler:]
//
- (void)application:(UIApplication *)application didReceiveLocalNotification:(UILocalNotification *)notification
{
    [AppDelegate _saveAllCachedData];
        
    // if we received a notificatino and application is inactive
    if (notification && application.applicationState == 1) {  // UIApplicationStateInactive
        DDLogInfo(@"UILocalNotification Body: %@", notification.alertBody);
        // Save the notification for later
        self.launchedNotification = notification;
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
    if ([AppSettings numActiveAccounts] == 0) {
        [UIApplication sharedApplication].applicationIconBadgeNumber = 0;
    }
    else { // there is at least one active accounty
        
        // if there was a notification saved while we were inactive,
        // then execute it now.
    
        [AppDelegate _saveAllCachedData];
        
        [[AppSettings getSingleton] setCache:@[]];
        
        if (self.launchedShortcutItem) {
            
            [self handleShortcut:self.launchedShortcutItem];
            self.launchedShortcutItem = nil;
        }
        else if ( self.launchedNotification ) {
            
            [self _selectConversationForNotificationUserInfoDictionary:self.launchedNotification.userInfo];
            self.launchedNotification = nil;
        }
        else if ( self.notificationRequest ) {
            
            [self _selectConversationForNotificationUserInfoDictionary:self.notificationRequest.content.userInfo];
            self.notificationRequest = nil;
        }
    }
}

-(ConversationIndex *)_conversationIndexForUserInfo:(NSDictionary *)userInfo
{
    NSInteger index      = [[userInfo objectForKey:@"cIndexIndex"] integerValue];
    NSInteger accountNum = [[userInfo objectForKey:@"cIndexAccountNum"] integerValue];
    
    UserSettings* user = [AppSettings userWithNum:accountNum];
    
    if ( user == nil ) {
        DDLogWarn(@"Cannot find UserSettings for index:%@",@(index));
    }

    return [ConversationIndex initWithIndex:(NSUInteger)index user:user];
}

- (void)_selectConversationForNotificationUserInfoDictionary:(NSDictionary *)userInfo
{
    ConversationIndex *cIndex = [self _conversationIndexForUserInfo:userInfo];

    Conversation *conversation = [cIndex.user.linkedAccount getConversationForIndex:(NSUInteger)cIndex.index];
    
    [conversation foldersType];     // Return a Set of all the Folder Types of all the Mails in this Conversation
    
    DDLogInfo(@"Opening email:%@", [conversation firstMail].subject);
    DDLogInfo(@"Index: %@",@(cIndex.index));
    
    Accounts* allAccounts = [Accounts sharedInstance];
    
    allAccounts.currentAccountIdx = cIndex.user.accountIndex;
    [[allAccounts currentAccount] connect];
    
    [ViewController refreshCocoaButton];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kACCOUNT_CHANGED_NOTIFICATION object:nil];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kPRESENT_CONVERSATION_NOTIFICATION
                                                        object:nil
                                                      userInfo:@{kPRESENT_CONVERSATION_KEY:conversation}];
}


// This method is called when we are running in the Background.
//
-(void) application:(UIApplication*)application performFetchWithCompletionHandler:(void (^)(UIBackgroundFetchResult))completionHandler
{
    // Here be Background Fetch
        
    if ([[Reachability reachabilityForInternetConnection] currentReachabilityStatus] == NotReachable ) {
        DDLogInfo(@"Cannot Background Fetch: Internet Unreachable");
        completionHandler(UIBackgroundFetchResultNoData);
    }
    else if ([self.window.rootViewController isKindOfClass:[ViewController class]]) {
        [(ViewController*)self.window.rootViewController refreshWithCompletionHandler:^(BOOL didReceiveNewPosts) {
            if (didReceiveNewPosts) {
                DDLogInfo(@"Background Fetch Complete: HAVE NEW DATA.");
                completionHandler(UIBackgroundFetchResultNewData);
            } else {
                DDLogInfo(@"Background Fetch Complete: NO NEW DATA.");
                completionHandler(UIBackgroundFetchResultNoData);
            }
        }];
    } else {
        DDLogWarn(@"rootViewController is not a ViewController");
        completionHandler(UIBackgroundFetchResultNoData);
    }
}

- (void)_deleteConversationForNotificationUserInfo:(NSDictionary *)userInfo {
    
    ConversationIndex *convIndex = [self _conversationIndexForUserInfo:userInfo];
    
    Conversation* conversation = [[Accounts sharedInstance] conversationForCI:convIndex];
        
    DDLogInfo(@"Email in account:%ld", (long)[conversation user].accountNum);
    
#ifdef USING_FLURRY
    NSString* toFolderString = [convIndex.user.linkedAccount systemFolderNames][FolderTypeDeleted];
    
    NSDictionary *articleParams = [NSDictionary dictionaryWithObjectsAndKeys:
                                   @"INBOX", @"from_Folder",
                                   toFolderString, @"to_Folder",
                                   @"lock_screen", @"action_Location"
                                   ,nil];
    [Flurry logEvent:@"Conversation Moved" withParameters:articleParams];
#endif

    [convIndex.user.linkedAccount moveConversation:conversation from:inboxFolderType() to:FolderTypeWith(FolderTypeDeleted, 0) updateUI:YES];
}

// The method called prior to iOS v10.0
//
- (void)application:(UIApplication *)application handleActionWithIdentifier:(NSString *)identifier forLocalNotification:(UILocalNotification *)notification completionHandler:(void (^)())completionHandler {
    
    if ([identifier isEqualToString:CCMDeleteTriggerIdentifier]) {
        // handle it
        DDLogInfo(@"Delete Cached Email");
        
        [self _deleteConversationForNotificationUserInfo:notification.userInfo];
    }
    
    // Call this when you're finished
    completionHandler();
}

#pragma mark - openURL

// This protocol method replaced the one below it in iOS 9
-(BOOL) application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey,id> *)options
{
    return [self _openURL:url];
}

// This protocol method was depricated in iOS 9, and replaced by the call above
//  I'll leave it here so we can still operate with an older iOS.
//-(BOOL) application:(UIApplication*)application openURL:(NSURL*)url sourceApplication:(NSString*)sourceApplication annotation:(id)annotation
//{
//    /*if ([[GIDSignIn sharedInstance] handleURL:url sourceApplication:sourceApplication annotation:annotation]) {
//        return YES;
//    }*/
//    
//    return [self _openURL:url];
//}

-(BOOL) _openURL:(NSURL *)url
{
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
        Draft* draft = [Draft newDraftFormCurrentAccount];
        
        
        for (NSString* fileName in dirFiles) {
            Attachment* attach = [[Attachment alloc]init];
            attach.fileName = fileName;
            attach.msgID = draft.msgID;
            
            NSString* localPath = [inboxPath stringByAppendingPathComponent:fileName];
            
            if ([filemgr fileExistsAtPath:localPath]) {
                attach.data = [filemgr contentsAtPath:localPath];
                attach.size = [attach.data length];
            }
            
            /*if (mail.attachments == nil) {
             mail.attachments = @[attach];
             }
             else {
             NSMutableArray* ma = [mail.attachments mutableCopy];
             [ma addObject:attach];
             mail.attachments = ma;
             }*/
        }
        
        for (NSString* fileName in dirFiles) {
            NSString* localPath = [inboxPath stringByAppendingPathComponent:fileName];
            [filemgr removeItemAtPath:localPath error:nil];
        }
        
        
        [[NSNotificationCenter defaultCenter] postNotificationName:kPRESENT_EDITMAIL_NOTIFICATION object:nil userInfo:@{kPRESENT_MAIL_KEY:draft}];
    }
    // Add whatever other url handling code your app requires here
    return NO;
    
}

/*-(void) signIn:(GIDSignIn*)signIn
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
                    DDLogError(@"connection error");
                } completed:^{}];
            }
        }
    }
    }
    else {
        DDLogError(@"Erorr signing in %@",error.localizedDescription);
    }
}*/

-(void)application:(UIApplication *)application didReceiveRemoteNotification:(nonnull NSDictionary *)userInfo fetchCompletionHandler:(nonnull void (^)(UIBackgroundFetchResult))completionHandler
{
    DDLogInfo(@"UserInfro = %@",userInfo);
    
    completionHandler(UIBackgroundFetchResultNoData);
}

#pragma mark - Set Up UNNotificationCenter notifications (iOS 10.0 and above)

- (void)_setupUNNotifications
{
    // iOS version 10.0 and above
    
    DDLogInfo(@"iOS VERSION 10.0 OR HIGHER: using UNUserNotificationCenter.");
    
    UNUserNotificationCenter* center = [UNUserNotificationCenter currentNotificationCenter];
    
    center.delegate = self;
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wassign-enum"
    UNAuthorizationOptions desiredSettings = (UNAuthorizationOptionAlert | UNAuthorizationOptionBadge | UNAuthorizationOptionSound);
#pragma clang diagnostic pop
    
    // Request user authhorization
    [center requestAuthorizationWithOptions:desiredSettings
                          completionHandler:^(BOOL granted, NSError * _Nullable error) {
                              // this block runs asynchronously in background
                              
                              // Enable or disable features based on authorization.
                              if (granted) {
                                  // autorizations agreed
                                  DDLogInfo(@"Authorization granted for User Notification Alert, Badge AND/OR Sound.");
                                  
                              } else {
                                  // An Error occurred
                                  DDLogError(@"Error while authorizing Alert|Badge|Sound for User Notification, error=|%@|",error);
                              }
                          }];
    
    UNNotificationAction *deleteMessageAction =
    [UNNotificationAction actionWithIdentifier:CCMDeleteTriggerIdentifier
                                         title:NSLocalizedString(@"quick-swipe.delete",@"Lock screen swipe")
                                       options:UNNotificationActionOptionDestructive];
    
    UNNotificationCategory *newMessageCategory =
    [UNNotificationCategory categoryWithIdentifier:CCMCategoryIdentifier
                                           actions:@[deleteMessageAction]
                                 intentIdentifiers:@[]
                                           options:UNNotificationCategoryOptionCustomDismissAction];
    
    [center setNotificationCategories:[NSSet setWithObjects:newMessageCategory, nil]];
}

#pragma mark - UNUserNotificationCenterDelegate (iOS 10.0 and above)



// This method is called, in iOS 10.0 and above, when we are in the Foreground and a notification is received
//
-(void)userNotificationCenter:(UNUserNotificationCenter *)center willPresentNotification:(UNNotification *)notification withCompletionHandler:(void (^)(UNNotificationPresentationOptions))completionHandler
{
    [AppDelegate _saveAllCachedData];
    
    if (notification) {
        DDLogInfo(@"Notification Body: %@", notification.request.content.body);
        self.notificationRequest = notification.request;
    }
    
    // TODO: Can we request all 3 of these without checking that the user has authorized them?
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wassign-enum"
    UNNotificationPresentationOptions presentationOptions = UNNotificationPresentationOptionAlert | UNNotificationPresentationOptionSound | UNNotificationPresentationOptionBadge;
#pragma clang diagnostic pop
    
    if ( completionHandler ) {
        completionHandler(presentationOptions);
    }
}

// This method is called, in iOS 10.0 and above, when the User has acted on an on-screen notification.
//
-(void)userNotificationCenter:(UNUserNotificationCenter *)center didReceiveNotificationResponse:(nonnull UNNotificationResponse *)response withCompletionHandler:(nonnull void (^)())completionHandler
{
    
    NSDictionary *userInfo = response.notification.request.content.userInfo;

    if ( [response.actionIdentifier isEqualToString:UNNotificationDefaultActionIdentifier] ) {
        // App was opened from the notification interface'
        DDLogInfo(@"Notification is opening Application, so display notification's email messaage.");
        
        [self _selectConversationForNotificationUserInfoDictionary:userInfo];
        self.notificationRequest = nil;
    }
    else if ([response.actionIdentifier isEqualToString:CCMDeleteTriggerIdentifier]) {   // is this correcty?
        
        //  handle it
        DDLogInfo(@"Delete Cached Email");
        
        [self _deleteConversationForNotificationUserInfo:userInfo];
    }
    else {
        DDLogWarn(@"Unknown Identifier \"%@\"",response.actionIdentifier);
    }
    
    // Call this when you're finished
    if ( completionHandler ) {
        completionHandler();
    }
}


#pragma mark - Set Up pre-iOS 10.0 style notifications

- (UIMutableUserNotificationAction *)createAction {
    
    UIMutableUserNotificationAction *acceptAction = [[UIMutableUserNotificationAction alloc] init];
    acceptAction.identifier = CCMDeleteTriggerIdentifier;
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
    
    mailCategory.identifier = CCMCategoryIdentifier;
    
    // You can define up to 4 actions in the 'default' context
    // On the lock screen, only the first two will be shown
    // If you want to specify which two actions get used on the lockscreen, use UIUserNotificationActionContextMinimal
    [mailCategory setActions:actions forContext:UIUserNotificationActionContextDefault];
    
    // These would get set on the lock screen specifically
    // [inviteCategory setActions:@[declineAction, acceptAction] forContext:UIUserNotificationActionContextMinimal];
    
    return mailCategory;
}

- (void)registerSettings:(UIMutableUserNotificationCategory *)category {
    
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wassign-enum"
    UIUserNotificationType types = (UIUserNotificationTypeAlert | UIUserNotificationTypeBadge | UIUserNotificationTypeSound);
#pragma clang diagnostic pop
    
    NSSet *categories = [NSSet setWithObjects:category, nil];
    UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:types categories:categories];
    
    [[UIApplication sharedApplication] registerUserNotificationSettings:settings];
}

#pragma mark - Google Sign In

/*-(void) registerGoogleSignIn
{
    NSString* driveScope = @"https://mail.google.com/";
    NSArray* currentScopes = [GIDSignIn sharedInstance].scopes;
    [GIDSignIn sharedInstance].scopes = [currentScopes arrayByAddingObject:driveScope];
    
    NSError* configureError;
    [[GGLContext sharedInstance] configureWithError:&configureError];
    DDAssert(!configureError, @"Error configuring Google services: %@", configureError);
    
    [GIDSignIn sharedInstance].delegate = self;
}*/

# pragma mark - Springboard Shortcut Items (dynamic)

- (void)createItemsWithIcons
{
    UIApplicationShortcutIcon *loveIcon = [UIApplicationShortcutIcon iconWithTemplateImageName:@"favoris_off"];
    UIApplicationShortcutIcon *mailIcon = [UIApplicationShortcutIcon iconWithTemplateImageName:@"swipe_inbox"];
    UIApplicationShortcutIcon *searchIcon = [UIApplicationShortcutIcon iconWithTemplateImageName:@"simple_search_off"];
    UIApplicationShortcutIcon *composeIcon = [UIApplicationShortcutIcon iconWithTemplateImageName:@"simple_edit_off"];
    
    // create several (dynamic) shortcut items
    UIMutableApplicationShortcutItem *itemLove = [[UIMutableApplicationShortcutItem alloc]initWithType:@"com.fav" localizedTitle:NSLocalizedString(@"3d.favoris",@"Favoris") localizedSubtitle:nil icon:loveIcon userInfo:nil];
    
    UIMutableApplicationShortcutItem *itemMail = [[UIMutableApplicationShortcutItem alloc]initWithType:@"com.inbox" localizedTitle:NSLocalizedString(@"3d.inbox",@"Inbox") localizedSubtitle:nil icon:mailIcon userInfo:nil];
    
    UIMutableApplicationShortcutItem *item3 = [[UIMutableApplicationShortcutItem alloc]initWithType:@"com.search" localizedTitle:NSLocalizedString(@"3d.search",@"Search") localizedSubtitle:nil icon:searchIcon userInfo:nil];
    
    UIMutableApplicationShortcutItem *item4 = [[UIMutableApplicationShortcutItem alloc]initWithType:@"com.compose" localizedTitle:NSLocalizedString(@"3d.compose",@"Compose") localizedSubtitle:nil icon:composeIcon userInfo:nil];
    
    // add all items to an array
    NSArray *items = @[item4, item3, itemLove, itemMail];
    
    // add this array to the potentially existing static UIApplicationShortcutItems
    [UIApplication sharedApplication].shortcutItems = items;
}

- (void)application:(UIApplication *)application performActionForShortcutItem:(UIApplicationShortcutItem *)shortcutItem completionHandler:(void (^)(BOOL))completionHandler
{
    // react to shortcut item selections
    completionHandler([self handleShortcut:shortcutItem]);
    
}

-(BOOL) handleShortcut:(UIApplicationShortcutItem*)shortcutItem
{
    DDLogInfo(@"A shortcut item was pressed. It was %@.", shortcutItem.localizedTitle);
    
    if ([shortcutItem.type isEqualToString:@"com.fav"]) {
        CCMFolderType type = CCMFolderTypeFavoris;
        [[Accounts sharedInstance].currentAccount setCurrentFolder:type];
        NSNumber* encodedType = @(encodeFolderTypeWith(type));
        [[NSNotificationCenter defaultCenter] postNotificationName:kQUICK_ACTION_NOTIFICATION object:nil userInfo:@{kPRESENT_FOLDER_TYPE:encodedType}];
    }
    else if ([shortcutItem.type isEqualToString:@"com.inbox"]) {
        CCMFolderType type = CCMFolderTypeInbox;
        [[Accounts sharedInstance].currentAccount setCurrentFolder:type];
        NSNumber* encodedType = @(encodeFolderTypeWith(type));
        [[NSNotificationCenter defaultCenter] postNotificationName:kQUICK_ACTION_NOTIFICATION object:nil userInfo:@{kPRESENT_FOLDER_TYPE:encodedType}];
    }
    else if ([shortcutItem.type isEqualToString:@"com.search"]) {
        [self _search];
    }
    else if ([shortcutItem.type isEqualToString:@"com.compose"]) {
        [self _editMail];
    }
    
    return YES;
}

-(void) _editMail
{
    [[NSNotificationCenter defaultCenter] postNotificationName:kPRESENT_EDITMAIL_NOTIFICATION object:nil];
}

-(void) _search
{
    [[NSNotificationCenter defaultCenter] postNotificationName:kPRESENT_SEARCH_NOTIFICATION object:nil];
}


@end
