//
//  Mail.m
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 16/07/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "Mail.h"
#import "StringUtil.h"
#import "Persons.h"
#import "Accounts.h"
#import "AppSettings.h"
#import "DateUtil.h"
#import "RegExCategories.h"
#import "GlobalDBFunctions.h"
#import "EmailProcessor.h"
#import "EmailDBAccessor.h"
#import "ImapSync.h"
#import "UserSettings.h"
#import "Draft.h"
#import "sqlite3.h"

#ifdef USING_INSTABUG
#import <Instabug/Instabug.h>
#endif

@implementation Mail {
    UserSettings* _user;
    NSArray<UidEntry*>* _uids;
}


@synthesize pk, htmlBody, msgID,flag;
@synthesize body;
@synthesize attachments;
@synthesize datetime = _datetime;
@synthesize subject = _subject;
@synthesize sender = _sender;
@synthesize tos = _tos;
@synthesize ccs = _ccs;
@synthesize bccs = _bccs;

static NSDateFormatter * s_df_day = nil;
static NSDateFormatter * s_df_hour = nil;


+(void) initialize
{
    s_df_day = [[NSDateFormatter alloc] init];
    s_df_day.dateFormat = @"d MMM yy";
    
    s_df_hour = [[NSDateFormatter alloc] init];
    s_df_hour.dateStyle = NSDateFormatterNoStyle;
    s_df_hour.timeStyle = NSDateFormatterShortStyle;
}

-(Draft*) replyDraft:(BOOL)replyAll
{
    Draft* mail = [Draft newDraftFormCurrentAccount];
    
    mail.subject = self.subject;

    Persons* p = [Persons sharedInstance];
    
    NSInteger currentAccountIndex = [p indexForPerson:[Accounts sharedInstance].currentAccount.person];

    if (replyAll) {
        NSMutableArray* currents = [self.toPersonIDs mutableCopy];
        
        if (currentAccountIndex != self.fromPersonID) {
            [currents addObject:@(self.fromPersonID)];
        }
        
        [currents removeObject:@(currentAccountIndex)];
        
        for (NSNumber* pID in currents) {
            [mail.toPersons addObject:[p getPersonWithID:[pID integerValue]].email];
        }
    }
    else {
        if (currentAccountIndex != self.fromPersonID) {
            [mail.toPersons addObject:[p getPersonWithID:self.fromPersonID].email];
        }
    }
    
    mail.body = @"";
    
    mail.fromMailMsgID = self.msgID;
    
    return mail;
}

-(Draft*) transfertDraft
{
    Draft* draft = [self replyDraft:NO];

    draft.toPersons = [[NSMutableArray alloc]init];
    
    for (Attachment* att in self.attachments) {
        att.msgID = draft.msgID;
        [Attachment addAttachments:@[att]];
    }
    
    Person* from = [[Persons sharedInstance] getPersonWithID:self.fromPersonID];
    NSString* wrote = NSLocalizedString(@"compose-view.content.transfer", @"wrote");
    
    NSDateFormatter* s_df_dayFull = [[NSDateFormatter alloc] init];
    s_df_dayFull.dateFormat = @"d MMM yyyy";
    
    NSRegularExpression* regex = [Rx rx:@"\\s\\r"];
    
    NSString* htmlString = self.htmlBody;
    
    if ([htmlString isMatch:regex]) {
        htmlString = [htmlString replace:regex with:@"\r"];
    }
    
    NSString* oldcontent = [NSString stringWithFormat:@"<br/>Le %@ à %@, %@ %@ :<br/><br/>%@<br/>", [s_df_dayFull stringFromDate:self.datetime] , [s_df_hour stringFromDate:self.datetime], from.name, wrote, htmlString];
    
    draft.transferContent = oldcontent;
    
    draft.fromMailMsgID = @"";
    
    return draft;
}

-(NSData*) rfc822DataWithAccountIdx:(NSInteger)idx isBcc:(BOOL)isBcc
{
    if (!self.htmlBody) {
        self.htmlBody = @"";
    }
    
    MCOMessageBuilder* builder = [[MCOMessageBuilder alloc] init];
    UserSettings* user = [AppSettings userWithIndex:idx];
    [[builder header] setFrom:[MCOAddress addressWithDisplayName:[user name] mailbox:[user username]]];
    
    NSMutableArray* to = [[NSMutableArray alloc] init];
    
    for (NSNumber* personID in self.toPersonIDs) {
        Person* p = [[Persons sharedInstance] getPersonWithID:[personID intValue]];
        MCOAddress* newAddress = [MCOAddress addressWithMailbox:p.email];
        [to addObject:newAddress];
    }
    
    if (!isBcc) {
        [[builder header] setTo:to];
    }
    else {
        [[builder header] setBcc:to];
    }
    
    [builder setHTMLBody:self.htmlBody];

    if (self.fromMail) {
        [[builder header] setReferences:@[self.fromMail.sonID]];
        [[builder header] setInReplyTo: @[self.fromMail.msgID]];
        
        //Not adding the Yuk! :D
        //Person* from = [[Persons sharedInstance] getPersonID:self.fromMail.fromPersonID];
        //NSString* wrote = NSLocalizedString(@"compose-view.content.transfer", @"wrote");
        
        //[builder setHTMLBody:[NSString stringWithFormat:@"%@<br/>%@ %@ :<br/><br/>%@<br/>",self.content, from.name, wrote, self.fromMail.email.htmlBody]];
    }
    
    [[builder header] setSubject:self.subject];
    
    for (Attachment* att in [self attachments]) {
        [builder addAttachment:[MCOAttachment attachmentWithData:att.data filename:att.fileName]];
    }
    
    
    return [builder data];
}


