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
    NSArray* dbNumbers = [SearchRunner dbNumsInAccountNum:accountNum];
    
    searchText = [searchText stringByAppendingString:@"*"];
    
    self.cancelled = NO;
    
    return [self searchForSignal:[self performFTSearch:searchText withDbNum:dbNumbers inAccountNum:accountNum]];
}

-(RACSignal*) searchForSignal:(RACSignal*)signal
{
    return  [signal map:^(Mail* email) {
        return email;
    }];
}

#pragma mark Full-text search

-(RACSignal*) performFTSearch:(NSString*)query withDbNum:(NSArray*)dbNums inAccountNum:(NSInteger)accountNum
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
                    Mail* email = [Mail resToMail:results];
                    
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
        
        return [RACDisposable disposableWithBlock:^{
        }];
    }];
}

#pragma mark Folder "Search"

-(RACSignal*) performThreadSearch:(NSString*)thread withDbNum:(NSArray*)dbNums inAccountNum:(NSInteger)accountNum
{
    return [RACSignal createSignal:^RACDisposable* (id<RACSubscriber> subscriber) {
        self.cancelled = NO;
        
        NSMutableArray* uids = [UidEntry getUidEntriesWithThread:thread];
        
        NSMutableString* query = [NSMutableString string];
        [query appendString:kQueryThread];
        
        for (UidEntry* p in uids) {
            [query appendFormat:@"%@ OR ", p.msgID];
        }
        
        query = [[NSMutableString alloc]initWithString:[query substringToIndex:(query.length-3)]];
        [query appendFormat:@"'"];
        
        for (NSNumber* dbNum in dbNums) {
            if (self.cancelled) {
                [subscriber sendCompleted];
            }
            
            FMDatabaseQueue* queue = [FMDatabaseQueue databaseQueueWithPath:[StringUtil filePathInDocumentsDirectoryForFileName:[GlobalDBFunctions dbFileNameForNum:[dbNum integerValue]]]];
            [queue inDatabase:^(FMDatabase* db) {
                //[databaseManager setDatabaseFilepath:[StringUtil filePathInDocumentsDirectoryForFileName:[GlobalDBFunctions dbFileNameForNum:[dbNum integerValue]]]];
                //[databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
                FMResultSet* results = [db executeQuery:query];
                
                while ([results next]) {
                    CCMLog(@"Have One");
                    Mail* email = [Mail resToMail:results];
                    
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
                }
                
                [results close];
            }];
        }
        [subscriber sendCompleted];
        
        return [RACDisposable disposableWithBlock:^{}];
    }];
}

-(RACSignal*) performAllSearch
{
    return [RACSignal createSignal:^RACDisposable* (id<RACSubscriber> subscriber) {
        
        NSInteger __block allFound = 500;
        NSArray* dbNums = [SearchRunner _dbNumsInAllAccountNums];
        
        NSSortDescriptor* sortOrder = [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(self)) ascending:NO];
        dbNums = [dbNums sortedArrayUsingDescriptors:@[sortOrder]];
        
        for (NSNumber* dbNum in dbNums) {
            if (self.cancelled || allFound <= 0) {
                [subscriber sendCompleted];
                
                return [RACDisposable disposableWithBlock:^{}];
            }
            
            NSMutableArray* dels = [[NSMutableArray alloc] init];
            
            FMDatabaseQueue* queue = [FMDatabaseQueue databaseQueueWithPath:[StringUtil filePathInDocumentsDirectoryForFileName:[GlobalDBFunctions dbFileNameForNum:[dbNum integerValue]]]];
            
            [queue inDatabase:^(FMDatabase* db) {
                NSMutableString* query = [NSMutableString string];
                [query appendString:kQueryAll];
                
                FMResultSet* results = [db executeQuery:query];
                
                if ([db hadError] && [db lastErrorCode] == 1) {
                    CCMLog(@"Checking table");
                    [Mail tableCheck:db];
                }
                
                while ([results next]) {
                    Mail* email = [Mail resToMail:results];
                    
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
                    NSLog(@"Lone email deleted");
                    [db executeUpdate:kQueryDelete, m.msgID];
                }
            }];
        }
        
        [subscriber sendCompleted];
        
        return [RACDisposable disposableWithBlock:^{
        }];
    }];
}

-(RACSignal*) performDeleteAccountNum:(NSInteger)accountNum
{
    return [RACSignal createSignal:^RACDisposable* (id<RACSubscriber> subscriber) {
        
        [UidEntry cleanBeforeDeleteinAccountNum:accountNum];
        
            NSMutableArray* uidsInGroups = [UidEntry getUidEntriesinAccountNum:accountNum andDelete:YES];
        
            while (true) {
                
                if (uidsInGroups.count == 0) {
                    break;
                }
                else {
                    NSLog(@"Deleting Batch");
                    
                    for (NSArray* pagedUids in uidsInGroups) {
                        
                        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                            [(InViewController*)[[ViewController mainVC] topIVC] setSGProgressPercentage:((long)(pagedUids.count*100)/uidsInGroups.count) andTintColor:[UIColor blackColor]];
                        }];
                        
                        for (UidEntry* p in pagedUids) {
                            FMDatabaseQueue* queue = [FMDatabaseQueue databaseQueueWithPath:[StringUtil filePathInDocumentsDirectoryForFileName:[GlobalDBFunctions dbFileNameForNum:p.dbNum]]];
                            [queue inDatabase:^(FMDatabase* db) {
                                if ([db executeUpdate:kQueryDelete, p.msgID]) {
                                    //NSLog(@"email deleted");
                                }
                            }];
                        }
                    }
                    
                    break;
                }
            }
            
            [subscriber sendCompleted];
                    
        return [RACDisposable disposableWithBlock:^{
        }];
    }];
}

