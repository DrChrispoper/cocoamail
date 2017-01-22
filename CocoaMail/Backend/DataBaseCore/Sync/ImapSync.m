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

#define ONE_MONTH_IN_SECONDS    ( 60 * 60 * 24 * 30 )

@interface ImapSync ()

@property (nonatomic) UserSettings* user;
@property (nonatomic, strong) MCOIMAPOperation* imapCheckOp;
@property (nonatomic) BOOL isCanceled;

@end

static NSArray<ImapSync*>* sharedServices = nil;


@implementation ImapSync

// Returns the IMAP Sync Service for the given User's Account
// Returns nil if not matching account
//
+(ImapSync*) sharedServices:(UserSettings*)user
{
    DDAssert(user, @"No user at accountNum:%ld",(long)user.accountNum);
    
    DDAssert(!user.isDeleted, @"AccountNum:%ld is deleted",(long)user.accountNum);
    
    // Find the shared IMAP Sync Service with the matching Account Number
    NSArray<ImapSync*>* allSharedServices = [ImapSync allSharedServices:nil];
    for (ImapSync* sharedService in allSharedServices) {
        if (sharedService.user.accountNum == user.accountNum) {
            return sharedService;
        } else {
            DDLogInfo(@"sharedService.user.accountNum %@ NOT EQUAL TO user.accountNum %@",
                      @(sharedService.user.accountNum),@(user.accountNum));
        }
    }
    
    DDLogError(@"Unable to find Account Number %@",@(user.accountNum));
    
    return nil;
}

+(NSArray<ImapSync*>*) allSharedServices:(MCOIMAPSession*)updated
{
    if (updated) {
        sharedServices = nil;
    }
    
    @synchronized(self) {
        
        // If we already have one or more shared services, then return them
        if (sharedServices && sharedServices.count > 0) {
            DDLogInfo(@"[ImapSync allSharedServices] returning existing sharedServices array.");
            return sharedServices;
        }
        
        DDLogInfo(@"[ImapSync allSharedServices] creating new sharedServices array, one for each User.");
        
        // Create new sharedServices, one for each user.
        
        NSMutableArray* newSharedServices = [[NSMutableArray alloc]init];
        
        NSArray<UserSettings*>* allUsers = [AppSettings getSingleton].users;
        
        // Create a new ImapSync Shared Service for each (non deleted) user
        for (UserSettings* user in allUsers ) {
            
            if (user.isDeleted) {
                continue;   // next UserSettings
            }
            
            DDLogInfo(@"Create new Shared Service to Username \"%@\" (acnt # %@)",user.username,@(user.accountNum));
            
            // Create and set up new Imap Sync Shared Service
            ImapSync* sharedService = [[super allocWithZone:nil] init];
            sharedService.user = user;
            sharedService.connected = NO;
            
            sharedService.s_queue = dispatch_queue_create(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
            
            // If an updated Imap Session was passed in, and its username matches this user, then update the new service
            if (updated && [updated.username isEqualToString:user.username]) {
                sharedService.imapSession = updated;
                sharedService.imapSession.dispatchQueue = sharedService.s_queue;
                sharedService.connected = YES;
            }
            else {
                // We do not have an updated IMAP Session with a user that matches this one
                
                dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
                
                dispatch_async(sharedService.s_queue, ^{
                    sharedService.imapSession = [AppSettings imapSession:user];
                    sharedService.imapSession.dispatchQueue = sharedService.s_queue;
                    dispatch_semaphore_signal(semaphore);
                });
                
                dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
                
                sharedService.connected = NO;
            }
            
            [newSharedServices addObject:sharedService];
        }
        
        sharedServices = [[NSArray alloc]initWithArray:newSharedServices];
        
        return sharedServices;
        
    } // end @synchronized(self)
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
    DDLogInfo(@"ENTERED IMAP Sync Servier: Do Login for \"%@\"]",user.username);
    
    if (!user || user.isDeleted) {
        
        DDLogInfo(@"\tHave no user or user is deleted");
        
        return [RACSignal startEagerlyWithScheduler:[RACScheduler scheduler] block:^(id<RACSubscriber> subscriber) {
            [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMDeletedError userInfo:nil]];
        }];
    }

    // TODO: Consider moving this off the stack
    ImapSync* sharedService = [ImapSync sharedServices:user];
    
    if (!sharedService) {
        
        DDLogInfo(@"\tHave no Shared ImapSync Services for User \"%@\"",user.username);
        
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
    
    DDLogInfo(@"CURIOUS: user %@ sharedSettings.user",(user==sharedService.user?@"EQUAL":@"DOES NOT EQUAL"));

    if (![ImapSync isNetworkAvailable]) {
        
        DDLogInfo(@"\t+[ImapSync isNetworkAvailable] returned NO");
        
        return [RACSignal startEagerlyWithScheduler:[RACScheduler scheduler] block:^(id<RACSubscriber> subscriber) {
            sharedService.connected = NO;
            [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain
                                                      code:CCMConnectionError
                                                  userInfo:nil]];
        }];
    }
    
    
    if ( sharedService.signal ) {
        
        DDLogInfo(@"\tReturning (existing) Shared IMAP Sync Service Signal");
        
        return sharedService.signal;
    }
    
    DDLogInfo(@"\tCREATE NEW Shared IMAP Sync Service Signal.");
    
    sharedService.signal = [RACSignal startEagerlyWithScheduler:[RACScheduler scheduler]
                      block:^(id<RACSubscriber> subscriber)
    {
        if (sharedService.connected) {
            DDLogInfo(@"\tShared IMAP Sync Service is Connected");
            [subscriber sendCompleted];
            return;
        }

        DDLogInfo(@"\tShared IMAP Sync Service is NOT Connected");

        if ([sharedService.user isUsingOAuth]) {
            DDLogInfo(@"\tAttempting to log in with OAuth.");

            [self _loginWithOAuth:sharedService forUser:user withSubscriber:subscriber];
        }
        else { //Not using OAuth
            DDLogInfo(@"\tAttempting to log in with Password.");

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
                                            [sharedService getImapFolderNamesAndUpdateLocal];
                                            
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
                [sharedService getImapFolderNamesAndUpdateLocal];
                
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
                [sharedService getImapFolderNamesAndUpdateLocal];
                
                [subscriber sendCompleted];
            }
            
        }];
    });
}

