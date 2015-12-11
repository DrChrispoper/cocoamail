//
//  Email.m
//  CocoaMail
//
//  Created by Christopher Hockley on 20/01/2012.
//  Copyright (c) 2012 Christopher Hockley. All rights reserved.
//

#import "Email.h"
#import "EmailDBAccessor.h"
#import "AppSettings.h"
#import "StringUtil.h"
#import "UidEntry.h"
#import "GlobalDBFunctions.h"
#import "EmailProcessor.h"
#import "Reachability.h"
#import "ImapSync.h"
#import "CCMAttachment.h"
#import "EmailProcessor.h"

@implementation Email

@synthesize accountNum = _accountNum;
@synthesize pk, datetime, sender, tos, ccs, bccs, htmlBody, msgId,flag;
@synthesize subject, body;
@synthesize attachments;
@synthesize uids = _uids;

-(void) loadData
{
    //EmailDBAccessor* databaseManager = [EmailDBAccessor sharedManager];
    //[databaseManager.databaseQueue close];
    //[databaseManager setDatabaseFilepath:[StringUtil filePathInDocumentsDirectoryForFileName:[GlobalDBFunctions dbFileNameForNum:[EmailProcessor dbNumForDate:self.datetime]]]];
    
    FMDatabaseQueue* queue = [FMDatabaseQueue databaseQueueWithPath:[StringUtil filePathInDocumentsDirectoryForFileName:[GlobalDBFunctions dbFileNameForNum:[EmailProcessor dbNumForDate:self.datetime]]]];

	[queue inDatabase:^(FMDatabase* db) {
        FMResultSet* results = [db executeQuery:kQueryPk, @(self.pk)];
        
        if ([results next]) {
            [Email res:results ToEmail:self];
        }
    }];
}

-(BOOL) existsLocally
{
    return self.uids.count > 0 ;
}

-(NSArray*) getUids
{
    if (!_uids) {
        _uids = [UidEntry getUidEntriesWithMsgId:self.msgId];
    }
    
    return _uids;
}

-(void) setUids:(NSArray*)pUids
{
    _uids = pUids;
}
/*-(NSInteger)account
{
    if ([self getFirstUIDE]) {
        return [[self getFirstUIDE] account];
    }
    
    return -1;
}*/

-(NSString*) getSonID
{
    if ([self getFirstUIDE]) {
        return [[self getFirstUIDE] sonMsgId];
    }
    
    return @"";
}

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
    NSString* son = [self getSonID];
    
    NSMutableArray* sonsTemp;
    NSMutableArray* sons = [[NSMutableArray alloc]init];
    
    if ([son isEqualToString:@"0"]) {
        sonsTemp = [UidEntry getUidEntriesWithThread:self.msgId];
    }
    else {
        sonsTemp = [UidEntry getUidEntriesWithThread:son];
    }
    
    for (UidEntry* e in sonsTemp) {
        if (![e.msgId isEqualToString:self.msgId]) {
            [sons addObject:e];
        }
    }
    
    return sons;
}

-(void) loadBody
{
    __block Email* email = [[Email alloc] init];

    FMDatabaseQueue* queue = [FMDatabaseQueue databaseQueueWithPath:[StringUtil filePathInDocumentsDirectoryForFileName:[GlobalDBFunctions dbFileNameForNum:[EmailProcessor dbNumForDate:self.datetime]]]];
    
    [queue inDatabase:^(FMDatabase* db) {
        
        FMResultSet* results = [db executeQuery:kQueryAllMsgID, self.msgId];
        
        if ([results next]) {
            email = [Email resToEmail:results];
            self.pk = email.pk;
            self.body = email.body;
            self.htmlBody = email.htmlBody;
            
        }
        
        [results close];
    }];
}

-(void) fetchAllAttachments
{
    self.attachments = [CCMAttachment getAttachmentsWithMsgId:self.msgId];
}

-(void) setAccountNum:(NSInteger)accountNum
{
    _accountNum = accountNum;
}

