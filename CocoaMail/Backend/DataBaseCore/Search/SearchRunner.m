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
    
    return [self searchForSignal:[self performFTSearch:searchText withDbNum:dbNumbers]];
}

-(RACSignal*) searchForSignal:(RACSignal*)signal
{
    return  [signal map:^(Email* email) {
        return email;
    }];
}

#pragma mark Full-text search

-(RACSignal*) performFTSearch:(NSString*)query withDbNum:(NSArray*)dbNums
{
    return [RACSignal createSignal:^RACDisposable* (id<RACSubscriber> subscriber) {
        
        for (NSNumber* dbNum in dbNums) {
            if (self.cancelled) {
                [subscriber sendCompleted];
            }
            
            //[manager setDatabaseFilepath:[StringUtil filePathInDocumentsDirectoryForFileName:[GlobalDBFunctions dbFileNameForNum:[dbNum integerValue]]]];
            FMDatabaseQueue* queue = [FMDatabaseQueue databaseQueueWithPath:[StringUtil filePathInDocumentsDirectoryForFileName:[GlobalDBFunctions dbFileNameForNum:[dbNum integerValue]]]];
            
            [queue inDatabase:^(FMDatabase* db) {
                
                FMResultSet* results = [db executeQuery:@"SELECT email.pk, email.sender, search_email.subject, email.datetime, "
                                        "search_email.body, snippet(search_email,'[', ']','...'), email.msg_id FROM "
                                        "email, search_email "
                                        "WHERE email.pk = search_email.rowid AND search_email MATCH ?"
                                        "ORDER BY email.datetime DESC;", query];
                
                while ([results next]) {
                    
                    Email* email  = [[Email alloc]init];
                    
                    email.pk = [results intForColumnIndex:0];
                    email.sender = [MCOAddress addressWithNonEncodedRFC822String:[results stringForColumnIndex:1]];
                    email.subject = [results stringForColumnIndex:2];
                    email.datetime = [results dateForColumnIndex:3];
                    email.body = [results stringForColumnIndex:4];
                    //CCMLog(@"Snippet: %@",[results stringForColumnIndex:5]);
                    email.msgId = [results stringForColumnIndex:6];
                    
                    email.attachments = [CCMAttachment getAttachmentsWithMsgId:email.msgId];
                    
                    [subscriber sendNext:email];
                    
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
        
        NSInteger accountNum = [AppSettings numForData:accountIndex];
        
        NSMutableArray* uids = [UidEntry getUidEntriesWithThread:thread];
        
        NSMutableString* query = [NSMutableString string];
        [query appendString:@"SELECT email.pk, email.sender, search_email.subject, email.datetime, "
         "SUBSTR(search_email.body,0,140), email.flag, email.msg_id, email.tos,email.ccs,email.bccs,email.html_body "
         "FROM  email, search_email "
         "WHERE email.pk = search_email.rowid AND search_email.msg_id MATCH '"];
        
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
                    Email* email = [[Email alloc]init];
                    
                    email.pk = [results intForColumnIndex:0];
                    email.sender = [MCOAddress addressWithNonEncodedRFC822String:[results stringForColumnIndex:1]];
                    email.subject = [results stringForColumnIndex:2];
                    email.datetime = [results dateForColumnIndex:3];
                    email.body = [results stringForColumnIndex:4];
                    email.flag = [results intForColumnIndex:5];
                    email.msgId = [results stringForColumnIndex:6];
                    
                    email.tos = @[];
                    email.ccs = @[];
                    email.bccs = @[];
                    
                    if (![[results stringForColumnIndex:7] isEqualToString:@""]) {
                        email.tos = [MCOAddress addressesWithNonEncodedRFC822String:[results stringForColumnIndex:7]];
                    }
                    
                    if (![[results stringForColumnIndex:8] isEqualToString:@""]) {
                        email.ccs = [MCOAddress addressesWithNonEncodedRFC822String:[results stringForColumnIndex:8]];
                    }
                    
                    if (![[results stringForColumnIndex:9] isEqualToString:@""]) {
                        email.bccs = [MCOAddress addressesWithNonEncodedRFC822String:[results stringForColumnIndex:9]];
                    }
                    
                    email.htmlBody = [results stringForColumnIndex:10];
                    email.body = email.body?:@"";
                    email.htmlBody = email.htmlBody?:@"";
                    
                    email.attachments = [CCMAttachment getAttachmentsWithMsgId:email.msgId];
                    
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
                [query appendString:@"SELECT email.pk, email.sender, search_email.subject, email.datetime, "
                 "search_email.body, email.flag, email.msg_id, email.tos,email.ccs,email.bccs,email.html_body "
                 "FROM  email, search_email "
                 "WHERE email.pk = search_email.rowid"];
                
                FMResultSet* results = [db executeQuery:query];
                
                if ([db hadError] && [db lastErrorCode] == 1) {
                    CCMLog(@"Checking table");
                    [Email tableCheck:db];
                }
                
                while ([results next]) {
                    Email* email = [[Email alloc]init];
                    
                    email.pk = [results intForColumnIndex:0];
                    email.sender = [MCOAddress addressWithNonEncodedRFC822String:[results stringForColumnIndex:1]];
                    email.subject = [results stringForColumnIndex:2];
                    email.datetime = [results dateForColumnIndex:3];
                    email.body = [results stringForColumnIndex:4];
                    email.flag = [results intForColumnIndex:5];
                    email.msgId = [results stringForColumnIndex:6];
                    
                    email.tos = @[];
                    email.ccs = @[];
                    email.bccs = @[];
                    
                    if (![[results stringForColumnIndex:7] isEqualToString:@""]) {
                        email.tos = [MCOAddress addressesWithNonEncodedRFC822String:[results stringForColumnIndex:7]];
                    }
                    
                    if (![[results stringForColumnIndex:8] isEqualToString:@""]) {
                        email.ccs = [MCOAddress addressesWithNonEncodedRFC822String:[results stringForColumnIndex:8]];
                    }
                    
                    if (![[results stringForColumnIndex:9] isEqualToString:@""]) {
                        email.bccs = [MCOAddress addressesWithNonEncodedRFC822String:[results stringForColumnIndex:9]];
                    }
                    
                    email.htmlBody = [results stringForColumnIndex:10];
                    email.body = email.body?:@"";
                    email.htmlBody = email.htmlBody?:@"";
                    
                    email.attachments = [CCMAttachment getAttachmentsWithMsgId:email.msgId];
                    
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
        
        CCMLog(@"Account:%ld Searching in Folder:%@ with count:%lu", (long)accountIndex, [AppSettings folderDisplayName:realFolderNum forAccountIndex:accountIndex], (long)uidsInGroups.count);
        
        for (NSArray* pagedUids in uidsInGroups) {
            NSInteger dbNum = ((UidEntry*)[pagedUids firstObject]).dbNum;
            
            if (self.cancelled) {
                CCMLog(@"Cancel");
                [subscriber sendCompleted];
                
                return [RACDisposable disposableWithBlock:^{}];
            }
            
            NSMutableString* query = [NSMutableString string];
            [query appendString:@"SELECT email.pk, email.sender, search_email.subject, email.datetime, "
             "search_email.body, email.flag, email.msg_id, email.tos,email.ccs,email.bccs,email.html_body "
             "FROM  email, search_email "
             "WHERE email.pk = search_email.rowid AND search_email.msg_id MATCH '"];
            
            for (UidEntry* p in pagedUids) {
                [query appendFormat:@"%@ OR ", p.msgId];
            }
            
            query = [[NSMutableString alloc]initWithString:[query substringToIndex:(query.length-4)]];
            [query appendFormat:@"'"];
            
            FMDatabaseQueue* queue = [FMDatabaseQueue databaseQueueWithPath:[StringUtil filePathInDocumentsDirectoryForFileName:[GlobalDBFunctions dbFileNameForNum:dbNum]]];
            
            [queue inDatabase:^(FMDatabase* db) {
                FMResultSet* results = [db executeQuery:query];
                
                if ([db hadError] && [db lastErrorCode] == 1) {
                    CCMLog(@"Checking table");
                    [Email tableCheck:db];
                }
                
                while ([results next]) {
                    Email* email = [[Email alloc]init];
                    
                    email.pk = [results intForColumnIndex:0];
                    email.sender = [MCOAddress addressWithNonEncodedRFC822String:[results stringForColumnIndex:1]];
                    email.subject = [results stringForColumnIndex:2];
                    email.datetime = [results dateForColumnIndex:3];
                    email.body = [results stringForColumnIndex:4];
                    email.flag = [results intForColumnIndex:5];
                    email.msgId = [results stringForColumnIndex:6];
                    
                    email.tos = @[];
                    email.ccs = @[];
                    email.bccs = @[];
                    
                    if (![[results stringForColumnIndex:7] isEqualToString:@""]) {
                        email.tos = [MCOAddress addressesWithNonEncodedRFC822String:[results stringForColumnIndex:7]];
                    }
                    
                    if (![[results stringForColumnIndex:8] isEqualToString:@""]) {
                        email.ccs = [MCOAddress addressesWithNonEncodedRFC822String:[results stringForColumnIndex:8]];
                    }
                    
                    if (![[results stringForColumnIndex:9] isEqualToString:@""]) {
                        email.bccs = [MCOAddress addressesWithNonEncodedRFC822String:[results stringForColumnIndex:9]];
                    }
                    
                    email.htmlBody = [results stringForColumnIndex:10];
                    email.body = email.body?:@"";
                    email.htmlBody = email.htmlBody?:@"";
                    
                    email.attachments = [CCMAttachment getAttachmentsWithMsgId:email.msgId];
                    
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
                [results close];
            }];
        }
        
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

-(RACSignal*) senderSearch:(NSArray*)addressess inAccount:(NSInteger)accountIndex
{
    self.cancelled = NO;
    
    NSArray* dbNumbers = [SearchRunner dbNumsInAccount:kActiveAccountIndex];
    
    NSSortDescriptor* sortOrder = [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(self)) ascending:NO];
    dbNumbers = [dbNumbers sortedArrayUsingDescriptors:@[sortOrder]];
    
    return [self searchForSignal:[self performSenderSearch:addressess withDbNum:dbNumbers inAccount:accountIndex]];
}

-(RACSignal*) performSenderSearch:(NSArray*)addresses withDbNum:(NSArray*)dbNums inAccount:(NSInteger)accountIndex
{
    return [RACSignal createSignal:^RACDisposable* (id<RACSubscriber> subscriber) {
        
        NSInteger accountNum = [AppSettings numForData:accountIndex];
        
        NSMutableString* query = [NSMutableString string];
        
        [query appendString:@"SELECT email.pk, email.sender, search_email.subject, email.datetime, "
         "search_email.body, email.flag, email.msg_id, email.tos,email.ccs,email.bccs,email.html_body "
         "FROM  email, search_email "
         "WHERE email.pk = search_email.rowid AND "];
        
        for (Person* p in addresses) {
            [query appendFormat:@"search_email.people LIKE '%@%@%@' OR", @"%", p.email,@"%"];
        }
        
        NSString* queryString = [query substringToIndex:(query.length - 3)];
        
        query = [NSMutableString string];
        [query appendFormat:@"%@ ORDER BY email.datetime DESC;", queryString];
        queryString = query;
        
        for (NSNumber* dbNumObj in dbNums) {
            int dbNum = [dbNumObj intValue];
            
            if (self.cancelled) {
                [subscriber sendCompleted];
            }
            
            FMDatabaseQueue* queue = [FMDatabaseQueue databaseQueueWithPath:[StringUtil filePathInDocumentsDirectoryForFileName:[GlobalDBFunctions dbFileNameForNum:dbNum]]];
            
            [queue inDatabase:^(FMDatabase* db) {
                
                FMResultSet* results = [db executeQuery:queryString];
                
                while ([results next]) {
                    Email* email = [[Email alloc]init];
                    
                    email.pk = [results intForColumnIndex:0];
                    email.sender = [MCOAddress addressWithNonEncodedRFC822String:[results stringForColumnIndex:1]];
                    email.subject = [results stringForColumnIndex:2];
                    email.datetime = [results dateForColumnIndex:3];
                    email.body = [results stringForColumnIndex:4];
                    email.flag = [results intForColumnIndex:5];
                    email.msgId = [results stringForColumnIndex:6];
                    
                    email.tos = @[];
                    email.ccs = @[];
                    email.bccs = @[];
                    
                    if (![[results stringForColumnIndex:7] isEqualToString:@""]) {
                        email.tos = [MCOAddress addressesWithNonEncodedRFC822String:[results stringForColumnIndex:7]];
                    }
                    
                    if (![[results stringForColumnIndex:8] isEqualToString:@""]) {
                        email.ccs = [MCOAddress addressesWithNonEncodedRFC822String:[results stringForColumnIndex:8]];
                    }
                    
                    if (![[results stringForColumnIndex:9] isEqualToString:@""]) {
                        email.bccs = [MCOAddress addressesWithNonEncodedRFC822String:[results stringForColumnIndex:9]];
                    }
                    
                    email.htmlBody = [results stringForColumnIndex:10];
                    email.body = email.body?:@"";
                    email.htmlBody = email.htmlBody?:@"";
                    
                    email.attachments = [CCMAttachment getAttachmentsWithMsgId:email.msgId];
                    
                    if ([email isInMultipleAccounts]) {
                        Email* e = [email secondAccountDuplicate];
                        
                        ///if (kisActiveAccountAll) {
                        //    [subscriber sendNext:e];
                        //}
                        //else
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