-(RACSignal*) performFolderSearch:(NSInteger)folderNum inAccountNum:(NSInteger)accountNum from:(Mail*)email
{
    return [RACSignal createSignal:^RACDisposable* (id<RACSubscriber> subscriber) {
        NSMutableArray* uidsInGroups;
        
        NSInteger realFolderNum = folderNum;
        
        if ([Accounts sharedInstance].currentAccount.user.isAll) {
            realFolderNum = [[AppSettings userWithNum:accountNum] importantFolderNumforBaseFolder:[Accounts sharedInstance].currentAccount.currentFolderType.type];
        }
        
        if (email) {
            uidsInGroups = [UidEntry getUidEntriesFrom:email withFolder:realFolderNum inAccountNum:accountNum];
        }
        else {
            uidsInGroups = [UidEntry getUidEntriesWithFolder:realFolderNum inAccountNum:accountNum];
        }
        
        for (NSArray* pagedUids in uidsInGroups) {
            NSInteger dbNum = ((UidEntry*)[pagedUids firstObject]).dbNum;
            
            if (self.cancelled) {
                NSLog(@"Cancel Search");
                [subscriber sendCompleted];
                
                return [RACDisposable disposableWithBlock:^{}];
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
                
                if ([db hadError] && [db lastErrorCode] == 1) {
                    NSLog(@"Error querying table. Checking table");
                    [Mail tableCheck:db];
                }
                
                while ([results next]) {
                    Mail* email = [Mail resToMail:results];
                    
                    if (!email) {
                        continue;
                    }
                    
                    UidEntry* uidE = [email uidEWithFolder:realFolderNum];
                    
                    [tmp removeObject:uidE];
                    
                    if ([email isInMultipleAccounts]) {
                        Mail* e = [email secondAccountDuplicate];
                        
                        if (kisActiveAccountAll) {
                            [subscriber sendNext:e];
                        }
                        else if (e.user.accountNum == kActiveAccountNum) {
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
                
                [results close];
            }];
        }
        
        //NSDate *fetchEnd = [NSDate date];
        //NSTimeInterval timeElapsed = [fetchEnd timeIntervalSinceDate:fetchStart];
        //NSLog(@"Emails Fetch Duration: %f seconds. Groups: %lu", timeElapsed, (unsigned long)uidsInGroups.count);
        
        [subscriber sendCompleted];
        
        return [RACDisposable disposableWithBlock:^{
        }];
    }];
}

-(RACSignal*) allEmailsSearch
{
    self.cancelled = NO;
    
    return [self searchForSignal:[self performAllSearch]];
}

-(RACSignal*) deleteEmailsInAccountNum:(NSInteger)accountNum
{
    return [self searchForSignal:[self performDeleteAccountNum:accountNum]];
}

-(RACSignal*) activeFolderSearch:(Mail*)email inAccountNum:(NSInteger)accountNum
{
    self.cancelled = NO;
    
    if (!email.msgID) {
        email = nil;
    }
    
    return [self searchForSignal:[self performFolderSearch:[Accounts sharedInstance].currentAccount.currentFolderIdx inAccountNum:accountNum from:email]];
}

-(RACSignal*) threadSearch:(NSString*)thread inAccountNum:(NSInteger)accountNum
{
    NSArray* nums  = [SearchRunner dbNumsInAccountNum:accountNum];
    
    return [self searchForSignal:[self performThreadSearch:thread withDbNum:nums inAccountNum:accountNum]];
}

// Sender Search
#pragma mark Sender Search

-(RACSignal*) senderSearch:(Person*)person inAccountNum:(NSInteger)accountNum
{
    self.cancelled = NO;
    
    NSArray* dbNumbers = [SearchRunner dbNumsInAccountNum:accountNum];
    
    NSSortDescriptor* sortOrder = [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(self)) ascending:NO];
    dbNumbers = [dbNumbers sortedArrayUsingDescriptors:@[sortOrder]];
    
    return [self searchForSignal:[self performSenderSearch:person withDbNum:dbNumbers inAccountNum:accountNum]];
}

-(RACSignal*) performSenderSearch:(Person*)person withDbNum:(NSArray*)dbNums inAccountNum:(NSInteger)accountNum
{
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
                    Mail* email = [Mail resToMail:results];
                    
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