// MARK: - Strip IMAP Folder Prefix from Folder Path

+(NSString *)displayNameForFolder:(MCOIMAPFolder*)folder usingSession:(MCOIMAPSession*)imapSession
{
    DDAssert(folder,@"MCOIMAPFolder required.");
    DDAssert(folder.path, @"MCOIMAPFolder.path required.");

    MCOIMAPNamespace *imapNamespace = [imapSession defaultNamespace];
    DDAssert(imapNamespace, @"IMAP Namespace must exist");
    
    NSString *folderName = [folder.path copy];  // return the full path if prefix is not removed
    
    NSString *folderPathDelimiter = [NSString stringWithFormat:@"%c",imapNamespace.mainDelimiter];
    NSString *folderPathPrefix    = imapNamespace.mainPrefix;

    // If we have a folder path prefix
    if ( folderPathPrefix && folderPathPrefix.length ) {
        
        // If the folder path contains the folder prefix ...
        if ( [folder.path hasPrefix:folderPathPrefix] ) {
            
            // Then create the folder name with the prefix removed.
            NSArray *namespaceComponents = [imapNamespace componentsFromPath:folder.path];
            folderName = [namespaceComponents componentsJoinedByString:folderPathDelimiter];
        } else {
            DDLogInfo(@"IMAP Folder Path \"%@\" is not prefixed by \"%@\"",folder.path,folderPathPrefix);
        }

    } else {
        DDLogInfo(@"IMAP Namespace has NO Prefix.");
    }
    
    DDAssert(folderName,@"Folder Display Name must be found");
    DDAssert(folderName.length>0, @"Folder Display Name must exist");
    
    return folderName;
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

-(NSInteger)folderIndexForBaseFolderType:(NSInteger)folderType
{
    return [self.user numFolderWithFolder:FolderTypeWith(folderType, 0)];
}

-(BOOL)folderIsNotSynced:(NSInteger)folderNumber
{
    SyncManager *syncMgr = [SyncManager getSingleton];
        
    NSDictionary *folderState = [syncMgr retrieveState:folderNumber accountNum:self.user.accountNum];
    
    BOOL folderIsSynced = [folderState[kFolderStateFullSyncKey] boolValue];
    
    BOOL retVal = (folderIsSynced == FALSE);
    
    DDLogVerbose(@"Folder #%ld \"fullsynced\" state = %@, folderIsNotSynced returning %@",
                 (long)folderNumber,
                 (folderIsSynced?@"YES":@"NO"),
                 (retVal?@"YES":@"NO"));
    return retVal;
}

-(NSInteger) _nextFolderToSync
{
    DDLogInfo(@"BEGIN _nextFolderToSync");
    
//    SyncManager *syncMgr = [SyncManager getSingleton];
//        
//    NSInteger folderIndexForBaseFolderType = [self.user numFolderWithFolder:FolderTypeWith(FolderTypeAll, 0)];
//    
//    NSDictionary *state = [syncMgr retrieveState:folderIndexForBaseFolderType
//                                      accountNum:self.user.accountNum];
//    
//    if ( ![state[@"fullsynced"] boolValue] ) {
//        return folderIndexForBaseFolderType;
//    }
    
    NSInteger allFolderNum = [self folderIndexForBaseFolderType:FolderTypeAll];
    if ( [self folderIsNotSynced:allFolderNum] ){
        DDLogInfo(@"\tAll Folder Not Synced, do next");
        return allFolderNum;
    }

//    if (![[[SyncManager getSingleton] retrieveState:[self.user numFolderWithFolder:FolderTypeWith(FolderTypeInbox, 0)] accountNum:self.user.accountNum][@"fullsynced"] boolValue]) {
//        return [self.user numFolderWithFolder:FolderTypeWith(FolderTypeInbox, 0)];
//    }
    
    NSInteger inboxFolderNumber = [self folderIndexForBaseFolderType:FolderTypeInbox];
    if ( [self folderIsNotSynced:inboxFolderNumber] ){
        DDLogInfo(@"\tInbox Folder Not Synced, do next");
        return inboxFolderNumber;
    }
    
//    if (![[[SyncManager getSingleton] retrieveState:[self.user numFolderWithFolder:FolderTypeWith(FolderTypeFavoris, 0)] accountNum:self.user.accountNum][@"fullsynced"] boolValue]) {
//        if ([self.user numFolderWithFolder:FolderTypeWith(FolderTypeFavoris, 0)] != -1) {
//            return [self.user numFolderWithFolder:FolderTypeWith(FolderTypeFavoris, 0)];
//        }
//    }
        
    NSInteger favorisFolderNumber = [self folderIndexForBaseFolderType:FolderTypeFavoris];
    if ( [self folderIsNotSynced:favorisFolderNumber] ){
        DDLogInfo(@"\tFavoris Folder Not Synced, do next");
        return favorisFolderNumber;
    }
    
//    if (![[[SyncManager getSingleton] retrieveState:[self.user numFolderWithFolder:FolderTypeWith(FolderTypeSent, 0)] accountNum:self.user.accountNum][@"fullsynced"] boolValue]) {
//        return [self.user numFolderWithFolder:FolderTypeWith(FolderTypeSent, 0)];
//    }
    
    NSInteger sentFolderNumber = [self folderIndexForBaseFolderType:FolderTypeSent];
    if ( [self folderIsNotSynced:sentFolderNumber] ){
        DDLogInfo(@"\tSent Folder Not Synced, do next");
        return sentFolderNumber;
    }
    
    // Return the first unsynced user folder
    NSArray* folders = [self.user allFoldersDisplayNames];
    for (int indexFolder = 0; indexFolder < folders.count; indexFolder++) {
        
        if ( [self folderIsNotSynced:indexFolder] ) {
            DDLogInfo(@"\tUser Folder %ld Not Synced, do next",(long)indexFolder);
            return indexFolder;
        }
    }
    
    DDLogInfo(@"\tCould not find next folder to sync, returning -1");
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
    NSString* folderPath = [[SyncManager getSingleton] retrieveFolderPathFromFolderState:currentFolder accountNum:self.user.accountNum];
    
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

-(void) getImapFolderNamesAndUpdateLocal
{
    // NB: Called only from Login methods
    
    DDLogInfo(@"BEGIN getImapFolderNamesAndUpdateLocal");
    
    MCOIMAPFetchFoldersOperation* fio = [self.imapSession fetchAllFoldersOperation];
    
    dispatch_async(self.s_queue, ^{
        [fio start:^(NSError* error, NSArray* folders) {
            
            DDLogInfo(@"STARTED IMAP Session Fetch All Folders Operation");
            
            if ( error ) {
                DDLogError(@"\tFetch All Folders Operation error = %@",error);
                return;
            }
            
            if (folders && folders.count > 0) {
                [self _checkFolderNamesForUpdates:folders];
            }
        }];
    });
}

-(BOOL)_localFolderMatchesImapFolder:(MCOIMAPFolder *)imapFolder
{
    SyncManager* syncManager = [SyncManager getSingleton];
    
    NSUInteger localFolderCount = [syncManager folderCount:self.user.accountNum];

    BOOL matchingFolderFound = FALSE;
 
    // Find a Local Folder whose path equals the IMAP Folder Path
    for (NSUInteger localFolderIndex = 0; localFolderIndex < localFolderCount; localFolderIndex++) {
        
        // retrieve the folder's path from the sync manager persistent store
        NSString* folderPath =
        [syncManager retrieveFolderPathFromFolderState:localFolderIndex
                                            accountNum:self.user.accountNum];
        
        // if the path of the folder being checked, matches the path of the existing folder
        if ([[imapFolder path] isEqualToString:folderPath]) {
            
            DDLogInfo(@"\t *** IMAP Folder (%@) == Local Folder %lu ***",
                      folderPath,(unsigned long)localFolderIndex);
            
            matchingFolderFound = TRUE;
            break;
        }
    } // for each local folder
    
    return matchingFolderFound;
}


// Given an array of IMAP folder names, determine if any have been
// added, renamed, or deleted, and update
-(void)_checkFolderNamesForUpdates:(NSArray <MCOIMAPFolder *>*)imapFolders
{
    // NB: This handles Added Folders, but does not handle Deleted Folders or Renamed Folders.
    
    DDAssert(imapFolders, @"Folders Array must not be empty");
    DDAssert(imapFolders.count>0, @"Folders Array must contain folders");
    
    
    // I believe this code block updates local IMAP Folder Names if any have
    // changed to the server (or something like that).
    
    // Appears not to handle DELETED folders.  What about folders with name CHANGES?
    
    DDLogInfo(@"BEGIN: Check Folder Names for Updates, IMAP folder count = %lu",
              (unsigned long)imapFolders.count);
    
    int folderIndex = 0;
    
    NSMutableArray* newFolderNames = [[NSMutableArray alloc] initWithCapacity:imapFolders.count];
    
    for (MCOIMAPFolder* imapFolder in imapFolders) {
        
        BOOL imapFolderMatchesLocalFolder = [self _localFolderMatchesImapFolder:imapFolder];
        
        // If the IMAP Folder being checked was not found in the Local Folders
        // then it is a NEW folder and needs to be added.
        if ( imapFolderMatchesLocalFolder == FALSE ) {
            
            DDLogInfo(@"\tIMAP Folder \"%@\" NOT found in local folders.",[imapFolder path]);
            
            NSString *dispName = [ImapSync displayNameForFolder:imapFolder usingSession:self.imapSession];
            
            DDAssert(dispName, @"Display Name must exist.");
            
            [newFolderNames addObject:dispName];
            
            [self addFolder:imapFolder withName:dispName toAccount:self.user.accountNum];
        }

        folderIndex++;
        
    } // for each IMAP folder
    
    // If there are any folders to add to the Local store ...
    if (newFolderNames.count > 0) {
        
        DDLogDebug(@"Adding New Folder Names \"%@\" to ALL Folder Names",newFolderNames);
        
        // Add dispNamesFolders to saved All Folder Names
        NSMutableArray* allFolderNames = [NSMutableArray arrayWithArray:self.user.allFoldersDisplayNames];
        [allFolderNames addObjectsFromArray:newFolderNames];
        [self.user setAllFoldersDisplayNames:allFolderNames];
    }
}

-(void)addFolder:(MCOIMAPFolder *)folder withName:(NSString*)folderName toAccount:(NSUInteger)accountNum
{
//    NSString* dispName = [ImapSync displayNameForFolder:folder usingSession:imapSession];
    
    // Append a new Folder Sync State Object for this Account
    SyncManager* syncManager = [SyncManager getSingleton];
    NSInteger newFolderSyncIndex = [syncManager addNewStateForFolder:folder
                                                                named:folderName
                                                           forAccount:accountNum];
    
    [self updateSyncStateWithImapMessageCountForFolder:folder.path
                                          atFolderIndex:newFolderSyncIndex
                                       forAccountNumber:accountNum];
    
    return;
}


-(void) updateSyncStateWithImapMessageCountForFolder:(NSString *)folderPath atFolderIndex:(NSInteger)folderIndex forAccountNumber:(NSUInteger)accountNum
{
    MCOIMAPFolderInfoOperation* folderOp = [self.imapSession folderInfoOperation:folderPath];
    
    [folderOp start:^(NSError* error, MCOIMAPFolderInfo* info) {
        
        DDLogInfo(@"BEGAN IMAP Folder Get Info Operation on %@",folderPath);
        
        if (error) {
            DDLogError(@"\tIMAP Folder Get Info Operation Error = %@",error);
        } else {
            
            DDLogInfo(@"\tGot Folder Sync State from folder %ld for IMAP folder \"%@\"",(long)folderIndex,folderPath);
            
            int msgCount = [info messageCount];
            
            [self _writeFolderStateMessageCount:msgCount andFolder:folderIndex];

        }
    }];
}

// MARK: - IMAP Sync Service - Iterate through folders, syncing each
#warning Function is 1920 lines long!!!

- (void)_processImapMessages:(NSArray<MCOIMAPMessage*>*)imapMessages subscriber:(id)subscriber currentFolder:(NSInteger)currentFolder from:(NSInteger)from isFromStart:(BOOL)isFromStart getAll:(BOOL)getAll
{
    dispatch_async(self.s_queue, ^{
        
        SyncManager *syncMgr = [SyncManager getSingleton];
        
        DDLogInfo(@"BEGIN Process %lu IMAP Messages.",(unsigned long)imapMessages.count);
        
        // Message ID of the last mail message returned by the IMAP server
        NSString* lastMsgID = [imapMessages lastObject].header.messageID;
        
        for (MCOIMAPMessage* imapMsg in imapMessages) {
            
            
            if (self.isCanceled) {
                DDLogInfo(@"\tCancelled == TRUE, so sending Completed to subscriber");
                [subscriber sendCompleted];
                return;
            }
            
            NSString* folderPath = [syncMgr retrieveFolderPathFromFolderState:currentFolder accountNum:self.user.accountNum];
            
            Mail* email = [Mail mailWithMCOIMAPMessage:imapMsg inFolder:currentFolder andAccount:self.user.accountNum];
            
            DDLogInfo(@"\n\nEMAIL SUBJECT: \"%@\"\nEMAIL MSG ID:  \"%@\"\nACCOUNT NUM:   %ld\nFOLDER NUM:    %ld\n",
                      email.subject,email.msgID,(long)self.user.accountNum,(long)currentFolder);
            
            if ([UidEntry hasUidEntrywithMsgId:email.msgID inAccount:self.user.accountNum]) {
                
                DDLogInfo(@"--- Message already exists in this Account's Databsase");
                
                if (![UidEntry hasUidEntrywithMsgId:email.msgID withFolder:currentFolder inAccount:self.user.accountNum]) {
                    // already have this email in other folder than this one -> add folder in uid_entry
                    
                    DDLogInfo(@"--- Message DOES NOT already exist in this Account's Database in Folder \"%@\", ADDING.",@(currentFolder));
                    
                    NSInvocationOperation* nextOp = [[NSInvocationOperation alloc] initWithTarget:[EmailProcessor getSingleton] selector:@selector(addToFolderWrapper:) object:[email uidEWithFolder:currentFolder]];
                    
                    nextOp.completionBlock = ^{
                        if ((currentFolder == [Accounts sharedInstance].currentAccount.currentFolderIdx) | getAll) {
                            [email loadBody];
                            [subscriber sendNext:email];
                        }
                    };
                    
                    [[EmailProcessor getSingleton].operationQueue addOperation:nextOp];
                }
                else {
                    DDLogInfo(@"--- Message already exists in this Account's Database in Folder \"%@\"",@(currentFolder));

                }
                
                if ([email.msgID isEqualToString:lastMsgID]) {
                    if (!isFromStart && ![self _isRunningInBackground]) {
                        [self _writeFolderStateLastEnded:from andFolder:currentFolder];
                    }
                    [subscriber sendCompleted];
                }
                
                //We already have email with folder
                continue;
            }
            else {
                DDLogInfo(@"--- Message DOES NOT already exist in this Account's Databsase");
            }
            
            DDLogInfo(@"BEGIN Loading Email from IMAP Server into Database");
            
            [[self.imapSession plainTextBodyRenderingOperationWithMessage:imapMsg folder:folderPath stripWhitespace:NO] start:^(NSString* plainTextBodyString, NSError* error) {
                
                if (plainTextBodyString) {
                    plainTextBodyString = [plainTextBodyString stringByReplacingCharactersInRange:NSMakeRange(0, 1) withString:@""];
                    
                    email.body = plainTextBodyString;
                }
                else {
                    email.body = @"";
                }
                
                NSDate* currentDateAndTime = [NSDate date];
                NSDate* oneMonthBeforeCurrentDateAndTime = [currentDateAndTime dateByAddingTimeInterval:- ONE_MONTH_IN_SECONDS];
                
                if ([email.datetime compare:oneMonthBeforeCurrentDateAndTime] == NSOrderedAscending) {
                    BOOL isNew = [self _saveEmail:email folder:currentFolder];
                    
                    if ((currentFolder == [Accounts sharedInstance].currentAccount.currentFolderIdx) | getAll) {
                        if ( [self _isRunningInBackground] ) {
                            if (isNew) {
                                [subscriber sendNext:email];
                            }
                        }
                        else {
                            [subscriber sendNext:email];
                        }
                    }
                    
                    if ([email.msgID isEqualToString:lastMsgID]) {
                        if (!isFromStart && ![self _isRunningInBackground]) {
                            [self _writeFolderStateLastEnded:from andFolder:currentFolder];
                        }
                        [subscriber sendCompleted];
                    }
                }
                else {
                    [[self.imapSession htmlBodyRenderingOperationWithMessage:imapMsg folder:folderPath] start:^(NSString* htmlString, NSError* error) {
                        email.htmlBody = htmlString;
                        
                        BOOL isNew = [self _saveEmail:email folder:currentFolder];
                        
                        if ((currentFolder == [Accounts sharedInstance].currentAccount.currentFolderIdx) | getAll) {
                            if ( [self _isRunningInBackground] ) {
                                if (isNew) {
                                    [subscriber sendNext:email];
                                }
                            }
                            else {
                                [subscriber sendNext:email];
                            }
                        }
                        
                        if ([email.msgID isEqualToString:lastMsgID]) {
                            if (!isFromStart && ![self _isRunningInBackground]) {
                                [self _writeFolderStateLastEnded:from andFolder:currentFolder];
                            }
                            [subscriber sendCompleted];
                        }
                    }];
                }
            }];
        }
    });

}

- (void)_fetchImapMessages:(id)subscriber currentFolder:(NSInteger)currentFolder isFromStart:(BOOL)isFromStart getAll:(BOOL)getAll folderPath:(NSString *)folderPath messageCount:(NSInteger)msgCount lastEnded:(NSInteger)lastEnded
{
    
    dispatch_async(self.s_queue, ^{
        
        DDLogInfo(@"BEGIN Fetch Folder \"%@\" Messages from IMAP Server.",folderPath);
        
        int batchsize = 50;
        
        DDLogInfo(@"\tFolder has %ld emails", (long)msgCount);
        
        if ( ![self _isRunningInBackground] ) {
            
            DDLogInfo(@"\twe are not running in background, so ...");
            
            DDLogInfo(@"\tSave email count (%lu) to Local State Storage",(long)msgCount);
            
            
            [self _writeFolderStateMessageCount:msgCount andFolder:currentFolder];
            
            // If (the folder contains NO messages), OR
            // (we are NOT loading folder messages from Index
            //   Zero AND the last loaded message was Index One)
            if (msgCount == 0 || (!isFromStart && (lastEnded == 1))) {
                
                DDLogInfo(@"\tNo Messages OR (Not from Start AND Last Ended == 1");
                
                NSInteger lastEndedIndex = 0;
                if ( msgCount == 0 ) {
                    lastEndedIndex = 1;
                }
                else {
                    lastEndedIndex = lastEnded;
                }
                
                DDLogInfo(@"\tSave Last Ended Index (%lu) to Local State Storage",(long)lastEndedIndex);
                
                [self _writeFolderStateLastEnded:lastEndedIndex andFolder:currentFolder];
                
                DDLogInfo(@"\tand send CCMFolderSyncedError to subscriber.");
                
                [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMFolderSyncedError userInfo:nil]];
                return;
            }
        }
        
        NSInteger from = msgCount;
        
        if (!(isFromStart || [self _isRunningInBackground]) && lastEnded != 0) {
            from = lastEnded-1;
        }
        
        uint64_t batch = MIN(batchsize, msgCount);
        
        batch--;
        
        if (from > batch) {
            from -= batch;
        }
        else {
            from = 1;
        }
        
        MCOIndexSet* numbers = [MCOIndexSet indexSetWithRange:MCORangeMake(from, batch)];
        
        MCOIMAPFetchMessagesOperation* imapMessagesFetchOp =
        [self.imapSession fetchMessagesByNumberOperationWithFolder:folderPath
                                                       requestKind:self.user.requestKind
                                                           numbers:numbers];
        
        DDLogInfo(@"BEGIN Fetch Messages for Folder \"%@\".",folderPath);
        
        [imapMessagesFetchOp start:^(NSError* error, NSArray<MCOIMAPMessage*>* imapMessages, MCOIndexSet* vanishedMessages) {
            
            if (error) {
                DDLogError(@"\tError %@ fetching messages.  Send CCMConnectionError to subscriber.",error.description);
                
                self.connected = NO;
                [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMConnectionError userInfo:nil]];
                
                return;
            }
            
            DDLogInfo(@"\tgot %lu messages.",(unsigned long)imapMessages.count);
            
            [self _processImapMessages:imapMessages subscriber:(id)subscriber currentFolder:currentFolder from:from isFromStart:isFromStart getAll:getAll];
            
        }];//Fetch Messages
    });

}

