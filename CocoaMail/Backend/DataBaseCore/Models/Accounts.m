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
        
        NSMutableArray* accounts = [[NSMutableArray alloc]initWithCapacity:[AppSettings numActiveAccounts]];
        
        if ([AppSettings numActiveAccounts] > 0) {
            
            for (UserSettings* user in [AppSettings getSingleton].users) {
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
            [[[SearchRunner getSingleton] activeFolderSearch:nil inAccountNum:self.currentAccount.user.accountNum]
             subscribeNext:^(Mail* email) {
                 [self sortEmail:email];
             }
             completed:^{
                 [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                     [self.currentAccount.mailListSubscriber reFetch:YES];
                 }];
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
        CCMLog(@"Houston on a un probleme avec l'email:%@", email.subject);
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
    [account setConnected:NO];
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
    
    NSAssert(accountIndex <= [AppSettings numActiveAccounts], @"accountIdx:%ld is incorrect only %ld active account",(long)accountIndex,(long)[AppSettings numActiveAccounts]);
    
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
    return @[@"inbox_off", @"favoris_off", @"sent_off", @"draft_off", @"all_off", @"delete_off", @"spam_off"];
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
        
        [[AppSettings userWithNum:draft.accountNum].linkedAccount addLocalDraft:draft];
    }
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
    UIBackgroundTaskIdentifier _backgroundUpdateTask;
    UserSettings* _user;
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

-(void) addLocalDraft:(Draft*)draft
{
    Mail* m = [Mail mailWithDraft:draft];
    //Conversation* conv = [[Conversation alloc]init];
    //[conv addMail:m];
    //conv.isDraft = YES;
    
    //[_drafts addObject:conv];
    [self insertRows:m];
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
    _connected = NO;
    _runningUpToDateTest = NO;
    _drafts = [[NSMutableArray alloc]init];
    
    _localFetchQueue = [NSOperationQueue new];
    [_localFetchQueue setMaxConcurrentOperationCount:1];
    _isLoadingMore = NO;
    _hasLoadedAllLocal = NO;
    
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
    
    //Including Non selectable
    NSInteger folderCount = [[SyncManager getSingleton] folderCount:self.user.accountNum];
    
    _lastEmails = [[NSMutableArray alloc]initWithCapacity:folderCount];
    
    for (int index = 0; index < folderCount ; index++) {
        [_lastEmails addObject:[[Mail alloc]init]];
    }
    
    self.currentFolderType = decodeFolderTypeWith([AppSettings lastFolderIndex].integerValue);
    
    if (self.currentFolderType.type == FolderTypeUser) {
        NSString* name = self.userFolders[self.currentFolderType.idx][0];
        NSArray* names = [self.user allFoldersDisplayNames];
        for (int i = 0; i < names.count; i++) {
            if ([name isEqualToString:names[i]]) {
                self.currentFolderIdx = i;
                break;
            }
        }
    } else {
        self.currentFolderIdx = [self.user importantFolderNumforBaseFolder:self.currentFolderType.type];
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
                    CCMLog(@"connection error");
                } completed:^{}];
                
                break;
            }
        }
    }
    else {
        [[ImapSync doLogin:self.user] subscribeError:^(NSError *error) {
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
    NSAssert(!self.user.isAll, @"Should not be called by all Accounts");
    
    if (isConnected && !_connected) {
        _connected = isConnected;
        
        [ImapSync runInboxUnread:self.user];
        [self refreshCurrentFolder];
    }
    
    if (isConnected && kisActiveAccountAll){
        [[Accounts sharedInstance].currentAccount connect];
    }
    
    _connected = isConnected;
}

-(void) releaseContent
{
    //TODO:If memory issues
    //self.allsMails = nil;
    //self.userFoldersContent = nil;
    //self.systemFoldersContent = nil;
    // let the drafts
}

-(NSArray*) systemFolderNames
{
    NSMutableArray* names = [[NSMutableArray alloc]init];
    
    [names addObject:NSLocalizedString(@"Inbox", @"Inbox")];
    [names addObject:NSLocalizedString(@"Favoris", @"Favoris")];
    
    if (self.user.isAll || [self.user importantFolderNumforBaseFolder:FolderTypeSent] != -1) {
        [names addObject:NSLocalizedString(@"Sent", @"Sent")];
    }
    
    if (self.user.isAll || [self.user importantFolderNumforBaseFolder:FolderTypeDrafts] != -1) {
        [names addObject:NSLocalizedString(@"Drafts", @"Drafts")];
    }
    [names addObject:NSLocalizedString(@"All emails", @"All emails")];
    
    if (self.user.isAll || [self.user importantFolderNumforBaseFolder:FolderTypeDeleted] != -1) {
        [names addObject:NSLocalizedString(@"Deleted", @"Deleted")];
    }
    
    if (self.user.isAll || [self.user importantFolderNumforBaseFolder:FolderTypeSpam] != -1) {
        [names addObject:NSLocalizedString(@"Spam", @"Spam")];
    }
    
    return names;
}

- (void)cancelSearch
{
    self.mailListSubscriber = nil;
}

-(void) _addCon:(NSUInteger)idx toFoldersContent:(NSSet*)folders
{
    NSAssert(!self.user.isAll, @"Should not be called by all Accounts");
    
    for (NSNumber* Fuser in folders) {
        [self _addIdx:idx inArray:decodeFolderTypeWith([Fuser integerValue])];
    }
}

-(void) _addIdx:(NSUInteger)idx inArray:(CCMFolderType)type
{
    NSAssert(!self.user.isAll, @"Should not be called by all Accounts");
    
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
            
            NSMutableDictionary* syncState = [[SyncManager getSingleton] retrieveState:[self.user numFolderWithFolder:self.currentFolderType] accountNum:self.user.accountNum];
            NSInteger tmpEmailCount = [syncState[@"emailCount"] integerValue];
            
            if (set.count == 20) {
                if ([Accounts sharedInstance].currentAccountIdx == self.idx) {
                    [self runTestData];
                }
            }
            
            if (set.count == 50 || (tmpEmailCount < 50 && set.count == tmpEmailCount)) {
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    [self.mailListSubscriber reFetch:YES];
                }];
            }
        }
    }
}

