//
//  Email.h
//  CocoaMail
//
//  Created by Christopher Hockley on 20/01/2012.
//  Copyright (c) 2012 Christopher Hockley. All rights reserved.
//

#import <MailCore/MailCore.h>
#import "FMDB.h"
#import "UidEntry.h"
#import "FMDatabase.h"

static NSString* kQueryAll = @"SELECT email.pk, email.datetime, email.sender, email.tos, email.ccs, email.bccs, email.msg_id, email.html_body, email.flag, search_email.subject, search_email.body FROM email, search_email WHERE email.msg_id = search_email.msg_id";

static NSString* kQueryAllMsgID = @"SELECT email.pk, email.datetime, email.sender, email.tos, email.ccs, email.bccs, email.msg_id, email.html_body, email.flag, search_email.subject, search_email.body FROM email, search_email WHERE email.msg_id = search_email.msg_id AND search_email.msg_id = ?";

static NSString* kQueryPk = @"SELECT email.pk, email.datetime, email.sender, email.tos, email.ccs, email.bccs, email.msg_id, email.html_body, email.flag, search_email.subject, search_email.body FROM email, search_email WHERE email.msg_id = search_email.msg_id AND email.pk = ? LIMIT 1;";

static NSString* kQuerySearch = @"SELECT email.pk, email.datetime, email.sender, email.tos, email.ccs, email.bccs, email.msg_id, email.html_body, email.flag, search_email.subject, search_email.body FROM email, search_email WHERE email.msg_id = search_email.msg_id AND search_email MATCH ? ORDER BY email.datetime DESC;";

static NSString* kQueryThread = @"SELECT email.pk, email.datetime, email.sender, email.tos, email.ccs, email.bccs, email.msg_id, email.html_body, email.flag, search_email.subject, search_email.body FROM email, search_email WHERE email.msg_id = search_email.msg_id AND search_email.msg_id MATCH '";

static NSString* kQueryDelete = @"DELETE FROM email WHERE email.msg_id MATCH '";

@interface Email : NSObject <NSCopying>

//email
@property (assign, getter=getAccountNum, setter=setAccountNum:) NSInteger accountNum;

@property (assign) NSInteger pk;
@property (nonatomic, readwrite, strong) NSDate* datetime;

@property (nonatomic, readwrite, strong) MCOAddress* sender;

@property (nonatomic, readwrite, copy) NSArray* tos;
@property (nonatomic, readwrite, copy) NSArray* ccs;
@property (nonatomic, readwrite, copy) NSArray* bccs;

@property (nonatomic, readwrite, strong) NSArray* toPersonIDs;

@property (nonatomic, readwrite, copy) NSString* htmlBody;

@property (nonatomic, readwrite, copy) NSString* msgId;
@property (nonatomic, readwrite) MCOMessageFlag flag;

//search
@property (nonatomic, readwrite, copy) NSString* subject;
@property (nonatomic, readwrite, copy) NSString* body;

//ToFetch
@property (nonatomic, readwrite, copy) NSArray* attachments;
@property (nonatomic, readwrite, copy, getter=getUids, setter=setUids:) NSArray * uids;

-(BOOL) hasAttachments;

-(void) loadData;
-(BOOL) existsLocally;
//-(NSInteger)account;
-(UidEntry*) uidEWithFolder:(NSInteger)folderNum;
-(NSString*) getSonID;
-(BOOL) haveSonInFolder:(NSInteger)folderIdx;
-(NSArray*) getSons;
-(void) fetchAllAttachments;
-(void) loadBody;
-(BOOL) isInMultipleAccounts;
//-(void) forActiveAccount;
-(Email*) secondAccountDuplicate;

+(void) tableCheck;
+(void) tableCheck:(FMDatabase*)db;

+(NSMutableArray*) getEmails;
+(Email*) resToEmail:(FMResultSet*)result;

-(void) moveFromFolder:(NSInteger)fromFolderIdx ToFolder:(NSInteger)toFolderIdx;
-(void) trash;
-(void) star;
-(void) read;

+(void) clean:(Email*)email;
+(NSInteger) insertEmail:(Email*)email;
+(void) updateEmail:(Email*)email;
+(BOOL) removeEmail:(NSString*)msgIdDel;

@end


