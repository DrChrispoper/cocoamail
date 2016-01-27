//
//  UidEntry.m
//  CocoaMail
//
//  Created by Christopher Hockley on 20/01/2012.
//  Copyright (c) 2012 Christopher Hockley. All rights reserved.
//

#import "UidEntry.h"
#import "UidDBAccessor.h"
#import "FMDatabase.h"
#import "Email.h"
#import "AppSettings.h"
#import "ImapSync.h"
#import "Reachability.h"
#import "CachedAction.h"
#import "EmailProcessor.h"
#import <Instabug/Instabug.h>

@implementation UidEntry

+(void) tableCheck
{
    UidDBAccessor* databaseManager = [UidDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        
        if (![db executeUpdate:@"CREATE TABLE IF NOT EXISTS uid_entry (pk INTEGER PRIMARY KEY, uid INTEGER, folder INTEGER, msg_id TEXT, son_msg_id TEXT, dbNum INTEGER)"]) {
            CCMLog(@"errorMessage = %@", db.lastErrorMessage);
        }
        
        if (![db executeUpdate:@"CREATE INDEX IF NOT EXISTS uid_entry_md5 on uid_entry(msg_id);"]) {
            CCMLog(@"errorMessage = %@", db.lastErrorMessage);
        }
        
        if (![db executeUpdate:@"CREATE INDEX IF NOT EXISTS uid_entry_son on uid_entry(son_msg_id);"]) {
            CCMLog(@"errorMessage = %@", db.lastErrorMessage);
        }
        
        if (![db executeUpdate:@"CREATE INDEX IF NOT EXISTS uid_entry_folder on uid_entry(folder);"]) {
            CCMLog(@"errorMessage = %@", db.lastErrorMessage);
        }
    }];
}

+(BOOL) addUid:(UidEntry*)uid_entry
{
    __block BOOL success = FALSE;
    UidDBAccessor* databaseManager = [UidDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        
        if (![uid_entry.sonMsgId isEqualToString:@"0"]) {
            FMResultSet* result = [db executeQuery:@"SELECT * FROM uid_entry WHERE msg_id = ?", uid_entry.sonMsgId];
            
            if ([result next]) {
                NSString* son = [result stringForColumn:@"son_msg_id"];
                
                if (![son isEqualToString:@"0"]) {
                    uid_entry.sonMsgId = son;
                }
            }
            [result close];
        }
        
        FMResultSet* result = [db executeQuery:@"SELECT * FROM uid_entry WHERE msg_id = ? and folder = ?", uid_entry.msgId, @(uid_entry.folder + 1000 * uid_entry.account)];
        
        //Doesn't exist
        if (![result next]) {
            [result close];
            
            success =  [db executeUpdate:@"INSERT INTO uid_entry (uid,folder,msg_id,son_msg_id,dbNum) VALUES (?,?,?,?,?);",
                        @(uid_entry.uid),
                        @(uid_entry.folder + 1000 * uid_entry.account),
                        uid_entry.msgId,
                        uid_entry.sonMsgId,
                        @(uid_entry.dbNum)];
        }
        else {
            [result close];
        }
    }];
    
    return success;
}

+(BOOL) updateNewUID:(UidEntry*)uid_entry
{
    __block BOOL success = FALSE;
    UidDBAccessor* databaseManager = [UidDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        success =  [db executeUpdate:@"UPDATE uid_entry SET uid = ? WHERE msg_id = ? AND folder = ?;",
                    uid_entry.msgId,
                    @(uid_entry.folder + 1000 * uid_entry.account)];
        
    }];
    
    if ([self getUidEntriesWithMsgId:uid_entry.msgId].count == 0) {
        NSInvocationOperation* nextOpUp = [[NSInvocationOperation alloc] initWithTarget:[EmailProcessor getSingleton] selector:@selector(removeEmail:) object:uid_entry];
        [[EmailProcessor getSingleton].operationQueue addOperation:nextOpUp];
    }
    
    return success;
}