-(NSUInteger) addConversation:(Conversation*)conv
{
    NSAssert(!self.user.isAll, @"Should not be called by all Accounts");
    
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
    NSAssert(!self.user.isAll, @"Should not be called by all Accounts");
    
    return [self.allsMails objectAtIndex:index];
}

-(NSMutableArray*) getConversationsForFolder:(CCMFolderType)type
{
    NSAssert(!self.user.isAll, @"Should not be called by all Accounts");
    
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
                             [res addObject:[ConversationIndex initWithIndex:idx user:self.user]];
                         }];
    
    
    return res;
    
}

-(void) sendDraft:(Draft*)draft to:(NSArray *)toPersonIDs
{
    NSAssert(!self.user.isAll, @"Should not be called by all Accounts");
    
    MCOMailProvider* accountProvider = [[MCOMailProvidersManager sharedManager] providerForIdentifier:self.user.identifier];
    
    NSArray* smtpServicesArray = accountProvider.smtpServices;
    MCONetService* service = smtpServicesArray[0];
    
    MCOSMTPSession* smtpSession = [[MCOSMTPSession alloc] init];
    smtpSession.hostname = service.hostname ;
    smtpSession.port = service.port;
    smtpSession.username = self.user.username;
    smtpSession.password = self.user.password;
    smtpSession.connectionType = service.connectionType;
    
    CCMLog(@"Sending with:%@ port:%u authType:%ld", smtpSession.hostname, smtpSession.port, (long)MCOAuthTypeSASLNone);
    [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.sending-email", @"Sending email...") dismissAfter:2];
    NSData* rfc822Data = [draft rfc822DataTo:toPersonIDs];
    
    MCOSMTPSendOperation* sendOperation = [smtpSession sendOperationWithData:rfc822Data];
    
    //[(InViewController*)[[ViewController mainVC] topIVC] showSGProgressWithDuration:2.0 andTintColor:[AppSettings color:self.idx] andTitle:NSLocalizedString(@"status-bar-message.sending-email", @"Sending email...")];

    sendOperation.progress = ^(unsigned int current, unsigned int maximum){
        [(InViewController*)[[ViewController mainVC] topIVC] setSGProgressPercentage:((long)(current*100)/maximum) andTintColor:self.user.color];
    };

    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        [self beginBackgroundUpdateTask];
        
        [sendOperation start:^(NSError* error) {
        
        if (error) {
            
            if (error.code == MCOErrorNeedsConnectToWebmail) {
                UIAlertController* ac = [UIAlertController alertControllerWithTitle:nil
                                                                            message:@"Authorization in webmail needed"
                                                                     preferredStyle:UIAlertControllerStyleAlert];
                
                UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"Ok" style:UIAlertActionStyleDefault
                                                                     handler:nil];
                [ac addAction:cancelAction];
                
                ViewController* vc = [ViewController mainVC];
                
                [vc presentViewController:ac animated:YES completion:nil];
            }
            
            CCMLog(@"%@ Error sending email:%@", self.user.username, error);
            
            if (smtpServicesArray.count == 2) {
                [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.sending-email", @"Sending email...") dismissAfter:2];
                
                MCOSMTPSession* smtpSessionAux = [[MCOSMTPSession alloc] init];
                
                MCONetService* serviceAux = smtpServicesArray[1];
                smtpSessionAux.hostname = serviceAux.hostname ;
                smtpSessionAux.port = serviceAux.port;
                smtpSessionAux.connectionType = serviceAux.connectionType;
                smtpSessionAux.username = self.user.username;
                smtpSessionAux.password = self.user.password;
                
                CCMLog(@"Sending with:%@ port:%u authType:%ld", smtpSessionAux.hostname, smtpSessionAux.port, (long)MCOAuthTypeSASLNone);
                
                MCOSMTPSendOperation* sendOperation = [smtpSessionAux sendOperationWithData:rfc822Data];
                [sendOperation start:^(NSError* error) {
                    if (error) {
                        if (error.code == MCOErrorNeedsConnectToWebmail) {
                            UIAlertController* ac = [UIAlertController alertControllerWithTitle:nil
                                                                                        message:@"Authorization in webmail needed"
                                                                                 preferredStyle:UIAlertControllerStyleAlert];
                            
                            UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"Ok" style:UIAlertActionStyleDefault
                                                                                 handler:nil];
                            [ac addAction:cancelAction];
                            
                            ViewController* vc = [ViewController mainVC];
                            
                            [vc presentViewController:ac animated:YES completion:nil];
                        }
                        CCMLog(@"%@ Error sending email:%@", self.user.username, error);
                        [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.error-sending", @"Error: Email not sent.") dismissAfter:2];
                        [self endBackgroundUpdateTask];
                    }
                    else {
                        CCMLog(@"%@ Successfully sent email!", self.user.username);
                        [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.email-sent", @"Email sent.") dismissAfter:2];
                        [draft deleteDraft];
                        [self endBackgroundUpdateTask];
                    }
                }];
                
            }
            else {
                [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.error-sending", @"Error: Email not sent.") dismissAfter:2];
                [self endBackgroundUpdateTask];
            }
        }
        else {
            CCMLog(@"%@ Successfully sent email!", self.user.username);
            [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.email-sent", @"Email sent.")  dismissAfter:2];
            [draft deleteDraft];
            [self endBackgroundUpdateTask];
        }
    }];
        
    });
    
    /*if ([self.drafts containsObject:mail]) {
     [self.drafts removeObject:mail];
     }*/
    
    //NSInteger index = self.allsMails.count;
    
    //Conversation* c = [[Conversation alloc] init];
    //[c addMail:mail];
    
    //[self.allsMails addObject:c];
    //[self _addIdx:index inArray:FolderTypeWith(FolderTypeSent, 0)];
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

-(void) deleteDraft:(NSString*)msgID
{
    Conversation* conversation = [[Conversation alloc]init];
    
    NSArray* uids = [UidEntry getUidEntriesWithMsgId:msgID];
    for (UidEntry* e in uids) {
        [conversation addMail:[Mail getMailWithMsgId:e.msgID dbNum:e.dbNum]];
    }
    
    CCMFolderType folderFrom = FolderTypeWith(FolderTypeDrafts, 0);
    CCMFolderType folderTo = FolderTypeWith(FolderTypeDeleted, 0);
    
    [self moveConversation:conversation from:folderFrom to:folderTo updateUI:YES];
}

-(BOOL) moveConversationAtIndex:(NSInteger)index from:(CCMFolderType)folderFrom to:(CCMFolderType)folderTo updateUI:(BOOL)updateUI
{
    if ([NSThread isMainThread]) CCMLog(@"Main Thread");

    NSAssert(!self.user.isAll, @"Should not be called by all Accounts");
    
    return [self moveConversation:[self.allsMails objectAtIndex:index] from:folderFrom to:folderTo updateUI:updateUI];
}

-(BOOL) moveConversation:(Conversation*)conversation from:(CCMFolderType)folderFrom to:(CCMFolderType)folderTo updateUI:(BOOL)updateUI
{
    if ([NSThread isMainThread]) CCMLog(@"Main Thread");

    NSAssert(!self.user.isAll, @"Should not be called by all Accounts");
    
    NSMutableArray* tmp = [self.allsMails mutableCopy];
    NSUInteger idx = [tmp indexOfObject:conversation];
    
    if (idx == NSNotFound) {
        CCMLog(@"Conversation:%@ not found",[conversation firstMail].subject);
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
    
    /*if (folderFrom.type == FolderTypeDrafts && [[conversation firstMail].email.msgID integerValue] <= 0) {
     [self deleteDraft:[conversation firstMail]];
     
     return YES;
     }*/
    
    if (folderTo.type == FolderTypeDeleted) {
        [conversation trash];
    }
    else {
        [conversation moveFromFolder:[self.user numFolderWithFolder:folderFrom] ToFolder:[self.user numFolderWithFolder:folderTo]];
    }
    
    if (remove) {
        [setFrom removeIndex:idx];
        
        NSMutableIndexSet* setTest = nil;
        
        if (folderFrom.type == FolderTypeUser) {
            setTest = self.userFoldersContent[folderFrom.idx];
        }
        else {
            setTest = self.systemFoldersContent[folderFrom.type];
        }
        
        if (updateUI && encodeFolderTypeWith(folderFrom) == encodeFolderTypeWith(self.currentFolderType)) {
            [self.mailListSubscriber removeConversationList:@[[ConversationIndex initWithIndex:idx user:self.user]]];
        }
    }
    else {
        [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.done", @"Done")  dismissAfter:2];
    }
    
    [setTo addIndex:idx];
    
    return remove;
}

-(void) star:(BOOL)add conversation:(Conversation*)conversation
{
    if ([NSThread isMainThread]) CCMLog(@"Main Thread");

    NSAssert(!self.user.isAll, @"Should not be called by all Accounts");
    
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
        if ([self.user numFolderWithFolder:FolderTypeWith(FolderTypeFavoris, 0)] != [self.user numFolderWithFolder:FolderTypeWith(FolderTypeAll, 0)]) {
            count = [[[SyncManager getSingleton] retrieveState:[self.user numFolderWithFolder:FolderTypeWith(FolderTypeFavoris, 0)] accountNum:self.user.accountNum][@"emailCount"] integerValue];
        }
        else {
            count = [self getConversationsForFolder:FolderTypeWith(FolderTypeFavoris, 0)].count;
        }
    }
    else {
        for (Account* a in [Accounts sharedInstance].accounts) {
            if (!a.user.isAll) {
                if ([self.user numFolderWithFolder:FolderTypeWith(FolderTypeFavoris, 0)] != [self.user numFolderWithFolder:FolderTypeWith(FolderTypeAll, 0)]) {
                    count += [[[SyncManager getSingleton] retrieveState:[self.user numFolderWithFolder:FolderTypeWith(FolderTypeFavoris, 0)] accountNum:a.user.accountNum][@"emailCount"] integerValue];
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
    
    if (!self.user.isAll) {
        count = [[[SyncManager getSingleton] retrieveState:[self.user numFolderWithFolder:FolderTypeWith(FolderTypeDrafts, 0)] accountNum:self.user.accountNum][@"emailCount"] integerValue];
    }
    else {
        for (Account* a in [Accounts sharedInstance].accounts) {
            if (!a.user.isAll) {
                NSInteger Acount =  [[[SyncManager getSingleton] retrieveState:[a.user numFolderWithFolder:FolderTypeWith(FolderTypeDrafts, 0)] accountNum:a.user.accountNum][@"emailCount"] integerValue];
                count = count + Acount;
            }
        }
    }
    
    return count;
}

-(void) setCurrentFolder:(CCMFolderType)folder
{
    if (encodeFolderTypeWith(self.currentFolderType) == encodeFolderTypeWith(folder)) {
        CCMLog(@"Same folder");
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
            self.currentFolderIdx = [self.user importantFolderNumforBaseFolder:folder.type];
            [self refreshCurrentFolder];
            [self localFetchMore:NO];
        }
    }
}

-(void) showProgress
{
    /*NSInteger syncCount = 0;
    NSInteger emailCount = 0;
    
    if (self.isAllAccounts) {
        for (NSInteger accountIndex = 0; accountIndex < [Accounts sharedInstance].accountsCount-1; accountIndex++) {
            
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
    
    NSInteger percentage = (long)(syncCount * 100) / emailCount;
    
    if (percentage > 0 && percentage < 99) {
        [CCMStatus showStatus:[NSString stringWithFormat:NSLocalizedString(@"status-bar-message.account-progress-sync", @"%@ %ld%% synced"), self.person.codeName, percentage]  dismissAfter:2];
    }*/
}

-(void) insertRows:(Mail*)email
{
    if (self.user.isDeleted) {
        return;
    }
    
    if ((![[email sonID] isEqualToString:@""] & ![[email sonID] isEqualToString:@"0"]) && [_convIDs containsObject:[email sonID]]) {
        for (NSUInteger idx = 0; idx < self.allsMails.count; idx++) {
            Conversation* conv = self.allsMails[idx];
            
            if ([[[conv firstMail] sonID] isEqualToString:[email sonID]]) {
                [conv addMail:email];
                [self _addCon:idx toFoldersContent:conv.foldersType];
                return;
            }
        }
    }
    else {
        Conversation* conv = [[Conversation alloc]init];
        [conv addMail:email];
        if ([RX(@"^[0-9]+?$") isMatch:email.msgID]) {
            conv.isDraft = YES;
        }
        [_convIDs addObject:[email sonID]];
        [self addConversation:conv];
    }
}

#pragma mark - Fetch Data

-(void) importantFoldersRefresh:(NSInteger)pFolder
{
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
         }
         error:^(NSError* error) {
             
             if (error.code != 9002 && error.code != 9001) {
                 CCMLog(@"Error: %@", error.localizedDescription);
             }
             
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
    if (self.user.isDeleted) {
        return;
    }
    
    if (![ImapSync canFullSync]){
        return;
    }
    
    if (!_isSyncing && !_isSyncingCurrentFolder) {
        _isSyncing = YES;
        [[[[SyncManager getSingleton] syncFoldersUser:self.user] deliverOn:[RACScheduler scheduler]]
         subscribeNext:^(Mail* email) {
             //[self insertRows:email];
         }
         error:^(NSError* error) {
             _isSyncing = NO;
             
             if (error.code != 9002 && error.code != 9001) {
                 CCMLog(@"Error: %@", error.localizedDescription);
             }
             
             if ([Accounts sharedInstance].currentAccountIdx == self.idx) {
                 if (error.code == 9001) {
                     //CCMLog(@"ALLLLLL Synced!?");
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
    if (self.user.isDeleted) {
        return;
    }
    
    if (!self.user.isAll && self.allsMails.count != 0 && !_runningUpToDateTest) {
        _runningUpToDateTest = YES;
        
        NSMutableIndexSet* set = nil;
        
        if (self.currentFolderType.type == FolderTypeUser) {
            set = [self.userFoldersContent[self.currentFolderType.idx] mutableCopy];
        }
        else {
            set = [self.systemFoldersContent[self.currentFolderType.type] mutableCopy];
        }
        
        NSMutableIndexSet* setAll = [self.systemFoldersContent[FolderTypeAll] mutableCopy];
        NSMutableArray* resAll = [NSMutableArray arrayWithCapacity:[setAll count]];
        NSMutableArray* res = [NSMutableArray arrayWithCapacity:[set count]];
        
        NSArray* _aMS = [self.allsMails mutableCopy];
        
        [_aMS enumerateObjectsAtIndexes:set
                                options:0
                             usingBlock:^(id obj, NSUInteger idx, BOOL* stop){
                                 [res addObject:obj];
                             }];
        
        [[ImapSync sharedServices:self.user] runUpToDateTest:res folderIndex:self.currentFolderIdx completed:^(NSArray *dels, NSArray *ups) {
            [self.mailListSubscriber removeConversationList:nil];
            
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
                
                [[ImapSync sharedServices:self.user] runUpToDateTest:resAll folderIndex:[self.user numFolderWithFolder:FolderTypeWith(FolderTypeAll, 0)] completed:^(NSArray *dels, NSArray *ups) {
                    _runningUpToDateTest = NO;
                    
                    [self.mailListSubscriber removeConversationList:nil];
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
        
        NSMutableIndexSet* set = nil;
        
        if (self.currentFolderType.type == FolderTypeUser) {
            set = [self.userFoldersContent[self.currentFolderType.idx] mutableCopy];
        }
        else {
            set = [self.systemFoldersContent[self.currentFolderType.type] mutableCopy];
        }
        
        NSMutableArray* res = [NSMutableArray arrayWithCapacity:[set count]];
        
        NSArray* _aMS = [self.allsMails mutableCopy];
        
        [_aMS enumerateObjectsAtIndexes:set
                                options:0
                             usingBlock:^(id obj, NSUInteger idx, BOOL* stop){
                                 [res addObject:obj];
                             }];
        
        [[ImapSync sharedServices:self.user] runUpToDateTest:res folderIndex:self.currentFolderIdx completed:^(NSArray *dels, NSArray *ups) {
            [self.mailListSubscriber removeConversationList:nil];
            [self localFetchMore:NO];
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
            CCMLog(@"Error Conversation to delete not found");
        }
    }
}

-(void) deliverDelete:(NSArray*)emails fromFolder:(CCMFolderType)folderFrom
{
    if (self.user.isDeleted) {
        return;
    }
    
    NSMutableArray* idxs = [[NSMutableArray alloc]initWithCapacity:emails.count];
    
    NSMutableIndexSet* currentSet = nil;
    
    if (folderFrom.type == FolderTypeUser) {
        currentSet = self.userFoldersContent[folderFrom.idx];
    }
    else {
        currentSet = self.systemFoldersContent[folderFrom.type];
    }
    
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
            CCMLog(@"Error Conversation to delete not found");
        }
        else {
            if ([currentSet containsIndex:index]) {
                [idxs addObject:[ConversationIndex initWithIndex:index user:self.user]];
                [currentSet removeIndex:index];
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
    
    NSMutableIndexSet* currentSet = nil;
    
    if (self.currentFolderType.type == FolderTypeUser) {
        currentSet = self.userFoldersContent[self.currentFolderType.idx];
    }
    else {
        currentSet = self.systemFoldersContent[self.currentFolderType.type];
    }
    
    if ([currentSet containsIndex:index]) {
        NSLog(@"Index %ld was still in set",(long)index);
        [currentSet removeIndex:index];
        return YES;
    }
    
    return NO;
}

-(void) doPersonSearch:(Person*)person
{
    if (self.user.isDeleted) {
        return;
    }
    
    NSInteger refBatch = 5;
    NSInteger __block batch = refBatch;
    
    //LocalSearch
    [_localFetchQueue addOperationWithBlock:^{
        [[[SearchRunner getSingleton] senderSearch:person inAccountNum:self.user.accountNum]
         subscribeNext:^(Mail* email) {
             [self insertRows:email];
             if (batch-- == 0) {
                 batch = refBatch;
                 [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                     [self.mailListSubscriber reFetch:YES];
                 }];
             }
         }
         completed:^{
             [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                 [self.mailListSubscriber reFetch:YES];
             }];
         }];
    }];
    
    //ServerSearch
    [[[[SyncManager getSingleton] searchPerson:person user:self.user] deliverOn:[RACScheduler mainThreadScheduler]]
     subscribeNext:^(Mail* email) {
         [self insertRows:email];
     }
     error:^(NSError* error) {
         CCMLog(@"Error: %@", error.localizedDescription);
         [[NSOperationQueue mainQueue] addOperationWithBlock:^{
             [self.mailListSubscriber reFetch:YES];
         }];
     }
     completed:^{
         [[NSOperationQueue mainQueue] addOperationWithBlock:^{
             [self.mailListSubscriber reFetch:YES];
         }];
     }];
}

-(void) doTextSearch:(NSString*)searchString
{
    if (self.user.isDeleted) {
        return;
    }
    
    NSInteger refBatch = 5;
    NSInteger __block batch = refBatch;
    
    //LocalSearch
    [_localFetchQueue addOperationWithBlock:^{
        [[[SearchRunner getSingleton] search:searchString inAccountNum:self.user.accountNum]
         subscribeNext:^(Mail* email) {
             [self insertRows:email];
             if (batch-- == 0) {
                 batch = refBatch;
                 [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                     [self.mailListSubscriber reFetch:YES];
                 }];
             }
         }
         completed:^{
             [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                 [self.mailListSubscriber reFetch:YES];
             }];
         }];
    }];
    
    //ServerSearch
    [[[[SyncManager getSingleton] searchText:searchString user:self.user] deliverOn:[RACScheduler mainThreadScheduler]]
     subscribeNext:^(Mail* email) {
         [self insertRows:email];
     }
     error:^(NSError* error) {
         CCMLog(@"Error: %@", error.localizedDescription);
         [[NSOperationQueue mainQueue] addOperationWithBlock:^{
             [self.mailListSubscriber reFetch:YES];
         }];
     }
     completed:^{
         [[NSOperationQueue mainQueue] addOperationWithBlock:^{
             [self.mailListSubscriber reFetch:YES];
         }];
     }];
}

-(void) localFetchMore:(BOOL)loadMore
{
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
        
        NSInteger refBatch = 50;
        
        if (!loadMore) {
            refBatch = 5;
        }
        
        NSInteger __block batch = refBatch;
        BOOL __block more = NO;
        
        [_localFetchQueue addOperationWithBlock:^{
            [[[SearchRunner getSingleton] activeFolderSearch:loadMore?_lastEmails[self.currentFolderIdx]:nil inAccountNum:self.user.accountNum]
             subscribeNext:^(Mail* email) {
                 more = YES;
                 
                 if (email.user && !email.user.isDeleted) {
                     [email.user.linkedAccount insertRows:email];
                 }
                 
                 if (batch-- == 0) {
                     batch = refBatch;
                     [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                         [self.mailListSubscriber reFetch:YES];
                     }];
                 }
                 
                 _lastEmails[self.currentFolderIdx] = email;
             }
             completed:^{
                 _isLoadingMore = NO;
                 
                 if (!more) {
                     _hasLoadedAllLocal = YES;
                 }
                 
                 [self runTestData];
                 
                 [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                     [self.mailListSubscriber reFetch:YES];
                 }];
             }];
        }];
    }
}

-(void) refreshCurrentFolder
{
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
    
        if (_connected) {
            NSInteger __block new = 0;
            
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [ViewController animateCocoaButtonRefresh:YES];
            }];
            
            [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.checking-email", @"Checking for new emails") dismissAfter:2];
            
            [[[[SyncManager getSingleton] syncActiveFolderFromStart:YES user:self.user] deliverOn:[RACScheduler schedulerWithPriority:RACSchedulerPriorityBackground]]
             subscribeNext:^(Mail* email) {
                 new++;
                 [self insertRows:email];
             } error:^(NSError* error) {
                 
                 if (error.code != 9002 && error.code != 9001) {
                     CCMLog(@"Error: %@", error.localizedDescription);
                 }
                 
                 [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                     [ViewController animateCocoaButtonRefresh:NO];
                 }];
                 
                 if (error.code == 9001 || error.code == 9002) {
                     
                     if (new == 0) {
                         [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.no-new-emails", @"No new emails") dismissAfter:2];
                     }
                     else if (new == 1) {
                         [CCMStatus showStatus:[NSString stringWithFormat:NSLocalizedString(@"status-bar-message.one-new-email", @"one new email"),(long)new] dismissAfter:2];
                     }
                     else {
                         [CCMStatus showStatus:[NSString stringWithFormat:NSLocalizedString(@"status-bar-message.x-new-emails", @"%ld new emails"),(long)new] dismissAfter:2];
                     }
                     
                     if ([Accounts sharedInstance].currentAccountIdx == self.idx) {
                         
                         [self runTestData];
                         
                         _currentFolderFullSyncCompleted = YES;
                         _isSyncingCurrentFolder = NO;
                         [self importantFoldersRefresh:1];
                     }
                 }
                 else if (error.code == 9000) {
                     [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.connecting_error", @"Connection error") dismissAfter:2];
                 }
             } completed:^{
                 
                 [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                     [ViewController animateCocoaButtonRefresh:NO];
                 }];
                 
                 if (new == 0) {
                     [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.no-new-emails", @"No new emails") dismissAfter:2];
                 }
                 else {
                     if (new == 1) {
                         [CCMStatus showStatus:[NSString stringWithFormat:NSLocalizedString(@"status-bar-message.one-new-email", @"one new email"),(long)new] dismissAfter:2];
                     }
                     else {
                         [CCMStatus showStatus:[NSString stringWithFormat:NSLocalizedString(@"status-bar-message.x-new-emails", @"%ld new emails"),(long)new] dismissAfter:2];
                     }
                     
                     [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                         [self.mailListSubscriber reFetch:YES];
                     }];
                 }
                 
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
}

-(void) syncCurrentFolder
{
    if (self.user.isDeleted) {
        return;
    }
    
    if (![ImapSync canFullSync]){
        return;
    }
    
    [[[[SyncManager getSingleton] syncActiveFolderFromStart:NO user:self.user] deliverOn:[RACScheduler mainThreadScheduler]]
     subscribeNext:^(Mail* email) {
         //[self insertRows:email];
     } error:^(NSError* error) {
         //CCMLog(@"Error: %@", error.localizedDescription);
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

@end
