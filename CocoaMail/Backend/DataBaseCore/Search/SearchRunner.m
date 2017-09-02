//
//  SearchRunner.m
//  CocoaMail
//
//  Created by Christopher Hockley on 20/01/2012.
//  Copyright (c) 2012 Christopher Hockley. All rights reserved.
//
#import "SearchRunner.h"
#import "UidDBAccessor.h"
#import "GlobalDBFunctions.h"
#import "DateUtil.h"
#import "SyncManager.h"
#import "EmailProcessor.h"
#import "AppSettings.h"
#import "Reachability.h"
#import "UidEntry.h"
#import "FMDatabase.h"
#import "Persons.h"
#import "CCMAttachment.h"
#import "StringUtil.h"
#import "Accounts.h"
#import "UserSettings.h"
#import "ViewController.h"
#import "InViewController.h"
#import "InViewController+SGProgress.h"
#import <ReactiveCocoa/ReactiveCocoa.h>


static SearchRunner * searchSingleton = nil;

@implementation SearchRunner

@synthesize operationQueue;
@synthesize cancelled;

+(id) getSingleton
{
    @synchronized(self) {
        if (searchSingleton == nil) {
            searchSingleton = [[SearchRunner alloc] init];
        }
    }
    
    return searchSingleton;
}

-(id) init
{
    if (self = [super init]) {
        NSOperationQueue* ops = [[NSOperationQueue alloc] init];
        [ops setMaxConcurrentOperationCount:1];
        self.operationQueue = ops;
    }
    
    return self;
}

-(void) cancel
{
    if (self) {
        [self.operationQueue cancelAllOperations];
        self.cancelled = YES;
    }
}

-(RACSignal*) search:(NSString*)searchText inAccountNum:(NSInteger)accountNum
{
    DDLogInfo(@"*** ENTRY POINT ***");

    DDLogInfo(@"ENTERED, search text = \"%@\", account num = %@",searchText,@(accountNum));
    
    NSArray* dbNumbers = [SearchRunner dbNumsInAccountNum:accountNum];
    
    DDLogDebug(@"Account %@ has %@ dbNums.",@(accountNum),@(dbNumbers.count));
    
    searchText = [searchText stringByAppendingString:@"*"];
    
    self.cancelled = NO;
    
    return [self searchForSignal:[self _performFullTextSearch:searchText withDbNum:dbNumbers inAccountNum:accountNum]];
}

-(RACSignal*) searchForSignal:(RACSignal*)signal
{
    return  [signal map:^(Mail* email) {
        return email;
    }];
}

#pragma mark Full-text search

-(RACSignal*) _performFullTextSearch:(NSString*)query withDbNum:(NSArray*)dbNums inAccountNum:(NSInteger)accountNum
{
    return [RACSignal createSignal:^RACDisposable* (id<RACSubscriber> subscriber) {
        
        for (NSNumber* dbNum in dbNums) {
            if (self.cancelled) {
                [subscriber sendCompleted];
            }
            
            //[manager setDatabaseFilepath:[StringUtil filePathInDocumentsDirectoryForFileName:[GlobalDBFunctions dbFileNameForNum:[dbNum integerValue]]]];
            FMDatabaseQueue* queue = [FMDatabaseQueue databaseQueueWithPath:[StringUtil filePathInDocumentsDirectoryForFileName:[GlobalDBFunctions dbFileNameForNum:[dbNum integerValue]]]];
            
            [queue inDatabase:^(FMDatabase* db) {
                
                FMResultSet* results = [db executeQuery:kQuerySearch, query];
                
                while ([results next]) {
                    Mail* email = [Mail newMailFromDatabaseResult:results];
                    
                    if (!email) {
                        continue;
                    }
                    
                    if ([email isInMultipleAccounts]) {
                        Mail* e = [email secondAccountDuplicate];
                        
                        if (e.user.accountNum == accountNum) {
                            email = e;
                        }
                    }
                    
                    if (email.user.accountNum == accountNum) {
                        [subscriber sendNext:email];
                    }
                    
                    if (self.cancelled) {
                        break;
                    }
                }
                
                [results close];
            }];
        }
        
        [subscriber sendCompleted];
        
        return [RACDisposable disposableWithBlock:^{}];
    }];
}

