//
//  AppSettings.m
//  CocoaMail
//
//  Created by Christopher Hockley on 20/01/2012.
//  Copyright (c) 2012 Christopher Hockley. All rights reserved.
//

#import "AppSettings.h"
#import "PDKeychainBindings.h"
#import <UIKit/UIDevice.h>

@implementation AppSettings

+ (NSString*)appID
{
	return [[NSBundle mainBundle] infoDictionary] [@"CFBundleIdentifier"];
}

+ (NSString*)version
{
	return [[NSBundle mainBundle] infoDictionary] [@"CFBundleVersion"];
}

+ (NSString*)dataInitVersion
{
	// version of the software at which the data store was initialized
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults]; 
	return  [defaults stringForKey:@"app_data_init_version"];
}

+ (void)setDataInitVersion
{
	// version of the software at which the data store was initialized
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults]; 
	[defaults setObject:[AppSettings version] forKey:@"app_data_init_version"];
	[NSUserDefaults resetStandardUserDefaults];
}

+ (NSInteger)datastoreVersion
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	return [defaults integerForKey:@"datastore_version"];
}

+ (void)setDatastoreVersion:(NSInteger)value
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults]; 
	[defaults setInteger:value forKey:[NSString stringWithFormat:@"datastore_version"]];
	[NSUserDefaults resetStandardUserDefaults];
}


+ (NSString *)systemVersion
{
	NSString* systemVersion = [UIDevice currentDevice].systemVersion;
	return systemVersion;
}


+ (NSString *)model
{
	NSString* model = [UIDevice currentDevice].model;
	return model;
}


+ (NSString *)udid
{
	NSString* udid = [UIDevice currentDevice].identifierForVendor.UUIDString;
	return udid;
}

+ (BOOL)firstSync
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults]; 
	return ([defaults boolForKey:@"app_first_sync"] == NO); //stores the opposite!
}

+ (void)setFirstSync:(BOOL)firstSync
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults]; 
	[defaults setBool:!firstSync forKey:@"app_first_sync"];
	[defaults synchronize];
}

+ (BOOL) firstInit
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    BOOL resetPreference = [defaults boolForKey:@"init_preference"];
    return resetPreference;
}

+ (void) setFirstInit:(BOOL)value
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:value forKey:@"init_preference"];
    [NSUserDefaults resetStandardUserDefaults];
}

+ (void) initDefaultValues
{
    [AppSettings setNumAccounts:0];
    [AppSettings setFirstInit:TRUE];
}

+ (BOOL)reset
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults]; 
	BOOL resetPreference = [defaults boolForKey:@"reset_preference"];
	return resetPreference;
}

+ (void)setReset:(BOOL)value
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults]; 
	[defaults setBool:value forKey:@"reset_preference"];
	[NSUserDefaults resetStandardUserDefaults];
}

+ (void)setBadgeCount:(NSInteger)y
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setInteger:y forKey:@"badgecount_preference"];
    [defaults synchronize];
}

+ (NSInteger)badgeCount
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	return [defaults integerForKey:@"badgecount_preference"];
}

+ (void)setNotifications:(BOOL)y
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:@(y) forKey:@"notifications_preference"];
    [defaults synchronize];
}

+ (BOOL)notifications
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	return [defaults boolForKey:@"notifications_preference"];
}

+ (void)firstFullSyncDone
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:@(YES) forKey:[NSString stringWithFormat:@"first_sync_%lu", (long)[AppSettings activeAccount]]];
    [defaults synchronize];
}

+ (BOOL)isFirstFullSyncDone
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    return [defaults boolForKey:[NSString stringWithFormat:@"first_sync_%lu", (long)[AppSettings activeAccount]]];
}

+ (BOOL)featurePurchased:(NSString *)productIdentifier
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults]; 
	return  [defaults boolForKey:@"premium"];
}

+ (void)setFeaturePurchased:(NSString *)productIdentifier
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults]; 
	[defaults setObject:@YES forKey:@"premium"];
	[defaults synchronize];
}

+ (NSInteger)globalDBVersion
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults]; 
	NSInteger pref = [defaults integerForKey:@"global_db_version"];
	return pref;
}

+ (void)setGlobalDBVersion:(NSInteger)version
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults]; 
	[defaults setInteger:version forKey:@"global_db_version"];
	[NSUserDefaults resetStandardUserDefaults];
}

