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

@implementation UidEntry

@synthesize pk,uid,folder,msgId,account,sonMsgId;

+ (void)tableCheck
{
    UidDBAccessor *databaseManager = [UidDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase *db) {
        
        if (![db executeUpdate:@"CREATE TABLE uid_entry (pk INTEGER PRIMARY KEY, uid INTEGER, folder INTEGER, msg_id TEXT, son_msg_id TEXT)"])
            CCMLog(@"errorMessage = %@",db.lastErrorMessage);
        
        if (![db executeUpdate:@"CREATE INDEX IF NOT EXISTS uid_entry_md5 on uid_entry(msg_id);"])
            CCMLog(@"errorMessage = %@",db.lastErrorMessage);
        
        if (![db executeUpdate:@"CREATE INDEX IF NOT EXISTS uid_entry_son on uid_entry(son_msg_id);"])
            CCMLog(@"errorMessage = %@",db.lastErrorMessage);
        
        if (![db executeUpdate:@"CREATE INDEX IF NOT EXISTS uid_entry_folder on uid_entry(folder);"])
            CCMLog(@"errorMessage = %@",db.lastErrorMessage);
        
    }];
}

+ (BOOL)addUid:(UidEntry *) uid_entry
{
    __block BOOL success = FALSE;
    UidDBAccessor *databaseManager = [UidDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase *db) {
        
        if (![uid_entry.sonMsgId isEqualToString:@"0"]) {
            FMResultSet *result = [db executeQuery:@"SELECT * FROM uid_entry WHERE msg_id = ?",uid_entry.sonMsgId];
            if([result next]){
                NSString *son = [result stringForColumn:@"son_msg_id"];
                if (![son isEqualToString:@"0"]) {
                    uid_entry.sonMsgId = son;
                }
            }
            [result close];
        }
        
        success =  [db executeUpdate:@"INSERT INTO uid_entry (uid,folder,msg_id,son_msg_id) VALUES (?,?,?,?);",
                    @(uid_entry.uid),
                    @(uid_entry.folder+1000*uid_entry.account),
                    uid_entry.msgId,
                    uid_entry.sonMsgId];
        
    }];
    return success;
}

+(BOOL) addUidUnsafe:(UidEntry *) uid_entry
{
    BOOL success = FALSE;
    UidDBAccessor *databaseManager = [UidDBAccessor sharedManager];
    
    FMDatabase *database = [FMDatabase databaseWithPath:databaseManager.databaseFilepath];
    [database open];
    
    if (![uid_entry.sonMsgId isEqualToString:@"0"]) {
        FMResultSet *result = [database executeQuery:@"SELECT * FROM uid_entry WHERE msg_id = ?",uid_entry.sonMsgId];
        if([result next]){
            NSString *son = [result stringForColumn:@"son_msg_id"];
            if (![son isEqualToString:@"0"]) {
                uid_entry.sonMsgId = son;
            }
        }
        [result close];
    }
    
    success =  [database executeUpdate:@"INSERT INTO uid_entry (uid,folder,msg_id,son_msg_id) VALUES (?,?,?,?);",
                @(uid_entry.uid),
                @(uid_entry.folder+1000*uid_entry.account),
                uid_entry.msgId,
                uid_entry.sonMsgId];
    
    [database close];
    return success;
}

+(BOOL) removeFromFolderUid:(UidEntry *) uid_entry
{
    __block BOOL success = FALSE;
    UidDBAccessor *databaseManager = [UidDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase *db) {
        success =  [db executeUpdate:@"DELETE FROM uid_entry WHERE msg_id = ? AND folder = ?;",
                    uid_entry.msgId,
                    @(uid_entry.folder+1000*uid_entry.account)];
        
    }];
    
    if ([self getUidEntriesWithMsgId:uid_entry.msgId].count == 0){
        [Email removeEmail:uid_entry.msgId];
    }
    
    return success;
}

+(BOOL) removeFromAccount:(NSInteger) accountN
{
    __block BOOL success = FALSE;
    UidDBAccessor *databaseManager = [UidDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase *db) {
        success =  [db executeUpdate:@"DELETE FROM uid_entry WHERE folder LIKE ?;",
                    [NSString stringWithFormat:@"%li___", (long)accountN]];
        
    }];
    
    return success;
}

