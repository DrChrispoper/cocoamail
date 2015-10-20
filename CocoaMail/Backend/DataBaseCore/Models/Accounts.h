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
-(NSArray*) getAllTheAccounts;
-(Account*) getAccount:(NSInteger)accountIndex;
-(NSInteger) accountsCount;
-(void) addAccount:(Account*)account;
-(BOOL) deleteAccount:(Account*)account;


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
@property (nonatomic, strong) Person* person;

@property (nonatomic) BOOL isAllAccounts;
//
@property (nonatomic) BOOL notificationEnabled;
// TODO save it (config)

@property (nonatomic, weak) id<MailListDelegate> mailListSubscriber;

+(instancetype) emptyAccount;

-(void) initContent;
-(void) connect;
-(void) runTestData;
-(void) releaseContent;

-(NSInteger) favorisCount;
-(NSInteger) draftCount;

-(void) insertRows:(Email*)email;
-(void) addConversation:(Conversation*)conv;
-(NSMutableArray*) getConversationsForFolder:(CCMFolderType)type;
-(BOOL) moveConversation:(Conversation*)conversation from:(CCMFolderType)folderFrom to:(CCMFolderType)folderTo;
// return NO if not removed from form folder, YES if really removed
-(void) star:(BOOL)add conversation:(Conversation*)conversation;

-(void) setName:(NSString*)name;
-(NSInteger) unreadInInbox;

-(void) sendMail:(Mail*)mail bcc:(BOOL)isBcc;
-(void) saveDraft:(Conversation*)mail;
-(void) deleteDraft:(Conversation*)mail;

-(NSArray*) systemFolderNames;
-(void) deliverUpdate:(NSArray<Email*>*)emails;
-(void) deliverDelete:(NSArray<Email*>*)emails;


@end
