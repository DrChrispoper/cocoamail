//
//  SearchRunner.m
//  CocoaMail
//
//  Created by Christopher Hockley on 20/01/2012.
//  Copyright (c) 2012 Christopher Hockley. All rights reserved.
//
#import "SearchRunner.h"
#import "UidDBAccessor.h"
#import "EmailDBAccessor.h"
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

static SearchRunner *searchSingleton = nil;

@implementation SearchRunner
@synthesize operationQueue;
@synthesize cancelled;

+ (id)getSingleton
{
    @synchronized(self) {
        if (searchSingleton == nil) {
            searchSingleton = [[SearchRunner alloc] init];
        }
    }
    return searchSingleton;
}

- (id)init
{
    if(self = [super init]) {
        NSOperationQueue *ops = [[NSOperationQueue alloc] init];
        [ops setMaxConcurrentOperationCount:1];
        self.operationQueue = ops;
    }
    
    return self;
}

- (void)cancel
{
    if(self){
        [self.operationQueue cancelAllOperations];
        self.cancelled = YES;
    }
}

- (RACSignal *)searchOfFolder:(NSString*)searchText
{
    NSSet* dbNumbers = [[SyncManager getSingleton] retrieveAllDBNumsAccountNum:[AppSettings activeAccount]];
    
    searchText = [searchText stringByAppendingString:@"*"];
    
    self.cancelled = NO;
    
    return [self searchForSignal:[self performFTSearch:searchText withDbNum:dbNumbers]];
}

- (RACSignal *)searchForSignal:(RACSignal *)signal
{
    return  [signal map:^(Email *email) {
        return email;
    }];
}

#pragma mark Full-text search

