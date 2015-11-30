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

@interface Accounts()

@property (nonatomic, retain) NSOperationQueue* localFetchQueue;
@property (nonatomic, strong) NSArray* accounts;


@end


@interface Account () {
    BOOL _currentFolderFullSyncCompleted;
    BOOL _connected;
    BOOL _runningUpToDateTest;
}

@property (nonatomic, strong) NSMutableArray* allsMails;
@property (nonatomic, strong) NSMutableSet* convIDs;

@property (nonatomic, strong) NSArray* userFoldersContent;
@property (nonatomic, strong) NSArray* systemFoldersContent;

@end

@implementation Accounts

+(Accounts*) sharedInstance
{
    static dispatch_once_t once;
    static Accounts * sharedInstance;
    
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
        sharedInstance.quickSwipeType = [AppSettings quickSwipe];
        sharedInstance.currentAccountIdx = [AppSettings lastAccountIndex];
        sharedInstance.localFetchQueue = [NSOperationQueue new];
        [sharedInstance.localFetchQueue setMaxConcurrentOperationCount:1];
        
        /*sharedInstance.accountColors = @[[UIColor colorWithRed:0.01f green:0.49f blue:1.f alpha:1.f],
         [UIColor colorWithRed:0.44f green:0.02f blue:1.f alpha:1.f],
         [UIColor colorWithRed:1.f green:0.01f blue:0.87f alpha:1.f],
         [UIColor colorWithRed:1.f green:0.07f blue:0.01f alpha:1.f],
         [UIColor colorWithRed:1.f green:0.49f blue:0.01f alpha:1.f],
         [UIColor colorWithRed:0.96f green:0.72f blue:0.02f alpha:1.f],
         [UIColor colorWithRed:0.07f green:0.71f blue:0.02f alpha:1.f]];*/
        
        NSMutableArray* accounts = [[NSMutableArray alloc]initWithCapacity:[AppSettings numActiveAccounts]];
        
        if ([AppSettings numActiveAccounts] > 0) {
            
            for (int accountIndex = 0; accountIndex < [AppSettings numActiveAccounts]; accountIndex++) {
                //NSInteger accountIndex = [AppSettings numAccountForIndex:i];
                Account* a = [self _createAccountMail:[AppSettings username:accountIndex]
                                                color:[AppSettings color:accountIndex]
                                                 code:[AppSettings initials:accountIndex]
                                                 name:[AppSettings name:accountIndex]
                                                  idx:accountIndex];
                [a initContent];
                [accounts addObject:a];
            }
        }
        
        Account* all = [self _createAllAccountsFrom:accounts];
        [accounts addObject:all];
        
        sharedInstance.accounts = accounts;
        
        [EmailProcessor getSingleton].updateSubscriber = sharedInstance;
        
        if ([AppSettings numActiveAccounts] > 0) {
            [sharedInstance runLoadData];
        }
    });
    
    return sharedInstance;
}

+(Account*) _createAccountMail:(NSString*)mail color:(UIColor*)color code:(NSString*)code name:(NSString*)name idx:(NSInteger)idx
{
    Account* ac = [Account emptyAccount];
    ac.idx = idx;
    
    ac.userMail = mail;
    ac.userColor = color;
    ac.codeName = code;
    
    //ac.currentFolder = FolderTypeWith(FolderTypeInbox,0);
    
    //Folders Indentation?
    NSArray* tmpFolders = [AppSettings allNonImportantFoldersNameforAccountIndex:ac.idx];
    NSMutableArray* foldersNIndent = [[NSMutableArray alloc]initWithCapacity:tmpFolders.count];
    
    for (NSString* folderNames in tmpFolders) {
        [foldersNIndent addObject:@[folderNames, @([folderNames containsString:@"/"])]];
    }
    
    ac.userFolders = foldersNIndent;
    
    ac.person = [Person createWithName:name email:ac.userMail icon:nil codeName:code];
    [ac.person linkToAccount:ac];
    [[Persons sharedInstance] registerPersonWithNegativeID:ac.person];
    
    return ac;
}

+(Account*) _createAllAccountsFrom:(NSArray*)account
{
    Account* ac = [[Account alloc] init];
    ac.userMail = NSLocalizedString(@"All accounts", @"All accounts");
    ac.userColor = [UIColor blackColor];
    ac.isAllAccounts = YES;
    
    NSMutableArray* userfolders = [NSMutableArray arrayWithCapacity:0];
    /*for (Account* a in accounts) {
     [userfolders addObjectsFromArray:a.userFolders];
     }*/
    
    ac.userFolders = userfolders;
    ac.person = [Person createWithName:nil email:nil icon:nil codeName:@"ALL"];
    ac.idx = account.count;
    
    return ac;
}

