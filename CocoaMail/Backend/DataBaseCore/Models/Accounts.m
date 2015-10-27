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
        sharedInstance.currentAccountIdx = 0;
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
        
        [sharedInstance runLoadData];
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
    
    return ac;
}

-(void) runLoadData
{
    [self.localFetchQueue addOperationWithBlock:^{
        [[[SearchRunner getSingleton] allEmailsSearch]
         subscribeNext:^(Email* email) {
             [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                 //CCMLog(@"Adding email to account:%u",self.idx);
                 if (email.accountNum == 0) {
                     CCMLog(@"Houston on a un probleme avec l'email:%@", email.subject);
                 }
                 else {
                     [self.accounts[[AppSettings indexForAccount:email.accountNum]] insertRows:email];
                 }
             }];
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
    
    NSAssert(accountIndex <= [AppSettings numActiveAccounts], @"accountIdx:%li is incorrect only %li active account",(long)accountIndex,(long)[AppSettings numActiveAccounts]);
    
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
    
    [self setCurrentFolder:FolderTypeWith(FolderTypeInbox, 0)];
}

-(void) connect
{
    _connected = YES;
}

-(void) refreshCurrentFolder
{
    if (_connected) {
        [[[[SyncManager getSingleton] syncActiveFolderFromStart:YES] deliverOn:[RACScheduler mainThreadScheduler]]
         subscribeNext:^(Email* email) {
             [self insertRows:email];
         } error:^(NSError* error) {
             CCMLog(@"Error: %@", error.localizedDescription);
             if (error.code == 9001) {
                 [self runTestData];

                 _currentFolderFullSyncCompleted = YES;
                 [self importantFoldersRefresh:1];
             }
         } completed:^{
             if ([Accounts sharedInstance].currentAccountIdx == self.idx) {
                 [self runTestData];

                 if (_currentFolderFullSyncCompleted) {
                     [self importantFoldersRefresh:1];
                 }
                 else {
                     [self syncCurrentFolder];
                 }
             }
         }];
    }
}

-(void) syncCurrentFolder
{
    [[[[SyncManager getSingleton] syncActiveFolderFromStart:NO] deliverOn:[RACScheduler mainThreadScheduler]]
     subscribeNext:^(Email* email) {
         [self insertRows:email];
     } error:^(NSError* error) {
         CCMLog(@"Error: %@", error.localizedDescription);
         
         if (error.code == 9001) {
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
    for (NSNumber* Fuser in folders) {
        [self _addIdx:idx inArray:decodeFolderTypeWith([Fuser integerValue])];
    }
}

-(void) _addIdx:(NSUInteger)idx inArray:(CCMFolderType)type
{
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
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [self.mailListSubscriber insertConversation:[ConversationIndex initWithIndex:idx Account:self.idx]];
            }];
            
            if (set.count == 20) {
                [self runTestData];
            }
        }
    }
}

-(void) addConversation:(Conversation*)conv
{
    NSUInteger index = [self.allsMails indexOfObject:conv];
    
    if (index == NSNotFound) {
        [self.allsMails addObject:conv];
        
        if (![conv.foldersType containsObject:numberWithFolderType(FolderTypeDeleted)] && ![conv.foldersType containsObject:numberWithFolderType(FolderTypeSpam)] && ![conv.foldersType containsObject:numberWithFolderType(FolderTypeDrafts)]) {
            [self _addIdx:self.allsMails.count - 1 inArray:FolderTypeWith(FolderTypeAll, 0)];
        }
        [self _addCon:self.allsMails.count - 1 toFoldersContent:conv.foldersType];
    }
    else {
        Conversation* con = [self.allsMails objectAtIndex:index];
        
        for (Mail* m in conv.mails) {
            [con addMail:m];
        }
    }
}

-(NSArray*) conversations
{
    return self.allsMails;
}

-(NSMutableArray*) getConversationsForFolder:(CCMFolderType)type
{
    NSMutableIndexSet* set = nil;
    
    if (type.type == FolderTypeUser) {
        set = self.userFoldersContent[type.idx];
    }
    else {
        set = self.systemFoldersContent[type.type];
    }
    
    NSMutableArray* res = [NSMutableArray arrayWithCapacity:[set count]];
    
    [self.allsMails enumerateObjectsAtIndexes:set
                                      options:0
                                   usingBlock:^(id obj, NSUInteger idx, BOOL* stop){
                                       [res addObject:[ConversationIndex initWithIndex:idx Account:self.idx]];
                                   }];
    
    
    return res;
    
}

-(void) sendMail:(Mail*)mail bcc:(BOOL)isBcc
{
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
    
    NSData* rfc822Data = [mail rfc822DataWithAccountIdx:self.idx isBcc:isBcc];
    
    MCOSMTPSendOperation* sendOperation = [smtpSession sendOperationWithData:rfc822Data];
    [sendOperation start:^(NSError* error) {
        
        if (error) {
            CCMLog(@"%@ Error sending email:%@", [AppSettings username:self.idx], error);
        }
        else {
            CCMLog(@"%@ Successfully sent email!", [AppSettings username:self.idx]);
        }
    }];
    
    /*if ([self.drafts containsObject:mail]) {
        [self.drafts removeObject:mail];
    }*/
    
    NSInteger index = self.allsMails.count;
    
    Conversation* c = [[Conversation alloc] init];
    [c addMail:mail];
    
    [self.allsMails addObject:c];
    [self _addIdx:index inArray:FolderTypeWith(FolderTypeSent, 0)];
}

/*-(void) saveDraft:(Mail*)mail
{
    Conversation* conv = [[Conversation alloc]init];
    [conv addMail:mail];
    
    if (![self.drafts containsObject:conv]) {
        [self.drafts addObject:conv];
    }
}

-(void) deleteDraft:(Mail*)mail
{
    Conversation* conv = [[Conversation alloc]init];
    [conv addMail:mail];
    
    [self.drafts removeObject:conv];
}*/

-(BOOL) moveConversationAtIndex:(NSInteger)index from:(CCMFolderType)folderFrom to:(CCMFolderType)folderTo
{
    return [self moveConversation:[self.allsMails objectAtIndex:index] from:folderFrom to:folderTo];
}

-(BOOL) moveConversation:(Conversation*)conversation from:(CCMFolderType)folderFrom to:(CCMFolderType)folderTo
{
    NSUInteger idx = [self.allsMails indexOfObject:conversation];
    
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
    
    [conversation moveFromFolder:[AppSettings numFolderWithFolder:folderFrom forAccountIndex:self.idx] ToFolder:[AppSettings numFolderWithFolder:folderTo forAccountIndex:self.idx]];
    
    if (remove) {
        [setFrom removeIndex:idx];
        if (encodeFolderTypeWith(folderFrom) == encodeFolderTypeWith(self.currentFolderType)) {
            [self.mailListSubscriber removeConversationList:@[[ConversationIndex initWithIndex:idx Account:self.idx]]];
        }
    }
    [setTo addIndex:idx];
    
    return remove;
}

-(void) star:(BOOL)add conversation:(Conversation*)conversation
{
    NSUInteger idx = [self.allsMails indexOfObject:conversation];
    
    if (!add) {
        [(NSMutableIndexSet*)self.systemFoldersContent[FolderTypeFavoris] removeIndex:idx];
    }
    else {
        [(NSMutableIndexSet*)self.systemFoldersContent[FolderTypeFavoris] addIndex:idx];
    }
}

-(NSInteger) unreadInInbox
{
    NSArray* a = [self getConversationsForFolder:FolderTypeWith(FolderTypeInbox, 0)];
    
    NSInteger count = 0;
    
    for (ConversationIndex* cI in a) {
        Conversation* c = [self.allsMails objectAtIndex:cI.index];
        if (![c firstMail].isRead) {
            count++;
        }
    }
    
    return count;
}

-(NSInteger) favorisCount
{
    return [[[SyncManager getSingleton] retrieveState:[AppSettings numFolderWithFolder:FolderTypeWith(FolderTypeFavoris, 0) forAccountIndex:self.idx] accountIndex:self.idx][@"emailCount"] integerValue];
}

-(NSInteger) draftCount
{
    NSArray* a = [self getConversationsForFolder:FolderTypeWith(FolderTypeDrafts, 0)];
    return a.count;//[[[SyncManager getSingleton] retrieveState:[AppSettings numFolderWithFolder:FolderTypeWith(FolderTypeDrafts, 0) forAccountIndex:self.idx] accountIndex:self.idx][@"emailCount"] integerValue];
}

-(void) setCurrentFolder:(CCMFolderType)folder
{
    self.currentFolderType = folder;
    
    if (folder.type == FolderTypeUser) {
        NSString* name = [[Accounts sharedInstance] currentAccount].userFolders[folder.idx][0];
        NSArray* names = [AppSettings allFoldersNameforAccountIndex:self.idx];
        for (int i = 0; i < names.count; i++) {
            if ([name isEqualToString:names[i]]) {
                self.currentFolderIdx = i;
                [self refreshCurrentFolder];
                return;
            }
        }
    } else {
        if (self.isAllAccounts) {
            self.currentFolderIdx = folder.type;
        }
        else {
            self.currentFolderIdx = [AppSettings importantFolderNumforAccountIndex:self.idx forBaseFolder:folder.type];
        }
        [self refreshCurrentFolder];
    }
}

-(void) showProgress
{
    NSInteger syncCount = 0;
    NSInteger emailCount = 0;
    
    for (int i = 0; i < [AppSettings allFoldersNameforAccountIndex:self.idx].count; i++) {
        // used by fetchFrom to write the finished state for this round of syncing to disk
        NSMutableDictionary* syncState = [[SyncManager getSingleton] retrieveState:i accountIndex:self.idx];
        NSInteger lastEnded = [syncState[@"lastended"] integerValue];
        NSInteger tmpEmailCount = [syncState[@"emailCount"] integerValue];
        
        if (lastEnded == 0) {
            lastEnded = tmpEmailCount;
        }
        
        emailCount += tmpEmailCount;
        syncCount += tmpEmailCount - lastEnded;
    }
    
    CCMLog(@"syncCount:%i emailCount:%i Percentage:%i", syncCount, emailCount, (syncCount * 100) / emailCount);

    [CCMStatus showStatus:[NSString stringWithFormat:@"%@ %i%% synced", self.person.codeName, (syncCount * 100) / emailCount]];
}

-(void) insertRows:(Email*)email
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
        [self.allsMails addObject:conv];
    }
}