-(NSString *)subject
{
    if (!_subject) {
        _subject = @"";
    }
    
    return _subject;
}

-(void)setSubject:(NSString *)subject
{
    if (!subject) {
        subject = @"";
    }
    
    _subject = [subject replace:RX(@"([Rr][Ee]|[Tt][Rr]|[Ff][Ww][Dd]|[Ff][Ww])\\s??:\\s?") with:@""];
}

-(MCOAddress *)sender
{
    return _sender;
}

-(void)setSender:(MCOAddress *)sender
{
    NSString* name = sender.displayName;
    
    if (!name || [name isEqualToString:@""]) {
        name = sender.mailbox;
    }
    
    NSString* codeName = [name uppercaseString];
    codeName = [codeName stringByReplacingOccurrencesOfString:@" " withString:@""];
    codeName = [codeName substringToIndex:(codeName.length < 3)?codeName.length:3];
    
    _sender = sender;
    
    self.fromPersonID = [[Persons sharedInstance]indexForPerson:[Person createWithName:name email:sender.mailbox icon:nil codeName:codeName]];
}

-(NSArray *)tos
{
    if (!_tos){
        _tos = [[NSArray alloc] init];
    }
    
    return _tos;
}

-(NSArray *)ccs
{
    if (!_ccs){
        _ccs = [[NSArray alloc] init];
    }
    
    return _ccs;
}

-(NSArray *)bccs
{
    if (!_bccs){
        _bccs = [[NSArray alloc] init];
    }
    
    return _bccs;
}

-(void)setTos:(NSArray *)tos
{
    _tos = tos;
    
    [self _setToPID];
}

-(void)setCcs:(NSArray *)ccs
{
    _ccs = ccs;
    [self _setToPID];
}

-(void)setBccs:(NSArray *)bccs
{
    _bccs = bccs;
    [self _setToPID];
}

-(void) _setToPID
{
    NSArray* tmp = [NSMutableArray arrayWithArray:_tos];
    tmp = [tmp arrayByAddingObjectsFromArray:_ccs];
    tmp = [tmp arrayByAddingObjectsFromArray:_bccs];

    NSMutableArray* ids = [[NSMutableArray alloc]initWithCapacity:tmp.count];

    for (MCOAddress* ad in tmp) {
        
        NSString* name = ad.displayName;
        
        if (!name || [name isEqualToString:@""]) {
            name = ad.mailbox;
        }
        
        NSString* codeName = [name uppercaseString];
        codeName = [codeName stringByReplacingOccurrencesOfString:@" " withString:@""];
        codeName = [codeName substringToIndex:(codeName.length < 3)?codeName.length:3];
        
        [ids addObject:@([[Persons sharedInstance] addPerson:[Person createWithName:name email:ad.mailbox icon:nil codeName:codeName]])];
    }

    self.toPersonIDs = ids;
}

-(NSDate *)datetime
{
    return _datetime;
}

-(void)setDatetime:(NSDate *)datetime
{
    _datetime = datetime;
    
    self.day = [s_df_day stringFromDate:datetime];
    self.hour = [s_df_hour stringFromDate:datetime];
}

-(BOOL) isFav
{
    return (self.flag & MCOMessageFlagFlagged);
}

-(BOOL) isRead
{
    return (self.flag & MCOMessageFlagSeen);
}

+(NSInteger) isTodayOrYesterday:(NSString*)dateString
{
    NSDate* today = [NSDate date];
    NSString* todayS = [s_df_day stringFromDate:today];
    
    if ([dateString isEqualToString:todayS]) {
        return 0;
    }
    
    NSDate* yesterday = [today dateByAddingTimeInterval:- 60 * 60 * 24];
    NSString* yesterdayS = [s_df_day stringFromDate:yesterday];
    
    if ([dateString isEqualToString:yesterdayS]) {
        return -1;
    }
    
    return 1;
}