+(BOOL) removeFromFolderUid:(UidEntry*)uid_entry
{
    __block BOOL success = FALSE;
    UidDBAccessor* databaseManager = [UidDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        success =  [db executeUpdate:@"DELETE FROM uid_entry WHERE msg_id = ? AND folder = ?;",
                    uid_entry.msgId,
                    @(uid_entry.folder + 1000 * uid_entry.account)];
        
    }];
    
    if ([self getUidEntriesWithMsgId:uid_entry.msgId].count == 0) {
        NSInvocationOperation* nextOpUp = [[NSInvocationOperation alloc] initWithTarget:[EmailProcessor getSingleton] selector:@selector(removeEmail:) object:uid_entry];
        [[EmailProcessor getSingleton].operationQueue addOperation:nextOpUp];
    }
    
    return success;
}

+(BOOL) removeFromAccount:(NSInteger)accountN
{
    __block BOOL success = FALSE;
    UidDBAccessor* databaseManager = [UidDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        NSMutableString* query = [NSMutableString string];
        [query appendFormat:@"DELETE FROM uid_entry WHERE folder LIKE '%ld___' ", (long)accountN];
        success =  [db executeUpdate:query];
        
    }];
    
    return success;
}

+(NSMutableArray*) getUidEntries
{
    NSMutableArray* uids = [[NSMutableArray alloc] init];
    
    UidDBAccessor* databaseManager = [UidDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        FMResultSet* results = [db executeQuery:@"SELECT * FROM uid_entry"];
        
        while ([results next]) {
            [uids addObject:[UidEntry resToUidEntry:results]];
        }
        
    }];
    
    return uids;
}

+(void) cleanBeforeDeleteinAccount:(NSInteger)accountIndex
{
    NSInteger accountNum = [AppSettings numForData:accountIndex];

    NSMutableString* query = [NSMutableString string];
    [query appendFormat:@"SELECT msg_id, folder, count(*) c FROM uid_entry where folder LIKE '%ld___' GROUP BY msg_id HAVING c > 1;", (long)accountNum];
     
    [[UidDBAccessor sharedManager].databaseQueue inDatabase:^(FMDatabase* db) {
        FMResultSet* results = [db executeQuery:query];
        
        while ([results next]) {
            UidEntry* uidEntry = [[UidEntry alloc] init];
            
            uidEntry.folder = [results intForColumn:@"folder"] % 1000;
            uidEntry.msgId = [results stringForColumn:@"msg_id"];

            [db executeUpdate:@"DELETE FROM uid_entry WHERE msg_id = ? and folder = ?", uidEntry.msgId, @(uidEntry.folder)];
        }
    }];
}

+(NSMutableArray*) getUidEntriesinAccount:(NSInteger)accountIndex andDelete:(BOOL)haveDeleted
{
    NSMutableArray* uids = [[NSMutableArray alloc] init];
    NSMutableSet* dbNums = [[NSMutableSet alloc] init];
    
    NSInteger accountNum = [AppSettings numForData:accountIndex];
    NSString* folder = [NSString stringWithFormat:@"'%ld___'", (long)accountNum];
    NSString* query = [NSString stringWithFormat:@"SELECT * FROM uid_entry where folder LIKE %@ ORDER BY uid DESC LIMIT 500", folder];
    
    [[UidDBAccessor sharedManager].databaseQueue inDatabase:^(FMDatabase* db) {
        FMResultSet* results = [db executeQuery:query];
        
        NSMutableArray* tmpUids = [[NSMutableArray alloc] init];
        
        while ([results next]) {
            UidEntry* uid = [UidEntry resToUidEntry:results];
            
            if (![dbNums containsObject:@(uid.dbNum)]) {
                [dbNums addObject:@(uid.dbNum)];
                [uids addObject:[NSMutableArray new]];
            }
            
            [tmpUids addObject:uid];
        }
        
        NSSortDescriptor* sortOrder = [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(self)) ascending:NO];
        NSArray* sortedNums = [dbNums sortedArrayUsingDescriptors:@[sortOrder]];
        
        for (UidEntry* uidE in tmpUids) {
            NSInteger index = [sortedNums indexOfObject:@(uidE.dbNum)];
            [uids[index] addObject:uidE];
        }
        
        if (haveDeleted) {
            for (NSArray* uidEs in uids) {
                for (UidEntry* uid in uidEs) {
                    [db executeUpdate:@"DELETE FROM uid_entry WHERE msg_id = ? and folder = ?", uid.msgId, @(uid.folder)];
                }
            }
            
        }
    }];
    
    return uids;
}