- (RACSignal *)performFTSearch:(NSString *)query withDbNum:(NSSet *)dbNums
{
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        
        EmailDBAccessor *manager = [EmailDBAccessor sharedManager];
        
        for(NSNumber* dbNum in dbNums) {
            if (self.cancelled) [subscriber sendCompleted];
            
            [manager setDatabaseFilepath:[StringUtil filePathInDocumentsDirectoryForFileName:[GlobalDBFunctions dbFileNameForNum:[dbNum integerValue]]]];
            
            [manager.databaseQueue inDatabase:^(FMDatabase *db) {
                
                FMResultSet *results = [db executeQuery:@"SELECT email.pk, email.sender, search_email.subject, email.datetime, "
                                        "search_email.body, snippet(search_email,'[', ']','...'), email.msg_id FROM "
                                        "email, search_email "
                                        "WHERE email.pk = search_email.rowid AND search_email MATCH ?"
                                        "ORDER BY email.datetime DESC;",query];
                
                while([results next]) {
                    
                    Email* email  = [[Email alloc]init];
                    
                    email.pk = [results intForColumnIndex:0];
                    email.sender = [MCOAddress addressWithNonEncodedRFC822String:[results stringForColumnIndex:1]];
                    email.subject = [results stringForColumnIndex:2];
                    email.datetime = [results dateForColumnIndex:3];
                    email.body = [results stringForColumnIndex:5];
                    //CCMLog(@"Snippet: %@",[results stringForColumnIndex:5]);
                    email.msgId = [results stringForColumnIndex:6];
                    
                    [subscriber sendNext:email];
                    
                    if(self.cancelled) { break; }
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

- (RACSignal *)performThreadSearch:(NSString *)thread withDbNum:(NSArray *)dbNums
{
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        self.cancelled = NO;
        
        NSMutableArray *uids = [UidEntry getUidEntriesWithThread:thread];
        
        NSMutableString *query = [NSMutableString string];
        [query appendString:@"SELECT email.pk, email.sender, search_email.subject, email.datetime, "
         "SUBSTR(search_email.body,0,140), email.flag, email.msg_id, email.tos,email.ccs,email.bccs,email.html_body "
         "FROM  email, search_email "
         "WHERE email.pk = search_email.rowid AND search_email.msg_id MATCH '"];
        
        for (UidEntry* p in uids) { [query appendFormat:@"%@ OR ",p.msgId]; }
        
        query = [[NSMutableString alloc]initWithString:[query substringToIndex:(query.length-3)]];
        [query appendFormat:@"'"];
        
        for (NSNumber* dbNum in dbNums) {
            if (self.cancelled) [subscriber sendCompleted];
            
            EmailDBAccessor *databaseManager = [EmailDBAccessor sharedManager];
            
            [databaseManager setDatabaseFilepath:[StringUtil filePathInDocumentsDirectoryForFileName:[GlobalDBFunctions dbFileNameForNum:[dbNum integerValue]]]];
            [databaseManager.databaseQueue inDatabase:^(FMDatabase *db) {
                FMResultSet *results = [db executeQuery:query];
                while([results next])
                {
                    CCMLog(@"Have One");
                    Email * email = [[Email alloc]init];
                    
                    email.pk = [results intForColumnIndex:0];
                    email.sender = [MCOAddress addressWithNonEncodedRFC822String:[results stringForColumnIndex:1]];
                    email.subject = [results stringForColumnIndex:2];
                    email.datetime = [results dateForColumnIndex:3];
                    email.body = [results stringForColumnIndex:4];
                    email.flag = [results intForColumnIndex:5];
                    email.msgId = [results stringForColumnIndex:6];
                    
                    [[results stringForColumnIndex:7] isEqualToString:@""]?(email.tos = [[NSArray alloc]init]):(email.tos = [MCOAddress addressesWithNonEncodedRFC822String:[results stringForColumnIndex:7]]);
                    [[results stringForColumnIndex:8] isEqualToString:@""]?(email.ccs = [[NSArray alloc]init]):(email.ccs = [MCOAddress addressesWithNonEncodedRFC822String:[results stringForColumnIndex:8]]);
                    [[results stringForColumnIndex:9] isEqualToString:@""]?(email.bccs = [[NSArray alloc]init]):(email.bccs = [MCOAddress addressesWithNonEncodedRFC822String:[results stringForColumnIndex:9]]);
                    
                    email.htmlBody = [results stringForColumnIndex:10];
                    email.body = email.body?:@"";
                    email.htmlBody = email.htmlBody?:@"";
                    
                    [subscriber sendNext:email];
                    
                }
                
                [results close];
            }];
        }
        [subscriber sendCompleted];
        return [RACDisposable disposableWithBlock:^{}];
    }];
}

- (RACSignal *)performFolderSearch:(NSInteger)folderNum withDbNum:(NSArray *)dbNums from:(NSInteger)pEmail
{
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        EmailDBAccessor *manager = [EmailDBAccessor sharedManager];
        NSMutableArray *uids = [UidEntry getUidEntriesFrom:pEmail withFolder:folderNum];
        
        NSInteger __block allFound = uids.count;
        NSUInteger count = 20;
        
        if (allFound != 0) {
            for (NSUInteger startIndex = 0; count != 0;) {
                if (self.cancelled) {
                    CCMLog(@"Cancel");
                    [subscriber sendCompleted];
                    return [RACDisposable disposableWithBlock:^{}];
                }
                count = MIN( uids.count - startIndex, 20 );
                if (count == 0) break;
                NSArray *pagedUids = [uids subarrayWithRange:NSMakeRange( startIndex, count )];
                startIndex += count;
                
                NSMutableString *query = [NSMutableString string];
                [query appendString:@"SELECT email.pk, email.sender, search_email.subject, email.datetime, "
                 "search_email.body, email.flag, email.msg_id, email.tos,email.ccs,email.bccs,email.html_body "
                 "FROM  email, search_email "
                 "WHERE email.pk = search_email.rowid AND search_email.msg_id MATCH '"];
                
                for (UidEntry* p in pagedUids) { [query appendFormat:@"%@ OR ",p.msgId]; }
                
                query = [[NSMutableString alloc]initWithString:[query substringToIndex:(query.length-3)]];
                [query appendFormat:@"'"];
                
                for (NSNumber* dbNum in dbNums){
                    if (self.cancelled) {
                        [subscriber sendCompleted];
                        return [RACDisposable disposableWithBlock:^{}];
                    }
                    
                    [manager setDatabaseFilepath:[StringUtil filePathInDocumentsDirectoryForFileName:[GlobalDBFunctions dbFileNameForNum:[dbNum integerValue]]]];
                    [manager.databaseQueue inDatabase:^(FMDatabase *db) {
                        FMResultSet *results = [db executeQuery:query];
                        
                        if([db hadError] && [db lastErrorCode] == 1){
                            CCMLog(@"Checking table");
                            [Email tableCheck:db];
                        }
                        
                        while([results next]) {
                            Email * email = [[Email alloc]init];
                            
                            email.pk = [results intForColumnIndex:0];
                            email.sender = [MCOAddress addressWithNonEncodedRFC822String:[results stringForColumnIndex:1]];
                            email.subject = [results stringForColumnIndex:2];
                            email.datetime = [results dateForColumnIndex:3];
                            email.body = [results stringForColumnIndex:4];
                            email.flag = [results intForColumnIndex:5];
                            email.msgId = [results stringForColumnIndex:6];
                            
                            [[results stringForColumnIndex:7] isEqualToString:@""]?(email.tos = [[NSArray alloc]init]):(email.tos = [MCOAddress addressesWithNonEncodedRFC822String:[results stringForColumnIndex:7]]);
                            [[results stringForColumnIndex:8] isEqualToString:@""]?(email.ccs = [[NSArray alloc]init]):(email.ccs = [MCOAddress addressesWithNonEncodedRFC822String:[results stringForColumnIndex:8]]);
                            [[results stringForColumnIndex:9] isEqualToString:@""]?(email.bccs = [[NSArray alloc]init]):(email.bccs = [MCOAddress addressesWithNonEncodedRFC822String:[results stringForColumnIndex:9]]);
                            
                            email.htmlBody = [results stringForColumnIndex:10];
                            email.body = email.body?:@"";
                            email.htmlBody = email.htmlBody?:@"";
                            
                            allFound--;
                            
                            [subscriber sendNext:email];
                        }
                        [results close];
                    }];
                    
                    if (allFound == 0) break;
                }
            }
        }
        
        [subscriber sendCompleted];
        
        return [RACDisposable disposableWithBlock:^{
        }];
    }];
}

- (RACSignal *)allFoldersSearchInAccount:(NSInteger)accountIdx
{
    SyncManager* sm = [SyncManager getSingleton];
    NSDictionary* folderState;
    NSMutableSet* nums = [[NSMutableSet alloc]init];
    
    self.cancelled = NO;
    
    for(int i = 0; i < [AppSettings allFoldersName:accountIdx].count; i++){
        folderState = [sm retrieveState:i accountNum:accountIdx];
        [nums addObjectsFromArray:folderState[@"dbNums"]];
    }
    
    NSArray* dbs = [[NSArray alloc]initWithArray:[nums allObjects]];
    NSSortDescriptor* sortOrder = [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(self)) ascending: NO];
    dbs = [dbs sortedArrayUsingDescriptors:@[sortOrder]];
    
    return [self searchForSignal:[self performFolderSearch:[AppSettings importantFolderNumForAcct:accountIdx forBaseFolder:FolderTypeAll] withDbNum:dbs from:accountIdx]];
}

