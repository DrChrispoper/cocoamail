//
//  Accounts.h
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 11/08/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "Persons.h"
#import "Mail.h"
#import "AppSettings.h"
#import "MailListViewController.h"

@class Conversation;
@class Account;
@class Mail;
@protocol MailListDelegate;


@interface Accounts : NSObject

+(Accounts*) sharedInstance;

+(NSArray*) systemFolderIcons;
+(NSString*) userFolderIcon;

@property (nonatomic) BOOL navBarBlurred;

@property (nonatomic, readonly) QuickSwipeType quickSwipeType;
@property (nonatomic, readonly) NSInteger defaultAccountIdx;

-(void) setDefaultAccountIdx:(NSInteger)defaultAccountIdx;
-(void) setQuickSwipeType:(QuickSwipeType)quickSwipeType;

@property (nonatomic) NSInteger currentAccountIdx;

-(Account*) currentAccount;
-(NSArray*) accounts;
-(Account*) getAccount:(NSInteger)accountIndex;
-(NSInteger) accountsCount;
-(void) addAccount:(Account*)account;
-(BOOL) deleteAccount:(Account*)account;
-(Conversation*) conversationForCI:(ConversationIndex*)conversationIndex;
-(NSInteger) getPersonID:(NSInteger)accountIndex;

@end


@interface Account : NSObject

@property (nonatomic, getter=codeName, setter=setCodeName:) NSString * codeName;
@property (nonatomic, strong) NSString* userMail;
@property (nonatomic, strong) UIColor* userColor;
@property (nonatomic) NSInteger idx;

@property (nonatomic, strong) NSArray* userFolders;
@property (nonatomic) NSInteger currentFolderIdx;
@property (nonatomic) CCMFolderType currentFolderType;
-(void) setCurrentFolder:(CCMFolderType)folder;
-(void) refreshCurrentFolder;
@property (nonatomic, strong) Person* person;

@property (nonatomic) BOOL isAllAccounts;

@property (nonatomic, weak) id<MailListDelegate> mailListSubscriber;

+(instancetype) emptyAccount;

-(void) initContent;
-(void) connect;
-(BOOL) isConnected;
-(void) setConnected:(BOOL)isConnected;
-(void) runTestData;
-(void) releaseContent;
-(void) cancelSearch;

-(NSInteger) favorisCount;
-(NSInteger) draftCount;

-(void) insertRows:(Email*)email;
-(NSUInteger) addConversation:(Conversation*)conv;
-(NSMutableArray*) getConversationsForFolder:(CCMFolderType)type;
-(Conversation*) getConversationForIndex:(NSUInteger)index;
-(BOOL) moveConversationAtIndex:(NSInteger)index from:(CCMFolderType)folderFrom to:(CCMFolderType)folderTo;
-(BOOL) moveConversation:(Conversation*)conversation from:(CCMFolderType)folderFrom to:(CCMFolderType)folderTo;
// return NO if not removed from form folder, YES if really removed
-(void) star:(BOOL)add conversation:(Conversation*)conversation;

-(NSArray*) conversations;

-(void) setName:(NSString*)name;
-(NSInteger) unreadInInbox;

-(void) sendMail:(Mail*)mail bcc:(BOOL)isBcc;
-(void) saveDraft:(Mail*)mail;
-(void) deleteDraft:(Mail*)mail;

-(NSArray*) systemFolderNames;
-(void) deliverUpdate:(NSArray<Email*>*)emails;
-(void) deliverDelete:(NSArray<Email*>*)emails;

-(void) doPersonSearch:(Person*)person;
-(void) doTextSearch:(NSString*)searchString;

-(void) localFetchMore:(BOOL)loadMore;

-(void) showProgress;

@end