#pragma mark Folder "Search"

//-(RACSignal*) _performThreadSearch:(NSString*)thread withDbNum:(NSArray*)dbNums inAccountNum:(NSInteger)accountNum
//{
//    DDLogInfo(@"*** ENTRY POINT ***");
//
//    DDLogInfo(@"ENTERED, thread = \"%@\", dbNumbers[0..%@], account num %@",thread,@(dbNums.count),@(accountNum));
//
//    return [RACSignal createSignal:^RACDisposable* (id<RACSubscriber> subscriber) {
//        self.cancelled = NO;
//
//        NSMutableArray* uids = [UidEntry getUidEntriesWithThread:thread];
//
//        NSMutableString* query = [NSMutableString string];
//        [query appendString:kQueryThread];
//
//        for (UidEntry* p in uids) {
//            [query appendFormat:@"%@ OR ", p.msgID];
//        }
//
//        query = [[NSMutableString alloc]initWithString:[query substringToIndex:(query.length-3)]];
//        [query appendFormat:@"'"];
//
//        for (NSNumber* dbNum in dbNums) {
//            if (self.cancelled) {
//                [subscriber sendCompleted];
//            }
//
//            FMDatabaseQueue* queue = [FMDatabaseQueue databaseQueueWithPath:[StringUtil filePathInDocumentsDirectoryForFileName:[GlobalDBFunctions dbFileNameForNum:[dbNum integerValue]]]];
//            [queue inDatabase:^(FMDatabase* db) {
//                //[databaseManager setDatabaseFilepath:[StringUtil filePathInDocumentsDirectoryForFileName:[GlobalDBFunctions dbFileNameForNum:[dbNum integerValue]]]];
//                //[databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
//                FMResultSet* results = [db executeQuery:query];
//
//                while ([results next]) {
//                    DDLogDebug(@"Have One");
//                    Mail* email = [Mail newMailFromDatabaseResult:results];
//
//                    if (!email) {
//                        continue;
//                    }
//
//                    if ([email isInMultipleAccounts]) {
//                        Mail* e = [email secondAccountDuplicate];
//
//                        if (e.user.accountNum == accountNum) {
//                            email = e;
//                        }
//                    }
//
//                    if (email.user.accountNum == accountNum) {
//                        [subscriber sendNext:email];
//                    }
//                }
//
//                [results close];
//            }];
//        }
//        [subscriber sendCompleted];
//
//        return [RACDisposable disposableWithBlock:^{}];
//    }];
//}

-(RACSignal*) _performAllSearch
{
    ddLogLevel = DDLogLevelInfo;       // Limit reporting to Info and above for now
    
    DDLogInfo(@"ENTERED");
    
    return [RACSignal createSignal:^RACDisposable* (id<RACSubscriber> subscriber) {
        
        NSInteger __block allFound = 500;       // DOES THS CAP # OF MAIL MSGS THAT CAN BE READ or BREAK FETCHING INTO BLOCKS?
        NSArray* dbNums = [SearchRunner _dbNumsInAllAccountNums];
        
        DDLogDebug(@"Have %@ FMDB numbers across all Accounts.",@(dbNums.count));
        
        NSSortDescriptor* sortOrder =
        [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(self))
                                      ascending:NO];
        
        dbNums = [dbNums sortedArrayUsingDescriptors:@[sortOrder]];
        
        for (NSNumber* dbNum in dbNums) {
            
            if (self.cancelled || allFound <= 0) {
                [subscriber sendCompleted];
                
                return [RACDisposable disposableWithBlock:^{}];
            }
            
            NSMutableArray* dels = [[NSMutableArray alloc] init];
            
            NSString *dbFilename = [GlobalDBFunctions dbFileNameForNum:[dbNum integerValue]];
            NSString *dbFilenameInDocDir = [StringUtil
                                            filePathInDocumentsDirectoryForFileName:dbFilename];
            FMDatabaseQueue* queue = [FMDatabaseQueue databaseQueueWithPath:dbFilenameInDocDir];
            
            DDLogDebug(@"Query FMDB file \"%@\".",dbFilename);
            
            [queue inDatabase:^(FMDatabase* db) {
                NSMutableString* query = [NSMutableString string];
                [query appendString:kQueryAll];
                
                DDLogVerbose(@"Query = \"%@\"",query);
                
                FMResultSet* results = [db executeQuery:query];
                
                if ([db hadError] && [db lastErrorCode] == 1) {
                    DDLogError(@"FMDB Query Failed, Error Code = 1");
                    [Mail tableCheck:db];
                }
                
                DDLogDebug(@"FMDB Query returned FMResultSet*.");
                
                while ([results next]) {
                    Mail* email = [Mail newMailFromDatabaseResult:results];
                    
                    if (!email) {
                        Mail* email = [[Mail alloc] init];
                        email.msgID = [results stringForColumnIndex:6];
                        [dels addObject:email];
                        continue;
                    }
                    
                    if ([email isInMultipleAccounts]) {
                        allFound--;
                        Mail* secondEmail = [email secondAccountDuplicate];
                        [subscriber sendNext:secondEmail];
                    }
                    
                    allFound--;
                    [subscriber sendNext:email];
                }
                [results close];
                
                for (Mail* m in dels) {
                    DDLogDebug(@"Delete mail with subject \"%@\"",m.subject);
                    [db executeUpdate:kQueryDelete, m.msgID];
                }
            }];
        }
        
        [subscriber sendCompleted];
        
        return [RACDisposable disposableWithBlock:^{}];
    }];
}

