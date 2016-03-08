//
//  Mail.h
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 16/07/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import <MailCore/MailCore.h>
#import "FMDB.h"
#import "UidEntry.h"
#import "FMDatabase.h"
#import "Attachments.h"

@class UserSettings;
@class Draft;

static NSString* kQueryAll = @"SELECT email.pk, email.datetime, email.sender, email.tos, email.ccs, email.bccs, email.msg_id, email.html_body, email.flag, search_email.subject, search_email.body FROM email, search_email WHERE email.msg_id = search_email.msg_id";

static NSString* kQueryAllMsgID = @"SELECT email.pk, email.datetime, email.sender, email.tos, email.ccs, email.bccs, email.msg_id, email.html_body, email.flag, search_email.subject, search_email.body FROM email, search_email WHERE email.msg_id = search_email.msg_id AND search_email.msg_id = ?";

static NSString* kQueryPk = @"SELECT email.pk, email.datetime, email.sender, email.tos, email.ccs, email.bccs, email.msg_id, email.html_body, email.flag, search_email.subject, search_email.body FROM email, search_email WHERE email.msg_id = search_email.msg_id AND email.pk = ? LIMIT 1;";

static NSString* kQuerySearch = @"SELECT email.pk, email.datetime, email.sender, email.tos, email.ccs, email.bccs, email.msg_id, email.html_body, email.flag, search_email.subject, search_email.body FROM email, search_email WHERE email.msg_id = search_email.msg_id AND search_email MATCH ? ORDER BY email.datetime DESC;";

static NSString* kQueryThread = @"SELECT email.pk, email.datetime, email.sender, email.tos, email.ccs, email.bccs, email.msg_id, email.html_body, email.flag, search_email.subject, search_email.body FROM email, search_email WHERE email.msg_id = search_email.msg_id AND search_email.msg_id MATCH '";

static NSString* kQueryDelete = @"DELETE FROM email WHERE email.msg_id = ?";

@interface Mail : NSObject <NSCopying>

@property (assign) NSInteger pk;

@property (nonatomic, readwrite, strong) NSDate* datetime;
@property (nonatomic, strong) NSString* day;
@property (nonatomic, strong) NSString* hour;

@property (nonatomic, readwrite, strong) MCOAddress* sender;
@property (nonatomic, readwrite, copy) NSArray<MCOAddress*>* tos;
@property (nonatomic, readwrite, copy) NSArray<MCOAddress*>* ccs;
@property (nonatomic, readwrite, copy) NSArray<MCOAddress*>* bccs;
@property (nonatomic) NSInteger fromPersonID;
@property (nonatomic, readwrite, strong) NSArray* toPersonIDs;

@property (nonatomic, strong) NSString* transferContent;
@property (nonatomic, strong) Mail* fromMail;

@property (nonatomic, readwrite, copy) NSString* htmlBody;
@property (nonatomic, readwrite, copy) NSString* msgID;
@property (nonatomic, readwrite) MCOMessageFlag flag;

//search
@property (nonatomic, readwrite, copy) NSString* subject;
@property (nonatomic, readwrite, copy) NSString* body;

//ToFetch
@property (nonatomic, readwrite, copy) NSArray* attachments;
@property (nonatomic, readwrite, copy) NSArray<UidEntry*>* uids;


-(BOOL) hasAttachments;

-(void) loadData;
-(BOOL) existsLocally;
-(UserSettings*) user;
-(UidEntry*) uidEWithFolder:(NSInteger)folderNum;
-(NSString*) sonID;
-(BOOL) haveSonInFolder:(NSInteger)folderIdx;
-(NSArray*) getSons;
-(void) fetchAllAttachments;
-(void) loadBody;
-(BOOL) isInMultipleAccounts;
-(Mail*) secondAccountDuplicate;

-(void) moveFromFolder:(NSInteger)fromFolderIdx ToFolder:(NSInteger)toFolderIdx;
-(void) trash;
-(BOOL) isFav;
-(BOOL) isRead;
-(void) toggleFav;
-(void) toggleRead;

-(Mail*) replyMail:(BOOL)replyAll;
-(Mail*) transfertMail;
-(NSData*) rfc822DataWithAccountIdx:(NSInteger)idx isBcc:(BOOL)isBcc;

-(BOOL) isEqualToMail:(Mail*)mail;

+(void) tableCheck;
+(void) tableCheck:(FMDatabase*)db;

+(Mail*) getMailWithMsgId:(NSString*)msgIdDel dbNum:(NSInteger)dbNum;
+(NSMutableArray*) getMails;
+(Mail*) resToMail:(FMResultSet*)result;

+(void) clean:(Mail*)mail;
+(NSInteger) insertMail:(Mail*)mail;
+(void) updateMail:(Mail*)mail;
+(BOOL) removeMail:(NSString*)msgIdDel;

+(NSInteger) isTodayOrYesterday:(NSString*)dateString;
+(Mail*) newMailFormCurrentAccount;
+(Mail*) mailWithMCOIMAPMessage:(MCOIMAPMessage*)msg inFolder:(NSInteger)folder andAccount:(NSInteger)accountNum;
+(Mail*) mailWithDraft:(Draft*)draft;

-(Draft*) toDraft;

@end

