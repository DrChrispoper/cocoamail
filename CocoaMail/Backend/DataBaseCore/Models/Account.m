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

// MARK: - ********** Account **********

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

// All Mail Conversations for this Account
@property (nonatomic, strong) NSMutableArray<Conversation*>* allConversations;

// All Conversation ID's, used only(?) in InsertRows() function.
@property (nonatomic, strong) NSMutableSet* convIDs;

// User Folders Mail Index Sets
@property (nonatomic, strong) NSArray<NSMutableIndexSet*>* userFoldersContent;

// System Folders Mail Index Sets
@property (nonatomic, strong) NSArray<NSMutableIndexSet*>* systemFoldersContent;

@end

@implementation Account

+(instancetype) emptyAccount
{
    Account* a = [[Account alloc] init];
    
    // MARK: We should collect statistics on how many messages most people have
    a.allConversations = [NSMutableArray arrayWithCapacity:500];
    
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
    [_localFetchQueue setMaxConcurrentOperationCount:1]; // make queue non-concurrent
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
    
    const NSInteger userFolderCount = self.userFolders.count;
    
    NSMutableArray* arrayU = [[NSMutableArray alloc] initWithCapacity:userFolderCount];
    for (int i = 0; i < userFolderCount; i++) {
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
            // Set Current Folder Index to the index in the All Folder Names of the Current Folder
            NSString* name = self.userFolders[self.currentFolderType.idx][0];
            NSArray* names = [self.user allFoldersDisplayNames];
            for (int i = 0; i < names.count; i++) {
                if ([name isEqualToString:names[i]]) {
                    self.currentFolderIdx = i;
                    break;
                }
            }
        }
    } else { // Folder Type is Important/System Folder
        self.currentFolderIdx = [self.user numFolderWithFolder:self.currentFolderType];
    }
}

