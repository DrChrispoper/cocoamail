//
//  ImapSync.m
//  CocoaMail
//
//  Created by Christopher Hockley on 20/01/2012.
//  Copyright (c) 2012 Christopher Hockley. All rights reserved.

#import "ImapSync.h"
#import "SyncManager.h"
#import "AppSettings.h"
#import "SearchRunner.h"
#import "EmailProcessor.h"
#import "UidEntry.h"
#import "CachedAction.h"
#import "Attachments.h"
#import "Reachability.h"
#import <libextobjc/EXTScope.h>
//#import <Google/SignIn.h>
#import "GTMOAuth2Authentication.h"
#import "GTMOAuth2ViewControllerTouch.h"
#import "Mail.h"

#import "ViewController.h"
#import "StringUtil.h"
#import "CCMConstants.h"
#import "UserSettings.h"

#import <CocoaLumberjack/CocoaLumberjack.h>

#ifdef USING_INSTABUG
#import <Instabug/Instabug.h>
#endif

@interface ImapSync ()

@property (nonatomic) UserSettings* user;
@property (nonatomic, strong) MCOIMAPOperation* imapCheckOp;
@property (nonatomic) BOOL isCanceled;

@end

static NSArray * sharedServices = nil;


@implementation ImapSync

// Returns the IMAP Sync Service for the given User's Account
// Returns nil if not matching account
//
+(ImapSync*) sharedServices:(UserSettings*)user
{
    DDAssert(user, @"No user at accountNum:%ld",(long)user.accountNum);
    
    DDAssert(!user.isDeleted, @"AccountNum:%ld is deleted",(long)user.accountNum);
    
    // Find the shared IMAP Sync Service with the matching Account Number
    for (ImapSync* sharedService in [ImapSync allSharedServices:nil]) {
        if (sharedService.user.accountNum == user.accountNum) {
            return sharedService;
        }
    }
    
    return nil;
}

+(NSArray<ImapSync*>*) allSharedServices:(MCOIMAPSession*)updated
{
    if (updated) {
        sharedServices = nil;
    }
    
    @synchronized(self) {
        if (sharedServices == nil || sharedServices.count == 0) {
            
            NSMutableArray* sS = [[NSMutableArray alloc]init];
            
            for (UserSettings* user in [AppSettings getSingleton].users) {
                
                if (user.isDeleted) {
                    continue;
                }
                
                ImapSync* sharedService = [[super allocWithZone:nil] init];
                sharedService.user = user;
                sharedService.connected = NO;
                
                sharedService.s_queue = dispatch_queue_create(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
                
                if (updated && [updated.username isEqualToString:user.username]) {
                    sharedService.imapSession = updated;
                    sharedService.imapSession.dispatchQueue = sharedService.s_queue;
                    sharedService.connected = YES;
                }
                else {
                    
                    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
                    
                    dispatch_async(sharedService.s_queue, ^{
                        sharedService.imapSession = [AppSettings imapSession:user];
                        sharedService.imapSession.dispatchQueue = sharedService.s_queue;
                        dispatch_semaphore_signal(semaphore);
                    });
                    
                    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
                    
                    sharedService.connected = NO;
                }
                
                [sS addObject:sharedService];
            }
            sharedServices = [[NSArray alloc]initWithArray:sS];
            
            return sharedServices;
        }
        else {
            return sharedServices;
        }
    }
}

+(void) deletedAndWait:(UserSettings*)deleteUser
{
    for (ImapSync* service in sharedServices) {
        if (service.user.accountNum == deleteUser.accountNum) {
            dispatch_async(service.s_queue, ^{
                [[service.imapSession disconnectOperation] start:^(NSError * _Nullable error) {
                    DDLogDebug(@"IMAP Sync Session Disconnect Operation for Acnt# %lu",
                               (unsigned long)deleteUser.accountNum);
                }];
            });
        }
    }
    
    sharedServices = nil;
}

- (void)setConnected:(BOOL)connected
{
    _connected = connected;
    if (!connected) {
        self.signal = nil;
    }
}

// MARK: - Login to IMAP Server

+(RACSignal*) doLogin:(UserSettings*)user
{
    DDLogDebug(@"ENTERED IMAP Sync Servier: Do Login for \"%@\"]",user.username);
    
    if (!user || user.isDeleted) {
        
        DDLogDebug(@"\tHave no user or user is deleted");
        
        return [RACSignal startEagerlyWithScheduler:[RACScheduler scheduler] block:^(id<RACSubscriber> subscriber) {
            [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMDeletedError userInfo:nil]];
        }];
    }

    // TODO: Consider moving this off the stack
    ImapSync* sharedService = [ImapSync sharedServices:user];
    
    if (!sharedService) {
        
        DDLogDebug(@"\tHave no Shared ImapSync Services for User \"%@\"",user.username);
        
        return [RACSignal startEagerlyWithScheduler:[RACScheduler scheduler] block:^(id<RACSubscriber> subscriber) {
#ifdef USING_INSTABUG
            NSException* myE = [NSException exceptionWithName:@"No shared Service" reason:@"Can't login no shared service" userInfo:nil];
            [Instabug reportException:myE];
#endif
            [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain
                                                      code:CCMNoSharedServiceError
                                                  userInfo:nil]];
        }];
    }
    
    DDLogDebug(@"CURIOUS: user %@ sharedSettings.user",(user==sharedService.user?@"EQUAL":@"DOES NOT EQUAL"));

    if (![ImapSync isNetworkAvailable]) {
        
        DDLogDebug(@"\t+[ImapSync isNetworkAvailable] returned NO");
        
        return [RACSignal startEagerlyWithScheduler:[RACScheduler scheduler] block:^(id<RACSubscriber> subscriber) {
            sharedService.connected = NO;
            [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain
                                                      code:CCMConnectionError
                                                  userInfo:nil]];
        }];
    }
    
    
    if ( sharedService.signal ) {
        
        DDLogDebug(@"\tReturning (existing) Shared IMAP Sync Service Signal");
        
        return sharedService.signal;
    }
    
    DDLogDebug(@"\tCREATE NEW Shared IMAP Sync Service Signal.");
    
    sharedService.signal = [RACSignal startEagerlyWithScheduler:[RACScheduler scheduler]
                      block:^(id<RACSubscriber> subscriber)
    {
        if (sharedService.connected) {
            DDLogDebug(@"\tShared IMAP Sync Service is Connected");
            [subscriber sendCompleted];
            return;
        }

        DDLogDebug(@"\tShared IMAP Sync Service is NOT Connected");

        if ([sharedService.user isUsingOAuth]) {
            DDLogDebug(@"\tAttempting to log in with OAuth.");

            [self _loginWithOAuth:sharedService forUser:user withSubscriber:subscriber];
        }
        else { //Not using OAuth
            DDLogDebug(@"\tAttempting to log in with Password.");

            [self _loginWithPassword:sharedService forUser:user withSubscriber:subscriber];
        }
    }];
    return sharedService.signal;

}

//+ (RACSignal*)_createSignalForSharedIMAPSyncService:(ImapSync*)sharedService forUser:(UserSettings *)user
//{
//    return [RACSignal startEagerlyWithScheduler:[RACScheduler scheduler]
//                                          block:^(id<RACSubscriber> subscriber) {
//        
//        if (sharedService.connected) {
//            DDLogDebug(@"\tShared IMAP Sync Service is Connected");
//            [subscriber sendCompleted];
//            
//            return;
//        }
//    
//        DDLogDebug(@"\tShared IMAP Sync Service is NOT Connected");
//
//        if ([sharedService.user isUsingOAuth]) {
//            DDLogDebug(@"\tAttempting to log in with OAuth.");
//            
//            [self _loginWithOAuth:sharedService forUser:user withSubscriber:subscriber];
//        }
//        else { //Not using OAuth
//            DDLogDebug(@"\tAttempting to log in with Password.");
//            
//            [self _loginWithPassword:sharedService forUser:user withSubscriber:subscriber];
//        }
//    }];
//
//}

