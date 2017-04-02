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


@class RACSignal;
@class UserSettings;

@interface ImapSync : NSObject <MCOHTMLRendererIMAPDelegate>

@property (nonatomic, strong) NSMutableArray* cachedData;
@property (nonatomic, strong) MCOIMAPSession* imapSession;
@property (nonatomic) BOOL connected;
@property (nonatomic, strong) RACSignal* signal;
@property (nonatomic) dispatch_queue_t s_queue;

+(ImapSync*) sharedServices:(UserSettings*)user;
+(NSArray<ImapSync*>*) allSharedServices:(MCOIMAPSession*)update;
+(RACSignal*) doLogin:(UserSettings*)user;

+(NSString *)displayNameForFolder:(MCOIMAPFolder *)folder usingSession:(MCOIMAPSession*)imapSession;

-(void)addFolder:(MCOIMAPFolder *)folder withName:(NSString*)folderName toAccount:(NSUInteger)accountNum;


-(RACSignal*) runFolder:(NSInteger)folder fromStart:(BOOL)isFromStart gettingAll:(BOOL)getAll;
-(RACSignal*) runSearchText:(NSString*)text;
-(RACSignal*) runSearchPerson:(Person*)person;
-(void) runUpToDateTest:(NSArray*)convs folderIndex:(NSInteger)folderIdx completed:(void (^)(NSArray<Mail*>* dels, NSArray<Mail*>* ups, NSArray<NSString*>* days))completedBlock;
-(void) runUpToDateCachedTest:(NSArray*)data;
-(void) saveCachedData;
+(void) deletedAndWait:(UserSettings*)deleteUser;
//+(void) runInboxUnread:(UserSettings*)user;
-(void) cancel;
+(void) runInboxUnread:(UserSettings*)user completed:(void (^)(void))completedBlock;
+(void) runUnreadCount:(UserSettings*)user folder:(CCMFolderType)folder completed:(void (^)(void))completedBlock;


//-(NSMutableSet*) emailIDs;
//-(void) newOAuthSet;

+(BOOL) canFullSync;

@end