+(Mail*) newMailFormCurrentAccount
{
    Mail* mail = [[Mail alloc] init];
    
    Accounts* allAccounts = [Accounts sharedInstance];
    
    if (allAccounts.currentAccount.user.isAll) {
        mail.fromPersonID = -(1 + [Accounts sharedInstance].defaultAccountIdx);
        
        UidEntry* uid_entry = [[UidEntry alloc]init];
        uid_entry.uid = 0;
        uid_entry.accountNum = [AppSettings userWithIndex:[Accounts sharedInstance].defaultAccountIdx].accountNum;//self.currentUser.accountNum;
        
        mail.uids = [NSMutableArray arrayWithArray:@[uid_entry]];
    }
    else {
        mail.fromPersonID = -(1 + [Accounts sharedInstance].currentAccountIdx);
        
        UidEntry* uid_entry = [[UidEntry alloc]init];
        uid_entry.uid = 0;
        uid_entry.accountNum = [AppSettings userWithIndex:[Accounts sharedInstance].defaultAccountIdx].accountNum;//self.currentUser.accountNum;
        
        mail.uids = [NSMutableArray arrayWithArray:@[uid_entry]];
    }
    
    return mail;
}

+(Mail*) mailWithMCOIMAPMessage:(MCOIMAPMessage*)msg inFolder:(NSInteger)folder andAccount:(NSInteger)accountNum
{
    Mail* email = [[Mail alloc] init];
    
    if (!msg.header.from.displayName) {
        msg.header.from = [MCOAddress addressWithDisplayName:[msg.header.from.mailbox componentsSeparatedByString:@"@"].firstObject mailbox:msg.header.from.mailbox];
    }
    
    email.sender = msg.header.from;
    email.subject = msg.header.subject;
    
    if (!email.subject) {
        email.subject = @"";
    }
    
    email.body = @"";
    email.htmlBody = @"";
    
    email.datetime = msg.header.receivedDate;
    email.msgID = msg.header.messageID;
    
    email.tos = msg.header.to;
    
    if (!email.tos) {
        email.tos = [[NSArray alloc]init];
    }
    email.ccs = msg.header.cc;
    
    if (!email.ccs) {
        email.ccs = [[NSArray alloc]init];
    }
    email.bccs = msg.header.bcc;
    
    if (!email.bccs) {
        email.bccs = [[NSArray alloc]init];
    }
    email.flag = msg.flags;
    
    UidEntry* uid_entry = [[UidEntry alloc]init];
    uid_entry.uid = msg.uid;
    uid_entry.folder = folder;
    uid_entry.accountNum = accountNum;
    uid_entry.msgID = email.msgID;
    uid_entry.dbNum = [EmailProcessor dbNumForDate:email.datetime];
    
    if (msg.gmailThreadID) {
        uid_entry.sonMsgID = [NSString stringWithFormat:@"%llu", msg.gmailThreadID];
    }
    else if(msg.header.references) {
        uid_entry.sonMsgID = msg.header.references[0];
    }
    else {
        uid_entry.sonMsgID = @"0";
    }
    
    DDLogDebug(@"\nEmail subj=\"%@\"\nmsgID=\"%@\" has %ld references.\nson ID ref \"%@\"",
               msg.header.subject,
               msg.header.messageID,
               (long)msg.header.references.count,
               uid_entry.sonMsgID);
    
    email.uids = [[NSMutableArray arrayWithArray:email.uids] arrayByAddingObject:uid_entry];
    
    NSMutableArray* atts = [[NSMutableArray alloc] initWithCapacity:msg.attachments.count + msg.htmlInlineAttachments.count];
    
    for (MCOAbstractPart* part in msg.attachments) {
        if([part isKindOfClass:[MCOIMAPPart class]]) {
            MCOIMAPPart* imapPart = (MCOIMAPPart*)part;
            
            Attachment* at = [[Attachment alloc]init];
            at.mimeType = part.mimeType;
            at.msgID = email.msgID;
            at.fileName = part.filename;
            if ([at.fileName isEqualToString:@""]) {
                at.fileName = [NSString stringWithFormat:@"No name - %@",email.subject];
            }
            at.partID = imapPart.partID;
            at.size = imapPart.size;
            at.contentID = @"";
            [atts addObject:at];
        }
        else if([part isKindOfClass:[MCOIMAPMultipart class]]) {
            MCOIMAPMultipart* imapParts = (MCOIMAPMultipart*)part;
            
            NSMutableString* string = [NSMutableString new];
            
            for (MCOIMAPPart* imapPart in imapParts.parts) {
                if (imapPart.filename) {
                    [string appendString:imapPart.filename];
                }
            }
        }
    }
    
    for (MCOAbstractPart* part in msg.htmlInlineAttachments) {
        if([part isKindOfClass:[MCOIMAPPart class]]) {
            MCOIMAPPart* imapPart = (MCOIMAPPart*)part;
            
            Attachment* at = [[Attachment alloc]init];
            at.mimeType = part.mimeType;
            at.msgID = email.msgID;
            at.fileName = part.filename;
            if ([at.fileName isEqualToString:@""]) {
                at.fileName = part.contentID;
            }
            at.partID = imapPart.partID;
            at.size = imapPart.size;
            at.contentID = part.contentID;
            [atts addObject:at];
        }
        else if([part isKindOfClass:[MCOIMAPMultipart class]]) {
            MCOIMAPMultipart* imapParts = (MCOIMAPMultipart*)part;
            
            NSMutableString* string = [NSMutableString new];
            
            for (MCOIMAPPart* imapPart in imapParts.parts) {
                if (imapPart.filename) {
                    [string appendString:imapPart.filename];
                }
            }
            
            
        }
    }
    
    email.attachments = atts;

    return email;
}

