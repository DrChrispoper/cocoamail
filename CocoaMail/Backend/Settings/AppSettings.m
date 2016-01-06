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
#import "Accounts.h"
#import "SyncManager.h"

@implementation AppSettings

+(NSString*) appID
{
	return [[NSBundle mainBundle] infoDictionary] [@"CFBundleIdentifier"];
}

+(NSString*) version
{
	return [[NSBundle mainBundle] infoDictionary] [@"CFBundleVersion"];
}

+(NSString*) dataInitVersion
{
	// version of the software at which the data store was initialized
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    
	return  [defaults stringForKey:@"app_data_init_version"];
}

+(void) setDataInitVersion
{
	// version of the software at which the data store was initialized
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults]; 
	[defaults setObject:[AppSettings version] forKey:@"app_data_init_version"];
	[NSUserDefaults resetStandardUserDefaults];
}

+(NSInteger) datastoreVersion
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	
    return [defaults integerForKey:@"datastore_version"];
}

+(void) setDatastoreVersion:(NSInteger)value
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults]; 
	[defaults setInteger:value forKey:[NSString stringWithFormat:@"datastore_version"]];
	[NSUserDefaults resetStandardUserDefaults];
}

+(NSString*) systemVersion
{
	NSString* systemVersion = [UIDevice currentDevice].systemVersion;
	
    return systemVersion;
}

+(NSString*) model
{
	NSString* model = [UIDevice currentDevice].model;
	
    return model;
}

+(NSString*) udid
{
	NSString* udid = [UIDevice currentDevice].identifierForVendor.UUIDString;
	
    return udid;
}

+(BOOL) firstSync
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	
    return ([defaults boolForKey:@"app_first_sync"] == NO); //stores the opposite!
}

+(void) setFirstSync:(BOOL)firstSync
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults]; 
	[defaults setBool:!firstSync forKey:@"app_first_sync"];
	[defaults synchronize];
}

+(BOOL) firstInit
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    BOOL resetPreference = [defaults boolForKey:@"init_preference"];
    
    return resetPreference;
}

+(void) setFirstInit:(BOOL)value
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults setBool:value forKey:@"init_preference"];
    [NSUserDefaults resetStandardUserDefaults];
}

+(void) initDefaultValues
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:0 forKey:@"num_accounts"];
    [defaults synchronize];

    [AppSettings setFirstInit:TRUE];
}

+(BOOL) reset
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults]; 
	BOOL resetPreference = [defaults boolForKey:@"reset_preference"];
	
    return resetPreference;
}

+(void) setReset:(BOOL)value
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults]; 
	[defaults setBool:value forKey:@"reset_preference"];
	[NSUserDefaults resetStandardUserDefaults];
}

+(void) setBadgeCount:(NSInteger)y
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:@(y) forKey:@"badgecount_preference"];
    
    /*NSUbiquitousKeyValueStore *store = [NSUbiquitousKeyValueStore defaultStore];
    if (store) {
        [store setObject:@(y) forKey:@"badgecount_preference"];
        [store synchronize];
    }*/
    
    [AppSettings setInboxUnread:[AppSettings inboxUnread:0] accountIndex:0];
}

+(NSInteger) badgeCount
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	
    return [[defaults objectForKey:@"badgecount_preference"] integerValue];
}

+(void) setNotifications:(BOOL)y
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:@(y) forKey:@"notifications_preference"];
    
    /*NSUbiquitousKeyValueStore *store = [NSUbiquitousKeyValueStore defaultStore];
    if (store) {
        [store setObject:@(y) forKey:@"notifications_preference"];
        [store synchronize];
    }*/
}

+(BOOL) notifications
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    
    return [defaults boolForKey:@"notifications_preference"];
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

+(QuickSwipeType) quickSwipe
{
    return [[[NSUserDefaults standardUserDefaults] objectForKey:@"quickswipe_preference"] unsignedIntegerValue];
}

