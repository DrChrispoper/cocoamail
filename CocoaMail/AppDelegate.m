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
#import "Flurry.h"
#import "UserSettings.h"
#import "Draft.h"
#import <CocoaLumberjack/CocoaLumberjack.h>
#import "CCMDDLogFormatter.h"

//#define USING_XCODECOLORS        // Define this to use XCodeColors (no longer supported in XCode 8)

#ifdef USING_INSTABUG
#import "asl.h"
#import <Instabug/Instabug.h>
#import <Instabug-CocoaLumberjack/DDInstabugLogger.h>

// Required to get logging into Instabug in iOS 10+
//inline void NSLog(NSString *format, ...) {
//    va_list arg_list;
//    va_start(arg_list, format);
//    aslmsg msg = asl_new(ASL_TYPE_MSG);
//    asl_set(msg, ASL_KEY_READ_UID, "-1");
//    NSString *formattedString = [[NSString alloc] initWithFormat:format arguments:arg_list];
//    asl_log(NULL, msg, (ASL_LEVEL_ERR), "%s", [formattedString UTF8String]);
//    asl_free(msg);
//    va_end(arg_list);
//}

#endif  // USING_INSTABUG

@implementation AppDelegate

-(BOOL) application:(UIApplication*)application willFinishLaunchingWithOptions:(NSDictionary*)launchOptions
{
    BOOL shouldPerformAdditionalDelegateHandling = TRUE;
    
#ifdef USING_INSTABUG
    [Instabug startWithToken:@"745ee58bde267456dafb4be700be1924" invocationEvent:IBGInvocationEventScreenshot];
    [Instabug setIntroMessageEnabled:NO];
#endif
    
    // Initialize CocoaLumberjack logging system
    [self _initCocoaLumberjack ];
    
    // Initialize Flurry analytics
    [Flurry startSession:@"D67NTWY4V6RW5RFVMRGK"];
    
    // First, create an action
    UIMutableUserNotificationAction *acceptAction = [self createAction];
    
    // Second, create a category and tie those actions to it (only the one action for now)
    UIMutableUserNotificationCategory *inviteCategory = [self createCategory:@[acceptAction]];
    
    application.applicationSupportsShakeToEdit = YES;
    
    UIApplicationShortcutItem* shortcutItem = launchOptions[UIApplicationLaunchOptionsShortcutItemKey];
    
    if (shortcutItem) {
        self.launchedShortcutItem = shortcutItem;
        
        // This will block "performActionForShortcutItem:completionHandler" from being called.
        shouldPerformAdditionalDelegateHandling = FALSE;
    }
    
    [self createItemsWithIcons];
    
    // Third, register those settings with our new notification category
    [self registerSettings:inviteCategory];
    
    [application setMinimumBackgroundFetchInterval:UIApplicationBackgroundFetchIntervalMinimum];
    
    DBSession* dbSession = [[DBSession alloc] initWithAppKey:@"hqbpjnlap118jqh" appSecret:@"mhdjbn703ama4wf" root:kDBRootDropbox];
    [DBSession setSharedSession:dbSession];
    
    [Accounts sharedInstance];  // Allocate the shared instance
    [[Accounts sharedInstance] getDrafts];
    
    //[self registerGoogleSignIn];
    
    return shouldPerformAdditionalDelegateHandling;
}

