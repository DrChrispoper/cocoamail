//
//  AppSettings.m
//  CocoaMail
//
//  Created by Christopher Hockley on 20/01/2012.
//  Copyright (c) 2012 Christopher Hockley. All rights reserved.
//

#import "AppSettings.h"
#import <UIKit/UIDevice.h>
#import "Accounts.h"
#import "SyncManager.h"
#import "UserSettings.h"

#ifdef USING_INSTABUG
#import <Instabug/Instabug.h>
#endif


@implementation AppSettings

@synthesize badgeCount = _badgeCount;
@synthesize cache = _cache;
@synthesize canSyncOverData = _canSyncOverData;
@synthesize quickSwipe = _quickSwipe;
@synthesize draftCount = _draftCount;
@synthesize premiumPurchased = _premiumPurchased;
@synthesize globalDBVersion = _globalDBVersion;
@synthesize users = _users;





+(AppSettings*) getSingleton
{
    static dispatch_once_t once;
    static AppSettings* singleton = nil;
    
    dispatch_once(&once, ^{
        
        DDLogInfo(@"Creating Singleton");

        if (singleton == nil) {
            singleton = [[self alloc] init];
        }
    });
    
    return singleton;
}

-(id) init
{
    if (self = [super init]) {
        NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
        
        _badgeCount = [[defaults objectForKey:@"badgecount_preference"] integerValue];
        _cache = [defaults arrayForKey:@"cache"];
        _canSyncOverData = [defaults boolForKey:@"sync_over_data"];
        _quickSwipe = [[defaults objectForKey:@"quickswipe_preference"] unsignedIntegerValue];
        _draftCount = [[defaults objectForKey:@"drafts_preference"] unsignedIntValue];
        _premiumPurchased = [defaults boolForKey:@"premium"];
        _globalDBVersion = [defaults integerForKey:@"global_db_version"];
        
        _users = [[NSMutableArray alloc] init];
        
        NSFileManager *filemgr = [NSFileManager defaultManager];
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsDirectory = [paths objectAtIndex:0];
        NSString* inboxPath = [documentsDirectory stringByAppendingPathComponent:FOLDER_USER_SETTINGS_KEY];
        
        if (![filemgr fileExistsAtPath:inboxPath]) {
            [filemgr createDirectoryAtPath:inboxPath withIntermediateDirectories:NO attributes:nil error:nil];
        }
        
        NSArray *dirFiles = [filemgr contentsOfDirectoryAtPath:inboxPath error:nil];
        
        if (!dirFiles || dirFiles.count == 0) {
            UserSettings* user = [[UserSettings alloc] init];
            user.accountNum = 999;
            
            user.all = YES;
            user.deleted = YES;
            user.initials = @"ALL";
            user.color = [UIColor blackColor];
            user.username = NSLocalizedString(@"All accounts", @"All accounts");
            
            [_users addObject:user];
            
            DDLogInfo(@"Created \"All Files\" UserSettings");
        }
        else {
            for (NSString* fileName in dirFiles) {
                
                NSString* localPath = [inboxPath stringByAppendingPathComponent:fileName];
                
                UserSettings* user = [NSKeyedUnarchiver unarchiveObjectWithFile:localPath];
                //if ([user isDeleted]) {
                //    continue;
                //}
                
                if (!user) {
                    NSData* data = [[NSFileManager defaultManager] contentsAtPath:localPath];
                    user = [NSKeyedUnarchiver unarchiveObjectWithData:data]; // nil
                }
                
                DDAssert(user, @"User can't be nil, Filename:%@", fileName);
                
                [_users addObject:user];
                
            }
        }
        
        NSMutableString* accounts = [NSMutableString stringWithString:@""];
        
        for (int index = 0; index < _users.count; index++) {
            UserSettings* user = _users[index];
            
            if (user.isAll) {
                continue;
            }
            
            [accounts appendFormat:@"Identifier:%@\n", user.identifier];
            [accounts appendFormat:@"OAuth?%@\n", user.oAuth];
        }
        
        
#ifdef USING_INSTABUG
        NSString* userData = [NSString stringWithFormat:@"Users:\n%@",accounts];
        [Instabug setUserData:userData];
#endif
        
        //Default Settings
        if (_users.count == 1) {
            _badgeCount = 1;

            NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
            [defaults setObject:@(_badgeCount) forKey:@"badgecount_preference"];
        }
    }
    
    return self;
}