+(NSMutableArray*) getUidEntriesWithThread:(NSString*)son_msgId
{
    NSMutableArray* uids = [[NSMutableArray alloc] init];
    
    UidDBAccessor* databaseManager = [UidDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        FMResultSet* results = [db executeQuery:@"SELECT * FROM uid_entry WHERE son_msg_id = ?", son_msgId];
        
        while ([results next]) {
            [uids addObject:[UidEntry resToUidEntry:results]];
            
        }
    }];
    
    return uids;
}

+(NSMutableArray*) getUidEntriesWithMsgId:(NSString*)msgId
{
    NSMutableArray* uids = [[NSMutableArray alloc] init];
    
    UidDBAccessor* databaseManager = [UidDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        FMResultSet* results = [db executeQuery:@"SELECT * FROM uid_entry WHERE msg_id = ?", msgId]; //AND folder LIKE ?",msgId,[NSString stringWithFormat:@"%ld%%",(long)accountNum]];
        
        while ([results next]) {
            [uids addObject:[UidEntry resToUidEntry:results]];
        }
    }];
    
    return uids;
}

+(NSMutableArray*) getUidEntriesWithFolder:(NSInteger)folderNum inAccount:(NSInteger)accountIndex;
{
    NSMutableArray* uids = [[NSMutableArray alloc] init];
    NSMutableSet* dbNums = [[NSMutableSet alloc] init];
    
    NSInteger accountNum = [AppSettings numForData:accountIndex];
    
    UidDBAccessor* databaseManager = [UidDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        FMResultSet* results = [db executeQuery:@"SELECT * FROM uid_entry WHERE folder = ? ORDER BY uid DESC LIMIT 200", @(folderNum + 1000 * accountNum)];
        
        NSMutableArray* tmpUids = [[NSMutableArray alloc] init];

        while ([results next]) {
            UidEntry* uid = [UidEntry resToUidEntry:results];
            
            if (![dbNums containsObject:@(uid.dbNum)]) {
                [dbNums addObject:@(uid.dbNum)];
                [uids addObject:[NSMutableArray new]];
            }
            
            [tmpUids addObject:uid];
        }
        
        NSSortDescriptor* sortOrder = [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(self)) ascending:NO];
        NSArray* sortedNums = [dbNums sortedArrayUsingDescriptors:@[sortOrder]];
        
        for (UidEntry* uidE in tmpUids) {
            NSInteger index = [sortedNums indexOfObject:@(uidE.dbNum)];
            [uids[index] addObject:uidE];
        }
        
    }];
    
    return uids;
}