-(void) runLoadData
{
    [self.localFetchQueue addOperationWithBlock:^{
        [[[SearchRunner getSingleton] allEmailsSearch]
         subscribeNext:^(Email* email) {
             //[[NSOperationQueue mainQueue] addOperationWithBlock:^{
                 //CCMLog(@"Adding email to account:%u",self.idx);
                 if (email.accountNum == 0) {
                     CCMLog(@"Houston on a un probleme avec l'email:%@", email.subject);
                     [Email clean:email];
                 }
                 else {
                     [self.accounts[[AppSettings indexForAccount:email.accountNum]] insertRows:email];
                 }
             //}];
         }
         completed:^{
             [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                 if (self.currentAccount.isAllAccounts) {
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

-(void) deliverUpdate:(NSArray<Email*>*)emails
{
    [self.accounts[[AppSettings indexForAccount:[emails firstObject].accountNum]] deliverUpdate:emails];
}

-(void) deliverDelete:(NSArray<Email*>*)emails
{
    [self.accounts[[AppSettings indexForAccount:[emails firstObject].accountNum]] deliverDelete:emails];
}

-(BOOL) deleteAccount:(Account*)account
{
    NSMutableArray* tmp = [self.accounts mutableCopy];
    NSInteger removeIdx = [tmp indexOfObject:account];
    
    if (removeIdx != NSNotFound) {
        [ImapSync deleted];
        
        [tmp removeObjectAtIndex:removeIdx];
        self.accounts = tmp;
        
        if (self.currentAccountIdx >= removeIdx && self.currentAccountIdx>0) {
            self.currentAccountIdx--;
        }
        
        if (self.defaultAccountIdx >= removeIdx && self.defaultAccountIdx>0) {
            self.defaultAccountIdx--;
        }
        
        return YES;
    }
    
    return NO;
}

-(Account*) getAccount:(NSInteger)accountIndex
{
    if (accountIndex < self.accounts.count) {
        return self.accounts[accountIndex];
    }
    
    NSAssert(accountIndex <= [AppSettings numActiveAccounts], @"accountIdx:%ld is incorrect only %ld active account",(long)accountIndex,(long)[AppSettings numActiveAccounts]);
    
    return nil;
}

-(NSInteger) getPersonID:(NSInteger)accountIndex
{
    Account* ac = self.accounts[accountIndex];
    return [[Persons sharedInstance] indexForPerson:ac.person];
}

-(NSInteger) accountsCount
{
    return self.accounts.count;
}

-(void) addAccount:(Account*)account
{
    [[Persons sharedInstance] registerPersonWithNegativeID:account.person];
    [account.person linkToAccount:account];
    
    NSInteger currentIdx = self.currentAccountIdx;
    NSMutableArray* tmp = [self.accounts mutableCopy];
    NSInteger putIdx = tmp.count - 1;
    
    [tmp insertObject:account atIndex:putIdx];
    self.accounts = tmp;
    
    if (putIdx>=currentIdx) {
        self.currentAccountIdx++;
    }
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
    [AppSettings setDefaultAccountIndex:defaultAccountIdx];
}

-(void) setQuickSwipeType:(QuickSwipeType)quickSwipeType
{
    _quickSwipeType = quickSwipeType;
    [AppSettings setQuickSwipe:quickSwipeType];
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

/*-(NSM*) getAllDrafts
 {
 NSMutableIndexSet* alls = [[NSMutableIndexSet alloc] init];
 
 for (Account* a in self.accounts) {
 if (a.isAllAccounts) {
 continue;
 }
 
 NSIndexSet* drafts = [a getConversationsForFolder:FolderTypeWith(FolderTypeDrafts, 0)];
 [alls addIndexes:drafts];
 
 }
 
 return alls;
 }*/

+(NSArray*) systemFolderIcons
{
    return @[@"inbox_off", @"favoris_off", @"sent_off", @"draft_off", @"all_off", @"delete_off", @"spam_off"];
}

+(NSString*) userFolderIcon
{
    return @"folder_off";
}

-(Conversation*) conversationForCI:(ConversationIndex*)conversationIndex
{
    return [[self.accounts[conversationIndex.account] conversations] objectAtIndex:conversationIndex.index];
}

@end


@interface Account () {
    NSOperationQueue* _localFetchQueue;
    BOOL _isLoadingMore;
    BOOL _hasLoadedAllLocal;
    BOOL _isSyncing;
    BOOL _isSyncingCurrentFolder;
    NSMutableArray* _drafts;
    NSMutableArray* _lastEmails;
}

@end

@implementation Account

+(instancetype) emptyAccount
{
    Account* a = [[Account alloc] init];
    a.allsMails = [NSMutableArray arrayWithCapacity:500];
    a.convIDs = [NSMutableSet setWithCapacity:500];

    return a;
}

-(void) setName:(NSString*)name
{
    self.person.name = name;
    [AppSettings setName:name accountIndex:self.idx];
}

-(NSString*) codeName
{
    return self.person.codeName;
}

-(void) setCodeName:(NSString*)codeName
{
    self.person.codeName = codeName;
    [AppSettings setInitials:codeName accountIndex:self.idx];
}

-(void) initContent
{
    _currentFolderFullSyncCompleted = YES;
    _connected = NO;
    _runningUpToDateTest = NO;
    _drafts = [[NSMutableArray alloc]init];
    
    _localFetchQueue = [NSOperationQueue new];
    [_localFetchQueue setMaxConcurrentOperationCount:1];
    _isLoadingMore = NO;
    _hasLoadedAllLocal = NO;
    _lastEmails = [[NSMutableArray alloc]initWithCapacity:7+self.userFolders.count];
    
    for (int index = 0; index < 7+self.userFolders.count ; index++) {
        [_lastEmails addObject:[[Email alloc]init]];
    }
    
    _isSyncing = NO;
    _isSyncingCurrentFolder = NO;
    
    // create structure
    NSMutableArray* array = [[NSMutableArray alloc] initWithCapacity:7];
    
    for (int i = 0; i < 7; i++) {
        [array addObject:[[NSMutableIndexSet alloc] init]];
    }
    self.systemFoldersContent = array;
    
    const NSInteger limite = self.userFolders.count;
    NSMutableArray* arrayU = [[NSMutableArray alloc] initWithCapacity:limite];
    for (int i = 0; i < limite; i++) {
        [arrayU addObject:[[NSMutableIndexSet alloc] init]];
    }
    self.userFoldersContent = arrayU;
    
    self.currentFolderIdx = [AppSettings importantFolderNumforAccountIndex:self.idx forBaseFolder:FolderTypeInbox];
    //[self connect];
    [self localFetchMore:NO];
}

-(void) connect
{
    if (self.isAllAccounts) {
        for (Account* a in [[Accounts sharedInstance] accounts]) {
            if (!a.isAllAccounts && !a.isConnected) {
                [[ImapSync doLogin:a.idx] subscribeError:^(NSError *error) {
                    CCMLog(@"connection error");
                } completed:^{}];
                
                break;
            }
        }
    }
    else {
    [[ImapSync doLogin:self.idx] subscribeError:^(NSError *error) {
        CCMLog(@"connection error");
    } completed:^{}];
    }
}

-(BOOL) isConnected
{
    return _connected;
}

-(void) setConnected:(BOOL)isConnected
{
    NSAssert(!self.isAllAccounts, @"Should not be called by all Accounts");
    if (kisActiveAccountAll){
        [[Accounts sharedInstance].currentAccount connect];
    }
    
    if (isConnected && !_connected) {
        _connected = isConnected;

        [ImapSync runInboxUnread:self.idx];
        [self refreshCurrentFolder];
    }
    
    _connected = isConnected;
}

-(void) refreshCurrentFolder
{
    NSAssert(!self.isAllAccounts, @"Should not be called by all Accounts");

    if (_connected) {
        NSInteger __block new = 0;
        
        [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.checking-email", @"Checking for new emails")];

        [[[[SyncManager getSingleton] syncActiveFolderFromStart:YES] deliverOn:[RACScheduler mainThreadScheduler]]
         subscribeNext:^(Email* email) {
             new++;
             [self insertRows:email];
         } error:^(NSError* error) {
             CCMLog(@"Error: %@", error.localizedDescription);

             if (error.code == 9001 || error.code == 9002) {
                 
                 if (new == 0) {
                     [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.no-new-emails", @"No new emails")];
                 }
                 else if (new == 1) {
                     [CCMStatus showStatus:[NSString stringWithFormat:NSLocalizedString(@"status-bar-message.one-new-email", @"one new email"),(long)new]];
                 }
                 else {
                     [CCMStatus showStatus:[NSString stringWithFormat:NSLocalizedString(@"status-bar-message.x-new-emails", @"%ld new emails"),(long)new]];
                 }
                 
                 [CCMStatus dismissAfter:2];
                 
                 [self runTestData];
                 
                 _currentFolderFullSyncCompleted = YES;
                 _isSyncingCurrentFolder = NO;
                 [self importantFoldersRefresh:1];
             }
         } completed:^{

             if (new == 0) {
                 [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.no-new-emails", @"No new emails")];
             }
             else {
                 if (new == 1) {
                     [CCMStatus showStatus:[NSString stringWithFormat:NSLocalizedString(@"status-bar-message.one-new-email", @"one new email"),(long)new]];
                 }
                 else {
                     [CCMStatus showStatus:[NSString stringWithFormat:NSLocalizedString(@"status-bar-message.x-new-emails", @"%ld new emails"),(long)new]];
                 }
                 
                 [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                     [self.mailListSubscriber reFetch];
                 }];
             }
             
             [CCMStatus dismissAfter:2];
             
             if ([Accounts sharedInstance].currentAccountIdx == self.idx) {
                 [self runTestData];
                 
                 if (_currentFolderFullSyncCompleted) {
                     _isSyncingCurrentFolder = NO;
                     [self importantFoldersRefresh:1];
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
    }
}

-(void) syncCurrentFolder
{
    NSAssert(!self.isAllAccounts, @"Should not be called by all Accounts");

    [[[[SyncManager getSingleton] syncActiveFolderFromStart:NO] deliverOn:[RACScheduler mainThreadScheduler]]
     subscribeNext:^(Email* email) {
         //[self insertRows:email];
     } error:^(NSError* error) {
         CCMLog(@"Error: %@", error.localizedDescription);
         _isSyncingCurrentFolder = NO;
         if (error.code == 9002) {
             _currentFolderFullSyncCompleted = YES;
             [self importantFoldersRefresh:1];
         }
     } completed:^{
         if ([Accounts sharedInstance].currentAccountIdx == self.idx) {
             [self syncCurrentFolder];
         }
     }];
}

-(void) releaseContent
{
    //TODO:If memory issues
    //self.allsMails = nil;
    //self.userFoldersContent = nil;
    //self.systemFoldersContent = nil;
    // let the drafts
}

-(void) _addCon:(NSUInteger)idx toFoldersContent:(NSSet*)folders
{
    NSAssert(!self.isAllAccounts, @"Should not be called by all Accounts");

    for (NSNumber* Fuser in folders) {
        [self _addIdx:idx inArray:decodeFolderTypeWith([Fuser integerValue])];
    }
}

-(void) _addIdx:(NSUInteger)idx inArray:(CCMFolderType)type
{
    NSAssert(!self.isAllAccounts, @"Should not be called by all Accounts");

    NSMutableIndexSet* set = nil;
    
    if (type.type == FolderTypeUser) {
        set = self.userFoldersContent[type.idx];
    }
    else {
        set = self.systemFoldersContent[type.type];
    }
    
    if (![set containsIndex:idx]) {
        [set addIndex:idx];
        if (encodeFolderTypeWith(type) == encodeFolderTypeWith(self.currentFolderType)) {
            
            NSMutableDictionary* syncState = [[SyncManager getSingleton] retrieveState:[AppSettings numFolderWithFolder:self.currentFolderType forAccountIndex:self.idx] accountIndex:self.idx];
            NSInteger tmpEmailCount = [syncState[@"emailCount"] integerValue];
            
            if (set.count == 20 || set.count == tmpEmailCount) {
                [self runTestData];
            }
            
            if (set.count == 10 || (tmpEmailCount < 10 && set.count == tmpEmailCount)) {
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    [self.mailListSubscriber reFetch];
                 }];
            }
        }
    }
}

-(NSUInteger) addConversation:(Conversation*)conv
{
    NSAssert(!self.isAllAccounts, @"Should not be called by all Accounts");

    NSMutableArray* tmp = [self.allsMails mutableCopy];
    NSUInteger index = [tmp indexOfObject:conv];
    
    if (index == NSNotFound) {
        [self.allsMails addObject:conv];
        index  = self.allsMails.count - 1;

        if (![conv.foldersType containsObject:numberWithFolderType(FolderTypeDeleted)] && ![conv.foldersType containsObject:numberWithFolderType(FolderTypeSpam)] && ![conv.foldersType containsObject:numberWithFolderType(FolderTypeDrafts)]) {
            [self _addIdx:index inArray:FolderTypeWith(FolderTypeAll, 0)];
        }
        
        if ([conv isFav]) {
            [self _addIdx:index inArray:FolderTypeWith(FolderTypeFavoris, 0)];
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

-(NSArray*) conversations
{
    return self.allsMails;
}

-(Conversation*) getConversationForIndex:(NSUInteger)index
{
    NSAssert(!self.isAllAccounts, @"Should not be called by all Accounts");

    return [self.allsMails objectAtIndex:index];
}

-(NSMutableArray*) getConversationsForFolder:(CCMFolderType)type
{
    NSAssert(!self.isAllAccounts, @"Should not be called by all Accounts");

    NSMutableIndexSet* set = nil;
    
    if (type.type == FolderTypeUser) {
        set = [self.userFoldersContent[type.idx] mutableCopy];
    }
    else {
        set = [self.systemFoldersContent[type.type] mutableCopy];
    }
    
    NSMutableArray* res = [NSMutableArray arrayWithCapacity:[set count]];
    NSMutableArray* _aMS = [self.allsMails mutableCopy];
    
    [_aMS enumerateObjectsAtIndexes:set
                                      options:0
                                   usingBlock:^(Conversation* obj, NSUInteger idx, BOOL* stop){
                                       [res addObject:[ConversationIndex initWithIndex:idx Account:self.idx]];
                                   }];
    
    
    return res;
    
}

-(void) sendMail:(Mail*)mail bcc:(BOOL)isBcc
{
    NSAssert(!self.isAllAccounts, @"Should not be called by all Accounts");

    MCOMailProvider* accountProvider = [[MCOMailProvidersManager sharedManager] providerForIdentifier:[AppSettings identifier:self.idx]];
    
    NSArray* smtpServicesArray = accountProvider.smtpServices;
    MCONetService* service = smtpServicesArray[0];
    
    MCOSMTPSession* smtpSession = [[MCOSMTPSession alloc] init];
    smtpSession.hostname = service.hostname ;
    smtpSession.port = service.port;
    smtpSession.username = [AppSettings username:self.idx];
    smtpSession.password = [AppSettings password:self.idx];
    smtpSession.connectionType = service.connectionType;
    
    CCMLog(@"Sending with:%@ port:%u authType:%ld", smtpSession.hostname, smtpSession.port, (long)MCOAuthTypeSASLNone);
    [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.sending-email", @"Sending email...")];
    NSData* rfc822Data = [mail rfc822DataWithAccountIdx:self.idx isBcc:isBcc];
    
    MCOSMTPSendOperation* sendOperation = [smtpSession sendOperationWithData:rfc822Data];
    [sendOperation start:^(NSError* error) {
        
        if (error) {
            CCMLog(@"%@ Error sending email:%@", [AppSettings username:self.idx], error);
            [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.error-sending", @"Error: Email not sent.")];
        }
        else {
            CCMLog(@"%@ Successfully sent email!", [AppSettings username:self.idx]);
            [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.email-sent", @"Email sent.")];
        }
    }];
    
    /*if ([self.drafts containsObject:mail]) {
     [self.drafts removeObject:mail];
     }*/
    
    //NSInteger index = self.allsMails.count;
    
    //Conversation* c = [[Conversation alloc] init];
    //[c addMail:mail];
    
    //[self.allsMails addObject:c];
    //[self _addIdx:index inArray:FolderTypeWith(FolderTypeSent, 0)];
}

-(void) saveDraft:(Mail*)mail
{
    NSAssert(!self.isAllAccounts, @"Should not be called by all Accounts");

    NSInteger idx = [_drafts indexOfObject:mail];

    if (idx == NSNotFound) {
        [_drafts addObject:mail];
    }
    else {
        _drafts[idx] = mail;
    }
}
 
-(void) deleteDraft:(Mail*)mail
{
    NSAssert(!self.isAllAccounts, @"Should not be called by all Accounts");

    [_drafts removeObject:mail];
}

-(BOOL) moveConversationAtIndex:(NSInteger)index from:(CCMFolderType)folderFrom to:(CCMFolderType)folderTo
{
    NSAssert(!self.isAllAccounts, @"Should not be called by all Accounts");

    return [self moveConversation:[self.allsMails objectAtIndex:index] from:folderFrom to:folderTo];
}

-(BOOL) moveConversation:(Conversation*)conversation from:(CCMFolderType)folderFrom to:(CCMFolderType)folderTo
{
    NSAssert(!self.isAllAccounts, @"Should not be called by all Accounts");

    NSMutableArray* tmp = [self.allsMails mutableCopy];
    NSUInteger idx = [tmp indexOfObject:conversation];
    
    if (idx == NSNotFound) {
        CCMLog(@"Conversation:%@ not found",[conversation firstMail].title);
        return FALSE;
    }
    
    NSMutableIndexSet* setTo = nil;
    
    if (folderTo.type == FolderTypeUser) {
        setTo = self.userFoldersContent[folderTo.idx];
    }
    else {
        setTo = self.systemFoldersContent[folderTo.type];
    }
    
    switch (folderTo.type) {
        case FolderTypeInbox:
        case FolderTypeAll:
        case FolderTypeDeleted:
        case FolderTypeSpam:
        case FolderTypeUser:
            break;
        default:
            NSLog(@"move to this folder not implemented");
            
            return NO;
    }
    
    NSMutableIndexSet* setFrom = nil;
    
    if (folderFrom.type == FolderTypeUser) {
        setFrom = self.userFoldersContent[folderFrom.idx];
    }
    else {
        setFrom = self.systemFoldersContent[folderFrom.type];
    }
    
    BOOL remove = NO;
    
    switch (folderFrom.type) {
        case FolderTypeInbox:
        case FolderTypeUser:
        case FolderTypeDrafts:
            remove = YES;
            break;
            
        case FolderTypeFavoris:
        case FolderTypeAll:
            remove = (folderTo.type == FolderTypeDeleted || folderTo.type == FolderTypeSpam);
            break;
        case FolderTypeDeleted:
        case FolderTypeSpam:
            remove = (folderTo.type != FolderTypeDeleted && folderTo.type != FolderTypeSpam);
            break;
        default:
            NSLog(@"move from this folder not implemented");
            
            return NO;
    }
    
    /*if (folderFrom.type == FolderTypeDrafts && [[conversation firstMail].email.msgId integerValue] <= 0) {
     [self deleteDraft:[conversation firstMail]];
     
     return YES;
     }*/
    
    if (folderTo.type == FolderTypeDeleted) {
        [conversation trash];
    }
    else {
        [conversation moveFromFolder:[AppSettings numFolderWithFolder:folderFrom forAccountIndex:self.idx] ToFolder:[AppSettings numFolderWithFolder:folderTo forAccountIndex:self.idx]];
    }
    
    if (remove) {
        [setFrom removeIndex:idx];
        if (encodeFolderTypeWith(folderFrom) == encodeFolderTypeWith(self.currentFolderType)) {
            [self.mailListSubscriber removeConversationList:@[[ConversationIndex initWithIndex:idx Account:self.idx]]];
        }
    }
    else {
        [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.done", @"Done")];
        [CCMStatus dismissAfter:1];
    }
    
    [setTo addIndex:idx];
    
    return remove;
}

-(void) star:(BOOL)add conversation:(Conversation*)conversation
{
    NSAssert(!self.isAllAccounts, @"Should not be called by all Accounts");

    NSMutableArray* tmp = [self.allsMails mutableCopy];
    NSUInteger idx = [tmp indexOfObject:conversation];
    
    if (!add) {
        [(NSMutableIndexSet*)self.systemFoldersContent[FolderTypeFavoris] removeIndex:idx];
    }
    else {
        [(NSMutableIndexSet*)self.systemFoldersContent[FolderTypeFavoris] addIndex:idx];
    }
}

-(NSInteger) unreadInInbox
{
    NSInteger count = 0;

    if (!self.isAllAccounts) {
        count = [AppSettings inboxUnread:self.idx];
    }
    else {
        for (Account* a in [Accounts sharedInstance].accounts) {
            if (!a.isAllAccounts) {
                count += [AppSettings inboxUnread:a.idx];
            }
        }
    }
    
    return count;
}

-(NSInteger) favorisCount
{
    NSInteger count = 0;

    if (!self.isAllAccounts) {
        if ([AppSettings numFolderWithFolder:FolderTypeWith(FolderTypeFavoris, 0) forAccountIndex:self.idx] != [AppSettings numFolderWithFolder:FolderTypeWith(FolderTypeAll, 0) forAccountIndex:self.idx]) {
            count = [[[SyncManager getSingleton] retrieveState:[AppSettings numFolderWithFolder:FolderTypeWith(FolderTypeFavoris, 0) forAccountIndex:self.idx] accountIndex:self.idx][@"emailCount"] integerValue];
        }
        else {
            count = [self getConversationsForFolder:FolderTypeWith(FolderTypeFavoris, 0)].count;
        }
    }
    else {
        for (Account* a in [Accounts sharedInstance].accounts) {
            if (!a.isAllAccounts) {
                if ([AppSettings numFolderWithFolder:FolderTypeWith(FolderTypeFavoris, 0) forAccountIndex:a.idx] != [AppSettings numFolderWithFolder:FolderTypeWith(FolderTypeAll, 0) forAccountIndex:a.idx]) {
                    count += [[[SyncManager getSingleton] retrieveState:[AppSettings numFolderWithFolder:FolderTypeWith(FolderTypeFavoris, 0) forAccountIndex:a.idx] accountIndex:a.idx][@"emailCount"] integerValue];
                }
                else {
                    count += [a getConversationsForFolder:FolderTypeWith(FolderTypeFavoris, 0)].count;
                }
            }
        }
    }
    
    return count;
}

-(NSInteger) draftCount
{
    NSInteger count = 0;

    if (!self.isAllAccounts) {
        count = [[[SyncManager getSingleton] retrieveState:[AppSettings numFolderWithFolder:FolderTypeWith(FolderTypeDrafts, 0) forAccountIndex:self.idx] accountIndex:self.idx][@"emailCount"] integerValue];
    }
    else {
        for (Account* a in [Accounts sharedInstance].accounts) {
            if (!a.isAllAccounts) {
                count +=  [[[SyncManager getSingleton] retrieveState:[AppSettings numFolderWithFolder:FolderTypeWith(FolderTypeDrafts, 0) forAccountIndex:a.idx] accountIndex:a.idx][@"emailCount"] integerValue];
            }
        }
    }
    
    return count;
}

-(void) setCurrentFolder:(CCMFolderType)folder
{
    self.currentFolderType = folder;
    _currentFolderFullSyncCompleted = NO;
    _hasLoadedAllLocal = NO;
    _isLoadingMore = NO;

    if (folder.type == FolderTypeUser) {
        NSString* name = [[Accounts sharedInstance] currentAccount].userFolders[folder.idx][0];
        NSArray* names = [AppSettings allFoldersNameforAccountIndex:self.idx];
        for (int i = 0; i < names.count; i++) {
            if ([name isEqualToString:names[i]]) {
                self.currentFolderIdx = i;
                [self refreshCurrentFolder];
                [self localFetchMore:NO];
                return;
            }
        }
    } else {
        if (self.isAllAccounts) {
            self.currentFolderIdx = folder.type;
            for (Account* a in [Accounts sharedInstance].accounts) {
                if (!a.isAllAccounts) {
                    [a setCurrentFolder:folder];
                }
            }
        }
        else {
            self.currentFolderIdx = [AppSettings importantFolderNumforAccountIndex:self.idx forBaseFolder:folder.type];
            [self refreshCurrentFolder];
            [self localFetchMore:NO];
        }
    }
}

-(void) showProgress
{
    NSInteger syncCount = 0;
    NSInteger emailCount = 0;
    
    if (self.isAllAccounts) {
        
        for (NSInteger accountIndex = 0; accountIndex < [Accounts sharedInstance].accountsCount; accountIndex++) {
            
            for (int i = 0; i < [AppSettings allFoldersNameforAccountIndex:accountIndex].count; i++) {
                NSMutableDictionary* syncState = [[SyncManager getSingleton] retrieveState:i accountIndex:accountIndex];
                NSInteger lastEnded = [syncState[@"lastended"] integerValue];
                NSInteger tmpEmailCount = [syncState[@"emailCount"] integerValue];
                
                if (lastEnded == 0) {
                    lastEnded = tmpEmailCount;
                }
                
                emailCount += tmpEmailCount;
                syncCount += tmpEmailCount - lastEnded;
            }
        }
    }
    else {
        for (int i = 0; i < [AppSettings allFoldersNameforAccountIndex:self.idx].count; i++) {
            NSMutableDictionary* syncState = [[SyncManager getSingleton] retrieveState:i accountIndex:self.idx];
            NSInteger lastEnded = [syncState[@"lastended"] integerValue];
            NSInteger tmpEmailCount = [syncState[@"emailCount"] integerValue];
            
            if (lastEnded == 0) {
                lastEnded = tmpEmailCount;
            }
            
            emailCount += tmpEmailCount;
            syncCount += tmpEmailCount - lastEnded;
        }
    }
    
    if ((long)(syncCount * 100) / emailCount < 99) {
        [CCMStatus showStatus:[NSString stringWithFormat:NSLocalizedString(@"status-bar-message.account-progress-sync", @"%@ %ld%% synced"), self.person.codeName, (long)(syncCount * 100) / emailCount]];
        [CCMStatus dismissAfter:3.0];
    }
}

-(void) insertRows:(Email*)email
{
    NSAssert(!self.isAllAccounts, @"Should not be called by all Accounts");

    if ((![[email getSonID] isEqualToString:@""] & ![[email getSonID] isEqualToString:@"0"]) && [_convIDs containsObject:[email getSonID]]) {
        for (NSUInteger idx = 0; idx < self.allsMails.count; idx++) {
            Conversation* conv = self.allsMails[idx];
            
            if ([[[conv firstMail].email getSonID] isEqualToString:[email getSonID]]) {
                [conv addMail:[Mail mail:email]];
                [self _addCon:idx toFoldersContent:conv.foldersType];
                return;
            }
        }
    }
    else {
        Conversation* conv = [[Conversation alloc]init];
        [conv addMail:[Mail mail:email]];
        [_convIDs addObject:[email getSonID]];
        [self addConversation:conv];
    }
}

-(void) insertPersonRows:(Email*)email
{
    if ((![[email getSonID] isEqualToString:@""] & ![[email getSonID] isEqualToString:@"0"]) && [_convIDs containsObject:[email getSonID]]) {
        for (NSUInteger idx = 0; idx < self.allsMails.count; idx++) {
            Conversation* conv = self.allsMails[idx];
            
            if ([[[conv firstMail].email getSonID] isEqualToString:[email getSonID]]) {
                [conv addMail:[Mail mail:email]];
                [self _addCon:idx toFoldersContent:conv.foldersType];
                return;
            }
        }
    }
    else {
        Conversation* conv = [[Conversation alloc]init];
        [conv addMail:[Mail mail:email]];
        [_convIDs addObject:[email getSonID]];
        [self addConversation:conv];
    }
}

#pragma mark - Fetch Data

-(void) importantFoldersRefresh:(NSInteger)pFolder
{
    NSAssert(!self.isAllAccounts, @"Should not be called by all Accounts");

    NSInteger __block folder = pFolder;
    
    //If last important folder start full sync
    if (folder > 4) {
        [self doLoadServer];
        return;
    }
    
    if (!_isSyncing && !_isSyncingCurrentFolder) {
        _isSyncing = YES;
        
    [[[SyncManager getSingleton] refreshImportantFolder:folder]
     subscribeNext:^(Email* email) {
     }
     error:^(NSError* error) {
         CCMLog(@"Error: %@", error.localizedDescription);
         _isSyncing = NO;

         if (error.code == 9002 && [Accounts sharedInstance].currentAccountIdx == self.idx) {
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
    NSAssert(!self.isAllAccounts, @"Should not be called by all Accounts");

    if (!_isSyncing && !_isSyncingCurrentFolder) {
        _isSyncing = YES;
    [[[[SyncManager getSingleton] syncFolders] deliverOn:[RACScheduler scheduler]]
     subscribeNext:^(Email* email) {
         //[self insertRows:email];
     }
     error:^(NSError* error) {
         _isSyncing = NO;
         CCMLog(@"Error: %@", error.localizedDescription);
         
         if ([Accounts sharedInstance].currentAccountIdx == self.idx) {
             if (error.code == 9001) {
                 CCMLog(@"ALLLLLL Synced!?");
             }
             else if (error.code == 9002) {
                 [self doLoadServer];;
             }
         }
     }
     completed:^{
         _isSyncing = NO;
         if ([Accounts sharedInstance].currentAccountIdx == self.idx) {
             [self doLoadServer];
         }
     }];
    }
}

-(void) runTestData
{
    NSAssert(!self.isAllAccounts, @"Should not be called by all Accounts");

    if (!self.isAllAccounts && self.allsMails.count != 0 && !_runningUpToDateTest) {
        _runningUpToDateTest = YES;
        
        NSMutableIndexSet* set = nil;
        
        if (self.currentFolderType.type == FolderTypeUser) {
            set = [self.userFoldersContent[self.currentFolderType.idx] mutableCopy];
        }
        else {
            set = [self.systemFoldersContent[self.currentFolderType.type] mutableCopy];
        }
        
        NSMutableArray* res = [NSMutableArray arrayWithCapacity:[set count]];
        
        NSMutableArray* _aMS = [self.allsMails mutableCopy];
        
        [_aMS enumerateObjectsAtIndexes:set
                                          options:0
                                       usingBlock:^(id obj, NSUInteger idx, BOOL* stop){
                                           [res addObject:obj];
                                       }];
        
        NSMutableIndexSet* setAll = [self.systemFoldersContent[FolderTypeAll] mutableCopy];
        NSMutableArray* resAll = [NSMutableArray arrayWithCapacity:[setAll count]];

        [[ImapSync sharedServices:self.idx] runUpToDateTest:res folderIndex:self.currentFolderIdx completed:^{
            [self.mailListSubscriber removeConversationList:nil];
            
            if (self.currentFolderType.type != FolderTypeAll) {
                [_aMS enumerateObjectsAtIndexes:setAll
                                        options:0
                                     usingBlock:^(id obj, NSUInteger idx, BOOL* stop){
                                                    [resAll addObject:obj];
                                                }];
            
            
                [[ImapSync sharedServices:self.idx] runUpToDateTest:resAll folderIndex:[AppSettings numFolderWithFolder:FolderTypeWith(FolderTypeAll, 0) forAccountIndex:self.idx] completed:^{
                    _runningUpToDateTest = NO;
                
                    [self.mailListSubscriber removeConversationList:nil];
                }];
            }
            
        }];
    }
}

-(void) deliverUpdate:(NSArray <Email*>*)emails
{
    NSAssert(!self.isAllAccounts, @"Should not be called by all Accounts");

    CCMLog(@"Updates");
    
    for (Email* email in emails) {
        BOOL found = NO;
        
        for (Conversation* conv in self.allsMails) {
            for (Mail* m in conv.mails) {
                if ([m.email.msgId isEqualToString:email.msgId]) {
                    CCMLog(@"Updated Email");
                    
                    m.email.flag = email.flag;
                    
                    found = YES;
                    break;
                }
            }
            
            if (found) {
                break;
            }
        }
        
        if (!found) {
            CCMLog(@"Error Conversation to delete not found");
        }
    }
}

-(void) deliverDelete:(NSArray*)emails
{
    NSAssert(!self.isAllAccounts, @"Should not be called by all Accounts");

    CCMLog(@"Deletes");
    
    NSMutableArray* idxs = [[NSMutableArray alloc]initWithCapacity:emails.count];
    
    NSMutableIndexSet* currentSet = nil;
    
    if (self.currentFolderType.type == FolderTypeUser) {
        currentSet = self.userFoldersContent[self.currentFolderType.idx];
    }
    else {
        currentSet = self.systemFoldersContent[self.currentFolderType.type];
    }
    
    for (Email* email in emails) {
        BOOL found = NO;
        NSInteger index = 0;
        
        for (; !found && index < self.allsMails.count; index++) {
            for (Mail* m in ((Conversation* )self.allsMails[index]).mails) {
                if ([m.email.msgId isEqualToString:email.msgId]) {
                    CCMLog(@"Delete Email %@", email.subject);
                    found = YES;
                    break;
                }
            }
        }
        
        index--;
        
        if (!found) {
            CCMLog(@"Error Conversation to delete not found");
        }
        else {
            //[self.allsMails removeObjectAtIndex:index];
            
            if ([currentSet containsIndex:index]) {
                [idxs addObject:[ConversationIndex initWithIndex:index Account:self.idx]];
            }
            
            for (NSMutableIndexSet* set in self.systemFoldersContent) {
                [set removeIndex:index];
            }
            
            for (NSMutableIndexSet* set in self.userFoldersContent) {
                [set removeIndex:index];
            }
        }
    }
    
    [self.mailListSubscriber removeConversationList:idxs];
}

-(void) doPersonSearch:(NSArray*)addressess
{
    NSAssert(!self.isAllAccounts, @"Should not be called by all Accounts");

    NSInteger refBatch = 5;
    NSInteger __block batch = refBatch;

    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [ViewController animateCocoaButtonRefresh:YES];
    }];
    
    //LocalSearch
    [_localFetchQueue addOperationWithBlock:^{
        [[[SearchRunner getSingleton] senderSearch:addressess inAccount:self.idx]
         subscribeNext:^(Email* email) {
                 [self insertPersonRows:email];
                 if (batch-- == 0) {
                     batch = refBatch;
                     [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                         [self.mailListSubscriber reFetch];
                     }];
                 }
         }
         completed:^{
             [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                 [self.mailListSubscriber reFetch];
             }];
         }];
    }];
    
    //ServerSearch
    [[[[SyncManager getSingleton] searchThings:addressess] deliverOn:[RACScheduler mainThreadScheduler]]
     subscribeNext:^(Email* email) {
         [self insertPersonRows:email];
     }
     error:^(NSError* error) {
         CCMLog(@"Error: %@", error.localizedDescription);
         [[NSOperationQueue mainQueue] addOperationWithBlock:^{
             [ViewController animateCocoaButtonRefresh:NO];
             [self.mailListSubscriber reFetch];
         }];
     }
     completed:^{
         [[NSOperationQueue mainQueue] addOperationWithBlock:^{
             [ViewController animateCocoaButtonRefresh:NO];
             [self.mailListSubscriber reFetch];
         }];
     }];
}

-(void) doTextSearch:(NSString*)searchString
{
    NSAssert(!self.isAllAccounts, @"Should not be called by all Accounts");
    
    NSInteger refBatch = 5;
    NSInteger __block batch = refBatch;
    
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [ViewController animateCocoaButtonRefresh:YES];
    }];
    
    //LocalSearch
    [_localFetchQueue addOperationWithBlock:^{
        [[[SearchRunner getSingleton] search:searchString inAccount:self.idx]
         subscribeNext:^(Email* email) {
             [self insertPersonRows:email];
             if (batch-- == 0) {
                 batch = refBatch;
                 [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                     [self.mailListSubscriber reFetch];
                 }];
             }
         }
         completed:^{
             [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                 [self.mailListSubscriber reFetch];
             }];
         }];
    }];
    
    //ServerSearch
    [[[[SyncManager getSingleton] searchText:searchString] deliverOn:[RACScheduler mainThreadScheduler]]
     subscribeNext:^(Email* email) {
         [self insertPersonRows:email];
     }
     error:^(NSError* error) {
         CCMLog(@"Error: %@", error.localizedDescription);
         [[NSOperationQueue mainQueue] addOperationWithBlock:^{
             [ViewController animateCocoaButtonRefresh:NO];
             [self.mailListSubscriber reFetch];
         }];
     }
     completed:^{
         [[NSOperationQueue mainQueue] addOperationWithBlock:^{
             [ViewController animateCocoaButtonRefresh:NO];
             [self.mailListSubscriber reFetch];
         }];
     }];
}

-(void) localFetchMore:(BOOL)loadMore
{

    if (self.isAllAccounts) {
        for (Account* a in [Accounts sharedInstance].accounts) {
            if (!self.isAllAccounts) {
                [a localFetchMore:loadMore];
            }
        }
        return;
    }
    
    if (!_isLoadingMore && !_hasLoadedAllLocal) {
        _isLoadingMore = YES;
        
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [ViewController animateCocoaButtonRefresh:YES];
        }];
        
        NSInteger refBatch = 50;
        
        if (!loadMore) {
            refBatch = 5;
        }
        
        NSInteger __block batch = refBatch;
        BOOL __block more = NO;
        
        [_localFetchQueue addOperationWithBlock:^{
            [[[SearchRunner getSingleton] activeFolderSearch:loadMore?_lastEmails[self.currentFolderIdx]:nil inAccount:self.idx]
         subscribeNext:^(Email* email) {
             more = YES;
             
             [[Accounts sharedInstance].accounts[[AppSettings indexForAccount:email.accountNum]] insertRows:email];
             if (batch-- == 0) {
                 batch = refBatch;
                 [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                     [self.mailListSubscriber reFetch];
                 }];
             }
             
             _lastEmails[self.currentFolderIdx] = email;
         }
         completed:^{
             _isLoadingMore = NO;
             
             if (!more) {
                 _hasLoadedAllLocal = YES;
             }
             
             [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                 [ViewController animateCocoaButtonRefresh:NO];
                 [self.mailListSubscriber reFetch];
             }];
         }];
    }];
    }
}

-(NSArray*) systemFolderNames
{
    NSMutableArray* names = [[NSMutableArray alloc]init];
    
    [names addObject:NSLocalizedString(@"Inbox", @"Inbox")];
    [names addObject:NSLocalizedString(@"Favoris", @"Favoris")];
    
    if ([AppSettings importantFolderNumforAccountIndex:self.idx forBaseFolder:FolderTypeSent] != -1) {
        [names addObject:NSLocalizedString(@"Sent", @"Sent")];
    }
    
    if ([AppSettings importantFolderNumforAccountIndex:self.idx forBaseFolder:FolderTypeDrafts] != -1) {
        [names addObject:NSLocalizedString(@"Drafts", @"Drafts")];
    }
    [names addObject:NSLocalizedString(@"All emails", @"All emails")];
    
    if ([AppSettings importantFolderNumforAccountIndex:self.idx forBaseFolder:FolderTypeDeleted] != -1) {
        [names addObject:NSLocalizedString(@"Deleted", @"Deleted")];
    }
    
    if ([AppSettings importantFolderNumforAccountIndex:self.idx forBaseFolder:FolderTypeSpam] != -1) {
        [names addObject:NSLocalizedString(@"Spam", @"Spam")];
    }
    
    return names;
}


@end