+(void) _loginWithOAuth:(ImapSync *)sharedService forUser:(UserSettings *)user withSubscriber:(id<RACSubscriber>) subscriber
{
    DDLogDebug(@"\tLogging with OAuth (with token:%@)", [sharedService.user oAuth]);
    
    sharedService.imapSession.OAuth2Token = [sharedService.user oAuth];
    sharedService.imapSession.authType = MCOAuthTypeXOAuth2;
    sharedService.imapSession.connectionType = MCOConnectionTypeTLS;
    sharedService.imapCheckOp = [sharedService.imapSession checkAccountOperation];
    
    dispatch_async([ImapSync sharedServices:user].s_queue, ^{
        
        [sharedService.imapCheckOp start:^(NSError* error) {
            if (error) {
                
                DDLogError(@"Error:%@ loading oauth account:%@", error, sharedService.user.username);
                GTMOAuth2Authentication * auth = [GTMOAuth2ViewControllerTouch authForGoogleFromKeychainForName:USR_TKN_KEYCHAIN_NAME
                                                                                                       clientID:CLIENT_ID
                                                                                                   clientSecret:CLIENT_SECRET];
                
                DDLogDebug(@"\tUser:%@",[auth userEmail]);
                
                [auth setUserEmail:sharedService.user.username];
                
                if (![auth canAuthorize]) {
                    DDLogDebug(@"\tCan't Authorize");
                    
                    auth.clientID = CLIENT_ID;
                    auth.clientSecret = CLIENT_SECRET;
                    
                    BOOL didAuth = [GTMOAuth2ViewControllerTouch authorizeFromKeychainForName:USR_TKN_KEYCHAIN_NAME
                                                                               authentication:auth
                                                                                        error:NULL];
                    if (didAuth) {
                        DDLogDebug(@"\tDid Authorize");
                        [GTMOAuth2ViewControllerTouch saveParamsToKeychainForName:USR_TKN_KEYCHAIN_NAME authentication:auth];
                    }
                    else {
                        sharedService.connected = NO;
                        [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMConnectionError userInfo:nil]];
                    }
                }
                else {
                    DDLogDebug(@"\tAuthorization successfull, tesign & refresh token.");
                    
                    NSURL *tokenURL = auth.tokenURL;
                    
                    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:tokenURL];
                    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
                    
                    NSString *userAgent = [auth userAgent];
                    [request setValue:userAgent forHTTPHeaderField:@"User-Agent"];
                    
                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                        
                        [auth authorizeRequest:request completionHandler:^(NSError *error) {
                            
                            if ([auth accessToken] && ![[auth accessToken] isEqualToString:@""]) {
                                DDLogDebug(@"\tNew Token");
                                
                                DDLogDebug(@"\tRefresh Token:%@",[auth refreshToken]);
                                
                                [sharedService.user setOAuth:[auth accessToken]];
                                sharedService.imapSession = [AppSettings imapSession:sharedService.user];
                                sharedService.imapSession.dispatchQueue = sharedService.s_queue;
                                
                                dispatch_async([ImapSync sharedServices:user].s_queue, ^{
                                    
                                    DDLogDebug(@"\tLoggin Again with OAuth with token:%@", [sharedService.user oAuth]);
                                    
                                    sharedService.imapCheckOp = [sharedService.imapSession checkAccountOperation];
                                    [sharedService.imapCheckOp start:^(NSError* error) {
                                        if (!error) {
                                            DDLogDebug(@"\tAccount:%ld check OK", (long)sharedService.user.accountNum);
                                            sharedService.connected = YES;
                                            [sharedService.user.linkedAccount setConnected];
                                            [sharedService checkForCachedActions];
                                            [sharedService _checkFolders];
                                            
                                            [subscriber sendCompleted];
                                        }
                                        else {
                                            DDLogError(@"Error:%@ loading oauth account:%@", error, sharedService.user.username);
                                            [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMConnectionError userInfo:nil]];
                                        }
                                    }];
                                });
                            }
                            else {
                                DDLogDebug(@"Error:%@ loading oauth account:%@", error, sharedService.user.username);
                                [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMConnectionError userInfo:nil]];
                            }
                        }];
                    }];
                }
            }
            else {
                DDLogDebug(@"Account:%ld check OK", (long)sharedService.user.accountNum);
                sharedService.connected = YES;
                [sharedService.user.linkedAccount setConnected];
                [sharedService checkForCachedActions];
                [sharedService _checkFolders];
                
                [subscriber sendCompleted];
                
            }
        }];
    });
}

+(void) _loginWithPassword:(ImapSync *)sharedService forUser:(UserSettings *)user withSubscriber:(id<RACSubscriber>) subscriber
{
    sharedService.imapCheckOp = [sharedService.imapSession checkAccountOperation];
    
    DDLogDebug(@"\tLogging in with Password (not oAuth)");
    
    dispatch_async([ImapSync sharedServices:user].s_queue, ^{
        
        [sharedService.imapCheckOp start:^(NSError* error) {
            if (error) {
                sharedService.connected = NO;
                DDLogError(@"Error:%@ loading account:\"%@\"", error, sharedService.user.username);
                
                if (error.code == MCOErrorAuthentication) {
                    [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMCredentialsError userInfo:nil]];
                }
                else {
                    [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMConnectionError userInfo:nil]];
                }
            }
            else {
                DDLogDebug(@"\tAccount:%ld CONNECTED", (long)sharedService.user.accountNum);
                sharedService.connected = YES;
                [sharedService.user.linkedAccount setConnected];
                [sharedService checkForCachedActions];
                [sharedService _checkFolders];
                
                [subscriber sendCompleted];
            }
            
        }];
    });
}

-(void) cancel
{
    self.isCanceled = YES;
}

-(void) saveCachedData
{
    //NSMutableArray* ops = [[NSMutableArray alloc] initWithCapacity:self.cachedData.count];
    /*EmailProcessor* ep = [EmailProcessor getSingleton];
     
     NSURL* someURL = [[NSURL alloc] initFileURLWithPath:[StringUtil filePathInDocumentsDirectoryForFileName:@"cache"]];
     [[[NSArray alloc]init] writeToURL:someURL atomically:YES];
     
     if (self.cachedData) {
     for (Mail* mail in self.cachedData) {
     CCMLog(@"Saving Cached Email: %@", mail.subject);
     
     NSInvocationOperation* nextOp = [[NSInvocationOperation alloc] initWithTarget:ep selector:@selector(addEmailWrapper:) object:mail];
     //[ops addObject:nextOp];
     }
     }
     
     [ep.operationQueue addOperations:ops waitUntilFinished:YES];*/
    
    self.cachedData = nil;
    
}

-(NSInteger)folderNumberForType:(NSInteger)folderType
{
    return [self.user numFolderWithFolder:FolderTypeWith(folderType, 0)];
}

-(BOOL)folderIsNotSynced:(NSInteger)folderNumber
{
    SyncManager *syncMgr = [SyncManager getSingleton];
        
    NSDictionary *state = [syncMgr retrieveState:folderNumber
                                      accountNum:self.user.accountNum];
    
    return ([state[@"fullsynced"] boolValue] == FALSE) ;
}