-(NSInteger) getAccountNum
{
    return _accountNum;
}

-(BOOL) isInMultipleAccounts
{
    self.accountNum = [self getFirstUIDE].account;
    
    for (UidEntry* e in self.uids) {
        if (self.accountNum != e.account) {
            return YES;
        }
    }
    
    return NO;
}
/*-(void)forActiveAccount
{
    if (!self.uids) {
        self.uids = [UidEntry getUidEntriesWithMsgId:self.msgId];
    }
    
    NSMutableArray* uidsOne = [[NSMutableArray alloc]init];
    
    for (UidEntry* e in self.uids) {
        if(kisActiveAccountAll || e.account == kActiveAccountNum){
            [uidsOne addObject:e];
        }
    }
    
    self.uids = uidsOne;
}*/

-(Email*) secondAccountDuplicate
{
    Email* emailTwo = [self copy];
    
    NSMutableArray<UidEntry* >* uidsOne = [[NSMutableArray alloc]init];
    NSMutableArray<UidEntry* >* uidsTwo = [[NSMutableArray alloc]init];
    
    for (UidEntry* e in self.uids) {
        if (e.account == self.accountNum) {
            [uidsOne addObject:e];
        }
        else {
            [uidsTwo addObject:e];
        }
    }
    
    self.uids = uidsOne;
    
    emailTwo.accountNum = uidsTwo[0].account;
    emailTwo.uids = uidsTwo;
    
    return emailTwo;
}

-(UidEntry*) uidEWithFolder:(NSInteger)folderNum
{
    if (folderNum == -1) {
        for (UidEntry* uidE in self.uids) {
            if (uidE.folder == 0) {
                return uidE;
            }
        }
    }
    else {
        for (UidEntry* uidE in self.uids) {
            if (uidE.folder == folderNum) {
                return uidE;
            }
        }
    }
    
    if (self.uids.count == 0) {
        CCMLog(@"Email not in DB yet");
    }

    return nil;
}

+(void) tableCheck
{
    EmailDBAccessor* databaseManager = [EmailDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        [Email tableCheck:db];
    }];
}

+(void) tableCheck:(FMDatabase*)db
{
    
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
        CCMLog(@"errorMessage = %@", db.lastErrorMessage);
    }
    
    if (![db executeUpdate:@"CREATE INDEX IF NOT EXISTS email_datetime on email (datetime desc);"]) {
        CCMLog(@"errorMessage = %@", db.lastErrorMessage);
    }
    
    if (![db executeUpdate:@"CREATE INDEX IF NOT EXISTS email_sender on email (sender);"]) {
        CCMLog(@"errorMessage = %@", db.lastErrorMessage);
    }
    
    if (![db executeUpdate:@"CREATE VIRTUAL TABLE IF NOT EXISTS search_email USING fts4(subject TEXT, body TEXT, sender TEXT, tos TEXT, ccs TEXT, people TEXT,msg_id TEXT);"]) {
        CCMLog(@"errorMessage = %@", db.lastErrorMessage);
    }
    
    if (![db executeUpdate:@"CREATE TRIGGER IF NOT EXISTS delete_email_search AFTER DELETE ON email BEGIN DELETE FROM search_email WHERE search_email.msg_id = OLD.msg_id; END;"]) {
        CCMLog(@"errorMessage = %@", db.lastErrorMessage);
    }
    
    [db executeUpdate:@"DELETE FROM search_email WHERE msg_id NOT IN (SELECT msg_id FROM email)"];
}

