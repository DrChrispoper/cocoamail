//
//  AppSettings.h
//  CocoaMail
//
//  Created by Christopher Hockley on 20/01/2012.
//  Copyright (c) 2012 Christopher Hockley. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "Accounts.h"
#import <MailCore/MailCore.h>

@interface AppSettings : NSObject

+(NSString*)version;
+(NSString*)appID;
+(NSString*)udid;
+(NSString*)systemVersion;
+(NSString*)model;
+(BOOL)firstInit;
+(void)setFirstInit:(BOOL)value;
+(void)initDefaultValues;
+(BOOL)reset;
+(void)setReset:(BOOL)value;
+(BOOL)firstSync;
+(void)setFirstSync:(BOOL)firstSync;
+(NSString*)dataInitVersion;
+(void)setDataInitVersion;
+(NSInteger)datastoreVersion;
+(void)setDatastoreVersion:(NSInteger)value;

+(NSInteger)globalDBVersion;
+(void)setGlobalDBVersion:(NSInteger)version;

//Global Settings
+(void)setBadgeCount:(NSInteger)y;
+(NSInteger)badgeCount;
+(void)setNotifications:(BOOL)y;
+(BOOL)notifications;

// data about accounts
+(NSInteger)numAccountForEmail:(NSString*)email;
+(NSInteger)numAccountForIndex:(NSInteger)index;
+(NSInteger)numIndexForAccount:(NSInteger)accountNum;
+(NSInteger)numActiveAccounts;
+(NSInteger)numAccounts;
+(void)setNumAccounts:(NSInteger)value;
+(NSInteger)numDelAccounts;
+(void)setNumDelAccounts:(NSInteger)value;
+(BOOL)accountDeleted:(NSInteger)accountNum;
+(void)setAccountDeleted:(BOOL)value accountNum:(NSInteger)accountNum;

+(NSString*)identifier;
+(NSString*)identifier:(NSInteger)accountNum;
+(void)setIdentifier:(NSString*)value accountNum:(NSInteger)accountNum;

+(NSString*)username;
+(NSString*)username:(NSInteger)accountNum;
+(void)setUsername:(NSString*)y accountNum:(NSInteger)accountNum;

+(NSString*)password;
+(NSString*)password:(NSInteger)accountNum;
+(void)setPassword:(NSString*)y accountNum:(NSInteger)accountNum;

+(MCOIMAPSession*)imapSession:(NSInteger)accountNum;
+(NSString*)imapServer:(NSInteger)accountNum;
+(void)setImapServer:(NSString*)y accountNum:(NSInteger)accountNum;
+(unsigned int)imapPort:(NSInteger)accountNum;
+(void)setImapPort:(NSInteger)y accountNum:(NSInteger)accountNum;
+(NSInteger)imapEnc:(NSInteger)accountNum;
+(void)setImapEnc:(NSInteger)y accountNum:(NSInteger)accountNum;
+(NSString*)smtpServer:(NSInteger)accountNum;
+(void)setSmtpServer:(NSString*)y accountNum:(NSInteger)accountNum;
+(NSInteger)smtpPort:(NSInteger)accountNum;
+(void)setSmtpPort:(NSInteger)y accountNum:(NSInteger)accountNum;
+(NSInteger)smtpEnc:(NSInteger)accountNum;
+(void)setSmtpEnc:(NSInteger)y accountNum:(NSInteger)accountNum;

+(NSString*)signature:(NSInteger)accountNum;
+(void)setSignature:(NSString*)y accountNum:(NSInteger)accountNum;

+(NSString*)name:(NSInteger)accountNum;
+(void)setName:(NSString*)y accountNum:(NSInteger)accountNum;

+(NSString*)initials:(NSInteger)accountNum;
+(void)setInitials:(NSString*)y accountNum:(NSInteger)accountNum;

+(UIColor*)color:(NSInteger)accountNum;
+(void)setColor:(UIColor*)y accountNum:(NSInteger)accountNum;
+(void)setDefaultColorForAccountNum:(NSInteger)accountNum;

// For active account
+(BOOL)isUsingOAuth;
+(BOOL)isUsingOAuth:(NSInteger)accountNum;
+(void)setOAuth:(NSString*)y accountNum:(NSInteger)accountNum;
+(NSString*)oAuth:(NSInteger)accountNum;

/// Indexes are: 0-INBOX 1-Starred 2-Sent Mail 3-Draft 4-All Mail 5-Trash  6-Spam
+(NSInteger)importantFolderNumForAcct:(NSInteger)account forBaseFolder:(BaseFolderType)baseFolder;
+(void)setImportantFolderNum:(NSInteger)folder forBaseFolder:(BaseFolderType)baseFolder forAccount:(NSInteger)account;
+(FolderType)typeOfFolder:(NSInteger)folder forAccount:(NSInteger)account;
+(NSString*)folderName:(NSInteger)folder forAccount:(NSInteger)account;
+(NSInteger)numFolderWithFolder:(FolderType)folder forAccount:(NSInteger)account;
+(NSArray*)allFoldersName:(NSInteger)account;
+(NSArray*)allNonImportantFoldersName:(NSInteger)account;
+(void)setFoldersName:(NSArray*)folders forAccount:(NSInteger)account;
//+(FolderType)activeFolder;
//+(void)setActiveFolder:(FolderType)folder;
+(NSInteger)activeAccount;
+(void)setActiveAccount:(NSInteger)account;
+(NSInteger)defaultAccount;
+(void)setDefaultAccount:(NSInteger)account;

// in-store sales
+(BOOL)featurePurchased:(NSString*)productIdentifier;
+(void)setFeaturePurchased:(NSString*)productIdentifier;

+(void)firstFullSyncDone;
+(BOOL)isFirstFullSyncDone;

+(void)setSettingsWithAccountVal:(MCOAccountValidator*)accountVal accountNum:(NSInteger)accountNum;

@end
