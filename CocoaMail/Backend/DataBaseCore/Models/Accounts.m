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
                
        sharedInstance = [[self alloc] init];
        sharedInstance.quickSwipeType = [[AppSettings getSingleton] quickSwipe];
        sharedInstance.currentAccountIdx = (NSUInteger) [AppSettings lastAccountIndex];
        
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
        
        NSUInteger numActiveAccounts = [AppSettings numActiveAccounts];
        
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
        
        // If we've loaded any accounts from from memory ...
        if ([AppSettings numActiveAccounts] > 0) {
            // update the account mail from the database
            Account *currAccount = [sharedInstance account:sharedInstance.currentAccountIdx];
            if ( currAccount ) {
                [sharedInstance _loadMailFromDatabaseForAccount:currAccount];
            }
            else {
                DDLogWarn(@"No Account found for account index %@",@(sharedInstance.currentAccountIdx));
            }
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

// Called only when the Accounts shared instance is initialized, and there are > 0 accounts
//
-(void) _loadMailFromDatabaseForAccount:(Account*)account
{
    DDLogInfo(@"*** ENTRY POINT ***");

    DDLogInfo(@"START PART 1 - If Current Account is ALL Account, then load All Mail from Database.");

    // If this is NOT the All Mails user account ..
    if ( !account.user.isAll ) {
        
        DDLogInfo(@"Not the All Mail Account.");
        
        id<MailListDelegate> delegate = account.mailListDelegate;  // strong hold
        
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            
            //NSInteger refBatch = 5;
            //NSInteger __block batch = refBatch;
            [account.mailListDelegate localSearchDone:NO];
            
            // Search for all email belonging to this account in the DB
            //
            DDLogInfo(@"CALLING activeFolderSearch:nil inAccountNum:%@ (\"%@\") ", @(account.user.accountNum), account.user.imapHostname );

            [[[SearchRunner getSingleton] activeFolderSearch:nil inAccountNum:account.user.accountNum]
             
             subscribeNext:^(Mail* email) {
                 DDLogDebug(@"subscribeNext received for activeFolderSearch");
//                 DDLogDebug(@"SearchRunner next email \"%@\"",email.subject);
                 
                 // Add the mail message to the account's Conversation book keeeping.
                 [self _addMail:email];
                 //if (batch-- == 0) {
                //   batch = refBatch;
                    //[self.currentAccount.mailListDelegate reFetch:YES];
                 //}
             } // end SearchRunner subscribeNext block
             completed:^{
                DDLogInfo(@"COMPLETED activeFolderSearch:nil inAccountNum:%@ (\"%@\") ", @(account.user.accountNum), account.user.imapHostname );

                 [delegate localSearchDone:YES];
                 
                 [delegate reFetch:YES];  // This will cause the Mail List tableView to redraw
                 
             }]; // end SearchRunner completed block
        }]; // end mainQueue block
    } // end Not All Mail Account
    else { // this IS the All Mail Account
        DDLogInfo(@"PART 1 - Do Nothing (because All Mail Account)");
    }
    
    DDLogInfo(@"START PART 2 - Load All Mails from Database.");

    NSUInteger __block _mailCount = 0;
    
    [self.localFetchQueue addOperationWithBlock:^{
        
        DDLogInfo(@"QUEUEING allEmailsDBSearch");
        
        // Load ALL email messages from the database, setting up its in memory structures (e.g. conversations)
        
        [[[SearchRunner getSingleton] allEmailsDBSearch]
         
         subscribeNext:^(Mail* email) {
             _mailCount++;
             [self _addMail:email];
         }
         completed:^{
             DDLogInfo(@"COMPLETED allEmailsDBSearch");

             DDLogInfo(@"PART 2 - Loaded %@ mail messages from database; will refresh table view and Update deleted and changed from IMAP server.",@(_mailCount));
             _mailCount = 0;
             
             [account.mailListDelegate reloadTableView];
             
             [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                 
                 if (account.user.isAll) {
                     // update all accounts
                     for (Account *acnt in self.accounts) {
                         [acnt updateCurrentFolderMailInDatabaseFromImapServer];
                     }
                 }
                 else {
                     // not the all account
                     
                     // UPDATE current folder mail from IMAP server: remove deleted, update updated (e.g. flagged)
                     [account updateCurrentFolderMailInDatabaseFromImapServer];
                 }
             }];
         }];
    }];
    
}

-(void) _addMail:(Mail*)email
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
        [email.user.linkedAccount insertIntoConversation:email];
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
        
        DDLogInfo(@"CALLING deleteEmailsInAccountNum:%@ (\"%@\")", @(account.user.accountNum), account.user.imapHostname );

        [[[SearchRunner getSingleton] deleteEmailsInAccountNum:account.user.accountNum]
         subscribeNext:^(Mail* email) {
             DDLogInfo(@"subscribeNext received for deleteEmailsInAccountNum");

             DDLogVerbose(@"[SearchRunner deleteEmailsInAccountNum:%@] - subscribeNext:(for mail %@",
                          @(account.user.accountNum),email.subject);
         }
         completed:^{
             DDLogInfo(@"COMPLETED deleteEmailsInAccountNum:%@ (\"%@\")", @(account.user.accountNum), account.user.imapHostname );

             NSMutableArray* tmp = [self.accounts mutableCopy];
             NSUInteger removeIdx = [tmp indexOfObject:account];
             
             if (removeIdx != NSNotFound) {
                 [ImapSync deletedAndWait:account.user];
                 
                 [tmp removeObjectAtIndex:removeIdx];
                 self.accounts = tmp;
                 
                 self.currentAccountIdx = 0;
                 
                 if ([AppSettings defaultAccountIndex] == account.idx) {
                     for (UserSettings* user in [AppSettings getSingleton].users) {
                         if (!user.isDeleted) {
                             [AppSettings setDefaultAccountNum:(NSUInteger)user.accountNum];
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

-(NSUInteger) accountsCount
{
    return self.accounts.count;
}

-(void) addAccount:(Account*)account
{
    DDAssert(account, @"Account must not be nil.");
    
    [[Persons sharedInstance] registerPersonWithNegativeID:account.person];
    
    [account.person linkToAccount:account];
    
    [account initContent];
    
//    if ( self.accounts.count == 0 ) {
//        return;
//    }
    
    //NSInteger currentIdx = self.currentAccountIdx;
    NSMutableArray* tmp = [self.accounts mutableCopy];
    NSUInteger putIdx = tmp.count - 1;
    [tmp insertObject:account atIndex:putIdx];
    self.accounts = tmp;
    
    /*if (putIdx >= currentIdx) {
     self.currentAccountIdx = currentIdx + 1;
     }*/
}

-(NSUInteger) defaultAccountIdx
{
    return [AppSettings defaultAccountIndex];
}

-(void) setCurrentAccountIdx:(NSUInteger)currentAccountIdx
{
    _currentAccountIdx = currentAccountIdx;
    [AppSettings setLastAccountIndex:currentAccountIdx];
}

-(void) setDefaultAccountIdx:(NSUInteger)defaultAccountIdx
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
    // currentAccountIdx is unsigned, therefore always >= 0
    
    return self.accounts[self.currentAccountIdx];
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