-(NSInteger) nextFolderToSync
{
    DDLogInfo(@"ENTERING ImapSync nextFolderToSync");
    
//    SyncManager *syncMgr = [SyncManager getSingleton];
//        
//    NSInteger folderNumberForType = [self.user numFolderWithFolder:FolderTypeWith(FolderTypeAll, 0)];
//    
//    NSDictionary *state = [syncMgr retrieveState:folderNumberForType
//                                      accountNum:self.user.accountNum];
//    
//    if ( ![state[@"fullsynced"] boolValue] ) {
//        return folderNumberForType;
//    }
    
    NSInteger allFolderNum = [self folderNumberForType:FolderTypeAll];
    if ( [self folderIsNotSynced:allFolderNum] ){
        DDLogDebug(@"\tAll Folder Not Synced, do next");
        return allFolderNum;
    }

//    if (![[[SyncManager getSingleton] retrieveState:[self.user numFolderWithFolder:FolderTypeWith(FolderTypeInbox, 0)] accountNum:self.user.accountNum][@"fullsynced"] boolValue]) {
//        return [self.user numFolderWithFolder:FolderTypeWith(FolderTypeInbox, 0)];
//    }
    
    NSInteger inboxFolderNumber = [self folderNumberForType:FolderTypeInbox];
    if ( [self folderIsNotSynced:inboxFolderNumber] ){
        DDLogDebug(@"\tInbox Folder Not Synced, do next");
        return inboxFolderNumber;
    }
    
//    if (![[[SyncManager getSingleton] retrieveState:[self.user numFolderWithFolder:FolderTypeWith(FolderTypeFavoris, 0)] accountNum:self.user.accountNum][@"fullsynced"] boolValue]) {
//        if ([self.user numFolderWithFolder:FolderTypeWith(FolderTypeFavoris, 0)] != -1) {
//            return [self.user numFolderWithFolder:FolderTypeWith(FolderTypeFavoris, 0)];
//        }
//    }
        
    NSInteger favorisFolderNumber = [self folderNumberForType:FolderTypeFavoris];
    if ( [self folderIsNotSynced:favorisFolderNumber] ){
        DDLogDebug(@"\tFavoris Folder Not Synced, do next");
        return favorisFolderNumber;
    }
    
//    if (![[[SyncManager getSingleton] retrieveState:[self.user numFolderWithFolder:FolderTypeWith(FolderTypeSent, 0)] accountNum:self.user.accountNum][@"fullsynced"] boolValue]) {
//        return [self.user numFolderWithFolder:FolderTypeWith(FolderTypeSent, 0)];
//    }
    
    NSInteger sentFolderNumber = [self folderNumberForType:FolderTypeSent];
    if ( [self folderIsNotSynced:sentFolderNumber] ){
        DDLogDebug(@"\tSent Folder Not Synced, do next");
        return sentFolderNumber;
    }
    
    // Return the first unsynced user folder
    NSArray* folders = [self.user allFoldersDisplayNames];
    for (int indexFolder = 0; indexFolder < folders.count; indexFolder++) {
        if (![[[SyncManager getSingleton] retrieveState:indexFolder accountNum:self.user.accountNum][@"fullsynced"] boolValue]) {
            DDLogDebug(@"\tUser Folder %ld Not Synced, do next",(long)indexFolder);
            return indexFolder;
        }
    }
    
    return -1;
}

// MARK: - IMAP Sync Service - Search for Text

-(RACSignal*) runSearchText:(NSString*)text
{
    DDLogInfo(@"ENTERING ImapSync runSearchText:\"%@\"",text);
    
    @weakify(self);
    
    return [RACSignal createSignal:^RACDisposable* (id<RACSubscriber> subscriber) {
        @strongify(self);
        
        if (![ImapSync isNetworkAvailable]) {
            self.connected = NO;
            DDLogError(@"\tIMAP Sync - Network is not available");
            [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMConnectionError userInfo:nil]];
        }
        
        NSInteger currentFolder = [self.user numFolderWithFolder:FolderTypeWith(FolderTypeAll, 0)];
        NSString* folderPath = [self.user folderServerName:currentFolder];
        MCOIMAPSearchExpression* expr = [MCOIMAPSearchExpression searchContent:text];
        
        MCOIMAPSearchOperation* searchOperation = [self.imapSession searchExpressionOperationWithFolder:folderPath expression:expr];
        
        dispatch_async(self.s_queue, ^{
            [searchOperation start:^(NSError* error, MCOIndexSet* searchResult) {
                if (error) {
                    DDLogError(@"searchOperation error = %@",error);
                    [subscriber sendError:error];
                    return;
                }
                
                [self _saveSearchResults:searchResult withSubscriber:subscriber inFolder:currentFolder];
            }];
        });
        
        return [RACDisposable disposableWithBlock:^{}];
    }];
}

// MARK: - IMAP Sync Service - Search for Person

-(RACSignal*) runSearchPerson:(Person*)person
{
    DDLogInfo(@"ENTERING ImapSync runSearchPerson: name=\"%@\"",person.name);

    @weakify(self);
    
    return [RACSignal createSignal:^RACDisposable* (id<RACSubscriber> subscriber) {
        @strongify(self);
        
        if (![ImapSync isNetworkAvailable]) {
            self.connected = NO;
            DDLogError(@"IMAP Sync Service Network is not available error");
            [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMConnectionError userInfo:nil]];
        }
        
        NSInteger currentFolder = [self.user numFolderWithFolder:FolderTypeWith(FolderTypeAll, 0)];
        MCOIMAPSearchExpression* expr = [MCOIMAPSearchExpression searchRecipient:person.email];
        MCOIMAPSearchOperation* searchOperation = [self.imapSession searchExpressionOperationWithFolder:[self.user folderServerName:currentFolder]
                                                                                expression:expr];
        dispatch_async(self.s_queue, ^{
            [searchOperation start:^(NSError* error, MCOIndexSet* searchResult) {
                
                DDLogDebug(@"STARTED IMAP Search Expression Operation");

                if (error) {
                    DDLogError(@"Search Expression Operation error = %@",error);
                    
                    [subscriber sendError:error];
                    return;
                }
                
                [self _saveSearchResults:searchResult  withSubscriber:subscriber inFolder:currentFolder];
            }];
        });
        
        return [RACDisposable disposableWithBlock:^{}];
    }];
}

-(void) _saveSearchResults:(MCOIndexSet*)searchResult withSubscriber:(id<RACSubscriber>)subscriber inFolder:(NSInteger)currentFolder
{
    if (searchResult.count == 0) {
        DDLogError(@"Save Search Results error, count of results = 0");
        
        [subscriber sendCompleted];
        return;
    }
    
    if (!self.connected) {
        DDLogError(@"Save Search Results error, IMAP Sync Service not connected");
        
        [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMConnectionError userInfo:nil]];
        return;
    }
    

    NSString *folderServerName = [self.user folderServerName:currentFolder];
    
    MCOIMAPFetchMessagesOperation* imapMessagesFetchOp
    = [self.imapSession fetchMessagesOperationWithFolder:folderServerName
                                             requestKind:self.user.requestKind
                                                    uids:searchResult];
    
    dispatch_async(self.s_queue, ^{
        [imapMessagesFetchOp start:^(NSError* error, NSArray<MCOIMAPMessage*>* messages, MCOIndexSet* vanishedMessages){
            
            DDLogInfo(@"STARTED IMAP Messages Fetch Operation");
            
            if (error) {
                DDLogError(@"IMAP Messages Fetch Operation error = %@",error);
                
                [subscriber sendError:error];
                return;
            }
            
            NSString* lastMsgID = [messages firstObject].header.messageID;
            
            for (MCOIMAPMessage* msg in [messages reverseObjectEnumerator]) {
                [self _saveSearchedEmail:msg
                                inFolder:currentFolder
                          withSubscriber:subscriber
                               lastMsgID:lastMsgID];
            }
            
        }];
        
    });
    
}

