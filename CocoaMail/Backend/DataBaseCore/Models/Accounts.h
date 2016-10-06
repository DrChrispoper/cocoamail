//
//  Accounts.h
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 11/08/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "Persons.h"
#import "Mail.h"
#import "AppSettings.h"
#import "MailListViewController.h"
#import "Conversation.h"
#import "Account.h"
#import "Folders.h"

@class Conversation;
@class Account;
@class Mail;
@class Draft;

@protocol MailListDelegate;

@interface Accounts : NSObject

+(Accounts*) sharedInstance;

+(NSArray*) systemFolderIcons;
+(NSString*) userFolderIcon;
+(NSString*) userFolderPadIcon;

@property (nonatomic) BOOL navBarBlurred;

@property (nonatomic, readonly) QuickSwipeType quickSwipeType;
@property (nonatomic, readonly) NSInteger defaultAccountIdx;

-(void) setDefaultAccountIdx:(NSInteger)defaultAccountIdx;
-(void) setQuickSwipeType:(QuickSwipeType)quickSwipeType;

@property (nonatomic) NSInteger currentAccountIdx;

-(Account*) currentAccount;
-(NSArray*) accounts;
-(Account*) account:(NSInteger)accountIndex;
-(NSInteger) accountsCount;
-(void) addAccount:(Account*)account;
-(void) deleteAccount:(Account*)account completed:(void (^)(void))completedBlock;
-(Conversation*) conversationForCI:(ConversationIndex*)conversationIndex;
-(NSInteger) getPersonID:(NSInteger)accountIndex;
-(void) getDrafts;
-(void) appeared;

-(NSString*) description;

@end