+(NSInteger) insertEmail:(Email*)email
{
    EmailDBAccessor* databaseManager = [EmailDBAccessor sharedManager];
    __block sqlite_int64 success = -1 ;
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        
        FMResultSet* results = [db executeQuery:@"SELECT * FROM email WHERE email.msg_id = ?", email.msgId];
        
        if (![results next]) {
            [results close];
            [db executeUpdate:@"INSERT INTO email (datetime,sender,tos,ccs,bccs,msg_id,html_body,flag) VALUES (?,?,?,?,?,?,?,?);",
             email.datetime,
             email.sender.nonEncodedRFC822String,
             email.tos.mco_nonEncodedRFC822StringForAddresses,
             email.ccs.mco_nonEncodedRFC822StringForAddresses,
             email.bccs.mco_nonEncodedRFC822StringForAddresses,
             email.msgId,
             email.htmlBody,
             @(email.flag)];
            success = [db lastInsertRowId];
            
            [db executeUpdate:@"INSERT INTO search_email (subject,body,sender,tos,ccs,people,msg_id) VALUES (?,?,?,?,?,?,?);",
             email.subject,
             email.body,
             email.sender.nonEncodedRFC822String,
             email.tos.mco_nonEncodedRFC822StringForAddresses,
             email.ccs.mco_nonEncodedRFC822StringForAddresses,
             [NSString stringWithFormat:@"%@, %@, %@, %@", email.sender.nonEncodedRFC822String, email.tos.mco_nonEncodedRFC822StringForAddresses, email.ccs.mco_nonEncodedRFC822StringForAddresses, email.bccs.mco_nonEncodedRFC822StringForAddresses], email.msgId];
        }
        else {
            [results close];
        }
    }];
    
    return (int)success;
}

+(void) updateEmailFlag:(Email*)email
{
    NSInteger dbNum = [EmailProcessor dbNumForDate:email.datetime];
    
    //EmailDBAccessor* databaseManager = [EmailDBAccessor sharedManager];
    //[databaseManager.databaseQueue close];
    //[databaseManager setDatabaseFilepath:[StringUtil filePathInDocumentsDirectoryForFileName:[GlobalDBFunctions dbFileNameForNum:dbNum]]];
    
    FMDatabaseQueue* queue = [FMDatabaseQueue databaseQueueWithPath:[StringUtil filePathInDocumentsDirectoryForFileName:[GlobalDBFunctions dbFileNameForNum:dbNum]]];

    [queue inDatabase:^(FMDatabase* db) {
        [db executeUpdate:@"UPDATE email SET flag = ? WHERE msg_id = ?;", @(email.flag), email.msgId];
    }];
}

+(void) updateEmail:(Email*)email;
{
    NSInteger dbNum = [EmailProcessor dbNumForDate:email.datetime];
    
    //EmailDBAccessor* databaseManager = [EmailDBAccessor sharedManager];
    //[databaseManager.databaseQueue close];
    //[databaseManager setDatabaseFilepath:[StringUtil filePathInDocumentsDirectoryForFileName:[GlobalDBFunctions dbFileNameForNum:dbNum]]];
    
    FMDatabaseQueue* queue = [FMDatabaseQueue databaseQueueWithPath:[StringUtil filePathInDocumentsDirectoryForFileName:[GlobalDBFunctions dbFileNameForNum:dbNum]]];

    [queue inDatabase:^(FMDatabase* db) {
        [db executeUpdate:@"UPDATE email SET sender = ? WHERE msg_id = ?;", email.sender, email.msgId];
        [db executeUpdate:@"UPDATE email SET tos = ? WHERE msg_id = ?;", email.tos.mco_nonEncodedRFC822StringForAddresses, email.msgId];
        [db executeUpdate:@"UPDATE email SET bccs = ? WHERE msg_id = ?;", email.bccs.mco_nonEncodedRFC822StringForAddresses, email.msgId];
        [db executeUpdate:@"UPDATE email SET html_body = ? WHERE msg_id = ?;", email.htmlBody, email.msgId];
        
        [db executeUpdate:@"UPDATE search_email SET body = ? WHERE msg_id = ?;", email.body, email.msgId];
        [db executeUpdate:@"UPDATE search_email SET subject = ? WHERE msg_id = ?;", email.subject, email.msgId];
        [db executeUpdate:@"UPDATE search_email SET tos = ? WHERE msg_id = ?;", email.tos.mco_nonEncodedRFC822StringForAddresses, email.msgId];
    }];
}