-(void) _saveSearchedEmail:(MCOIMAPMessage*)msg inFolder:(NSInteger)currentFolder withSubscriber:(id<RACSubscriber>)subscriber lastMsgID:(NSString*)lastMsgID
{
    NSMutableDictionary* folderState = [[SyncManager getSingleton] retrieveState:currentFolder accountNum:self.user.accountNum];
    NSString* folderPath = folderState[@"folderPath"];
    
    Mail* email = [Mail mailWithMCOIMAPMessage:msg inFolder:currentFolder andAccount:self.user.accountNum];
    
    if ([UidEntry hasUidEntrywithMsgId:email.msgID inAccount:self.user.accountNum]) {
        
        [email loadBody];
        
        if (![UidEntry hasUidEntrywithMsgId:email.msgID withFolder:currentFolder inAccount:self.user.accountNum]) {
            // already have this email in other folder than this one -> add folder in uid_entry
            
            NSInvocationOperation* nextOp = [[NSInvocationOperation alloc] initWithTarget:[EmailProcessor getSingleton] selector:@selector(addToFolderWrapper:) object:[email uidEWithFolder:currentFolder]];
            
            nextOp.completionBlock = ^{
                [subscriber sendNext:email];
            };
            
            [[EmailProcessor getSingleton].operationQueue addOperation:nextOp];
        }
        else {
            [subscriber sendNext:email];
        }
        
        if ([email.msgID isEqualToString:lastMsgID]) {
            [subscriber sendCompleted];
        }
        //We already have email with folder
        return;
    }
    
    dispatch_async(self.s_queue, ^{
        
        [[self.imapSession plainTextBodyRenderingOperationWithMessage:msg folder:folderPath stripWhitespace:NO] start:^(NSString* plainTextBodyString, NSError* error) {
            
            DDLogInfo(@"START IMAP Session Text Body Rendering Operation");
            
            if (plainTextBodyString) {
                plainTextBodyString = [plainTextBodyString stringByReplacingCharactersInRange:NSMakeRange(0, 1) withString:@""];
                
                email.body = plainTextBodyString;
            }
            else {
                email.body = @"";
            }
            
            [[self.imapSession htmlBodyRenderingOperationWithMessage:msg folder:folderPath] start:^(NSString* htmlString, NSError* error) {
                email.htmlBody = htmlString;
                
                DDLogInfo(@"START IMAP Session HTML Body Rendering Operation");
                
                NSInvocationOperation* nextOp = [[NSInvocationOperation alloc] initWithTarget:[EmailProcessor getSingleton] selector:@selector(addEmailWrapper:) object:email];
                
                [[EmailProcessor getSingleton].operationQueue addOperation:nextOp];
                
                [nextOp waitUntilFinished];
                
                [subscriber sendNext:email];
                
                if ([email.msgID isEqualToString:lastMsgID]) {
                    [subscriber sendCompleted];
                }
            }];
        }];
        
    });
}

-(void) _checkFolders
{
    MCOIMAPFetchFoldersOperation* fio = [self.imapSession fetchAllFoldersOperation];
    
    dispatch_async(self.s_queue, ^{
        [fio start:^(NSError* error, NSArray* folders) {
            
            DDLogInfo(@"STARTED IMAP Session Fetch All Folders Operation");
            
            if ( error ) {
                DDLogError(@"IMAP Session Fetch All Folders Operation error = %@",error);
                return;
            }
            
            if (folders && folders.count > 0) {
                [self _checkFolderNamesForUpdates:folders];
            }
        }];
    });
}

-(void)_checkFolderNamesForUpdates:(NSArray *)folders
{
    DDAssert(folders, @"Folders Array must not be empty");
    DDAssert(folders.count>0, @"Folders Array must contain folders");
    
    // I believe this code block updates local IMAP Folder Names if any have
    // changed to the server (or something like that).
    
    // Appears not to handle DELETED folders.  What about folders with name CHANGES?
    
#warning more work to do here!
    SyncManager* sm = [SyncManager getSingleton];
    
    int indexPath = 0;
    
    NSMutableArray* dispNamesFolders = [[NSMutableArray alloc] initWithCapacity:1];
    
    for (MCOIMAPFolder* folder in folders) {
        BOOL folderPathInAccountsExistingFolders = NO;
        
        NSUInteger existingFolderCount = [sm folderCount:self.user.accountNum];
        
        // For each existing folder
        for (NSUInteger fIndex = 0; fIndex < existingFolderCount; fIndex++) {
            
            NSDictionary* folderState = [sm retrieveState:fIndex
                                               accountNum:self.user.accountNum];
            
            NSString* folderPath = folderState[@"folderPath"];
            
            if ([[folder path] isEqualToString:folderPath]) {
                folderPathInAccountsExistingFolders = YES;
                break;
            }
        }
        
        if ( folderPathInAccountsExistingFolders == FALSE ) {
            
            NSString* dispName = [[[self.imapSession defaultNamespace] componentsFromPath:[folder path]] componentsJoinedByString:@"/"];
            [dispNamesFolders addObject:dispName];
            
#warning Found this code in three places!
            NSDictionary* folderState = @{ @"accountNum" : @(self.user.accountNum),
                                           @"folderDisplayName":dispName,
                                           @"folderPath":folder.path,
                                           @"deleted":@false,
                                           @"fullsynced":@false,
                                           @"lastended":@0,
                                           @"flags":@(folder.flags),
                                           @"emailCount":@(0)};
            
            [sm addFolderState:folderState accountNum:self.user.accountNum];
            
            MCOIMAPFolderInfoOperation* folderOp = [self.imapSession folderInfoOperation:folder.path];
            [folderOp start:^(NSError* error, MCOIMAPFolderInfo* info) {
                if (!error) {
                    NSMutableDictionary* syncState = [sm retrieveState:indexPath accountNum:self.user.accountNum];
                    syncState[@"emailCount"] = @([info messageCount]);
                    [sm persistState:syncState forFolderNum:indexPath accountNum:self.user.accountNum];
                }
            }];
        }
        
        indexPath++;
    }
    
    if (dispNamesFolders.count > 0) {
        
        DDLogDebug(@"Adding Folders %@ to All Folder Names",dispNamesFolders);
        
        NSMutableArray* all = [NSMutableArray arrayWithArray:self.user.allFoldersDisplayNames];
        [all addObjectsFromArray:dispNamesFolders];
        
        [self.user setAllFoldersDisplayNames:all];
    }
}

// MARK: - IMAP Sync Service - Iterate through folders, syncing each
#warning Function is 1920 lines long!!!

