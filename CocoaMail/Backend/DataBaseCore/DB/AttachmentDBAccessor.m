//
//  AttachmentDBAccessor.m
//  CocoaMail
//
//  Created by Christopher Hockley on 20/01/2012.
//  Copyright (c) 2012 Christopher Hockley. All rights reserved.
//

#import "AttachmentDBAccessor.h"
#import "StringUtil.h"
#import "sqlite3.h"

#define ATTACHMENTS_DB_NAME @"attachment.tdb"

@implementation AttachmentDBAccessor

#pragma mark Singleton Methods

+(id) sharedManager
{
	static id sharedMyManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedMyManager = [[self alloc] init];
    });
    
    return sharedMyManager;
}

#pragma mark Public Instance Methods

-(id) init
{
    self = [super init];
    
    if (self) {
        _databaseQueue = [[FMDatabaseQueue alloc] initWithPath:[self databaseFilepath] flags:SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FILEPROTECTION_NONE];
    }
    
    return self;
}

-(void) close
{
	// close DB
	if (_databaseQueue != NULL) {
		[_databaseQueue close];
	}
}

-(void) deleteDatabase
{
	[[NSFileManager defaultManager] removeItemAtPath:[self databaseFilepath] error:nil];
    _databaseQueue = NULL;
}

-(NSString*) databaseFilepath
{
	return [StringUtil filePathInDocumentsDirectoryForFileName:ATTACHMENTS_DB_NAME];
}


@end