+(void) setQuickSwipe:(QuickSwipeType)quickswipetype
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:@(quickswipetype) forKey:@"quickswipe_preference"];
    
    /*/*NSUbiquitousKeyValueStore *store = [NSUbiquitousKeyValueStore defaultStore];
    if (store) {
        [store setObject:@(quickswipetype) forKey:@"quickswipe_preference"];
        [store synchronize];
    }*/
}

+(NSInteger) draftCount
{
    NSInteger count = [[[NSUserDefaults standardUserDefaults] objectForKey:@"drafts_preference"] integerValue];
    
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:@(count + 1) forKey:@"drafts_preference"];
    
    /*NSUbiquitousKeyValueStore *store = [NSUbiquitousKeyValueStore defaultStore];
    if (store) {
        [store setObject:@(count + 1) forKey:@"drafts_preference"];
        [store synchronize];
    }*/
    
    return count;
}

+(void) firstFullSyncDone:(NSInteger)accountIndex
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:@(YES) forKey:[NSString stringWithFormat:@"first_sync_%li", (long)[AppSettings numAccountForIndex:accountIndex]]];
    
    /*NSUbiquitousKeyValueStore *store = [NSUbiquitousKeyValueStore defaultStore];
    if (store) {
        [store setObject:@(YES) forKey:@"first_sync_%li"];
        [store synchronize];
    }*/
}

+(BOOL) isFirstFullSyncDone:(NSInteger)accountIndex
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    
    return [defaults boolForKey:[NSString stringWithFormat:@"first_sync_%li", (long)[AppSettings numAccountForIndex:accountIndex]]];
}

+(BOOL) premiumPurchased
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults]; 
	
    return  [defaults boolForKey:@"premium"];
}

+(void) setPremiumPurchased
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults]; 
	[defaults setObject:@YES forKey:@"premium"];
    
    /*NSUbiquitousKeyValueStore *store = [NSUbiquitousKeyValueStore defaultStore];
    if (store) {
        [store setObject:@(YES) forKey:@"premium"];
        [store synchronize];
    }*/
}

+(NSInteger) globalDBVersion
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults]; 
	NSInteger pref = [defaults integerForKey:@"global_db_version"];
	
    return pref;
}

+(void) setGlobalDBVersion:(NSInteger)version
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults]; 
	[defaults setInteger:version forKey:@"global_db_version"];
	[NSUserDefaults resetStandardUserDefaults];
}

+(NSInteger) accountIndexForEmail:(NSString*)email
{
    NSInteger index = [AppSettings numActiveAccounts] - 1;
    
    while (index != -1) {
        //NSInteger numAccount = [AppSettings numAccountForIndex:index];
        
        if ([[AppSettings username:index] isEqualToString:email]) {
            return index;
        }
        else {
            index--;
        }
    }
    
    return -1;
}

+(NSInteger) numForData:(NSInteger)accountIndex
{
    return [AppSettings numAccountForIndex:accountIndex];
}

//NumAccout:1 - 2 - 4 If 3 is deleted
+(NSInteger) numAccountForIndex:(NSInteger)accountIndex
{
    if (accountIndex == [AppSettings numActiveAccounts]) {
        return -1;
    }
    
    NSAssert(accountIndex < [AppSettings numActiveAccounts], @"Index:%li is incorrect only %li active account",(long)accountIndex,(long)[AppSettings numActiveAccounts]);
    
    NSInteger accountNum = 0;
    
    if (accountIndex == [AppSettings numActiveAccounts]) {
        return -1;
    }
    
    while (accountIndex != -1) {
        if (![AppSettings isAccountNumDeleted:accountNum + 1]) {
            accountIndex--;
        }
        accountNum++;
    }
    
	return accountNum;
}

//numIndex:0 - 1 - 2 ...
+(NSInteger) indexForAccount:(NSInteger)accountNum
{
    NSInteger index = accountNum;
    NSInteger i = -1;
    
    while (index != 0) {
        if (![AppSettings isAccountDeleted:++i]) {
            index--;
        }
    }
    
    NSAssert(i < [AppSettings numActiveAccounts],@"returning an incorrect account index");
    if (i < 0) {
        
        NSAssert(i >= 0,@"returning an incorrect account index; %s ", __PRETTY_FUNCTION__);
    }

    return i;
}