-(RACSignal*) runFolder:(NSInteger)folder fromStart:(BOOL)isFromStart fromAccount:(BOOL)getAll
{
    DDLogInfo(@">> ENTERING ImapSync runFolder:%ld fromStart:%@ fromAccount:(getAll=%@):",
               folder,
               (isFromStart==TRUE?@"TRUE":@"FALSE"),
               (getAll==TRUE?@"TRUE":@"FALSE"));
    
    BOOL isInBackground = UIApplicationStateBackground == [UIApplication sharedApplication].applicationState;
    
    DDLogDebug(@"\tisInBackground = %@",
               (isInBackground==TRUE?@"TRUE":@"FALSE") );
    
    if (folder == -1) {
        folder = [self nextFolderToSync];
        DDLogDebug(@"\tfolder was -1, CALLED -[self nextFolderToSync]");
    }
    DDLogDebug(@"\tfolder= %ld",folder);
    
    NSInteger currentFolder = folder;
    
    if (!self.cachedData) {
        self.cachedData = [[NSMutableArray alloc]initWithCapacity:1];
    }
    
    @weakify(self);
    
    return [RACSignal startLazilyWithScheduler:[RACScheduler schedulerWithPriority:RACSchedulerPriorityBackground] block:^(id<RACSubscriber> subscriber) {
        
        @strongify(self);
        // get list of all folders
        
        if (self.isCanceled) {
            DDLogInfo(@"IMAP Sync Service: CANCELLED, runFolder COMPLETED");
            [subscriber sendCompleted];
        }
        else if (![ImapSync isNetworkAvailable]) {
            DDLogError(@"IMAP Sync Service: Network is not available error");
            
            self.connected = NO;
            [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMConnectionError userInfo:nil]];
        }
        else if (currentFolder == -1) {
            DDLogError(@"IMAP Sync Service: All Synced Error");
            
            [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMAllSyncedError userInfo:nil]];
        }
        else if (isInBackground && currentFolder != [self.user numFolderWithFolder:FolderTypeWith(FolderTypeInbox, 0)]) {
            DDLogInfo(@"IMAP Sync Service: runFolder COMPLETED");

            [subscriber sendCompleted];
        }
        else {
            [[ImapSync doLogin:self.user] subscribeError:^(NSError *error) {
                [subscriber sendError:error];
            } completed:^{
                if (!self.connected) {
                    if (isInBackground) {
                        DDLogInfo(@"IMAP Sync Service: Not Connected, but in Background, so runFolder COMPLETED");

                        [subscriber sendCompleted];
                    }
                    else {
                        DDLogError(@"IMAP Sync Service: Not Connection Error");
                        
                        [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMConnectionError userInfo:nil]];
                    }
                }
                else {
                    MCOIMAPFetchFoldersOperation* fio = [self.imapSession fetchAllFoldersOperation];
                    dispatch_async(self.s_queue, ^{
                        DDLogInfo(@"STARTING IMAP Sync Service: Fetch Folder Operation");
                        
                        [fio start:^(NSError* error, NSArray* folders) {
                            if (error) {
                                DDLogError(@"IMAP Sync Service: Fetch Folder op error = %@",error.description);
                                
                                self.connected = NO;
                                [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMConnectionError userInfo:nil]];
                                
                                return;
                            }
                            else if (!folders || folders.count == 0) {
                                DDLogInfo(@"IMAP Sync Service: No Folders, so Completed");
                                
                                [subscriber sendCompleted];
                                
                                return;
                            }//Fetch folder issue
                            
                            dispatch_async(self.s_queue, ^{
                                
                                
#warning Look: Almost the same code as _checkFolders again!
                                SyncManager* sm = [SyncManager getSingleton];
                                // mark folders that were deleted on the server as deleted on the client
                                int i = 0;
                                
                                while (i < [sm folderCount:self.user.accountNum]) {
                                    NSDictionary* folderState = [sm retrieveState:i accountNum:self.user.accountNum];
                                    NSString* folderPath = folderState[@"folderPath"];
                                    
                                    if ([sm isFolderDeleted:i accountNum:self.user.accountNum]) {
                                        //NSLog(@"Folder %i in account %ld is deleted", i, (long)self.user.accountNum);
                                    }
                                    
                                    if (![sm isFolderDeleted:i accountNum:self.user.accountNum] && ![[folders valueForKey:@"path"] containsObject:folderPath]) {
                                        CCMLog(@"Folder %@ has been deleted - deleting FolderState", folderPath);
                                        [sm markFolderDeleted:i accountNum:self.user.accountNum];
                                        i = 0;
                                    }
                                    
                                    i++;
                                }
                                
                                //If the folder is Deleted & it's an important Folder
                                //Check for another
                                if ([sm isFolderDeleted:currentFolder accountNum:self.user.accountNum]) {
                                    
                                    CCMFolderType f = [self.user typeOfFolder:currentFolder];
                                    
                                    if (f.type != FolderTypeUser) {
                                        
                                        MCOMailProvider* accountProvider = [[MCOMailProvidersManager sharedManager] providerForIdentifier:self.user.identifier];
                                        
                                        for (MCOIMAPFolder* folder in folders) {
                                            
                                            if (folder.flags & MCOIMAPFolderFlagNoSelect) {
                                                continue;
                                            }
                                            
                                            NSString* newFolderPath = @"";
                                            
                                            if (f.type == FolderTypeInbox &&  ((folder.flags == MCOIMAPFolderFlagInbox) || [folder.path  isEqualToString: @"INBOX"])) {
                                                newFolderPath = folder.path;
                                                //[self.user setImportantFolderNum:indexPath forBaseFolder:FolderTypeInbox];
                                            } //Starred
                                            else if(f.type == FolderTypeFavoris &&  ([accountProvider.starredFolderPath isEqualToString:folder.path] || (folder.flags == MCOIMAPFolderFlagFlagged))) {
                                                newFolderPath = folder.path;
                                                //[self.user setImportantFolderNum:indexPath forBaseFolder:FolderTypeFavoris];
                                            } //Sent
                                            else if(f.type == FolderTypeSent &&  ([accountProvider.sentMailFolderPath isEqualToString:folder.path] || (folder.flags == MCOIMAPFolderFlagSentMail))) {
                                                newFolderPath = folder.path;
                                                //[self.user setImportantFolderNum:indexPath forBaseFolder:FolderTypeSent];
                                            } //Draft
                                            else if(f.type == FolderTypeDrafts &&  ([accountProvider.draftsFolderPath isEqualToString:folder.path] || (folder.flags == MCOIMAPFolderFlagDrafts))) {
                                                newFolderPath = folder.path;
                                                //[self.user setImportantFolderNum:indexPath forBaseFolder:FolderTypeDrafts];
                                            } //Archive
                                            else if(f.type == FolderTypeAll &&  ([accountProvider.allMailFolderPath isEqualToString:folder.path] || ((folder.flags == MCOIMAPFolderFlagAll) || (folder.flags == MCOIMAPFolderFlagAllMail)))) {
                                                newFolderPath = folder.path;
                                                //[self.user setImportantFolderNum:indexPath forBaseFolder:FolderTypeAll];
                                            } //Trash
                                            else if(f.type == FolderTypeDeleted &&  ([accountProvider.trashFolderPath isEqualToString:folder.path] || (folder.flags == MCOIMAPFolderFlagTrash))) {
                                                newFolderPath = folder.path;
                                                //[self.user setImportantFolderNum:indexPath forBaseFolder:FolderTypeDeleted];
                                            } //Spam
                                            else if(f.type == FolderTypeSpam &&  ([accountProvider.spamFolderPath isEqualToString:folder.path] || (folder.flags == MCOIMAPFolderFlagSpam))) {
                                                newFolderPath = folder.path;
                                                //[self.user setImportantFolderNum:indexPath forBaseFolder:FolderTypeSpam];
                                            }
                                            
                                            if (![newFolderPath isEqualToString:@""]) {
                                                int i = 0;
                                                
                                                while (i < [sm folderCount:self.user.accountNum]) {
                                                    NSDictionary* folderState = [sm retrieveState:i accountNum:self.user.accountNum];
                                                    NSString* folderPath = folderState[@"folderPath"];
                                                    
                                                    if ([newFolderPath isEqualToString:folderPath]) {
                                                        [self.user setImportantFolderNum:i forBaseFolder:f.type];
                                                    }
                                                    
                                                    i++;
                                                }
                                            }//Set new important folder index
                                        }//Is there other folder same importance/role
                                    }//If important folder
                                }//If folder deleted
                                
                                NSMutableDictionary* folderState = [sm retrieveState:currentFolder accountNum:self.user.accountNum];
                                NSString* folderPath = folderState[@"folderPath"];
                                
                                MCOIMAPFolderInfoOperation* folder = [self.imapSession folderInfoOperation:folderPath];
                                NSInteger lastEnded = [folderState[@"lastended"] integerValue];
                                
                                [folder start:^(NSError* error, MCOIMAPFolderInfo* info) {
                                    if (error) {
                                        DDLogError(@"Error %@ fetching folder %@",error.description, folderPath);
                                        
                                        self.connected = NO;
                                        [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMConnectionError userInfo:nil]];
                                        
                                        return;
                                    }
                                    if (self.isCanceled) {
                                        [subscriber sendCompleted];
                                        return;
                                    }
                                    
                                    dispatch_async(self.s_queue, ^{
                                        
                                        int batchsize = 20;
                                        
                                        //if (!isFromStart) {
                                        batchsize = 50;
                                        //}
                                        
                                        DDLogDebug(@"Folder:%@ has %d emails", folderPath, [info messageCount]);
                                        
                                        if (!isInBackground) {
                                            [self _writeFinishedFolderState:sm emailCount:[info messageCount] andFolder:currentFolder];
                                            
                                            if ([info messageCount] == 0 || (!isFromStart && (lastEnded == 1))) {
                                                NSInteger lE = ([info messageCount] == 0)?1:lastEnded;
                                                [self _writeFinishedFolderState:sm lastEnded:lE andFolder:currentFolder];
                                                
                                                [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMFolderSyncedError userInfo:nil]];
                                                return;
                                            }
                                        }
                                        
                                        NSInteger from = [info messageCount];
                                        
                                        if (!(isFromStart || isInBackground) && lastEnded != 0) {
                                            from = lastEnded-1;
                                        }
                                        
                                        uint64_t batch = MIN(batchsize, [info messageCount]);
                                        
                                        batch--;
                                        
                                        if (from > batch) {
                                            from -= batch;
                                        }
                                        else {
                                            from = 1;
                                        }
                                        
                                        MCOIndexSet* numbers = [MCOIndexSet indexSetWithRange:MCORangeMake(from, batch)];
                                        MCOIMAPFetchMessagesOperation* imapMessagesFetchOp = [self.imapSession fetchMessagesByNumberOperationWithFolder:folderPath
                                                                                                                                            requestKind:self.user.requestKind
                                                                                                                                                numbers:numbers];
                                        
                                        [imapMessagesFetchOp start:^(NSError* error, NSArray<MCOIMAPMessage*>* messages, MCOIndexSet* vanishedMessages) {
                                            if (error) {
                                                DDLogError(@"Error %@ fetching messages in folder %@",error.description, folderPath);
                                                
                                                self.connected = NO;
                                                [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMConnectionError userInfo:nil]];
                                                
                                                return;
                                            }
                                            
                                            dispatch_async(self.s_queue, ^{
                                                
                                                NSString* lastMsgID = [messages lastObject].header.messageID;
                                                
                                                DDLogInfo(@"Retrieve %lu Messages from IMAP Server",(unsigned long)messages.count);
                                                
                                                for (MCOIMAPMessage* msg in messages) {
                                                    if (self.isCanceled) {
                                                        [subscriber sendCompleted];
                                                        return;
                                                    }
                                                    
                                                    NSMutableDictionary* folderState = [sm retrieveState:currentFolder accountNum:self.user.accountNum];
                                                    NSString* folderPath = folderState[@"folderPath"];
                                                    
                                                    Mail* email = [Mail mailWithMCOIMAPMessage:msg inFolder:currentFolder andAccount:self.user.accountNum];
                                                    
                                                    if ([UidEntry hasUidEntrywithMsgId:email.msgID inAccount:self.user.accountNum]) {
                                                        
                                                        if (![UidEntry hasUidEntrywithMsgId:email.msgID withFolder:currentFolder inAccount:self.user.accountNum]) {
                                                            // already have this email in other folder than this one -> add folder in uid_entry
                                                            
                                                            NSInvocationOperation* nextOp = [[NSInvocationOperation alloc] initWithTarget:[EmailProcessor getSingleton] selector:@selector(addToFolderWrapper:) object:[email uidEWithFolder:currentFolder]];
                                                            
                                                            nextOp.completionBlock = ^{
                                                                if ((currentFolder == [Accounts sharedInstance].currentAccount.currentFolderIdx) | getAll) {
                                                                    [email loadBody];
                                                                    [subscriber sendNext:email];
                                                                }
                                                            };
                                                            
                                                            [[EmailProcessor getSingleton].operationQueue addOperation:nextOp];
                                                        }
                                                        
                                                        if ([email.msgID isEqualToString:lastMsgID]) {
                                                            if (!isFromStart && !isInBackground) {
                                                                [self _writeFinishedFolderState:sm lastEnded:from andFolder:currentFolder];
                                                            }
                                                            [subscriber sendCompleted];
                                                        }
                                                        
                                                        //We already have email with folder
                                                        continue;
                                                    }
                                                    
                                                    [[self.imapSession plainTextBodyRenderingOperationWithMessage:msg folder:folderPath stripWhitespace:NO] start:^(NSString* plainTextBodyString, NSError* error) {
                                                        
                                                        if (plainTextBodyString) {
                                                            plainTextBodyString = [plainTextBodyString stringByReplacingCharactersInRange:NSMakeRange(0, 1) withString:@""];
                                                            
                                                            email.body = plainTextBodyString;
                                                        }
                                                        else {
                                                            email.body = @"";
                                                        }
                                                        
                                                        NSDate* month = [[NSDate date] dateByAddingTimeInterval:- 60 * 60 * 24 * 30];
                                                        
                                                        if ([email.datetime compare:month] == NSOrderedAscending) {
                                                            BOOL isNew = [self _saveEmail:email inBackground:isInBackground folder:currentFolder];
                                                            
                                                            if ((currentFolder == [Accounts sharedInstance].currentAccount.currentFolderIdx) | getAll) {
                                                                if (isInBackground) {
                                                                    if (isNew) {
                                                                        [subscriber sendNext:email];
                                                                    }
                                                                }
                                                                else {
                                                                    [subscriber sendNext:email];
                                                                }
                                                            }
                                                            
                                                            if ([email.msgID isEqualToString:lastMsgID]) {
                                                                if (!isFromStart && !isInBackground) {
                                                                    [self _writeFinishedFolderState:sm lastEnded:from andFolder:currentFolder];
                                                                }
                                                                [subscriber sendCompleted];
                                                            }
                                                        }
                                                        else {
                                                            [[self.imapSession htmlBodyRenderingOperationWithMessage:msg folder:folderPath] start:^(NSString* htmlString, NSError* error) {
                                                                email.htmlBody = htmlString;
                                                                
                                                                BOOL isNew = [self _saveEmail:email inBackground:isInBackground folder:currentFolder];
                                                                
                                                                if ((currentFolder == [Accounts sharedInstance].currentAccount.currentFolderIdx) | getAll) {
                                                                    if (isInBackground) {
                                                                        if (isNew) {
                                                                            [subscriber sendNext:email];
                                                                        }
                                                                    }
                                                                    else {
                                                                        [subscriber sendNext:email];
                                                                    }
                                                                }
                                                                
                                                                if ([email.msgID isEqualToString:lastMsgID]) {
                                                                    if (!isFromStart && !isInBackground) {
                                                                        [self _writeFinishedFolderState:sm lastEnded:from andFolder:currentFolder];
                                                                    }
                                                                    [subscriber sendCompleted];
                                                                }
                                                            }];
                                                        }
                                                    }];
                                                }
                                            });
                                        }];//Fetch Messages
                                    });
                                }];//Fetch folder Info
                            });
                        }];//Fetch All Folders
                    });
                }
            }];
        }
    }];
}