- (void)_getImapMessages:(NSInteger)currentFolder subscriber:(id)subscriber isFromStart:(BOOL)isFromStart getAll:(BOOL)getAll
{
    SyncManager *syncMgr = [SyncManager getSingleton];
    
    DDLogInfo(@"BEGIN Fetch Folder %lu Info from IMAP Server.",(unsigned long)currentFolder);
    
    NSString* folderPath =
    [syncMgr retrieveFolderPathFromFolderState:currentFolder
                                    accountNum:self.user.accountNum];
    
    MCOIMAPFolderInfoOperation* folderInfoOp = [self.imapSession folderInfoOperation:folderPath];
    
    NSInteger lastEnded = [syncMgr retrieveLastEndedFromFolderState:currentFolder
                                                         accountNum:self.user.accountNum];
    
    [folderInfoOp start:^(NSError* error, MCOIMAPFolderInfo* imapFolderInfo) {
        if (error) {
            DDLogError(@"\tError %@ fetching folder %@, sending CCMConnectionError to subscriber",error.description, folderPath);
            
            self.connected = NO;
            [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMConnectionError userInfo:nil]];
            
            return;
        }
        if (self.isCanceled) {
            DDLogInfo(@"\tCancelled == TRUE, so sending Completed to subscriber");
            [subscriber sendCompleted];
            return;
        }
        
        [self _fetchImapMessages:subscriber
                   currentFolder:currentFolder
                     isFromStart:isFromStart
                          getAll:getAll
                      folderPath:folderPath
                    messageCount:imapFolderInfo.messageCount
                       lastEnded:lastEnded];
    }];
}


