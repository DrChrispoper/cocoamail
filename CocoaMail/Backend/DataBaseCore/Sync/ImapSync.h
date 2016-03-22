//
//  ImapSync.h
//  CocoaMail
//
//  Created by Christopher Hockley on 20/01/2012.
//  Copyright (c) 2012 Christopher Hockley. All rights reserved.

#import <MailCore/MailCore.h>
#import "Persons.h"

@class RACSignal;
@class UserSettings;

@interface ImapSync : NSObject <MCOHTMLRendererIMAPDelegate>

@property (nonatomic, strong) NSMutableArray* cachedData;
@property (nonatomic, strong) MCOIMAPSession* imapSession;
@property (nonatomic) BOOL connected;
@property (nonatomic) dispatch_queue_t s_queue;

+(ImapSync*) sharedServices:(UserSettings*)user;
+(NSArray*) allSharedServices:(MCOIMAPSession*)updated;
+(RACSignal*) doLogin:(UserSettings*)user;

-(RACSignal*) runFolder:(NSInteger)folder fromStart:(BOOL)isFromStart fromAccount:(BOOL)getAll;
-(RACSignal*) runSearchText:(NSString*)text;
-(RACSignal*) runSearchPerson:(Person*)person;
-(void) runUpToDateTest:(NSArray*)convs folderIndex:(NSInteger)folderIdx completed:(void (^)(NSArray* dels, NSArray* ups))completedBlock;
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