-(BOOL) _saveEmail:(Mail*)email inBackground:(BOOL)isInBackground folder:(NSInteger)currentFolder
{
    //Cache email if in Background
    if (isInBackground) {
        
        BOOL isInInbox = (currentFolder == [self.user numFolderWithFolder:FolderTypeWith(FolderTypeInbox, 0)]);
        BOOL isUnread = !(email.flag & MCOMessageFlagSeen);
        
        if (isInInbox & isUnread) {
            NSMutableSet* eIds = [self emailIDs];
            
            if (![eIds containsObject:email.msgID]) {
                Mail* newE = [email copy];
                CCMLog(@"Had Cached %ld Emails in account:%ld", (unsigned long)eIds.count, (long)[email.uids[0] accountNum]);
                
                //[self.cachedData addObject:newE];
                [eIds addObject:newE.msgID];
                [AppSettings getSingleton].cache = [eIds allObjects];
                
                
                NSInvocationOperation* nextOp = [[NSInvocationOperation alloc] initWithTarget:[EmailProcessor getSingleton] selector:@selector(addEmailWrapper:) object:email];
                
                // NSInvocationOperation* nextOp = [[NSInvocationOperation alloc] initWithTarget:[EmailProcessor getSingleton] selector:@selector(addToFolderWrapper:) object:newE.uids[0]];
                [[EmailProcessor getSingleton].operationQueue addOperation:nextOp];
                [[EmailProcessor getSingleton].operationQueue waitUntilAllOperationsAreFinished];
                
                Conversation* conv = [[Conversation alloc] init];
                [conv addMail:email];
                
                ConversationIndex* index = [ConversationIndex initWithIndex:[email.user.linkedAccount addConversation:conv] user:email.user]; ;
                
                if (isUnread && [AppSettings notifications:self.user.accountNum]) {
                    
                    UILocalNotification* localNotification = [[UILocalNotification alloc] init];
                    localNotification.fireDate = [NSDate dateWithTimeIntervalSinceNow:10];
                    NSString* alertText = [[NSString alloc]initWithFormat:@"%@\n%@%@", email.sender.displayName, (email.hasAttachments?@"📎 ":@""), email.subject];
                    alertText = [alertText stringByReplacingOccurrencesOfString:@"%" withString:@"%%"];
                    localNotification.alertBody = alertText;
                    localNotification.timeZone = [NSTimeZone defaultTimeZone];
                    localNotification.userInfo = @{@"cIndexIndex":@(index.index),
                                                   @"cIndexAccountNum":@(index.user.accountNum)};
                    localNotification.category = @"MAIL_CATEGORY";
                    
                    NSLog(@"Index: %ld",(long)index.index);
                    NSLog(@"Conversation: %@",[conv firstMail].subject);
                    
                    [[UIApplication sharedApplication] presentLocalNotificationNow:localNotification];
                }
                
                return YES;
            }
        }
    }
    else {
        NSInvocationOperation* nextOp = [[NSInvocationOperation alloc] initWithTarget:[EmailProcessor getSingleton] selector:@selector(addEmailWrapper:) object:email];
        
        [[EmailProcessor getSingleton].operationQueue addOperation:nextOp];
        [[EmailProcessor getSingleton].operationQueue waitUntilAllOperationsAreFinished];
    }
    
    return NO;
}