+(NSInteger)numAccountForEmail:(NSString*)email
{
    NSInteger index = [AppSettings numActiveAccounts]-1;
    
    while (index != -1) {
        NSInteger numAccount = [AppSettings numAccountForIndex:index];
        
        if ([[AppSettings username:numAccount] isEqualToString:email])
            return numAccount;
        else
            index--;
    }
    
    return -1;
}

//NumAccout:1 - 2 - 4 If 3 is deleted
+ (NSInteger)numAccountForIndex:(NSInteger)index
{
    NSInteger i = 0;
    
    if(index == [AppSettings numActiveAccounts]) return -1;
    
    while (index != -1) {
        if (![AppSettings accountDeleted:++i])index--;
    }
    
	return i;
}

//numIndex:0 - 1 - 2 ...
+ (NSInteger)numIndexForAccount:(NSInteger)accountNum
{
    NSInteger index = accountNum;
    NSInteger i = -1;
    
    while (index != 0) {
        if (![AppSettings accountDeleted:++i])index--;
    }
    
    return i;
}

+ (NSInteger)numActiveAccounts
{
    return [AppSettings numAccounts]-[AppSettings numDelAccounts];
}

+ (NSInteger)numAccounts
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults]; 
	NSInteger numAccts = [defaults integerForKey:@"num_accounts"];
	return numAccts;
}

+ (void)setNumAccounts:(NSInteger)value
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults]; 
	[defaults setInteger:value forKey:@"num_accounts"];
	[defaults synchronize];
}

+ (NSInteger)numDelAccounts
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	return [defaults integerForKey:@"num_del_accounts"];
}

+ (void)setNumDelAccounts:(NSInteger)value
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setInteger:value forKey:@"num_del_accounts"];
	[defaults synchronize];
}

+ (BOOL)accountDeleted:(NSInteger)accountNum
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	return [defaults boolForKey:[NSString stringWithFormat:@"account_deleted_%lu", (long)accountNum]];
}

+ (void)setAccountDeleted:(BOOL)value accountNum:(NSInteger)accountNum
{
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults]; 
	[defaults setBool:value forKey:[NSString stringWithFormat:@"account_deleted_%lu", (long)accountNum]];
	[defaults synchronize];
    if(value)[self setNumDelAccounts:[AppSettings numDelAccounts]+1];
}

+ (NSString *)identifier{
    return [self identifier:[self activeAccount]];
}

+ (NSString *)identifier:(NSInteger)accountNum {
	NSString* str =  [[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat:@"identifier_%lu", (long)accountNum]];
    return str;
}

+ (void)setIdentifier:(NSString *)value accountNum:(NSInteger)accountNum {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults]; 
	[defaults setObject:value forKey:[NSString stringWithFormat:@"identifier_%lu", (long)accountNum]];
	[defaults synchronize];
}

+ (NSString *)username{
    return [self username:[AppSettings activeAccount]];
}

+ (NSString *)username:(NSInteger)accountNum {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSString* usernamePreference = [defaults stringForKey:[NSString stringWithFormat:@"username_%lu", (long)accountNum]];
	return usernamePreference;
}

+ (void)setUsername:(NSString *)y accountNum:(NSInteger)accountNum {
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults]; 
	[defaults setObject:y forKey:[NSString stringWithFormat:@"username_%lu", (long)accountNum]];
	[defaults synchronize];
}

+ (NSString *)password
{
    return [self password:[self activeAccount]];
}

+ (NSString *)password:(NSInteger)accountNum
{
	NSString* str =  [[PDKeychainBindings sharedKeychainBindings] objectForKey:[NSString stringWithFormat: @"P%lu", (long)accountNum]];
    return str;
}

+ (void)setPassword:(NSString *)y accountNum:(NSInteger)accountNum
{
    PDKeychainBindings *bindings=[PDKeychainBindings sharedKeychainBindings];
    [bindings setObject:y forKey:[NSString stringWithFormat: @"P%lu", (long)accountNum] accessibleAttribute:kSecAttrAccessibleAfterFirstUnlock];
}