- (void)_replaceDeletedImportantFolders:(NSInteger)currentFolder imapFolders:(NSArray *)imapFolders
{
    SyncManager *syncMgr = [SyncManager getSingleton];

  DDLogInfo(@"BEGIN Replace Deleted Important Folder");
    
        // If the Current Folder is one of the deleted folders, and it is an Important
        // folder, then try to find a replacement folder.
    
        BOOL currentFolderIsDeletedLocally =
        [syncMgr isFolderDeletedLocally:currentFolder accountNum:self.user.accountNum];
    
        if ( currentFolderIsDeletedLocally ) {
            
            DDLogInfo(@"\tFolder %li is deleted locally",
                      (long)currentFolder);
            
            CCMFolderType folderHandle = [self.user typeOfFolder:currentFolder];
            
            BOOL currentFolderIsAnImportantFolder = (folderHandle.type != FolderTypeUser);
            
            if ( currentFolderIsAnImportantFolder ) {
                
                DDLogInfo(@"\tis an Important Folder");
                
                MCOMailProvider* accountProvider = [[MCOMailProvidersManager sharedManager] providerForIdentifier:self.user.identifier];
                
                DDLogInfo(@"\tsearch each IMAP folder:");
                
                // For each IMAP Folder
                for (MCOIMAPFolder* folder in imapFolders) {
                    
                    DDLogInfo(@"\tIMAP Folder \"%@\"",
                              folder.path);
                    
                    if (folder.flags & MCOIMAPFolderFlagNoSelect) {
                        DDLogInfo(@"\t\thas NO Flags");
                        continue;
                    }
                    
                    NSString *folderName = [ImapSync displayNameForFolder:folder usingSession:self.imapSession];
                    DDLogInfo(@"Folder Path = \"%@\", Folder Name = \"%@\"",folder.path,folderName);

                    NSString* importantImapFolderPath = @"";
                    
                    if (folderHandle.type == FolderTypeInbox &&  ((folder.flags == MCOIMAPFolderFlagInbox) || [folderName  isEqualToString: @"INBOX"])) {
                        importantImapFolderPath = folderName;
                        DDLogInfo(@"\t\tIs the INBOX folder.");
                        //[self.user setImportantFolderNum:indexPath forBaseFolder:FolderTypeInbox];
                    } //Starred
                    else if(folderHandle.type == FolderTypeFavoris &&  ([accountProvider.starredFolderPath isEqualToString:folderName] || (folder.flags == MCOIMAPFolderFlagFlagged))) {
                        importantImapFolderPath = folderName;
                        DDLogInfo(@"\t\tIs the FLAGGED folder.");
                        //[self.user setImportantFolderNum:indexPath forBaseFolder:FolderTypeFavoris];
                    } //Sent
                    else if(folderHandle.type == FolderTypeSent &&  ([accountProvider.sentMailFolderPath isEqualToString:folderName] || (folder.flags == MCOIMAPFolderFlagSentMail))) {
                        importantImapFolderPath = folderName;
                        DDLogInfo(@"\t\tIs the SENT folder.");
                        //[self.user setImportantFolderNum:indexPath forBaseFolder:FolderTypeSent];
                    } //Draft
                    else if(folderHandle.type == FolderTypeDrafts &&  ([accountProvider.draftsFolderPath isEqualToString:folderName] || (folder.flags == MCOIMAPFolderFlagDrafts))) {
                        importantImapFolderPath = folderName;
                        DDLogInfo(@"\t\tIs the DRAFTS folder.");
                        //[self.user setImportantFolderNum:indexPath forBaseFolder:FolderTypeDrafts];
                    } //Archive
                    else if(folderHandle.type == FolderTypeAll &&  ([accountProvider.allMailFolderPath isEqualToString:folderName] || ((folder.flags == MCOIMAPFolderFlagAll) || (folder.flags == MCOIMAPFolderFlagAllMail)))) {
                        importantImapFolderPath = folderName;
                        DDLogInfo(@"\t\tIs the ARCHIVE folder.");
                        //[self.user setImportantFolderNum:indexPath forBaseFolder:FolderTypeAll];
                    } //Trash
                    else if(folderHandle.type == FolderTypeDeleted &&  ([accountProvider.trashFolderPath isEqualToString:folderName] || (folder.flags == MCOIMAPFolderFlagTrash))) {
                        importantImapFolderPath = folderName;
                        DDLogInfo(@"\t\tIs the TRASH folder.");
                        
                        //[self.user setImportantFolderNum:indexPath forBaseFolder:FolderTypeDeleted];
                    } //Spam
                    else if(folderHandle.type == FolderTypeSpam &&  ([accountProvider.spamFolderPath isEqualToString:folderName] || (folder.flags == MCOIMAPFolderFlagSpam))) {
                        importantImapFolderPath = folderName;
                        DDLogInfo(@"\t\tIs the SPAM folder.");
                        //[self.user setImportantFolderNum:indexPath forBaseFolder:FolderTypeSpam];
                    } else {
                        DDLogInfo(@"\t\tIs NOT an Important folder.");
                    }
                    
                    BOOL thisImapFolderIsImportant = ![importantImapFolderPath isEqualToString:@""];
                    
                    if ( thisImapFolderIsImportant ) {
                        
                        DDLogInfo(@"\tImportant Folder Path = \"%@\"", importantImapFolderPath);
                        
                        // Review each local folder
                        NSInteger localFolderCount = [syncMgr folderCount:self.user.accountNum];
                        int localFolderIndex = 0;
                        while ( localFolderIndex < localFolderCount ) {
                            
                            NSString* localFolderPath =
                            [syncMgr retrieveFolderPathFromFolderState:localFolderIndex
                                                            accountNum:self.user.accountNum];
                            
                            // If the Important Imap Folder matches the local folder
                            if ( [importantImapFolderPath isEqualToString:localFolderPath] ) {
                                
                                DDLogInfo(@"\tmatches local folder");
                                
                                [self.user setImportantFolderNum:localFolderIndex forBaseFolder:folderHandle.type];
                                
                                
                                // FIXME: "break;" here, even return?
                            }
                            
                            localFolderIndex++;
                        }
                    }//Set new important folder index
                }//Is there other folder same importance/role
            }//If important folder
        }
}

