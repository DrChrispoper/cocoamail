//
//  Accounts.m
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 11/08/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "Accounts.h"
#import "AppSettings.h"
#import "SyncManager.h"
#import "SearchRunner.h"
#import "ImapSync.h"
#import "EmailProcessor.h"
#import "CCMStatus.h"
#import "InViewController+SGProgress.h"
#import "UserSettings.h"
#import "Draft.h"
#import "RegExCategories.h"

#import <CocoaLumberjack/CocoaLumberjack.h>


@interface Accounts()

@property (nonatomic, retain) NSOperationQueue* localFetchQueue;
@property (nonatomic, strong) NSArray<Account*>* accounts;

@end

@implementation Accounts

+(Accounts*) sharedInstance
{
    static dispatch_once_t once;
    static Accounts * sharedInstance;
    
    dispatch_once(&once, ^{
        
        DDLogInfo(@"dispatch_once");
        
        sharedInstance = [[self alloc] init];
        sharedInstance.quickSwipeType = [[AppSettings getSingleton] quickSwipe];
        sharedInstance.currentAccountIdx = [AppSettings lastAccountIndex];
        
        sharedInstance.localFetchQueue = [NSOperationQueue new];
        [sharedInstance.localFetchQueue setMaxConcurrentOperationCount:1];
        [sharedInstance.localFetchQueue setQualityOfService:NSQualityOfServiceUserInitiated];
        
        /*sharedInstance.accountColors = @[[UIColor colorWithRed:0.01f green:0.49f blue:1.f alpha:1.f],
         [UIColor colorWithRed:0.44f green:0.02f blue:1.f alpha:1.f],
         [UIColor colorWithRed:1.f green:0.01f blue:0.87f alpha:1.f],
         [UIColor colorWithRed:1.f green:0.07f blue:0.01f alpha:1.f],
         [UIColor colorWithRed:1.f green:0.49f blue:0.01f alpha:1.f],
         [UIColor colorWithRed:0.96f green:0.72f blue:0.02f alpha:1.f],
         [UIColor colorWithRed:0.07f green:0.71f blue:0.02f alpha:1.f]];*/
        
        NSInteger numActiveAccounts = [AppSettings numActiveAccounts];
        
        NSMutableArray* accounts = [[NSMutableArray alloc]initWithCapacity:numActiveAccounts];
        
        if ( numActiveAccounts > 0) {
            
            AppSettings *appSettings = [AppSettings getSingleton];
            
            DDAssert(appSettings, @"AppSettings must exist.");
            
            for (UserSettings* user in appSettings.users) {
                //for (int accountIndex = 0; accountIndex < [AppSettings numActiveAccounts]; accountIndex++) {
                if (user.isDeleted) {
                    continue;
                }
                
                Account* a = [self _createAccountWithUserSettings:user];
                [a initContent];
                [accounts addObject:a];
            }
        }
        
        Account* all = [self _createAllAccountsFrom:accounts];
        [accounts addObject:all];
        
        sharedInstance.accounts = accounts;
        
        if ([AppSettings numActiveAccounts] > 0) {
            [sharedInstance runLoadData];
        }
        
        DDLogVerbose(@"Accounts Singleton Initialized. Account count = %ld",(unsigned long)[accounts count]);
        DDLogVerbose(@"Accounts:%@",[sharedInstance description]);
    });
    
    return sharedInstance;
}

+(Account*) _createAccountWithUserSettings:(UserSettings*)user
{
    Account* ac = [Account emptyAccount];
    
    [ac setNewUser:user];
    
    ac.userFolders = [ac userFolderNames];
    
    ac.person = [Person createWithName:ac.user.name email:ac.user.username icon:nil codeName:ac.user.initials];
    [ac.person linkToAccount:ac];
    [[Persons sharedInstance] registerPersonWithNegativeID:ac.person];
    
    return ac;
}

+(Account*) _createAllAccountsFrom:(NSArray*)account
{
    Account* ac = [[Account alloc] init];
    [ac setNewUser:[[AppSettings getSingleton].users lastObject]];
    
    NSMutableArray* userfolders = [NSMutableArray arrayWithCapacity:0];
    /*for (Account* a in accounts) {
     [userfolders addObjectsFromArray:a.userFolders];
     }*/
    
    ac.userFolders = userfolders; // NB Empty array
    
    ac.person = [Person createWithName:nil email:nil icon:nil codeName:@"ALL"];
    
    return ac;
}