+(BOOL) removeFromAllFoldersUid:(UidEntry *) uid_entry
{
    __block BOOL success = FALSE;
    UidDBAccessor *databaseManager = [UidDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase *db) {
        success =  [db executeUpdate:@"DELETE FROM uid_entry WHERE msg_id = ?;", uid_entry.msgId];
        
    }];
    
    [Email removeEmail:uid_entry.msgId];
    return success;
}

+ (NSMutableArray *)getUidEntries
{
    NSMutableArray *uids = [[NSMutableArray alloc] init];
    
    UidDBAccessor *databaseManager = [UidDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *results = [db executeQuery:@"SELECT * FROM uid_entry"];
        
        while([results next])
        {
            [uids addObject:[UidEntry resToUidEntry:results]];
        }
        
    }];
    return uids;
}

+ (NSMutableArray*)getUidEntriesWithThread:(NSString*)son_msgId
{
    NSMutableArray *uids = [[NSMutableArray alloc] init];
    
    UidDBAccessor *databaseManager = [UidDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *results = [db executeQuery:@"SELECT * FROM uid_entry WHERE son_msg_id = ?",son_msgId];
        
        while([results next])
        {
            [uids addObject:[UidEntry resToUidEntry:results]];
            
        }
    }];
    return uids;
}


+ (NSMutableArray*)getUidEntriesWithMsgId:(NSString*)msgId
{
    NSMutableArray *uids = [[NSMutableArray alloc] init];
    
    UidDBAccessor *databaseManager = [UidDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *results = [db executeQuery:@"SELECT * FROM uid_entry WHERE msg_id = ?",msgId]; //AND folder LIKE ?",msgId,[NSString stringWithFormat:@"%ld%%",(long)accountNum]];
        
        while([results next])
        {
            [uids addObject:[UidEntry resToUidEntry:results]];
        }
    }];
    
    return uids;
}

+ (NSMutableArray *)getUidEntriesWithFolder:(NSInteger)folderNum
{
    NSMutableArray *uids = [[NSMutableArray alloc] init];
    
    UidDBAccessor *databaseManager = [UidDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *results;
        if(!kisActiveAccountAll)
            results = [db executeQuery:@"SELECT * FROM uid_entry WHERE folder = ?",@(folderNum+1000*kActiveAccountNum)];
        else
            results = [db executeQuery:@"SELECT * FROM uid_entry WHERE folder LIKE ?",[NSString stringWithFormat:@"_%03ld",(long)folderNum]];
        
        while([results next])
        {
            [uids addObject:[UidEntry resToUidEntry:results]];
        }
        
    }];
    
    return uids;
}

+ (NSMutableArray *)getUidEntriesFrom:(NSInteger)from withFolder:(NSInteger)folderNum
{
    NSMutableArray *uids = [[NSMutableArray alloc] init];
    
    UidDBAccessor *databaseManager = [UidDBAccessor sharedManager];
    NSNumber *offset = @(from);
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *results;
        NSMutableString *query = [NSMutableString string];

        if(!kisActiveAccountAll) {
            NSNumber *folderAccount = @(folderNum+1000*kActiveAccountNum);

            if (folderNum != [AppSettings importantFolderNumforAccountIndex:kActiveAccountIndex forBaseFolder:FolderTypeAll]) {
                [query appendFormat:@"SELECT * FROM uid_entry t WHERE t.folder = %@ AND t.msg_id NOT IN (SELECT c.son_msg_id FROM uid_entry c)"
                         "OR t.folder != %@ "
                         "AND t.son_msg_id IN (SELECT c.msg_id FROM uid_entry c WHERE c.folder = %@)"
                         "ORDER BY uid DESC LIMIT 100 OFFSET %@",folderAccount,folderAccount,folderAccount, offset];
            }
            else {
                NSString* folder = [NSString stringWithFormat:@"'%ld___'",(long)kActiveAccountNum];
                [query appendFormat:@"SELECT * FROM uid_entry t WHERE t.folder LIKE %@ "
                         "ORDER BY uid DESC LIMIT 100 OFFSET %@",folder, offset];
            }
            
            results = [db executeQuery:query];
            
            while([results next])
            {
                [uids addObject:[UidEntry resToUidEntry:results]];
                //NSAssert([(UidEntry*)[uids lastObject] folder] == folderNum, @"Email from folder:%i trying to be added to folder:%i using query:%@",[(UidEntry*)[uids lastObject] folder],folderNum,query);
            }
            
        }
        else {
            
            [query appendString:@"SELECT * FROM uid_entry WHERE "];
            
            for (Account* ac in [Accounts sharedInstance].getAllTheAccounts) {
                NSNumber *folderAccount = @([AppSettings numFolderWithFolder:FolderTypeWith(folderNum, 0) forAccountIndex:ac.idx]+1000*[AppSettings numForData:ac.idx]);
                [query appendFormat:@"folder = %@ OR ",folderAccount];
            }
            
            query = [[NSMutableString alloc]initWithString:[query substringToIndex:(query.length-3)]];
            
            //[query appendFormat:@" ORDER BY uid DESC LIMIT 100 OFFSET %@",offset];
            [query appendString:@" ORDER BY uid DESC LIMIT 100"];
            results = [db executeQuery:query];
            
            while([results next])
            {
                [uids addObject:[UidEntry resToUidEntry:results]];
                //NSAssert([(UidEntry*)[uids lastObject] folder] == folderNum, @"Email from folder:%i trying to be added to folder:%i using query:%@",[(UidEntry*)[uids lastObject] folder],folderNum,query);
            }
        }
        
    }];
    
    return uids;
}

