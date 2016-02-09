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

-(RACSignal*) search:(NSString*)searchText inAccount:(NSInteger)accountIndex
{
    NSArray* dbNumbers = [SearchRunner dbNumsInAccount:accountIndex];
    
    searchText = [searchText stringByAppendingString:@"*"];
    
    self.cancelled = NO;
    
    return [self searchForSignal:[self performFTSearch:searchText withDbNum:dbNumbers inAccount:accountIndex]];
}

-(RACSignal*) searchForSignal:(RACSignal*)signal
{
    return  [signal map:^(Email* email) {
        return email;
    }];
}

#pragma mark Full-text search

-(RACSignal*) performFTSearch:(NSString*)query withDbNum:(NSArray*)dbNums inAccount:(NSInteger)accountIndex
{
    return [RACSignal createSignal:^RACDisposable* (id<RACSubscriber> subscriber) {
        
        NSInteger accountNum = [[AppSettings getSingleton] numAccountForIndex:accountIndex];
        
        for (NSNumber* dbNum in dbNums) {
            if (self.cancelled) {
                [subscriber sendCompleted];
            }
            
            //[manager setDatabaseFilepath:[StringUtil filePathInDocumentsDirectoryForFileName:[GlobalDBFunctions dbFileNameForNum:[dbNum integerValue]]]];
            FMDatabaseQueue* queue = [FMDatabaseQueue databaseQueueWithPath:[StringUtil filePathInDocumentsDirectoryForFileName:[GlobalDBFunctions dbFileNameForNum:[dbNum integerValue]]]];
            
            [queue inDatabase:^(FMDatabase* db) {
                
                FMResultSet* results = [db executeQuery:kQuerySearch, query];
                
                while ([results next]) {
                    Email* email = [Email resToEmail:results];
                    
                    if ([email isInMultipleAccounts]) {
                        Email* e = [email secondAccountDuplicate];
                        
                        if (e.accountNum == accountNum) {
                            email = e;
                        }
                    }
                    
                    if (email.accountNum == accountNum) {
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

-(RACSignal*) performThreadSearch:(NSString*)thread withDbNum:(NSArray*)dbNums inAccount:(NSInteger)accountIndex
{
    return [RACSignal createSignal:^RACDisposable* (id<RACSubscriber> subscriber) {
        self.cancelled = NO;
        
        NSInteger accountNum = [[AppSettings getSingleton] numAccountForIndex:accountIndex];
        
        NSMutableArray* uids = [UidEntry getUidEntriesWithThread:thread];
        
        NSMutableString* query = [NSMutableString string];
        [query appendString:kQueryThread];
        
        for (UidEntry* p in uids) {
            [query appendFormat:@"%@ OR ", p.msgId];
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
                    Email* email = [Email resToEmail:results];
                    
                    if ([email isInMultipleAccounts]) {
                        Email* e = [email secondAccountDuplicate];
                        
                        if (e.accountNum == accountNum) {
                            email = e;
                        }
                    }
                    
                    if (email.accountNum == accountNum) {
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
        NSArray* dbNums = [SearchRunner dbNumsInAccount:[Accounts sharedInstance].accountsCount-1];
        for (NSNumber* dbNum in dbNums) {
            if (self.cancelled || allFound <= 0) {
                [subscriber sendCompleted];
                
                return [RACDisposable disposableWithBlock:^{}];
            }
            
            FMDatabaseQueue* queue = [FMDatabaseQueue databaseQueueWithPath:[StringUtil filePathInDocumentsDirectoryForFileName:[GlobalDBFunctions dbFileNameForNum:[dbNum integerValue]]]];
            
            [queue inDatabase:^(FMDatabase* db) {
                NSMutableString* query = [NSMutableString string];
                [query appendString:kQueryAll];
                
                FMResultSet* results = [db executeQuery:query];
                
                if ([db hadError] && [db lastErrorCode] == 1) {
                    CCMLog(@"Checking table");
                    [Email tableCheck:db];
                }
                
                while ([results next]) {
                    Email* email = [Email resToEmail:results];
                    
                    if ([email isInMultipleAccounts]) {
                        allFound--;
                        Email* secondEmail = [email secondAccountDuplicate];
                        [subscriber sendNext:secondEmail];
                    }
                    
                    allFound--;
                    [subscriber sendNext:email];
                }
                [results close];
            }];
        }
        
        [subscriber sendCompleted];
        
        return [RACDisposable disposableWithBlock:^{
        }];
    }];
}

-(RACSignal*) performDeleteAccount:(NSInteger)accountIndex
{
    return [RACSignal createSignal:^RACDisposable* (id<RACSubscriber> subscriber) {
        NSMutableArray* uidsInGroups;
        
        [UidEntry cleanBeforeDeleteinAccount:accountIndex];
        
        while (true) {
            uidsInGroups = [UidEntry getUidEntriesinAccount:accountIndex andDelete:YES];
            
            if (uidsInGroups.count == 0) {
                break;
            }
            else {
                CCMLog(@"Deleting Batch");
                
                for (NSArray* pagedUids in uidsInGroups) {
                    NSInteger dbNum = ((UidEntry*)[pagedUids firstObject]).dbNum;
                    
                    if (self.cancelled) {
                        CCMLog(@"Cancel");
                        [subscriber sendCompleted];
                        
                        return [RACDisposable disposableWithBlock:^{}];
                    }
                    
                    NSMutableString* query = [NSMutableString string];
                    [query appendString:kQueryDelete];
                    
                    for (UidEntry* p in pagedUids) {
                        [query appendFormat:@"%@ OR ", p.msgId];
                    }
                    
                    query = [[NSMutableString alloc]initWithString:[query substringToIndex:(query.length-4)]];
                    [query appendFormat:@"'"];
                    
                    FMDatabaseQueue* queue = [FMDatabaseQueue databaseQueueWithPath:[StringUtil filePathInDocumentsDirectoryForFileName:[GlobalDBFunctions dbFileNameForNum:dbNum]]];
                    
                    [queue inDatabase:^(FMDatabase* db) {
                        [db executeUpdate:query];
                    }];
                }
            }
        }
        
        [subscriber sendCompleted];
        
        return [RACDisposable disposableWithBlock:^{
        }];
    }];
}

-(RACSignal*) performFolderSearch:(NSInteger)folderNum inAccount:(NSInteger)accountIndex from:(Email*)email
{
    return [RACSignal createSignal:^RACDisposable* (id<RACSubscriber> subscriber) {
        NSMutableArray* uidsInGroups;
        
        NSInteger realFolderNum = folderNum;
        
        if ([Accounts sharedInstance].currentAccount.isAllAccounts) {
            realFolderNum = [AppSettings importantFolderNumforAccountIndex:accountIndex forBaseFolder:[Accounts sharedInstance].currentAccount.currentFolderType.type];
        }
        
        if (email) {
            uidsInGroups = [UidEntry getUidEntriesFrom:email withFolder:realFolderNum inAccount:accountIndex];
        }
        else {
            uidsInGroups = [UidEntry getUidEntriesWithFolder:realFolderNum inAccount:accountIndex];
        }
        
        for (NSArray* pagedUids in uidsInGroups) {
            NSInteger dbNum = ((UidEntry*)[pagedUids firstObject]).dbNum;
            
            if (self.cancelled) {
                CCMLog(@"Cancel");
                [subscriber sendCompleted];
                
                return [RACDisposable disposableWithBlock:^{}];
            }
            
            NSMutableString* query = [NSMutableString string];
            [query appendString:kQueryThread];
            
            for (UidEntry* p in pagedUids) {
                [query appendFormat:@"%@ OR ", p.msgId];
            }
            
            query = [[NSMutableString alloc]initWithString:[query substringToIndex:(query.length-4)]];
            [query appendFormat:@"'"];

            NSMutableArray* tmp = [pagedUids mutableCopy];
            
            FMDatabaseQueue* queue = [FMDatabaseQueue databaseQueueWithPath:[StringUtil filePathInDocumentsDirectoryForFileName:[GlobalDBFunctions dbFileNameForNum:dbNum]]];
            [queue inDatabase:^(FMDatabase* db) {
                FMResultSet* results = [db executeQuery:query];
                
                if ([db hadError] && [db lastErrorCode] == 1) {
                    CCMLog(@"Checking table");
                    [Email tableCheck:db];
                }
                
                while ([results next]) {
                    Email* email = [Email resToEmail:results];
                    
                    UidEntry* uidE = [email uidEWithFolder:realFolderNum];
                    
                    [tmp removeObject:uidE];
                    
                    if ([email isInMultipleAccounts]) {
                        Email* e = [email secondAccountDuplicate];
                        
                        if (kisActiveAccountAll) {
                            [subscriber sendNext:e];
                        }
                        else if (e.accountNum == kActiveAccountNum) {
                            email = e;
                        }
                    }
                    
                    [subscriber sendNext:email];
                    
                    if (self.cancelled) {
                        break;
                    }
                }
                
                for (UidEntry* p in tmp) {
                    [UidEntry removeFromFolderUid:p];
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

-(RACSignal*) deleteEmailsInAccount:(NSInteger)accountIndex
{
    return [self searchForSignal:[self performDeleteAccount:accountIndex]];
}

-(RACSignal*) activeFolderSearch:(Email*)email inAccount:(NSInteger)accountIndex
{
    self.cancelled = NO;
    
    return [self searchForSignal:[self performFolderSearch:[Accounts sharedInstance].currentAccount.currentFolderIdx inAccount:accountIndex from:email]];
}

-(RACSignal*) threadSearch:(NSString*)thread inAccount:(NSInteger)accountIndex
{
    NSArray* nums  = [SearchRunner dbNumsInAccount:accountIndex];
    
    return [self searchForSignal:[self performThreadSearch:thread withDbNum:nums inAccount:accountIndex]];
}

// Sender Search
#pragma mark Sender Search

-(RACSignal*) senderSearch:(Person*)person inAccount:(NSInteger)accountIndex
{
    self.cancelled = NO;
    
    NSArray* dbNumbers = [SearchRunner dbNumsInAccount:accountIndex];
    
    NSSortDescriptor* sortOrder = [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(self)) ascending:NO];
    dbNumbers = [dbNumbers sortedArrayUsingDescriptors:@[sortOrder]];
    
    return [self searchForSignal:[self performSenderSearch:person withDbNum:dbNumbers inAccount:accountIndex]];
}

-(RACSignal*) performSenderSearch:(Person*)person withDbNum:(NSArray*)dbNums inAccount:(NSInteger)accountIndex
{
    return [RACSignal createSignal:^RACDisposable* (id<RACSubscriber> subscriber) {
        
        NSInteger accountNum = [[AppSettings getSingleton] numAccountForIndex:accountIndex];
        
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
                    Email* email = [Email resToEmail:results];
                    
                    if ([email isInMultipleAccounts]) {
                        Email* e = [email secondAccountDuplicate];
                        
                        if (e.accountNum == accountNum) {
                            email = e;
                        }
                    }
                    
                    if (email.accountNum == accountNum) {
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

+(NSArray*) dbNumsInAccount:(NSInteger)accountIndex
{
    return [UidEntry dbNumsInAccount:accountIndex];
}


@end