+(Mail*) mailWithDraft:(Draft*)draft
{
    Mail* email = [[Mail alloc] init];
    
    UserSettings* user = [AppSettings userWithNum:draft.accountNum];
    
    email.sender = [MCOAddress addressWithDisplayName:user.linkedAccount.person.name mailbox:user.linkedAccount.person.email];
    email.subject = draft.subject;
    
    if (!email.subject) {
        email.subject = @"";
    }
    
    email.body = draft.body;
    email.htmlBody = draft.body;
    
    email.datetime = draft.datetime;
    email.msgID = draft.msgID;
    
    NSMutableArray* toMCOAdressS = [[NSMutableArray alloc] init];
    
    for (NSString* ad in draft.toPersons) {
        [toMCOAdressS addObject:[MCOAddress addressWithMailbox:ad]];
    }
    
    if (draft.isBcc) {
        email.bccs = toMCOAdressS;
    }
    else {
        email.tos = toMCOAdressS;
    }
    
    if (!email.tos) {
        email.tos = [[NSArray alloc]init];
    }
    
    if (!email.ccs) {
        email.ccs = [[NSArray alloc]init];
    }
    
    if (!email.bccs) {
        email.bccs = [[NSArray alloc]init];
    }
    
    email.transferContent = draft.transferContent;
    
    if (draft.fromMailMsgID) {
        NSArray* uids = [UidEntry getUidEntriesWithMsgId:draft.fromMailMsgID];
    
        for (UidEntry* e in uids) {
            email.fromMail = [Mail getMailWithMsgId:e.msgID dbNum:e.dbNum];
            break;
        }
    }
    
    if ([RX(@"^[0-9]+?$") isMatch:draft.msgID]) {

        UidEntry* uid_entry = [[UidEntry alloc]init];
        uid_entry.uid = 0;
        uid_entry.folder = [user numFolderWithFolder:FolderTypeWith(FolderTypeDrafts, 0)];
        uid_entry.accountNum = draft.accountNum;
        uid_entry.msgID = email.msgID;
        uid_entry.dbNum = [EmailProcessor dbNumForDate:email.datetime];
        
        uid_entry.sonMsgID = @"0";
    
        email.uids = [[NSMutableArray arrayWithArray:email.uids] arrayByAddingObject:uid_entry];
    }
    else {
        email.uids = [UidEntry getUidEntriesWithMsgId:draft.msgID];
    }
    
    
    [email user];

    email.attachments = [draft attachments];
    
    email.flag = MCOMessageFlagSeen;
    
    return email;
}

-(BOOL) isEqualToMail:(Mail*)mail
{
    if (!mail) {
        return NO;
    }
    
    return [self.msgID isEqualToString:mail.msgID];
}

-(BOOL) isEqual:(id)object
{
    if (self == object) {
        return YES;
    }
    
    if (![object isKindOfClass:[Mail class]]) {
        return NO;
    }
    
    return [self isEqualToMail:(Mail*)object];
}

-(void) loadData
{
    FMDatabaseQueue* queue = [FMDatabaseQueue databaseQueueWithPath:[StringUtil filePathInDocumentsDirectoryForFileName:[GlobalDBFunctions dbFileNameForNum:[EmailProcessor dbNumForDate:self.datetime]]]];
    
    [queue inDatabase:^(FMDatabase* db) {
        FMResultSet* results = [db executeQuery:kQueryPk, @(self.pk)];
        
        if ([results next]) {
            [Mail _res:results toMail:self];
        }
    }];
}

-(BOOL) existsLocally
{
    return self.uids.count > 0 ;
}

-(NSArray*) uids
{
    if (!_uids) {
        _uids = [UidEntry getUidEntriesWithMsgId:self.msgID];
    }
    
    return _uids;
}