-(void) setBadgeCount:(NSInteger)y
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:@(y) forKey:@"badgecount_preference"];
    
    _badgeCount = y;
    
    [AppSettings setInboxUnread:[AppSettings inboxUnread:0] accountIndex:0];
}

-(NSInteger) badgeCount
{
    return _badgeCount;
}

-(void) setCache:(NSArray*)y
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:y forKey:@"cache"];
    
    _cache = y;
}

-(NSArray*) cache
{
    return _cache;
}

-(void) setSyncOverData:(BOOL)y
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:y forKey:@"sync_over_data"];
    
    _canSyncOverData = y;
}

-(BOOL) canSyncOverData
{
    return _canSyncOverData;
}

+(NSArray*) defaultColors
{
    return @[[[UIColor alloc] initWithRed:0.01f green:0.49f blue:1.f alpha:1.f],
             [[UIColor alloc] initWithRed:0.44f green:0.02f blue:1.f alpha:1.f],
             [[UIColor alloc] initWithRed:1.f green:0.01f blue:0.87f alpha:1.f],
             [[UIColor alloc] initWithRed:1.f green:0.07f blue:0.01f alpha:1.f],
             [[UIColor alloc] initWithRed:1.f green:0.49f blue:0.01f alpha:1.f],
             [[UIColor alloc] initWithRed:0.96f green:0.72f blue:0.02f alpha:1.f],
             [[UIColor alloc] initWithRed:0.07f green:0.71f blue:0.02f alpha:1.f]];
}

-(QuickSwipeType) quickSwipe
{
    return _quickSwipe;
}

-(void) setQuickSwipe:(QuickSwipeType)quickswipetype
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:@(quickswipetype) forKey:@"quickswipe_preference"];
    
    _quickSwipe = quickswipetype;
}

-(uint32_t) draftCount
{
    _draftCount++;
    
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:@(_draftCount) forKey:@"drafts_preference"];
    
    return _draftCount;
}

-(BOOL) premiumPurchased
{
    return  _premiumPurchased;
}

-(void) setPremiumPurchased:(BOOL)value
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults]; 
	[defaults setObject:@(value) forKey:@"premium"];
    
    _premiumPurchased = YES;
}

-(NSInteger) globalDBVersion
{
    return _globalDBVersion;
}

-(void) setGlobalDBVersion:(NSInteger)version
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults]; 
	[defaults setInteger:version forKey:@"global_db_version"];
	
    _globalDBVersion = version;
}

+(NSInteger) accountIndexForEmail:(NSString*)email
{
    NSInteger index = 0;
    
    for (UserSettings* user in [[AppSettings getSingleton] users]) {
        if (!user.isDeleted) {
        if ([user.username isEqualToString:email]) {
            return index;
        }
        index++;
        }
    }
    
    return -1;
}

//NumAccout:1 - 2 - 4 If 3 is deleted
/*+(NSInteger) numAccountForIndex:(NSInteger)accountIndex
{
    DDAssert(accountIndex < [AppSettings numActiveAccounts], @"Index:%li is incorrect only %li active account",(long)accountIndex,(long)[AppSettings numActiveAccounts]);

    for (UserSettings* user in [[AppSettings getSingleton] users]) {
        if (user.accountIndex == accountIndex) {
            return user.accountNum;
        }
    }
    
    return -1;
}*/