#pragma mark - Fetch Data

-(void) importantFoldersRefresh:(NSInteger)pFolder
{
    NSInteger __block folder = pFolder;
    
    //If last important folder start full sync
    if (folder > 4) {
        [self doLoadServer];
        return;
    }
    
    [[[SyncManager getSingleton] refreshImportantFolder:folder]
     subscribeNext:^(Email* email) {
         [self insertRows:email];
     }
     error:^(NSError* error) {
         CCMLog(@"Error: %@", error.localizedDescription);
         
         if (error.code == 9001 && [Accounts sharedInstance].currentAccountIdx == self.idx) {
             [self importantFoldersRefresh:++folder];
         }
     }
     completed:^{
         if ([Accounts sharedInstance].currentAccountIdx == self.idx) {
             [self importantFoldersRefresh:++folder];
         }
     }];
}

-(void) doLoadServer
{
    [[[[SyncManager getSingleton] syncFolders] deliverOn:[RACScheduler scheduler]]
     subscribeNext:^(Email* email) {
         [self insertRows:email];
     }
     error:^(NSError* error) {
         CCMLog(@"Error: %@", error.localizedDescription);
         
         if (error.code == 9001 && [Accounts sharedInstance].currentAccountIdx == self.idx) {
             CCMLog(@"ALLLLLL Synced!?");
             //[self importantFoldersRefresh:1];
         }
     }
     completed:^{
         if ([Accounts sharedInstance].currentAccountIdx == self.idx) {
             [self doLoadServer];
         }
     }];
}