-(void) setUids:(NSArray<UidEntry *> *)uids
{
    _uids = uids;
}

-(NSString*) sonID // returns first UID's son Msg ID, or @"" (empty string)
{
    UidEntry *firstUID = [self getFirstUIDE]; // value or nil
    
    if ( firstUID ) {
        return firstUID.sonMsgID;
    }
    
    return @"";
}

// If there is at least one UID in the UID array, then return UID[0]
// If there is not, then return nil.
-(UidEntry*) getFirstUIDE
{
    if (self.uids.count > 0) {
        return self.uids[0];
    }
    
    return nil;
}

-(BOOL) haveSonInFolder:(NSInteger)folderIdx
{
    for (UidEntry* uidE in [self getSons]) {
        if (uidE.folder == folderIdx) {
            return YES;
        }
    }
    
    return NO;
}

-(NSArray*) getSons
{
    NSString* son = [self sonID];
    
    NSMutableArray* sonsTemp;
    NSMutableArray* sons = [[NSMutableArray alloc]init];
    
    if ([son isEqualToString:@"0"]) {
        sonsTemp = [UidEntry getUidEntriesWithThread:self.msgID];
    }
    else {
        sonsTemp = [UidEntry getUidEntriesWithThread:son];
    }
    
    for (UidEntry* e in sonsTemp) {
        if (![e.msgID isEqualToString:self.msgID]) {
            [sons addObject:e];
        }
    }
    
    return sons;
}

-(void) loadBody
{
    FMDatabaseQueue* queue = [FMDatabaseQueue databaseQueueWithPath:[StringUtil filePathInDocumentsDirectoryForFileName:[GlobalDBFunctions dbFileNameForNum:[EmailProcessor dbNumForDate:self.datetime]]]];
    
    [queue inDatabase:^(FMDatabase* db) {
        
        FMResultSet* results = [db executeQuery:kQueryAllMsgID, self.msgID];
        
        if ([results next]) {
            Mail* email = [Mail resToMail:results];
            self.pk = email.pk;
            self.body = email.body;
            self.htmlBody = email.htmlBody;
            
        }
        
        [results close];
        
        
        if ([db hadError] && [db lastErrorCode] == 1) {
            DDLogInfo(@"Checking table");
            [Mail tableCheck:db];
        }
    }];
}

-(void) fetchAllAttachments
{
    self.attachments = [CCMAttachment getAttachmentsWithMsgID:self.msgID];
}

-(UserSettings*) user
{
    if (!_user) {
        _user = [AppSettings userWithNum:[self getFirstUIDE].accountNum];
    }
    
//    if (!_user) {
//        DDLogError(@"WHAT!NOOOOOOOOOOOOOOOOOOOOOOOOOOOOOO");
//    }
    
    return _user;
}

-(BOOL) isInMultipleAccounts
{
    for (UidEntry* e in self.uids) {
        if (self.user.accountNum != e.accountNum) {
            return YES;
        }
    }
    
    return NO;
}

-(Mail*) secondAccountDuplicate
{
    Mail* emailTwo = [self copy];
    
    NSMutableArray<UidEntry* >* uidsOne = [[NSMutableArray alloc]init];
    NSMutableArray<UidEntry* >* uidsTwo = [[NSMutableArray alloc]init];
    
    for (UidEntry* e in self.uids) {
        if (e.accountNum == self.user.accountNum) {
            [uidsOne addObject:e];
        }
        else {
            [uidsTwo addObject:e];
        }
    }
    
    self.uids = uidsOne;
    
    emailTwo.uids = uidsTwo;
    
    return emailTwo;
}

-(UidEntry*) uidEWithFolder:(NSInteger)folderNum
{
    if (folderNum == -1) {
        folderNum = 0;
    }

    for (UidEntry* uidE in self.uids) {
        if (uidE.folder == folderNum) {
            return uidE;
        }
    }
    
    return nil;
}

-(BOOL)isInFolder:(NSInteger)folderNum
{
    return [self uidEWithFolder:folderNum] > 0;
}

+(void) tableCheck
{
    [[EmailDBAccessor sharedManager].databaseQueue inDatabase:^(FMDatabase* db) {
        [Mail tableCheck:db];
    }];
}