+(NSMutableArray*) getUidEntriesFrom:(Email*)email withFolder:(NSInteger)folderNum inAccount:(NSInteger)accountIndex
{
    NSMutableArray* uids = [[NSMutableArray alloc] init];
    NSMutableSet* dbNums = [[NSMutableSet alloc] init];

    NSInteger accountNum = [AppSettings numForData:accountIndex];
    
    UidDBAccessor* databaseManager = [UidDBAccessor sharedManager];
    
    UidEntry* uidE = [email uidEWithFolder:folderNum];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        FMResultSet* results;
        
        NSMutableString* query = [NSMutableString string];

            NSNumber* folderAccount = @(folderNum + 1000 * accountNum);

            if (folderNum != [AppSettings importantFolderNumforAccountIndex:kActiveAccountIndex forBaseFolder:FolderTypeAll]) {
                [query appendFormat:@"SELECT * FROM uid_entry t WHERE t.uid < %i AND t.folder = %@ "
                //[query appendFormat:@"SELECT * FROM uid_entry t WHERE t.folder = %@ AND t.msg_id NOT IN (SELECT c.son_msg_id FROM uid_entry c) "
                         "OR t.folder != %@ "
                         "AND t.son_msg_id IN (SELECT c.msg_id FROM uid_entry c WHERE c.folder = %@)",
                  uidE.uid, folderAccount, folderAccount, folderAccount];
            }
            else {
                NSString* folder = [NSString stringWithFormat:@"'%ld___'", (long)accountNum];
                [query appendFormat:@"SELECT * FROM uid_entry t WHERE t.uid < %i AND t.folder LIKE %@ ", uidE.uid, folder];
            }
        
        [query appendString:@" ORDER BY uid DESC"];
        
        results = [db executeQuery:query];
        
        NSMutableArray* tmpUids = [[NSMutableArray alloc] init];
        
        while ([results next]) {
            UidEntry* uid = [UidEntry resToUidEntry:results];
            
            
            if (![dbNums containsObject:@(uid.dbNum)]) {
                [dbNums addObject:@(uid.dbNum)];
                [uids addObject:[NSMutableArray new]];
            }
            
            [tmpUids addObject:uid];
                
            if (tmpUids.count > 200) {
                [results close];
                break;
            }
        }
        
        NSSortDescriptor* sortOrder = [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(self)) ascending:NO];
        NSArray* sortedNums = [dbNums sortedArrayUsingDescriptors:@[sortOrder]];
        
        for (UidEntry* uidE in tmpUids) {
            NSInteger index = [sortedNums indexOfObject:@(uidE.dbNum)];
            [uids[index] addObject:uidE];
        }
    }];
    
    return uids;
}

+(UidEntry*) getUidEntryAtPk:(NSInteger)pk
{
    UidDBAccessor* databaseManager = [UidDBAccessor sharedManager];
    
    UidEntry* __block uid_entry = [[UidEntry alloc]init];
    uid_entry.pk = pk;
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        FMResultSet* results = [db executeQuery:@"SELECT * FROM uid_entry WHERE pk = ?", uid_entry.pk];
        
        if ([results next]) {
            uid_entry = [UidEntry resToUidEntry:results];
        }
        [results close];
    }];
    
    return uid_entry;
}

+(UidEntry*) getUidEntryWithFolder:(NSInteger)folderNum msgId:(NSString*)msgId
{
    UidDBAccessor* databaseManager = [UidDBAccessor sharedManager];
    
    UidEntry* __block uid_entry = [[UidEntry alloc]init];
    uid_entry.msgId = msgId;
    uid_entry.folder = folderNum;
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        FMResultSet* results = [db executeQuery:@"SELECT * FROM uid_entry WHERE folder LIKE ? AND msg_id = ?",
                                [NSString stringWithFormat:@"_%03ld", (long)uid_entry.folder],
                                msgId];
        
        if ([results next]) {
            uid_entry = [UidEntry resToUidEntry:results];
        }
        [results close];
    }];
    
    return uid_entry;
}

+(BOOL) hasUidEntrywithMsgId:(NSString*)msgId withFolder:(NSInteger)folderNum
{
    __block BOOL result = NO;
    
    UidDBAccessor* databaseManager = [UidDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        
        FMResultSet* results = [db executeQuery:@"SELECT folder FROM uid_entry WHERE msg_id = ?", msgId];
        
        while ([results next]) {
            if (folderNum == -1 || folderNum == [results intForColumn:@"folder"] % 1000) {
                result = YES;
            }
        }
    }];
    
    return result;
}

