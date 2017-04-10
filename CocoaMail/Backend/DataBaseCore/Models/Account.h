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
#import "CCMConstants.h"

//@class Conversation;
//@class Mail;
@class Draft;

@protocol MailListDelegate;

@interface Account : NSObject

-(NSUInteger) idx;               // Account index
-(UserSettings*) user;
-(void) setNewUser:(UserSettings*)user;

@property (nonatomic, strong) NSArray* userFolders; // Array of {folder name, name contains "/"}
@property (nonatomic) NSUInteger currentFolderIdx;
@property (nonatomic) NSInteger isSendingOut;
@property (nonatomic) CCMFolderType currentFolderType;
-(void) setCurrentFolder:(CCMFolderType)folder;
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
-(NSMutableArray<ConversationIndex*>*) getConversationsForFolder:(CCMFolderType)type;
-(Conversation*) getConversationForIndex:(NSUInteger)index;
-(BOOL) moveConversationAtIndex:(NSUInteger)index from:(CCMFolderType)folderFrom to:(CCMFolderType)folderTo updateUI:(BOOL)updateUI;
-(BOOL) moveConversation:(Conversation*)conversation from:(CCMFolderType)folderFrom to:(CCMFolderType)folderTo updateUI:(BOOL)updateUI;
-(void) star:(BOOL)add conversation:(Conversation*)conversation;

-(NSMutableArray<Conversation*>*) conversations;

-(void) sendDraft:(Draft*)draft to:(NSArray *)toPersonIDs;
-(void) deleteDraft:(Draft*)draft;
-(void) addLocalDraft:(Draft*)draft;

-(NSArray*) systemFolderNames;      // System Folder Names
-(NSArray*) userFolderNames;

-(void) deliverUpdate:(NSArray<Mail*>*)emails;
-(void) deliverDelete:(NSArray<Mail*>*)emails fromFolder:(CCMFolderType)folderFrom;
-(BOOL) deleteIndex:(NSInteger)index fromFolder:(CCMFolderType)folderFrom;

-(void) doPersonSearch:(Person*)person;
-(void) doTextSearch:(NSString*)searchString;

-(void) localFetchMore:(BOOL)loadMore;

-(NSString *) description;
-(NSString *) folderDescription:(CCMFolderType)folderType;
-(NSString *) currentFolderTypeValue;
-(NSString *) baseFolderType:(BaseFolderType)folderType;


@end
