//
//  EmailProcessor.m
//  CocoaMail
//
//  Created by Christopher Hockley on 20/01/2012.
//  Copyright (c) 2012 Christopher Hockley. All rights reserved.
//

#import "EmailProcessor.h"
#import "SyncManager.h"
#import "SearchRunner.h"
#import "EmailProcessor.h"
#import "StringUtil.h"
#import "GlobalDBFunctions.h"
#import "EmailDBAccessor.h"
#import "AppSettings.h"
#import "UidEntry.h"
#import "CCMAttachment.h"
#import "FMDatabase.h"
#import "Accounts.h"
#import "UserSettings.h"

#define SECONDS_PER_DAY 86400.0 //24*3600
#define FOLDER_COUNT_LIMIT 999 // maximum number of folders allowed
#define ADDS_PER_TRANSACTION 20

static EmailProcessor * singleton = nil;

@implementation EmailProcessor

@synthesize dbDateFormatter;
@synthesize operationQueue;
@synthesize shuttingDown;

BOOL firstOne = YES; // caused effect: Don't endTransaction when we're just starting
BOOL transactionOpen = NO; // caused effect (with firstOne): After we start up, don't wrap the first ADDS_PER_TRANSACTION calls into a transaction

+(EmailProcessor*) getSingleton
{
	@synchronized(self) {
		if (singleton == nil) {
			singleton = [[self alloc] init];
		}
	}
    
	return singleton;
}

-(id) init
{
	self = [super init];
	
	if (self) {
		self.shuttingDown = NO;
		
		NSOperationQueue* ops = [[NSOperationQueue alloc] init];
		[ops setMaxConcurrentOperationCount:1]; // note that this makes it a simple, single queue (i.e. non-concurrent)
		self.operationQueue = ops;
		
        NSLocale* enUSPOSIXLocale;
        enUSPOSIXLocale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
		NSDateFormatter* df = [[NSDateFormatter alloc] init];
        [df setLocale:enUSPOSIXLocale];
		[df setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSSS"];
		self.dbDateFormatter = df;
		
		currentDBNum = -1;
		addsSinceTransaction = 0;
		transactionOpen = NO;
	}
	
	return self;
}

#pragma mark AddEmailDB Management stuff

-(void) rolloverAddEmailDBTo:(NSInteger)dbNum
{
    DDLogDebug(@"-[EmailProcessor rolloverAddEmailDBTo:dbNum]");

	//[[[EmailDBAccessor sharedManager] databaseQueue] close];
	
	// create new, empty db file
	NSString* fileName = [GlobalDBFunctions dbFileNameForNum:dbNum];
	NSString* dbPath = [StringUtil filePathInDocumentsDirectoryForFileName:fileName];
    
    DDLogDebug(@"\tdbNum    = %ld",(long)dbNum);
    DDLogDebug(@"\tfilename = \"%@\"",fileName);
//    DDLogDebug(@"\tdbPath   = \"%@\"",dbPath);
    
	if (![[NSFileManager defaultManager] fileExistsAtPath:dbPath]) {
        [[NSFileManager defaultManager] createFileAtPath:dbPath contents:nil attributes:@{NSFileProtectionKey: NSFileProtectionNone}];
        DDLogDebug(@"\tdatabase doesn't exist, creating");
	}
    
	[[EmailDBAccessor sharedManager] setDatabaseFilepath:[StringUtil filePathInDocumentsDirectoryForFileName:fileName]];
	
    [Mail tableCheck];
}

+(NSInteger) folderCountLimit
{
	return FOLDER_COUNT_LIMIT;
}

+(NSInteger) dbNumForDate:(NSDate*)date
{
	double timeSince1970 = [date timeIntervalSince1970];
	
	NSInteger dbNum = (NSInteger)(floor(timeSince1970 / SECONDS_PER_DAY / 3.0)) * 100; // The *100 is to avoid overlap with date files from the past
	
	dbNum = MAX(0, dbNum);
	
	return dbNum;
}

-(void) _switchDBForMail:(Mail*)mail
{
    [self _switchToDBNum:[EmailProcessor dbNumForDate:mail.datetime]];
}

-(void) _switchToDBNum:(NSInteger)dbNum
{
    if (self.shuttingDown) {
        return;
    }
	
	if (currentDBNum != dbNum) {
		// need to switch between DBs

		[self rolloverAddEmailDBTo:dbNum];
		
		currentDBNum = dbNum;
	}
}

-(void) addToFolderWrapper:(UidEntry*)data
{
	[UidEntry addUid:data];
}

-(void)clean:(Mail *)mail
{
    [Mail clean:mail.msgID dbNum:[EmailProcessor dbNumForDate:mail.datetime]];
}

-(void) updateFlag:(NSMutableArray<Mail*>*)emails
{
    if (self.shuttingDown) {
        return;
    }
    
    for (Mail* mail in emails) {
        [self _switchDBForMail:mail];
        [Mail updateMail:mail];             // Update mail in DB
    }
    
    UserSettings* user  = [emails firstObject].user;
    
    if (user && !user.isDeleted) {
        [user.linkedAccount deliverUpdate:emails];      // Update mail in local store
    }
}

-(void) removeFromFolderWrapper:(NSDictionary*)data
{
    [self _removeFromFolder:data[@"datas"] folderIndex:[data[@"folderIdx"] integerValue]];
}

-(void) _removeFromFolder:(NSArray<Mail*>*)emails folderIndex:(NSInteger)folderIdx
{
    if (self.shuttingDown) {
        return;
    }
    
	for (Mail* mail in emails) {
        [UidEntry removeFromFolderUid:[mail uidEWithFolder:folderIdx]];
    }
    
    UserSettings* user  = [emails firstObject].user;
    
    if (user && !user.isDeleted) {
        [user.linkedAccount deliverDelete:emails fromFolder:[user typeOfFolder:folderIdx]];
    }
}

-(void) updateEmailWrapper:(Mail*)mail
{
    if (self.shuttingDown) {
        return;
    }
    
    [self _switchDBForMail:mail];
    [Mail updateMail:mail];
}

-(void) removeEmail:(UidEntry*)uid_entry
{
    if (self.shuttingDown) {
        return;
    }
    
    [self _switchToDBNum:uid_entry.dbNum];
    [Mail removeMail:uid_entry.msgID];
}

-(void) addEmailWrapper:(Mail*)mail
{
	[self addEmail:mail];
    [self addAttachments:mail.attachments];
}

-(void) addEmail:(Mail*)mail
{
    if (self.shuttingDown) {
        return;
    }
    
    [self _switchDBForMail:mail];
    
    [Mail insertMail:mail];
    
    if ([mail.user.name isEqualToString:@""]) {
        UidEntry* u = [mail uidEWithFolder:[mail.user numFolderWithFolder:CCMFolderTypeSent]];
        if (u) {
            if (![mail.sender.displayName isEqualToString:@""] || ![mail.sender.displayName isEqualToString:mail.sender.mailbox]) {
                DDLogInfo(@"New display name:%@",mail.sender.displayName);
                mail.user.name = mail.sender.displayName;
            }
        }
    }
    
    UidEntry* uid = mail.uids[0];
        
    if (![UidEntry hasUidEntrywithMsgId:mail.msgID withFolder:uid.folder inAccount:uid.accountNum]) {
        [UidEntry addUid:uid];
    }
}

-(void) addAttachments:(NSArray*)atts
{
    [CCMAttachment addAttachments:atts];
}


@end