+(void) res:(FMResultSet*)result ToUidEntry:(UidEntry*)uidEntry
{
    uidEntry = [UidEntry resToUidEntry:result];
}

+(UidEntry*) resToUidEntry:(FMResultSet*)result
{
    UidEntry* uidEntry = [[UidEntry alloc] init];
    
    uidEntry.pk = [result intForColumn:@"pk"];
    uidEntry.uid = [[result objectForColumnName:@"uid"] unsignedIntValue];
    uidEntry.folder = [result intForColumn:@"folder"] % 1000;
    uidEntry.msgId = [result stringForColumn:@"msg_id"];
    uidEntry.account = [result intForColumn:@"folder"] / 1000;
    uidEntry.sonMsgId = [result stringForColumn:@"son_msg_id"];
    uidEntry.dbNum = [result intForColumn:@"dbNum"];
    
    return uidEntry;
}


+(void) copy:(UidEntry*)uidE toFolder:(NSInteger)to
{
    //No Important folder at Index
    if (to == -1) {
        IBGLog(@"Email not synced in folder, so can't move it");
        return ;
    }
    
    NSInteger accountIndex = [AppSettings indexForAccount:uidE.account];
    
    NSString* fromFolderName = [AppSettings folderServerName:uidE.folder forAccountIndex:accountIndex];
    NSString* toFolderName = [AppSettings folderServerName:to forAccountIndex:accountIndex];
    
    CachedAction* action = [CachedAction addActionWithUid:uidE actionIndex:4 toFolder:to];
    
    UidEntry* newUidE = [uidE copy];
    newUidE.uid = 0;
    newUidE.folder = to;
    [self addUid:newUidE];
    
    if ([[Reachability reachabilityForInternetConnection] currentReachabilityStatus] != NotReachable) {
        MCOIMAPCopyMessagesOperation* opMove = [[ImapSync sharedServices:accountIndex].imapSession copyMessagesOperationWithFolder:fromFolderName
                                                                                                                              uids:[MCOIndexSet indexSetWithIndex:uidE.uid]
                                                                                                                        destFolder:toFolderName];
        [opMove start:^(NSError* error, NSDictionary* destUids) {
            if (!error && destUids) {
                CCMLog(@"Email copied to folder!");
                
                [CachedAction removeAction:action];
                
                newUidE.uid = [destUids[@(uidE.uid)] unsignedIntValue];
                [self updateNewUID:newUidE];
                [CachedAction updateActionUID:newUidE];
            } else {
                CCMLog(@"Error copying email to folder:%@", error);
            }
        }];
    }
}

+(void) move:(UidEntry*)uidE toFolder:(NSInteger)to
{
    //No Important folder at Index
    if (to == -1) {
        IBGLog(@"Email not synced in folder, so can't move it");
        return ;
    }
    
    NSInteger accountIndex = [AppSettings indexForAccount:uidE.account];
    
    NSString* fromFolderName = [AppSettings folderServerName:uidE.folder forAccountIndex:accountIndex];
    NSString* toFolderName = [AppSettings folderServerName:to forAccountIndex:accountIndex];
    
    [self removeFromFolderUid:uidE];
    
    CachedAction* action = [CachedAction addActionWithUid:uidE actionIndex:0 toFolder:to];
    
    UidEntry* newUidE = [uidE copy];
    newUidE.uid = 0;
    newUidE.folder = to;
    [self addUid:newUidE];
    
    if ([[Reachability reachabilityForInternetConnection] currentReachabilityStatus] != NotReachable) {
        MCOIMAPCopyMessagesOperation* opMove = [[ImapSync sharedServices:accountIndex].imapSession copyMessagesOperationWithFolder:fromFolderName
                                                                                                                              uids:[MCOIndexSet indexSetWithIndex:uidE.uid]
                                                                                                                        destFolder:toFolderName];
        [opMove start:^(NSError* error, NSDictionary* destUids) {
            if (!error && destUids) {
                CCMLog(@"Email copied to folder!");
                
                [CachedAction removeAction:action];
                
                [UidEntry deleteUidEntry:uidE];
                
                newUidE.uid = [destUids[@(uidE.uid)] unsignedIntValue];
                [self updateNewUID:newUidE];
                [CachedAction updateActionUID:newUidE];
            } else {
                [self removeFromFolderUid:uidE];
                
                CCMLog(@"Error copying email to folder:%@", error);
            }
        }];
    }
}