+(NSInteger) numActiveAccounts
{
    return [AppSettings numAccounts] - [AppSettings numDelAccounts];
}

+(NSInteger) numAccounts
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults]; 
	NSInteger numAccts = [[defaults objectForKey:@"num_accounts"] integerValue];
	
    return numAccts;
}

+(void) addAccount
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSInteger numAccts = [[defaults objectForKey:@"num_accounts"] integerValue] + 1;
    
	[defaults setObject:@(numAccts) forKey:@"num_accounts"];
    
    [AppSettings setAccountDeleted:NO accountIndex:[AppSettings indexForAccount:numAccts]];

    /*NSUbiquitousKeyValueStore *store = [NSUbiquitousKeyValueStore defaultStore];
    if (store) {
        [store setObject:@(numAccts) forKey:@"num_accounts"];
        [store synchronize];
    }*/
}

+(NSInteger) numDelAccounts
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	
    return [[defaults objectForKey:@"num_del_accounts"] integerValue];
}

+(void) setNumDelAccounts:(NSInteger)value
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:@(value) forKey:@"num_del_accounts"];
	
    /*NSUbiquitousKeyValueStore *store = [NSUbiquitousKeyValueStore defaultStore];
    if (store) {
        [store setObject:@(value) forKey:@"num_del_accounts"];
        [store synchronize];
    }*/
}

+(BOOL) isAccountNumDeleted:(NSInteger)accountNum
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSString* key = [NSString stringWithFormat:@"account_deleted_%ld", (long)accountNum];
    BOOL isDeleted = [defaults boolForKey:key];
    return isDeleted;
}

+(BOOL) isAccountDeleted:(NSInteger)accountIndex
{
    return [AppSettings isAccountNumDeleted:[AppSettings numAccountForIndex:accountIndex]];
}

+(void) setAccountDeleted:(BOOL)value accountIndex:(NSInteger)accountIndex
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults]; 
	[defaults setBool:value forKey:[NSString stringWithFormat:@"account_deleted_%ld", (long)[AppSettings numAccountForIndex:accountIndex]]];
	
    /*NSUbiquitousKeyValueStore *store = [NSUbiquitousKeyValueStore defaultStore];
    if (store) {
        [store setObject:@(value) forKey:@"account_deleted_%ld"];
        [store synchronize];
    }*/
    
    if (value) {
        [self setNumDelAccounts:[AppSettings numDelAccounts] + 1];
    }
}

+(NSString*) identifier:(NSInteger)accountIndex
{
	NSString* str =  [[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat:@"identifier_%li", (long)[AppSettings numAccountForIndex:accountIndex]]];
    
    return str;
}

+(void) setIdentifier:(NSString*)value accountIndex:(NSInteger)accountIndex
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults]; 
	[defaults setObject:value forKey:[NSString stringWithFormat:@"identifier_%li", (long)[AppSettings numAccountForIndex:accountIndex]]];
	
    /*NSUbiquitousKeyValueStore *store = [NSUbiquitousKeyValueStore defaultStore];
    if (store) {
        [store setObject:value forKey:@"identifier_%li"];
        [store synchronize];
    }*/
}

+(NSString*) username:(NSInteger)accountIndex
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	NSString* usernamePreference = [defaults stringForKey:[NSString stringWithFormat:@"username_%li", (long)[AppSettings numAccountForIndex:accountIndex]]];
	
    return usernamePreference;
}

+(void) setUsername:(NSString*)y accountIndex:(NSInteger)accountIndex
{
	NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults]; 
	[defaults setObject:y forKey:[NSString stringWithFormat:@"username_%li", (long)[AppSettings numAccountForIndex:accountIndex]]];
	
    /*NSUbiquitousKeyValueStore *store = [NSUbiquitousKeyValueStore defaultStore];
    if (store) {
        [store setObject:y forKey:@"username_%li"];
        [store synchronize];
    }*/
}

