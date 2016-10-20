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


@interface Account () {
    BOOL _currentFolderFullSyncCompleted;
    BOOL _runningUpToDateTest;
    
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

typedef NSMutableArray<Conversation*> CCMMutableConversationArray;

@property (nonatomic, strong) CCMMutableConversationArray* allsMails;        // All Mail Conversations for this account
@property (nonatomic, strong) NSMutableSet* convIDs;

//@property (nonatomic, strong) NSArray* userFoldersContent;      // user folder mail index sets
//@property (nonatomic, strong) NSArray* systemFoldersContent;    // system folder mail index sets

@end

@implementation Account

+(instancetype) emptyAccount
{
    Account* a = [[Account alloc] init];
    
#warning These are set to be arrays of 500 entries.  We should collect statistics on how many messages most people have
    a.allsMails = [NSMutableArray arrayWithCapacity:500];
    
#warning is "convIDs" used anywhere?
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
    // Create an empty Mutable Array for the "Standard" IMAP Folders
    //
    self.imapFolders = [[Folders alloc] init];
    
//    // create structure
//    NSMutableArray* systemFolderArray = [[NSMutableArray alloc] initWithCapacity:7];
//    
//    for (int i = 0; i < 7; i++) {
//        [systemFolderArray addObject:[[NSMutableIndexSet alloc] init]];
//    }
//    self.systemFoldersContent = systemFolderArray;
    
    //
    // Create an empty Mutable Array for the "User" IMAP Folders
    //
    
//    const NSInteger userFolderCount = [self.imapFolders userFoldersCount];
////    self.userFolders.count;
//    
//    NSMutableArray* userFolderArray = [[NSMutableArray alloc] initWithCapacity:userFolderCount];
//    for (int i = 0; i < userFolderCount; i++) {
//        [userFolderArray addObject:[[NSMutableIndexSet alloc] init]];
//    }
//    
//    self.userFoldersContent = userFolderArray;
    
    
    //Including Non selectable
    NSInteger folderCount = [[SyncManager getSingleton] folderCount:self.user.accountNum];
    
    _lastEmails = [[NSMutableArray alloc]initWithCapacity:folderCount];
    
    for (int index = 0; index < folderCount ; index++) {
        [_lastEmails addObject:[[Mail alloc]init]];
    }
    
    self.currentFolderIndex = [[AppSettings lastFolderIndex] integerValue];
    
    if ( [self.imapFolders isUserFolder:self.currentFolderIndex] ) {
        
#warning check this code
        if (self.currentFolderIndex >= [self.imapFolders userFoldersCount]) {
            self.currentFolderIndex = FolderTypeInbox;
            [self.imapFolders setCurrentFolder:FolderTypeInbox];
//            self.currentFolderIdx = [self.user numFolderWithFolder:self.currentFolderType];
        }
        else { // Current Folder Type Index < Number of User Folders
            
            Folder *folder = [self.imapFolders folderAtIndex:self.currentFolderIndex];
            NSString* name = folder.IMAPFolderName;
            
            NSArray* names = [self.user allFoldersDisplayNames];
            for (int i = 0; i < names.count; i++) {
                if ([name isEqualToString:names[i]]) {
                    self.currentFolderIndex = i;
                    break;
                }
            }
        }
    } else { // Current Folder Type is a System Folder

//        self.currentFolderIndex = self.currentFolderindex;
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
                if (error.code == 9000) {
                    [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.connecting_error", @"Connection error")  dismissAfter:2.0 code:2];
                }
                else if (error.code == 9003){
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

-(Folder*)_getCurrentFolder
{
    Accounts *accounts = [Accounts sharedInstance];
    DDAssert(accounts,@"Accounts singleton must exist");
    Account *currentAccount = [accounts currentAccount];
    DDAssert(currentAccount,@"Current Account must exist.");
    Folders *currentAccountFolders = [currentAccount imapFolders];
    DDAssert(currentAccountFolders,@"Current Account Folders must exist");
    Folder *currentFolder = [currentAccountFolders currentFolder];
    DDAssert(currentFolder, @"Current Folder must exist");
    return currentFolder;
}

-(void) setCurrentFolder:(FolderIndex)toFolderIndex
{
    if (self.currentFolderIndex == toFolderIndex) {
        DDLogWarn(@"Same folder");
        return;
    }
    
//    self.currentFolderType = folder;
    self.currentFolderIndex = toFolderIndex;
    _currentFolderFullSyncCompleted = NO;
    _hasLoadedAllLocal = NO;
    _isLoadingMore = NO;
    
    [_localFetchQueue cancelAllOperations];
    
    [AppSettings setLastFolderIndex:@(toFolderIndex)];
    
//    if (folder.type == FolderTypeUser)
    if ( [Folders ])
    {

        Folder *currentFolder = [self _getCurrentFolder];
        
        NSString* name = [NSString stringWithString:currentFolder.IMAPFolderName];
        NSArray* names = [self.user allFoldersDisplayNames];
        for (int i = 0; i < names.count; i++) {
            if ([name isEqualToString:names[i]]) {
                self.currentFolderIdx = i;
                [self refreshCurrentFolder];
                [self localFetchMore:NO];
                return;
            }
        }
    } else { // not a User Folder
        
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
    
    if ((![[email sonID] isEqualToString:@""] & ![[email sonID] isEqualToString:@"0"]) && [_convIDs containsObject:[email sonID]]) {
        
        for (NSUInteger idx = 0; idx < self.allsMails.count; idx++) {
            Conversation* conv = self.allsMails[idx];
            
            if ([[[conv firstMail] sonID] isEqualToString:[email sonID]]) {
                [conv addMail:email];
                [self _addCon:idx toFoldersContent:conv.folders];
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

-(void) _addCon:(NSUInteger)idx toFoldersContent:(NSSet*)folderSet
{
    DDAssert(!self.user.isAll, @"Should not be called by all Accounts");
    
    for (NSNumber* Fuser in folderSet) { // TODO: AJC not finished
        [self _addIdx:idx inArray:decodeFolderTypeWith([Fuser integerValue])];
    }
}

-(NSMutableIndexSet*) _mailIndeciesForFolder:(FolderIndex)folderIndex
{
    Folder *folder = [self.imapFolders folderAtIndex:folderIndex];
    DDAssert(folder,@"Bad folder index %d",folderIndex);
    
    return folder.mailIndecies;
}

-(void) _addIdx:(NSUInteger)idx inArray:(FolderIndex)folderIndex
{
    DDAssert(!self.user.isAll, @"Should not be called by all Accounts");
    
    NSMutableIndexSet* folderMailIndecies = [self _mailIndeciesForFolder:folderIndex];
    
    if (![folderMailIndecies containsIndex:idx]) {
        
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
    DDAssert(!self.user.isAll, @"Should not be called by all Accounts");
    
    CCMMutableConversationArray* tmp = [self.allsMails mutableCopy];
    NSUInteger index = [tmp indexOfObject:conv];
    
    if (index == NSNotFound) {
        [self.allsMails addObject:conv];
        index  = self.allsMails.count - 1;
        
        if (![conv.folders containsObject:@(FolderTypeDeleted)] &&
            ![conv.folders containsObject:@(FolderTypeSpam)] &&
            ![conv.folders containsObject:@(FolderTypeDrafts)]) {
            
            [self _addIdx:index inArray:CCMFolderTypeAll];
        }
        
        if ([conv isFav]) {
            [self _addIdx:index inArray:CCMFolderTypeFavoris];
        }
        
        [self _addCon:index toFoldersContent:conv.folders];
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

-(NSMutableArray*) getConversationsForFolder:(FolderIndex)folderIndex
{
    DDAssert(!self.user.isAll, @"Should not be called by all Accounts");
    
    NSMutableIndexSet* set = [[self _mailIndeciesForFolder:folderIndex] mutableCopy];
    
    NSMutableArray* res = [NSMutableArray arrayWithCapacity:[set count]];
    CCMMutableConversationArray* _aMS = [self.allsMails mutableCopy];
    
    [_aMS enumerateObjectsAtIndexes:set
                            options:0
                         usingBlock:^(Conversation* obj, NSUInteger idx, BOOL* stop){
                             [res addObject:[ConversationIndex initWithIndex:idx user:self.user]];
                         }];
    
    
    return res;
    
}

#pragma mark - Drafting

-(void) sendDraft:(Draft*)draft to:(NSArray *)toPersonIDs
{
    DDAssert(!self.user.isAll, @"Should not be called by all Accounts");
    
    MCOMailProvider* accountProvider = [[MCOMailProvidersManager sharedManager] providerForIdentifier:self.user.identifier];
    
    NSArray* smtpServicesArray = accountProvider.smtpServices;
    MCONetService* service = smtpServicesArray[0];
    
    MCOSMTPSession* smtpSession = [[MCOSMTPSession alloc] init];
    smtpSession.hostname = service.hostname ;
    smtpSession.port = service.port;
    smtpSession.username = self.user.username;
    if (self.user.isUsingOAuth) {
        smtpSession.OAuth2Token = self.user.oAuth;
        smtpSession.authType = MCOAuthTypeXOAuth2;
        smtpSession.connectionType = MCOConnectionTypeStartTLS;
    }
    else {
        smtpSession.password = self.user.password;
        smtpSession.connectionType = service.connectionType;
    }
    
    DDLogInfo(@"Sending with:%@ port:%u authType:%ld", smtpSession.hostname, smtpSession.port, (long)MCOAuthTypeSASLNone);
    //[CCMStatus showStatus:NSLocalizedString(@"status-bar-message.sending-email", @"Sending email...") dismissAfter:2 code:0];
    
    UserSettings* user = [AppSettings userWithNum:draft.accountNum];
    
    NSMutableArray* to = [[NSMutableArray alloc] init];
    
    for (NSNumber* personID in toPersonIDs) {
        Person* p = [[Persons sharedInstance] getPersonWithID:[personID intValue]];
        MCOAddress* newAddress = [MCOAddress addressWithMailbox:p.email];
        [to addObject:newAddress];
    }
    
    NSString* rfc822DataFilename = [draft rfc822DataTo:toPersonIDs];
    
    MCOSMTPSendOperation * op = [smtpSession sendOperationWithContentsOfFile:rfc822DataFilename
                                                                        from:[MCOAddress addressWithDisplayName:[user name] mailbox:[user username]]
                                                                  recipients:to];
    
    op.progress = ^(unsigned int current, unsigned int maximum){
        [(InViewController*)[[ViewController mainVC] topIVC] setSGProgressPercentage:(MAX(10 ,(long)(current*100)/maximum)) andTintColor:self.user.color];
    };
    
    
    self.isSendingOut++;

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        [self beginBackgroundUpdateTask];
        
        [op start:^(NSError* error) {
            
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
                
                DDLogError(@"%@ Error sending email:%@", self.user.username, error);
                
                if (smtpServicesArray.count == 2) {
                    
                    [(InViewController*)[[ViewController mainVC] topIVC] setSGProgressPercentage:50 andTintColor:self.user.color];

                    [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.sending-email", @"Sending email...") dismissAfter:2 code:0];
                    
                    MCOSMTPSession* smtpSessionAux = [[MCOSMTPSession alloc] init];
                    
                    MCONetService* serviceAux = smtpServicesArray[1];
                    smtpSessionAux.hostname = serviceAux.hostname ;
                    smtpSessionAux.port = serviceAux.port;
                    smtpSessionAux.connectionType = serviceAux.connectionType;
                    smtpSessionAux.username = self.user.username;
                    smtpSessionAux.password = self.user.password;
                    
                    DDLogInfo(@"Sending with:%@ port:%u authType:%ld", smtpSessionAux.hostname, smtpSessionAux.port, (long)MCOAuthTypeSASLNone);
                    
                    MCOSMTPSendOperation * op = [smtpSession sendOperationWithContentsOfFile:rfc822DataFilename
                                                                                        from:[MCOAddress addressWithDisplayName:[user name] mailbox:[user username]]
                                                                                  recipients:to];
                    
                    op.progress = ^(unsigned int current, unsigned int maximum){
                        
#warning look - View Controller's being called inside this model object!
                        
                        [(InViewController*)[[ViewController mainVC] topIVC] setSGProgressPercentage:(MAX(10 ,(long)(current*100)/maximum)) andTintColor:self.user.color];
                    };
                    
                    [op start:^(NSError* error) {
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
                            [(InViewController*)[[ViewController mainVC] topIVC] finishSGProgress];
                            DDLogError(@"%@ Error sending email:%@", self.user.username, error);
                            [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.error-sending", @"Error: Email not sent.") dismissAfter:2 code:2];
                            self.isSendingOut--;
                            [self endBackgroundUpdateTask];
                        }
                        else {
                            [(InViewController*)[[ViewController mainVC] topIVC] finishSGProgress];
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
                    [(InViewController*)[[ViewController mainVC] topIVC] finishSGProgress];
                    [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.error-sending", @"Error: Email not sent.") dismissAfter:2 code:2];
                    self.isSendingOut--;
                    [self endBackgroundUpdateTask];
                }
            }
            else {
                [(InViewController*)[[ViewController mainVC] topIVC] finishSGProgress];
                DDLogInfo(@"%@ Successfully sent email!", self.user.username);
                [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.email-sent", @"Email sent.")  dismissAfter:2 code:1];
                [draft deleteOutboxDraft];
                [draft appendToSent:rfc822DataFilename];
                self.isSendingOut--;
                [self endBackgroundUpdateTask];
            }
        }];
    });
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
    CCMFolderType folderTo = CCMFolderTypeDeleted;
    
    [self moveConversation:conversation from:folderFrom to:folderTo updateUI:YES];
}

-(void) sendOutboxs
{
    if (self.isSendingOut == 0) {
    NSFileManager *filemgr = [NSFileManager defaultManager];
    NSString *draftPath = @"outbox";
    
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
        
        if (draft.toPersons.count == 0) {
            [draft deleteOutboxDraft];
            [draft save];
            continue;
        }
        
        if (draft.accountNum == self.user.accountNum) {
            NSMutableArray* toPIDs = [[NSMutableArray alloc] initWithCapacity:draft.toPersons.count];
            Persons* ps = [Persons sharedInstance];
            for (NSString* email in draft.toPersons) {
                [toPIDs addObject:@([ps indexForEmail:email])];
            }
            
            [self sendDraft:draft to:toPIDs];
        }
    }
    }
}

#warning There is a lot of RW going on in this function, just to determine the number of mail msgs in the Outbox.
-(NSInteger) outBoxNb
{
    NSFileManager *filemgr = [NSFileManager defaultManager];
    NSString *draftPath = @"outbox";
    
    NSString *documentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString* folderPath = [documentsDirectory stringByAppendingPathComponent:draftPath];
    
    if (![filemgr fileExistsAtPath:folderPath]) {
        [filemgr createDirectoryAtPath:folderPath withIntermediateDirectories:NO attributes:nil error:nil];
    }
    
    NSArray *dirFiles = [filemgr contentsOfDirectoryAtPath:folderPath error:nil];
    
    NSInteger count = 0;
    
    for (NSString* fileName in dirFiles) {
        NSString* localPath = [folderPath stringByAppendingPathComponent:fileName];
        Draft* draft = [NSKeyedUnarchiver unarchiveObjectWithFile:localPath];
        
        if (!draft.msgID) {
            draft.msgID = @"0";
        }
        
        if (draft.accountNum == self.user.accountNum) {
            count++;
        }
    }
    
    return count;
}

#pragma mark - Move

-(BOOL) moveConversationAtIndex:(NSInteger)index from:(FolderIndex)folderFrom to:(FolderIndex)folderTo updateUI:(BOOL)updateUI
{
    DDLogInfo(@"%@ Main Thread",([NSThread isMainThread]?@"Is":@"Isn't"));
    
    DDAssert(!self.user.isAll, @"Should not be called by all Accounts");
    
    Conversation *conv = [self.allsMails objectAtIndex:index];
    return [self moveConversation:conv from:folderFrom to:folderTo updateUI:updateUI];
}

-(BOOL) moveConversation:(Conversation*)conversation from:(FolderIndex)folderFrom to:(FolderIndex)folderTo updateUI:(BOOL)updateUI
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
        case FolderTypeSent:
            remove = (folderTo.type == FolderTypeDeleted);
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
    
    if (remove) {
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
    
    return remove;
}

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
             [self insertRows:email];
         }
         error:^(NSError* error) {
             
             if (error.code != 9002 && error.code != 9001) {
                 [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.connecting_error", @"Connection error") dismissAfter:2 code:2];
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
    DDLogDebug(@"-[Accounts doLoadServer]");
    
    if (self.user.isDeleted) {
        DDLogDebug(@"\tUser is deleted, doLoadServer returning.");
        return;
    }
    
    if (![ImapSync canFullSync]){
        DDLogDebug(@"\tCannot Full Sync, doLoadServer returning.");
        return;
    }
    
    if (!_isSyncing && !_isSyncingCurrentFolder) {
        DDLogDebug(@"\tNOT syncing AND NOT syncing current folder");
        _isSyncing = YES;
        [[[[SyncManager getSingleton] syncFoldersUser:self.user] deliverOn:[RACScheduler scheduler]]
         subscribeNext:^(Mail* email) {
             //[self insertRows:email];
         }
         error:^(NSError* error) {
             _isSyncing = NO;
             
             
             if (error.code != 9002 && error.code != 9001) {
                 DDLogError(@"\tSyncing error, error code = %ld",error.code);
                 DDLogError(@"\t\tError description = \'%@\"", error.localizedDescription);
             }
             
             if ([Accounts sharedInstance].currentAccountIdx == self.idx) {
                 if (error.code == 9001) {
                     DDLogDebug(@"\tError code 9001, ALLLLLL Synced!?");
                 }
                 else if (error.code == 9002) {
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
    if (self.user.isDeleted) {
        return;
    }
    
    if (!self.user.isAll && self.allsMails.count != 0 && !_runningUpToDateTest) {
        _runningUpToDateTest = YES;

        // Make a Mutable copy of the Current Folder Mail Indecies
        NSMutableIndexSet* currentFolderMailIndecies =
            [[self _mailIndeciesForFolder:self.currentFolderType] mutableCopy];
        NSMutableArray* res = [NSMutableArray arrayWithCapacity:[currentFolderMailIndecies count]];
        
        // Make a Mutable copy of the All Mails array
        NSArray* _aMS = [self.allsMails mutableCopy];
        
        [_aMS enumerateObjectsAtIndexes:currentFolderMailIndecies
                                options:0
                             usingBlock:^(id obj, NSUInteger idx, BOOL* stop){
                                 [res addObject:obj];
                             }];
        
        // Make a Mutable copy of the All Mail System Folder Mail Indecies
        NSMutableIndexSet* allMailSystemFolderMailIndecies = [self.systemFoldersContent[FolderTypeAll] mutableCopy];
        NSMutableArray* resAll = [NSMutableArray arrayWithCapacity:[allMailSystemFolderMailIndecies count]];
        
        ImapSync *imapServices = [ImapSync sharedServices:self.user];
        
        [imapServices runUpToDateTest:res
                          folderIndex:self.currentFolderIdx
                            completed:^(NSArray *dels, NSArray *ups, NSArray* days) {
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
                
                NSInteger folderNumber = [self.user numFolderWithFolder:CCMFolderTypeAll];
                [imapServices runUpToDateTest:resAll
                                  folderIndex:folderNumber
                                    completed:^(NSArray *dels, NSArray *ups, NSArray* days) {
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

-(void) deliverDelete:(NSArray*)emails fromFolder:(FolderIndex)folderFrom
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


-(BOOL) deleteIndex:(NSInteger)index fromFolder:(FolderIndex)folderFrom
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
    
    /*
     * If the User is for the "All" view, 
     * then refresh the current folder for all accounts that
     * are not part of an All user.
     */
    if (self.user.isAll) {
        for (Account* acnt in [[Accounts sharedInstance] accounts]) {
            if (!acnt.user.isAll) {
                [acnt refreshCurrentFolder];  // Recursive call
            }
        }
        return;
    }
    
    if (self.user.isDeleted) {
        return;
    }
    
    if ([ImapSync sharedServices:self.user].connected == FALSE) {
        [self connect];
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [self.mailListSubscriber serverSearchDone:YES];
        }];
        return;
    }
    
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
         
         if (error.code != 9002 && error.code != 9001) {
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
         DDLogError(@"Error: %@", error.localizedDescription);
         _isSyncingCurrentFolder = NO;
         if (error.code == 9002) {
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