- (RACSignal *)activeFolderSearch:(NSInteger)email
{
    SyncManager* sm = [SyncManager getSingleton];
    NSDictionary* folderState;
    NSArray* nums;
    
    self.cancelled = NO;
    
    if ([AppSettings activeAccount] == -1) {
        NSMutableSet* numsM = [[NSMutableSet alloc]init];
        for (int i = 0; i < [AppSettings numActiveAccounts]; i++) {
            NSInteger accountIndex = [AppSettings numAccountForIndex:i];
            folderState = [sm retrieveState:[[Accounts sharedInstance].accounts[i] currentFolderIdx] accountNum:accountIndex];
            [numsM addObjectsFromArray:folderState[@"dbNums"]];
        }
        nums = [[NSArray alloc]initWithArray:[numsM allObjects]];
        NSSortDescriptor* sortOrder = [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(self)) ascending: NO];
        nums = [nums sortedArrayUsingDescriptors:@[sortOrder]];
    }
    else {
        folderState = [sm retrieveState:[[Accounts sharedInstance].currentAccount currentFolderIdx] accountNum:[AppSettings activeAccount]];
        nums = folderState[@"dbNums"];
        NSSortDescriptor* sortOrder = [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(self)) ascending: NO];
        nums = [nums sortedArrayUsingDescriptors:@[sortOrder]];
    }
    
    return [self searchForSignal:[self performFolderSearch:[[Accounts sharedInstance].currentAccount currentFolderIdx] withDbNum:nums from:email]];
}

