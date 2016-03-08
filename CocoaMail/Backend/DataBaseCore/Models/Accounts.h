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

@end


@interface Account : NSObject

-(NSInteger) idx;
-(UserSettings*) user;
-(void) setNewUser:(UserSettings*)user;

@property (nonatomic, strong) NSArray* userFolders;
@property (nonatomic) NSInteger currentFolderIdx;
@property (nonatomic) CCMFolderType currentFolderType;
-(void) setCurrentFolder:(CCMFolderType)folder;
-(void) refreshCurrentFolder;
@property (nonatomic, strong) Person* person;

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
-(NSInteger) unreadInInbox;

-(void) insertRows:(Mail*)email;
-(NSUInteger) addConversation:(Conversation*)conv;
-(NSMutableArray*) getConversationsForFolder:(CCMFolderType)type;
-(Conversation*) getConversationForIndex:(NSUInteger)index;
-(BOOL) moveConversationAtIndex:(NSInteger)index from:(CCMFolderType)folderFrom to:(CCMFolderType)folderTo updateUI:(BOOL)updateUI;
-(BOOL) moveConversation:(Conversation*)conversation from:(CCMFolderType)folderFrom to:(CCMFolderType)folderTo updateUI:(BOOL)updateUI;
-(void) star:(BOOL)add conversation:(Conversation*)conversation;

-(NSArray*) conversations;

-(void) sendDraft:(Draft*)draft to:(NSArray *)toPersonIDs;
-(void) deleteDraft:(NSString*)msgID;
-(void) addLocalDraft:(Draft*)draft;

-(NSArray*) systemFolderNames;
-(void) deliverUpdate:(NSArray<Mail*>*)emails;
-(void) deliverDelete:(NSArray<Mail*>*)emails fromFolder:(CCMFolderType)folderFrom;
-(BOOL) deleteIndex:(NSInteger)index fromFolder:(CCMFolderType)folderFrom;

-(void) doPersonSearch:(Person*)person;
-(void) doTextSearch:(NSString*)searchString;

-(void) localFetchMore:(BOOL)loadMore;

-(void) showProgress;

@end
