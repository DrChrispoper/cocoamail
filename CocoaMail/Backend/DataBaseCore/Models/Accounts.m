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
@property (nonatomic) BOOL canUI;

@end

@interface Account () {
    BOOL _currentFolderFullSyncCompleted;
    BOOL _runningUpToDateTest;
}

typedef NSMutableArray<Conversation*> CCMMutableConversationArray;

// All Mail Conversations for this Account
@property (nonatomic, strong) CCMMutableConversationArray* allsMails;

// All Conversation ID's, used only(?) in InsertRows() function.
@property (nonatomic, strong) NSMutableSet* convIDs;

// User Folders Mail Index Sets
@property (nonatomic, strong) NSArray* userFoldersContent;

// System Folders Mail Index Sets
@property (nonatomic, strong) NSArray* systemFoldersContent;

@end

@implementation Accounts

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
        
        Account* all = [self _createAllAccountsFrom:accounts];
        [accounts addObject:all];
        
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
    Account* ac = [Account emptyAccount];
    
    [ac setNewUser:user];
    
    //Folders Indentation?
    NSArray* tmpFolders = [ac.user allNonImportantFoldersName];
    
    NSMutableArray* foldersNIndent = [[NSMutableArray alloc]initWithCapacity:tmpFolders.count];
    
    // MARK: Is '/' guaranteed to be the only mailbox path connector?

    for (NSString* folderName in tmpFolders) {
        [foldersNIndent addObject:@[folderName, @([folderName containsString:@"/"])]];
    }
    
    ac.userFolders = foldersNIndent;
    
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
    
    ac.userFolders = userfolders;
    ac.person = [Person createWithName:nil email:nil icon:nil codeName:@"ALL"];
    
    return ac;
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
                 DDLogDebug(@"IN runLoadData, called SearchRunner, recieved subscribeNext, so sorting email (1)");
                 [self sortEmail:email];
                 //if (batch-- == 0) {
                //   batch = refBatch;
                    //[self.currentAccount.mailListSubscriber reFetch:YES];
                 //}
             }
             completed:^{
                 DDLogDebug(@"IN runLoadData, called SearchRunner, recieved completed, so alerting currentAccount's mailListSubscriber that the localSearchDone:YES and reFetch:YES");
                 [self.currentAccount.mailListSubscriber localSearchDone:YES];
                 [self.currentAccount.mailListSubscriber reFetch:YES];
             }];
        }];
    }
    
    
    [self.localFetchQueue addOperationWithBlock:^{
        [[[SearchRunner getSingleton] allEmailsSearch]
         subscribeNext:^(Mail* email) {
             DDLogDebug(@"IN runLoadData, called SearchRunner, recieved subscribeNext, so sorting email (2)");
             if (email.user && !email.user.isDeleted) {
                 [self sortEmail:email];
             }
         }
         completed:^{
              DDLogDebug(@"IN runLoadData, called SearchRunner, recieved completed");
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
         subscribeNext:^(Mail* email) {
             int breakpoint = 1;
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


@interface Account () {
    NSOperationQueue* _localFetchQueue;
    BOOL _isLoadingMore;
    BOOL _hasLoadedAllLocal;
    BOOL _isSyncing;
    BOOL _isSyncingCurrentFolder;
    NSMutableArray* _drafts;
    NSMutableArray* _lastEmails;
    UIBackgroundTaskIdentifier _backgroundUpdateTask;
    UserSettings* _user;
}

@end

@implementation Account

+(instancetype) emptyAccount
{
    Account* a = [[Account alloc] init];
    
    // MARK: We should collect statistics on how many messages most people have
    a.allsMails = [NSMutableArray arrayWithCapacity:500];
    
    a.convIDs = [NSMutableSet setWithCapacity:500];
    
    return a;
}

-(NSInteger) idx
{
    return [AppSettings indexForAccountNum:_user.accountNum];
}

-(UserSettings*) user
{
    return _user;
}

-(void) setNewUser:(UserSettings*)user
{
    _user = user;
}

-(void) initContent
{
    _currentFolderFullSyncCompleted = YES;
    _runningUpToDateTest = NO;
    _drafts = [[NSMutableArray alloc]init];
    
    _localFetchQueue = [NSOperationQueue new];
    [_localFetchQueue setMaxConcurrentOperationCount:1];
    _isLoadingMore = NO;
    _hasLoadedAllLocal = NO;
    
    _isSyncing = NO;
    _isSyncingCurrentFolder = NO;
    
    //
    // Initialize the "Standard" IMAP Folders
    //
    
    // create structure
    NSMutableArray* array = [[NSMutableArray alloc] initWithCapacity:7];
    
    for (int i = 0; i < 7; i++) {
        [array addObject:[[NSMutableIndexSet alloc] init]];
    }
    self.systemFoldersContent = array;
    
    //
    // Initialize the "User" IMAP Folders
    //
    
    const NSInteger limite = self.userFolders.count;
    
    NSMutableArray* arrayU = [[NSMutableArray alloc] initWithCapacity:limite];
    for (int i = 0; i < limite; i++) {
        [arrayU addObject:[[NSMutableIndexSet alloc] init]];
    }
    
    self.userFoldersContent = arrayU;
    
    
    //Including Non selectable
    NSInteger folderCount = [[SyncManager getSingleton] folderCount:self.user.accountNum];
    
    _lastEmails = [[NSMutableArray alloc]initWithCapacity:folderCount];
    
    for (int index = 0; index < folderCount ; index++) {
        [_lastEmails addObject:[[Mail alloc]init]];
    }
    
    self.currentFolderType = decodeFolderTypeWith([AppSettings lastFolderIndex].integerValue);
    
    if (self.currentFolderType.type == FolderTypeUser) {
        if (self.currentFolderType.idx >= self.userFolders.count) {
            self.currentFolderType = CCMFolderTypeInbox;
            self.currentFolderIdx = [self.user numFolderWithFolder:self.currentFolderType];
        }
        else {
            NSString* name = self.userFolders[self.currentFolderType.idx][0];
            NSArray* names = [self.user allFoldersDisplayNames];
            for (int i = 0; i < names.count; i++) {
                if ([name isEqualToString:names[i]]) {
                    self.currentFolderIdx = i;
                    break;
                }
            }
        }
    } else {
        self.currentFolderIdx = [self.user numFolderWithFolder:self.currentFolderType];
    }
}

-(void) connect
{
    if (!self.user.isAll && self.user.isDeleted) {
        return;
    }
    
    if (self.user.isAll) {
        for (Account* a in [[Accounts sharedInstance] accounts]) {
            if (!a.user.isAll && !a.isConnected) {
                [[ImapSync doLogin:a.user] subscribeError:^(NSError *error) {
                    DDLogError(@"connection error");
                } completed:^{
                    DDLogInfo(@"login");
                }];
                
                break;
            }
        }
    }
    else {
        //if (!self.isConnected) {
        [[ImapSync doLogin:self.user] subscribeError:^(NSError *error) {
            if ([Accounts sharedInstance].canUI) {
                if (error.code == CCMConnectionError) {
                    [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.connecting_error", @"Connection error")  dismissAfter:2.0 code:2];
                }
                else if (error.code == CCMCredentialsError){
                    [CCMStatus showStatus:NSLocalizedString(@"add-account-view.error.wrong-credentials", @"Credentials")  dismissAfter:2.0 code:2];
                }
                else {
                    [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.connecting_error", @"Connection error")  dismissAfter:2.0 code:2];
                    DDLogError(@"Unkown connection error, Error Code =%ld",(long)error.code );
                }
            }
        } completed:^{}];
        //}
    }
}

-(BOOL) isConnected
{
    return [ImapSync sharedServices:self.user].connected;
}

-(void) setConnected
{
    DDAssert(!self.user.isAll, @"Should not be called by all Accounts");
    
    [ImapSync runInboxUnread:self.user];
    [self refreshCurrentFolder];
    [self sendOutboxs];
    
    if (kisActiveAccountAll){
        [[Accounts sharedInstance].currentAccount connect];
    }
}

-(void) setCurrentFolder:(CCMFolderType)folder
{
    if (encodeFolderTypeWith(self.currentFolderType) == encodeFolderTypeWith(folder)) {
        DDLogWarn(@"Same folder");
        return;
    }
    
    self.currentFolderType = folder;
    _currentFolderFullSyncCompleted = NO;
    _hasLoadedAllLocal = NO;
    _isLoadingMore = NO;
    
    [_localFetchQueue cancelAllOperations];
    
    [AppSettings setLastFolderIndex:@(encodeFolderTypeWith(folder))];
    
    if (folder.type == FolderTypeUser) {
        NSString* name = [[Accounts sharedInstance] currentAccount].userFolders[folder.idx][0];
        NSArray* names = [self.user allFoldersDisplayNames];
        for (int i = 0; i < names.count; i++) {
            if ([name isEqualToString:names[i]]) {
                self.currentFolderIdx = i;
                [self refreshCurrentFolder];
                [self localFetchMore:NO];
                return;
            }
        }
    } else {
        if (self.user.isAll) {
            self.currentFolderIdx = folder.type;
            for (Account* a in [Accounts sharedInstance].accounts) {
                if (!a.user.isAll) {
                    [a setCurrentFolder:folder];
                }
            }
        }
        else {
            self.currentFolderIdx = [self.user numFolderWithFolder:folder];
            [self refreshCurrentFolder];
            [self localFetchMore:NO];
        }
    }
}

-(void) releaseContent
{
    //TODO:If memory issues
    //self.allsMails = nil;
    //self.userFoldersContent = nil;
    //self.systemFoldersContent = nil;
    // let the drafts
}

#warning This property is generated every time we call it !?!

-(NSArray*) systemFolderNames
{
    NSMutableArray* names = [[NSMutableArray alloc]init];
    
    [names addObject:NSLocalizedString(@"Inbox", @"Inbox")];
    [names addObject:NSLocalizedString(@"Favoris", @"Favoris")];
    
    //if (self.user.isAll || [self.user importantFolderNumforBaseFolder:FolderTypeSent] != -1) {
        [names addObject:NSLocalizedString(@"Sent", @"Sent")];
    //}
    
    //if (self.user.isAll || [self.user importantFolderNumforBaseFolder:FolderTypeDrafts] != -1) {
        [names addObject:NSLocalizedString(@"Drafts", @"Drafts")];
    //}
    [names addObject:NSLocalizedString(@"All emails", @"All emails")];
    
    //if (self.user.isAll || [self.user importantFolderNumforBaseFolder:FolderTypeDeleted] != -1) {
        [names addObject:NSLocalizedString(@"Deleted", @"Deleted")];
    //}
    
    //if (self.user.isAll || [self.user importantFolderNumforBaseFolder:FolderTypeSpam] != -1) {
        [names addObject:NSLocalizedString(@"Spam", @"Spam")];
    //}
    
    [names addObject:NSLocalizedString(@"Outbox", @"Outbox")];
    
    return names;
}

- (void)cancelSearch
{
    self.mailListSubscriber = nil;
}

#pragma mark - Receive Mails

-(void) addLocalDraft:(Draft*)draft
{
    Mail* m = [Mail mailWithDraft:draft];
    [self insertRows:m];
}

-(void) insertRows:(Mail*)email
{
    if (self.user.isDeleted) {
        return;
    }
    
    NSString *sonID = [email sonID];
    
    if ( [sonID isEqualToString:@""] ||
         [sonID isEqualToString:@"0"] ||
         ![_convIDs containsObject:sonID] ) {
        
        // No conversation with a matching sonID ...
        [self _addNewConversationWithMail:email];
        
    } else {
        
        // Find the conversation with the matching sonID,
        // and add this mail message to the conversation,
        // and
        for (NSUInteger idx = 0; idx < self.allsMails.count; idx++) {
            Conversation* conv = self.allsMails[idx];
            
            // Find the conversation with the matching sonID
            if ([[[conv firstMail] sonID] isEqualToString:sonID]) {
                
                // Add the mail message to the conversation
                [conv addMail:email];
                
                [self _addCon:idx toFoldersContent:[conv foldersType]];
                
                return; // we match only once (could be break;)
            }
        }
    }
    
}

-(void)_addNewConversationWithMail:(Mail*)email
{
    Conversation* conv = [[Conversation alloc]init];
    
    [conv addMail:email];
    
    if ([RX(@"^[0-9]+?$") isMatch:email.msgID]) {
        conv.isDraft = YES;
    }
    
    [_convIDs addObject:[email sonID]];
    
    [self addConversation:conv];
}

-(void) _addCon:(NSUInteger)idx toFoldersContent:(NSSet*)folders
{
    DDAssert(!self.user.isAll, @"Should not be called by all Accounts");
    
    for (NSNumber* Fuser in folders) {
        [self _addIdx:idx inArray:decodeFolderTypeWith([Fuser integerValue])];
    }
}

-(NSMutableIndexSet*) _mailIndeciesForFolder:(CCMFolderType)folderHandle
{
    NSMutableIndexSet *mailIndecies = nil;
    
    if (folderHandle.type == FolderTypeUser) {
        mailIndecies = self.userFoldersContent[folderHandle.idx];
    }
    else {
        mailIndecies = self.systemFoldersContent[folderHandle.type];
    }
    return mailIndecies;
}

-(void) _addIdx:(NSUInteger)idx inArray:(CCMFolderType)folderHandle
{
    DDAssert(!self.user.isAll, @"Should not be called by all Accounts");
    
    NSMutableIndexSet* folderMailIndecies = [self _mailIndeciesForFolder:folderHandle];
    
    if ( ![folderMailIndecies containsIndex:idx] ) {
        
        [folderMailIndecies addIndex:idx];
        
        if (encodeFolderTypeWith(folderHandle) == encodeFolderTypeWith(self.currentFolderType)) {
            
            //NSMutableDictionary* syncState = [[SyncManager getSingleton] retrieveState:[self.user numFolderWithFolder:self.currentFolderType] accountNum:self.user.accountNum];
            //NSInteger tmpEmailCount = [syncState[@"emailCount"] integerValue];
            
            if ( [folderMailIndecies count] == 20) {
                if ([Accounts sharedInstance].currentAccountIdx == self.idx) {
                    [self runTestData];
                }
            }
            
            ConversationIndex* ci = [ConversationIndex initWithIndex:idx user:self.user];
            
            //if (set.count == 50 || (tmpEmailCount < 50 && set.count == tmpEmailCount)) {
            //[self.mailListSubscriber reFetch:YES];
            [self.mailListSubscriber insertConversationIndex:ci];
            //}
        }
    }
}

-(NSUInteger) addConversation:(Conversation*)conv
{
    DDAssert(!self.user.isAll, @"Should not be called for All Account");
    
    CCMMutableConversationArray* tmp = [self.allsMails mutableCopy];
    NSUInteger index = [tmp indexOfObject:conv];
    
    if (index == NSNotFound) {
        [self.allsMails addObject:conv];
        index  = self.allsMails.count - 1;
        
        if (![conv.foldersType containsObject:numberWithFolderType(FolderTypeDeleted)] &&
            ![conv.foldersType containsObject:numberWithFolderType(FolderTypeSpam)]    &&
            ![conv.foldersType containsObject:numberWithFolderType(FolderTypeDrafts)]) {
            
            [self _addIdx:index inArray:CCMFolderTypeAll];
        }
        
        if ([conv isFav]) {
            [self _addIdx:index inArray:CCMFolderTypeFavoris];
        }
        
        [self _addCon:index toFoldersContent:conv.foldersType];
    }
    else {
        Conversation* con = [self.allsMails objectAtIndex:index];
        
        for (Mail* m in conv.mails) {
            [con addMail:m];
        }
    }
    
    return index;
}

#pragma mark - Get Mails

-(CCMMutableConversationArray*) conversations
{
    return self.allsMails;
}

-(Conversation*) getConversationForIndex:(NSUInteger)index
{
    DDAssert(!self.user.isAll, @"Should not be called by all Accounts");
    
    return [self.allsMails objectAtIndex:index];
}

-(NSMutableArray*) getConversationsForFolder:(CCMFolderType)type
{
    DDLogInfo(@">>ENTERED getConversationsForFolder");
    
    DDAssert(!self.user.isAll, @"Should not be called by all Accounts");
    
    NSMutableIndexSet* set = [[self _mailIndeciesForFolder:type] mutableCopy];
    
    NSMutableArray* res = [NSMutableArray arrayWithCapacity:[set count]];
    CCMMutableConversationArray* _aMS = [self.allsMails mutableCopy];
    
    [_aMS enumerateObjectsAtIndexes:set
                            options:0
                         usingBlock:^(Conversation* obj, NSUInteger idx, BOOL* stop){
                             [res addObject:[ConversationIndex initWithIndex:idx user:self.user]];
                         }];
    
    
    return res;
    
}

#pragma mark - Sending Draft to PersonIDs

-(void) sendDraft:(Draft*)draft to:(NSArray *)toPersonIDs
{
    DDAssert(!self.user.isAll, @"Should not be called by \"all\" Account");
    
    DDLogInfo(@"Sending Draft to %lu Persons",(unsigned long)toPersonIDs.count);
    
    MCOMailProvider* accountProvider = [[MCOMailProvidersManager sharedManager] providerForIdentifier:self.user.identifier];
    
    NSInteger smtpServicesCount = accountProvider.smtpServices.count;
    DDAssert(smtpServicesCount>0, @"At least one SMTP service must exist");
    
    MCONetService* smtpService = accountProvider.smtpServices.firstObject;
    
    MCOSMTPSession* smtpSession = [[MCOSMTPSession alloc] init];
    smtpSession.hostname = smtpService.hostname ;
    smtpSession.port     = smtpService.port;
    smtpSession.username = self.user.username;
    
    if (self.user.isUsingOAuth) {
        smtpSession.OAuth2Token    = self.user.oAuth;
        smtpSession.authType       = MCOAuthTypeXOAuth2;
        smtpSession.connectionType = MCOConnectionTypeStartTLS;
    }
    else {
        smtpSession.password       = self.user.password;
        smtpSession.connectionType = smtpService.connectionType;
    }
    
    DDLogInfo(@"Send Draft with Host=\"%@\" Port:%u Auth Type:%ld", smtpSession.hostname, smtpSession.port, (long)MCOAuthTypeSASLNone);
    //[CCMStatus showStatus:NSLocalizedString(@"status-bar-message.sending-email", @"Sending email...") dismissAfter:2 code:0];
    
    UserSettings* user = [AppSettings userWithNum:draft.accountNum];
    
    NSMutableArray<MCOAddress *> * to = [[NSMutableArray alloc] init];
    
    // Create an array of MCOAddress's to send the Draft to
    for (NSNumber* personID in toPersonIDs) {
        Person* p = [[Persons sharedInstance] getPersonWithID:[personID intValue]];
        MCOAddress* newAddress = [MCOAddress addressWithMailbox:p.email];
        [to addObject:newAddress];
    }
    
    NSString* rfc822DataFilename = [draft rfc822DataTo:toPersonIDs];
    
    MCOAddress *addressWithDispName = [MCOAddress addressWithDisplayName:[user name] mailbox:[user username]];
    
    MCOSMTPSendOperation * op =
    [smtpSession sendOperationWithContentsOfFile:rfc822DataFilename
                                            from:addressWithDispName
                                      recipients:to];
    
    op.progress = ^(unsigned int current, unsigned int maximum){
        [self._getInVC setSGProgressPercentage:(MAX(10 ,(long)(current*100)/maximum))
                                  andTintColor:self.user.color];
    };
    
    self.isSendingOut++;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        [self beginBackgroundUpdateTask];
        
        [op start:^(NSError* error) {
            
            if (error) {
                if (error.code == MCOErrorNeedsConnectToWebmail) {
                    [self _authorizeWebmail];
                }
                
                DDLogError(@"%@ Error sending email:%@", self.user.username, error);
                
                if ( smtpServicesCount == 2) {
                    
                    [self._getInVC setSGProgressPercentage:50 andTintColor:self.user.color];

                    [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.sending-email", @"Sending email...") dismissAfter:2 code:0];
                    
                    MCOSMTPSession* smtpSessionAux = [[MCOSMTPSession alloc] init];
                    
                    MCONetService* serviceAux = accountProvider.smtpServices[1];
                    smtpSessionAux.hostname = serviceAux.hostname ;
                    smtpSessionAux.port = serviceAux.port;
                    smtpSessionAux.connectionType = serviceAux.connectionType;
                    smtpSessionAux.username = self.user.username;
                    smtpSessionAux.password = self.user.password;
                    
                    DDLogInfo(@"Sending with:%@ port:%u authType:%ld", smtpSessionAux.hostname, smtpSessionAux.port, (long)MCOAuthTypeSASLNone);
                    
                    MCOAddress *addr = [MCOAddress addressWithDisplayName:[user name] mailbox:[user username]];
                    MCOSMTPSendOperation * op =
                    [smtpSession sendOperationWithContentsOfFile:rfc822DataFilename
                                                            from:addr
                                                      recipients:to];
                    
                    op.progress = ^(unsigned int current, unsigned int maximum){
                        
                        [self._getInVC setSGProgressPercentage:(MAX(10 ,(long)(current*100)/maximum))
                                         andTintColor:self.user.color];
                    };
                    
                    [op start:^(NSError* error) {
                        if (error) {
                            if (error.code == MCOErrorNeedsConnectToWebmail) {
                                [self _authorizeWebmail];
                            }
                            
                            [self._getInVC finishSGProgress];
                            DDLogError(@"%@ Error sending email:%@", self.user.username, error);
                            
                            [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.error-sending", @"Error: Email not sent.") dismissAfter:2 code:2];
                            self.isSendingOut--;
                            [self endBackgroundUpdateTask];
                        }
                        else {
                            [self._getInVC finishSGProgress];
                            DDLogInfo(@"%@ Successfully sent email!", self.user.username);
                            [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.email-sent", @"Email sent.") dismissAfter:2 code:1];
                            [draft deleteOutboxDraft];
                            [draft appendToSent:rfc822DataFilename];
                            self.isSendingOut--;
                            [self endBackgroundUpdateTask];
                        }
                    }];
                }
                else {
                    [self._getInVC finishSGProgress];
                    [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.error-sending", @"Error: Email not sent.") dismissAfter:2 code:2];
                    self.isSendingOut--;
                    [self endBackgroundUpdateTask];
                }
            }
            else {
                [self._getInVC finishSGProgress];
                DDLogInfo(@"%@: Successfully sent email", self.user.username);
                [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.email-sent", @"Email sent.")  dismissAfter:2 code:1];
                [draft deleteOutboxDraft];
                [draft appendToSent:rfc822DataFilename];
                self.isSendingOut--;
                [self endBackgroundUpdateTask];
            }
        }];
    });
}

-(InViewController*)_getInVC
{
    // TODO: If this can be proven not to change, then set it once and store it
    return (InViewController*)[[ViewController mainVC] topIVC];
}

-(void)_authorizeWebmail
{
    NSString *authNeededMsg = NSLocalizedString(@"Authorization in webmail needed", @"Authorization in webmail needed");
    UIAlertController* ac =
    [UIAlertController alertControllerWithTitle:nil
                                        message:authNeededMsg
                                 preferredStyle:UIAlertControllerStyleAlert];
    
    NSString *titleText = NSLocalizedString(@"Ok", @"Ok");
    UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:titleText
                                                           style:UIAlertActionStyleDefault
                                                         handler:nil];
    [ac addAction:cancelAction];
    
    ViewController* vc = [ViewController mainVC];
    
    [vc presentViewController:ac animated:YES completion:nil];
}
- (void) beginBackgroundUpdateTask
{
    _backgroundUpdateTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        [self endBackgroundUpdateTask];
    }];
}

- (void) endBackgroundUpdateTask
{
    [[UIApplication sharedApplication] endBackgroundTask: _backgroundUpdateTask];
    _backgroundUpdateTask = UIBackgroundTaskInvalid;
}

-(void) deleteDraft:(Draft*)draft
{
    Mail* m = [Mail mailWithDraft:draft];

    Conversation* conversation = [[Conversation alloc]init];
    [conversation addMail:m];
    
    CCMFolderType folderFrom = CCMFolderTypeDrafts;
    CCMFolderType folderTo   = CCMFolderTypeDeleted;
    
    [self moveConversation:conversation from:folderFrom to:folderTo updateUI:YES];
}

// TODO: This should be +[Folder folderFileFolder] (or such)
-(NSString *)_outboxFolderPath
{
    NSString *outboxPath = NSLocalizedString(@"outbox", @"outbox");
    NSString *documentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString* outboxFolder = [documentsDirectory stringByAppendingPathComponent:outboxPath];
    
    NSFileManager *filemgr = [NSFileManager defaultManager];

    // If the Outbox Folder does not exist then create it
    if (![filemgr fileExistsAtPath:outboxFolder]) {
        
        [filemgr createDirectoryAtPath:outboxFolder
           withIntermediateDirectories:NO
                            attributes:nil
                                 error:nil];
        
        DDLogInfo(@"Created \"%@\"",outboxFolder);
    }
    return outboxFolder;
}

-(void) sendOutboxs
{
    DDLogInfo(@"ENTERED sendOutboxs");
    
    if (self.isSendingOut == 0) {
        
        DDLogInfo(@"isSendingOut EQUALS 0");
        
        NSString *outboxFolder = [self _outboxFolderPath];  // creates if not found
        
        NSFileManager *filemgr = [NSFileManager defaultManager];
        NSArray<NSString *> *outboxFilenames = [filemgr contentsOfDirectoryAtPath:outboxFolder
                                                                     error:nil];
        
        for (NSString* fileName in outboxFilenames) {
            
            NSString* localPath = [outboxFolder stringByAppendingPathComponent:fileName];
            Draft* draft = [NSKeyedUnarchiver unarchiveObjectWithFile:localPath];
            
            // TODO: msgID is an NSString, therefore does !msgID mean if its NULL?
            if (!draft.msgID) {
                draft.msgID = @"0";
            }
            
            DDLogInfo(@"Sending Draft to %lu Persons",(unsigned long)draft.toPersons.count);
            
            if (draft.toPersons.count == 0) {
                [draft deleteOutboxDraft];
                [draft saveToDraftsFolder];
                continue;
            }
            
            if (draft.accountNum == self.user.accountNum) {
                NSMutableArray* toPIDs = [[NSMutableArray alloc] initWithCapacity:draft.toPersons.count];
                Persons* ps = [Persons sharedInstance];
                for (NSString* email in draft.toPersons) {
                    [toPIDs addObject:@([ps indexForEmail:email])];
                }
                
                [self sendDraft:draft to:toPIDs];
            } else {
                DDLogWarn(@"Draft Acnt # %lu DOES NOT EQUAL User Acnt # %lu",
                             draft.accountNum,self.user.accountNum);
            }
        }
    }
    else {
        DDLogInfo(@"isSendingOut DOES NOT EQUAL 0");
    }
}

-(NSInteger) outBoxNb
{
    NSFileManager *filemgr = [NSFileManager defaultManager];
    NSString *outboxPath   = [self _outboxFolderPath]; // creates if not found
    NSArray *dirFiles      = [filemgr contentsOfDirectoryAtPath:outboxPath error:nil];
    
    NSInteger count = 0;
    
    for (NSString* fileName in dirFiles) {
        NSString* localPath = [outboxPath stringByAppendingPathComponent:fileName];
        
        // TODO: We unarchive the entire file to get one value - can we get just the value?  Perhaps if we added it to the Draft Archive Name??
        Draft* draft = [NSKeyedUnarchiver unarchiveObjectWithFile:localPath];
        
        if (draft.accountNum == self.user.accountNum) {
            count++;
        }
    }
    
    return count;
}

#pragma mark - Move Indexed Conversation from Folder to Folder

-(BOOL) moveConversationAtIndex:(NSInteger)index from:(CCMFolderType)folderFrom to:(CCMFolderType)folderTo updateUI:(BOOL)updateUI
{
    DDLogInfo(@"%@ Main Thread",([NSThread isMainThread]?@"Is":@"Isn't"));
    
    DDAssert(!self.user.isAll, @"Should not be called by all Accounts");
    
    Conversation *conv = [self.allsMails objectAtIndex:index];
    return [self moveConversation:conv from:folderFrom to:folderTo updateUI:updateUI];
}

#pragma mark - Move Conversation from Folder to Folder

-(BOOL) moveConversation:(Conversation*)conversation from:(CCMFolderType)folderFrom to:(CCMFolderType)folderTo updateUI:(BOOL)updateUI
{
    DDLogInfo(@"%@ Main Thread",([NSThread isMainThread]?@"Is":@"Isn't"));
    
    // Cannot move a converstaion from the All Mails folder
    DDAssert(!self.user.isAll, @"Should not be called by all Accounts");
    
    CCMMutableConversationArray* tmp = [self.allsMails mutableCopy];
    NSUInteger idx = [tmp indexOfObject:conversation];
    
    if (idx == NSNotFound) {
        DDLogError(@"Conversation with subject \"%@\" not found.",
                   [conversation firstMail].subject);
        return FALSE;
    }
   
    NSMutableIndexSet* toFolderMailIndecies = [self _mailIndeciesForFolder:folderTo];
    
#warning This seems kludgy.  This kind of knowledge might be better kept in a Type object
    // Re above warning - structure with type could include CanMoveFrom and CanMoveTo BOOLs
    
    switch (folderTo.type) {
        case FolderTypeInbox:
        case FolderTypeAll:
        case FolderTypeDeleted:
        case FolderTypeSpam:
        case FolderTypeUser:
            break;
        default:
            DDLogError(@"Move to folder type %ld not implemented.",(long)folderTo.type);
            
            return NO;
    }
    
    NSMutableIndexSet* fromFolderMailIndecies = [self _mailIndeciesForFolder:folderFrom];
    
    BOOL okayToRemoveFromFolder = NO;
    
    switch (folderFrom.type) {
        case FolderTypeInbox:
        case FolderTypeUser:
        case FolderTypeDrafts:
            okayToRemoveFromFolder = YES;
            break;
            
        case FolderTypeFavoris:
        case FolderTypeAll:
            okayToRemoveFromFolder = (folderTo.type == FolderTypeDeleted || folderTo.type == FolderTypeSpam);
            break;
        case FolderTypeDeleted:
        case FolderTypeSpam:
            okayToRemoveFromFolder = (folderTo.type != FolderTypeDeleted && folderTo.type != FolderTypeSpam);
            break;
        case FolderTypeSent:
            okayToRemoveFromFolder = (folderTo.type == FolderTypeDeleted);
            break;
        default:
            DDLogError(@"move from this folder not implemented (From Folder Type = %ld)",folderFrom.type);
            
            return NO;
    }
    
    /*if (folderFrom.type == FolderTypeDrafts && [[conversation firstMail].email.msgID integerValue] <= 0) {
     [self deleteDraft:[conversation firstMail]];
     
     return YES;
     }*/
    
    if (folderTo.type == FolderTypeDeleted) {
        [conversation trash];
    }
    else {
        [conversation moveFromFolder:[self.user numFolderWithFolder:folderFrom]
                            ToFolder:[self.user numFolderWithFolder:folderTo]];
    }
    
    if (okayToRemoveFromFolder) {
        [fromFolderMailIndecies removeIndex:idx];
        
//#warning setTest not used!?!
//        
//        NSMutableIndexSet* setTest = nil;
//        
//        if (folderFrom.type == FolderTypeUser) {
//            setTest = self.userFoldersContent[folderFrom.idx];
//        }
//        else {
//            setTest = self.systemFoldersContent[folderFrom.type];
//        }
        
        BOOL fromFolderIsCurrentFolder = ( encodeFolderTypeWith(folderFrom) == encodeFolderTypeWith(self.currentFolderType) );
        
        if (updateUI && fromFolderIsCurrentFolder) {
            [self.mailListSubscriber removeConversationList:@[[ConversationIndex initWithIndex:idx user:self.user]]];
        }
    }
    else {
        //[CCMStatus showStatus:NSLocalizedString(@"status-bar-message.done", @"Done")  dismissAfter:2];
    }
    
    [toFolderMailIndecies addIndex:idx];
    
    return okayToRemoveFromFolder;
}

#pragma mark - Flag a Conversation

-(void) star:(BOOL)add conversation:(Conversation*)conversation
{
    DDLogInfo(@"%@ Main Thread",([NSThread isMainThread]?@"Is":@"Isn't"));
    
    DDAssert(!self.user.isAll, @"Should not be called by all Accounts");
    
//    NSMutableArray* tmp = [self.allsMails mutableCopy];
    NSUInteger idx = [self.allsMails indexOfObject:conversation];
    
    NSMutableIndexSet* favorisFolderMailIndecies = self.systemFoldersContent[FolderTypeFavoris];
    
    if (!add) {
        [favorisFolderMailIndecies removeIndex:idx];
    }
    else {
        [favorisFolderMailIndecies addIndex:idx];
    }
}

#pragma mark - Folder Badges

-(NSInteger) unreadInInbox
{
    NSInteger count = 0;
    
    if (!self.user.isAll) {
        count = [AppSettings inboxUnread:self.idx];
    }
    else {
        for (Account* a in [Accounts sharedInstance].accounts) {
            if (!a.user.isAll) {
                count += [AppSettings inboxUnread:a.idx];
            }
        }
    }
    
    return count;
}

-(NSInteger) favorisCount
{
    NSInteger count = 0;
    
    if (!self.user.isAll) {
        if ([self.user numFolderWithFolder:CCMFolderTypeFavoris] != [self.user numFolderWithFolder:CCMFolderTypeAll]) {
            count = [[[SyncManager getSingleton] retrieveState:[self.user numFolderWithFolder:CCMFolderTypeFavoris] accountNum:self.user.accountNum][@"emailCount"] integerValue];
        }
        else {
            count = [self getConversationsForFolder:CCMFolderTypeFavoris].count;
        }
    }
    else {
        for (Account* a in [Accounts sharedInstance].accounts) {
            if (!a.user.isAll) {
                if ([self.user numFolderWithFolder:CCMFolderTypeFavoris] != [self.user numFolderWithFolder:CCMFolderTypeAll]) {
                    count += [[[SyncManager getSingleton] retrieveState:[self.user numFolderWithFolder:CCMFolderTypeFavoris] accountNum:a.user.accountNum][@"emailCount"] integerValue];
                }
                else {
                    count += [a getConversationsForFolder:CCMFolderTypeFavoris].count;
                }
            }
        }
    }
    
    return count;
}

-(NSInteger) draftCount
{
    NSInteger count = 0;
    
    if (!self.user.isAll) {
        count = [[[SyncManager getSingleton] retrieveState:[self.user numFolderWithFolder:CCMFolderTypeDrafts] accountNum:self.user.accountNum][@"emailCount"] integerValue];
    }
    else {
        for (Account* a in [Accounts sharedInstance].accounts) {
            if (!a.user.isAll) {
                NSInteger Acount =  [[[SyncManager getSingleton] retrieveState:[a.user numFolderWithFolder:CCMFolderTypeDrafts] accountNum:a.user.accountNum][@"emailCount"] integerValue];
                count = count + Acount;
            }
        }
    }
    
    return count;
}

#pragma mark - Fetch Data

// Refresh contents of IMAP System Folders 
-(void) importantFoldersRefresh:(NSInteger)pFolder
{
    DDLogInfo(@">> ENTERING importantFolderRefresh:folder=%ld",(long)pFolder);
    
    if (self.user.isDeleted) {
        return;
    }
    
    if (![ImapSync canFullSync]){
        return;
    }
    
    NSInteger __block folder = pFolder;
    
    //If last important folder start full sync
    if (folder > 4) {
        [self doLoadServer];
        return;
    }
    
    if (!_isSyncing && !_isSyncingCurrentFolder) {
        _isSyncing = YES;
        
        [[[SyncManager getSingleton] refreshImportantFolder:folder user:self.user]
         subscribeNext:^(Mail* email) {
             [self insertRows:email];
         }
         error:^(NSError* error) {
             
             if (error.code != CCMFolderSyncedError && error.code != CCMAllSyncedError) {
                 [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.connecting_error", @"Connection error") dismissAfter:2 code:2];
             }
             
             _isSyncing = NO;
             
             if (error.code == CCMFolderSyncedError && [Accounts sharedInstance].currentAccountIdx == self.idx) {
                 [self importantFoldersRefresh:++folder];
             }
         }
         completed:^{
             _isSyncing = NO;
             if ([Accounts sharedInstance].currentAccountIdx == self.idx) {
                 [self importantFoldersRefresh:++folder];
             }
         }];
    }
}

-(void) doLoadServer
{
    DDLogInfo(@">> ENTERING doLoadServer");
    
    if ( self.user.isDeleted ) {
        DDLogDebug(@"\tdoLoadServer: User-is-deleted, returning.");
        return;
    }
    
    if ( ![ImapSync canFullSync] ){
        DDLogDebug(@"\tdoLoadServer: Cannot Full Sync, returning.");
        return;
    }
    
    if (!_isSyncing && !_isSyncingCurrentFolder) {
        DDLogDebug(@"\tNOT syncing AND NOT syncing current folder");
        _isSyncing = YES;
        [[[[SyncManager getSingleton] syncFoldersUser:self.user] deliverOn:[RACScheduler scheduler]]
         subscribeNext:^(Mail* email) {
             //[self insertRows:email];
             DDLogDebug(@"\tsubscribeNext^(email)");
         }
         error:^(NSError* error) {
             _isSyncing = NO;
             
             DDLogDebug(@"\tError: %@",error);
             
//             if (error.code != CCMFolderSyncedError && error.code != CCMAllSyncedError) {
//                 DDLogError(@"\tSyncing error, error = %@",error);
//             }
             
             if ([Accounts sharedInstance].currentAccountIdx == self.idx) {
                 if (error.code == CCMAllSyncedError) {
                     DDLogDebug(@"\tError code CCMAllSyncedError");
                 }
                 else if (error.code == CCMFolderSyncedError) {
                     DDLogDebug(@"\tError code 9002, calling self recursively");
                     [self doLoadServer];;
                 }
             }
         }
         completed:^{
             DDLogDebug(@"\tSyncing completed.");
             _isSyncing = NO;
             if ([Accounts sharedInstance].currentAccountIdx == self.idx) {
                 DDLogDebug(@"\tCalling self recursively");
                 [self doLoadServer];
             }
         }];
    }
}

-(void) runTestData
{
    DDLogInfo(@">> ENTERING runTestData");
    
    if (self.user.isDeleted) {
        return;
    }
    
    if (!self.user.isAll && self.allsMails.count != 0 && !_runningUpToDateTest) {
        _runningUpToDateTest = YES;

        NSMutableIndexSet* currentFolderMailIndecies =
            [[self _mailIndeciesForFolder:self.currentFolderType] mutableCopy];
        
        NSMutableIndexSet* setAll = [self.systemFoldersContent[FolderTypeAll] mutableCopy];
        NSMutableArray* resAll = [NSMutableArray arrayWithCapacity:[setAll count]];
        NSMutableArray* res = [NSMutableArray arrayWithCapacity:[currentFolderMailIndecies count]];
        
        NSArray* _aMS = [self.allsMails mutableCopy];
        
        [_aMS enumerateObjectsAtIndexes:currentFolderMailIndecies
                                options:0
                             usingBlock:^(id obj, NSUInteger idx, BOOL* stop){
                                 [res addObject:obj];
                             }];
        
        [[ImapSync sharedServices:self.user] runUpToDateTest:res folderIndex:self.currentFolderIdx completed:^(NSArray *dels, NSArray *ups, NSArray* days) {
            //[self.mailListSubscriber removeConversationList:nil];
            
            [self.mailListSubscriber updateDays:days];
            
            if (self.currentFolderType.type != FolderTypeAll) {
                [_aMS enumerateObjectsAtIndexes:setAll
                                        options:0
                                     usingBlock:^(id obj, NSUInteger idx, BOOL* stop){
                                         [resAll addObject:obj];
                                     }];
                
                if (![ImapSync canFullSync]){
                    _runningUpToDateTest = NO;
                    return;
                }
                
                [[ImapSync sharedServices:self.user] runUpToDateTest:resAll folderIndex:[self.user numFolderWithFolder:CCMFolderTypeAll] completed:^(NSArray *dels, NSArray *ups, NSArray* days) {
                    _runningUpToDateTest = NO;
                    
                    [self.mailListSubscriber updateDays:days];

                    //[self.mailListSubscriber removeConversationList:nil];
                }];
            }
            
        }];
    }
}

-(void) runMoreTestData
{
    if (self.user.isDeleted) {
        return;
    }
    
    if (!self.user.isAll && self.allsMails.count != 0) {
        
        NSMutableIndexSet* currentFolderMailIndecies =
            [[self _mailIndeciesForFolder:self.currentFolderType] mutableCopy];
        
        NSMutableArray* res = [NSMutableArray arrayWithCapacity:[currentFolderMailIndecies count]];
        
        NSArray* _aMS = [self.allsMails mutableCopy];
        
        [_aMS enumerateObjectsAtIndexes:currentFolderMailIndecies
                                options:0
                             usingBlock:^(id obj, NSUInteger idx, BOOL* stop){
                                 [res addObject:obj];
                             }];
        
        [[ImapSync sharedServices:self.user] runUpToDateTest:res folderIndex:self.currentFolderIdx completed:^(NSArray *dels, NSArray *ups, NSArray* days) {
            [self.mailListSubscriber updateDays:days];
            //[self localFetchMore:NO];
        }];
    }
}

-(void) deliverUpdate:(NSArray <Mail*>*)emails
{
    if (self.user.isDeleted) {
        return;
    }
    
    for (Mail* email in emails) {
        BOOL found = NO;
        
        for (Conversation* conv in self.allsMails) {
            for (Mail* m in conv.mails) {
                if ([m.msgID isEqualToString:email.msgID]) {
                    
                    m.flag = email.flag;
                    
                    found = YES;
                    break;
                }
            }
            
            if (found) {
                break;
            }
        }
        
        if (!found) {
            DDLogError(@"Error Conversation to delete not found");
        }
    }
}

-(void) deliverDelete:(NSArray*)emails fromFolder:(CCMFolderType)folderFrom
{
    if (self.user.isDeleted) {
        return;
    }
    
    NSMutableArray* idxs = [[NSMutableArray alloc]initWithCapacity:emails.count];
 
    NSMutableIndexSet* fromFolderMailIndecies = [self _mailIndeciesForFolder:folderFrom];
    
    for (Mail* email in emails) {
        BOOL found = NO;
        NSInteger index = 0;
        
        for (; !found && index < self.allsMails.count; index++) {
            for (Mail* m in ((Conversation* )self.allsMails[index]).mails) {
                if ([m.msgID isEqualToString:email.msgID]) {
                    found = YES;
                    break;
                }
            }
        }
        
        index--;
        
        if (!found) {
            DDLogError(@"Error Conversation to delete not found");
        }
        else {
            if ([fromFolderMailIndecies containsIndex:index]) {
                [idxs addObject:[ConversationIndex initWithIndex:index user:self.user]];
                [fromFolderMailIndecies removeIndex:index];
            }
        }
    }
    
    [self.mailListSubscriber removeConversationList:idxs];
}


-(BOOL) deleteIndex:(NSInteger)index fromFolder:(CCMFolderType)folderFrom
{
    if (self.user.isDeleted) {
        return NO;
    }
    
    NSMutableIndexSet* currentFolderMailIndecies =
        [self _mailIndeciesForFolder:self.currentFolderType];
    
    if ([currentFolderMailIndecies containsIndex:index]) {
        DDLogError(@"Index %ld was still in set",(long)index);
        [currentFolderMailIndecies removeIndex:index];
        return YES;
    }
    
    return NO;
}

-(void) doPersonSearch:(Person*)person
{
    if (self.user.isDeleted) {
        return;
    }
    
    //NSInteger refBatch = 5;
    //NSInteger __block batch = refBatch;
    
    [self.mailListSubscriber localSearchDone:NO];
    [self.mailListSubscriber serverSearchDone:NO];
    
    //LocalSearch
    [_localFetchQueue addOperationWithBlock:^{
        [[[SearchRunner getSingleton] senderSearch:person inAccountNum:self.user.accountNum]
         subscribeNext:^(Mail* email) {
             [self insertRows:email];
             //if (batch-- == 0) {
             //    batch = refBatch;
            //[self.mailListSubscriber reFetch:YES];
             //}
         }
         completed:^{
                 //[self.mailListSubscriber reFetch:YES];
                 [self.mailListSubscriber localSearchDone:YES];
         }];
    }];
    
    //ServerSearch
    [[[[SyncManager getSingleton] searchPerson:person user:self.user] deliverOn:[RACScheduler mainThreadScheduler]]
     subscribeNext:^(Mail* email) {
         [self insertRows:email];
         //if (batch-- == 0) {
         //    batch = refBatch;
        //[self.mailListSubscriber reFetch:YES];
         //}
     }
     error:^(NSError* error) {
         DDLogError(@"Error: %@", error.localizedDescription);
            [self.mailListSubscriber reFetch:YES];
     }
     completed:^{
             [self.mailListSubscriber reFetch:YES];
             [self.mailListSubscriber serverSearchDone:YES];
     }];
}

-(void) doTextSearch:(NSString*)searchString
{
    if (self.user.isDeleted) {
        return;
    }
    
    //NSInteger refBatch = 5;
    //NSInteger __block batch = refBatch;
    
    [self.mailListSubscriber localSearchDone:NO];
    [self.mailListSubscriber serverSearchDone:NO];
    
    
    //LocalSearch
    [_localFetchQueue addOperationWithBlock:^{
        [[[SearchRunner getSingleton] search:searchString inAccountNum:self.user.accountNum]
         subscribeNext:^(Mail* email) {
             [self insertRows:email];
             //if (batch-- == 0) {
             //    batch = refBatch;
                     //[self.mailListSubscriber reFetch:YES];
             //}
         }
         completed:^{
                 [self.mailListSubscriber reFetch:YES];
                 [self.mailListSubscriber serverSearchDone:YES];
         }];
    }];
    
    //ServerSearch
    [[[[SyncManager getSingleton] searchText:searchString user:self.user] deliverOn:[RACScheduler mainThreadScheduler]]
     subscribeNext:^(Mail* email) {
         [self insertRows:email];
     }
     error:^(NSError* error) {
         DDLogError(@"Error: %@", error.localizedDescription);
             [self.mailListSubscriber reFetch:YES];
     }
     completed:^{
             [self.mailListSubscriber reFetch:YES];
             [self.mailListSubscriber serverSearchDone:YES];
     }];
}

-(void) localFetchMore:(BOOL)loadMore
{
    DDLogDebug(@"-[Accounts localFetchMore:%@]",(loadMore?@"TRUE":@"FALSE"));
    
    if (self.user.isAll) {
        for (Account* a in [Accounts sharedInstance].accounts) {
            if (!self.user.isAll) {
                [a localFetchMore:loadMore];
            }
        }
        return;
    }
    
    if (self.user.isDeleted) {
        return;
    }
    
    if (!_isLoadingMore && !_hasLoadedAllLocal) {
        _isLoadingMore = YES;
        
        [self.mailListSubscriber localSearchDone:NO];
        
        BOOL __block more = NO;
        
        DDLogDebug(@"Local search");
        
        [_localFetchQueue addOperationWithBlock:^{
            [[[SearchRunner getSingleton] activeFolderSearch:loadMore?_lastEmails[self.currentFolderIdx]:nil inAccountNum:self.user.accountNum]
             subscribeNext:^(Mail* email) {
                 more = YES;
                 
                 if (email.user && !email.user.isDeleted) {
                     [email.user.linkedAccount insertRows:email];
                 }
                 
                 _lastEmails[self.currentFolderIdx] = email;
             }
             completed:^{
                 _isLoadingMore = NO;
                 
                 DDLogDebug(@"Local search done. Found emails? %@", more?@"YES":@"NO");
                 
                 if (!more) {
                     _hasLoadedAllLocal = YES;
                 }
                 
                 [self runTestData];
                 
                 [self.mailListSubscriber localSearchDone:YES];
                 [self.mailListSubscriber reFetch:YES];
             }];
        }];
    }
}

-(void) refreshCurrentFolder
{
    DDLogInfo(@"-[Accounts refreshCurrentFolder]");
    
    if (self.user.isAll) {
        for (Account* a in [[Accounts sharedInstance] accounts]) {
            if (!a.user.isAll) {
                [a refreshCurrentFolder];
            }
        }
    }
    else {
        
        if (self.user.isDeleted) {
            return;
        }
        
        if ([ImapSync sharedServices:self.user].connected) {
            NSInteger __block new = 0;
            
            [self.mailListSubscriber serverSearchDone:NO];
            
            [self runTestData];
            
            DDLogInfo(@"\tRefresh");
            
            [[[[SyncManager getSingleton] syncActiveFolderFromStart:YES user:self.user] deliverOn:[RACScheduler schedulerWithPriority:RACSchedulerPriorityBackground]]
             subscribeNext:^(Mail* email) {
                 DDLogInfo(@"\tEmail Refresh");

                 new++;
                 [self insertRows:email];
             } error:^(NSError* error) {
                 
                 DDLogError(@"\tError Refresh");

                 [self.mailListSubscriber serverSearchDone:YES];
                 
                 if (error.code != CCMFolderSyncedError && error.code != CCMAllSyncedError) {
                     [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.connecting_error", @"Connection error") dismissAfter:2 code:2];
                 }
                 else if ([Accounts sharedInstance].currentAccountIdx == self.idx) {
                         
                         [self runTestData];
                         
                         _currentFolderFullSyncCompleted = YES;
                         _isSyncingCurrentFolder = NO;
                         [self importantFoldersRefresh:0];
                 }
             } completed:^{

                 DDLogInfo(@"\tDone Refresh");

                 [self.mailListSubscriber serverSearchDone:YES];
                 
                 if (new != 0) {
                    [self.mailListSubscriber reFetch:YES];
                 }
                 
                 if ([Accounts sharedInstance].currentAccountIdx == self.idx) {
                     [self runTestData];
                     
                     if (_currentFolderFullSyncCompleted) {
                         _isSyncingCurrentFolder = NO;
                         [self importantFoldersRefresh:0];
                     }
                     else if (!_isSyncingCurrentFolder) {
                         _isSyncingCurrentFolder = YES;
                         [self syncCurrentFolder];
                     }
                 }
             }];
        }
        else {
            [self connect];
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [self.mailListSubscriber serverSearchDone:YES];
            }];
        }
    }
}

-(void) syncCurrentFolder
{
    DDLogInfo(@"ENTERING >>syncCurrentFolder");
    
    if (self.user.isDeleted) {
        DDLogWarn(@"Returning because self.user.isDeleted is FALSE");
        return;
    }
    
    if (![ImapSync canFullSync]){
        DDLogWarn(@"Returning because [ImapSync canFullSyc] returned YES and we negated it??");
        return;
    }
    
    [[[[SyncManager getSingleton] syncActiveFolderFromStart:NO user:self.user] deliverOn:[RACScheduler mainThreadScheduler]]
     subscribeNext:^(Mail* email) {
         //[self insertRows:email];
     } error:^(NSError* error) {
         DDLogError(@"Error: %@", error.localizedDescription);
         _isSyncingCurrentFolder = NO;
         if (error.code == CCMFolderSyncedError) {
             _currentFolderFullSyncCompleted = YES;
             [self importantFoldersRefresh:0];
         }
     } completed:^{
         if ([Accounts sharedInstance].currentAccountIdx == self.idx) {
             [self syncCurrentFolder];
         }
     }];
}

#pragma mark - Account description

-(NSString *)description
{
    NSMutableString *desc = [NSMutableString string];
    
    [desc appendString:@"\n --- Begin Account ---\n"];
    
    // Account Index
    [desc appendFormat:@"Account Index = %ld\n",[self idx]];
    [desc appendString:@"\n"];

    // UserSettings
    [desc appendFormat:@"UserSettings: %@",[[self user] description]];
    [desc appendString:@"\n\n"];

    [desc appendString:[self folderSetDescription:@"System" accountFolders:self.systemFoldersContent folderNames:self.systemFolderNames]];
    
    [desc appendString:[self folderSetDescription:@"User" accountFolders:self.userFoldersContent folderNames:self.userFolders]];
    
    [desc appendFormat:@"Current-Folder Index = %ld\n",(long)self.currentFolderIdx];
    [desc appendFormat:@"Current-Folder Type  = %@\n",[self currentFolderTypeValue]];
    [desc appendFormat:@"Is-Sending-Out count = %ld\n",(long)self.isSendingOut];
    [desc appendString:@"\n"];

    [desc appendFormat:@"Person: %@",[[self person] description]];
      
//    @property (nonatomic, weak) id<MailListDelegate> mailListSubscriber;
    
    [desc appendString:@"\n --- End Account ---\n"];
    
    return desc;
}

-(NSString *)folderSetDescription:(NSString *)folderType accountFolders:(NSArray *)folderArray folderNames:(NSArray *)folderNames
{
    NSMutableString *desc = [NSMutableString string];
    
    NSUInteger folderCount = [folderArray count];
    
    [desc appendFormat:@"%@ Folders count = %ld\n",folderType, folderCount];
    
    for (NSUInteger folderIndex = 0; folderIndex < folderCount; folderIndex++) {
        
        NSString *folderName = folderNames[folderIndex];
        
        NSMutableIndexSet *mailIndecies = folderArray[folderIndex];
        
        NSUInteger mailCount = [mailIndecies count];
        
        [desc appendFormat:@"\t%@ Folder[%lu] \"%@\" has %lu mail messages\n",
         folderType,(unsigned long)folderIndex,
         folderName,(unsigned long)mailCount];
    }
    return desc;
}

-(NSString *)currentFolderTypeValue
{
    NSString *currFolderType = @"";
    
    switch (self.currentFolderType.type) {
        case FolderTypeInbox:
            currFolderType = @"INBOX";
            break;
        case FolderTypeFavoris:
            currFolderType = @"Favorite?";
            break;
        case FolderTypeSent:
            currFolderType = @"Sent";
            break;
        case FolderTypeDrafts:
            currFolderType = @"Drafts";
            break;
        case FolderTypeAll:
            currFolderType = @"All";
            break;
        case FolderTypeDeleted:
            currFolderType = @"Deleted";
            break;
        case FolderTypeSpam:
            currFolderType = @"SPAM";
            break;
        default:
            currFolderType = [NSString stringWithFormat:@"Unknown CCMFolderType.type (%ld)",(long)self.currentFolderType.type];
            break;
    }
        return currFolderType;
}
@end