- (RACSignal *)threadSearch:(NSString *)thread
{
    NSArray* nums  = [[[SyncManager getSingleton] retrieveAllDBNumsAccountNum:[AppSettings activeAccount]] allObjects];
    
    NSSortDescriptor* sortOrder = [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(self)) ascending: NO];
    nums = [nums sortedArrayUsingDescriptors: @[sortOrder]];
    
    return [self searchForSignal:[self performThreadSearch:thread withDbNum:nums]];
}

// Sender Search
#pragma mark Sender Search

- (RACSignal *)senderSearch:(NSArray *)addressess
{
    self.cancelled = NO;
    
    NSArray* dbNumbers = [[[SyncManager getSingleton] retrieveAllDBNumsAccountNum:[AppSettings activeAccount]] allObjects];
    
    NSSortDescriptor* sortOrder = [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(self)) ascending: NO];
    dbNumbers = [dbNumbers sortedArrayUsingDescriptors: @[sortOrder]];
    
    return [self searchForSignal:[self performSenderSearch:addressess withDbNum:dbNumbers]];
}

- (RACSignal *)performSenderSearch:(NSArray *)addresses withDbNum:(NSArray *)dbNums
{
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        
        NSMutableString *query = [NSMutableString string];
        
        [query appendString:@"SELECT email.pk, email.datetime, email.sender, email.tos, email.ccs, email.bccs, email.msg_id, email.html_body, email.flag, search_email.subject,"
         "search_email.body FROM "
         "email, search_email "
         "WHERE email.pk = search_email.rowid AND "];
        
        for (Person* p in addresses) {
            [query appendFormat:@"search_email.people LIKE '%@%@%@' OR",@"%",p.email,@"%"];
        }
        
        NSString *queryString = [query substringToIndex:(query.length-3)];
        
        query = [NSMutableString string];
        [query appendFormat:@"%@ ORDER BY email.datetime DESC;",queryString];
        queryString = query;
        
        for(id dbNumObj in dbNums) {
            int dbNum = [dbNumObj intValue];
            if (self.cancelled)
                [subscriber sendCompleted];
            
            FMDatabaseQueue *queue = [FMDatabaseQueue databaseQueueWithPath:[StringUtil filePathInDocumentsDirectoryForFileName:[GlobalDBFunctions dbFileNameForNum:dbNum]]];
            
            [queue inDatabase:^(FMDatabase *db) {
                
                FMResultSet *results = [db executeQuery:queryString];
                
                while([results next]) {
                    [subscriber sendNext:[Email resToEmail:results]];
                    
                    if(self.cancelled) break;
                }
                
                [results close];
            }];
        }
        [subscriber sendCompleted];
        
        return nil;
    }];
}

@end
