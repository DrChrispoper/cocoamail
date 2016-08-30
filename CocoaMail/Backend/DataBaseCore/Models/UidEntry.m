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
#import "Mail.h"
#import "AppSettings.h"
#import "ImapSync.h"
#import "Reachability.h"
#import "CachedAction.h"
#import "EmailProcessor.h"
#import "UserSettings.h"

#ifdef USING_INSTABUG
#import <Instabug/Instabug.h>
#endif

@implementation UidEntry

+(void) tableCheck
{
    UidDBAccessor* databaseManager = [UidDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        
        if (![db executeUpdate:@"CREATE TABLE IF NOT EXISTS uid_entry (pk INTEGER PRIMARY KEY, uid INTEGER, folder INTEGER, msg_id TEXT, son_msg_id TEXT, dbNum INTEGER)"]) {
            DDLogError(@"errorMessage = %@", db.lastErrorMessage);
        }
        
        if (![db executeUpdate:@"CREATE INDEX IF NOT EXISTS uid_entry_md5 on uid_entry(msg_id);"]) {
            DDLogError(@"errorMessage = %@", db.lastErrorMessage);
        }
        
        if (![db executeUpdate:@"CREATE INDEX IF NOT EXISTS uid_entry_son on uid_entry(son_msg_id);"]) {
            DDLogError(@"errorMessage = %@", db.lastErrorMessage);
        }
        
        if (![db executeUpdate:@"CREATE INDEX IF NOT EXISTS uid_entry_folder on uid_entry(folder);"]) {
            DDLogError(@"errorMessage = %@", db.lastErrorMessage);
        }
    }];
}

+(void) addUid:(UidEntry*)uid_entry
{
    UidDBAccessor* databaseManager = [UidDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        
        if (![uid_entry.sonMsgID isEqualToString:@"0"]) {
            FMResultSet* result = [db executeQuery:@"SELECT * FROM uid_entry WHERE msg_id = ?", uid_entry.sonMsgID];
            
            if ([result next]) {
                NSString* son = [result stringForColumn:@"son_msg_id"];
                
                if (![son isEqualToString:@"0"]) {
                    uid_entry.sonMsgID = son;
                }
            }
            [result close];
        }
        
        FMResultSet* result = [db executeQuery:@"SELECT * FROM uid_entry WHERE msg_id = ? and folder = ?", uid_entry.msgID, @(uid_entry.folder + 1000 * uid_entry.accountNum)];
        
        //Doesn't exist
        if (![result next]) {
            [result close];
            
            BOOL res = [db executeUpdate:@"INSERT INTO uid_entry (uid,folder,msg_id,son_msg_id,dbNum) VALUES (?,?,?,?,?);",
                        @(uid_entry.uid),
                        @(uid_entry.folder + 1000 * uid_entry.accountNum),
                        uid_entry.msgID,
                        uid_entry.sonMsgID,
                        @(uid_entry.dbNum)];
            
            if (!res) {
                DDLogError(@"Add Uid in background:%@ failed", uid_entry.msgID);
            }
        }
        else {
            [result close];
        }
    }];
}

+(void) updateNewUID:(UidEntry*)uid_entry
{
    UidDBAccessor* databaseManager = [UidDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        [db executeUpdate:@"UPDATE uid_entry SET uid = ? WHERE msg_id = ? AND folder = ?;",
                    @(uid_entry.uid),
                    uid_entry.msgID,
                    @(uid_entry.folder + 1000 * uid_entry.accountNum)];
        
    }];
    
    if ([self getUidEntriesWithMsgId:uid_entry.msgID].count == 0) {
        NSInvocationOperation* nextOpUp = [[NSInvocationOperation alloc] initWithTarget:[EmailProcessor getSingleton] selector:@selector(removeEmail:) object:uid_entry];
        [[EmailProcessor getSingleton].operationQueue addOperation:nextOpUp];
    }
}

+(void) removeFromFolderUid:(UidEntry*)uid_entry
{
    if (uid_entry.uid == 0) {
        DDLogError(@"Draft not in DB no Delete");
        return;
    }
    
    UidDBAccessor* databaseManager = [UidDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        BOOL success =  [db executeUpdate:@"DELETE FROM uid_entry WHERE msg_id = ? AND folder = ?;",
                    uid_entry.msgID,
                    @(uid_entry.folder + 1000 * uid_entry.accountNum)];
        if (success) {
            DDLogInfo(@"UID Deleted");
        }
    }];
    
    if ([self getUidEntriesWithMsgId:uid_entry.msgID].count == 0) {
        NSInvocationOperation* nextOpUp = [[NSInvocationOperation alloc] initWithTarget:[EmailProcessor getSingleton] selector:@selector(removeEmail:) object:uid_entry];
        [[EmailProcessor getSingleton].operationQueue addOperation:nextOpUp];
    }
}

