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
#import "Folders.h"

#import <CocoaLumberjack/CocoaLumberjack.h>


@interface Accounts()

@property (nonatomic, retain) NSOperationQueue* localFetchQueue;
@property (nonatomic, strong) NSArray<Account*>* accounts;
@property (nonatomic) BOOL canUI;

@end


@implementation Accounts

//
// The Accounts object is a Singleton
//
+(Accounts*) sharedInstance
{
    static dispatch_once_t once;
    static Accounts * sharedInstance;
    
    dispatch_once(&once, ^{
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
        
        Account* allAccount = [self _createAllAccountsFrom:accounts];
        [accounts addObject:allAccount];
        
        sharedInstance.accounts = accounts;
        
        if ([AppSettings numActiveAccounts] > 0) {
            [sharedInstance runLoadData];
        }
        
        DDLogInfo(@"Accounts Loaded, count = %ld",[accounts count]);
        DDLogInfo(@"Accounts:\n%@",[sharedInstance description]);
    });
    
    return sharedInstance;
}

+(Account*) _createAccountWithUserSettings:(UserSettings*)user
{
    Account* newAccount = [Account emptyAccount];
    
    [newAccount setNewUser:user];
    
    NSArray *allUserFolderNames = [newAccount.user allNonImportantFoldersName];
    [self.imapFolders addUserFoldersWithNames:allUserFolderNames];
    
    //Folders Indentation?
//    NSArray* userFolderNames = [newAccount.user allNonImportantFoldersName];
//    NSUInteger userFolderCount = [userFolderNames count];
    
    //
    // Create an array, where each entry contains
    // the name of a folder and whether or not the folder contains a
    // path divider and is therefore part of a tree branch.
    //
//    NSMutableArray* foldersNIndent = [[NSMutableArray alloc]initWithCapacity:userFolderCount];
//    for (NSString* folderName in userFolderNames) {
//#warning Is '/' guaranteed to be the only mailbox path connector?
//        [foldersNIndent addObject:@[folderName, @([folderName containsString:@"/"])]];
//    }
//    newAccount.userFolders = foldersNIndent;
    
    newAccount.person = [Person createWithName:newAccount.user.name
                                         email:newAccount.user.username
                                          icon:nil
                                      codeName:newAccount.user.initials];
    [newAccount.person linkToAccount:newAccount];
    [[Persons sharedInstance] registerPersonWithNegativeID:newAccount.person];
    
    return newAccount;
}

+(Account*) _createAllAccountsFrom:(NSArray*)account
{
    Account* newAllAccount = [[Account alloc] init];
    
    AppSettings *appSettings = [AppSettings getSingleton];
    NSArray <UserSettings *> *users = [AppSettings users];
    UserSettings *lastUser = [users lastObject];
    [newAllAccount setNewUser:lastUser];

    
//    NSMutableArray* userfolders = [NSMutableArray arrayWithCapacity:0];
    /*for (Account* a in accounts) {
     [userfolders addObjectsFromArray:a.userFolders];
     }*/
    
//    ac.userFolders = userfolders;
    
    newAllAccount.person = [Person createWithName:nil
                                 email:nil
                                  icon:nil
                              codeName:@"ALL"];
    
    return newAllAccount;
}

-(void) runLoadData
{
    if (!self.currentAccount.user.isAll) {
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            //NSInteger refBatch = 5;
            //NSInteger __block batch = refBatch;
            [self.currentAccount.mailListSubscriber localSearchDone:NO];

            [[[SearchRunner getSingleton] activeFolderSearch:nil inAccountNum:self.currentAccount.user.accountNum]
             subscribeNext:^(Mail* email) {
                 [self sortEmail:email];
                 //if (batch-- == 0) {
                //   batch = refBatch;
                    //[self.currentAccount.mailListSubscriber reFetch:YES];
                 //}
             }
             completed:^{
                 [self.currentAccount.mailListSubscriber localSearchDone:YES];
                 [self.currentAccount.mailListSubscriber reFetch:YES];
             }];
        }];
    }
    
    
    [self.localFetchQueue addOperationWithBlock:^{
        [[[SearchRunner getSingleton] allEmailsSearch]
         subscribeNext:^(Mail* email) {
             if (email.user && !email.user.isDeleted) {
                 [self sortEmail:email];
             }
         }
         completed:^{
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

-(void) sortEmail:(Mail*)email
{
    if (!email.user || email.user.isDeleted) {
        DDLogInfo(@"Houston on a un probleme avec l'email:%@", email.subject);
        NSInvocationOperation* nextOpUp = [[NSInvocationOperation alloc] initWithTarget:[EmailProcessor getSingleton] selector:@selector(clean:) object:email];
        [[EmailProcessor getSingleton].operationQueue addOperation:nextOpUp];
    }
    else {
        [email.user.linkedAccount insertRows:email];
    }
}

-(void) deleteAccount:(Account*)account completed:(void (^)(void))completedBlock;
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        [[ImapSync sharedServices:account.user] cancel];
        
        [account.user setUsername:@""];
        [account.user setPassword:@""];
        [account.user setOAuth:@""];
        [account.user setIdentifier:@""];
        [account.user setDeleted:YES];
        [account cancelSearch];
        
        [[SearchRunner getSingleton] cancel];
        
        [[[SearchRunner getSingleton] deleteEmailsInAccountNum:account.user.accountNum]
         subscribeNext:^(Mail* email) {}
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

-(Account*) account:(NSInteger)accountIndex
{
    if (accountIndex < self.accounts.count) {
        return self.accounts[accountIndex];
    }
    
    DDAssert(accountIndex <= [AppSettings numActiveAccounts], @"accountIdx:%ld is incorrect only %ld active account",(long)accountIndex,(long)[AppSettings numActiveAccounts]);
    
    return nil;
}

-(NSInteger) getPersonID:(NSInteger)accountIndex
{
    if (accountIndex >= self.accountsCount || accountIndex < 0) {
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

-(NSArray*) accounts
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

#pragma mark - Accounts description

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