- (void)_processFoldersAndGetImapMessages:(id)subscriber currentFolder:(NSInteger)currentFolder isFromStart:(BOOL)isFromStart getAll:(BOOL)getAll imapFolders:(NSArray *)imapFolders
{
    dispatch_async(self.s_queue, ^{
        
        DDLogInfo(@"BEGIN Check Folder Deletion");
        
#warning Look: Almost the same code as _checkFolders again!
        SyncManager* syncMgr = [SyncManager getSingleton];
        // mark folders that were deleted on the server as deleted on the client
        NSInteger localFolderIndex = 0;
        NSInteger localFolderCount = [syncMgr folderCount:self.user.accountNum];
        
        // Check each local folder, and if it is not found on the IMAP server,
        // then mark it deleted on locally.
        while (localFolderIndex < localFolderCount) {
            
            NSString* localFolderPath =
            [syncMgr retrieveFolderPathFromFolderState:localFolderIndex
                                            accountNum:self.user.accountNum];
            
            DDLogInfo(@"\tAccount %li, Local Folder [%li]: \"%@\"",
                      (long)self.user.accountNum,
                      (long)localFolderIndex,
                      localFolderPath);
            
            BOOL folderIsDeletedLocally =
            [syncMgr isFolderDeletedLocally:localFolderIndex accountNum:self.user.accountNum];
            
            if ( folderIsDeletedLocally ) {
                DDLogInfo(@"\t\tLocal Folder's Delete State = TRUE");
            }
            else {
                BOOL folderDeletedOnImapServer = ![imapFolders containsObject:localFolderPath];
                
                if ( folderDeletedOnImapServer ) {
                    DDLogInfo(@"\t\tLocal Folder Path NOT found in IMAP Folders");
                    DDLogInfo(@"\t\tMark Local Folder's Delete State as TRUE");
                    [syncMgr markFolderDeleted:localFolderIndex accountNum:self.user.accountNum];
                    localFolderIndex = 0;
                }
                else {
                    DDLogInfo(@"\tFolder has NOT been deleted (Locally or on IMAP server).");
                }
            }
            
            localFolderIndex++;
        }
        
        [self _replaceDeletedImportantFolders:currentFolder imapFolders:imapFolders];
        
        [self _getImapMessages:currentFolder subscriber:subscriber isFromStart:isFromStart getAll:getAll];
    });
}

