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

// All Conversation ID's, used only(?) in insertIntoConversation() function.
@property (nonatomic, strong) NSMutableSet<NSString*>* conversationIDs;

// User Folders Mail Index Sets
@property (nonatomic, strong) NSArray<NSMutableIndexSet*>* userFoldersContent;

// System Folders Mail Index Sets
@property (nonatomic, strong) NSArray<NSMutableIndexSet*>* systemFoldersContent;

@end

@implementation Account

+(instancetype) emptyAccount
{
    Account* newAccount = [[Account alloc] init];
    
    // MARK: We should collect statistics on how many messages most people have
    newAccount.allConversations = [NSMutableArray arrayWithCapacity:500];
    
    newAccount.conversationIDs = [NSMutableSet setWithCapacity:500];
    
    return newAccount;
}

-(NSInteger) idx
{
    return (NSInteger)[AppSettings indexForAccountNum:(NSInteger)_user.accountNum];
}

-(UserSettings*) user
{
    return _user;
}

-(void) setNewUser:(UserSettings*)user
{
    _user = user;
}

-(NSUInteger)userFolderCount
{
    return self.userFolders.count;
}
-(NSString*)userFolderNameAtIndex:(NSUInteger)folderIndex
{
    return self.userFolders[folderIndex][0];
}
-(BOOL)userFolderAtIndexContainsPathDelimiter:(NSUInteger)folderIndex
{
    return [self.userFolders[folderIndex][1] boolValue];
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
    NSMutableArray* array = [[NSMutableArray alloc] initWithCapacity:kImportantFolderTypeCount];
    
    for (int i = 0; i < kImportantFolderTypeCount; i++) {
        [array addObject:[[NSMutableIndexSet alloc] init]];
    }
    self.systemFoldersContent = array;
    
    //
    // Initialize the "User" IMAP Folders
    //
    
    const NSUInteger userFolderCount = self.userFolders.count;
    
    NSMutableArray* arrayU = [[NSMutableArray alloc] initWithCapacity:userFolderCount];
    for (NSUInteger i = 0; i < userFolderCount; i++) {
        [arrayU addObject:[[NSMutableIndexSet alloc] init]];
    }
    
    self.userFoldersContent = arrayU;
    
    
    //Including Non selectable
    NSUInteger folderCount = [[SyncManager getSingleton] folderCount:(NSInteger)self.user.accountNum];
    
    _lastEmails = [[NSMutableArray alloc]initWithCapacity:folderCount];
    
    for (NSUInteger index = 0; index < folderCount ; index++) {
        [_lastEmails addObject:[[Mail alloc]init]];
    }
    
    NSNumber *lastFolderIndex = [AppSettings lastFolderIndex];
    if ( lastFolderIndex == nil ) {
        DDLogInfo(@"Last Folder Index not found, setting folder to Inbox.");
        self.currentFolderType = inboxFolderType(); // we could not find a previous folder, so start in Inbox
    }
    else {        
        NSInteger lastFolderValue = [lastFolderIndex integerValue];
        self.currentFolderType = decodeFolderTypeWith(lastFolderValue);
    }
    
    if (self.currentFolderType.type == FolderTypeUser) {
        if ((NSUInteger)self.currentFolderType.idx >= self.userFolders.count) {
            self.currentFolderType = CCMFolderTypeInbox;
            self.currentFolderIdx = [self.user numFolderWithFolder:self.currentFolderType];
        }
        else {
            // Set Current Folder Index to the index in the All Folder Names of the Current Folder
            NSUInteger currentFolderIndex = (NSUInteger)self.currentFolderType.idx;
            NSString* name = self.userFolders[currentFolderIndex][0];
            NSArray* names = [self.user allFoldersDisplayNames];
            for (NSUInteger i = 0; i < names.count; i++) {
                if ([name isEqualToString:names[i]]) {
                    self.currentFolderIdx = (NSInteger)i;
                    break;
                }
            }
        }
    } else { // Folder Type is Important/System Folder
        self.currentFolderIdx = [self.user numFolderWithFolder:self.currentFolderType];
    }
}

#pragma mark - IMAP Login and Connetions

-(void) connect
{
    // If this user is not the All user, but it is deleted, thjen do not connect
    if (!self.user.isAll && self.user.isDeleted) {
        DDLogWarn(@"User is not ALL and IS DELETED");
        return;
    }
    
    if (self.user.isAll) {
        DDLogInfo(@"User.isAll = TRUE");
        
        // Connect all non-All Accounts
        [self _loginAllUsers];
    }
    else { // The is not the "All" User Account
        
        DDLogInfo(@"User.isAll == FALSE");
        
        [self _doLoginForUser:self.user];
    }
}

-(BOOL) isConnected
{
    return [ImapSync sharedServices:self.user].connected;
}

-(void) setConnected
{
    DDAssert(!self.user.isAll, @"Should not be called by all Accounts");
    
    [ImapSync getInboxUnreadCountForUser:self.user completed:^{}];
    
    [self refreshCurrentFolder];
    
    [self sendOutboxs];
    
    BOOL isActiveAccountAll = [[Accounts sharedInstance] currentAccount].user.isAll;
    if (isActiveAccountAll){
        [[Accounts sharedInstance].currentAccount connect];
    }
}

- (void)_loginAllUsers
{
    NSArray<Account*>* allAccounts = [[Accounts sharedInstance] accounts];
    for (NSUInteger acntIndex = 0; acntIndex < allAccounts.count;acntIndex++) {
        Account *acnt = allAccounts[acntIndex];
        
        DDLogInfo(@"Evaluate Account[%ld]:",(long)acntIndex);
        
        if (!acnt.user.isAll && !acnt.isConnected) {
            
            DDLogInfo(@"Not All Account AND Is Not Connected.");
            
            [self _doLoginForUser:acnt.user];
            
            break;
        }
        else {
            DDLogInfo(@"Is All Account OR Is Connected");
        }
    }
}