+(NSString*) password:(NSInteger)accountIndex
{
	NSString* str =  [[PDKeychainBindings sharedKeychainBindings] objectForKey:[NSString stringWithFormat: @"P%li", (long)[AppSettings numAccountForIndex:accountIndex]]];
    
    return str;
}

+(void) setPassword:(NSString*)y accountIndex:(NSInteger)accountIndex
{
    PDKeychainBindings* bindings = [PDKeychainBindings sharedKeychainBindings];
    [bindings setObject:y forKey:[NSString stringWithFormat: @"P%li", (long)[AppSettings numAccountForIndex:accountIndex]] accessibleAttribute:kSecAttrAccessibleAfterFirstUnlock];
}

+(MCOIMAPSession*) imapSession:(NSInteger)accountIndex
{
    MCOIMAPSession* imapSession = [[MCOIMAPSession alloc] init];
    
    imapSession.hostname = [AppSettings imapServer:accountIndex];
    imapSession.port = [AppSettings imapPort:accountIndex];
    imapSession.username = [AppSettings username:accountIndex];
    imapSession.password = [AppSettings password:accountIndex];
    
    if ([AppSettings isUsingOAuth:accountIndex]) {
        imapSession.OAuth2Token = [AppSettings oAuth:accountIndex];
        imapSession.authType = MCOAuthTypeXOAuth2;
    }
    imapSession.connectionType = [AppSettings imapEnc:accountIndex];
    
    return imapSession;
}

+(NSString*) imapServer:(NSInteger)accountIndex
{
    return [[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat: @"IMAPServ%li", (long)[AppSettings numAccountForIndex:accountIndex]]];
}

+(void) setImapServer:(NSString*)y accountIndex:(NSInteger)accountIndex
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:y forKey:[NSString stringWithFormat:@"IMAPServ%li", (long)[AppSettings numAccountForIndex:accountIndex]]];
	
    /*NSUbiquitousKeyValueStore *store = [NSUbiquitousKeyValueStore defaultStore];
    if (store) {
        [store setObject:y forKey:@"IMAPServ%li"];
        [store synchronize];
    }*/
}

+(unsigned int) imapPort:(NSInteger)accountIndex
{
    return (unsigned int)[[[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat: @"IMAPPort_%li", (long)[AppSettings numAccountForIndex:accountIndex]]] integerValue];
}

+(void) setImapPort:(NSInteger)y accountIndex:(NSInteger)accountIndex
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:@(y) forKey:[NSString stringWithFormat:@"IMAPPort_%li", (long)[AppSettings numAccountForIndex:accountIndex]]];
	
    /*NSUbiquitousKeyValueStore *store = [NSUbiquitousKeyValueStore defaultStore];
    if (store) {
        [store setObject:@(y) forKey:@"IMAPPort_%li"];
        [store synchronize];
    }*/
}

+(NSInteger) imapEnc:(NSInteger)accountIndex
{
    return [[[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat:@"IMAPEnc_%li", (long)[AppSettings numAccountForIndex:accountIndex]]] integerValue];
}

+(void) setImapEnc:(NSInteger)y accountIndex:(NSInteger)accountIndex
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:@(y) forKey:[NSString stringWithFormat:@"IMAPEnc_%li", (long)[AppSettings numAccountForIndex:accountIndex]]];
	
    /*NSUbiquitousKeyValueStore *store = [NSUbiquitousKeyValueStore defaultStore];
    if (store) {
        [store setObject:@(y) forKey:@"IMAPEnc_%li"];
        [store synchronize];
    }*/
}

+(NSString*) smtpServer:(NSInteger)accountIndex
{
    return [[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat: @"SMTPServ_%li", (long)[AppSettings numAccountForIndex:accountIndex]]];
}