- (void)_getImapFoldersAndMessages:(id)subscriber currentFolder:(NSInteger)currentFolder isFromStart:(BOOL)isFromStart getAll:(BOOL)getAll
{
    DDLogInfo(@"BEGIN Fetch IMAP Folders");
    
    MCOIMAPFetchFoldersOperation* fio = [self.imapSession fetchAllFoldersOperation];
    dispatch_async(self.s_queue, ^{
        
        DDLogInfo(@"BEGIN Fetch All IMAP Folders Operation");
        
        [fio start:^(NSError* error, NSArray* imapFolders) {
            if (error) {
                DDLogError(@"\treturned error = %@. Send CCMConnectionError to subscriber",error.description);
                
                self.connected = NO;
                
                [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMConnectionError userInfo:nil]];
                
                return;
            }
            else if (!imapFolders || imapFolders.count == 0) {
                
                DDLogInfo(@"\tNO imap Folders, so send Completed to subscriber");
                [subscriber sendCompleted];
                
                return;
            } else {
                DDLogInfo(@"\tsuccess: have %lu folders.",(unsigned long)imapFolders.count);
            }
            
            [self _processFoldersAndGetImapMessages:subscriber currentFolder:currentFolder isFromStart:isFromStart getAll:getAll imapFolders:imapFolders];
        }];//Fetch All Folders
    });
}