+(void) removeAllMsgID:(NSString*)msgID
{
    UidDBAccessor* databaseManager = [UidDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        BOOL success =  [db executeUpdate:@"DELETE FROM uid_entry WHERE msg_id = ? ;",
                         msgID];
        if (success) {
            DDLogInfo(@"UID Deleted");
        }
    }];
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

+(void) cleanBeforeDeleteinAccountNum:(NSInteger)accountNum
{
    NSMutableString* query = [NSMutableString string];
    [query appendFormat:@"SELECT msg_id, folder, count(*) c FROM uid_entry where folder LIKE '%ld___' GROUP BY msg_id HAVING c > 1;", (long)accountNum];
     
    [[UidDBAccessor sharedManager].databaseQueue inDatabase:^(FMDatabase* db) {
        FMResultSet* results = [db executeQuery:query];
        
        while ([results next]) {
            UidEntry* uidEntry = [[UidEntry alloc] init];
            
            uidEntry.folder = [results intForColumn:@"folder"] % 1000;
            uidEntry.msgID = [results stringForColumn:@"msg_id"];

            [db executeUpdate:@"DELETE FROM uid_entry WHERE msg_id = ? and folder = ?", uidEntry.msgID, @(uidEntry.folder)];
        }
    }];
}

+(NSMutableArray*) getUidEntriesinAccountNum:(NSInteger)accountNum andDelete:(BOOL)haveDeleted
{
    NSMutableArray* uids = [[NSMutableArray alloc] init];
    NSMutableSet* dbNums = [[NSMutableSet alloc] init];
    
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
                    if ([db executeUpdate:@"DELETE FROM uid_entry WHERE msg_id = ? ", uid.msgID]) {
                        DDLogInfo(@"UID Deleted");
                    }
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

+(NSMutableArray*) getUidEntriesWithMsgId:(NSString*)msgID
{
    NSMutableArray* uids = [[NSMutableArray alloc] init];
    
    UidDBAccessor* databaseManager = [UidDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        FMResultSet* results = [db executeQuery:@"SELECT * FROM uid_entry WHERE msg_id = ?", msgID]; //AND folder LIKE ?",msgID,[NSString stringWithFormat:@"%ld%%",(long)accountNum]];
        
        while ([results next]) {
            [uids addObject:[UidEntry resToUidEntry:results]];
        }
    }];
    
    return uids;
}