//numIndex:0 - 1 - 2 ...
+(NSUInteger) indexForAccountNum:(NSInteger)accountNum
{
    NSUInteger index = 0;
    
    for (UserSettings* user in [[AppSettings getSingleton] users]) {
        if (!user.isDeleted) {
            if (user.accountNum == accountNum) {
                return index;
            }
        
            index++;
        }
    }
    
    return -1;
}

+(NSInteger) numActiveAccounts
{
    NSInteger num = 0;
    
    for (UserSettings* user in [[AppSettings getSingleton] users]) {
        if (!user.isDeleted) {
            num++;
        }
    }
    
    return num;
}

+(NSMutableArray*) activeUsers
{
    NSMutableArray* acts = [[NSMutableArray alloc] init];
    
    for (UserSettings* user in [[AppSettings getSingleton] users]) {
        if (!user.isDeleted) {
            [acts addObject:user];
        }
    }
    
    return acts;
}

-(UserSettings*) createNewUser
{
    NSInteger accountNum = 1;
    
    for (UserSettings* user in _users) {
        if (user.isAll) {
            continue;  // There is no account for the User record
        }
        
        accountNum++;
    }
    
    UserSettings* user = [[UserSettings alloc] init];
    user.accountNum = accountNum;
    
    DDAssert(user, @"UserSettings must not be nil.");
    
    [_users insertObject:user atIndex:_users.count-1];
    
    [user setImportantFolderNum:-1 forBaseFolder:FolderTypeInbox];
    [user setImportantFolderNum:-1 forBaseFolder:FolderTypeFavoris];
    [user setImportantFolderNum:-1 forBaseFolder:FolderTypeSent];
    [user setImportantFolderNum:-1 forBaseFolder:FolderTypeDrafts];
    [user setImportantFolderNum:-1 forBaseFolder:FolderTypeAll];
    [user setImportantFolderNum:-1 forBaseFolder:FolderTypeDeleted];
    [user setImportantFolderNum:-1 forBaseFolder:FolderTypeSpam];

    DDLogInfo(@"Created New User UserSettings: %@",[user description]);

    return user;
}


+(UserSettings*) userWithIndex:(NSInteger)accountIndex;
{
    if (accountIndex < [AppSettings activeUsers].count) {
        return [AppSettings activeUsers][accountIndex];
    }
    
    return nil;
}

+(UserSettings*) userWithNum:(NSInteger)accountNum
{
    for (UserSettings* user in [[AppSettings getSingleton] users]) {
        if (user.accountNum == accountNum) {
            return user;
        }
    }
    
    return nil;
}

+(UserSettings*) userWithEmail:(NSString*)email
{
    for (UserSettings* user in [[AppSettings getSingleton] users]) {
        if ([user.username isEqualToString:email]) {
            return user;
        }
    }
    
    return nil;
}

+(MCOIMAPSession*) imapSession:(UserSettings*)user
{
    MCOIMAPSession* imapSession = [[MCOIMAPSession alloc] init];

    imapSession.hostname = user.imapHostname;
    imapSession.port = (unsigned int)user.imapPort;
    imapSession.username = user.username;
    imapSession.password = user.password;
    imapSession.connectionType = user.imapConnectionType;

    if ([user isUsingOAuth]) {
        imapSession.OAuth2Token = [user oAuth];
        imapSession.authType = MCOAuthTypeXOAuth2;
        imapSession.connectionType = MCOConnectionTypeTLS;
    }
    
    imapSession.maximumConnections = 6;
        
    return imapSession;
}

#warning method below not called from anywhere?
+(MCOIMAPSession*) createImapSession:(NSInteger)accountIndex
{
    UserSettings* user = [AppSettings userWithIndex:accountIndex];
    return [AppSettings imapSession:user];
}

+(void) setNotifications:(BOOL)y accountNum:(NSInteger)accountNum
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    
    [defaults setObject:@(y) forKey:[NSString stringWithFormat:@"notifications_preference_%li", (long)accountNum]];
}