+ (UidEntry *) getUidEntryAtPk:(NSInteger)pk
{
    UidDBAccessor *databaseManager = [UidDBAccessor sharedManager];
    
    UidEntry *uid_entry = [[UidEntry alloc]init];
    uid_entry.pk = pk;
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *results = [db executeQuery:@"SELECT * FROM uid_entry WHERE pk = ?",uid_entry.pk];
        
        if([results next]){
            uid_entry.pk = [results intForColumn:@"pk"];
            uid_entry.uid = [results intForColumn:@"uid"];
            uid_entry.account = [results intForColumn:@"folder"] / 1000;
            uid_entry.sonMsgId = [results stringForColumn:@"son_msg_id"];
        }
        [results close];
    }];
    
    return uid_entry;
}

+ (UidEntry *)getUidEntryWithFolder:(NSInteger)folderNum msgId:(NSString*)msgId
{
    UidDBAccessor *databaseManager = [UidDBAccessor sharedManager];
    
    UidEntry *uid_entry = [[UidEntry alloc]init];
    uid_entry.msgId = msgId;
    uid_entry.folder = folderNum;
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase *db) {
        FMResultSet *results = [db executeQuery:@"SELECT * FROM uid_entry WHERE folder LIKE ? AND msg_id = ?",
                                [NSString stringWithFormat:@"_%03ld",(long)uid_entry.folder],
                                msgId];
        
        if([results next]){
            uid_entry.pk = [results intForColumn:@"pk"];
            uid_entry.uid = [results intForColumn:@"uid"];
            uid_entry.account = [results intForColumn:@"folder"] / 1000;
            uid_entry.sonMsgId = [results stringForColumn:@"son_msg_id"];
        }
        [results close];
    }];
    
    return uid_entry;
}

+(BOOL) hasUidEntrywithMsgId:(NSString*)msgId withFolder:(NSInteger)folderNum
{
    __block BOOL result = NO;
    
    UidDBAccessor *databaseManager = [UidDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase *db) {
        
        FMResultSet * results = [db executeQuery:@"SELECT folder FROM uid_entry WHERE msg_id = ?",msgId];
        
        while([results next])
        {
            if (folderNum == -1 || folderNum == [results intForColumn:@"folder"] % 1000) {
                result = YES;
            }
        }
    }];
    
    return result;
}

+ (void) res:(FMResultSet*)result ToUidEntry:(UidEntry*)uidEntry
{
    uidEntry = [UidEntry resToUidEntry:result];
}