+(BOOL) removeEmail:(NSString*)msgIdDel dbNum:(NSInteger)dbNum
{
    __block BOOL success = FALSE;
    EmailDBAccessor* databaseManager = [EmailDBAccessor sharedManager];
    
    [Email getEmailWithMsgId:msgIdDel dbNum:dbNum];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        success =  [db executeUpdate:@"DELETE FROM email WHERE msg_id = ?;",
                    msgIdDel];
    }];
    
    return success;
}

+(Email*) getEmailWithMsgId:(NSString*)msgIdDel dbNum:(NSInteger)dbNum
{
    __block Email* email = [[Email alloc] init];
    
    //EmailDBAccessor* databaseManager = [EmailDBAccessor sharedManager];
    //[databaseManager.databaseQueue close];
    //[databaseManager setDatabaseFilepath:[StringUtil filePathInDocumentsDirectoryForFileName:[GlobalDBFunctions dbFileNameForNum:dbNum]]];
    
    FMDatabaseQueue* queue = [FMDatabaseQueue databaseQueueWithPath:[StringUtil filePathInDocumentsDirectoryForFileName:[GlobalDBFunctions dbFileNameForNum:dbNum]]];

    [queue inDatabase:^(FMDatabase* db) {
        
        FMResultSet* results = [db executeQuery:kQueryAllMsgID, msgIdDel];
        
        if ([results next]) {
            email = [Email resToEmail:results];
        }
    
        [results close];
    }];
    
    return email;
}

+(NSMutableArray*) getEmails
{
    NSMutableArray* emails = [[NSMutableArray alloc] init];
    EmailDBAccessor* databaseManager = [EmailDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        
        FMResultSet* results = [db executeQuery:kQueryAll];
        
        while ([results next]) {
            [emails addObject:[Email resToEmail:results]];
        }
        
    }];
    
    return emails;
}

+(void) res:(FMResultSet*)result ToEmail:(Email*)email
{
    email = [Email resToEmail:result];
}

+(Email*) resToEmail:(FMResultSet*)result
{
    Email* email = [[Email alloc] init];
    email.accountNum = -2;
    email.pk = [result intForColumnIndex:0];
    email.datetime = [result dateForColumnIndex:1];
    email.sender = [MCOAddress addressWithNonEncodedRFC822String:[result stringForColumnIndex:2]];
    [[result stringForColumnIndex:3] isEqualToString:@""]?(email.tos = [[NSArray alloc]init]):(email.tos = [MCOAddress addressesWithNonEncodedRFC822String:[result stringForColumnIndex:3]]);
    [[result stringForColumnIndex:4] isEqualToString:@""]?(email.ccs = [[NSArray alloc]init]):(email.ccs = [MCOAddress addressesWithNonEncodedRFC822String:[result stringForColumnIndex:4]]);
    [[result stringForColumnIndex:5] isEqualToString:@""]?(email.bccs = [[NSArray alloc]init]):(email.bccs = [MCOAddress addressesWithNonEncodedRFC822String:[result stringForColumnIndex:5]]);
    
    email.msgId = [result stringForColumnIndex:6];
    email.htmlBody = [result stringForColumnIndex:7];
    email.flag = [result intForColumnIndex:8];
    email.subject = [result stringForColumnIndex:9];
    email.body = [result stringForColumnIndex:10];
    email.attachments = [CCMAttachment getAttachmentsWithMsgId:email.msgId];
    
    [email isInMultipleAccounts];
    
    if (email.accountNum == 0) {
        
        CCMLog(@"Prout");
    }

    return email;
}

-(BOOL) hasAttachments
{
    if (!self.attachments) {
        self.attachments = [CCMAttachment getAttachmentsWithMsgId:self.msgId];
    }
    
    return self.attachments.count > 0;
}