- (void)_loginImapServerAndUpdateFoldersAndMessages:(id)subscriber currentFolder:(NSInteger)currentFolder isFromStart:(BOOL)isFromStart getAll:(BOOL)getAll
{
    DDLogInfo(@"BEGIN Login IMAP Server \"%@\":",self.user.imapHostname);
    
    [[ImapSync doLogin:self.user] subscribeError:^(NSError *error) {
        DDLogError(@"\tLogin attempt failed. Send ERROR CCMConnectionError to subscriber");
        [subscriber sendError:error];
    } completed:^{
        DDLogInfo(@"\tLogin attempt Completed.");
        if (!self.connected) {
            DDLogInfo(@"\tNOT Connected.");
            
            if ( [self _isRunningInBackground] ) {
                DDLogInfo(@"\tin BACKGROUND, so send COMPLETED to subscriber");
                
                [subscriber sendCompleted];
            }
            else {
                DDLogError(@"\tNOT in BACKGROUND. Send ERROR CCMConnectionError to subscriber");
                
                [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMConnectionError userInfo:nil]];
            }
        }
        else { // we are connected
            DDLogInfo(@"\tSUCCESSFULLY Connected.");
            
            [self _getImapFoldersAndMessages:subscriber currentFolder:currentFolder isFromStart:isFromStart getAll:getAll];
        }
    }];
}