+ (UidEntry*) resToUidEntry:(FMResultSet*)result
{
    UidEntry *uidEntry = [[UidEntry alloc] init];
    
    uidEntry.pk = [result intForColumn:@"pk"];
    uidEntry.uid = [[result objectForColumnName:@"uid"] unsignedIntValue];
    uidEntry.folder = [result intForColumn:@"folder"] % 1000;
    uidEntry.msgId = [result stringForColumn:@"msg_id"];
    uidEntry.account = [result intForColumn:@"folder"] / 1000;
    uidEntry.sonMsgId = [result stringForColumn:@"son_msg_id"];
    
    return uidEntry;
}

+ (BOOL)moveMsgId:(NSString*)msg_id inFolder:(NSInteger)from toFolder:(NSInteger)to
{
    return [UidEntry move:[UidEntry getUidEntryWithFolder:from msgId:msg_id] toFolder:to];
}

+ (BOOL)move:(UidEntry*)uidE toFolder:(NSInteger)to
{
    __block BOOL success = false;
    
    //No Important folder at Index
    if(to == -1){
        return true;
    }
    
    NSString *folderName = [AppSettings folderName:to forAccountIndex:[AppSettings indexForAccount:uidE.account]];
    
    Reachability *networkReachability = [Reachability reachabilityForInternetConnection];
    if ([networkReachability currentReachabilityStatus] != NotReachable) {
        MCOIMAPCopyMessagesOperation * opMove = [[ImapSync sharedServices:[AppSettings indexForAccount:uidE.account]].imapSession copyMessagesOperationWithFolder:[AppSettings folderName:uidE.folder forAccountIndex:[AppSettings indexForAccount:uidE.account]]
                                                                                                                               uids:[MCOIndexSet        indexSetWithIndex:uidE.uid]
                                                                                                                         destFolder:folderName];
        [opMove start:^(NSError * error,NSDictionary * destUids) {
            if(!error) {
                CCMLog(@"Updated folder!");
                
                success = true;
                
                if (destUids) {
                    uidE.folder = to;
                    uidE.uid = [destUids[[NSString stringWithFormat:@"%u",uidE.uid]] unsignedIntValue];
                    uidE.sonMsgId = uidE.sonMsgId;
                    [self addUid:uidE];
                }
            }
            else {
                CCMLog(@"Error updating label:%@", error);
            }
        }];
    }
    else {
        [CachedAction addActionWithUid:uidE actionIndex:0 toFolder:to];
    }
    
    return success;
}

+ (BOOL)deleteMsgId:(NSString*)msg_id fromfolder:(NSInteger)from
{
    return [UidEntry delete:[UidEntry getUidEntryWithFolder:from msgId:msg_id]];
}

+ (BOOL)delete:(UidEntry*)uidE
{
    __block BOOL success = false;

    if (uidE.pk == 0) {
        CCMLog(@"Email not synced in folder, so can't delete it");
        return success;
    }
    
    Reachability *networkReachability = [Reachability reachabilityForInternetConnection];
    if ([networkReachability currentReachabilityStatus] != NotReachable) {
        MCOIMAPOperation *op = [[ImapSync sharedServices:[AppSettings indexForAccount:uidE.account]].imapSession storeFlagsOperationWithFolder:[AppSettings folderName:uidE.folder forAccountIndex:[AppSettings indexForAccount:uidE.account]]
                                                                                                            uids:[MCOIndexSet indexSetWithIndex:uidE.uid]
                                                                                                            kind:MCOIMAPStoreFlagsRequestKindSet
                                                                                                           flags:MCOMessageFlagDeleted];
        [op start:^(NSError * error) {
            if(!error) {
                CCMLog(@"Updated flags!");
            } else {
                CCMLog(@"Error updating flags:%@", error);
            }
            
            MCOIMAPOperation *deleteOp = [[ImapSync sharedServices:[AppSettings indexForAccount:uidE.account]].imapSession expungeOperation:[AppSettings folderName:uidE.folder forAccountIndex:[AppSettings indexForAccount:uidE.account]]];
            [deleteOp start:^(NSError *error) {
                if(error) {
                    CCMLog(@"Error expunging folder:%@", error);
                } else {
                    success = true;
                    CCMLog(@"Successfully expunged folder:%@",[AppSettings folderName:uidE.folder forAccountIndex:[AppSettings indexForAccount:uidE.account]]);
                    [self removeFromFolderUid:uidE ];
                }
            }];
        }];
    }
    else {
        [CachedAction addActionWithUid:uidE actionIndex:1 toFolder:-1];
    }
    
    return success;
}