-(void) runLoadData
{
    ddLogLevel = DDLogLevelDebug;
    
    DDLogInfo(@"ENTERED");
    
    // If this is NOT the All Mails user account ..
    if (!self.currentAccount.user.isAll) {

        DDLogDebug(@"\tNOT All Mail Messages");
        
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            
            DDLogDebug(@"STARTING BLOCK on mainQueue.");
            
            //NSInteger refBatch = 5;
            //NSInteger __block batch = refBatch;
            [self.currentAccount.mailListSubscriber localSearchDone:NO];

            [[[SearchRunner getSingleton] activeFolderSearch:nil
                                                inAccountNum:self.currentAccount.user.accountNum]
             subscribeNext:^(Mail* email) {
//                 DDLogDebug(@"SearchRunner next email \"%@\"",email.subject);
                 
                 [self _sortEmail:email];
                 //if (batch-- == 0) {
                //   batch = refBatch;
                    //[self.currentAccount.mailListSubscriber reFetch:YES];
                 //}
             } // end SearchRunner subscribeNext block
             completed:^{
                 DDLogDebug(@"SearchRunner returned \"completed\", so alerting currentAccount's mailListSubscriber that the localSearchDone:YES and reFetch:YES");
                 [self.currentAccount.mailListSubscriber localSearchDone:YES];
                 [self.currentAccount.mailListSubscriber reFetch:YES];
             }]; // end SearchRunner completed block
        }]; // end mainQueue block
    } // end All Mail
    
    DDLogInfo(@"START PART 2");

    [self.localFetchQueue addOperationWithBlock:^{
        
        DDLogDebug(@"Adding BLOCK to localFetchQueue.");
        
        [[[SearchRunner getSingleton] allEmailsSearch]
         subscribeNext:^(Mail* email) {
//             DDLogDebug(@"Next Mail from allEmailsSearch: Add mail \"%@\" from DB to local store.",email.subject);
             
             if (email && email.user && !email.user.isDeleted) {
                 [self _sortEmail:email];
             }
         }
         completed:^{
            DDLogDebug(@"Completed loading email from DB, calling runTestData on account.");
             
             [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                 if (self.currentAccount.user.isAll) {
                     for (NSInteger accountIndex = 0; accountIndex < [AppSettings numActiveAccounts]; accountIndex++) {
                         [self.accounts[accountIndex] runTestData];
                     }
                 }
                 else {
                     [self.currentAccount runTestData];
                 }
             }];
         }];
    }];
    
}

-(void) _sortEmail:(Mail*)email
{
    DDAssert(email,@"email must not be null");
    
    // If no email user or email's user/account is deleted ...
    if (!email.user || email.user.isDeleted) {
        
        DDLogInfo(@"Houston on a un probleme avec l'email:%@", email.subject);
        
        // Delete this email message from the database
        EmailProcessor* emailProcessor = [EmailProcessor getSingleton];
        
        NSInvocationOperation* nextOpUp
        = [[NSInvocationOperation alloc] initWithTarget:emailProcessor
                                               selector:@selector(clean:)
                                                 object:email];
        
        [emailProcessor.operationQueue addOperation:nextOpUp];
    }
    else {
        // Add email message to user account
        [email.user.linkedAccount insertRows:email];
    }
}

-(void) deleteAccount:(Account*)account completed:(void (^)(void))completedBlock;
{
    dispatch_queue_t defaultQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    
    dispatch_async( defaultQueue, ^{
        
        DDLogDebug(@"BLOCK START - DISPATCH_QUEUE_PRIORITY_DEFAULT");
        
        [[ImapSync sharedServices:account.user] cancel];
        
        [account.user setUsername:@""];
        [account.user setPassword:@""];
        [account.user setOAuth:@""];
        [account.user setIdentifier:@""];
        [account.user setDeleted:YES];
        [account cancelSearch];
        
        [[SearchRunner getSingleton] cancel];
        
        [[[SearchRunner getSingleton] deleteEmailsInAccountNum:account.user.accountNum]
         subscribeNext:^(Mail* email) {
             DDLogVerbose(@"[SearchRunner deleteEmailsInAccountNum:%@] - subscribeNext:(for mail %@",
                          @(account.user.accountNum),email.subject);
         }
         completed:^{
             
             NSMutableArray* tmp = [self.accounts mutableCopy];
             NSInteger removeIdx = [tmp indexOfObject:account];
             
             if (removeIdx != NSNotFound) {
                 [ImapSync deletedAndWait:account.user];
                 
                 [tmp removeObjectAtIndex:removeIdx];
                 self.accounts = tmp;
                 
                 self.currentAccountIdx = 0;
                 
                 if ([AppSettings defaultAccountIndex] == account.idx) {
                     for (UserSettings* user in [AppSettings getSingleton].users) {
                         if (!user.isDeleted) {
                             [AppSettings setDefaultAccountNum:user.accountNum];
                             break;
                         }
                     }
                 }
             }
             
             completedBlock();
         }];
        
    });
}