+(void) setSmtpServer:(NSString*)y accountIndex:(NSInteger)accountIndex
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:y forKey:[NSString stringWithFormat:@"SMTPServ%li", (long)[AppSettings numAccountForIndex:accountIndex]]];
	
    /*NSUbiquitousKeyValueStore *store = [NSUbiquitousKeyValueStore defaultStore];
    if (store) {
        [store setObject:y forKey:@"SMTPServ%li"];
        [store synchronize];
    }*/
}

+(NSInteger) smtpPort:(NSInteger)accountIndex
{
    return [[[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat: @"SMTPPort_%li", (long)[AppSettings numAccountForIndex:accountIndex]]] integerValue];
}

+(void) setSmtpPort:(NSInteger)y accountIndex:(NSInteger)accountIndex
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:@(y) forKey:[NSString stringWithFormat:@"SMTPPort_%li", (long)[AppSettings numAccountForIndex:accountIndex]]];
	
    /*NSUbiquitousKeyValueStore *store = [NSUbiquitousKeyValueStore defaultStore];
    if (store) {
        [store setObject:@(y) forKey:@"SMTPPort_%li"];
        [store synchronize];
    }*/
}

+(NSInteger) smtpEnc:(NSInteger)accountIndex
{
    return [[[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat:@"SMTPEnc_%li", (long)[AppSettings numAccountForIndex:accountIndex]]] integerValue];
}

+(void) setSmtpEnc:(NSInteger)y accountIndex:(NSInteger)accountIndex
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:@(y) forKey:[NSString stringWithFormat:@"SMTPEnc_%li", (long)[AppSettings numAccountForIndex:accountIndex]]];
	
    /*NSUbiquitousKeyValueStore *store = [NSUbiquitousKeyValueStore defaultStore];
    if (store) {
        [store setObject:@(y) forKey:@"SMTPEnc_%li"];
        [store synchronize];
    }*/
}

+(NSString*) signature:(NSInteger)accountIndex
{
    return [[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat: @"Signature_%li", (long)[AppSettings numAccountForIndex:accountIndex]]];
}

+(void) setSignature:(NSString*)y accountIndex:(NSInteger)accountIndex
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:y forKey:[NSString stringWithFormat:@"Signature_%li", (long)[AppSettings numAccountForIndex:accountIndex]]];
	
    /*NSUbiquitousKeyValueStore *store = [NSUbiquitousKeyValueStore defaultStore];
    if (store) {
        [store setObject:y forKey:@"Signature_%li"];
        [store synchronize];
    }*/
}

+(NSString*) name:(NSInteger)accountIndex
{
    return [[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat: @"Name_%li", (long)[AppSettings numAccountForIndex:accountIndex]]];

}

+(void) setName:(NSString*)y accountIndex:(NSInteger)accountIndex
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:y forKey:[NSString stringWithFormat:@"Name_%li", (long)[AppSettings numAccountForIndex:accountIndex]]];
	
    /*NSUbiquitousKeyValueStore *store = [NSUbiquitousKeyValueStore defaultStore];
    if (store) {
        [store setObject:y forKey:@"Name_%li"];
        [store synchronize];
    }*/
}

+(NSString*) initials:(NSInteger)accountIndex
{
    if (accountIndex == [AppSettings numActiveAccounts]) {
        return @"ALL";
    }
    
    return [[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat: @"Initials_%li", (long)[AppSettings numAccountForIndex:accountIndex]]];
}

+(void) setInitials:(NSString*)y accountIndex:(NSInteger)accountIndex
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:y forKey:[NSString stringWithFormat:@"Initials_%li", (long)[AppSettings numAccountForIndex:accountIndex]]];
	
    /*NSUbiquitousKeyValueStore *store = [NSUbiquitousKeyValueStore defaultStore];
    if (store) {
        [store setObject:y forKey:@"Initials_%li"];
        [store synchronize];
    }*/
}