-(void) runTestData
{
    if (!self.isAllAccounts && self.allsMails.count != 0 && !_runningUpToDateTest) {
        _runningUpToDateTest = YES;
        
        NSMutableIndexSet* set = nil;
        
        if (self.currentFolderType.type == FolderTypeUser) {
            set = self.userFoldersContent[self.currentFolderType.idx];
        }
        else {
            set = self.systemFoldersContent[self.currentFolderType.type];
        }
        
        NSMutableArray* res = [NSMutableArray arrayWithCapacity:[set count]];
        
        [self.allsMails enumerateObjectsAtIndexes:set
                                          options:0
                                       usingBlock:^(id obj, NSUInteger idx, BOOL* stop){
                                           [res addObject:obj];
                                       }];
        
        [[ImapSync sharedServices:self.idx] runUpToDateTest:res folderIndex:self.currentFolderIdx completed:^{
            [self.mailListSubscriber removeConversationList:nil];
            
            NSMutableIndexSet* setAll = self.systemFoldersContent[FolderTypeAll];
            NSMutableArray* resAll = [NSMutableArray arrayWithCapacity:[setAll count]];
            
            [self.allsMails enumerateObjectsAtIndexes:setAll
                                              options:0
                                           usingBlock:^(id obj, NSUInteger idx, BOOL* stop){
                                               [resAll addObject:obj];
                                           }];
            
            [[ImapSync sharedServices:self.idx] runUpToDateTest:resAll folderIndex:[AppSettings numFolderWithFolder:FolderTypeWith(FolderTypeAll, 0) forAccountIndex:self.idx] completed:^{
                _runningUpToDateTest = NO;

                [self.mailListSubscriber removeConversationList:nil];                
            }];

        }];
    }
}

-(void) deliverUpdate:(NSArray <Email*>*)emails
{
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

-(void) doLoadServer:(BOOL)refresh
{
    [ViewController animateCocoaButtonRefresh:YES];
    
    [[[[SyncManager getSingleton] syncActiveFolderFromStart:refresh] deliverOn:[RACScheduler mainThreadScheduler]]
     subscribeNext:^(Email* email) {
         [self insertRows:email];
     }
     error:^(NSError* error) {
         CCMLog(@"Error: %@", error.localizedDescription);
     }
     completed:^{
         CCMLog(@"Done");
         [ViewController animateCocoaButtonRefresh:NO];
     }];
}

-(void) doPersonSearch:(NSArray*)addressess
{
    //LocalSearch
    [_localFetchQueue addOperationWithBlock:^{
        [[[SearchRunner getSingleton] senderSearch:addressess]
         subscribeNext:^(Email* email) {
             [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                 [self insertRows:email];
             }];
         }
         completed:^{
             [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                 //[self updateFilteredContentForSearchStrings:nil];
             }];
         }];
    }];
    
    //ServerSearch
    [[[[SyncManager getSingleton] searchThings:addressess] deliverOn:[RACScheduler mainThreadScheduler]]
     subscribeNext:^(Email* email) {
         [self insertRows:email];
     }
     error:^(NSError* error) {
         CCMLog(@"Error: %@", error.localizedDescription);
     }
     completed:^{
     }];
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
