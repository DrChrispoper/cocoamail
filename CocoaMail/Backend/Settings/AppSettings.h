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
#define KEYCHAIN_ITEM_NAME @"CocoaMail iOS"

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

@property (nonatomic, strong) NSMutableArray* users;

+(AppSettings*) getSingleton;

+(NSInteger) numActiveAccounts;

-(UserSettings*) newUser;

//Account Main Settings
+(UserSettings*) userWithIndex:(NSInteger)accountIndex;
+(UserSettings*) userWithNum:(NSInteger)accountNum;
+(UserSettings*) userWithEmail:(NSString*)email;

+(NSInteger) numAccountForIndex:(NSInteger)accountIndex;
+(NSInteger) indexForAccount:(NSInteger)accountNum;

//Account Server Settings
+(MCOIMAPSession*) createImapSession:(NSInteger)accountIndex;

//Account Other Settings
+(void) setNotifications:(BOOL)y accountIndex:(NSInteger)accountIndex;
+(BOOL) notifications:(NSInteger)accountIndex;

+(NSInteger) defaultAccountIndex;
+(void) setDefaultAccountIndex:(NSInteger)accountIndex;
+(NSInteger) lastAccountIndex;
+(void) setLastAccountIndex:(NSInteger)accountIndex;

+(NSNumber*) lastFolderIndex;
+(void) setLastFolderIndex:(NSNumber*)accountIndex;

+(void) setSettingsWithAccountVal:(MCOAccountValidator*)accountVal accountIndex:(NSInteger)accountIndex;

+(NSInteger) inboxUnread:(NSInteger)accountIndex;
+(void) setInboxUnread:(NSInteger)value accountIndex:(NSInteger)accountIndex;

@end