+(void) tableCheck:(FMDatabase*)db
{
    DDLogDebug(@"+[Mail tableCheck:(FMDatabase *)]");
    
    if (![db executeUpdate:@"CREATE TABLE IF NOT EXISTS email "
          "(pk INTEGER PRIMARY KEY,"
          "datetime REAL,  "
          "sender TEXT,"
          "tos TEXT,"
          "ccs TEXT,"
          "bccs TEXT,"
          "html_body TEXT,"
          "msg_id TEXT,"
          "flag INTEGER);"
          ]) {
        DDLogError(@"errorMessage = %@", db.lastErrorMessage);
    }
    
    if (![db executeUpdate:@"CREATE INDEX IF NOT EXISTS email_datetime on email (datetime desc);"]) {
        DDLogError(@"errorMessage = %@", db.lastErrorMessage);
    }
    
    if (![db executeUpdate:@"CREATE INDEX IF NOT EXISTS email_sender on email (sender);"]) {
        DDLogError(@"errorMessage = %@", db.lastErrorMessage);
    }
    
    if (![db executeUpdate:@"CREATE VIRTUAL TABLE IF NOT EXISTS search_email USING fts4(subject TEXT, body TEXT, sender TEXT, tos TEXT, ccs TEXT, people TEXT,msg_id TEXT);"]) {
        DDLogError(@"errorMessage = %@", db.lastErrorMessage);
    }
    
    if (![db executeUpdate:@"CREATE TRIGGER IF NOT EXISTS delete_email_search AFTER DELETE ON email BEGIN DELETE FROM search_email WHERE search_email.msg_id = OLD.msg_id; END;"]) {
        DDLogError(@"errorMessage = %@", db.lastErrorMessage);
    }
    
    [db executeUpdate:@"DELETE FROM search_email WHERE msg_id NOT IN (SELECT msg_id FROM email)"];
}

+(NSInteger) insertMail:(Mail*)email
{
    __block sqlite_int64 success = -1 ;
    
    DDLogDebug(@"Insert mail \"%@\" into FM db",email.subject);
    
    [[EmailDBAccessor sharedManager].databaseQueue inDatabase:^(FMDatabase* db) {
        
        FMResultSet* results = [db executeQuery:@"SELECT * FROM email WHERE email.msg_id = ?", email.msgID];
        
        if (![results next]) {
            [results close];
            [db executeUpdate:@"INSERT INTO email (datetime,sender,tos,ccs,bccs,msg_id,html_body,flag) VALUES (?,?,?,?,?,?,?,?);",
             email.datetime,
             email.sender.nonEncodedRFC822String,
             email.tos.mco_nonEncodedRFC822StringForAddresses,
             email.ccs.mco_nonEncodedRFC822StringForAddresses,
             email.bccs.mco_nonEncodedRFC822StringForAddresses,
             email.msgID,
             email.htmlBody,
             @(email.flag)];
            success = [db lastInsertRowId];
            
            [db executeUpdate:@"INSERT INTO search_email (subject,body,sender,tos,ccs,people,msg_id) VALUES (?,?,?,?,?,?,?);",
             email.subject,
             email.body,
             email.sender.nonEncodedRFC822String,
             email.tos.mco_nonEncodedRFC822StringForAddresses,
             email.ccs.mco_nonEncodedRFC822StringForAddresses,
             [NSString stringWithFormat:@"%@, %@, %@, %@", email.sender.nonEncodedRFC822String, email.tos.mco_nonEncodedRFC822StringForAddresses, email.ccs.mco_nonEncodedRFC822StringForAddresses, email.bccs.mco_nonEncodedRFC822StringForAddresses], email.msgID];
        }
        else {
            [results close];
        }
    }];
    
    return (int)success;
}

+(void) updateMail:(Mail*)email;
{
    if (!email.subject) {
        NSException* myE = [NSException exceptionWithName:@"EmailHasNoSUBJECT" reason:@"Updating email with nil Subject" userInfo:nil];
#ifdef USING_INSTABUG
        [Instabug reportException:myE];
#else // not using Instabug
        // Raise the exception
        [myE raise];
#endif
        return;
    }
    
    [[EmailDBAccessor sharedManager].databaseQueue inDatabase:^(FMDatabase* db) {
        [db executeUpdate:@"UPDATE email SET sender = ? WHERE msg_id = ?;", email.sender.nonEncodedRFC822String, email.msgID];
        [db executeUpdate:@"UPDATE email SET tos = ? WHERE msg_id = ?;", email.tos.mco_nonEncodedRFC822StringForAddresses, email.msgID];
        [db executeUpdate:@"UPDATE email SET bccs = ? WHERE msg_id = ?;", email.bccs.mco_nonEncodedRFC822StringForAddresses, email.msgID];
        [db executeUpdate:@"UPDATE email SET html_body = ? WHERE msg_id = ?;", email.htmlBody, email.msgID];
        [db executeUpdate:@"UPDATE email SET flag = ? WHERE msg_id = ?;", @(email.flag), email.msgID];
        
        [db executeUpdate:@"UPDATE search_email SET body = ? WHERE msg_id = ?;", email.body, email.msgID];
        [db executeUpdate:@"UPDATE search_email SET subject = ? WHERE msg_id = ?;", email.subject, email.msgID];
        [db executeUpdate:@"UPDATE search_email SET tos = ? WHERE msg_id = ?;", email.tos.mco_nonEncodedRFC822StringForAddresses, email.msgID];
    }];
}