-(RACSignal*) _performDeleteAccountNum:(NSInteger)accountNum
{
    return [RACSignal createSignal:^RACDisposable* (id<RACSubscriber> subscriber) {
        
        [UidEntry cleanBeforeDeleteinAccountNum:accountNum];
        
            NSMutableArray* uidsInGroups = [UidEntry getUidEntriesinAccountNum:accountNum andDelete:YES];
        
            while (true) {
                
                if (uidsInGroups.count == 0) {
                    break;
                }
                else {
                    DDLogDebug(@"Deleting Batch of Uids");
                    
                    NSInteger group = 0;
                    
                    for (NSArray* pagedUids in uidsInGroups) {
                        
                        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                            [(InViewController*)[[ViewController mainVC] topIVC] setSGProgressPercentage:((group*100)/uidsInGroups.count) andTintColor:[UIColor blackColor]];
                        }];
                        
                        for (UidEntry* p in pagedUids) {
                            FMDatabaseQueue* queue = [FMDatabaseQueue databaseQueueWithPath:[StringUtil filePathInDocumentsDirectoryForFileName:[GlobalDBFunctions dbFileNameForNum:p.dbNum]]];
                            [queue inDatabase:^(FMDatabase* db) {
                                if ([db executeUpdate:kQueryDelete, p.msgID]) {
                                    DDLogDebug(@"Email deleted.");
                                }
                            }];
                        }
                        
                        group++;
                    }
                    
                    break;
                }
            }
            
            [subscriber sendCompleted];
                    
            return [RACDisposable disposableWithBlock:^{
        }];
    }];
}