+(UIColor*) color:(NSInteger)accountIndex
{
    if (accountIndex == [AppSettings numActiveAccounts]) {
        return [UIColor blackColor];
    }
    UIColor* color = [UIColor colorWithCIColor:[CIColor colorWithString:[[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat: @"Color_%li", (long)[AppSettings numAccountForIndex:accountIndex]]]]];
    
    return color;
}

+(void) setColor:(UIColor*)y accountIndex:(NSInteger)accountIndex
{
    CGColorRef colorRef = y.CGColor;
    NSString* colorString = [CIColor colorWithCGColor:colorRef].stringRepresentation;
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	[defaults setObject:colorString forKey:[NSString stringWithFormat:@"Color_%li", (long)[AppSettings numAccountForIndex:accountIndex]]];
	
    /*NSUbiquitousKeyValueStore *store = [NSUbiquitousKeyValueStore defaultStore];
    if (store) {
        [store setObject:colorString forKey:@"Color_%li"];
        [store synchronize];
    }*/
}

+(BOOL) isUsingOAuth:(NSInteger)accountIndex
{
    NSString* token = [AppSettings oAuth:accountIndex];
    
	return  ![token isEqualToString:@""];
}

+(NSString*) oAuth:(NSInteger)accountIndex
{
	return [[PDKeychainBindings sharedKeychainBindings] stringForKey:[NSString stringWithFormat: @"T%li", (long)[AppSettings numAccountForIndex:accountIndex]]];
}

+(void) setOAuth:(NSString*)y accountIndex:(NSInteger)accountIndex
{
    PDKeychainBindings* bindings = [PDKeychainBindings sharedKeychainBindings];
    [bindings setString:y forKey:[NSString stringWithFormat: @"T%li", (long)[AppSettings numAccountForIndex:accountIndex]] accessibleAttribute:kSecAttrAccessibleAfterFirstUnlock];
}

+(NSInteger) importantFolderNumforAccountIndex:(NSInteger)accountIndex forBaseFolder:(BaseFolderType)baseFolder
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	NSArray* importantFolderPreference = [defaults objectForKey:[NSString stringWithFormat:@"iFolder_%li", (long)[AppSettings numAccountForIndex:accountIndex]]];
	
    return [importantFolderPreference[baseFolder] integerValue];
}

+(void) setImportantFolderNum:(NSInteger)folder forBaseFolder:(BaseFolderType)baseFolder forAccountIndex:(NSInteger)accountIndex
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSMutableArray* newfolders = [[NSMutableArray alloc] initWithArray:[defaults objectForKey:[NSString stringWithFormat:@"iFolder_%li", (long)[AppSettings numAccountForIndex:accountIndex]]]];
    
    if (newfolders.count == 0) {
        newfolders = [[NSMutableArray alloc] initWithObjects:@"", @"", @"", @"", @"", @"", nil];
    }
    
    newfolders[baseFolder] = @(folder);
    
	[defaults setObject:newfolders forKey:[NSString stringWithFormat:@"iFolder_%li", (long)[AppSettings numAccountForIndex:accountIndex]]];
	
    /*NSUbiquitousKeyValueStore *store = [NSUbiquitousKeyValueStore defaultStore];
    if (store) {
        [store setObject:newfolders forKey:@"iFolder_%li"];
        [store synchronize];
    }*/
}

+(CCMFolderType) typeOfFolder:(NSInteger)folder forAccountIndex:(NSInteger)accountIndex
{
    if (accountIndex == [AppSettings numActiveAccounts]) {
        return FolderTypeWith(folder, 0);
    }
    
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSArray* importantFolderPreference = [defaults objectForKey:[NSString stringWithFormat:@"iFolder_%li", (long)[AppSettings numAccountForIndex:accountIndex]]];
    
    for (int idx = (int)importantFolderPreference.count-1 ; idx >= 0 ; idx--) {
        if (folder == [importantFolderPreference[idx] integerValue]) {
            return FolderTypeWith(idx, 0);
        }
    }
    
    NSArray* nonImportantFolders = [AppSettings allNonImportantFoldersNameforAccountIndex:accountIndex];
    NSString* folderName = [AppSettings folderDisplayName:folder forAccountIndex:accountIndex];
    
    for (int idx = 0; idx < nonImportantFolders.count;idx++) {
        if ([folderName isEqualToString:nonImportantFolders[idx]]) {
            return FolderTypeWith(FolderTypeUser, idx);
        }
    }
    
    return FolderTypeWith(FolderTypeAll, 0);
}