+ (MCOIMAPSession*)imapSession:(NSInteger)accountNum
{
    MCOIMAPSession *imapSession = [[MCOIMAPSession alloc] init];
    
    imapSession.hostname = [AppSettings imapServer:accountNum];
    imapSession.port = [AppSettings imapPort:accountNum];
    imapSession.username = [AppSettings username:accountNum];
    imapSession.password = [AppSettings password:accountNum];
    if ([AppSettings isUsingOAuth:accountNum]) {
        imapSession.OAuth2Token = [AppSettings oAuth:accountNum];
        imapSession.authType = MCOAuthTypeXOAuth2;
    }
    imapSession.connectionType = [AppSettings imapEnc:accountNum];
    
    return imapSession;
}

+ (NSString *)imapServer:(NSInteger)accountNum
{
    return [[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat: @"IMAPServ%lu", (long)accountNum]];
}

+ (void)setImapServer:(NSString *)y accountNum:(NSInteger)accountNum
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:y forKey:[NSString stringWithFormat:@"IMAPServ%lu", (long)accountNum]];
	[defaults synchronize];
}

+ (unsigned int)imapPort:(NSInteger)accountNum
{
    return (unsigned int)[[NSUserDefaults standardUserDefaults] integerForKey:[NSString stringWithFormat: @"IMAPPort_%lu", (long)accountNum]];
}

+ (void)setImapPort:(NSInteger)y accountNum:(NSInteger)accountNum
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:@(y) forKey:[NSString stringWithFormat:@"IMAPPort_%lu", (long)accountNum]];
	[defaults synchronize];
}

+ (NSInteger)imapEnc:(NSInteger)accountNum{
    return [[NSUserDefaults standardUserDefaults] integerForKey:[NSString stringWithFormat:@"IMAPEnc_%lu", (long)accountNum]];
}

+ (void)setImapEnc:(NSInteger)y accountNum:(NSInteger)accountNum
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:@(y) forKey:[NSString stringWithFormat:@"IMAPEnc_%lu", (long)accountNum]];
	[defaults synchronize];
}

+ (NSString *)smtpServer:(NSInteger)accountNum
{
    return [[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat: @"SMTPServ_%lu", (long)accountNum]];

}

+ (void)setSmtpServer:(NSString *)y accountNum:(NSInteger)accountNum
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:y forKey:[NSString stringWithFormat:@"SMTPServ%lu", (long)accountNum]];
	[defaults synchronize];
}

+ (NSInteger)smtpPort:(NSInteger)accountNum
{
    return [[NSUserDefaults standardUserDefaults] integerForKey:[NSString stringWithFormat: @"SMTPPort_%lu",(long)accountNum]];

}

+ (void)setSmtpPort:(NSInteger)y accountNum:(NSInteger)accountNum
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:@(y) forKey:[NSString stringWithFormat:@"SMTPPort_%lu", (long)accountNum]];
	[defaults synchronize];
}

+ (NSInteger)smtpEnc:(NSInteger)accountNum
{
    return [[NSUserDefaults standardUserDefaults] integerForKey:[NSString stringWithFormat:@"SMTPEnc_%lu", (long)accountNum]];
}

+ (void)setSmtpEnc:(NSInteger)y accountNum:(NSInteger)accountNum{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:@(y) forKey:[NSString stringWithFormat:@"SMTPEnc_%lu", (long)accountNum]];
	[defaults synchronize];
}
+ (NSString *)signature:(NSInteger)accountNum{
    return [[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat: @"Signature_%lu", (long)accountNum]];
}

+ (void)setSignature:(NSString *)y accountNum:(NSInteger)accountNum
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:y forKey:[NSString stringWithFormat:@"Signature_%lu", (long)accountNum]];
	[defaults synchronize];
}

+ (NSString*)name:(NSInteger)accountNum
{
    return [[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat: @"Name_%lu", (long)accountNum]];

}

+ (void)setName:(NSString *)y accountNum:(NSInteger)accountNum
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:y forKey:[NSString stringWithFormat:@"Name_%lu", (long)accountNum]];
	[defaults synchronize];
}

+ (NSString *)initials:(NSInteger)accountNum
{
    if (accountNum == -1) return @"ALL";
    return [[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat: @"Initials_%lu", (long)accountNum]];
}

+ (void)setInitials:(NSString *)y accountNum:(NSInteger)accountNum
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:y forKey:[NSString stringWithFormat:@"Initials_%lu", (long)accountNum]];
	[defaults synchronize];
}