-(id) copyWithZone:(NSZone*)zone
{
    Email* newEmail = [[[self class] allocWithZone:zone] init];
    
    if (newEmail) {
        newEmail.pk = self.pk;
        newEmail.datetime = self.datetime;
        newEmail.sender = self.sender;
        newEmail.tos = self.tos;
        newEmail.ccs = self.ccs;
        newEmail.bccs = self.bccs;
        newEmail.htmlBody = self.htmlBody;
        newEmail.msgId = self.msgId;
        newEmail.flag = self.flag;
        newEmail.subject = self.subject;
        newEmail.body = self.body;
        newEmail.attachments = self.attachments;
        newEmail.uids = self.uids;
        newEmail.accountNum = self.accountNum;
    }
    
    return newEmail;
}

#pragma Email Actions

-(void) moveFromFolder:(NSInteger)fromFolderIdx ToFolder:(NSInteger)toFolderIdx
{
    NSInteger accountndex = [AppSettings indexForAccount:self.accountNum];
    CCMLog(@"Move from folder %@ to %@", [AppSettings folderDisplayName:fromFolderIdx forAccountIndex:accountndex],  [AppSettings folderDisplayName:toFolderIdx forAccountIndex:accountndex]);
    if ([self uidEWithFolder:fromFolderIdx]) {
        if ([self uidEWithFolder:toFolderIdx]) {
            [UidEntry deleteMsgId:self.msgId fromfolder:fromFolderIdx];
        }
        else {
            [UidEntry moveMsgId:self.msgId inFolder:fromFolderIdx toFolder:toFolderIdx];
        }
        _uids = [UidEntry getUidEntriesWithMsgId:self.msgId];
    }
}

-(void) trash
{
    for (UidEntry* uidE in _uids) {
        [UidEntry moveMsgId:self.msgId inFolder:uidE.folder toFolder:[AppSettings importantFolderNumforAccountIndex:[AppSettings indexForAccount:self.accountNum] forBaseFolder:FolderTypeDeleted]];
    }
    
    _uids = [UidEntry getUidEntriesWithMsgId:self.msgId];
}

-(void) star
{
    if (!(self.flag & MCOMessageFlagFlagged)) {
        [UidEntry addFlag:MCOMessageFlagFlagged toMsgId:self.msgId fromFolder:[[Accounts sharedInstance].currentAccount currentFolderIdx]];
        self.flag |= MCOMessageFlagFlagged;
    }
    else {
        [UidEntry removeFlag:MCOMessageFlagFlagged toMsgId:self.msgId fromFolder:[[Accounts sharedInstance].currentAccount currentFolderIdx]];
        self.flag = self.flag & ~MCOMessageFlagFlagged;
    }
    
    [Email updateEmailFlag:self];
    
    _uids = [UidEntry getUidEntriesWithMsgId:self.msgId];
}

-(void) read
{
    if (!(self.flag & MCOMessageFlagSeen)) {
        [UidEntry addFlag:MCOMessageFlagSeen toMsgId:self.msgId fromFolder:[[Accounts sharedInstance].currentAccount currentFolderIdx]];
        self.flag |= MCOMessageFlagSeen;
    }
    else {
        [UidEntry removeFlag:MCOMessageFlagSeen toMsgId:self.msgId fromFolder:[[Accounts sharedInstance].currentAccount currentFolderIdx]];
        self.flag = self.flag & ~MCOMessageFlagSeen;
    }
    
    [Email updateEmailFlag:self];
    
    _uids = [UidEntry getUidEntriesWithMsgId:self.msgId];
}

+(void) clean:(Email*)email
{
/*    EmailDBAccessor* databaseManager = [EmailDBAccessor sharedManager];
    [databaseManager.databaseQueue close];
    [databaseManager setDatabaseFilepath:[StringUtil filePathInDocumentsDirectoryForFileName:[GlobalDBFunctions dbFileNameForNum:[EmailProcessor dbNumForDate:email.datetime]]]];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        if ([db executeUpdate:@"DELETE FROM email WHERE pk = ?;", @(email.pk)]) {
            CCMLog(@"Email cleaned");
        }
    }];*/
}


@end