-(NSMutableSet *) emailIDs
{
    return [NSMutableSet setWithArray:[[AppSettings getSingleton] cache]];
}

-(void) _writeFinishedFolderState:(SyncManager*)sm emailCount:(NSInteger)count andFolder:(NSInteger)folder
{
    if (!self.user.isDeleted) {
        
        // used by fetchFrom to write the finished state for this round of syncing to disk
        NSMutableDictionary* syncState = [sm retrieveState:folder accountNum:self.user.accountNum];
        syncState[@"emailCount"] = @(count);
        
        [sm persistState:syncState forFolderNum:folder accountNum:self.user.accountNum];
    }
}

-(void) _writeFinishedFolderState:(SyncManager*)sm lastEnded:(NSInteger)lastEIndex andFolder:(NSInteger)folder
{
    // used by fetchFrom to write the finished state for this round of syncing to disk
    if (!self.user.isDeleted) {
        NSMutableDictionary* syncState = [sm retrieveState:folder accountNum:self.user.accountNum];
        syncState[@"lastended"] = @(lastEIndex);
        syncState[@"fullsynced"] = @(lastEIndex == 1);
        
        [sm persistState:syncState forFolderNum:folder accountNum:self.user.accountNum];
        //[[[Accounts sharedInstance] getAccount:self.currentAccountIndex] showProgress];
    }
}

-(void) runUpToDateCachedTest:(NSArray*)emails
{
    MCOIndexSet* uidsIS = [[MCOIndexSet alloc]init];
    NSString* path = [self.user folderServerName:[[Accounts sharedInstance].currentAccount currentFolderIdx]];
    
    NSMutableArray* datas = [[NSMutableArray alloc]init];
    
    for (Mail* email in emails) {
        //TODO: Get the right uid corresponding to the message id and folder
        
        UidEntry* uid_entry = [UidEntry getUidEntryWithFolder:[[Accounts sharedInstance].currentAccount currentFolderIdx] msgID:email.msgID];
        [uidsIS addIndex:uid_entry.uid];
        
        NSMutableDictionary* dict = [NSMutableDictionary dictionary];
        dict[@"email"] = email;
        dict[@"uid_entry"] = uid_entry;
        [datas addObject:dict];
    }
    
    if (!self.connected){
        return;
    }
    
    [[ImapSync doLogin:self.user]
     subscribeError:^(NSError *error) {
     } completed:^{
         
         MCOIMAPFetchMessagesOperation* op = [self.imapSession  fetchMessagesOperationWithFolder:path requestKind:MCOIMAPMessagesRequestKindFlags uids:uidsIS];
         
         dispatch_async(self.s_queue, ^{
             [op start:^(NSError* error, NSArray* messages, MCOIndexSet* vanishedMessages) {
                 
                 if (error) {
                     [self setConnected:NO];
                     NSLog(@"error testing cached emails in %@, %@", path, error);
                     return;
                 }
                 
                 EmailProcessor* ep = [EmailProcessor getSingleton];
                 
                 for (MCOIMAPMessage* msg in messages) {
                     //If in this folder or cross check in other folder
                     if ([uidsIS containsIndex:msg.uid]) {
                         //Don't Delete
                         [uidsIS removeIndex:msg.uid];
                     }
                 }
                 
                 NSMutableArray* delDatas = [[NSMutableArray alloc]init];
                 NSMutableArray* upDatas = [[NSMutableArray alloc]init];
                 
                 
                 for (NSMutableDictionary* data in datas) {
                     UidEntry* uid_entry = data[@"uid_entry"];
                     Mail* email = data[@"email"];
                     
                     if ([uidsIS containsIndex:uid_entry.uid]) {
                         //Remove email from local folder
                         [delDatas addObject:data];
                     }
                     else {
                         for (MCOIMAPMessage* msg in messages) {
                             if (msg.uid == uid_entry.uid && !(msg.flags & email.flag)) {
                                 email.flag = msg.flags;
                                 data[@"email"] = email;
                                 [upDatas addObject:data];
                             }
                         }
                         
                     }
                 }
                 
                 NSDictionary* data = [[NSDictionary alloc]initWithObjects:@[delDatas,@([[Accounts sharedInstance].currentAccount currentFolderIdx])] forKeys:@[@"datas",@"folderIdx"]];
                 NSInvocationOperation* nextOpDel = [[NSInvocationOperation alloc] initWithTarget:ep selector:@selector(removeFromFolderWrapper:) object:data];
                 [ep.operationQueue addOperation:nextOpDel];
                 
                 NSInvocationOperation* nextOpUp = [[NSInvocationOperation alloc] initWithTarget:ep selector:@selector(updateFlag:) object:upDatas];
                 [ep.operationQueue addOperation:nextOpUp];
             }];
         });
         
     }];
    return;
}


// MARK: - Up to Date Test

