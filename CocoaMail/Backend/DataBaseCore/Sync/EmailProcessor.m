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

#define SECONDS_PER_DAY 86400.0 //24*3600
#define FOLDER_COUNT_LIMIT 999 // maximum number of folders allowed
#define ADDS_PER_TRANSACTION 20

static EmailProcessor *singleton = nil;

@implementation EmailProcessor

@synthesize dbDateFormatter;
@synthesize operationQueue;
@synthesize shuttingDown;
@synthesize updateSubscriber;

BOOL firstOne = YES; // caused effect: Don't endTransaction when we're just starting
BOOL transactionOpen = NO; // caused effect (with firstOne): After we start up, don't wrap the first ADDS_PER_TRANSACTION calls into a transaction

+ (EmailProcessor*)getSingleton
{
	@synchronized(self) {
		if (singleton == nil) {
			singleton = [[self alloc] init];
		}
	}
	return singleton;
}

- (id)init
{
	self = [super init];
	
	if(self) {
		self.shuttingDown = NO;
		
		NSOperationQueue *ops = [[NSOperationQueue alloc] init];
		[ops setMaxConcurrentOperationCount:1]; // note that this makes it a simple, single queue
		self.operationQueue = ops;
		
        NSLocale *enUSPOSIXLocale;
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

- (void)rolloverAddEmailDBTo:(NSInteger)dbNum
{
	[[(EmailDBAccessor *)[EmailDBAccessor sharedManager] databaseQueue] close];
	
	// create new, empty db file
	NSString* fileName = [GlobalDBFunctions dbFileNameForNum:dbNum];
	NSString *dbPath = [StringUtil filePathInDocumentsDirectoryForFileName:fileName];
	if (![[NSFileManager defaultManager] fileExistsAtPath:dbPath]) {
        [[NSFileManager defaultManager] createFileAtPath:dbPath contents:nil attributes:@{NSFileProtectionKey: NSFileProtectionNone}];
	}
	
	[[EmailDBAccessor sharedManager] setDatabaseFilepath:[StringUtil filePathInDocumentsDirectoryForFileName:fileName]];
	
    [Email tableCheck];
}

+ (NSInteger)folderCountLimit
{
	return FOLDER_COUNT_LIMIT;
}

+ (NSInteger)dbNumForDate:(NSDate *)date
{
	double timeSince1970 = [date timeIntervalSince1970];
	
	NSInteger dbNum = (NSInteger)(floor(timeSince1970/SECONDS_PER_DAY/3.0))*100; // The *100 is to avoid overlap with date files from the past
	
	dbNum = MAX(0, dbNum);
	
	return dbNum;
}

- (void)switchToDBNum:(NSInteger)dbNum
{
	if(self.shuttingDown) return;
	
	if(currentDBNum != dbNum) {
		// need to switch between DBs
		if(!firstOne) {
			// don't open a transaction for the first one
			//[self endTransactions];
		}
		//CCMLog(@"Switching to edb: %i", dbNum);
		[self rolloverAddEmailDBTo:dbNum];
		if(!firstOne) {
			//[self beginTransactions];
		}
		
		addsSinceTransaction = 0;
		currentDBNum = dbNum;
		firstOne = NO;
	} else {
		// have we exceeded the number of adds between transactions?
		addsSinceTransaction += 1;
		BOOL nextTransaction = (addsSinceTransaction >= ADDS_PER_TRANSACTION);
		if(nextTransaction) {
			addsSinceTransaction = 0;
		}
		
		// switching between transactions
		if(nextTransaction) {
			//[self endTransactions];
			firstOne = NO;
			//[self beginTransactions];
		}
	}
}

- (void)addToFolderWrapper:(UidEntry *)data
{
	[UidEntry addUid:data];
}

- (void)updateFlag:(NSMutableArray *)datas
{
	if(self.shuttingDown) return;
    for (Email *email in datas) {
        [self switchToDBNum:[EmailProcessor dbNumForDate:email.datetime]];
        [Email updateEmailFlag:email];
    }
    
    SEL selector = NSSelectorFromString(@"deliverUpdate:");
    
    if(self.updateSubscriber != nil && [self.updateSubscriber respondsToSelector:selector]) {
        ((void (*)(id, SEL, NSArray*))[self.updateSubscriber methodForSelector:selector])(self.updateSubscriber, selector,datas);
        //[self.updateSubscriber performSelector:selector withObject:datas];
	}
}

- (void)removeFromFolderWrapper:(NSArray *)datas
{
    if(self.shuttingDown) return;
	for (Email *email in datas) {
        [self switchToDBNum:[EmailProcessor dbNumForDate:email.datetime]];
        [UidEntry removeFromFolderUid:[email uidEWithFolder:[[Accounts sharedInstance].currentAccount currentFolderIdx]]];
    }
    
    SEL selector = NSSelectorFromString(@"deliverDelete:");
    
    if(self.updateSubscriber != nil && [self.updateSubscriber respondsToSelector:selector]) {
        ((void (*)(id, SEL, NSArray*))[self.updateSubscriber methodForSelector:selector])(self.updateSubscriber, selector,datas);
		//[self.updateSubscriber performSelector:selector withObject:datas];
	}
    
}

- (void)addEmailWrapper:(Email *)email
{
	// Note that there should be no parallel accesses to addEmailWrapper
    [self switchToDBNum:[EmailProcessor dbNumForDate:email.datetime]];
	[self addEmail:email];
    [self addAttachments:email.attachments];
}

- (void)addEmail:(Email *)email
{
	if(self.shuttingDown) return;
	[Email insertEmail:email];
	[UidEntry addUid:email.uids[0]];
}

- (void)addAttachments:(NSArray *)atts
{
    [CCMAttachment addAttachments:atts];
}

@end