/**********************************/
/*** Initialize CocoaLumberjack ***/
/**********************************/
-(void) _initCocoaLumberjack
{
#ifdef USING_XCODECOLORS
    // Enable XcodeColors
    setenv("XcodeColors", "YES", 0);
#endif
    
//    // Send debug statements to the System Log (Console.app)
//    [DDLog addLogger:[DDASLLogger sharedInstance]];

    
#ifdef USING_INSTABUG
    // This will log CocoaLumberjack into Instabug
    DDInstabugLogger *ibgLogger = [[DDInstabugLogger alloc] init];
    if ( ibgLogger ) {
        
        ibgLogger.logFormatter = [[CCMDDLogFormatter alloc] init];
        
        [DDLog addLogger:ibgLogger];
    }
#else // not using Instabug
    
    xyzzy
    
    // Send debug statements to the Xcode console (uses XcodeColor)
    DDTTYLogger *ttyLogger = [DDTTYLogger sharedInstance];
    if (ttyLogger) {
#ifdef USING_XCODECOLORS
        [ttyLogger setForegroundColor:[UIColor redColor] backgroundColor:nil forFlag:DDLogFlagError];
        [ttyLogger setForegroundColor:[UIColor yellowColor] backgroundColor:nil forFlag:DDLogFlagWarning];
        [ttyLogger setForegroundColor:[UIColor greenColor] backgroundColor:nil forFlag:DDLogFlagInfo];
        [ttyLogger setForegroundColor:[UIColor cyanColor] backgroundColor:nil forFlag:DDLogFlagDebug];
        [ttyLogger setColorsEnabled:YES]; // Enables XCodeColors XCode plugin, if available
#endif
        ttyLogger.logFormatter = [[CCMDDLogFormatter alloc] init];
        
        [DDLog addLogger:ttyLogger]; // Send debug statements to the XCode Console, if available
    }

#endif // not using Instabug

    
    // Send debug info to log files
//    DDFileLogger *fileLogger = [[DDFileLogger alloc] init];     // File Logger
//    fileLogger.rollingFrequency = 60 * 60 * 24;                 // 24 hour rolling
//    fileLogger.logFileManager.maximumNumberOfLogFiles = 7;
//    [DDLog addLogger:fileLogger];
//    
//    DDLogFileInfo *lfi = [fileLogger currentLogFileInfo];
//    DDLogInfo(@"*********");
//    DDLogInfo(@"LOG PATH: \"%@\"",[lfi filePath]);
//    DDLogInfo(@"*********");
   
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

- (void)application:(UIApplication *)application didReceiveLocalNotification:(UILocalNotification *)notification
{
    for (UserSettings* user in [AppSettings getSingleton].users) {
        if (user.isDeleted) {
            continue;
        }
    //for (NSInteger accountIndex = 0 ; accountIndex < [AppSettings numActiveAccounts];accountIndex++) {
        [[ImapSync sharedServices:user] saveCachedData];
    }
    
    if (notification && application.applicationState == 1) {
        DDLogInfo(@"Notification Body: %@", notification.alertBody);
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
    if ([AppSettings numActiveAccounts] > 0) {
        for (UserSettings* user in [AppSettings getSingleton].users) {
            if (user.isDeleted) {
                continue;
            }
        //for (NSInteger accountIndex = 0 ; accountIndex < [AppSettings numActiveAccounts];accountIndex++) {
            [[ImapSync sharedServices:user] saveCachedData];
        }
        
        [[AppSettings getSingleton] setCache:@[]];
        
        if (self.launchedShortcutItem) {
            UIApplicationShortcutItem* shortCut = self.launchedShortcutItem ;
            [self handleShortcut:shortCut];
            
            self.launchedShortcutItem = nil;
        }
        else if (self.launchedNotification) {
            UILocalNotification* notification = self.launchedNotification;
            
            NSInteger index = [[notification.userInfo objectForKey:@"cIndexIndex"] integerValue];
            NSInteger accountNum = [[notification.userInfo objectForKey:@"cIndexAccountNum"] integerValue];
            UserSettings* user = [AppSettings userWithNum:accountNum];
            
            ConversationIndex *cIndex = [ConversationIndex initWithIndex:index user:user];
            Conversation* conversation = [cIndex.user.linkedAccount getConversationForIndex:cIndex.index];
            
            [conversation foldersType];
            
            DDLogInfo(@"Opening email:%@", [conversation firstMail].subject);
            DDLogInfo(@"Index: %ld",(long)cIndex.index);
            
            Accounts* A = [Accounts sharedInstance];

            A.currentAccountIdx = cIndex.user.accountIndex;
            [[A currentAccount] connect];
            
            [ViewController refreshCocoaButton];
            
            [[NSNotificationCenter defaultCenter] postNotificationName:kACCOUNT_CHANGED_NOTIFICATION object:nil];
            
            [[NSNotificationCenter defaultCenter] postNotificationName:kPRESENT_CONVERSATION_NOTIFICATION
                                                                object:nil
                                                              userInfo:@{kPRESENT_CONVERSATION_KEY:conversation}];
            

            
            self.launchedNotification = nil;
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
        DDLogInfo(@"Delete Cached Email");
        
        NSInteger index = [[notification.userInfo objectForKey:@"cIndexIndex"] integerValue];
        NSInteger accountNum = [[notification.userInfo objectForKey:@"cIndexAccountNum"] integerValue];
        UserSettings* user = [AppSettings userWithNum:accountNum];
        
        ConversationIndex *convIndex = [ConversationIndex initWithIndex:index user:user];
        
        Conversation* conversation = [[Accounts sharedInstance] conversationForCI:convIndex];
        
        DDLogInfo(@"Email in account:%ld", (long)[conversation user].accountNum);

        [convIndex.user.linkedAccount moveConversation:conversation from:inboxFolderType() to:FolderTypeWith(FolderTypeDeleted, 0) updateUI:YES];
        
        NSString* toFolderString = [convIndex.user.linkedAccount systemFolderNames][FolderTypeDeleted];
        
        NSDictionary *articleParams = [NSDictionary dictionaryWithObjectsAndKeys:
                                       @"INBOX", @"from_Folder",
                                       toFolderString, @"to_Folder",
                                       @"lock_screen", @"action_Location"
                                       ,nil];
        
        [Flurry logEvent:@"Conversation Moved" withParameters:articleParams];
    }
    
    // Call this when you're finished
    completionHandler();
}

-(BOOL) application:(UIApplication*)application openURL:(NSURL*)url sourceApplication:(NSString*)sourceApplication annotation:(id)annotation
{
    /*if ([[GIDSignIn sharedInstance] handleURL:url sourceApplication:sourceApplication annotation:annotation]) {
        return YES;
    }*/
    
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
                    CCMLog(@"connection error");
                } completed:^{}];
            }
        }
    }
    }
    else {
        CCMLog(@"Erorr signing in %@",error.localizedDescription);
    }
}*/

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

/*-(void) registerGoogleSignIn
{
    NSString* driveScope = @"https://mail.google.com/";
    NSArray* currentScopes = [GIDSignIn sharedInstance].scopes;
    [GIDSignIn sharedInstance].scopes = [currentScopes arrayByAddingObject:driveScope];
    
    NSError* configureError;
    [[GGLContext sharedInstance] configureWithError:&configureError];
    NSAssert(!configureError, @"Error configuring Google services: %@", configureError);
    
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