+(BOOL) removeMail:(NSString*)msgIdDel
{
    __block BOOL success = FALSE;
    EmailDBAccessor* databaseManager = [EmailDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        success =  [db executeUpdate:@"DELETE FROM email WHERE msg_id = ?;",
                    msgIdDel];
    }];
    
    return success;
}

+(Mail*) getMailWithMsgId:(NSString*)msgIdDel dbNum:(NSInteger)dbNum
{
    __block Mail* mail = [[Mail alloc] init];
    
    //TODO:Queue?
    FMDatabaseQueue* queue = [FMDatabaseQueue databaseQueueWithPath:[StringUtil filePathInDocumentsDirectoryForFileName:[GlobalDBFunctions dbFileNameForNum:dbNum]]];
    [queue inDatabase:^(FMDatabase* db) {
        
        FMResultSet* results = [db executeQuery:kQueryAllMsgID, msgIdDel];
        
        if ([results next]) {
            mail = [Mail resToMail:results];
        }
        
        [results close];
        
        if (!mail) {
            [Mail clean:msgIdDel dbNum:dbNum];
        }
        
        if ([db hadError] && [db lastErrorCode] == 1) {
            DDLogInfo(@"Checking table");
            [Mail tableCheck:db];
        }
    }];
    
    return mail;
}

+(NSMutableArray*) getMails
{
    NSMutableArray* emails = [[NSMutableArray alloc] init];
    EmailDBAccessor* databaseManager = [EmailDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        
        FMResultSet* results = [db executeQuery:kQueryAll];
        
        while ([results next]) {
            Mail* m = [Mail resToMail:results];
            if (m) {
                [emails addObject:m];
            }
        }
        
    }];
    
    return emails;
}

+(void) _res:(FMResultSet*)result toMail:(Mail*)mail
{
    mail = [Mail resToMail:result];
}

+(Mail*) resToMail:(FMResultSet*)result
{
//    DDLogDebug(@"+[Mail (Mail *)resToMail:(FMResultSet*)result");
    
    Mail* email = [[Mail alloc] init];
    
    email.pk = [result intForColumnIndex:0];
    email.datetime = [result dateForColumnIndex:1];
    
    NSString* adrs = [result stringForColumnIndex:2];
    
    email.sender = [MCOAddress addressWithNonEncodedRFC822String:adrs];
    
    [[result stringForColumnIndex:3] isEqualToString:@""]?(email.tos = [[NSArray alloc]init]):(email.tos = [MCOAddress addressesWithNonEncodedRFC822String:[result stringForColumnIndex:3]]);
    [[result stringForColumnIndex:4] isEqualToString:@""]?(email.ccs = [[NSArray alloc]init]):(email.ccs = [MCOAddress addressesWithNonEncodedRFC822String:[result stringForColumnIndex:4]]);
    [[result stringForColumnIndex:5] isEqualToString:@""]?(email.bccs = [[NSArray alloc]init]):(email.bccs = [MCOAddress addressesWithNonEncodedRFC822String:[result stringForColumnIndex:5]]);
    
    email.msgID = [result stringForColumnIndex:6];
    email.htmlBody = [result stringForColumnIndex:7];
    email.flag = [result intForColumnIndex:8];
    NSString* subject = [result stringForColumnIndex:9];
    
    subject = [subject replace:RX(@"([Rr][Ee]|[Tt][Rr]|[Ff][Ww][Dd]|[Ff][Ww])\\s??:\\s?") with:@""];
    
    email.subject = subject;
    
    DDLogDebug(@"\temail subject =\"%@\"",subject);
    
    email.body = [result stringForColumnIndex:10];
    email.attachments = [CCMAttachment getAttachmentsWithMsgID:email.msgID];
    
    if (!email.user || email.user.isDeleted) {
        DDLogInfo(@"\tShould delete email, Subject=\"%@\"", email.subject);
        return nil;
    }
    
    return email;
}

-(BOOL) hasAttachments
{
    if (!self.attachments) {
        self.attachments = [CCMAttachment getAttachmentsWithMsgID:self.msgID];
    }
    
    return self.attachments.count > 0;
}

-(id) copyWithZone:(NSZone*)zone
{
    Mail* newEmail = [[[self class] allocWithZone:zone] init];
    
    if (newEmail) {
        newEmail.pk = self.pk;
        newEmail.datetime = self.datetime;
        newEmail.sender = self.sender;
        newEmail.tos = self.tos;
        newEmail.ccs = self.ccs;
        newEmail.bccs = self.bccs;
        newEmail.htmlBody = self.htmlBody;
        newEmail.msgID = self.msgID;
        newEmail.flag = self.flag;
        newEmail.subject = self.subject;
        newEmail.body = self.body;
        newEmail.attachments = self.attachments;
        
        NSMutableArray* uds = [[NSMutableArray alloc] initWithCapacity:self.uids.count];
        for (UidEntry* ud in self.uids) {
            [uds addObject:[ud copy]];
        }
        
        newEmail.uids = uds;
    }
    
    return newEmail;
}

