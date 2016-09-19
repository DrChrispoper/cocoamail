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


@interface Account : NSObject

-(NSInteger) idx;
-(UserSettings*) user;
-(void) setNewUser:(UserSettings*)user;

@property (nonatomic, strong) Folders* imapFolders;

@property (nonatomic) NSInteger isSendingOut;
@property (nonatomic) FolderIndex currentFolderIndex;

-(void) setCurrentFolder:(BaseFolderType)folder;
-(void) refreshCurrentFolder;
@property (nonatomic, strong) Person* person;

@property (nonatomic, weak) id<MailListDelegate> mailListSubscriber;

+(instancetype) emptyAccount;

-(void) initContent;
-(void) connect;
-(BOOL) isConnected;
-(void) setConnected;
-(void) runTestData;
-(void) releaseContent;
-(void) cancelSearch;
-(void) sendOutboxs;

-(NSInteger) favorisCount;
-(NSInteger) draftCount;
-(NSInteger) unreadInInbox;
-(NSInteger) outBoxNb;

-(void) insertRows:(Mail*)email;
-(NSUInteger) addConversation:(Conversation*)conv;
-(NSMutableArray*) getConversationsForFolder:(FolderIndex)folderIndex;
-(Conversation*) getConversationForIndex:(NSUInteger)index;
-(BOOL) moveConversationAtIndex:(NSInteger)index from:(CCMFolderType)folderFrom to:(CCMFolderType)folderTo updateUI:(BOOL)updateUI;
-(BOOL) moveConversation:(Conversation*)conversation from:(CCMFolderType)folderFrom to:(CCMFolderType)folderTo updateUI:(BOOL)updateUI;
-(void) star:(BOOL)add conversation:(Conversation*)conversation;

-(NSArray*) conversations;

-(void) sendDraft:(Draft*)draft to:(NSArray *)toPersonIDs;
-(void) deleteDraft:(Draft*)draft;
-(void) addLocalDraft:(Draft*)draft;

-(NSArray*) systemFolderNames;      // System Folder Names
-(void) deliverUpdate:(NSArray<Mail*>*)emails;
-(void) deliverDelete:(NSArray<Mail*>*)emails fromFolder:(CCMFolderType)folderFrom;
-(BOOL) deleteIndex:(NSInteger)index fromFolder:(CCMFolderType)folderFrom;

-(void) doPersonSearch:(Person*)person;
-(void) doTextSearch:(NSString*)searchString;

-(void) localFetchMore:(BOOL)loadMore;

-(NSString *) description;

@end