+(NSMutableArray*) getUidEntriesWithFolder:(NSInteger)folderNum inAccountNum:(NSInteger)accountNum;
{
    NSMutableArray* uids = [[NSMutableArray alloc] init];
    NSMutableSet* dbNums = [[NSMutableSet alloc] init];
    
    UidDBAccessor* databaseManager = [UidDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        FMResultSet* results = [db executeQuery:@"SELECT * FROM uid_entry WHERE folder = ? ORDER BY uid DESC LIMIT 50", @(folderNum + 1000 * accountNum)];
        
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

+(NSMutableArray*) getUidEntriesFrom:(Mail*)email withFolder:(NSInteger)folderNum inAccountNum:(NSInteger)accountNum
{
    NSMutableArray* uids = [[NSMutableArray alloc] init];
    NSMutableSet* dbNums = [[NSMutableSet alloc] init];
    
    UidDBAccessor* databaseManager = [UidDBAccessor sharedManager];
    
    UidEntry* uidE = [email uidEWithFolder:folderNum];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        FMResultSet* results;
        
        NSMutableString* query = [NSMutableString string];

            NSNumber* folderAccount = @(folderNum + 1000 * accountNum);

            if (folderNum != [[AppSettings userWithIndex:kActiveAccountIndex] numFolderWithFolder:CCMFolderTypeAll]) {
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

+(UidEntry*) getUidEntryWithFolder:(NSInteger)folderNum msgID:(NSString*)msgID
{
    UidDBAccessor* databaseManager = [UidDBAccessor sharedManager];
    
    UidEntry* __block uid_entry = [[UidEntry alloc]init];
    uid_entry.msgID = msgID;
    uid_entry.folder = folderNum;
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        FMResultSet* results = [db executeQuery:@"SELECT * FROM uid_entry WHERE folder LIKE ? AND msg_id = ?",
                                [NSString stringWithFormat:@"_%03ld", (long)uid_entry.folder],
                                msgID];
        
        if ([results next]) {
            uid_entry = [UidEntry resToUidEntry:results];
        }
        [results close];
    }];
    
    return uid_entry;
}

+(BOOL) hasUidEntrywithMsgId:(NSString*)msgID inAccount:(NSInteger)accountNum
{
    __block BOOL result = NO;
    NSString* folder = [NSString stringWithFormat:@"%ld___", (long)accountNum];
    
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    [[UidDBAccessor sharedManager].databaseQueue inDatabase:^(FMDatabase* db) {
        FMResultSet* results = [db executeQuery:@"SELECT * FROM uid_entry WHERE msg_id = ? AND folder LIKE ?", msgID, folder];
        
        if ([results next]) {
            result = YES;
            [results close];
            dispatch_semaphore_signal(semaphore);
            return;
        }
        
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    
    return result;
}

+(BOOL) hasUidEntrywithMsgId:(NSString*)msgID withFolder:(NSInteger)folderNum inAccount:(NSInteger)accountNum
{
    __block BOOL result = NO;
    
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);

    [[UidDBAccessor sharedManager].databaseQueue inDatabase:^(FMDatabase* db) {
        FMResultSet* results = [db executeQuery:@"SELECT folder FROM uid_entry WHERE msg_id = ? AND folder = ?", msgID, @(folderNum + 1000 * accountNum)];
        
        while ([results next]) {
            if (folderNum == -1 || folderNum == [results intForColumn:@"folder"] % 1000) {
                result = YES;
            }
        }
        
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    
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
    uidEntry.msgID = [result stringForColumn:@"msg_id"];
    uidEntry.accountNum = [result intForColumn:@"folder"] / 1000;
    uidEntry.sonMsgID = [result stringForColumn:@"son_msg_id"];
    uidEntry.dbNum = [result intForColumn:@"dbNum"];
    
    return uidEntry;
}

+(void) copy:(UidEntry*)uidE toFolder:(NSInteger)to
{
    if (uidE.uid == 0) {
        DDLogError(@"Draft not in DB no copy");
        return ;
    }
    
    //No Important folder at Index
    if (to == -1) {
#ifdef USING_INSTABUG
        IBGLog(@"Email not synced in folder, so can't move it");
#endif
        DDLogError(@"Email not synced in folder, so can't move it");
        return ;
    }
    
    UserSettings* user = [AppSettings userWithNum:uidE.accountNum];
    
    NSString* fromFolderName = [user folderServerName:uidE.folder];
    NSString* toFolderName = [user folderServerName:to];
    
    CachedAction* action = [CachedAction addActionWithUid:uidE actionIndex:4 toFolder:to];
    
    UidEntry* newUidE = [uidE copy];
    newUidE.uid = 0;
    newUidE.folder = to;
    [self addUid:newUidE];
    
    if ([[Reachability reachabilityForInternetConnection] currentReachabilityStatus] != NotReachable) {
        MCOIMAPCopyMessagesOperation* opMove = [[ImapSync sharedServices:user].imapSession copyMessagesOperationWithFolder:fromFolderName
                                                                                                                              uids:[MCOIndexSet indexSetWithIndex:uidE.uid]
                                                                                                                        destFolder:toFolderName];
        
        dispatch_async([ImapSync sharedServices:user].s_queue, ^{

        [opMove start:^(NSError* error, NSDictionary* destUids) {
            if (!error && destUids) {
                DDLogInfo(@"Email copied to folder!");
                
                [CachedAction removeAction:action];
                
                newUidE.uid = [destUids[@(uidE.uid)] unsignedIntValue];
                [self updateNewUID:newUidE];
                [CachedAction updateActionUID:newUidE];
            } else if (error) {
                DDLogError(@"Error copying email to folder:%@", error);
            }
        }];
            
        });
    }
}

+(void) move:(UidEntry*)uidE toFolder:(NSInteger)to
{
    if (uidE.uid == 0) {
        DDLogError(@"Draft not in DB no move");
        return ;
    }
    
    //No Important folder at Index
    if (to == -1) {
#ifdef USING_INSTABUG
        IBGLog(@"Email not synced in folder, so can't move it");
#endif
        DDLogError(@"Email not synced in folder, so can't move it");
        return ;
    }

    UserSettings* user = [AppSettings userWithNum:uidE.accountNum];
    
    NSString* fromFolderName = [user folderServerName:uidE.folder];
    NSString* toFolderName = [user folderServerName:to];
    
    [self removeFromFolderUid:uidE];
    
    CachedAction* action = [CachedAction addActionWithUid:uidE actionIndex:0 toFolder:to];
    
    UidEntry* newUidE = [uidE copy];
    newUidE.uid = 0;
    newUidE.folder = to;
    [self addUid:newUidE];
    
    if ([[Reachability reachabilityForInternetConnection] currentReachabilityStatus] != NotReachable) {
        MCOIMAPCopyMessagesOperation* opMove = [[ImapSync sharedServices:user].imapSession copyMessagesOperationWithFolder:fromFolderName
                                                                                                                              uids:[MCOIndexSet indexSetWithIndex:uidE.uid]
                                                                                                                        destFolder:toFolderName];
        dispatch_async([ImapSync sharedServices:user].s_queue, ^{

        [opMove start:^(NSError* error, NSDictionary* destUids) {
            if (!error && destUids) {
                DDLogInfo(@"Email copied to folder!");
                
                [CachedAction removeAction:action];
                
                [UidEntry deleteUidEntry:uidE];
                
                newUidE.uid = [destUids[@(uidE.uid)] unsignedIntValue];
                [self updateNewUID:newUidE];
                [CachedAction updateActionUID:newUidE];
            } else {
                if (error) {
                    DDLogError(@"Error copying email to folder:%@", error);
                }
            }
        }];
        });
    }
}

+(void) deleteUidEntry:(UidEntry*)uidE
{
    if (uidE.uid == 0) {
        DDLogError(@"Draft not in DB no delete");
        return ;
    }
    
    /*if (uidE.pk == 0) {
        CCMLog(@"Email doesn't look synced in folder, so deleting it might not work");
    }*/
    
    UserSettings* user = [AppSettings userWithNum:uidE.accountNum];
    
    [self removeFromFolderUid:uidE];

    CachedAction* action = [CachedAction addActionWithUid:uidE actionIndex:1 toFolder:-1];

    if ([[Reachability reachabilityForInternetConnection] currentReachabilityStatus] != NotReachable) {
        MCOIMAPOperation* op = [[ImapSync sharedServices:user].imapSession storeFlagsOperationWithFolder:[user folderServerName:uidE.folder]
                                                                                                            uids:[MCOIndexSet indexSetWithIndex:uidE.uid]
                                                                                                            kind:MCOIMAPStoreFlagsRequestKindSet
                                                                                                           flags:MCOMessageFlagDeleted];
        dispatch_async([ImapSync sharedServices:user].s_queue, ^{

        [op start:^(NSError* error) {
            if (!error) {
                DDLogInfo(@"Updated the deleted flags!");
                
                MCOIMAPOperation* deleteOp = [[ImapSync sharedServices:user].imapSession expungeOperation:[user folderServerName:uidE.folder]];
                [deleteOp start:^(NSError* error) {
                    if (error) {
                        DDLogError(@"Error expunging folder:%@", error);
                    }
                    else {
                        [CachedAction removeAction:action];
//                        DDLogInfo(@"Successfully expunged folder:%@", [AppSettings folderDisplayName:uidE.folder forAccountIndex:accountIndex]);
                    }
                }];
            }
            else {
                DDLogError(@"Error updating the deleted flags:%@", error);
            }
        }];
            
        });
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
        [copy setMsgID:self.msgID];
        [copy setSonMsgID:self.sonMsgID];
        [copy setAccountNum:self.accountNum];
        [copy setDbNum:self.dbNum];
    }
    
    return copy;
}

/*+(void) addFlag:(MCOMessageFlag)flag toMsgId:(NSString*)msg_id fromFolder:(NSInteger)folder
{
    return [UidEntry addFlag:flag to:[self getUidEntryWithFolder:folder msgID:msg_id]];
}*/

+(void) addFlag:(MCOMessageFlag)flag to:(UidEntry*)uidE
{
    if (uidE.uid == 0) {
        DDLogError(@"Draft not in DB no flagging");
        return ;
    }
    
    if (uidE.pk == 0) {
        DDLogError(@"Email not synced in folder, so can't add flag");
        return ;
    }
    
    CachedAction* action;
    if (flag & MCOMessageFlagFlagged) {
        action = [CachedAction addActionWithUid:uidE actionIndex:2 toFolder:-1];
    }
    
    Reachability* networkReachability = [Reachability reachabilityForInternetConnection];
    
    if ([networkReachability currentReachabilityStatus] != NotReachable) {
        UserSettings* user = [AppSettings userWithNum:uidE.accountNum];

        MCOIMAPOperation* op = [[ImapSync sharedServices:user].imapSession storeFlagsOperationWithFolder:[user folderServerName:[[Accounts sharedInstance].currentAccount currentFolderIdx]]
                                                                                                            uids:[MCOIndexSet indexSetWithIndex:uidE.uid]
                                                                                                            kind:MCOIMAPStoreFlagsRequestKindAdd
                                                                                                           flags:flag];
        dispatch_async([ImapSync sharedServices:user].s_queue, ^{

        [op start:^(NSError* error) {
            if (!error) {
                DDLogInfo(@"Added flag!");
                if (action) {
                    [CachedAction removeAction:action];
                }
                if ((flag & MCOMessageFlagFlagged)) {
                    [UidEntry copy:uidE toFolder:[user numFolderWithFolder:CCMFolderTypeFavoris]];
                }
            }
            else {
                DDLogError(@"Error adding flag email:%@", error);
            }
        }];
        });
    }
}

+(void) removeFlag:(MCOMessageFlag)flag toMsgId:(NSString*)msg_id fromFolder:(NSInteger)folder
{
    return [UidEntry removeFlag:flag to:[self getUidEntryWithFolder:folder msgID:msg_id]];
}

+(void) removeFlag:(MCOMessageFlag)flag to:(UidEntry*)uidE
{
    if (uidE.uid == 0) {
        DDLogError(@"Draft not in DB no unflagging");
        return ;
    }
    
    if (uidE.pk == 0) {
        DDLogError(@"Email not synced in folder, so can't remove flag");
        
        return ;
    }
    
    CachedAction* action;
    
    if (flag & MCOMessageFlagFlagged) {
        action = [CachedAction addActionWithUid:uidE actionIndex:3 toFolder:-1];
    }
    
    Reachability* networkReachability = [Reachability reachabilityForInternetConnection];
    
    if ([networkReachability currentReachabilityStatus] != NotReachable) {
        UserSettings* user = [AppSettings userWithNum:uidE.accountNum];
        MCOIMAPOperation* op = [[ImapSync sharedServices:user].imapSession storeFlagsOperationWithFolder:[user folderServerName:[[Accounts sharedInstance].currentAccount currentFolderIdx]]
                                                                                                            uids:[MCOIndexSet indexSetWithIndex:uidE.uid]
                                                                                                            kind:MCOIMAPStoreFlagsRequestKindRemove
                                                                                                           flags:flag];
        dispatch_async([ImapSync sharedServices:user].s_queue, ^{

        [op start:^(NSError* error) {
            if (!error) {
                DDLogInfo(@"Removed flag!");
                if (action) {
                    [CachedAction removeAction:action];
                }
                if ((flag & MCOMessageFlagFlagged)) {
                    [UidEntry deleteUidEntry:[UidEntry getUidEntryWithFolder:[user numFolderWithFolder:CCMFolderTypeFavoris] msgID:uidE.msgID]];
                }
            }
            else {
                DDLogError(@"Error removing flag:%@", error);
            }
        }];
        });
    }
}


+(NSArray*) dbNumsInAccountNum:(NSInteger)accountNum
{
    NSMutableArray* nums = [[NSMutableArray alloc]init];
    
    UidDBAccessor* databaseManager = [UidDBAccessor sharedManager];
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        FMResultSet* results;
        
        //if (accountIndex != [Accounts sharedInstance].accountsCount -1) {
            NSMutableString* query = [NSMutableString string];
            [query appendFormat:@"SELECT distinct(dbNum) FROM uid_entry WHERE folder LIKE '%ld___' ", (long)accountNum];
            results = [db executeQuery:query];
        /*}
        else {
            results = [db executeQuery:@"SELECT distinct(dbNum) FROM uid_entry"];
        }*/
        
        while ([results next]) {
            [nums addObject:@([results intForColumnIndex:0])];
        }
        
    }];

    NSSortDescriptor* sortOrder = [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(self)) ascending:NO];
    
    return [nums sortedArrayUsingDescriptors:@[sortOrder]];
}

-(BOOL) isEqualToUIDE:(UidEntry*)uidE
{
    if (!uidE) {
        return NO;
    }
    
    return [self.msgID isEqualToString:uidE.msgID] && (self.uid == uidE.uid) && (self.folder == uidE.folder);
}

-(BOOL) isEqual:(id)object
{
    if (self == object) {
        return YES;
    }
    
    if (![object isKindOfClass:[UidEntry class]]) {
        return NO;
    }
    
    return [self isEqualToUIDE:(UidEntry*)object];
}

@end