- (void)_doLoginForUser:(UserSettings*)user
{
    DDLogInfo(@"QUEUEING doLogin:\"%@\"",user.imapHostname);
    
    // note: returned RACSignal is ignored.
    [[ImapSync doLogin:user] subscribeError:^(NSError *error) {
        
        BOOL canShowUI = [Accounts sharedInstance].canUI;
        
        switch ( error.code ) {
                
            case CCMConnectionError:
                DDLogError(@"Login Connection Error (%@) to IMAP Server \"%@\"",user.imapHostname,@(error.code));
                
                if ( canShowUI ) {
                    [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.connecting_error", @"Connection error")  dismissAfter:2.0 code:2];
                }
                
                break;
                
            case CCMCredentialsError:
                DDLogError(@"Login Credentials Error (%@) to IMAP Server \"%@\"",user.imapHostname,@(error.code));
                
                if ( canShowUI ) {
                    [CCMStatus showStatus:NSLocalizedString(@"add-account-view.error.wrong-credentials", @"Credentials")  dismissAfter:2.0 code:2];
                }
                break;
                
            default:
                DDLogError(@"Uknown Login Error (IMAP Server \"%@\"), displaying Status UI",user.imapHostname);
                
                if ( canShowUI ) {
                    [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.connecting_error", @"Connection error")  dismissAfter:2.0 code:2];
                }
                break;
        }
        
    } completed:^{
        DDLogInfo(@"COMPLETED doLogin:\"%@\"",user.imapHostname);
    }];
    
}

#pragma mark - Select the "Current Folder"


-(void) setCurrentFolder:(CCMFolderType)folder
{
    DDLogInfo(@"%@",[self stringWithFolderType:folder]);
    
//    if (encodeFolderTypeWith(self.currentFolderType) == encodeFolderTypeWith(folder)) {
//        NSString *folderTypeName = [self baseFolderType:folder.type];
//        DDLogWarn(@"setCurrentFolder: Current Folder is unchanged, do nothing. Type=\"%@\" Index=%@",folderTypeName,@(folder.idx));
//        return;
//    }
    
    self.currentFolderType = folder;
    _currentFolderFullSyncCompleted = NO;
    _hasLoadedAllLocal = NO;
    _isLoadingMore = NO;
    
    [_localFetchQueue cancelAllOperations];
    
    [AppSettings setLastFolderIndex:@(encodeFolderTypeWith(folder))];
    
    if (folder.type == FolderTypeUser) {
        NSString* folderName = [[[Accounts sharedInstance] currentAccount] userFolderNameAtIndex:(NSUInteger)folder.idx];
        NSArray* allFolderNames = [self.user allFoldersDisplayNames];
        for (NSUInteger folderNamesIndex = 0; folderNamesIndex < allFolderNames.count; folderNamesIndex++) {
            if ([folderName isEqualToString:allFolderNames[folderNamesIndex]]) {
                self.currentFolderIdx = (NSInteger)folderNamesIndex;
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
    
    [self.mailListDelegate reloadTableView];
    
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
        BOOL folderNameContainsPathDelim = [folderName containsString:folderPathDelim];
        [foldersNIndent addObject:@[ folderName, @(folderNameContainsPathDelim)] ];
    }
    
    return foldersNIndent;
}


- (void)cancelSearch
{
    self.mailListDelegate = nil;
}

#pragma mark - Receive Mails

-(void) addLocalDraft:(Draft*)draft
{
    Mail* m = [Mail mailWithDraft:draft];
    [self insertIntoConversation:m];
}

-(void) insertIntoConversation:(Mail*)email
{
    if (self.user.isDeleted) {
        DDLogInfo(@"User is deleted, returning.");
        return;
    }
    
    NSString *sonID = [email sonID];
    
    if ( [sonID isEqualToString:@""] ||
        [sonID isEqualToString:@"0"] ||
        ![_conversationIDs containsObject:sonID] ) {
        
        // No conversation with a matching sonID ...
        [self _addNewConversationWithMail:email];
        
    } else {
        
        @synchronized (self.allConversations) {
            
            // Find the conversation with the matching sonID,
            // and add this mail message to the conversation,
            BOOL matchingUidFound = NO;
            for (NSUInteger idx = 0; idx < self.allConversations.count; idx++) {
                
                Conversation* conversation = self.allConversations[idx];
                
                // If the indexed conversation matche's the email sonID
                NSString *firstMailSonID = [[conversation firstMail] sonID];
                
                if ([firstMailSonID isEqualToString:sonID]) {
                    
                    // Add the mail message to the conversation
                    [conversation addMail:email];
                    
                    [self _addCon:idx toFoldersContent:[conversation foldersType]];
                    
                    matchingUidFound = YES;
                    
                    // we match only once
                    break;
                }
            }
            if ( matchingUidFound == NO ) {
                DDLogError(@"No Matching UID Found, but one must exist!.");
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
    
    [_conversationIDs addObject:[email sonID]];
    
    [self addConversation:conv];
}

-(void) _addCon:(NSUInteger)idx toFoldersContent:(NSSet<NSNumber*>*)folderIndecies
{
    DDAssert(!self.user.isAll, @"Should not be called by all Accounts");
    
    for (NSNumber* fldInx in folderIndecies) {
        
        NSInteger folderIndex = [fldInx integerValue];
        
        CCMFolderType folderHandle = decodeFolderTypeWith(folderIndex);
        
        if ( CCMFolderTypeTypeIsValid(folderHandle.type) == NO ) {
            DDLogError(@"CCMFolderType type is invalid!");
        } else {
            [self _addMailIndex:idx toIndexSetOfFolder:folderHandle];
        }
    }
}

-(NSMutableIndexSet*) _mailIndeciesForFolder:(CCMFolderType)folderHandle
{
    NSMutableIndexSet *mailIndecies = nil;
    
    if (folderHandle.type == FolderTypeUser) {
        NSUInteger folderIndex = (NSUInteger)folderHandle.idx;
        if ( folderIndex >= self.userFoldersContent.count ) {
            DDLogError(@"Folder Index %@ is out of range (count = %@)",
                       @(folderIndex),@(self.userFoldersContent.count));
        } else {
            DDLogInfo(@"Folder Index %@ is less than User Folder count %@",@(folderIndex),@(self.userFoldersContent.count));
            mailIndecies = self.userFoldersContent[folderIndex];
        }
    }
    else {
        NSUInteger folderIndex = (NSUInteger)folderHandle.type;
        if ( folderIndex >= self.systemFoldersContent.count ) {
            DDLogError(@"Folder Index %@ is out of range (count = %@)",
                       @(folderIndex),@(self.systemFoldersContent.count));
        } else {
            DDLogDebug(@"Folder Index %@ is less than System Folder count %@",@(folderIndex),@(self.systemFoldersContent.count));
            mailIndecies = self.systemFoldersContent[folderIndex];
        }
    }
    return mailIndecies;
}

-(void) _addMailIndex:(NSUInteger)mailIndex toIndexSetOfFolder:(CCMFolderType)folderHandle
{
    DDAssert(!self.user.isAll, @"Should not be called by all Accounts");
    
    NSMutableIndexSet* folderMailIndecies = [self _mailIndeciesForFolder:folderHandle];
    
    if ( ![folderMailIndecies containsIndex:mailIndex] ) {
        
        [folderMailIndecies addIndex:mailIndex];
        
        // if the folder passed in is the current folder ....
        if (encodeFolderTypeWith(folderHandle) == encodeFolderTypeWith(self.currentFolderType)) {
            
            //NSMutableDictionary* syncState = [[SyncManager getSingleton] retrieveState:[self.user numFolderWithFolder:self.currentFolderType] accountNum:self.user.accountNum];
            //NSInteger tmpEmailCount = [syncState[@"emailCount"] integerValue];
            
            // if this (current) folder has exactly 20 mail messages ...
//            if ( [folderMailIndecies count] == 20) {
//                
//                // if the current account index is our account index ...
//                if ([Accounts sharedInstance].currentAccountIdx == self.idx) {
//                    // Then test the current folder for correct messages
//                    [self updateCurrentFolderMailInDatabaseFromImapServer];
//                }
//            }
            
            ConversationIndex* ci = [ConversationIndex initWithIndex:mailIndex user:self.user];
            
            //if (set.count == 50 || (tmpEmailCount < 50 && set.count == tmpEmailCount)) {
            //[mailListDelegate reFetch:YES];
            [self.mailListDelegate insertConversationIndex:ci];
            //}
        }
    }
}

// Called by -[Account _addNewConversationWithMail] and by -[ImapSync _cacheEmail]
-(NSUInteger) addConversation:(Conversation*)conversationToAdd
{
    DDAssert(!self.user.isAll, @"Should not be called for All Account");
    
    NSUInteger conversationIndex = 0;
    
    @synchronized (self.allConversations) {
        
        conversationIndex = [self.allConversations indexOfObject:conversationToAdd];
        
        // If the conversationToAdd was not found in the allConversations array ...
        if (conversationIndex == NSNotFound) {
            // Then we need to add it ..
            
            [self.allConversations addObject:conversationToAdd];
            conversationIndex = self.allConversations.count - 1;
            
            NSMutableSet<NSNumber*>* folderIndecies = [conversationToAdd foldersType];
            
            // If the conversationToAdd is not in the Spam, Deletion, or Drafts folders
            if (![folderIndecies containsObject:numberWithFolderType(FolderTypeDeleted)] &&
                ![folderIndecies containsObject:numberWithFolderType(FolderTypeSpam)]    &&
                ![folderIndecies containsObject:numberWithFolderType(FolderTypeDrafts)]) {
                
                // Then add it to the All Folders index set
                [self _addMailIndex:conversationIndex toIndexSetOfFolder:CCMFolderTypeAll];
            }
            
            // If the conversationToAdd is a Favorite
            if ([conversationToAdd isFav]) {
                // Then add it to the Favorites mail index
                [self _addMailIndex:conversationIndex toIndexSetOfFolder:CCMFolderTypeFavoris];
            }
            
            [self _addCon:conversationIndex toFoldersContent:folderIndecies];
        }
        else {
            // The conversationToAdd already exists in the allConversations array
            
            Conversation* matchedConversation = [self.allConversations objectAtIndex:conversationIndex];
            
            // Add all mails from conversationToAdd into its matchedConversation mails
            for (Mail* mail in conversationToAdd.mails) {
                [matchedConversation addMail:mail];         // only adds new mail
            }
        }
    }
    
    return conversationIndex;
}

#pragma mark - Get Mails

-(NSArray<Conversation*>*) conversations
{
    NSArray<Conversation*>* allConvCopy = nil;
    
    @synchronized (self.allConversations) {
        allConvCopy = [self.allConversations copy];
    }
    return allConvCopy;
}

-(Conversation*) getConversationForIndex:(NSUInteger)index
{
    DDAssert(!self.user.isAll, @"Should not be called by all Accounts");
    
    Conversation *conv = nil;
    
    @synchronized (self.allConversations) {
        conv = [[self.allConversations objectAtIndex:index] copy];
    }
    return conv;
}

-(NSArray<ConversationIndex*>*) getConversationsForFolder:(CCMFolderType)folderHandle
{
//    DDLogInfo(@"CCMFolderType .index=%@ .type=%@",
//              @(folderHandle.idx),@(folderHandle.type));
    
    DDAssert(!self.user.isAll, @"Should not be called by all Accounts");
    
    NSIndexSet* conversationIndexSet = [[self _mailIndeciesForFolder:folderHandle] mutableCopy];
    
    NSMutableArray<ConversationIndex *>* conversationsForFolder = [NSMutableArray arrayWithCapacity:[conversationIndexSet count]];
    
    @synchronized (self.allConversations) {
        
        [self.allConversations  enumerateObjectsAtIndexes:conversationIndexSet
                                                  options:0UL
                                               usingBlock:^(Conversation* obj, NSUInteger idx, BOOL* stop) {
                                                   
                                                   ConversationIndex* ci = [ConversationIndex initWithIndex:idx user:self.user];
                                                   [conversationsForFolder addObject:ci];
                                               }];
    }
    
    return conversationsForFolder;  // an array of ConversationIndex, where each contains an index ito Account.allMails
    
}

#pragma mark - Send a single Draft to multiple Person Ds

-(void) sendDraft:(Draft*)draft to:(NSArray *)toPersonIDs
{
    DDAssert(!self.user.isAll, @"Should not be called by \"all\" Account");
    
    DDLogInfo(@"Sending Draft to %lu Persons",(unsigned long)toPersonIDs.count);
    
    MCOMailProvider* accountProvider = [[MCOMailProvidersManager sharedManager] providerForIdentifier:self.user.identifier];
    
    NSInteger smtpServicesCount = (NSInteger)accountProvider.smtpServices.count;
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
    
    MCOSMTPSendOperation * sendOp =
    [smtpSession sendOperationWithContentsOfFile:rfc822DataFilename
                                            from:addressWithDispName
                                      recipients:to];
    
    sendOp.progress = ^(unsigned int current, unsigned int maximum){
        [self._getInVC setSGProgressPercentage:(MAX(10 ,(long)(current*100)/maximum))
                                  andTintColor:self.user.color];
    };
    
    self.isSendingOut++;
    
    dispatch_queue_t defaultQueue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
    
    dispatch_async( defaultQueue, ^{
        
        DDLogDebug(@"BLOCK START - DISPATCH_QUEUE_PRIORITY_DEFAULT");
        
        [self beginBackgroundUpdateTask];
        
        [sendOp start:^(NSError* error) {
            
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
                    MCOSMTPSendOperation * sendOp2 =
                    [smtpSession sendOperationWithContentsOfFile:rfc822DataFilename
                                                            from:addr
                                                      recipients:to];
                    
                    sendOp2.progress = ^(unsigned int current, unsigned int maximum){
                        
                        [self._getInVC setSGProgressPercentage:(MAX(10 ,(long)(current*100)/maximum))
                                                  andTintColor:self.user.color];
                    };
                    
                    [sendOp2 start:^(NSError* error2) {
                        if (error2) {
                            if (error2.code == MCOErrorNeedsConnectToWebmail) {
                                [self _authorizeWebmail];
                            }
                            
                            [self._getInVC finishSGProgress];
                            DDLogError(@"%@ Error sending email:%@", self.user.username, error2);
                            
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
            
            if (draft.accountNum == (NSInteger)self.user.accountNum) {
                
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
        
        if (draft.accountNum == (NSInteger)self.user.accountNum) {
            count++;
        }
    }
    
    return count;
}

#pragma mark - Move Indexed Conversation from Folder to Folder

-(BOOL) moveConversationAtIndex:(NSUInteger)index from:(CCMFolderType)folderFrom to:(CCMFolderType)folderTo updateUI:(BOOL)updateUI
{
    DDLogInfo(@"%@ Main Thread",([NSThread isMainThread]?@"Is":@"Isn't"));
    
    DDAssert(!self.user.isAll, @"Should not be called by all Accounts");
    
    Conversation* conv = nil;
    BOOL moveSuccessful = NO;
    
    @synchronized (self.allConversations) {
        
        conv = [self.allConversations objectAtIndex:index];
        
        if ( conv ) {
            moveSuccessful = [self moveConversation:conv from:folderFrom to:folderTo updateUI:updateUI];
        }
    }
    return moveSuccessful;
}

#pragma mark - Move Conversation from Folder to Folder

-(BOOL) moveConversation:(Conversation*)conversation from:(CCMFolderType)folderFrom to:(CCMFolderType)folderTo updateUI:(BOOL)updateUI
{
    DDLogInfo(@"%@ Main Thread",([NSThread isMainThread]?@"Is":@"Isn't"));
    
    // Cannot move a converstaion from the All Mails folder
    DDAssert(!self.user.isAll, @"Should not be called by all Accounts");
    
    // conversation must not be nil
    DDAssert(conversation, @"Conversation must not be nil.");
    
    BOOL okayToRemoveFromFolder = NO;
    
    @synchronized (self.allConversations) {
        
        NSUInteger idx = [self.allConversations indexOfObject:conversation];
        
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
            
            BOOL fromFolderIsCurrentFolder = ( encodeFolderTypeWith(folderFrom) == encodeFolderTypeWith(self.currentFolderType) );
            
            if (updateUI && fromFolderIsCurrentFolder) {
                NSArray<ConversationIndex*>* convs = @[ [ConversationIndex initWithIndex:idx user:self.user] ];
                [self.mailListDelegate removeConversationList:convs];
            }
        }
        else {
            //[CCMStatus showStatus:NSLocalizedString(@"status-bar-message.done", @"Done")  dismissAfter:2];
        }
        
        [toFolderMailIndecies addIndex:idx];
        
    } // end @syncronized
    
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
            count = (NSInteger)[self getConversationsForFolder:CCMFolderTypeFavoris].count;
        }
    }
    else {
        for (Account* a in [Accounts sharedInstance].accounts) {
            if (!a.user.isAll) {
                
                NSInteger favoritesFolderNumber = [self.user numFolderWithFolder:CCMFolderTypeFavoris];
                NSInteger allFolderNumber       = [self.user numFolderWithFolder:CCMFolderTypeAll];
                
                if ( favoritesFolderNumber != allFolderNumber ) {
                    
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

// Refresh contents of the the System Folders in the Mail Database from the IMAP Server
-(void) _importantFoldersRefresh:(NSInteger)folderNumber
{
    // called recursively to load each important folder
    
    DDLogInfo(@"ENTERED, folder=%@",@(folderNumber));
    
    if (self.user.isDeleted) {
        DDLogInfo(@"User is Deleted, return.");
        return;
    }
    
    if (![ImapSync canFullSync]){
        DDLogInfo(@"Cannot full sync,return.");
        return;
    }
    
    NSInteger __block folder = folderNumber;
    
    //If last important folder start full sync
    NSInteger lastImportantFolderIndex = kImportantFolderTypeMaxIndex;
    if (folder > lastImportantFolderIndex) {
        DDLogInfo(@"Completed last important folder, so start full sync.");
        [self _doLoadServer];
        return;
    }
    
    if ( _isSyncing ) {
        DDLogInfo(@"_isSyncing is TRUE, so return");
        return;
    }
    
    if ( _isSyncingCurrentFolder ) {
        DDLogInfo(@"_isSyncingCurrentFolder is TRUE, so return.");
        return;
    }
    
    _isSyncing = YES;
    
    DDLogInfo(@"QUEUEING refreshImportantFolder:\"%@\" user:\"%@\"",@(folder),self.user.imapHostname);
    
    [[[SyncManager getSingleton] refreshImportantFolder:folder user:self.user]
     
     subscribeNext:^(Mail* email) {
         DDLogInfo(@"subscribeNext received for refreshImportantFolder");

        
         [self insertIntoConversation:email];
        
     } error:^(NSError* error) {
         
         if (error.code != CCMFolderSyncedError && error.code != CCMAllSyncedError) {
             [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.connecting_error", @"Connection error") dismissAfter:2 code:2];
         }
         
         self->_isSyncing = NO;
         
         if (error.code == CCMFolderSyncedError && [Accounts sharedInstance].currentAccountIdx == self.idx) {
#warning Here be recursion
             [self _importantFoldersRefresh:++folder];
         }
     }
     completed:^{
         DDLogInfo(@"COMPLETED refreshImportantFolder:\"%@\" user:\"%@\"",@(folder),self.user.imapHostname);
         
         self->_isSyncing = NO;
         
         [self.mailListDelegate reloadTableView];
         
         if ([Accounts sharedInstance].currentAccountIdx == self.idx) {
#warning Here be recursion
             [self _importantFoldersRefresh:++folder];  // NB: Note increase in folder number;
         }
         
     }];
}

// Called by -_importantFoldersRefresh and itself (recursion)
//
-(void) _doLoadServer
{
    DDLogInfo(@"ENTERED");
    
    if ( self.user.isDeleted ) {
        DDLogDebug(@"User is deleted, returning.");
        return;
    }
    
    if ( ![ImapSync canFullSync] ){
        DDLogDebug(@"Cannot Full Sync, returning.");
        return;
    }
    
    if ( _isSyncing ) {
        DDLogDebug(@"_isSyncing = YES, returning.");
        return;
    }
    
    if (_isSyncingCurrentFolder ) {
        DDLogDebug(@"_isSyncingCurrentFolder = YES, returning.");
        return;
    }
    
    // Start syncing with the IMAP server
    
    _isSyncing = YES;
    
    DDLogInfo(@"QUEUEING syncFoldersUser:\"%@\"",self.user.imapHostname);
    
    [[[[SyncManager getSingleton] syncFoldersUser:self.user] deliverOn:[RACScheduler scheduler]]
     
     subscribeNext:^(Mail* email) {
         DDLogInfo(@"subscribeNext received for syncFoldersUser");

         //[self insertIntoConversation:email];
     }
     
     error:^(NSError* error) {
         
         self->_isSyncing = NO;
         
         switch ( error.code ) {
             case CCMAllSyncedError:
                 DDLogError(@"[SyncManager syncFolderUser] failed with CCMAllSyncedError");
                 break;
             case CCMFolderSyncedError:
                 DDLogError(@"[SyncManager syncFolderUser] failed with CCMFolderSyncedError");
                 
#warning Here be recursion
                 if ([Accounts sharedInstance].currentAccountIdx == self.idx) {
                     DDLogInfo(@"SYNC ERROR: This Account is the Current Account, so call this method RECURSIVELY!");
                     [self _doLoadServer]; // recursion
                 }
             default:
                 DDLogError(@"[SyncManager syncFolderUser] returned error, code = %@",@(error.code));
                 break;
         }
         
     }
     
     completed:^{
         
         DDLogInfo(@"COMPLETED syncFoldersUser:\"%@\"",self.user.imapHostname);

         self->_isSyncing = NO;
         
         [self.mailListDelegate reloadTableView];
         
//#warning Here be recursion
//         if ([Accounts sharedInstance].currentAccountIdx == self.idx) {
//             [self _doLoadServer];  // recursion
//         }
     }];
}

- (NSArray<Conversation*>*)_conversationsInFolder:(CCMFolderType)folder
{
    // Get the indecies of all the mail in the folder
    NSIndexSet* mailIndeciesInFolder = [[self _mailIndeciesForFolder:folder] copy];  // returns mutable (changable), so copy so doesn't change under us
    
    DDLogInfo(@"Folder \"%@\" has %@ mails.",[self folderDescription:folder],@(mailIndeciesInFolder.count));
    
    NSMutableArray<Conversation*>* conversationsInFolder = [NSMutableArray arrayWithCapacity:mailIndeciesInFolder.count];
    
    @synchronized (self.allConversations) {
        
        // From All Conversations in the Account, get only those conversations indexed by folderMailIndecies
        [self.allConversations enumerateObjectsAtIndexes:mailIndeciesInFolder
                                                 options:0UL
                                              usingBlock:^(id obj, NSUInteger idx, BOOL* stop){
                                                  [conversationsInFolder addObject:obj];
                                              }];
    }
    DDLogInfo(@"Folder \"%@\" has %@ conversations.",[self folderDescription:folder],@(conversationsInFolder.count));

    return conversationsInFolder;
}

#pragma mark - Update Mail Database from IMAP Server (nee runTestData)

-(void) updateCurrentFolderMailInDatabaseFromImapServer
{
    DDLogInfo(@"*** ENTRY POINT ***");
    DDLogInfo(@"ENTERED (nee runTestData)");
    
    if (self.user.isDeleted) {
        DDLogInfo(@"User is Deleted, DO NOTHING.");
        return;
    }
    
    if ( self.user.isAll ) {
        DDLogInfo(@"User is All, DO NOTHING.");
        return;
    }
    
    if ( self.allConversations.count == 0 ) {
        DDLogInfo(@"No Conversations, DO NOTHING.");
        return;
    }
    
    if ( _runningUpToDateTest ) {
        DDLogInfo(@"Already running Up To Date test, DO NOTHING.");
        return;
    }
    
    if (self.currentFolderIdx == -1) {
        DDLogInfo(@"Current Folder Index is -1, DO NOTHING");
        return;
    }
    
    // Update Mail from IMAP Server for all Conversations in Currenbt Folder
    [self _updateMailFromImapServerForConversationsInFolder:self.currentFolderType];
    
}

// Updates all mail messages from the IMAP server for all the conversations in the
// requested folder.  If they folder is not the All Folder, it does it for that folder also.

- (void)_updateMailFromImapServerForAllFolder {
    
    ImapSync *imapSyncService = [ImapSync sharedServices:self.user];

    if (![ImapSync canFullSync]){
        self->_runningUpToDateTest = NO;
        return;
    }
    
    NSArray<Conversation*>* conversationsInAllFolder = [self _conversationsInFolder:CCMFolderTypeAll];
    
    NSInteger folderIndex = [self.user numFolderWithFolder:CCMFolderTypeAll];
    
    DDLogInfo(@"CALLING updateLocalMailFromImapServerInConversations:(%@ conversations) ofFolder:%@ completed:block", @(conversationsInAllFolder.count), @(folderIndex));
    
    [imapSyncService updateLocalMailFromImapServerInConversations:conversationsInAllFolder
                                                         ofFolder:folderIndex
                                                        completed:^(NSArray<NSString*>* daysWithUpdatesOrDeletes)
    {
        DDLogInfo(@"COMPLETED updateLocalMailFromImapServerInConversations:(%@ conversations) ofFolder:%@ completed:block", @(conversationsInAllFolder.count), @(folderIndex));
        
        self->_runningUpToDateTest = NO;
        
        // Update "Days" in mailing list delegate
        // NB: Days can be nil if an error occurred
        if ( daysWithUpdatesOrDeletes ) {
            [self.mailListDelegate updateDays:daysWithUpdatesOrDeletes];
        }
    }];
}

// NB: Only deletes and updates, doesn't add new messages to mail db

- (void)_updateMailFromImapServerForConversationsInFolder:(CCMFolderType)folderType
{
    DDAssert(self.currentFolderIdx != -1, @"The Current Folder must not be -1");
    
    DDLogInfo(@"Update mail (from IMAP server) for folder: \"%@\"",[self folderDescription:folderType]);

    _runningUpToDateTest = YES;
    
    // Get an array of all the Conversations in local memory for the requested Folder in this account
    NSArray<Conversation*>* conversationsInCurrentFolder = [self _conversationsInFolder:folderType];
    
    ImapSync *imapSyncService = [ImapSync sharedServices:self.user];
    
    DDLogInfo(@"CALLING updateLocalMailFromImapServerInConversations:(%@ conversations) ofFolder:%@ completed:block", @(conversationsInCurrentFolder.count), @(self.currentFolderIdx));

    // Update conversations in the local store's current folder from the IMAP Server, and update
    [imapSyncService updateLocalMailFromImapServerInConversations:conversationsInCurrentFolder
                                             ofFolder:self.currentFolderIdx
                                               completed:^(NSArray<NSString*>* daysWithUpdatesOrDeletes) {
                                                   
        DDLogInfo(@"COMPLETED updateLocalMailFromImapServerInConversations:(%@ conversations) ofFolder:%@ completed:block", @(conversationsInCurrentFolder.count), @(self.currentFolderIdx));

       // Update "Days" in mailing list delegate
       // NB: Days can be nil if an error occurred
       if ( daysWithUpdatesOrDeletes ) {
           [self.mailListDelegate updateDays:daysWithUpdatesOrDeletes];
       }
                                                   
       // If the All Folder wasn't the one just updated
       if (folderType.type != FolderTypeAll) {
           
           [self _updateMailFromImapServerForAllFolder];
       }
       self->_runningUpToDateTest = NO;
    }];
}



#pragma mark - Deliver Update, Delete, and Index

-(Mail*)_findConversationMailWithMatchingMsgID:(NSString*)msgId
{
    Mail *mailInConversation = nil;
    
    @synchronized (self.allConversations) {
        
        for (Conversation* conv in self.allConversations) {
            for (Mail* mail in conv.mails) {
                if ([mail.msgID isEqualToString:msgId]) {
                    
                    mailInConversation = mail;
                }
            }
        }
    }
    return mailInConversation;
}

-(void) deliverUpdate:(NSArray <Mail*>*)emails
{
    if (self.user.isDeleted) {
        return;
    }
    
    // For each mail passed in, find the the mail with the matching msgID in this account, and update its flag
    for (Mail* email in emails) {
        
        Mail *mailInConversation = [self _findConversationMailWithMatchingMsgID:email.msgID];
        if (mailInConversation) {
            mailInConversation.flag = email.flag;
        }
        else {
            DDLogInfo(@"No match found for mail (subj:\"%@\"",email.subject);
        }
    }
}

-(void) deliverDelete:(NSArray*)emails fromFolder:(CCMFolderType)folderFrom
{
    if (self.user.isDeleted) {
        return;
    }
    
    NSMutableArray<ConversationIndex*>* idxs = [[NSMutableArray alloc]initWithCapacity:emails.count];
    
    NSMutableIndexSet* fromFolderMailIndecies = [self _mailIndeciesForFolder:folderFrom];
    
    for (Mail* email in emails) {
        
        BOOL found = NO;
        NSUInteger conservationIndex = 0;
        
        for (; !found && conservationIndex < self.allConversations.count; conservationIndex++) {
            for (Mail* m in ((Conversation* )self.allConversations[conservationIndex]).mails) {
                if ([m.msgID isEqualToString:email.msgID]) {
                    found = YES;
                    break;
                }
            }
        }
        
        conservationIndex--;
        
        if (!found) {
            DDLogError(@"Error Conversation to delete not found");
        }
        else {
            if ([fromFolderMailIndecies containsIndex:conservationIndex]) {
                [idxs addObject:[ConversationIndex initWithIndex:conservationIndex user:self.user]];
                [fromFolderMailIndecies removeIndex:conservationIndex];
            }
        }
    }
    
    [self.mailListDelegate removeConversationList:idxs];
}


-(BOOL) deleteIndex:(NSUInteger)index fromFolder:(CCMFolderType)folderFrom
{
    if (self.user.isDeleted) {
        return NO;
    }
    
    NSMutableIndexSet* currentFolderMailIndecies =
       [self _mailIndeciesForFolder:self.currentFolderType];
    
    if ([currentFolderMailIndecies containsIndex:index]) {
        DDLogInfo(@"Index %@ found in folder, deleting.",@(index));
        [currentFolderMailIndecies removeIndex:index];
        return YES;
    }
    
    return NO;
}

-(void) doPersonSearch:(Person*)person
{
    id<MailListDelegate> delegate = self.mailListDelegate;  // strong hold
    
    if (self.user.isDeleted) {
        return;
    }
    
    //NSInteger refBatch = 5;
    //NSInteger __block batch = refBatch;
    
    [delegate localSearchDone:NO];
    [delegate serverSearchDone:NO];
    
    //LocalSearch
    [_localFetchQueue addOperationWithBlock:^{
        
        DDLogInfo(@"QUEUEING senderSearch:\"%@\" inAccountNum:%@ (\"%@\")", person.name, @(self.user.accountNum), self.user.imapHostname );

        [[[SearchRunner getSingleton] senderSearch:person inAccountNum:self.user.accountNum]
         subscribeNext:^(Mail* email) {
             DDLogInfo(@"subscribeNext received for senderSearch");

             [self insertIntoConversation:email];
             //if (batch-- == 0) {
             //    batch = refBatch;
             //[self.mailListDelegate reFetch:YES];
             //}
         }
         completed:^{
             DDLogInfo(@"COMPLETED senderSearch:\"%@\" inAccountNum:%@ (\"%@\")", person.name, @(self.user.accountNum), self.user.imapHostname );

             //[self.mailListDelegate reFetch:YES];
             [self.mailListDelegate localSearchDone:YES];
         }];
    }];
    
    DDLogInfo(@"QUEUEING searchPerson:\"%@\" user:\"%@\"", person.name, self.user.imapHostname );

    //ServerSearch
    [[[[SyncManager getSingleton] searchPerson:person user:self.user] deliverOn:[RACScheduler mainThreadScheduler]]
     subscribeNext:^(Mail* email) {
         DDLogInfo(@"subscribeNext received for searchPerson");

         [self insertIntoConversation:email];
         //if (batch-- == 0) {
         //    batch = refBatch;
         //[self.mailListDelegate reFetch:YES];
         //}
     }
     error:^(NSError* error) {
         DDLogError(@"Error: %@", error.localizedDescription);
         [self.mailListDelegate reFetch:YES];
     }
     completed:^{
         DDLogInfo(@"COMPLETED searchPerson:\"%@\" user:\"%@\"", person.name, self.user.imapHostname );

         [delegate reFetch:YES];
         [delegate serverSearchDone:YES];
     }];
}

-(void) doTextSearch:(NSString*)searchString
{
    id<MailListDelegate> mailListDelegate = self.mailListDelegate;  // strong hold

    if (self.user.isDeleted) {
        return;
    }
    
    //NSInteger refBatch = 5;
    //NSInteger __block batch = refBatch;
    
    [mailListDelegate localSearchDone:NO];
    [mailListDelegate serverSearchDone:NO];
    
    
    //LocalSearch
    [_localFetchQueue addOperationWithBlock:^{
        
        DDLogInfo(@"QUEUEING search:\"%@\" inAccountNum:%@ (\"%@\")", searchString, @(self.user.accountNum), self.user.imapHostname );

        [[[SearchRunner getSingleton] search:searchString inAccountNum:self.user.accountNum]
         subscribeNext:^(Mail* email) {
             DDLogInfo(@"subscribeNext received for search");

             [self insertIntoConversation:email];
             //if (batch-- == 0) {
             //    batch = refBatch;
             //[self.mailListDelegate reFetch:YES];
             //}
         }
         completed:^{
             DDLogInfo(@"COMPLETED search:\"%@\" inAccountNum:%@ (\"%@\")", searchString, @(self.user.accountNum), self.user.imapHostname );

             [mailListDelegate reFetch:YES];
             [mailListDelegate serverSearchDone:YES];
         }];
    }];
    
    DDLogInfo(@"CALLING searchText:\"%@\" user:\"%@\" deliverOn:<RAC Thread>", searchString, self.user.imapHostname );
    
    //ServerSearch
    [[[[SyncManager getSingleton] searchText:searchString user:self.user] deliverOn:[RACScheduler mainThreadScheduler]]
     subscribeNext:^(Mail* email) {
         DDLogInfo(@"subscribeNext received for searchText");

         [self insertIntoConversation:email];
     }
     error:^(NSError* error) {
         DDLogError(@"Error: %@", error.localizedDescription);
         [mailListDelegate reFetch:YES];
     }
     completed:^{
         DDLogInfo(@"COMPLETED searchText:\"%@\" user:\"%@\" deliverOn:<RAC Thread>", searchString, self.user.imapHostname );

         [mailListDelegate reFetch:YES];
         [mailListDelegate serverSearchDone:YES];
     }];
}

-(void) localFetchMore:(BOOL)loadMore
{
    DDAssert(self.currentFolderIdx != -1, @"The Current Folder must not be -1");

    id<MailListDelegate> subscriber = self.mailListDelegate;      // strong hold

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
        
        
        [subscriber localSearchDone:NO];
        
        BOOL __block more = NO;
        
        DDLogDebug(@"Local search");
        
        [_localFetchQueue addOperationWithBlock:^{
            
            Mail* email = loadMore ? self->_lastEmails[(NSUInteger)self.currentFolderIdx] : nil;
            
            DDLogInfo(@"CALLING activeFolderSearch:\"%@\" inAccountNum%@ (:\"%@\") ", ( email ? email.subject : @"nil" ), @(self.user.accountNum), self.user.imapHostname );

            [[[SearchRunner getSingleton] activeFolderSearch:email inAccountNum:self.user.accountNum]
             subscribeNext:^(Mail* email) {
                 DDLogDebug(@"subscribeNext received for activeFolderSearch");

                 more = YES;
                 
                 if (email.user && !email.user.isDeleted) {
                     [email.user.linkedAccount insertIntoConversation:email];
                 }
                 
                 self->_lastEmails[(NSUInteger)self.currentFolderIdx] = email;
             }
             completed:^{
                 DDLogInfo(@"COMPLETED activeFolderSearch:\"%@\" inAccountNum%@ (:\"%@\") ", ( email ? email.subject : @"nil" ), @(self.user.accountNum), self.user.imapHostname );

                 self->_isLoadingMore = NO;
                 
                 DDLogDebug(@"Local search done. Found emails? %@", more?@"YES":@"NO");
                 
                 if (!more) {
                     self->_hasLoadedAllLocal = YES;
                 }
                 
                 [self updateCurrentFolderMailInDatabaseFromImapServer];
                 
                 [subscriber localSearchDone:YES];
                 [subscriber reFetch:YES];
             }];
        }];
    }
}

#pragma mark - Both Pull-To-Refresh and Background-Update call here!

// Called by Pull To Refresh
// Called by Background Update
// Called by setConnected
//
-(void) refreshCurrentFolder
{
    DDLogInfo(@"*** ENTRY POINT ***");
    
    DDAssert(self.currentFolderIdx != -1, @"The Current Folder must not be -1");

    DDLogInfo(@"Folder[%@] of type \"%@\"",@(self.currentFolderIdx),[self currentFolderTypeValue]);
    
    // If the Current User Account is the "All" account ...
    if (self.user.isAll) {
        // then recurse through all non-All user accounts
        for (Account* a in [[Accounts sharedInstance] accounts]) {
            
            // if this is a non-All user account ....
            if (!a.user.isAll) {
                
                // refresh this account's curent folder
                DDLogWarn(@"Recursion");
                [a refreshCurrentFolder];   // NB: RECURSION
            }
        }
        DDLogInfo(@"All Folders refreshed.");
        
        // All folders refreshed, done with this method
        return;
    }
    
    // If this user account is deleted, then don't refresh it
    if (self.user.isDeleted) {
        DDLogInfo(@"Folder is Deleted.");
        return;
    }
    
    // If we are not connected to this user's IMAP server ...
    if ( ![self isConnected] ) {
        
        // Then connect (NB: Does not block)
        [self connect];
        
        DDLogInfo(@"IMAP Services NOT connected, tried connecting, set Server Search Done.");
        
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [self.mailListDelegate serverSearchDone:YES];
        }];
        
        return;
    }
    
    NSInteger __block new = 0;
    
    [self.mailListDelegate serverSearchDone:NO];      // notify delegate VC
    
    // Download all mail headers and flags for the current folder from the IMAP server,
    // and update the database, removing mail no longer in folder, updating changed flags (e.g. favorited).
    [self updateCurrentFolderMailInDatabaseFromImapServer];
    
    DDLogInfo(@"Refresh");
    
    DDLogInfo(@"CALLING syncActiveFolderFromStart:YES user:\"%@\" ", self.user.imapHostname );

    
    // Load IMAP Mail into Database for active folder
    RACSignal *signal = [[SyncManager getSingleton] syncActiveFolderFromStart:YES user:self.user];
    
    [[signal deliverOn:[RACScheduler schedulerWithPriority:RACSchedulerPriorityBackground]]
     
     subscribeNext:^(Mail* email) {
         DDLogInfo(@"subscribeNext received for syncActiveFolderFromStart");

         new++;
         [self insertIntoConversation:email];       // i.d. Conversation rows
     }
     error:^(NSError* error) {
         
         DDLogError(@"[SyncManager syncActiveFolderFromStart] - Error = %@",error);
         
         [self.mailListDelegate serverSearchDone:YES];
         
         if (error.code != CCMFolderSyncedError && error.code != CCMAllSyncedError) {
             
             [CCMStatus showStatus:NSLocalizedString(@"status-bar-message.connecting_error", @"Connection error") dismissAfter:2 code:2];
         }
         else if ([Accounts sharedInstance].currentAccountIdx == self.idx) {
             
             [self updateCurrentFolderMailInDatabaseFromImapServer];
             
             self->_currentFolderFullSyncCompleted = YES;
             self->_isSyncingCurrentFolder = NO;
             [self _importantFoldersRefresh:0];
         }
     }
     completed:^{
         
         DDLogInfo(@"COMPLETED syncActiveFolderFromStart:YES user:\"%@\" ", self.user.imapHostname );
         
         [self.mailListDelegate serverSearchDone:YES];
         
         if (new != 0) {
             [self.mailListDelegate reFetch:YES];
         }
         
         if ([Accounts sharedInstance].currentAccountIdx == self.idx) {
             
             [self updateCurrentFolderMailInDatabaseFromImapServer];
             
             if (self->_currentFolderFullSyncCompleted) {
                 self->_isSyncingCurrentFolder = NO;
                 [self _importantFoldersRefresh:0];
             }
             else if (!self->_isSyncingCurrentFolder) {
                 self->_isSyncingCurrentFolder = YES;
                 [self _syncCurrentFolder];
             }
             
             [self.mailListDelegate reloadTableView];
         }
     }];
}

-(void) _syncCurrentFolder
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
    
    DDLogInfo(@"CALLING syncActiveFolderFromStart:NO user:\"%@\" ", self.user.imapHostname );

    [[[[SyncManager getSingleton] syncActiveFolderFromStart:NO user:self.user] deliverOn:[RACScheduler mainThreadScheduler]]
     subscribeNext:^(Mail* email) {
         DDLogInfo(@"subscribeNext received for syncActiveFolderFromStart");

         //[self insertIntoConversation:email];
     } error:^(NSError* error) {
         
         DDLogError(@"Error: %@", error.localizedDescription);
         self->_isSyncingCurrentFolder = NO;
         
         if (error.code == CCMFolderSyncedError) {
             self->_currentFolderFullSyncCompleted = YES;
             [self _importantFoldersRefresh:0];
         }
     } completed:^{
         DDLogInfo(@"COMPLETED syncActiveFolderFromStart:NO user:\"%@\" ", self.user.imapHostname );
         
         [self.mailListDelegate reloadTableView];

//         if ([Accounts sharedInstance].currentAccountIdx == self.idx) {
//#warning Here be recursion
//             [self _syncCurrentFolder];  // Recursive!
//         }
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
    
    //    @property (nonatomic, weak) id<MailListDelegate> mailListDelegate;
    
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