+(void) deleteUidEntry:(UidEntry*)uidE
{
    if (uidE.pk == 0) {
        CCMLog(@"Email doesn't look synced in folder, so deleting it might not work");
    }
    
    NSInteger accountIndex = [AppSettings indexForAccount:uidE.account];
    
    CachedAction* action = [CachedAction addActionWithUid:uidE actionIndex:1 toFolder:-1];

    if ([[Reachability reachabilityForInternetConnection] currentReachabilityStatus] != NotReachable) {
        MCOIMAPOperation* op = [[ImapSync sharedServices:accountIndex].imapSession storeFlagsOperationWithFolder:[AppSettings folderServerName:uidE.folder forAccountIndex:accountIndex]
                                                                                                            uids:[MCOIndexSet indexSetWithIndex:uidE.uid]
                                                                                                            kind:MCOIMAPStoreFlagsRequestKindSet
                                                                                                           flags:MCOMessageFlagDeleted];
        [op start:^(NSError* error) {
            if (!error) {
                CCMLog(@"Updated the deleted flags!");
                
                MCOIMAPOperation* deleteOp = [[ImapSync sharedServices:accountIndex].imapSession expungeOperation:[AppSettings folderServerName:uidE.folder forAccountIndex:accountIndex]];
                [deleteOp start:^(NSError* error) {
                    if (error) {
                        CCMLog(@"Error expunging folder:%@", error);
                    }
                    else {
                        [CachedAction removeAction:action];
                        CCMLog(@"Successfully expunged folder:%@", [AppSettings folderDisplayName:uidE.folder forAccountIndex:accountIndex]);
                    }
                }];
            }
            else {
                [self removeFromFolderUid:uidE];

                CCMLog(@"Error updating the deleted flags:%@", error);
            }
        }];
    } else {
    }
}

-(UidEntry*) copyWithZone:(NSZone*)zone
{
    UidEntry* copy = [[[self class] alloc] init];
    
    if (copy) {
        [copy setPk:self.pk];
        [copy setUid:self.uid];
        [copy setFolder:self.folder];
        [copy setMsgId:self.msgId];
        [copy setSonMsgId:self.sonMsgId];
        [copy setAccount:self.account];
        [copy setDbNum:self.dbNum];
    }
    
    return copy;
}

+(void) addFlag:(MCOMessageFlag)flag toMsgId:(NSString*)msg_id fromFolder:(NSInteger)folder
{
    return [UidEntry addFlag:flag to:[self getUidEntryWithFolder:folder msgId:msg_id]];
}