-(RACSignal*) _performFolderSearch:(NSInteger)folderNum inAccountNum:(NSInteger)accountNum from:(Mail*)email
{
    DDLogInfo(@"folder num = %@, account num = %@, from Mail with Subj. \"%@\"",@(folderNum),@(accountNum),
              (email.subject?email.subject:@"nil"));
    
    NSMutableArray* uidsInGroups;
    
    NSInteger realFolderNum = folderNum;
    
    if ([Accounts sharedInstance].currentAccount.user.isAll) {
        
        realFolderNum = [[AppSettings userWithNum:accountNum] numFolderWithFolder:[Accounts sharedInstance].currentAccount.currentFolderType];
    }
    
    if (email) {
        uidsInGroups = [UidEntry getUidEntriesFrom:email withFolder:realFolderNum inAccountNum:accountNum];
    }
    else { // email == nil
        
        uidsInGroups = [UidEntry getUidEntriesWithFolder:realFolderNum inAccountNum:accountNum];
    }
    
    
    if (uidsInGroups.count == 0){
        dispatch_queue_t global_default_queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0);
        RACScheduler *scheduler = [[RACTargetQueueScheduler alloc] initWithName:@"testScheduler" targetQueue:global_default_queue];
        return [RACSignal startEagerlyWithScheduler:scheduler block:^(id<RACSubscriber> subscriber) {
            DDLogDebug(@"Done with 0");
            [subscriber sendCompleted];
        }];
    }

    NSDate *fetchStart = [NSDate date];

    return [RACSignal startEagerlyWithScheduler:[RACScheduler schedulerWithPriority:DISPATCH_QUEUE_PRIORITY_HIGH] block:^(id<RACSubscriber> subscriber) {

        for (NSArray* pagedUids in uidsInGroups) {
            NSInteger dbNum = ((UidEntry*)[pagedUids firstObject]).dbNum;
            
            if (self.cancelled) {
                DDLogDebug(@"Cancel Search");
                [subscriber sendCompleted];
                
                return;
            }
            
            NSMutableString* query = [NSMutableString string];
            [query appendString:kQueryThread];
            
            for (UidEntry* p in pagedUids) {
                [query appendFormat:@"%@ OR ", p.msgID];
            }
            
            query = [[NSMutableString alloc]initWithString:[query substringToIndex:(query.length-4)]];
            [query appendFormat:@"'"];
            
            NSMutableArray* tmp = [pagedUids mutableCopy];
            
            FMDatabaseQueue* queue = [FMDatabaseQueue databaseQueueWithPath:[StringUtil filePathInDocumentsDirectoryForFileName:[GlobalDBFunctions dbFileNameForNum:dbNum]]];
            [queue inDatabase:^(FMDatabase* db) {
                FMResultSet* results = [db executeQuery:query];
                
//                NSDate *fetchStartG = [NSDate date];

                if ([db hadError] && [db lastErrorCode] == 1) {
                    DDLogError(@"Error querying table. Checking table");
                    [Mail tableCheck:db];
                }
                
                while ([results next]) {
                    Mail* email = [Mail newMailFromDatabaseResult:results];
                    
                    if (!email) {
                        continue;
                    }
                    
                    UidEntry* uidE = [email uidEntryInFolder:realFolderNum];
                    if ( uidE ) {
                        [tmp removeObject:uidE];
                    }
                    
                    
                    if ([email isInMultipleAccounts]) {
                        Mail* e = [email secondAccountDuplicate];
                        
                        Account *currAcnt = [[Accounts sharedInstance] currentAccount];
                        DDAssert(currAcnt,@"Current Account must noty be nil");
                        
                        BOOL isActiveAccountAll = currAcnt.user.isAll;
                        if (isActiveAccountAll) {
                            [subscriber sendNext:e];
                        }
                        else if (e.user.accountNum == currAcnt.user.accountNum) {
                            email = e;
                        }
                    }
                    
                    [subscriber sendNext:email];
                    
                    if (self.cancelled) {
                        break;
                    }
                }
                
                for (UidEntry* p in tmp) {
                    [UidEntry removeAllMsgID:p.msgID];
                }
                
#if (LOG_INFO)
//                NSDate *fetchEndG = [NSDate date];
//                NSTimeInterval timeElapsedG = [fetchEndG timeIntervalSinceDate:fetchStartG];
//                Have FMDB Queue file results(@"Group Fetch Duration: %f seconds.", timeElapsedG);
#endif
                
                [results close];
            }];
        }
        
        NSDate *fetchEnd = [NSDate date];
        NSTimeInterval timeElapsed = [fetchEnd timeIntervalSinceDate:fetchStart];
        DDLogDebug(@"Emails Fetch Duration: %f seconds. Groups: %lu", timeElapsed, (unsigned long)uidsInGroups.count);
        
        [subscriber sendCompleted];
    }];
}

// Load ALL email messages from the database, setting up its in memory structures (e.g. conversations)
-(RACSignal*) allEmailsDBSearch     // Nee allEmailsSearch
{
    DDLogInfo(@"*** ENTRY POINT ***");

    DDLogInfo(@"BEGIN");
    
    self.cancelled = NO;
    
    return [self searchForSignal:[self _performAllSearch]];
}

-(RACSignal*) deleteEmailsInAccountNum:(NSInteger)accountNum
{
    DDLogInfo(@"*** ENTRY POINT ***");

    return [self searchForSignal:[self _performDeleteAccountNum:accountNum]];
}