-(void) connect
{
    DDLogInfo(@"ENTERED");
    
    if (!self.user.isAll && self.user.isDeleted) {
        DDLogWarn(@"User is not ALL and IS DELETED");
        return;
    }
    
    if (self.user.isAll) {
        DDLogInfo(@"User.isAll = TRUE");
        
        NSArray<Account*>* allAccounts = [[Accounts sharedInstance] accounts];
        for (NSInteger acntIndex = 0; acntIndex < allAccounts.count;acntIndex++) {
            Account *acnt = allAccounts[acntIndex];
            
            DDLogInfo(@"Evaluate Accounts[%ld]:",(long)acntIndex);
            
            if (!acnt.user.isAll && !acnt.isConnected) {
                
                DDLogInfo(@"Not All Account AND Is Not Connected.");
                
                [[ImapSync doLogin:acnt.user] subscribeError:^(NSError *error) {
                    DDLogError(@"Account[%ld] connection failed, error = %@",(long)acntIndex,error);
                } completed:^{
                    DDLogInfo(@"Account[%ld] connection success.",(long)acntIndex);
                }];
                
                break;
            }
            else {
                DDLogInfo(@"Is All Account OR Is Connected");
            }
        }
    }
    else {
        DDLogInfo(@"User.isAll == FALSE; CALLING doLogin:%@",self.user.username);
        
        [[ImapSync doLogin:self.user] subscribeError:^(NSError *error) {
            
            DDLogError(@"doLogin:\"%@\" failed with error = %@",self.user.username,error);
            
            if ([Accounts sharedInstance].canUI) {
                
                if (error.code == CCMConnectionError) {
                    DDLogError(@"Login Connection Error (%@), displaying Status UI",@(error.code));
                    
                    [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.connecting_error", @"Connection error")  dismissAfter:2.0 code:2];
                }
                else if (error.code == CCMCredentialsError){
                    DDLogError(@"Login Credentials Error (%@), displaying Status UI",@(error.code));
                    
                    [CCMStatus showStatus:NSLocalizedString(@"add-account-view.error.wrong-credentials", @"Credentials")  dismissAfter:2.0 code:2];
                }
                else {
                    DDLogError(@"Uknown Login Error, displaying Status UI");
                    
                    [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.connecting_error", @"Connection error")  dismissAfter:2.0 code:2];
                }
            }
        } completed:^{
            DDLogInfo(@"doLogin:%@ Succeded",self.user.username);
        }];
    }
}

-(BOOL) isConnected
{
    return [ImapSync sharedServices:self.user].connected;
}

-(void) setConnected
{
    DDAssert(!self.user.isAll, @"Should not be called by all Accounts");
    
    [ImapSync runInboxUnread:self.user completed:^{}];
    
    [self refreshCurrentFolder];
    
    [self sendOutboxs];
    
    if (kisActiveAccountAll){
        [[Accounts sharedInstance].currentAccount connect];
    }
}



-(void) setCurrentFolder:(CCMFolderType)folder
{
    DDLogInfo(@"%@",[self stringWithFolderType:folder]);
    
    if (encodeFolderTypeWith(self.currentFolderType) == encodeFolderTypeWith(folder)) {
        NSString *folderTypeName = [self baseFolderType:folder.type];
        DDLogWarn(@"setCurrentFolder: Current Folder is unchanged, do nothing. Type=\"%@\" Index=%@",folderTypeName,@(folder.idx));
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
    } else { // is a Special folder
        
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

#warning This property is generated every time we call it

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
- (NSArray *)userFolderNames
{
    //Folders Indentation?
    NSArray* allUserFolderNames = [self.user allNonImportantFoldersName];
    
    NSMutableArray* foldersNIndent = [[NSMutableArray alloc]initWithCapacity:allUserFolderNames.count];
    
    NSString *folderPathDelim = self.user.folderPathDelimiter;
    
    DDAssert(folderPathDelim&&folderPathDelim.length>0,@"Folder Path Delimiter must exist");
    
    for (NSString* folderName in allUserFolderNames) {
        [foldersNIndent addObject:@[folderName, @([folderName containsString:folderPathDelim])]];
    }
    
    return foldersNIndent;
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
        DDLogWarn(@"insertRows:(Mail*)mail, but self.user.isDeleted");
        return;
    }
    
    NSString *sonID = [email sonID];
    
    // Andy was debugging non duplicate messages showing as threaded
    //    if ( [email.subject containsString:@"Review blocked"]) {
    //        DDLogInfo(@"Email subj:\"%@\" has son ID \"%@\"",email.subject,sonID);
    //    }
    
    if ( [sonID isEqualToString:@""] ||
        [sonID isEqualToString:@"0"] ||
        ![_convIDs containsObject:sonID] ) {
        
        // No conversation with a matching sonID ...
        [self _addNewConversationWithMail:email];
        
    } else {
        
        // Find the conversation with the matching sonID,
        // and add this mail message to the conversation,
        // and
        for (NSUInteger idx = 0; idx < self.allConversations.count; idx++) {
            Conversation* conv = self.allConversations[idx];
            
            // If the indexed conversation matche's the email sonID
            NSString *firstMailSonID = [[conv firstMail] sonID];
            if ([firstMailSonID isEqualToString:sonID]) {
                
                // Add the mail message to the conversation
                [conv addMail:email];
                
                [self _addCon:idx toFoldersContent:[conv foldersType]];
                
                return; // we match only once (could be break;)
            }
            else {
                DDLogVerbose(@"Coversation's First Mail's Son ID \"%@\" equals given mail Son ID",firstMailSonID);
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
        
        // if the folder passed in is the current folder ....
        if (encodeFolderTypeWith(folderHandle) == encodeFolderTypeWith(self.currentFolderType)) {
            
            //NSMutableDictionary* syncState = [[SyncManager getSingleton] retrieveState:[self.user numFolderWithFolder:self.currentFolderType] accountNum:self.user.accountNum];
            //NSInteger tmpEmailCount = [syncState[@"emailCount"] integerValue];
            
            // if this (current) folder has exactly 20 mail messages ...
            if ( [folderMailIndecies count] == 20) {
                
                // if the current account index is our account index ...
                if ([Accounts sharedInstance].currentAccountIdx == self.idx) {
                    // Then test the current folder for correct messages
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
    
    NSMutableArray<Conversation*>* tmp = [self.allConversations mutableCopy];
    NSUInteger index = [tmp indexOfObject:conv];
    
    if (index == NSNotFound) {
        [self.allConversations addObject:conv];
        index  = self.allConversations.count - 1;
        
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
        Conversation* con = [self.allConversations objectAtIndex:index];
        
        for (Mail* m in conv.mails) {
            [con addMail:m];
        }
    }
    
    return index;
}

#pragma mark - Get Mails

-(NSMutableArray<Conversation*>*) conversations
{
    return self.allConversations;
}

-(Conversation*) getConversationForIndex:(NSUInteger)index
{
    DDAssert(!self.user.isAll, @"Should not be called by all Accounts");
    
    return [self.allConversations objectAtIndex:index];
}

-(NSMutableArray<ConversationIndex*>*) getConversationsForFolder:(CCMFolderType)folderHandle
{
    DDLogInfo(@"CCMFolderType .index=%@ .type=%@",
              @(folderHandle.idx),@(folderHandle.type));
    
    DDAssert(!self.user.isAll, @"Should not be called by all Accounts");
    
    NSMutableIndexSet* conversationIndexSet = [[self _mailIndeciesForFolder:folderHandle] mutableCopy];
    
    NSMutableArray<ConversationIndex *>* conversationsForFolder = [NSMutableArray arrayWithCapacity:[conversationIndexSet count]];
    
    NSMutableArray<Conversation*>* allConversations = [self.allConversations mutableCopy]; // why copy it? It doesn't look like we are going to change it??
    
    [allConversations enumerateObjectsAtIndexes:conversationIndexSet
                                        options:0
                                     usingBlock:^(Conversation* obj, NSUInteger idx, BOOL* stop){
                                         [conversationsForFolder addObject:[ConversationIndex initWithIndex:idx user:self.user]];
                                     }];
    
    // For debugging INBOX
#if (LOG_VERBOSE)
    NSString *folderName = [self.user folderDisplayNameForType:folderHandle];
    if ( [folderName isEqualToString:@"INBOX"] ) {
        DDLogVerbose(@"\"INBOX\" returns: ");
        NSInteger cnum = 0;
        for (ConversationIndex *conversationIndex in conversationsForFolder) {
            Conversation *conversation = [[Accounts sharedInstance] conversationForCI:conversationIndex];
            DDLogVerbose(@"\tConversation %@:",@(cnum));
            cnum++;
            NSInteger mnum = 0;
            for (Mail *msg in conversation.mails) {
                DDLogVerbose(@"\t\tMail %@ subj \"%@\" id \"%@\"",
                             @(mnum),msg.subject,msg.msgID);
                mnum++;
            }
        }
    }
#endif
    
    return conversationsForFolder;  // an array of ConversationIndex, where each contains an index ito Account.allMails
    
}

#pragma mark - Send a single Draft to multiple Person Ds

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
    
    dispatch_queue_t defaultQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    
    dispatch_async( defaultQueue, ^{
        
        DDLogDebug(@"BLOCK START - DISPATCH_QUEUE_PRIORITY_DEFAULT");
        
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
    // if ZERO emails are being sent
    if (self.isSendingOut == 0) {
        
        NSString *outboxFolder = [self _outboxFolderPath];  // creates if not found
        
        NSFileManager *filemgr = [NSFileManager defaultManager];
        
        NSError *error = nil;
        NSArray<NSString *> *outboxFilenames = [filemgr contentsOfDirectoryAtPath:outboxFolder error:&error];
        
        if ( error ){
            DDLogError(@"Error: could not read filenames from outbox folder\"%@\", error = %@.",outboxFolder,error);
        }
        
        for (NSString* fileName in outboxFilenames) {
            
            NSString* localPath = [outboxFolder stringByAppendingPathComponent:fileName];
            
            Draft* draft = [NSKeyedUnarchiver unarchiveObjectWithFile:localPath];
            
            // TODO: msgID is an NSString, therefore does !msgID mean if its NULL?
            if (!draft.msgID) {
                DDLogWarn(@"Draft message hs no Message ID!");
                draft.msgID = @"0";
            }
            
            DDLogInfo(@"Sending Draft (sujb: \"%@\") to %@ Persons",draft.subject,@(draft.toPersons.count));
            
            if (draft.toPersons.count == 0) {
                DDLogWarn(@"Sending to 0 addresses, so delete and (re)save draft file.");
                // TODO: - No TO addresses, so delete the draft file, then save a new version of the draft file.  Huh?
                [draft deleteOutboxDraft];      // Delete the Outbox Draft file
                [draft saveToDraftsFolder];     // Save the Outbox Draft to its file
                continue;   // next draft file
            }
            
            if (draft.accountNum == self.user.accountNum) {
                
                // create an array of Person ID's from the toPersons array
                NSMutableArray* toPIDs = [[NSMutableArray alloc] initWithCapacity:draft.toPersons.count];
                Persons* ps = [Persons sharedInstance];
                for (NSString* email in draft.toPersons) {
                    [toPIDs addObject:@([ps indexForEmail:email])];
                }
                
                // Send this draft to the PIDs
                [self sendDraft:draft to:toPIDs];
                
            } else {
                DDLogWarn(@"Draft does not belong to this account (i.e. draft acct num %@ doesn't match UserSettings acct num %@)",
                          @(draft.accountNum),@(self.user.accountNum));
            }
        }
    }
    else {
        DDLogInfo(@"self.isSendingOut != 0, do nothing.");
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
    
    Conversation *conv = [self.allConversations objectAtIndex:index];
    return [self moveConversation:conv from:folderFrom to:folderTo updateUI:updateUI];
}

#pragma mark - Move Conversation from Folder to Folder

-(BOOL) moveConversation:(Conversation*)conversation from:(CCMFolderType)folderFrom to:(CCMFolderType)folderTo updateUI:(BOOL)updateUI
{
    DDLogInfo(@"%@ Main Thread",([NSThread isMainThread]?@"Is":@"Isn't"));
    
    // Cannot move a converstaion from the All Mails folder
    DDAssert(!self.user.isAll, @"Should not be called by all Accounts");
    
    NSMutableArray<Conversation*>* tmp = [self.allConversations mutableCopy];
    NSUInteger idx = [tmp indexOfObject:conversation];
    
    if (idx == NSNotFound) {
        DDLogError(@"Conversation with subject \"%@\" not found.",
                   [conversation firstMail].subject);
        return FALSE;
    }
    
    NSMutableIndexSet* toFolderMailIndecies = [self _mailIndeciesForFolder:folderTo];
    
#warning Someday this information should be stored in Folder Type classes
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
            DDLogError(@"move from this folder not implemented (From Folder Type = %ld)",(unsigned long)folderFrom.type);
            
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
    NSUInteger idx = [self.allConversations indexOfObject:conversation];
    
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
    
    SyncManager *sm = [SyncManager getSingleton];
    
    if (!self.user.isAll) {
        if ([self.user numFolderWithFolder:CCMFolderTypeFavoris] != [self.user numFolderWithFolder:CCMFolderTypeAll]) {
            
            NSDictionary *syncStates = [sm retrieveState:[self.user numFolderWithFolder:CCMFolderTypeFavoris] accountNum:self.user.accountNum];
            
            count = [syncStates[kFolderStateEmailCountKey] integerValue];
        }
        else {
            count = [self getConversationsForFolder:CCMFolderTypeFavoris].count;
        }
    }
    else {
        for (Account* a in [Accounts sharedInstance].accounts) {
            if (!a.user.isAll) {
                if ([self.user numFolderWithFolder:CCMFolderTypeFavoris] != [self.user numFolderWithFolder:CCMFolderTypeAll]) {
                    
                    NSDictionary *syncStates = [sm retrieveState:[self.user numFolderWithFolder:CCMFolderTypeFavoris] accountNum:a.user.accountNum];
                    
                    count += [syncStates[kFolderStateEmailCountKey] integerValue];
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
    
    SyncManager *syncManager = [SyncManager getSingleton];
    
    if (!self.user.isAll) {
        
        NSInteger folderNum = [self.user numFolderWithFolder:CCMFolderTypeDrafts];
        
        NSDictionary *folderStates = [syncManager retrieveState:folderNum accountNum:self.user.accountNum];
        
        count = [folderStates[kFolderStateEmailCountKey] integerValue];
    }
    else {
        for (Account* a in [Accounts sharedInstance].accounts) {
            
            if (!a.user.isAll) {
                
                NSInteger folderNum = [a.user numFolderWithFolder:CCMFolderTypeDrafts];
                
                NSDictionary *folderStates = [syncManager retrieveState:folderNum accountNum:a.user.accountNum];
                
                count += [folderStates[kFolderStateEmailCountKey] integerValue];
            }
        }
    }
    
    return count;
}

#pragma mark - Fetch Data

// Refresh contents of IMAP System Folders
-(void) importantFoldersRefresh:(NSInteger)pFolder
{
    DDLogInfo(@"ENTERED, folder=%ld",(long)pFolder);
    
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
    DDLogInfo(@"ENTERED");
    
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
                     [self doLoadServer]; // recursion
                 }
             }
         }
         completed:^{
             DDLogDebug(@"\tSyncing completed.");
             _isSyncing = NO;
             if ([Accounts sharedInstance].currentAccountIdx == self.idx) {
                 DDLogDebug(@"\tCalling self recursively");
                 [self doLoadServer];  // recursion
             }
         }];
    }
}

-(void) runTestData
{
    DDLogInfo(@"ENTERED");
    
    if (self.user.isDeleted) {
        DDLogDebug(@"User is Deleted, DO NOTHING.");
        return;
    }
    
    if ( self.user.isAll ) {
        DDLogDebug(@"User is All, DO NOTHING.");
        return;
    }
    
    if ( self.allConversations.count == 0 ) {
        DDLogDebug(@"No Conversations, DO NOTHING.");
        return;
    }
    
    if ( _runningUpToDateTest ) {
        DDLogDebug(@"Already running Up To Date test, DO NOTHING.");
        return;
    }
    
    _runningUpToDateTest = YES;
    
    NSArray<Conversation*>* allConversations = self.allConversations;
    
    NSIndexSet* currentFolderMailIndecies = [self _mailIndeciesForFolder:self.currentFolderType];
    
    NSMutableArray* resultingFolderMail = [NSMutableArray arrayWithCapacity:[currentFolderMailIndecies count]];
    
    DDLogInfo(@"Folder %@ has %@ mails.",[self folderDescription:self.currentFolderType],@(currentFolderMailIndecies.count));
    
    // Create an array (resultingFolderMail) of all the conversations indexed by the current folder mail indecies
    [allConversations enumerateObjectsAtIndexes:currentFolderMailIndecies
                                        options:0
                                     usingBlock:^(id obj, NSUInteger idx, BOOL* stop){
                                         [resultingFolderMail addObject:obj];
                                     }];
    
    
    [[ImapSync sharedServices:self.user] runUpToDateTest:resultingFolderMail folderIndex:self.currentFolderIdx
                                               completed:^(NSArray *dels, NSArray *ups, NSArray* days) {
                                                   
                                                   //[self.mailListSubscriber removeConversationList:nil];
                                                   
                                                   [self.mailListSubscriber updateDays:days];
                                                   
                                                   
#warning - is this correct?  The next two lines seem to conflict.
                                                   
                                                   if (self.currentFolderType.type != FolderTypeAll) {
                                                       
                                                       NSIndexSet* allFolderMailIndecies = self.systemFoldersContent[FolderTypeAll];
                                                       
                                                       NSMutableArray* resultingAllFolderMail = [NSMutableArray arrayWithCapacity:[allFolderMailIndecies count]];
                                                       
                                                       [allConversations enumerateObjectsAtIndexes:allFolderMailIndecies
                                                                                           options:0
                                                                                        usingBlock:^(id obj, NSUInteger idx, BOOL* stop){
                                                                                            [resultingAllFolderMail addObject:obj];
                                                                                        }];
                                                       
                                                       if (![ImapSync canFullSync]){
                                                           _runningUpToDateTest = NO;
                                                           return;
                                                       }
                                                       
                                                       [[ImapSync sharedServices:self.user] runUpToDateTest:resultingAllFolderMail folderIndex:[self.user numFolderWithFolder:CCMFolderTypeAll] completed:^(NSArray *dels, NSArray *ups, NSArray* days) {
                                                           
                                                           _runningUpToDateTest = NO;
                                                           
                                                           [self.mailListSubscriber updateDays:days];
                                                           
                                                           //[self.mailListSubscriber removeConversationList:nil];
                                                       }];
                                                   }
                                                   
                                                   _runningUpToDateTest = NO;
                                                   
                                               }];
    
}

-(void) runMoreTestData
{
    if (self.user.isDeleted) {
        return;
    }
    
    if (!self.user.isAll && self.allConversations.count != 0) {
        
        NSMutableIndexSet* currentFolderMailIndecies =
        [[self _mailIndeciesForFolder:self.currentFolderType] mutableCopy];
        
        NSMutableArray* res = [NSMutableArray arrayWithCapacity:[currentFolderMailIndecies count]];
        
        NSArray* _aMS = [self.allConversations mutableCopy];
        
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
        
        for (Conversation* conv in self.allConversations) {
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
        
        for (; !found && index < self.allConversations.count; index++) {
            for (Mail* m in ((Conversation* )self.allConversations[index]).mails) {
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
    DDLogInfo(@"ENTERED");
    
    if (self.user.isAll) {
        DDLogDebug(@"\tWe are ALL folders");
        for (Account* a in [[Accounts sharedInstance] accounts]) {
            if (!a.user.isAll) {
                [a refreshCurrentFolder];
            }
        }
        DDLogDebug(@"\tAll Folders refreshed, returing");
        return;
    }
    
    if (self.user.isDeleted) {
        DDLogDebug(@"\tFolder is Deleted, returning");
        return;
    }
    
    if ([ImapSync sharedServices:self.user].connected == FALSE) {
        [self connect];
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [self.mailListSubscriber serverSearchDone:YES];
        }];
        DDLogDebug(@"\tIMAP Services not connected, connecting and returning");
        return;
    }
    
    NSInteger __block new = 0;
    
    [self.mailListSubscriber serverSearchDone:NO];
    
    [self runTestData];
    
    DDLogDebug(@"\tRefresh");
    
    RACSignal *signal = [[SyncManager getSingleton] syncActiveFolderFromStart:YES
                                                                         user:self.user];
    
    [[signal deliverOn:
      [RACScheduler schedulerWithPriority:RACSchedulerPriorityBackground]]
     
     subscribeNext:^(Mail* email) {
         
         DDLogDebug(@"\tsubscribeNext(Mail*)");
         
         new++;
         [self insertRows:email];
     }
     error:^(NSError* error) {
         
         DDLogError(@"\tError = %@",error);
         
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
     }
     completed:^{
         
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
    DDLogInfo(@"ENTERED");
    
    if (self.user.isDeleted) {
        DDLogWarn(@"\tReturning because self.user.isDeleted is FALSE");
        return;
    }
    
    if (![ImapSync canFullSync]){
        DDLogWarn(@"\tReturning because [ImapSync canFullSyc] == FALSE");
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
             [self syncCurrentFolder];  // Recursive!
         }
     }];
}

#pragma mark - Account description

-(NSString *)description
{
    NSMutableString *desc = [NSMutableString string];
    
    [desc appendFormat:@"\n *** Account Description (Index - %ld) ****\n",(long)[self idx]];
    [desc appendString:@"\n"];
    
    // UserSettings
    [desc appendFormat:@"\n * Account.UserSettings:\n%@",[[self user] description]];
    [desc appendString:@"\n\n"];
    
    [desc appendString:@"\n * System Folders:\n"];
    [desc appendString:[self folderSetDescription:@"System" accountFolders:self.systemFoldersContent folderNames:self.systemFolderNames]];
    
    [desc appendString:@"\n * User Folders:\n"];
    [desc appendString:[self folderSetDescription:@"User" accountFolders:self.userFoldersContent folderNames:self.userFolders]];
    
    [desc appendString:@"\n * Other Account properties\n"];
    [desc appendFormat:@"Current-Folder Index = %ld\n",(long)self.currentFolderIdx];
    [desc appendFormat:@"Current-Folder Type  = %@\n",[self currentFolderTypeValue]];
    [desc appendFormat:@"Is-Sending-Out count = %ld\n",(long)self.isSendingOut];
    [desc appendString:@"\n"];
    
    [desc appendFormat:@"\n * Account.Person:\n%@\n",[[self person] description]];
    
    //    @property (nonatomic, weak) id<MailListDelegate> mailListSubscriber;
    
    [desc appendString:@"\n *** End Account Description ***\n"];
    
    return desc;
}

-(NSString *)folderSetDescription:(NSString *)folderType accountFolders:(NSArray *)folderArray folderNames:(NSArray *)folderNames
{
    NSMutableString *desc = [NSMutableString string];
    
    NSUInteger folderCount = [folderArray count];
    
    [desc appendFormat:@"%@ Folders count = %ld\n",folderType, (unsigned long)folderCount];
    
    for (NSUInteger folderIndex = 0; folderIndex < folderCount; folderIndex++) {
        
        NSString *folderName = folderNames[folderIndex];
        
        NSMutableIndexSet *mailIndecies = folderArray[folderIndex];
        
        NSUInteger mailCount = [mailIndecies count];
        
        [desc appendFormat:@"\t%@ Folder[%lu] \"%@\" has %lu mail messages\n",
         folderType,(unsigned long)folderIndex,
         folderName,(unsigned long)mailCount];
        
        //        if ( [folderName isEqualToString:@"Inbox"] ) {
        //            
        //        }
    }
    return desc;
}

-(NSString *)stringWithFolderType:(CCMFolderType)folder
{
    return [NSString stringWithFormat:@"CCMFolderType .type=\"%@\" .index=%@",[self baseFolderType:folder.type],@(folder.idx)];
}

-(NSString *)folderDescription:(CCMFolderType)folderType
{
    if ( folderType.type == FolderTypeUser ) {
        return [NSString stringWithFormat:@"User Folder %@",@(folderType.idx)];
    }
    return [self baseFolderType:folderType.type];
}

-(NSString *)currentFolderTypeValue
{
    return [self baseFolderType:self.currentFolderType.type];
}

-(NSString*)baseFolderType:(BaseFolderType)folderType
{
    NSString *currFolderType = @"";
    
    switch (folderType) {
        case FolderTypeInbox:
            currFolderType = @"INBOX";
            break;
        case FolderTypeFavoris:
            currFolderType = @"Favorite (flagged)";
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
        case FolderTypeUser:
            currFolderType = @"User";
            break;
        default:
            currFolderType = [NSString stringWithFormat:@"Unknown BaseFolderType (%ld)",(long)folderType];
            break;
    }
    return currFolderType;
}
@end
