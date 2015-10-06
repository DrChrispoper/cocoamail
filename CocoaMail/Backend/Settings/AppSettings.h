//
//  AppSettings.h
//  CocoaMail
//
//  Created by Christopher Hockley on 20/01/2012.
//  Copyright (c) 2012 Christopher Hockley. All rights reserved.
//

#import <UIKit/UIKit.h>
#import <MailCore/MailCore.h>
#import "CCMConstants.h"

@interface AppSettings : NSObject

+ (NSString *)version;
+ (NSString *)appID;
+ (NSString *)udid;
+ (NSString *)systemVersion;
+ (NSString *)model;
+ (BOOL)firstInit;
+ (void)setFirstInit:(BOOL)value;
+ (void)initDefaultValues;
+ (BOOL)reset;
+ (void)setReset:(BOOL)value;
//+(BOOL)firstSync;
//+(void)setFirstSync:(BOOL)firstSync;
+ (NSString *)dataInitVersion;
+ (void)setDataInitVersion;
+ (NSInteger)datastoreVersion;
+ (void)setDatastoreVersion:(NSInteger)value;

+ (NSInteger)globalDBVersion;
+ (void)setGlobalDBVersion:(NSInteger)version;

//Global Settings
+ (void)setBadgeCount:(NSInteger)y;
+ (NSInteger)badgeCount;
+ (void)setNotifications:(BOOL)y;
+ (BOOL)notifications;
+ (NSArray *)defaultColors;

// Data about accounts
+ (NSInteger)accountIndexForEmail:(NSString *)email;
+ (NSInteger)indexForAccount:(NSInteger)accountNum;

+ (NSInteger)numActiveAccounts;

+ (NSInteger)numAccounts;
+ (void)addAccount;

//For SyncManager
+ (BOOL)isAccountNumDeleted:(NSInteger)accountNum;
+ (NSInteger)numForData:(NSInteger)accountIndex;

+ (NSInteger)numDelAccounts;
+ (void)setNumDelAccounts:(NSInteger)value;

+ (BOOL)isAccountDeleted:(NSInteger)accountIndex;
+ (void)setAccountDeleted:(BOOL)value accountIndex:(NSInteger)accountIndex;

//Account Main Settings
+ (NSString *)identifier:(NSInteger)accountIndex;
+ (void)setIdentifier:(NSString *)identifier accountIndex:(NSInteger)accountIndex;

+ (NSString *)username:(NSInteger)accountIndex;
+ (void)setUsername:(NSString *)username accountIndex:(NSInteger)accountIndex;

+ (NSString *)password:(NSInteger)accountIndex;
+ (void)setPassword:(NSString *)password accountIndex:(NSInteger)accountIndex;

//Account Server Settings
+ (MCOIMAPSession *)imapSession:(NSInteger)accountIndex;

+ (NSString *)imapServer:(NSInteger)accountIndex;
+ (void)setImapServer:(NSString *)y accountIndex:(NSInteger)accountIndex;

+ (unsigned int)imapPort:(NSInteger)accountIndex;
+ (void)setImapPort:(NSInteger)y accountIndex:(NSInteger)accountIndex;

+ (NSInteger)imapEnc:(NSInteger)accountIndex;
+ (void)setImapEnc:(NSInteger)y accountIndex:(NSInteger)accountIndex;

+ (NSString *)smtpServer:(NSInteger)accountIndex;
+ (void)setSmtpServer:(NSString *)y accountIndex:(NSInteger)accountIndex;

+ (NSInteger)smtpPort:(NSInteger)accountIndex;
+ (void)setSmtpPort:(NSInteger)y accountIndex:(NSInteger)accountIndex;

+ (NSInteger)smtpEnc:(NSInteger)accountIndex;
+ (void)setSmtpEnc:(NSInteger)y accountIndex:(NSInteger)accountIndex;

+ (void)setOAuth:(NSString *)y accountIndex:(NSInteger)accountIndex;
+ (NSString *)oAuth:(NSInteger)accountIndex;
+ (BOOL)isUsingOAuth:(NSInteger)accountIndex;

//Account Other Settings
+ (NSString *)signature:(NSInteger)accountIndex;
+ (void)setSignature:(NSString *)y accountIndex:(NSInteger)accountIndex;

+ (NSString *)name:(NSInteger)accountIndex;
+ (void)setName:(NSString *)y accountIndex:(NSInteger)accountIndex;

+ (NSString *)initials:(NSInteger)accountIndex;
+ (void)setInitials:(NSString *)y accountIndex:(NSInteger)accountIndex;

+ (UIColor *)color:(NSInteger)accountIndex;
+ (void)setColor:(UIColor *)y accountIndex:(NSInteger)accountIndex;

/// Indexes are: 0-INBOX 1-Starred 2-Sent Mail 3-Draft 4-All Mail 5-Trash  6-Spam
+ (NSInteger)importantFolderNumforAccountIndex:(NSInteger)accountIndex forBaseFolder:(BaseFolderType)baseFolder;
+ (void)setImportantFolderNum:(NSInteger)folder forBaseFolder:(BaseFolderType)baseFolder forAccountIndex:(NSInteger)accountIndex;
+ (CCMFolderType)typeOfFolder:(NSInteger)folder forAccountIndex:(NSInteger)accountIndex;
+ (NSInteger)numFolderWithFolder:(CCMFolderType)folder forAccountIndex:(NSInteger)accountIndex;

+ (NSString *)folderName:(NSInteger)folder forAccountIndex:(NSInteger)accountIndex;
+ (NSArray *)allFoldersNameforAccountIndex:(NSInteger)accountIndex;
+ (NSArray *)allNonImportantFoldersNameforAccountIndex:(NSInteger)accountIndex;
+ (void)setFoldersName:(NSArray *)folders forAccountIndex:(NSInteger)accountIndex;
//+(CCMFolderType)activeFolder;
//+(void)setActiveFolder:(CCMFolderType)folder;
//+(NSInteger)activeAccount;
//+(void)setActiveAccount:(NSInteger)account;
+ (NSInteger)defaultAccountIndex;
+ (void)setDefaultAccountIndex:(NSInteger)accountIndex;

// in-store sales
+ (BOOL)featurePurchased:(NSString *)productIdentifier;
+ (void)setFeaturePurchased:(NSString *)productIdentifier;

+ (void)firstFullSyncDone:(NSInteger)accountIndex;
+ (BOOL)isFirstFullSyncDone:(NSInteger)accountIndex;;

+ (void)setSettingsWithAccountVal:(MCOAccountValidator *)accountVal accountIndex:(NSInteger)accountIndex;

@end
