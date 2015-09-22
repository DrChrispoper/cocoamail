//
//  CacheDBAccessor.m
//  CocoaMail
//
//  Created by Christopher Hockley on 16/07/15.
//  Copyright (c) 2015 CocoaSoft. All rights reserved.
//

#import "CacheDBAccessor.h"
#import "StringUtil.h"

#define CACHE_DB_NAME @"cache.tdb"

@implementation CacheDBAccessor

#pragma mark Singleton Methods

+ (id)sharedManager
{
    static id sharedMyManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedMyManager = [[self alloc] init];
    });
    return sharedMyManager;
}

#pragma mark Public Instance Methods

- (id)init
{
    self = [super init];
    if (self) {
        _databaseQueue = [[FMDatabaseQueue alloc] initWithPath:[self databaseFilepath] flags:SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FILEPROTECTION_COMPLETEUNTILFIRSTUSERAUTHENTICATION];
    }
    return self;
}

-(void)close
{
    // close DB
    if(_databaseQueue != NULL) {
        [_databaseQueue close];
    }
}

- (void)deleteDatabase
{
    [[NSFileManager defaultManager] removeItemAtPath:[self databaseFilepath] error:nil];
    _databaseQueue = NULL;
}

- (NSString *)databaseFilepath
{
    return [StringUtil filePathInDocumentsDirectoryForFileName:CACHE_DB_NAME];
}

@end