-(BOOL)_isRunningInBackground
{
    BOOL isInBackground = (UIApplicationStateBackground == [UIApplication sharedApplication].applicationState);
    
    DDLogDebug(@"\tApp isInBackground = %@",
               (isInBackground==TRUE?@"TRUE":@"FALSE") );

    return isInBackground;
}

// "folder" is a Folder Index, or -1
-(RACSignal*) runFolder:(NSInteger)folder fromStart:(BOOL)isFromStart gettingAll:(BOOL)getAll
{
    DDLogInfo(@"BEGIN runFolder:%ld fromStart:%@ fromAccount:(getAll=%@):",
               (long)folder,
               (isFromStart==TRUE?@"TRUE":@"FALSE"),
               (getAll==TRUE?@"TRUE":@"FALSE"));
    
    if (folder == -1) {
        DDLogInfo(@"\tfolderIndex = -1, calling folderIndex = _nextFolderToSync");
        folder = [self _nextFolderToSync];
    }
    DDLogDebug(@"\tfolderIndex = %ld",(long)folder);
    
    NSInteger currentFolder = folder;
    
    if (!self.cachedData) {
        self.cachedData = [[NSMutableArray alloc]initWithCapacity:1];
    }
    
    @weakify(self);
    
    return [RACSignal startLazilyWithScheduler:[RACScheduler schedulerWithPriority:RACSchedulerPriorityBackground] block:^(id<RACSubscriber> subscriber) {
        
        @strongify(self);
        
        // get list of all folders from the IMAP Server
        
        if (self.isCanceled) {
            DDLogInfo(@"IMAP Sync Service CANCELLED, runFolder COMPLETED");
            [subscriber sendCompleted];
        }
        else if (![ImapSync isNetworkAvailable]) {
            DDLogError(@"IMAP Sync Service ERROR: Network is not available");
            
            self.connected = NO;
            [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMConnectionError userInfo:nil]];
        }
        else if (currentFolder == -1) {
            
            // This will happen when the folder passed into the function was -1,
            // and _nextFolderToSync returns -1.
            DDLogError(@"IMAP Sync Service Error: All Synced");
            
            [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMAllSyncedError userInfo:nil]];
        }
        else if ([self _isRunningInBackground] && currentFolder != [self.user inboxFolderNumber]) {
            
            DDLogInfo(@"Running in Background && folder is not Inbox folder.");
            DDLogInfo(@"\tso we are completed.");

            [subscriber sendCompleted];
        }
        else {
            [self _loginImapServerAndUpdateFoldersAndMessages:subscriber currentFolder:currentFolder isFromStart:isFromStart getAll:getAll];
        }
    }];
}

- (BOOL)_cacheEmail:(NSInteger)currentFolder email:(Mail *)email
{
    BOOL emailCached = NO;
    
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
                
                DDLogDebug(@"Index: %ld",(long)index.index);
                DDLogDebug(@"Conversation: %@",[conv firstMail].subject);
                
                [[UIApplication sharedApplication] presentLocalNotificationNow:localNotification];
            }
            
            emailCached = YES;
        }
    }
    return emailCached;
}

-(BOOL) _saveEmail:(Mail*)email folder:(NSInteger)currentFolder
{
    //Cache email if in Background
    if ( [self _isRunningInBackground] ) {
        
        return [self _cacheEmail:currentFolder email:email];
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

-(void) _writeFolderStateMessageCount:(NSInteger)messageCount andFolder:(NSInteger)folder
{
    SyncManager *sm = [SyncManager getSingleton];

    if (!self.user.isDeleted) {
        
        // used by fetchFrom to write the finished state for this round of syncing to disk
        NSMutableDictionary* syncState = [sm retrieveState:folder accountNum:self.user.accountNum];
        syncState[kFolderStateEmailCountKey] = @(messageCount);
        
        [sm persistState:syncState forFolderNum:folder accountNum:self.user.accountNum];
    }
}

-(void) _writeFolderStateLastEnded:(NSInteger)lastEIndex andFolder:(NSInteger)folder
{
    SyncManager *sm = [SyncManager getSingleton];

    // used by fetchFrom to write the finished state for this round of syncing to disk
    if (!self.user.isDeleted) {
        NSMutableDictionary* syncState = [sm retrieveState:folder accountNum:self.user.accountNum];
        syncState[kFolderStateLastEndedKey] = @(lastEIndex);
        syncState[kFolderStateFullSyncKey]  = @(lastEIndex == 1);
        
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
                     DDLogError(@"error testing cached emails in %@, %@", path, error);
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
    
    DDLogDebug(@"Testing folder %@ with %i emails in accountIndex:%ld", path, uidsIS.count, (long)self.user.accountNum);
    
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
                     DDLogError(@"error testing emails in %@, %@", path, error);
                     completedBlock(delDatas, upDatas, days);
                     return;
                 }
                 
                 
                 
                 DDLogDebug(@"Connected and Testing folder %@ in accountIndex:%ld", path, (long)self.user.accountNum);
                 
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
                     DDLogDebug(@"Delete %lu emails", (unsigned long)delDatas.count);
                     NSDictionary* data = [[NSDictionary alloc]initWithObjects:@[delDatas,@(folderIdx)] forKeys:@[@"datas",@"folderIdx"]];
                     NSInvocationOperation* nextOp = [[NSInvocationOperation alloc] initWithTarget:ep selector:@selector(removeFromFolderWrapper:) object:data];
                     [ep.operationQueue addOperation:nextOp];
                 }
                 
                 if (upDatas.count > 0) {
                     DDLogDebug(@"Update %lu emails", (unsigned long)upDatas.count);
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