+(BOOL) notifications:(NSInteger)accountNum
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    
    return [defaults boolForKey:[NSString stringWithFormat:@"notifications_preference_%li", (long)accountNum]];
}

+(NSInteger) defaultAccountIndex
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSNumber* activeAcctPreference = [defaults objectForKey:[NSString stringWithFormat:@"dAccountNum"]];
    NSInteger accountNum = [activeAcctPreference integerValue];
    
    UserSettings* user = [AppSettings userWithNum:accountNum];
    
    return user.accountIndex;
    
    /*if (accountNum != 999) {
        return [AppSettings indexForAccountNum:accountNum];
    }
    else {
        return [AppSettings numActiveAccounts];
    }*/
}

+(void) setDefaultAccountNum:(NSInteger)accountNum
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:@(accountNum) forKey:[NSString stringWithFormat:@"dAccountNum"]];
}

+(NSInteger) lastAccountIndex
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSNumber* activeAcctPreference = [defaults objectForKey:[NSString stringWithFormat:@"lastAccountNum"]];
    NSInteger num = [activeAcctPreference integerValue];
    
    if ([AppSettings numActiveAccounts] != 0 && num != 999) {
        NSInteger idx = [AppSettings indexForAccountNum:num];
        
        if (idx < 0 || idx >= [AppSettings numActiveAccounts]) {
            [AppSettings setLastAccountIndex:0];
            return 0;
        }
        
        return idx;
    }
    else {
        return [AppSettings numActiveAccounts];
    }
}

+(void) setLastAccountIndex:(NSInteger)accountIndex
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSInteger num = (accountIndex == [AppSettings numActiveAccounts])?999:[AppSettings userWithIndex:accountIndex].accountNum;
    [defaults setObject:@(num) forKey:[NSString stringWithFormat:@"lastAccountNum"]];
}

+(NSNumber*) lastFolderIndex
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSNumber* folderNum = [defaults objectForKey:[NSString stringWithFormat:@"lastFolder"]];
    
    return folderNum;
}

+(void) setLastFolderIndex:(NSNumber*)folderNum
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:folderNum forKey:[NSString stringWithFormat:@"lastFolder"]];
}

+(void) setSettingsWithAccountVal:(MCOAccountValidator*)accountVal user:(UserSettings*)user
{
    user.username = accountVal.username;
   
    if (accountVal.OAuth2Token) {
        [user setOAuth:accountVal.OAuth2Token];
        [user setPassword:@""];
    }
    else {
        [user setOAuth:@""];
        [user setPassword:accountVal.password];
    }
    
    user.identifier = accountVal.identifier;

    user.imapHostname = accountVal.imapServer.hostname;
    user.imapPort = accountVal.imapServer.port;
    user.imapConnectionType = accountVal.imapServer.connectionType;
    
    user.smtpHostname = accountVal.smtpServer.hostname;
    user.smtpPort = accountVal.smtpServer.port;
    user.smtpConnectionType = accountVal.smtpServer.connectionType;
}

+(NSInteger) inboxUnread:(NSInteger)accountIndex
{
    NSNumber* str =  [[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat:@"inboxUnread_%li", (long)[AppSettings userWithIndex:accountIndex].accountNum]];
    return [str integerValue];
}

+(void) setInboxUnread:(NSInteger)value accountIndex:(NSInteger)accountIndex
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:@(value) forKey:[NSString stringWithFormat:@"inboxUnread_%li", (long)[AppSettings userWithIndex:accountIndex].accountNum]];
    
    
    int badge = 0;
    
    if ([[AppSettings getSingleton] badgeCount] == 1) {
        for (int index = 0; index < [AppSettings numActiveAccounts]; index++) {
            badge += [AppSettings inboxUnread:index];
        }
    }
    DDLogDebug(@"Setting Inbox Unread to %ld",(long)badge);
    
    [UIApplication sharedApplication].applicationIconBadgeNumber = badge;
}

@end