+(void) addFlag:(MCOMessageFlag)flag to:(UidEntry*)uidE
{

    if (uidE.pk == 0) {
        CCMLog(@"Email not synced in folder, so can't add flag");
        return ;
    }
    
    CachedAction* action;
    if (flag & MCOMessageFlagFlagged) {
        action = [CachedAction addActionWithUid:uidE actionIndex:2 toFolder:-1];
    }
    
    Reachability* networkReachability = [Reachability reachabilityForInternetConnection];
    
    if ([networkReachability currentReachabilityStatus] != NotReachable) {
        MCOIMAPOperation* op = [[ImapSync sharedServices:[AppSettings indexForAccount:uidE.account]].imapSession storeFlagsOperationWithFolder:[AppSettings folderServerName:[[Accounts sharedInstance].currentAccount currentFolderIdx] forAccountIndex:[AppSettings indexForAccount:uidE.account]]
                                                                                                            uids:[MCOIndexSet indexSetWithIndex:uidE.uid]
                                                                                                            kind:MCOIMAPStoreFlagsRequestKindAdd
                                                                                                           flags:flag];
        [op start:^(NSError* error) {
            if (!error) {
                CCMLog(@"Added flag!");
                if (action) {
                    [CachedAction removeAction:action];
                }
                if ((flag & MCOMessageFlagFlagged)) {
                    [UidEntry move:uidE toFolder:[AppSettings importantFolderNumforAccountIndex:[AppSettings indexForAccount:uidE.account] forBaseFolder:FolderTypeFavoris]];
                }
            }
            else {
                CCMLog(@"Error adding flag email:%@", error);
            }
        }];
    }
}

+(void) removeFlag:(MCOMessageFlag)flag toMsgId:(NSString*)msg_id fromFolder:(NSInteger)folder
{
    return [UidEntry removeFlag:flag to:[self getUidEntryWithFolder:folder msgId:msg_id]];
}

+(void) removeFlag:(MCOMessageFlag)flag to:(UidEntry*)uidE
{
    if (uidE.pk == 0) {
        CCMLog(@"Email not synced in folder, so can't remove flag");
        
        return ;
    }
    
    CachedAction* action;

    if (flag & MCOMessageFlagFlagged) {
        action = [CachedAction addActionWithUid:uidE actionIndex:3 toFolder:-1];
    }
    
    Reachability* networkReachability = [Reachability reachabilityForInternetConnection];
    
    if ([networkReachability currentReachabilityStatus] != NotReachable) {
        MCOIMAPOperation* op = [[ImapSync sharedServices:[AppSettings indexForAccount:uidE.account]].imapSession storeFlagsOperationWithFolder:[AppSettings folderServerName:[[Accounts sharedInstance].currentAccount currentFolderIdx] forAccountIndex:[AppSettings indexForAccount:uidE.account]]
                                                                                                            uids:[MCOIndexSet indexSetWithIndex:uidE.uid]
                                                                                                            kind:MCOIMAPStoreFlagsRequestKindRemove
                                                                                                           flags:flag];
        [op start:^(NSError* error) {
            if (!error) {
                CCMLog(@"Removed flag!");
                if (action) {
                    [CachedAction removeAction:action];
                }
                if ((flag & MCOMessageFlagFlagged)) {
                    [UidEntry deleteUidEntry:[UidEntry getUidEntryWithFolder:[AppSettings importantFolderNumforAccountIndex:[AppSettings indexForAccount:uidE.account] forBaseFolder:FolderTypeFavoris] msgId:uidE.msgId]];
                }
            }
            else {
                CCMLog(@"Error removing flag:%@", error);
            }
        }];
    }
}


+(NSArray*) dbNumsInAccount:(NSInteger)accountIndex
{
    NSMutableArray* nums = [[NSMutableArray alloc]init];
    
    UidDBAccessor* databaseManager = [UidDBAccessor sharedManager];
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        FMResultSet* results;
        
        if (accountIndex != [Accounts sharedInstance].accountsCount -1) {
            NSMutableString* query = [NSMutableString string];
            [query appendFormat:@"SELECT distinct(dbNum) FROM uid_entry WHERE folder LIKE '%ld___' ", (long)[AppSettings numForData:accountIndex]];
            results = [db executeQuery:query];
        }
        else {
            results = [db executeQuery:@"SELECT distinct(dbNum) FROM uid_entry"];
        }
        
        while ([results next]) {
            [nums addObject:@([results intForColumnIndex:0])];
        }
        
    }];

    NSSortDescriptor* sortOrder = [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(self)) ascending:NO];
    
    return [nums sortedArrayUsingDescriptors:@[sortOrder]];
}

@end