+(NSArray*)defaultColors
{
    return @[[UIColor colorWithRed:0.01f green:0.49f blue:1.f alpha:1.f],
             [UIColor colorWithRed:0.44f green:0.02f blue:1.f alpha:1.f],
             [UIColor colorWithRed:1.f green:0.01f blue:0.87f alpha:1.f],
             [UIColor colorWithRed:1.f green:0.07f blue:0.01f alpha:1.f],
             [UIColor colorWithRed:1.f green:0.49f blue:0.01f alpha:1.f],
             [UIColor colorWithRed:0.96f green:0.72f blue:0.02f alpha:1.f],
             [UIColor colorWithRed:0.07f green:0.71f blue:0.02f alpha:1.f]];
}

+ (UIColor *)color:(NSInteger)accountNum
{
    if (accountNum == -1) return [UIColor blackColor];
    UIColor* color = [UIColor colorWithCIColor:[CIColor colorWithString:[[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat: @"Color_%lu", (long)accountNum]]]];
    return color;
}

+ (void)setColor:(UIColor *)y accountNum:(NSInteger)accountNum
{
    CGColorRef colorRef = y.CGColor;
    NSString *colorString = [CIColor colorWithCGColor:colorRef].stringRepresentation;
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:colorString forKey:[NSString stringWithFormat:@"Color_%lu", (long)accountNum]];
	[defaults synchronize];
}

+ (BOOL)isUsingOAuth
{
    return [self isUsingOAuth:[self activeAccount]];
}

+ (BOOL)isUsingOAuth:(NSInteger)accountNum
{
    NSString * token = [AppSettings oAuth:accountNum];
	return  ![token isEqualToString:@""];
}

+ (NSString *)oAuth:(NSInteger)accountNum
{
	return [[PDKeychainBindings sharedKeychainBindings] stringForKey:[NSString stringWithFormat: @"T%lu", (long)accountNum]];
}

+ (void)setOAuth:(NSString *)y accountNum:(NSInteger)accountNum
{
    PDKeychainBindings *bindings = [PDKeychainBindings sharedKeychainBindings];
    [bindings setString:y forKey:[NSString stringWithFormat: @"T%lu", (long)accountNum] accessibleAttribute:kSecAttrAccessibleAfterFirstUnlock];
}

+ (NSInteger)importantFolderNumForAcct:(NSInteger)account forBaseFolder:(BaseFolderType)baseFolder
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSArray* importantFolderPreference = [defaults objectForKey:[NSString stringWithFormat:@"iFolder_%lu", (long)account]];
	return [importantFolderPreference[baseFolder] integerValue];
}

+ (void)setImportantFolderNum:(NSInteger)folder forBaseFolder:(BaseFolderType)baseFolder forAccount:(NSInteger)account
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray* newfolders = [[NSMutableArray alloc] initWithArray:[defaults objectForKey:[NSString stringWithFormat:@"iFolder_%lu", (long)account]]];
    
    if (newfolders.count == 0) {
        newfolders = [[NSMutableArray alloc] initWithObjects:@"",@"",@"",@"",@"",@"",nil];
    }
    
    newfolders[baseFolder] = @(folder);
    
	[defaults setObject:newfolders forKey:[NSString stringWithFormat:@"iFolder_%lu", (long)account]];
	[defaults synchronize];
}

+ (FolderType)typeOfFolder:(NSInteger)folder forAccount:(NSInteger)account
{
    if(account == -1){
        return FolderTypeWith(folder, 0);
    }
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray* importantFolderPreference = [defaults objectForKey:[NSString stringWithFormat:@"iFolder_%lu", (long)account]];
    
    for (int idx = importantFolderPreference.count-1 ; idx >= 0 ; idx--) {
        if (folder == [importantFolderPreference[idx] integerValue]) {
            return FolderTypeWith(idx, 0);
        }
    }
    
    NSArray* nonImportantFolders = [AppSettings allNonImportantFoldersName:account];
    NSString* folderName = [AppSettings folderName:folder forAccount:account];
    
    for (int idx = 0;idx<nonImportantFolders.count;idx++) {
        if ([folderName isEqualToString:nonImportantFolders[idx]]) {
            return FolderTypeWith(FolderTypeUser, idx);
        }
    }
    
    return FolderTypeWith(FolderTypeAll, 0);
}

+ (NSString *)folderName:(NSInteger)folder forAccount:(NSInteger)account
{
    if (account == -1) return @"INBOX";
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSArray* allFoldersPreference = [defaults objectForKey:[NSString stringWithFormat:@"allFolders_%lu", (long)account]];
	return allFoldersPreference[folder];
}