#pragma Email Actions

-(void) moveFromFolder:(NSInteger)fromFolderIdx ToFolder:(NSInteger)toFolderIdx
{
    DDLogInfo(@"Move from folder %@ to %@", [self.user folderDisplayNameForIndex:fromFolderIdx],  [self.user folderDisplayNameForIndex:toFolderIdx]);
    
    if ([self uidEWithFolder:fromFolderIdx]) {
        if (([self.user numFolderWithFolder:CCMFolderTypeAll] == fromFolderIdx && [self.user numFolderWithFolder:CCMFolderTypeDeleted] != toFolderIdx) || [self.user numFolderWithFolder:CCMFolderTypeFavoris] == toFolderIdx) {
            [UidEntry copy:[self uidEWithFolder:fromFolderIdx] toFolder:toFolderIdx];
        }
        else if ([self uidEWithFolder:toFolderIdx]) {
            [UidEntry deleteUidEntry:[self uidEWithFolder:fromFolderIdx]];
        }
        else {
            [UidEntry move:[self uidEWithFolder:fromFolderIdx] toFolder:toFolderIdx];
        }
        
        _uids = [UidEntry getUidEntriesWithMsgId:self.msgID];
    }
}

-(void) trash
{
    for (UidEntry* uidE in _uids) {
        [UidEntry move:uidE toFolder:[self.user numFolderWithFolder:CCMFolderTypeDeleted]];
    }
    
    _uids = [UidEntry getUidEntriesWithMsgId:self.msgID];
}

-(void) toggleFav
{
    if (!(self.flag & MCOMessageFlagFlagged)) {
        [UidEntry addFlag:MCOMessageFlagFlagged to:[self getFirstUIDE]];
        self.flag |= MCOMessageFlagFlagged;
    }
    else {
        [UidEntry removeFlag:MCOMessageFlagFlagged to:[self getFirstUIDE]];
        self.flag = self.flag & ~MCOMessageFlagFlagged;
    }
    
    NSInvocationOperation* nextOpUp = [[NSInvocationOperation alloc] initWithTarget:[EmailProcessor getSingleton] selector:@selector(updateFlag:) object:@[self]];
    [[EmailProcessor getSingleton].operationQueue addOperation:nextOpUp];
    
    [nextOpUp waitUntilFinished];
    
    _uids = [UidEntry getUidEntriesWithMsgId:self.msgID];
}

-(void) toggleRead
{
    if (!(self.flag & MCOMessageFlagSeen)) {
        [UidEntry addFlag:MCOMessageFlagSeen to:[self getFirstUIDE]];
        self.flag |= MCOMessageFlagSeen;
    }
    else {
        [UidEntry removeFlag:MCOMessageFlagSeen to:[self getFirstUIDE]];
        self.flag = self.flag & ~MCOMessageFlagSeen;
    }
    
    NSInvocationOperation* nextOpUp = [[NSInvocationOperation alloc] initWithTarget:[EmailProcessor getSingleton] selector:@selector(updateFlag:) object:@[self]];
    [[EmailProcessor getSingleton].operationQueue addOperation:nextOpUp];
    
    [nextOpUp waitUntilFinished];
    
    _uids = [UidEntry getUidEntriesWithMsgId:self.msgID];
}

+(void) clean:(NSString*)msgID dbNum:(NSInteger)dbNum
{
    FMDatabaseQueue* queue = [FMDatabaseQueue databaseQueueWithPath:[StringUtil filePathInDocumentsDirectoryForFileName:[GlobalDBFunctions dbFileNameForNum:dbNum]]];

    [queue inDatabase:^(FMDatabase* db) {
        if ([db executeUpdate:@"DELETE FROM email WHERE msg_id = ?;", msgID]) {
            DDLogInfo(@"Email cleaned");
        }
    }];
}

-(Draft*) toDraft
{
    Draft* draft = [[Draft alloc] init];
    draft.accountNum = self.user.accountNum;
    
    for (NSNumber* n in self.toPersonIDs) {
        Person* p = [[Persons sharedInstance] getPersonWithID:[n integerValue]];
        [draft.toPersons addObject:p.email];
    }
    
    draft.transferContent = self.transferContent;
    draft.fromMailMsgID = self.fromMail.msgID;
    draft.subject = self.subject;
    draft.body = self.body;
    
    draft.msgID = self.msgID;
    
    draft.datetime = self.datetime;//[NSDate date];
    
    return draft;
}

@end