+ (void)deleteAllfromAccount:(NSInteger)accountN{
    [self removeFromAccount:accountN];
}

- (UidEntry*)copyWithZone:(NSZone *)zone
{
    UidEntry* copy = [[[self class] alloc] init];
    
    if (copy)
    {
        [copy setPk:self.pk];
        [copy setUid:self.uid];
        [copy setFolder:self.folder];
        [copy setMsgId:self.msgId];
        [copy setSonMsgId:self.sonMsgId];
        [copy setAccount:self.account];
    }
    
    return copy;
}

+ (BOOL)addFlag:(MCOMessageFlag)flag toMsgId:(NSString*)msg_id fromFolder:(NSInteger)folder
{
    return [UidEntry addFlag:flag to:[self getUidEntryWithFolder:folder msgId:msg_id]];
}

+ (BOOL)addFlag:(MCOMessageFlag)flag to:(UidEntry*)uidE
{
    __block BOOL success = false;

    Reachability *networkReachability = [Reachability reachabilityForInternetConnection];
    if ([networkReachability currentReachabilityStatus] != NotReachable) {
        MCOIMAPOperation *op = [[ImapSync sharedServices:[AppSettings indexForAccount:uidE.account]].imapSession storeFlagsOperationWithFolder:[AppSettings folderName:[[Accounts sharedInstance].currentAccount currentFolderIdx] forAccountIndex:[AppSettings indexForAccount:uidE.account]]
                                                                                                            uids:[MCOIndexSet indexSetWithIndex:uidE.uid]
                                                                                                            kind:MCOIMAPStoreFlagsRequestKindAdd
                                                                                                           flags:flag];
        [op start:^(NSError * error) {
            if(!error) {
                CCMLog(@"Added flag!");
                success = true;
            } else {
                CCMLog(@"Error adding flag email:%@", error);
            }
        }];
    }
    else {
        if(flag & MCOMessageFlagFlagged){
            [CachedAction addActionWithUid:uidE actionIndex:2 toFolder:-1];
        }
    }
    
    if (success & (flag & MCOMessageFlagFlagged)) {
        [UidEntry move:uidE toFolder:[AppSettings importantFolderNumforAccountIndex:[AppSettings indexForAccount:uidE.account] forBaseFolder:FolderTypeFavoris]];
    }
    
    return success;
}

+ (BOOL)removeFlag:(MCOMessageFlag)flag toMsgId:(NSString*)msg_id fromFolder:(NSInteger)folder
{
    return [UidEntry removeFlag:flag to:[self getUidEntryWithFolder:folder msgId:msg_id]];
}

+ (BOOL)removeFlag:(MCOMessageFlag)flag to:(UidEntry*)uidE
{
    __block BOOL success = false;

    Reachability *networkReachability = [Reachability reachabilityForInternetConnection];
    if ([networkReachability currentReachabilityStatus] != NotReachable) {
        MCOIMAPOperation *op = [[ImapSync sharedServices:[AppSettings indexForAccount:uidE.account]].imapSession storeFlagsOperationWithFolder:[AppSettings folderName:[[Accounts sharedInstance].currentAccount currentFolderIdx] forAccountIndex:[AppSettings indexForAccount:uidE.account]]
                                                                                                            uids:[MCOIndexSet indexSetWithIndex:uidE.uid]
                                                                                                            kind:MCOIMAPStoreFlagsRequestKindRemove
                                                                                                           flags:flag];
        [op start:^(NSError * error) {
            if(!error) {
                CCMLog(@"Removed flag!");
                success = true;
            } else {
                CCMLog(@"Error removing flag:%@", error);
            }
        }];
    }
    else {
        if(flag & MCOMessageFlagFlagged){
            [CachedAction addActionWithUid:uidE actionIndex:3 toFolder:-1];
        }
    }
    
    if (success & (flag & MCOMessageFlagFlagged)) {
        [UidEntry deleteMsgId:uidE.msgId fromfolder:[AppSettings importantFolderNumforAccountIndex:[AppSettings indexForAccount:uidE.account] forBaseFolder:FolderTypeFavoris]];
    }
    
    return success;
}

@end