+(NSInteger)numFolderWithFolder:(FolderType)folder forAccount:(NSInteger)account
{
    NSArray* folderNames = [AppSettings allFoldersName:account];
    NSString* folderName;
    if (folder.type == FolderTypeUser) {
        folderName = [[Accounts sharedInstance] currentAccount].userFolders[folder.idx][0];
        for (int index = 0; index < [folderNames count]; index++) {
            if ([folderName isEqualToString:folderNames[index]]) {
                return index;
            }
        }
    }
    else
    {
        return [AppSettings importantFolderNumForAcct:account forBaseFolder:folder.type];
    }
    return -1;
}

+ (NSArray *)allFoldersName:(NSInteger)account
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSArray* allFoldersPreference = [defaults objectForKey:[NSString stringWithFormat:@"allFolders_%lu", (long)account]];
	return allFoldersPreference;
}

+ (void)setFoldersName:(NSArray*)folders forAccount:(NSInteger)account
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:folders forKey:[NSString stringWithFormat:@"allFolders_%lu", (long)account]];
	[defaults synchronize];
}

+(NSArray*)allNonImportantFoldersName:(NSInteger)account
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray *allFoldersPreference = [defaults objectForKey:[NSString stringWithFormat:@"allFolders_%lu", (long)account]];
    NSMutableSet *foldersSet = [NSMutableSet setWithArray:allFoldersPreference];
    NSArray* importantFolderPreference = [defaults objectForKey:[NSString stringWithFormat:@"iFolder_%lu", (long)account]];
    
    for (NSNumber *index in importantFolderPreference) {
        if ([index intValue] >= 0) {
            [foldersSet removeObject:allFoldersPreference[[index intValue]]];
        }
    }
    
    return [foldersSet allObjects];
}

/*+ (FolderType)activeFolder
{
	return [[NSUserDefaults standardUserDefaults] integerForKey:@"aFolder"];
}

+ (void)setActiveFolder:(FolderType)folder
{
    if (folder.type == FolderTypeUser) {
        name = [[Accounts sharedInstance] currentAccount].userFolders[folder.idx];
    }
    else {
        name = [Accounts systemFolderNames][folder.type];
    }
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:@(folder) forKey:@"aFolder"];
	[defaults synchronize];
}*/

+ (NSInteger)activeAccount
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSNumber* activeAcctPreference = [defaults objectForKey:[NSString stringWithFormat:@"aAccount"]];
	return [activeAcctPreference integerValue];
}

+ (void)setActiveAccount:(NSInteger)account
{
    if(account > [AppSettings numActiveAccounts]){
        account = -1;
    }
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:@(account) forKey:[NSString stringWithFormat:@"aAccount"]];
	[defaults synchronize];
}

+(NSInteger)defaultAccount
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSNumber* activeAcctPreference = [defaults objectForKey:[NSString stringWithFormat:@"dAccount"]];
    return [activeAcctPreference integerValue];
}

+(void)setDefaultAccount:(NSInteger)account
{
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:@(account) forKey:[NSString stringWithFormat:@"dAccount"]];
    [defaults synchronize];
}

+ (void) setSettingsWithAccountVal:(MCOAccountValidator*)accountVal accountNum:(NSInteger)newAccountNum
{
    [AppSettings setUsername:accountVal.username accountNum:newAccountNum];
    [AppSettings setPassword:accountVal.password accountNum:newAccountNum];
    if (accountVal.OAuth2Token) {
        [AppSettings setOAuth:accountVal.OAuth2Token accountNum:newAccountNum];
    }
    else {
        [AppSettings setOAuth:@"" accountNum:newAccountNum];
    }
    
    [AppSettings setIdentifier:accountVal.identifier accountNum:newAccountNum];
    
    [AppSettings setImapServer:accountVal.imapServer.hostname accountNum:newAccountNum];
    [AppSettings setImapPort:accountVal.imapServer.port accountNum:newAccountNum];
    [AppSettings setImapEnc:accountVal.imapServer.connectionType accountNum:newAccountNum];
    
    [AppSettings setSmtpServer:accountVal.smtpServer.hostname accountNum:newAccountNum];
    [AppSettings setSmtpPort:accountVal.smtpServer.port accountNum:newAccountNum];
    [AppSettings setSmtpEnc:accountVal.smtpServer.connectionType accountNum:newAccountNum];
}

@end