+(NSString*) folderDisplayName:(NSInteger)folder forAccountIndex:(NSInteger)accountIndex
{
    if (accountIndex == [AppSettings numActiveAccounts]) {
        return @"INBOX";
    }
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	NSArray* allFoldersPreference = [defaults objectForKey:[NSString stringWithFormat:@"allFolders_%li", (long)[AppSettings numAccountForIndex:accountIndex]]];
	
    return allFoldersPreference[folder];
}

+(NSString*) folderServerName:(NSInteger)folder forAccountIndex:(NSInteger)accountIndex
{
    NSMutableDictionary* folderState = [[SyncManager getSingleton] retrieveState:folder accountIndex:accountIndex];
    return folderState[@"folderPath"];
}

+(NSInteger) numFolderWithFolder:(CCMFolderType)folder forAccountIndex:(NSInteger)accountIndex
{
    NSArray* folderNames = [AppSettings allFoldersNameforAccountIndex:accountIndex];
    NSString* folderName;
    
    if (folder.type == FolderTypeUser) {
        folderName = [[Accounts sharedInstance] currentAccount].userFolders[folder.idx][0];
        for (int index = 0; index < [folderNames count]; index++) {
            if ([folderName isEqualToString:folderNames[index]]) {
                return index;
            }
        }
    } else {
        return [AppSettings importantFolderNumforAccountIndex:accountIndex forBaseFolder:folder.type];
    }
    
    return -1;
}

+(NSArray*) allFoldersNameforAccountIndex:(NSInteger)accountIndex
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
	NSArray* allFoldersPreference = [defaults objectForKey:[NSString stringWithFormat:@"allFolders_%li", (long)[AppSettings numAccountForIndex:accountIndex]]];
	
    return allFoldersPreference;
}

+(void) setFoldersName:(NSArray*)folders forAccountIndex:(NSInteger)accountIndex
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:folders forKey:[NSString stringWithFormat:@"allFolders_%li", (long)[AppSettings numAccountForIndex:accountIndex]]];
	
    /*NSUbiquitousKeyValueStore *store = [NSUbiquitousKeyValueStore defaultStore];
    if (store) {
        [store setObject:folders forKey:@"allFolders_%li"];
        [store synchronize];
    }*/
}

+(NSArray*) allNonImportantFoldersNameforAccountIndex:(NSInteger)accountIndex
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSArray* allFoldersPreference = [defaults objectForKey:[NSString stringWithFormat:@"allFolders_%li", (long)[AppSettings numAccountForIndex:accountIndex]]];
    NSMutableSet* foldersSet = [NSMutableSet setWithArray:allFoldersPreference];
    NSArray* importantFolderPreference = [defaults objectForKey:[NSString stringWithFormat:@"iFolder_%li", (long)[AppSettings numAccountForIndex:accountIndex]]];
    
    for (NSNumber* index in importantFolderPreference) {
        if ([index intValue] >= 0) {
            [foldersSet removeObject:allFoldersPreference[[index intValue]]];
        }
    }
    
    return [[foldersSet allObjects] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

+(NSInteger) defaultAccountIndex
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSNumber* activeAcctPreference = [defaults objectForKey:[NSString stringWithFormat:@"dAccount"]];
    NSInteger index = [activeAcctPreference integerValue];
    
    if (index != 999) {
        return [AppSettings indexForAccount:index];
    }
    else {
        return [AppSettings numActiveAccounts];
    }
}

