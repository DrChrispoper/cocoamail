//
//  ImapSync.h
//  CocoaMail
//
//  Created by Christopher Hockley on 20/01/2012.
//  Copyright (c) 2012 Christopher Hockley. All rights reserved.

#import <MailCore/MailCore.h>
#import "Persons.h"
#import "Mail.h"
#import "CCMConstants.h"

// CocoaMail Error Domain and Errors
#define CCMErrorDomain          @"com.cocoasoft.cocoamail"
#define CCMConnectionError      9000
#define CCMAllSyncedError       9001
#define CCMFolderSyncedError    9002
#define CCMCredentialsError     9003
#define CCMNoSharedServiceError 9009
#define CCMDeletedError         9004
#define CCMFolderPathError      9005
#define CCMSyncMgrError         9006


@class RACSignal;
@class UserSettings;
@class Conversation;

@interface ImapSync : NSObject <MCOHTMLRendererIMAPDelegate>

@property (nonatomic, strong) MCOIMAPSession* imapSession;
@property (nonatomic) BOOL connected;
@property (nonatomic, strong) RACSignal* signal;
@property (nonatomic) dispatch_queue_t s_queue;

+(ImapSync*) sharedServices:(UserSettings*)user;
+(NSArray<ImapSync*>*) allSharedServices:(MCOIMAPSession*)update;
+(RACSignal*) doLogin:(UserSettings*)user;

// TODO: These are probably better off elsewhere
+(BOOL)isRunningInForeground;
+(BOOL)isRunningInBackground;

+(NSString *)displayNameForFolder:(MCOIMAPFolder *)folder usingSession:(MCOIMAPSession*)imapSession;

-(void)addFolder:(MCOIMAPFolder *)folder withName:(NSString*)folderName toAccount:(NSUInteger)accountNum;


-(RACSignal*) loadImapMessagesIntoDatabaseForFolder:(NSInteger)folder fromStart:(BOOL)isFromStart gettingAll:(BOOL)getAll;
-(RACSignal*) runSearchText:(NSString*)text;
-(RACSignal*) runSearchPerson:(Person*)person;
-(void) updateLocalMailFromImapServerInConversations:(NSArray<Conversation*>*)convs ofFolder:(NSInteger)folderIdx completed:(void (^)(NSArray<NSString*>* days))completedBlock;
//-(void) runUpToDateCachedTest:(NSArray*)data;
-(void) saveCachedData;
+(void) deletedAndWait:(UserSettings*)deleteUser;
//+(void) runInboxUnread:(UserSettings*)user;
-(void) cancel;
+(void) getInboxUnreadCountForUser:(UserSettings*)user completed:(void (^)(void))completedBlock;
//+(void) runUnreadCount:(UserSettings*)user folder:(CCMFolderType)folder completed:(void (^)(void))completedBlock;


//-(NSMutableSet*) emailIDs;
//-(void) newOAuthSet;

+(BOOL) canFullSync;

@end
