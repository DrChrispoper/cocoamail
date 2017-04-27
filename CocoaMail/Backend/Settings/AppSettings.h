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

@class UserSettings;

#define CLIENT_ID @"489238945643-oqhsao0g40kf8qe7qkrao3ivmhoeuifl.apps.googleusercontent.com"
#define CLIENT_SECRET @"LhDDzVoxcxbVT95lNPSDWkCg"
#define TKN_KEYCHAIN_NAME @"CocoaMail iOS"
#define USR_TKN_KEYCHAIN_NAME [NSString stringWithFormat:@"%@%lu", TKN_KEYCHAIN_NAME,(unsigned long)user.accountNum]

@interface AppSettings : NSObject

//Global Settings
@property (nonatomic) NSInteger badgeCount;
@property (nonatomic, strong) NSArray* cache;
@property (nonatomic) BOOL canSyncOverData;
+(NSArray*) defaultColors;
@property (nonatomic) QuickSwipeType quickSwipe;
@property (nonatomic) uint32_t draftCount;
@property (nonatomic) BOOL premiumPurchased;
@property (nonatomic) NSInteger globalDBVersion;


@property (nonatomic, strong) NSMutableArray<UserSettings *>* users;

+(AppSettings*) getSingleton;

+(NSUInteger) numActiveAccounts; // number of non-deleted accounts
+(NSMutableArray*) activeUsers;

-(UserSettings*) createNewUser; 

//Account Main Settings
+(UserSettings*) userWithIndex:(NSUInteger)accountIndex;
+(UserSettings*) userWithNum:(NSInteger)accountNum;
+(UserSettings*) userWithEmail:(NSString*)email;

//+(NSInteger) numAccountForIndex:(NSInteger)accountIndex;
+(NSUInteger) indexForAccountNum:(NSInteger)accountNum;  // returns -1 on failure

//Account Server Settings
+(MCOIMAPSession*) imapSession:(UserSettings*)user;
//+(MCOIMAPSession*) createImapSession:(NSInteger)accountIndex;

//Account Other Settings
+(void) setNotifications:(BOOL)y accountNum:(NSInteger)accountNum;
+(BOOL) notifications:(NSInteger)accountNum;

+(NSUInteger) defaultAccountIndex;
+(void) setDefaultAccountNum:(NSUInteger)accountNum;
+(NSInteger) lastAccountIndex;
+(void) setLastAccountIndex:(NSInteger)accountIndex;

+(NSNumber*) lastFolderIndex;
+(void) setLastFolderIndex:(NSNumber*)accountIndex;

+(void) setSettingsWithAccountVal:(MCOAccountValidator*)accountVal user:(UserSettings*)user;

+(NSInteger) inboxUnread:(NSInteger)accountIndex;
+(void) setInboxUnread:(NSInteger)value accountIndex:(NSInteger)accountIndex;

@end
