//
//  ImapSync.h
//  CocoaMail
//
//  Created by Christopher Hockley on 20/01/2012.
//  Copyright (c) 2012 Christopher Hockley. All rights reserved.

#import <MailCore/MailCore.h>
#import "Persons.h"

@class RACSignal;


@interface ImapSync : NSObject <MCOHTMLRendererIMAPDelegate>

@property (nonatomic, strong) NSMutableArray* cachedData;
@property (nonatomic, strong) MCOIMAPSession* imapSession;
@property (nonatomic) BOOL connected;

//+(ImapSync*) sharedServices;
+(ImapSync*) sharedServices:(NSInteger)accountNum;
+(NSArray*) allSharedServices:(MCOIMAPSession*)updated;
+(RACSignal*) doLogin:(NSInteger)account;

-(RACSignal*) runFolder:(NSInteger)folder fromStart:(BOOL)isFromStart fromAccount:(BOOL)getAll;
-(RACSignal*) runSearchText:(NSString*)text;
-(RACSignal*) runSearchPerson:(Person*)person;
-(void) runUpToDateTest:(NSArray*)convs folderIndex:(NSInteger)folderIdx completed:(void (^)(NSArray* dels, NSArray* ups))completedBlock;
-(void) runUpToDateCachedTest:(NSArray*)data;
-(void) saveCachedData;
+(void) deleted;
+(void) runInboxUnread:(NSInteger)accountIndex;
-(void) cancel;

-(NSMutableSet*) emailIDs;

+(BOOL) canFullSync;

@end