// If first argument, "email", is nil, then search for all email in the account
-(RACSignal*) activeFolderSearch:(Mail*)email inAccountNum:(NSInteger)accountNum
{
    DDLogInfo(@"*** ENTRY POINT ***");

    self.cancelled = NO;

    if (email && !email.msgID) {
        email = nil;
    }
    
    NSInteger folderIndex = [Accounts sharedInstance].currentAccount.currentFolderIdx;
    
    return [self searchForSignal:[self _performFolderSearch:folderIndex
                                              inAccountNum:accountNum
                                                      from:email]];
}

//-(RACSignal*) threadSearch:(NSString*)thread inAccountNum:(NSInteger)accountNum
//{
//    DDLogInfo(@"*** ENTRY POINT ***");
//
//    NSArray* nums  = [SearchRunner dbNumsInAccountNum:accountNum];
//    
//    return [self searchForSignal:[self _performThreadSearch:thread withDbNum:nums inAccountNum:accountNum]];
//}

// Sender Search
#pragma mark Sender Search

-(RACSignal*) senderSearch:(Person*)person inAccountNum:(NSInteger)accountNum
{
    DDLogInfo(@"*** ENTRY POINT ***");

    self.cancelled = NO;
    
    NSArray* dbNumbers = [SearchRunner dbNumsInAccountNum:accountNum];
    
    NSSortDescriptor* sortOrder = [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(self)) ascending:NO];
    dbNumbers = [dbNumbers sortedArrayUsingDescriptors:@[sortOrder]];
    
    return [self searchForSignal:[self _performSenderSearch:person withDbNum:dbNumbers inAccountNum:accountNum]];
}

-(RACSignal*) _performSenderSearch:(Person*)person withDbNum:(NSArray*)dbNums inAccountNum:(NSInteger)accountNum
{
    DDLogInfo(@"ENTERED, person(.name) = \"%@\", dbNumbers[0..%@], account num %@",person.name,@(dbNums.count),@(accountNum));
    
    return [RACSignal createSignal:^RACDisposable* (id<RACSubscriber> subscriber) {
        
        NSMutableString* query = [NSMutableString string];
        
        [query appendString:@"SELECT email.pk, email.datetime, email.sender, email.tos, email.ccs, email.bccs, email.msg_id, email.html_body, email.flag, search_email.subject, search_email.body FROM email, search_email WHERE email.msg_id = search_email.msg_id AND "];
        
        [query appendFormat:@"search_email.people LIKE '%@%@%@'", @"%", person.email,@"%"];
        
        [query appendString:@" ORDER BY email.datetime DESC;"];
        
        NSString* queryString = query;
        
        for (NSNumber* dbNumObj in dbNums) {
            int dbNum = [dbNumObj intValue];
            
            if (self.cancelled) {
                [subscriber sendCompleted];
            }
            
            FMDatabaseQueue* queue = [FMDatabaseQueue databaseQueueWithPath:[StringUtil filePathInDocumentsDirectoryForFileName:[GlobalDBFunctions dbFileNameForNum:dbNum]]];
            
            [queue inDatabase:^(FMDatabase* db) {
                FMResultSet* results = [db executeQuery:queryString];
                
                while ([results next]) {
                    Mail* email = [Mail newMailFromDatabaseResult:results];
                    
                    if (!email) {
                        continue;
                    }
                    if ([email isInMultipleAccounts]) {
                        Mail* e = [email secondAccountDuplicate];
                        
                        if (e.user.accountNum == accountNum) {
                            email = e;
                        }
                    }
                    
                    if (email.user.accountNum == accountNum) {
                        [subscriber sendNext:email];
                    }
                    
                    if (self.cancelled) {
                        break;
                    }
                }
                
                [results close];
            }];
        }
        [subscriber sendCompleted];
        
        return nil;
    }];
}

+(NSArray*) _dbNumsInAllAccountNums
{
    NSMutableSet* dbs = [[NSMutableSet alloc]init];
    
    for (UserSettings* user in [AppSettings getSingleton].users) {
        if (!user.isDeleted) {
            [dbs addObjectsFromArray:[SearchRunner dbNumsInAccountNum:user.accountNum]];
        }
    }
    
    return [dbs allObjects];
}


+(NSArray*) dbNumsInAccountNum:(NSInteger)accountNum
{
    return [UidEntry dbNumsInAccountNum:accountNum];
}


@end
