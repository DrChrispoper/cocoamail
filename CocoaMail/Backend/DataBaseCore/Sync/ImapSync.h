//
//  ImapSync.h
//  CocoaMail
//
//  Created by Christopher Hockley on 20/01/2012.
//  Copyright (c) 2012 Christopher Hockley. All rights reserved.

#import <MailCore/MailCore.h>
#import "Persons.h"

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
+(NSArray<ImapSync*>*) allSharedServices:(MCOIMAPSession*)updated;
+(RACSignal*) doLogin:(UserSettings*)user;

-(RACSignal*) runFolder:(NSInteger)folder fromStart:(BOOL)isFromStart fromAccount:(BOOL)getAll;
-(RACSignal*) runSearchText:(NSString*)text;
-(RACSignal*) runSearchPerson:(Person*)person;
-(void) runUpToDateTest:(NSArray*)convs folderIndex:(NSInteger)folderIdx completed:(void (^)(NSArray* dels, NSArray* ups, NSArray* days))completedBlock;
-(void) runUpToDateCachedTest:(NSArray*)data;
-(void) saveCachedData;
+(void) deletedAndWait:(UserSettings*)deleteUser;
+(void) runInboxUnread:(UserSettings*)user;
-(void) cancel;
+(void) runInboxUnread:(UserSettings*)user completed:(void (^)(void))completedBlock;;

-(NSMutableSet*) emailIDs;
//-(void) newOAuthSet;

+(BOOL) canFullSync;

@end