-(Account*) account:(NSUInteger)accountIndex
{
    DDAssert(accountIndex>=0, @"Account Index must not be -1");
    
    if (accountIndex < self.accounts.count) {
        return self.accounts[accountIndex];
    }
    
    DDAssert(accountIndex <= [AppSettings numActiveAccounts], @"accountIdx:%ld is incorrect only %ld active account",(long)accountIndex,(long)[AppSettings numActiveAccounts]);
    
    return nil;
}

-(NSInteger) getPersonID:(NSUInteger)accountIndex
{
    if (accountIndex >= self.accountsCount /* || accountIndex < 0 */) {
        Persons* p = [Persons sharedInstance];
        
        if (p.idxCocoaPerson == 0) {
            Person* more = [Person createWithName:nil email:@"support@cocoamail.com" icon:[UIImage imageNamed:@"cocoamail"] codeName:nil];
            p.idxCocoaPerson = [p addPerson:more];
        }
        
        return p.idxCocoaPerson;
    }
    
    Account* ac = self.accounts[accountIndex];
    NSInteger index = [[Persons sharedInstance] indexForPerson:ac.person];
    return index;
}

-(NSInteger) accountsCount
{
    return self.accounts.count;
}

-(void) addAccount:(Account*)account
{
    DDAssert(account, @"Account must not be nil.");
    
    [[Persons sharedInstance] registerPersonWithNegativeID:account.person];
    
    [account.person linkToAccount:account];
    
    [account initContent];
    
    //NSInteger currentIdx = self.currentAccountIdx;
    NSMutableArray* tmp = [self.accounts mutableCopy];
    NSInteger putIdx = tmp.count - 1;
    
    [tmp insertObject:account atIndex:putIdx];
    self.accounts = tmp;
    
    /*if (putIdx >= currentIdx) {
     self.currentAccountIdx = currentIdx + 1;
     }*/
}

-(NSInteger) defaultAccountIdx
{
    return [AppSettings defaultAccountIndex];
}

-(void) setCurrentAccountIdx:(NSInteger)currentAccountIdx
{
    _currentAccountIdx = currentAccountIdx;
    [AppSettings setLastAccountIndex:currentAccountIdx];
}

-(void) setDefaultAccountIdx:(NSInteger)defaultAccountIdx
{
    [AppSettings setDefaultAccountNum:[AppSettings userWithIndex:defaultAccountIdx].accountNum];
}

-(void) setQuickSwipeType:(QuickSwipeType)quickSwipeType
{
    _quickSwipeType = quickSwipeType;
    [[AppSettings getSingleton] setQuickSwipe:quickSwipeType];
}

-(Account*) currentAccount
{
    if (self.currentAccountIdx >= 0) {
        return self.accounts[self.currentAccountIdx];
    }
    
    return nil;
}

-(NSArray<Account*>*) accounts
{
    return _accounts;
}

+(NSArray*) systemFolderIcons
{
    return @[@"inbox_off", @"favoris_off", @"sent_off", @"draft_off", @"all_off", @"delete_off", @"spam_off",@"boite_envoi"];
}

+(NSString*) userFolderIcon
{
    return @"folder_off";
}

+(NSString*) userFolderPadIcon
{
    return @"folder_pad_off";
}

-(Conversation*) conversationForCI:(ConversationIndex*)conversationIndex
{
    return [[conversationIndex.user.linkedAccount conversations] objectAtIndex:conversationIndex.index];
}

-(void) getDrafts
{
    NSFileManager *filemgr = [NSFileManager defaultManager];
    NSString *draftPath = @"drafts";
    
    NSString *documentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString* folderPath = [documentsDirectory stringByAppendingPathComponent:draftPath];
    
    if (![filemgr fileExistsAtPath:folderPath]) {
        [filemgr createDirectoryAtPath:folderPath withIntermediateDirectories:NO attributes:nil error:nil];
    }
    
    NSArray *dirFiles = [filemgr contentsOfDirectoryAtPath:folderPath error:nil];
    
    for (NSString* fileName in dirFiles) {
        NSString* localPath = [folderPath stringByAppendingPathComponent:fileName];
        Draft* draft = [NSKeyedUnarchiver unarchiveObjectWithFile:localPath];
        
        if (!draft.msgID) {
            draft.msgID = @"0";
        }
        
        [[AppSettings userWithNum:draft.accountNum].linkedAccount addLocalDraft:draft];
    }
}

-(void) appeared
{
    _canUI = YES;
}

#pragma mark Accounts description

-(NSString *)description
{
    NSMutableString *desc = [NSMutableString string ];
    
    [desc appendFormat:@"Accounts has %lu accounts.\n",(unsigned long)[self.accounts count]];
    for (Account *acnt in self.accounts) {
        [desc appendString:[acnt description]];
    }
    
    return desc;
}


@end // end Accounts class