-(void) runUpToDateTest:(NSArray*)convs folderIndex:(NSInteger)folderIdx completed:(void (^)(NSArray* dels, NSArray* ups, NSArray* days))completedBlock
{
    MCOIndexSet* uidsIS = [[MCOIndexSet alloc]init];
    NSString* path = [self.user folderServerName:folderIdx];
    
    NSMutableArray* mails = [NSMutableArray arrayWithCapacity:convs.count];
    
    for (Conversation* conv in convs) {
        for (Mail* mail in conv.mails) {
            if ([mail uidEWithFolder:folderIdx]) {
                [uidsIS addIndex:[mail uidEWithFolder:folderIdx].uid];
                [mails addObject:mail];
            }
        }
    }
    
    //NSLog(@"Testing folder %@ with %i emails in accountIndex:%ld", path, uidsIS.count, (long)self.currentAccountIndex);
    
    if (uidsIS.count == 0) {
        completedBlock(nil, nil, nil);
        return;
    }
    
    NSMutableArray* delDatas = [[NSMutableArray alloc]init];
    NSMutableArray* upDatas = [[NSMutableArray alloc]init];
    NSMutableArray* days = [[NSMutableArray alloc]init];

    [[ImapSync doLogin:self.user]
     subscribeError:^(NSError *error) {
         completedBlock(delDatas, upDatas, days);
     } completed:^{
         
         if (!self.connected){
             completedBlock(delDatas, upDatas, days);
             return;
         }
         
         MCOIMAPFetchMessagesOperation* op = [self.imapSession fetchMessagesOperationWithFolder:path requestKind:MCOIMAPMessagesRequestKindHeaders | MCOIMAPMessagesRequestKindFlags uids:uidsIS];
         dispatch_async(self.s_queue, ^{
             [op start:^(NSError* error, NSArray* messages, MCOIndexSet* vanishedMessages) {
                 
                 if (error) {
                     [self setConnected:NO];
                     NSLog(@"error testing emails in %@, %@", path, error);
                     completedBlock(delDatas, upDatas, days);
                     return;
                 }
                 
                 
                 
                 //NSLog(@"Connected and Testing folder %@ in accountIndex:%ld", path, (long)self.currentAccountIndex);
                 
                 EmailProcessor* ep = [EmailProcessor getSingleton];
                 
                 for (MCOIMAPMessage* msg in messages) {
                     //If in this folder or cross check in other folder
                     if ([uidsIS containsIndex:msg.uid]) {
                         //Don't Delete
                         [uidsIS removeIndex:msg.uid];
                     }
                 }
                 
                 for (Mail* mail in mails) {
                     UidEntry* uid_entry = [mail uidEWithFolder:folderIdx];
                     
                     if ([uidsIS containsIndex:uid_entry.uid]) {
                         //Remove email from local folder
                         [delDatas addObject:mail];
                     }
                     else {
                         for (MCOIMAPMessage* msg in messages) {
                             if (msg.uid == uid_entry.uid && msg.flags != mail.flag) {
                                 mail.flag = msg.flags;
                                 [upDatas addObject:mail];
                             }
                         }
                     }
                 }
                 
                 if (delDatas.count > 0) {
                     //NSLog(@"Delete %lu emails", (unsigned long)delDatas.count);
                     NSDictionary* data = [[NSDictionary alloc]initWithObjects:@[delDatas,@(folderIdx)] forKeys:@[@"datas",@"folderIdx"]];
                     NSInvocationOperation* nextOp = [[NSInvocationOperation alloc] initWithTarget:ep selector:@selector(removeFromFolderWrapper:) object:data];
                     [ep.operationQueue addOperation:nextOp];
                 }
                 
                 if (upDatas.count > 0) {
                     //NSLog(@"Update %lu emails", (unsigned long)upDatas.count);
                     NSInvocationOperation* nextOp = [[NSInvocationOperation alloc] initWithTarget:ep selector:@selector(updateFlag:) object:upDatas];
                     [ep.operationQueue addOperation:nextOp];
                 }
                 
                 for (Mail* mail in delDatas) {
                     BOOL contains = NO;
                     for (NSString* day in days) {
                         if ([day isEqualToString:mail.day]) {
                             contains = YES;
                             break;
                         }
                     }
                     
                     if (!contains) {
                         [days addObject:mail.day];
                     }
                 }
                 
                 for (Mail* mail in upDatas) {
                     BOOL contains = NO;
                     for (NSString* day in days) {
                         if ([day isEqualToString:mail.day]) {
                             contains = YES;
                             break;
                         }                     }
                     
                     if (!contains) {
                         [days addObject:mail.day];
                     }
                 }
                 
                 completedBlock(delDatas, upDatas, days);
             }];
         });
     }];
    return;
}

-(void) checkForCachedActions
{
    NSMutableArray* cachedActions = [CachedAction getActionsForAccount:self.user.accountNum];
    
    for (CachedAction* cachedAction in cachedActions) {
        [cachedAction doAction];
    }
}

+(NSString *)_networkStatusText:(NetworkStatus)status
{
    NSMutableString *msg = [NSMutableString stringWithString:@"Network Status: "];
    switch (status) {
        case NotReachable:
            [msg appendString:@"NotReachable"];
            break;
        case ReachableViaWiFi:
            [msg appendString:@"ReachableViaWiFi"];
            break;
        case ReachableViaWWAN:
            [msg appendString:@"ReachableViaWWAN"];
            break;
        default:
            [msg appendString:@"Unknown Value"];
            break;
    }
    if ([[AppSettings getSingleton] canSyncOverData]) {
        [msg appendString:@" and canSyncOverData"];
    }
    return msg;
}
+(BOOL) isNetworkAvailable
{
    Reachability* networkReachability = [Reachability reachabilityForInternetConnection];
    NetworkStatus networkStatus = [networkReachability currentReachabilityStatus];

    DDLogInfo(@"%@",[self _networkStatusText:networkStatus]);

    return (networkStatus != NotReachable);
}

+(BOOL) canFullSync
{
    Reachability* networkReachability = [Reachability reachabilityForInternetConnection];
    NetworkStatus networkStatus = [networkReachability currentReachabilityStatus];
    
    DDLogInfo(@"%@",[self _networkStatusText:networkStatus]);

    return [[AppSettings getSingleton] canSyncOverData] || (networkStatus == ReachableViaWiFi);
}

+(void) runInboxUnread:(UserSettings*)user
{
    [ImapSync runInboxUnread:user completed:^{}];
}

// Get the Unread Count for User's Inbox
+(void) runInboxUnread:(UserSettings*)user completed:(void (^)(void))completedBlock
{
    DDLogInfo(@"ENTERED Get Inbox Unread Count");
    
    if (![ImapSync isNetworkAvailable] | user.isAll) {
        DDLogInfo(@"\tNetwork is not available OR this is All account");
        completedBlock();
        return;
    }
    
    dispatch_async([ImapSync sharedServices:user].s_queue, ^{
        NSInteger inboxFolder = [user numFolderWithFolder:FolderTypeWith(FolderTypeInbox, 0)];
        NSString* serverFolderPath = [user folderServerName:inboxFolder];
        MCOIMAPSearchExpression* expr = [MCOIMAPSearchExpression searchUnread];
        MCOIMAPSearchOperation* so = [[ImapSync sharedServices:user].imapSession searchExpressionOperationWithFolder:serverFolderPath expression:expr];
        
        [so start:^(NSError* error, MCOIndexSet* searchResult) {
            DDLogInfo(@"STARTED Search for All Unread Mails Operation");
            
            if (!error) {
                DDLogInfo(@"Got Inbox Unread search results, count = %u",searchResult.count);
                
                [AppSettings setInboxUnread:searchResult.count accountIndex:user.accountIndex];
            }
            else {
                DDLogError(@"Search for All Unread Mails Operation Failed, error = %@",error);
            }
            completedBlock();
        }];
    });
}



@end
