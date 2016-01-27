//
//  CachedAction.m
//  CocoaMail
//
//  Created by Christopher Hockley on 16/07/15.
//  Copyright (c) 2015 CocoaSoft. All rights reserved.
//

#import "CachedAction.h"
#import "CacheDBAccessor.h"

@implementation CachedAction

+(void) tableCheck
{
    CacheDBAccessor* databaseManager = [CacheDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        
        if (![db executeUpdate:@"CREATE TABLE IF NOT EXISTS cached_actions (pk INTEGER PRIMARY KEY, uid INTEGER, folder INTEGER, account INTEGER, action INTEGER, to_folder INTEGER, dbNum INTEGER)"]) {
            CCMLog(@"errorMessage = %@", db.lastErrorMessage);
        }
    }];
}

+(BOOL) addAction:(CachedAction*)action
{
    __block BOOL success = FALSE;
    CacheDBAccessor* databaseManager = [CacheDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        
        FMResultSet* result = [db executeQuery:@"SELECT * FROM cached_actions WHERE uid = ? AND folder = ? AND account = ? AND action = ?",
                               @(action.uid.uid),
                               @(action.uid.folder),
                               @(action.uid.account),
                               @(action.actionIndex)];
        
        if ([result next]) {
            success = true;
            [result close];
            return;
        }
        
        [result close];
        
        success =  [db executeUpdate:@"INSERT INTO cached_actions (uid,folder,account,action,to_folder,dbNum) VALUES (?,?,?,?,?,?);",
                    @(action.uid.uid),
                    @(action.uid.folder),
                    @(action.uid.account),
                    @(action.actionIndex),
                    @(action.toFolder),
                    @(action.uid.dbNum)];
        
    }];
    
    return success;
}

+(CachedAction*) addActionWithUid:(UidEntry*)uidEntry actionIndex:(NSInteger)pActionIndex toFolder:(NSInteger)folder
{
    CachedAction* cA = [[CachedAction alloc]init];
    cA.uid = uidEntry;
    cA.actionIndex = pActionIndex;
    cA.toFolder = folder;
    
    [CachedAction addAction:cA];
    
    return cA;
}

+(void) updateActionUID:(UidEntry*)uidEntry
{
    CacheDBAccessor* databaseManager = [CacheDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        [db executeUpdate:@"UPDATE cached_actions SET uid = ? WHERE uid = 0 AND folder = ? AND account = ? ;",
                    @(uidEntry.uid),
                    @(uidEntry.folder),
                    @(uidEntry.account)];
    }];
    
    NSMutableArray* acts = [CachedAction getActionsForAccount:uidEntry.account];
    for (CachedAction* act in acts) {
        [act doAction];
    }
}

+(BOOL) removeAction:(CachedAction*)action
{
    __block BOOL success = FALSE;
    CacheDBAccessor* databaseManager = [CacheDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        success =  [db executeUpdate:@"DELETE FROM cached_actions WHERE uid = ? AND folder = ? AND account = ? AND action = ?;",
                    @(action.uid.uid),
                    @(action.uid.folder),
                    @(action.uid.account),
                    @(action.actionIndex)];
    }];
    
    return success;
}

+(NSMutableArray*) getActions
{
    NSMutableArray* actions = [[NSMutableArray alloc] init];
    CacheDBAccessor* databaseManager = [CacheDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        FMResultSet* results = [db executeQuery:@"SELECT * FROM cached_actions"];
        
        while ([results next]) {
            CachedAction* cachedA = [[CachedAction alloc]init];
            
            cachedA.pk = [results intForColumn:@"pk"];
            cachedA.actionIndex = [[results objectForColumnName:@"action"] integerValue];
            cachedA.toFolder = [[results objectForColumnName:@"to_folder"] integerValue];
            cachedA.uid = [[UidEntry alloc]init];
            cachedA.uid.uid = [[results objectForColumnName:@"uid"] unsignedIntValue];
            cachedA.uid.folder = [[results objectForColumnName:@"folder"] integerValue];
            cachedA.uid.account = [[results objectForColumnName:@"account"] integerValue];
            cachedA.uid.dbNum = [results intForColumn:@"dbNum"];
            [actions addObject:cachedA];
        }
        
    }];
    
    return actions;
}

+(NSMutableArray*) getActionsForAccount:(NSInteger)accountNum
{
    NSMutableArray* actions = [[NSMutableArray alloc] init];
    CacheDBAccessor* databaseManager = [CacheDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        FMResultSet* results = [db executeQuery:@"SELECT * FROM cached_actions WHERE account = ?",
                                @(accountNum)];
        
        while ([results next]) {
            CachedAction* cachedA = [[CachedAction alloc]init];
            
            cachedA.pk = [results intForColumn:@"pk"];
            cachedA.actionIndex = [[results objectForColumnName:@"action"] integerValue];
            cachedA.toFolder = [[results objectForColumnName:@"to_folder"] integerValue];
            cachedA.uid = [[UidEntry alloc]init];
            cachedA.uid.uid = [[results objectForColumnName:@"uid"] unsignedIntValue];
            cachedA.uid.folder = [[results objectForColumnName:@"folder"] integerValue];
            cachedA.uid.account = [[results objectForColumnName:@"account"] integerValue];
            cachedA.uid.dbNum = [results intForColumn:@"dbNum"];

            [actions addObject:cachedA];
        }
        
    }];
    
    return actions;
}

-(void) doAction
{
    if (self.uid.uid == 0) {
        return;
    }
    
    switch (self.actionIndex) {
        case 0:
            [UidEntry move:self.uid toFolder:self.toFolder];
            break;
        case 1:
            //self.uid.pk = -1;
            [UidEntry deleteUidEntry:self.uid];
            break;
        case 2:
            [UidEntry addFlag:MCOMessageFlagFlagged to:self.uid];
            break;
        case 3:
            [UidEntry removeFlag:MCOMessageFlagFlagged to:self.uid];
            break;
        case 4:
            [UidEntry copy:self.uid toFolder:self.toFolder];
            break;
        default:
            break;
    }
    
    [CachedAction removeAction:self];
}


@end