+(void) setDefaultAccountIndex:(NSInteger)accountIndex
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:@((accountIndex == [AppSettings numActiveAccounts])?999:[AppSettings numAccountForIndex:accountIndex]) forKey:[NSString stringWithFormat:@"dAccount"]];
    
    /*NSUbiquitousKeyValueStore *store = [NSUbiquitousKeyValueStore defaultStore];
    if (store) {
        [store setObject:@((accountIndex == [AppSettings numActiveAccounts])?999:[AppSettings numAccountForIndex:accountIndex]) forKey:@"dAccount"];
        [store synchronize];
    }*/
}

+(NSInteger) lastAccountIndex
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    NSNumber* activeAcctPreference = [defaults objectForKey:[NSString stringWithFormat:@"lastAccount"]];
    NSInteger index = [activeAcctPreference integerValue];
    
    if ([AppSettings numActiveAccounts] != 0 && index != 999) {
        return [AppSettings indexForAccount:index];
    }
    else {
        return [AppSettings numActiveAccounts];
    }
}

+(void) setLastAccountIndex:(NSInteger)accountIndex
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:@((accountIndex == [AppSettings numActiveAccounts])?999:[AppSettings numAccountForIndex:accountIndex]) forKey:[NSString stringWithFormat:@"lastAccount"]];
    
    /*NSUbiquitousKeyValueStore *store = [NSUbiquitousKeyValueStore defaultStore];
    if (store) {
        [store setObject:@((accountIndex == [AppSettings numActiveAccounts])?999:[AppSettings numAccountForIndex:accountIndex]) forKey:@"lastAccount"];
        [store synchronize];
    }*/
}

+(void) setSettingsWithAccountVal:(MCOAccountValidator*)accountVal accountIndex:(NSInteger)accountIndex
{
    [AppSettings setUsername:accountVal.username accountIndex:accountIndex];
    [AppSettings setPassword:accountVal.password accountIndex:accountIndex];
   
    if (accountVal.OAuth2Token) {
        [AppSettings setOAuth:accountVal.OAuth2Token accountIndex:accountIndex];
    }
    else {
        [AppSettings setOAuth:@"" accountIndex:accountIndex];
    }
    
    [AppSettings setIdentifier:accountVal.identifier accountIndex:accountIndex];
    
    [AppSettings setImapServer:accountVal.imapServer.hostname accountIndex:accountIndex];
    [AppSettings setImapPort:accountVal.imapServer.port accountIndex:accountIndex];
    [AppSettings setImapEnc:accountVal.imapServer.connectionType accountIndex:accountIndex];
    
    [AppSettings setSmtpServer:accountVal.smtpServer.hostname accountIndex:accountIndex];
    [AppSettings setSmtpPort:accountVal.smtpServer.port accountIndex:accountIndex];
    [AppSettings setSmtpEnc:accountVal.smtpServer.connectionType accountIndex:accountIndex];
}

+(NSInteger) inboxUnread:(NSInteger)accountIndex
{
    NSNumber* str =  [[NSUserDefaults standardUserDefaults] objectForKey:[NSString stringWithFormat:@"inboxUnread_%li", (long)[AppSettings numAccountForIndex:accountIndex]]];
    return [str integerValue];
}

+(void) setInboxUnread:(NSInteger)value accountIndex:(NSInteger)accountIndex
{
    NSUserDefaults* defaults = [NSUserDefaults standardUserDefaults];
    [defaults setObject:@(value) forKey:[NSString stringWithFormat:@"inboxUnread_%li", (long)[AppSettings numAccountForIndex:accountIndex]]];
    
    /*NSUbiquitousKeyValueStore *store = [NSUbiquitousKeyValueStore defaultStore];
    if (store) {
        [store setObject:@(value) forKey:@"inboxUnread_%li"];
        [store synchronize];
    }*/
    
    int badge = 0;
    
    if ([AppSettings badgeCount] == 1) {
        for (int index = 0; index < [AppSettings numActiveAccounts]; index++) {
            badge += [AppSettings inboxUnread:index];
        }
    }
    
    [UIApplication sharedApplication].applicationIconBadgeNumber = badge;
}

@end
