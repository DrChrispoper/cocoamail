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

@class Conversation;
@class Account;
@class Mail;

@interface Accounts : NSObject

+(Accounts*) sharedInstance;

+(NSArray*) systemFolderIcons;
+(NSString*) userFolderIcon;

//@property (nonatomic, strong) NSArray* accountColors;
@property (nonatomic) QuickSwipeType quickSwipeType;
@property (nonatomic) BOOL navBarBlurred;

-(NSInteger) defaultAccountIdx;
-(void) setDefaultAccountIdx:(NSInteger)defaultAccountIdx;

@property (nonatomic) BOOL showBadgeCount;
// TODO save these config values
@property (nonatomic) NSInteger currentAccountIdx;

-(Account*) currentAccount;
-(NSArray*) getAllTheAccounts;
-(Account*)getAccount:(NSInteger)accountIndex;
-(NSInteger)accountsCount;
-(void) addAccount:(Account*)account;
-(BOOL) deleteAccount:(Account*)account;

@end

@interface Account : NSObject

@property (nonatomic, getter=codeName, setter=setCodeName:) NSString* codeName;
@property (nonatomic, strong) NSString* userMail;
@property (nonatomic, strong) UIColor* userColor;
@property (nonatomic) NSInteger idx;

@property (nonatomic, strong) NSArray* userFolders;
@property (nonatomic) NSInteger currentFolderIdx;
-(void) setCurrentFolder:(CCMFolderType)folder;
@property (nonatomic, strong) Person* person;

@property (nonatomic) BOOL isAllAccounts;
//
@property (nonatomic) BOOL notificationEnabled;
// TODO save it (config)

+(instancetype) emptyAccount;

-(void) initContent;
-(void) connect;
-(void) releaseContent;

-(void) insertRows:(Email *)email;
-(void) addConversation:(Conversation*)conv;
-(NSMutableArray*) getConversationsForFolder:(CCMFolderType)type;
-(BOOL) moveConversation:(Conversation*)conversation from:(CCMFolderType)folderFrom to:(CCMFolderType)folderTo;
// return NO if not removed from form folder, YES if really removed

-(NSInteger) unreadInInbox;

-(void) sendMail:(Mail*)mail bcc:(BOOL)isBcc;
-(void) saveDraft:(Mail*)mail;
-(void) deleteDraft:(Mail*)mail;

-(NSArray*) systemFolderNames;

@end
