//
//  EmailDBAccessor.m
//  CocoaMail
//
//  Created by Christopher Hockley on 20/01/2012.
//  Copyright (c) 2012 Christopher Hockley. All rights reserved.
//

#import "EmailDBAccessor.h"
#import "AppSettings.h"
#import "sqlite3.h"

@implementation EmailDBAccessor

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
	NSString* path = [self databaseFilepath];
	NSFileManager* fm = [NSFileManager defaultManager];
	[fm removeItemAtPath:path error:nil];
	
	_databaseQueue = NULL;
}

#pragma mark Private Methods

-(void) setDatabaseFilepath:(NSString*)databaseFilepath
{
    _databaseFilepath = databaseFilepath;
    _databaseQueue = [FMDatabaseQueue databaseQueueWithPath:[self databaseFilepath] flags:SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FILEPROTECTION_NONE];
}

-(NSString*) databaseFilepath
{
	if (_databaseFilepath == nil) {
		NSMutableString* ret = [NSMutableString string];
		NSString* appName = [[NSProcessInfo processInfo] processName];
		for (NSUInteger i = 0; i < [appName length]; i++) {
			NSRange range = NSMakeRange(i, 1);
            
			NSString* oneChar = [appName substringWithRange:range];
            
            if (![oneChar isEqualToString:@" "]) {
				[ret appendString:[oneChar lowercaseString]];
            }
		}
		
		NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
		NSString* saveDirectory = paths[0];
		NSString* saveFileName = [NSString stringWithFormat:@"%@.sqlite3", ret];
		NSString* filepath = [saveDirectory stringByAppendingPathComponent:saveFileName];
		
        _databaseFilepath = filepath;
		
        NSDictionary* attributes = @{NSFileProtectionKey: NSFileProtectionNone};

        if (![[NSFileManager defaultManager] fileExistsAtPath:saveDirectory]) {
			[[NSFileManager defaultManager] createDirectoryAtPath:saveDirectory withIntermediateDirectories:YES attributes:attributes error:nil];
        }
	}
    
	return _databaseFilepath;
}

@end

@implementation EmailDBReader

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

#pragma mark Private Methods

-(void) setDatabaseFilepath:(NSString*)databaseFilepath
{
    _databaseFilepath = databaseFilepath;
    _databaseQueue = [FMDatabaseQueue databaseQueueWithPath:[self databaseFilepath] flags:SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FILEPROTECTION_NONE];
}

-(NSString*) databaseFilepath
{
    if (_databaseFilepath == nil) {
        NSMutableString* ret = [NSMutableString string];
        NSString* appName = [[NSProcessInfo processInfo] processName];
        for (NSUInteger i = 0; i < [appName length]; i++) {
            NSRange range = NSMakeRange(i, 1);
            
            NSString* oneChar = [appName substringWithRange:range];
            
            if (![oneChar isEqualToString:@" "]) {
                [ret appendString:[oneChar lowercaseString]];
            }
        }
        
        NSArray* paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString* saveDirectory = paths[0];
        NSString* saveFileName = [NSString stringWithFormat:@"%@.sqlite3", ret];
        NSString* filepath = [saveDirectory stringByAppendingPathComponent:saveFileName];
        
        _databaseFilepath = filepath;
        
        NSDictionary* attributes = @{NSFileProtectionKey: NSFileProtectionNone};
        
        if (![[NSFileManager defaultManager] fileExistsAtPath:saveDirectory]) {
            [[NSFileManager defaultManager] createDirectoryAtPath:saveDirectory withIntermediateDirectories:YES attributes:attributes error:nil];
        }
    }
    
    return _databaseFilepath;
}

@end
