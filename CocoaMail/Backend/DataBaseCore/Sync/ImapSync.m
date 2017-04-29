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

#import <NotificationCenter/NotificationCenter.h>
#import <UserNotifications/UserNotifications.h>
#import <UserNotificationsUI/UserNotificationsUI.h>

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
    DDAssert(user, @"(UserSettings*)user must exist.");
    
    DDAssert(!user.isDeleted, @"Account # %@ is deleted",@(user.accountNum));
    
    // Find the shared IMAP Sync Service with the matching Account Number
    NSArray<ImapSync*>* allSharedServices = [ImapSync allSharedServices:nil];
    for (ImapSync* sharedService in allSharedServices) {
        if (sharedService.user.accountNum == user.accountNum) {
            return sharedService;
        } else {
            DDLogDebug(@"sharedService.user.accountNum %@ NOT EQUAL TO user.accountNum %@",
                      @(sharedService.user.accountNum),@(user.accountNum));
        }
    }
    
    DDLogError(@"Unable to find Account Number %@",@(user.accountNum));
    
    DDAssert(nil,@"Must be able to find an Account!");
    
    return nil;
}

+(NSArray<ImapSync*>*) allSharedServices:(MCOIMAPSession*)update
{
    DDLogVerbose(@"ENTERED");
    
    @synchronized(sharedServices) {
        
        if (update) {
            DDLogInfo(@"Updating IMAP Session, so generate new sharedServices.");
            sharedServices = nil;
        }
    
        // If we already have one or more shared services, then return them
        if (sharedServices && sharedServices.count > 0) {
            DDLogInfo(@"RETURNING existing sharedServices[0..%@]",@(sharedServices.count));
            return sharedServices;
        }
                
        // Create new sharedServices, one for each user.
        
        NSMutableArray* newSharedServices = [[NSMutableArray alloc]init];
        
        NSArray<UserSettings*>* allUsers = [AppSettings getSingleton].users;
        
        // Create a new ImapSync Shared Service for each (non deleted) user
        for (UserSettings* user in allUsers ) {
            
            if (user.isDeleted) {
                continue;   // next UserSettings
            }
            
            DDLogInfo(@"Create new IMAP Shared Service to for Account \"%@\" (# %@)",user.username,@(user.accountNum));
            
            // Create and set up new Imap Sync Shared Service
            ImapSync* sharedService = [[super allocWithZone:nil] init];
            sharedService.user = user;
            sharedService.connected = NO;
            
//            sharedService.s_queue = dispatch_queue_create("CocoaMail" /*DISPATCH_QUEUE_PRIORITY_DEFAULT*/, DISPATCH_QUEUE_SERIAL);
            
            sharedService.s_queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
            
            // If an updated Imap Session was passed in, and its username matches this user, then update the new service
            if (update && [update.username isEqualToString:user.username]) {
                sharedService.imapSession = update;
                sharedService.imapSession.dispatchQueue = sharedService.s_queue;
                sharedService.connected = YES;
            }
            else {
                // We do not have an updated IMAP Session with a user that matches this one
                
                dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
                
                
                // TODO: Should I remove the semaphores and change this to dispatch_sync?
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
        
    } // end @synchronized(sharedServices)
}

// MARK: - IMAP Sync Service: is Network available via WiFi

+(BOOL) canFullSync
{
    Reachability* networkReachability = [Reachability reachabilityForInternetConnection];
    NetworkStatus networkStatus = [networkReachability currentReachabilityStatus];
    
    BOOL canFullSync = [[AppSettings getSingleton] canSyncOverData] || (networkStatus == ReachableViaWiFi);
    
    DDLogInfo(@"returning %@",(canFullSync?@"TRUE":@"FALSE"));
    
    return canFullSync;
}

// MARK: - IMAP Sync Service: delete a user

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

// MARK: - IMAP Sync Server: strip IMAP folder prefix from folder path

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

// MARK: - IMAP Sync Service: Get the User's Inbox Unread Mail Count from the IMAP Server

//+(void) runInboxUnread:(UserSettings*)user
//{
//    [ImapSync runInboxUnread:user completed:^{}];
//}

// Get the Unread Count for User's Inbox
+(void) runInboxUnread:(UserSettings*)user completed:(void (^)(void))completedBlock
{
    DDLogInfo(@"ENTERED");
    
    if ( ![ImapSync _isNetworkAvailable] ) {
        DDLogInfo(@"Network is not available");
        completedBlock();
        return;
    }
    
    if ( user.isAll ) {
        DDLogInfo(@"This is All account, don't run Inbox Unread.");
        completedBlock();
        return;
    }
    
    [self runUnreadCount:user folder:inboxFolderType() completed:completedBlock];
}

+(void) runUnreadCount:(UserSettings*)user folder:(CCMFolderType)folder completed:(void (^)(void))completedBlock
{
    DDLogInfo(@"ENTERED");

    dispatch_queue_t imapDispatchQueue = [ImapSync sharedServices:user].s_queue;
    DDAssert(imapDispatchQueue, @"IMAP Displatch Queue must exist!");
    dispatch_async(imapDispatchQueue, ^{
        
        NSInteger folderNumber = [user numFolderWithFolder:folder];
        NSString* serverFolderPath = [user folderServerName:folderNumber];
        MCOIMAPSearchExpression* expr = [MCOIMAPSearchExpression searchUnread];
        MCOIMAPSearchOperation* so = [[ImapSync sharedServices:user].imapSession searchExpressionOperationWithFolder:serverFolderPath expression:expr];
        
        [so start:^(NSError* error, MCOIndexSet* searchResult) {
            DDLogInfo(@"STARTED Search for All Unread Mails Operation");
            
            if (!error) {
                DDLogInfo(@"Got Folder's Unread search results, count = %u",searchResult.count);
                
                [AppSettings setInboxUnread:searchResult.count accountIndex:user.accountIndex];
            }
            else {
                DDLogError(@"Search for All Unread Mails Operation Failed, error = %@",error);
            }
            
            if (completedBlock) {
                completedBlock();
            }
        }];
    });
 
}



// MARK: - IMAP Sync Service: set this IMAP service as Cancelled

-(void) cancel
{
    self.isCanceled = YES;
}

// MARK: - IMAP Sync Service: save Cached Data - DOES NOTHING - code commented out

-(void) saveCachedData
{
    //NSMutableArray* ops = [[NSMutableArray alloc] initWithCapacity:self.cachedData.count];
    /*EmailProcessor* ep = [EmailProcessor getSingleton];
     
     NSURL* someURL = [[NSURL alloc] initFileURLWithPath:[StringUtil filePathInDocumentsDirectoryForFileName:@"cache"]];
     [[[NSArray alloc]init] writeToURL:someURL atomically:YES];
     
     if (self.cachedData) {
     for (Mail* mail in self.cachedData) {
     DDLogInfo(@"Saving Cached Email: %@", mail.subject);
     
     NSInvocationOperation* nextOp = [[NSInvocationOperation alloc] initWithTarget:ep selector:@selector(addEmailWrapper:) object:mail];
     //[ops addObject:nextOp];
     }
     }
     
     [ep.operationQueue addOperations:ops waitUntilFinished:YES];*/
    
    self.cachedData = nil;
    
}

// MARK: - Local Methods, called by multiple methos

-(BOOL)_isRunningInBackground
{
    BOOL isInBackground = (UIApplicationStateBackground == [UIApplication sharedApplication].applicationState);
    
    DDLogVerbose(@"\tApp isInBackground = %@",(isInBackground==TRUE?@"TRUE":@"FALSE") );
    
    return isInBackground;
}

+(BOOL) _isNetworkAvailable
{
    Reachability* networkReachability = [Reachability reachabilityForInternetConnection];
    NetworkStatus networkStatus = [networkReachability currentReachabilityStatus];
    
    DDLogInfo(@"%@",[self _networkStatusText:networkStatus]);
    
    BOOL isAvailable = (networkStatus != NotReachable);
    
    return isAvailable;
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

- (void)_setConnected:(BOOL)connected
{
    _connected = connected;
    if (!connected) {
        self.signal = nil;
    }
}


// MARK: - IMAP Sync Service: Login to IMAP Server and sync Mail Folders

+(RACSignal*) doLogin:(UserSettings*)user
{
    DDLogInfo(@"userSesstings.imapHostname = \"%@\"",user.imapHostname);
    
    if (!user || user.isDeleted) {
        
        DDLogError(@"Have no user or user is deleted");
        
        return [RACSignal startEagerlyWithScheduler:[RACScheduler scheduler] block:^(id<RACSubscriber> subscriber) {
            [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMDeletedError userInfo:nil]];
        }];
    }

    ImapSync* sharedService = [ImapSync sharedServices:user];
    
    if (!sharedService) {
        
        DDLogError(@"Have no Shared ImapSync Services for User \"%@\"",user.username);
        
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
    
    // CURIOUS: Are these always equal?
    if ( user != sharedService.user ) {
        DDLogInfo(@"Andy is CURIOUS: \"user\" != \"sharedService.user\"");
    }

    if (![ImapSync _isNetworkAvailable]) {
        
        DDLogError(@"+[ImapSync _isNetworkAvailable] returned NO");
        
        return [RACSignal startEagerlyWithScheduler:[RACScheduler scheduler] block:^(id<RACSubscriber> subscriber) {
            sharedService.connected = NO;
            [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain
                                                      code:CCMConnectionError
                                                  userInfo:nil]];
        }];
    }
    
    
    if ( sharedService.signal ) {
        
        DDLogDebug(@"Returning (existing) Shared IMAP Sync Service Signal");
        
        return sharedService.signal;
    }
    
    DDLogDebug(@"CREATE NEW Shared IMAP Sync Service Signal.");
    
    sharedService.signal = [RACSignal startEagerlyWithScheduler:[RACScheduler scheduler]
                      block:^(id<RACSubscriber> subscriber)
    {
        if (sharedService.connected) {
            DDLogDebug(@"Shared IMAP Sync Service is Connected");
            [subscriber sendCompleted];
            return;
        }

        DDLogDebug(@"Shared IMAP Sync Service is NOT Connected");

        if ([sharedService.user isUsingOAuth]) {
            DDLogDebug(@"Attempting to log in with OAuth.");

            [self _loginWithOAuth:sharedService forUser:user withSubscriber:subscriber];
        }
        else { //Not using OAuth
            DDLogDebug(@"Attempting to log in with Password.");

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

// MARK: Local methods for dologin:

+(void) _loginWithOAuth:(ImapSync *)sharedService forUser:(UserSettings *)user withSubscriber:(id<RACSubscriber>) subscriber
{
    DDLogDebug(@"ENTERED");
    
    sharedService.imapSession.OAuth2Token = [sharedService.user oAuth];
    sharedService.imapSession.authType = MCOAuthTypeXOAuth2;
    sharedService.imapSession.connectionType = MCOConnectionTypeTLS;
    sharedService.imapCheckOp = [sharedService.imapSession checkAccountOperation];
    
    
    dispatch_queue_t imapDispatchQueue = [ImapSync sharedServices:user].s_queue;
    DDAssert(imapDispatchQueue, @"IMAP Displatch Queue must exist!");
    dispatch_async(imapDispatchQueue, ^{
        
        DDLogDebug(@"BLOCK START - DISPATCH_QUEUE_PRIORITY_DEFAULT");
        
        [sharedService.imapCheckOp start:^(NSError* error) {
            if (error) {
                
                DDLogError(@"Error 1:%@ loading oauth account:%@", error, sharedService.user.username);
                
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
                                
                                dispatch_queue_t imapDispatchQueue = [ImapSync sharedServices:user].s_queue;
                                DDAssert(imapDispatchQueue, @"IMAP Displatch Queue must exist!");
                                dispatch_async(imapDispatchQueue, ^{
                                    
                                    DDLogDebug(@"\tLoggin Again with OAuth with token:%@", [sharedService.user oAuth]);
                                    
                                    sharedService.imapCheckOp = [sharedService.imapSession checkAccountOperation];
                                    [sharedService.imapCheckOp start:^(NSError* error) {
                                        if (!error) {
                                            DDLogDebug(@"\tAccount:%ld check OK", (long)sharedService.user.accountNum);
                                            sharedService.connected = YES;
                                            [sharedService.user.linkedAccount setConnected];
                                            [sharedService _checkForCachedActions];
                                            [sharedService _getImapFolderNamesAndUpdateLocal];
                                            
                                            [subscriber sendCompleted];
                                        }
                                        else {
                                            DDLogError(@"Error 2:%@ loading oauth account:%@", error, sharedService.user.username);
                                            [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMConnectionError userInfo:nil]];
                                        }
                                    }];
                                });
                            }
                            else {
                                DDLogError(@"Error 3:%@ loading oauth account:%@", error, sharedService.user.username);
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
                [sharedService _checkForCachedActions];
                [sharedService _getImapFolderNamesAndUpdateLocal];
                
                [subscriber sendCompleted];
                
            }
        }];
    });
}

+(void) _loginWithPassword:(ImapSync *)sharedService forUser:(UserSettings *)user withSubscriber:(id<RACSubscriber>) subscriber
{
    sharedService.imapCheckOp = [sharedService.imapSession checkAccountOperation];
    
    DDLogDebug(@"\tLogging in with Password (not oAuth)");
    
    dispatch_queue_t imapDispatchQueue = [ImapSync sharedServices:user].s_queue;
    DDAssert(imapDispatchQueue, @"IMAP Displatch Queue must exist!");
    dispatch_async(imapDispatchQueue, ^{
        
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
                [sharedService _checkForCachedActions];
                [sharedService _getImapFolderNamesAndUpdateLocal];
                
                [subscriber sendCompleted];
            }
            
        }];
    });
}

-(void) _checkForCachedActions
{
    NSMutableArray* cachedActions = [CachedAction getActionsForAccount:self.user.accountNum];
    
    for (CachedAction* cachedAction in cachedActions) {
        [cachedAction doAction];
    }
}


-(void) _getImapFolderNamesAndUpdateLocal
{
    // NB: Called only from Login methods
    
    DDLogInfo(@"ENTERED");
    
    DDAssert(self.s_queue, @"s_queue must be set");
    
    MCOIMAPFetchFoldersOperation* fio = [self.imapSession fetchAllFoldersOperation];
    
    dispatch_async(self.s_queue, ^{
        [fio start:^(NSError* error, NSArray* folders) {
            
            DDLogInfo(@"STARTED IMAP Session Fetch All Folders Operation");
            
            if ( error ) {
                DDLogError(@"Fetch All Folders Operation error = %@",error);
                return;
            }
            
            if (folders && folders.count > 0) {
                [self _checkFolderNamesForUpdates:folders];
            }
        }];
    });
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
    
    DDLogInfo(@"Check Folder Names for Updates, IMAP folder count = %lu",
              (unsigned long)imapFolders.count);
    
    int folderIndex = 0;
    
    NSMutableArray* newFolderNames = [[NSMutableArray alloc] initWithCapacity:imapFolders.count];
    
    for (MCOIMAPFolder* imapFolder in imapFolders) {
        
        BOOL imapFolderMatchesLocalFolder = [self _localFolderMatchesImapFolder:imapFolder];
        
        // If the IMAP Folder being checked was not found in the Local Folders
        // then it is a NEW folder and needs to be added.
        if ( imapFolderMatchesLocalFolder == FALSE ) {
            
            DDLogDebug(@"IMAP Folder \"%@\" NOT found in local folders.",[imapFolder path]);
            
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
            
            DDLogVerbose(@"IMAP Folder (%@) == Local Folder %lu",
                      folderPath,(unsigned long)localFolderIndex);
            
            matchingFolderFound = TRUE;
            break;
        }
    } // for each local folder
    
    return matchingFolderFound;
}

-(NSInteger) _nextFolderToSync
{
    DDLogInfo(@"ENTERED");
    
//    SyncManager *syncMgr = [SyncManager getSingleton];
//        
//    NSInteger folderIndexForBaseFolderType = [self.user numFolderWithFolder:allFolderType()];
//    
//    NSDictionary *state = [syncMgr retrieveState:folderIndexForBaseFolderType
//                                      accountNum:self.user.accountNum];
//    
//    if ( ![state[@"fullsynced"] boolValue] ) {
//        return folderIndexForBaseFolderType;
//    }
    
    NSInteger allFolderNum = [self _folderIndexForBaseFolderType:FolderTypeAll];
    if ( [self _folderIsNotSynced:allFolderNum] ){
        DDLogInfo(@"All Folder Not Synced, do it next");
        return allFolderNum;
    }

//    if (![[[SyncManager getSingleton] retrieveState:[self.user numFolderWithFolder:inboxFolderType()] accountNum:self.user.accountNum][@"fullsynced"] boolValue]) {
//        return [self.user numFolderWithFolder:inboxFolderType()];
//    }
    
    NSInteger inboxFolderNumber = [self _folderIndexForBaseFolderType:FolderTypeInbox];
    if ( [self _folderIsNotSynced:inboxFolderNumber] ){
        DDLogInfo(@"Inbox Folder Not Synced, do it next");
        return inboxFolderNumber;
    }
    
//    if (![[[SyncManager getSingleton] retrieveState:[self.user numFolderWithFolder:FolderTypeWith(FolderTypeFavoris, 0)] accountNum:self.user.accountNum][@"fullsynced"] boolValue]) {
//        if ([self.user numFolderWithFolder:FolderTypeWith(FolderTypeFavoris, 0)] != -1) {
//            return [self.user numFolderWithFolder:FolderTypeWith(FolderTypeFavoris, 0)];
//        }
//    }
        
    NSInteger favorisFolderNumber = [self _folderIndexForBaseFolderType:FolderTypeFavoris];
    if ( [self _folderIsNotSynced:favorisFolderNumber] ){
        DDLogInfo(@"Favoris Folder Not Synced, do next");
        return favorisFolderNumber;
    }
    
//    if (![[[SyncManager getSingleton] retrieveState:[self.user numFolderWithFolder:FolderTypeWith(FolderTypeSent, 0)] accountNum:self.user.accountNum][@"fullsynced"] boolValue]) {
//        return [self.user numFolderWithFolder:FolderTypeWith(FolderTypeSent, 0)];
//    }
    
    NSInteger sentFolderNumber = [self _folderIndexForBaseFolderType:FolderTypeSent];
    if ( [self _folderIsNotSynced:sentFolderNumber] ){
        DDLogInfo(@"Sent Folder Not Synced, do next");
        return sentFolderNumber;
    }
    
    // Return the first unsynced user folder
    NSArray* folders = [self.user allFoldersDisplayNames];
    for (int indexFolder = 0; indexFolder < folders.count; indexFolder++) {
        
        if ( [self _folderIsNotSynced:indexFolder] ) {
            DDLogInfo(@"User Folder %ld Not Synced, do next",(long)indexFolder);
            return indexFolder;
        }
    }
    
    DDLogInfo(@"Could not find next folder to sync, returning -1");
    return -1;
}

-(NSInteger)_folderIndexForBaseFolderType:(NSInteger)folderType
{
    return [self.user numFolderWithFolder:FolderTypeWith(folderType, 0)];
}


-(BOOL)_folderIsNotSynced:(NSInteger)folderNumber
{
    SyncManager *syncMgr = [SyncManager getSingleton];
    
    NSDictionary *folderState = [syncMgr retrieveState:folderNumber accountNum:self.user.accountNum];
    
    BOOL folderIsSynced = [folderState[kFolderStateFullSyncKey] boolValue];
    
    BOOL retVal = (folderIsSynced == FALSE);
    
    DDLogVerbose(@"Folder #%ld \"fullsynced\" state = %@, _folderIsNotSynced returning %@",
                 (long)folderNumber,
                 (folderIsSynced?@"YES":@"NO"),
                 (retVal?@"YES":@"NO"));
    return retVal;
}


// MARK: - IMAP Sync Service: Search for Text or Person

-(RACSignal*) runSearchText:(NSString*)text
{
    DDLogInfo(@"ENTERED, search text = \"%@\"",text);
    
    @weakify(self);
    
    return [RACSignal createSignal:^RACDisposable* (id<RACSubscriber> subscriber) {
        @strongify(self);
        
        if (![ImapSync _isNetworkAvailable]) {
            self.connected = NO;
            DDLogError(@"\tIMAP Sync - Network is not available");
            [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMConnectionError userInfo:nil]];
        }
        
        NSInteger currentFolder = [self.user numFolderWithFolder:allFolderType()];
        NSString* folderPath = [self.user folderServerName:currentFolder];
        
        MCOIMAPSearchExpression* expr = [MCOIMAPSearchExpression searchContent:text];
        
        MCOIMAPSearchOperation* searchOperation = [self.imapSession searchExpressionOperationWithFolder:folderPath expression:expr];
        
        DDAssert(self.s_queue, @"s_queue must be set");

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

-(RACSignal*) runSearchPerson:(Person*)person
{
    DDLogInfo(@"ENTERED, person name = %@",person.name);

    @weakify(self);
    
    return [RACSignal createSignal:^RACDisposable* (id<RACSubscriber> subscriber) {
        @strongify(self);
        
        if (![ImapSync _isNetworkAvailable]) {
            self.connected = NO;
            DDLogError(@"IMAP Sync Service Network is not available error");
            [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMConnectionError userInfo:nil]];
        }
        
        NSInteger currentFolder = [self.user numFolderWithFolder:allFolderType()];
        MCOIMAPSearchExpression* expr = [MCOIMAPSearchExpression searchRecipient:person.email];
        MCOIMAPSearchOperation* searchOperation = [self.imapSession searchExpressionOperationWithFolder:[self.user folderServerName:currentFolder]
                                                                                expression:expr];
        
        DDAssert(self.s_queue, @"s_queue must be set");

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

// MARK: Local methods used by runSearchText and runSearchPerson

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
    DDAssert(self.s_queue, @"s_queue must be set");

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
    
    DDAssert(self.s_queue, @"s_queue must be set");

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


// MARK: - IMAP Sync Service: Add a Mail Folder

-(void)addFolder:(MCOIMAPFolder *)folder withName:(NSString*)folderName toAccount:(NSUInteger)accountNum
{
//    NSString* dispName = [ImapSync displayNameForFolder:folder usingSession:imapSession];
    
    // Append a new Folder Sync State Object for this Account
    SyncManager* syncManager = [SyncManager getSingleton];
    NSInteger newFolderSyncIndex = [syncManager addNewStateForFolder:folder
                                                                named:folderName
                                                           forAccount:accountNum];
    
    [self _updateSyncStateWithImapMessageCountForFolder:folder.path
                                          atFolderIndex:newFolderSyncIndex];
    
    return;
}



// MARK: Local methods for addFolder:

-(void) _updateSyncStateWithImapMessageCountForFolder:(NSString *)folderPath atFolderIndex:(NSInteger)folderIndex
{
    DDLogInfo(@"Folder Index = %@, Path = \"%@\"",@(folderIndex),folderPath);

    MCOIMAPFolderInfoOperation* folderOp = [self.imapSession folderInfoOperation:folderPath];
    
    [folderOp start:^(NSError* error, MCOIMAPFolderInfo* info) {
        
        DDLogInfo(@"BEGAN IMAP Folder Get Info Operation on %@",folderPath);
        
        if (error) {
            DDLogError(@"IMAP Folder Get Info Operation Error = %@",error);
        } else {
            
            DDLogDebug(@"Got Folder Sync State from folder %ld for IMAP folder \"%@\"",(long)folderIndex,folderPath);
            
            int msgCount = [info messageCount];
            
            [self _writeFolderStateMessageCount:msgCount andFolder:folderIndex];
            
        }
    }];
}


// MARK: - IMAP Sync Services: Process IMAP Folders and Messages

// "folder" is a Folder Index, or -1
-(RACSignal*) runFolder:(NSInteger)folder fromStart:(BOOL)isFromStart gettingAll:(BOOL)getAll
{
    DDLogInfo(@"ENTERED, folder=%@ fromStart=%@ getAll=%@",
              @(folder),
              (isFromStart==TRUE?@"TRUE":@"FALSE"),
              (getAll==TRUE?@"TRUE":@"FALSE"));

    
    if (folder == -1) {
        DDLogInfo(@"folderIndex = -1, so getting next folder to sync.");
        folder = [self _nextFolderToSync];
    }
    DDLogInfo(@"folderIndex = %@",@(folder));
    
    NSInteger currentFolder = folder;
    
    if (!self.cachedData) {
        self.cachedData = [[NSMutableArray alloc]initWithCapacity:1];
    }
    
    @weakify(self);
    
    return [RACSignal startLazilyWithScheduler:[RACScheduler schedulerWithPriority:RACSchedulerPriorityBackground] block:^(id<RACSubscriber> subscriber) {
        
        @strongify(self);
        
        DDLogInfo(@"BEGIN BLOCK - RACSchedulerPriorityBackground - Get List of All IMAP Folders");
        
        // get list of all folders from the IMAP Server
        
        if (self.isCanceled) {
            DDLogInfo(@"IMAP Sync Service CANCELLED, runFolder COMPLETED");
            [subscriber sendCompleted];
        }
        else if (![ImapSync _isNetworkAvailable]) {
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
            
            DDLogInfo(@"Running in Background && folder is not Inbox folder. We are completed.");

            [subscriber sendCompleted];
        }
        else {
            [self _loginImapServerAndUpdateFoldersAndMessages:subscriber currentFolder:currentFolder isFromStart:isFromStart getAll:getAll];
        }
    }];
}

// MARK: Local methods for runFolder:

- (void)_loginImapServerAndUpdateFoldersAndMessages:(id)subscriber currentFolder:(NSInteger)currentFolder isFromStart:(BOOL)isFromStart getAll:(BOOL)getAll
{
    DDLogInfo(@"ENTERED, Login IMAP Server=\"%@\"",self.user.imapHostname);
    
    [[ImapSync doLogin:self.user] subscribeError:^(NSError *error) {
        DDLogError(@"Login attempt failed. Send ERROR CCMConnectionError to subscriber");
        [subscriber sendError:error];
    } completed:^{
        DDLogInfo(@"Login attempt Completed.");
        
        if (!self.connected) {
            DDLogInfo(@"NOT Connected.");
            
            if ( [self _isRunningInBackground] ) {
                DDLogInfo(@"in BACKGROUND, so send COMPLETED to subscriber");
                
                [subscriber sendCompleted];
            }
            else {
                DDLogError(@"NOT in BACKGROUND. Send ERROR CCMConnectionError to subscriber");
                
                [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMConnectionError userInfo:nil]];
            }
        }
        else { // we are connected
            DDLogInfo(@"SUCCESSFULLY Connected.");
            
            [self _getImapFoldersAndMessages:subscriber currentFolder:currentFolder isFromStart:isFromStart getAll:getAll];
        }
    }];
}

- (void)_getImapFoldersAndMessages:(id)subscriber currentFolder:(NSInteger)currentFolder isFromStart:(BOOL)isFromStart getAll:(BOOL)getAll
{
    DDLogInfo(@"ENTERED, currentFolder=%@ fromStart=%@ getAll=%@",
              @(currentFolder),
              (isFromStart?@"TRUE":@"FALSE"),
              (getAll?@"TRUE":@"FALSE"));
    
    DDAssert(self.s_queue, @"s_queue must be set");

    MCOIMAPFetchFoldersOperation* fio = [self.imapSession fetchAllFoldersOperation];
    dispatch_async(self.s_queue, ^{
        
        DDLogInfo(@"BEGIN Fetch All IMAP Folders Operation");
        
        [fio start:^(NSError* error, NSArray<MCOIMAPFolder*>* imapFolders) {
            if (error) {
                DDLogError(@"\treturned error = %@. Send CCMConnectionError to subscriber",error.description);
                
                self.connected = NO;
                
                [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMConnectionError userInfo:nil]];
                
                return;
            }
            else if (!imapFolders || imapFolders.count == 0) {
                
                DDLogInfo(@"NO imap Folders, so send Completed to subscriber");
                [subscriber sendCompleted];
                
                return;
            } else {
                DDLogInfo(@"SUCCESS: have %lu folders.",(unsigned long)imapFolders.count);
            }
            
            [self _processFoldersAndGetImapMessages:subscriber currentFolder:currentFolder isFromStart:isFromStart getAll:getAll imapFolders:imapFolders];
        }];//Fetch All Folders
    });
}



- (void)_processFoldersAndGetImapMessages:(id)subscriber currentFolder:(NSInteger)currentFolder isFromStart:(BOOL)isFromStart getAll:(BOOL)getAll imapFolders:(NSArray<MCOIMAPFolder*>*)imapFolders
{
    DDLogInfo(@"ENTERED");
    
    DDAssert(self.s_queue, @"s_queue must be set");
    
    dispatch_async(self.s_queue, ^{
        
        [self _checkLocalFoldersForDeletionOnIMAPServer:imapFolders];
        
        [self _replaceDeletedImportantFolders:currentFolder imapFolders:imapFolders];
        
        [self _getImapMessages:currentFolder subscriber:subscriber isFromStart:isFromStart getAll:getAll];
    });
}

- (void)_checkLocalFoldersForDeletionOnIMAPServer:(NSArray<MCOIMAPFolder*>*)imapFolders
{
    SyncManager* syncMgr = [SyncManager getSingleton];
    
    // mark folders that were deleted on the server as deleted on the client
    NSInteger localFolderIndex = 0;
    NSInteger localFolderCount = [syncMgr folderCount:self.user.accountNum];
    
    DDLogInfo(@"We have %@ local folders.",@(localFolderCount));
    
    // Check each local folder, and if it is not found on the IMAP server,
    // then mark it deleted on locally.
    while (localFolderIndex < localFolderCount) {
        
        NSString* localFolderPath =
        [syncMgr retrieveFolderPathFromFolderState:localFolderIndex
                                        accountNum:self.user.accountNum];
        
        BOOL folderIsDeletedLocally =
        [syncMgr isFolderDeletedLocally:localFolderIndex accountNum:self.user.accountNum];
        
        if ( folderIsDeletedLocally ) {
            DDLogInfo(@"Local Folder %@: \"%@\" is (already) marked deleted locally.",@(localFolderIndex),localFolderPath);
        }
        else { // folder is not deleted locally
//            DDLogInfo(@"Local Folder %@: \"%@\" is NOT marked deleted locally.",@(localFolderIndex),localFolderPath);

//            BOOL folderDeletedOnImapServer ? ![imapFolders containsObject:localFolderPath];  // is imapFolders = [folders valueForKey @"path"]?
            BOOL folderDeletedOnImapServer = ![self _folderPath:localFolderPath isFoundInIMAPFolders:imapFolders];
            
            if ( folderDeletedOnImapServer ) {
                DDLogInfo(@"Local Folder %@: \"%@\" is not found on the IMAP Server (i.e. its been deleted), so mark local folder as deleted.",@(localFolderIndex),localFolderPath);
                
                [syncMgr markFolderDeleted:localFolderIndex accountNum:self.user.accountNum];
                localFolderIndex = 0;
            }
//            else {
//                DDLogDebug(@"\t\tIMAP Folder matching local folder exists, no work required.");
//            }
        }
        
        localFolderIndex++;
    }
}

-(BOOL)_folderPath:(NSString*)folderPath isFoundInIMAPFolders:(NSArray<MCOIMAPFolder*>*)imapFolders
{
    BOOL folderPathFound = FALSE;
    
    for ( MCOIMAPFolder *imapFolder in imapFolders ) {
        if ( [imapFolder.path isEqualToString:folderPath] ) {
            folderPathFound = TRUE;
            break;
        }
    }
    return folderPathFound;
}

- (void)_replaceDeletedImportantFolders:(NSInteger)currentFolder imapFolders:(NSArray<MCOIMAPFolder*>*)imapFolders
{
    SyncManager *syncMgr = [SyncManager getSingleton];
    
    DDLogInfo(@"ENTERED");
    
    // If the Current Folder is one of the deleted folders, and it is an Important
    // folder, then try to find a replacement folder.
    
    BOOL currentFolderIsDeletedLocally =
    [syncMgr isFolderDeletedLocally:currentFolder accountNum:self.user.accountNum];
    
    if ( currentFolderIsDeletedLocally ) {
        
        DDLogInfo(@"Current Folder %li is deleted locally",(long)currentFolder);
        
        CCMFolderType folderHandle = [self.user typeOfFolder:currentFolder];
        
        BOOL currentFolderIsAnImportantFolder = (folderHandle.type != FolderTypeUser);
        
        if ( currentFolderIsAnImportantFolder ) {
            
            DDLogInfo(@"\tThis an Important Folder, so earch for a match (replacemen) IMAP folder.");
            
            MCOMailProvider* accountProvider = [[MCOMailProvidersManager sharedManager] providerForIdentifier:self.user.identifier];
            
            // For each IMAP Folder
            for (MCOIMAPFolder* imapFolder in imapFolders) {
                
                DDLogInfo(@"Next IMAP Folder \"%@\" from array of all IMAP folders.", imapFolder.path);
                
                if (imapFolder.flags & MCOIMAPFolderFlagNoSelect) {
                    DDLogInfo(@"\thas NO Flags");
                    continue;
                }
                
                NSString *imapFolderName = [ImapSync displayNameForFolder:imapFolder usingSession:self.imapSession];
                
#if (LOG_INFO)
                if ( ![imapFolderName isEqualToString:imapFolder.path] ) {
                    DDLogInfo(@"IMAP Folder Path = \"%@\", IMAP Folder Name = \"%@\"",imapFolder.path,imapFolderName);
                }
#endif
                
                NSString* importantImapFolderPath = @"";
                
                
                switch ( folderHandle.type ) {
                    case FolderTypeInbox:
                        if ( (imapFolder.flags == MCOIMAPFolderFlagInbox) || [imapFolderName  isEqualToString: @"INBOX"] ) {
                            importantImapFolderPath = imapFolderName;
                            DDLogInfo(@"\tIs the INBOX folder.");
                        }
                        break;
                    case FolderTypeFavoris:
                        if ( ([accountProvider.starredFolderPath isEqualToString:imapFolderName] || (imapFolder.flags == MCOIMAPFolderFlagFlagged)) ) {
                            importantImapFolderPath = imapFolderName;
                            DDLogInfo(@"\tIs the FLAGGED folder.");
                        }
                        break;
                    case FolderTypeSent:
                        if ( ([accountProvider.sentMailFolderPath isEqualToString:imapFolderName] || (imapFolder.flags == MCOIMAPFolderFlagSentMail)) ) {
                            importantImapFolderPath = imapFolderName;
                            DDLogInfo(@"\tIs the SENT folder.");
                        }
                        break;
                    case FolderTypeDrafts:
                        if ( ([accountProvider.draftsFolderPath isEqualToString:imapFolderName] || (imapFolder.flags == MCOIMAPFolderFlagDrafts)) ) {
                            importantImapFolderPath = imapFolderName;
                            DDLogInfo(@"\tIs the DRAFTS folder.");
                        }
                        break;
                    case FolderTypeAll:
                        if ( ([accountProvider.allMailFolderPath isEqualToString:imapFolderName] || ((imapFolder.flags == MCOIMAPFolderFlagAll) || (imapFolder.flags == MCOIMAPFolderFlagAllMail))) ) {
                            importantImapFolderPath = imapFolderName;
                            DDLogInfo(@"\tIs the ARCHIVE folder.");
                        }
                        break;
                    case FolderTypeDeleted:
                        if ( ([accountProvider.trashFolderPath isEqualToString:imapFolderName] || (imapFolder.flags == MCOIMAPFolderFlagTrash)) ) {
                            importantImapFolderPath = imapFolderName;
                            DDLogInfo(@"\tIs the TRASH folder.");
                        }
                        break;
                    case FolderTypeSpam:
                        if ( ([accountProvider.spamFolderPath isEqualToString:imapFolderName] || (imapFolder.flags == MCOIMAPFolderFlagSpam)) ) {
                            importantImapFolderPath = imapFolderName;
                            DDLogInfo(@"\tIs the SPAM folder.");
                        }
                        break;
                    default:
                        DDLogError(@"/tIs UNKNOWN Important folder type (%@).",@(folderHandle.type));
                        break;
                }
                
//                if (folderHandle.type == FolderTypeInbox &&  ((imapFolder.flags == MCOIMAPFolderFlagInbox) || [imapFolderName  isEqualToString: @"INBOX"])) {
//                    importantImapFolderPath = imapFolderName;
//                    DDLogDebug(@"\t\tIs the INBOX folder.");
//                    //[self.user setImportantFolderNum:indexPath forBaseFolder:FolderTypeInbox];
//                } //Starred
//                else if(folderHandle.type == FolderTypeFavoris &&  ([accountProvider.starredFolderPath isEqualToString:imapFolderName] || (imapFolder.flags == MCOIMAPFolderFlagFlagged))) {
//                    importantImapFolderPath = imapFolderName;
//                    DDLogDebug(@"\t\tIs the FLAGGED folder.");
//                    //[self.user setImportantFolderNum:indexPath forBaseFolder:FolderTypeFavoris];
//                } //Sent
//                else if(folderHandle.type == FolderTypeSent &&  ([accountProvider.sentMailFolderPath isEqualToString:imapFolderName] || (imapFolder.flags == MCOIMAPFolderFlagSentMail))) {
//                    importantImapFolderPath = imapFolderName;
//                    DDLogDebug(@"\t\tIs the SENT folder.");
//                    //[self.user setImportantFolderNum:indexPath forBaseFolder:FolderTypeSent];
//                } //Draft
//                else if(folderHandle.type == FolderTypeDrafts &&  ([accountProvider.draftsFolderPath isEqualToString:imapFolderName] || (imapFolder.flags == MCOIMAPFolderFlagDrafts))) {
//                    importantImapFolderPath = imapFolderName;
//                    DDLogDebug(@"\t\tIs the DRAFTS folder.");
//                    //[self.user setImportantFolderNum:indexPath forBaseFolder:FolderTypeDrafts];
//                } //Archive
//                else if(folderHandle.type == FolderTypeAll &&  ([accountProvider.allMailFolderPath isEqualToString:imapFolderName] || ((imapFolder.flags == MCOIMAPFolderFlagAll) || (imapFolder.flags == MCOIMAPFolderFlagAllMail)))) {
//                    importantImapFolderPath = imapFolderName;
//                    DDLogDebug(@"\t\tIs the ARCHIVE folder.");
//                    //[self.user setImportantFolderNum:indexPath forBaseFolder:FolderTypeAll];
//                } //Trash
//                else if(folderHandle.type == FolderTypeDeleted &&  ([accountProvider.trashFolderPath isEqualToString:imapFolderName] || (imapFolder.flags == MCOIMAPFolderFlagTrash))) {
//                    importantImapFolderPath = imapFolderName;
//                    DDLogDebug(@"\t\tIs the TRASH folder.");
//                    
//                    //[self.user setImportantFolderNum:indexPath forBaseFolder:FolderTypeDeleted];
//                } //Spam
//                else if(folderHandle.type == FolderTypeSpam &&  ([accountProvider.spamFolderPath isEqualToString:imapFolderName] || (imapFolder.flags == MCOIMAPFolderFlagSpam))) {
//                    importantImapFolderPath = imapFolderName;
//                    DDLogDebug(@"\t\tIs the SPAM folder.");
//                    //[self.user setImportantFolderNum:indexPath forBaseFolder:FolderTypeSpam];
//                } else {
//                    DDLogDebug(@"\t\tIs NOT an Important folder.");
//                }
                
                BOOL thisImapFolderIsImportant = ![importantImapFolderPath isEqualToString:@""];
                
                if ( thisImapFolderIsImportant ) {
                    
                    DDLogInfo(@"\tImportant Folder Path = \"%@\"", importantImapFolderPath);
                    
                    // Review each local folder
                    NSUInteger localFolderCount = [syncMgr folderCount:(NSInteger)self.user.accountNum];
                    NSUInteger localFolderIndex = 0;
                    while ( localFolderIndex < localFolderCount ) {
                        
                        NSString* localFolderPath =
                        [syncMgr retrieveFolderPathFromFolderState:(NSInteger)localFolderIndex
                                                        accountNum:(NSInteger)self.user.accountNum];
                        
                        // If the Important Imap Folder matches the local folder
                        if ( [importantImapFolderPath isEqualToString:localFolderPath] ) {
                            
                            DDLogInfo(@"\tmatches local folder");
                            
                            [self.user setImportantFolderNum:localFolderIndex forBaseFolder:folderHandle.type];
                            
                            
                            break; // Important Folder replaced, we are done.
                        }
                        
                        localFolderIndex++;
                    }
                }//Set new important folder index
            }//Is there other folder same importance/role
        }//If important folder
    }
}

- (void)_getImapMessages:(NSInteger)currentFolder subscriber:(id)subscriber isFromStart:(BOOL)isFromStart getAll:(BOOL)getAll
{
    SyncManager *syncMgr = [SyncManager getSingleton];
    
    DDLogInfo(@"ENTERED, folder num = %@",@(currentFolder));
    
    NSInteger acntNumber = self.user.accountNum;
    
    NSString* folderPath =
    [syncMgr retrieveFolderPathFromFolderState:currentFolder accountNum:acntNumber];
    
    if ( folderPath == nil ) {
        DDLogError(@"Unable to retrieve folder path for folder=%@ and account=%@",
                   @(currentFolder),@(acntNumber));
        return;
    }
    
    NSInteger lastEnded = [syncMgr retrieveLastEndedFromFolderState:currentFolder accountNum:acntNumber];
    
    if ( lastEnded == -1 )  {
        DDLogError(@"Unable to retrieve last ended for folder=%@ and account=%@",
                   @(currentFolder),@(acntNumber));
        return;
    }
    
    
    MCOIMAPFolderInfoOperation* folderInfoOp = [self.imapSession folderInfoOperation:folderPath];
    
    [folderInfoOp start:^(NSError* error, MCOIMAPFolderInfo* imapFolderInfo) {
        if (error) {
            DDLogError(@"Unable to fetch IMAP folder for folder path \"%@\".  Error: %@", folderPath, error);
            
            self.connected = NO;
            [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMConnectionError userInfo:nil]];
            
            return;
        }
        
        if (self.isCanceled) {
            DDLogInfo(@"Cancelled == TRUE, so sending Completed to subscriber");
            [subscriber sendCompleted];
            return;
        }
        
        [self _fetchImapMessages:subscriber
                   currentFolder:(NSUInteger)currentFolder
                     isFromStart:isFromStart
                          getAll:getAll
                      folderPath:folderPath
                    messageCount:(NSUInteger)imapFolderInfo.messageCount
                       lastEnded:(NSUInteger)lastEnded];
    }];
}

- (void)_fetchImapMessages:(id)subscriber currentFolder:(NSUInteger)currentFolder isFromStart:(BOOL)isFromStart getAll:(BOOL)getAll folderPath:(NSString *)folderPath messageCount:(NSUInteger)msgCount lastEnded:(NSUInteger)lastEnded
{
    DDLogInfo(@"ENTERED, folder path = %@",folderPath);
    
    DDAssert(self.s_queue, @"s_queue must be set");

    dispatch_async(self.s_queue, ^{
        
        int batchsize = 50;
        
        DDLogInfo(@"Folder has %ld emails", (long)msgCount);
        
        if ( ![self _isRunningInBackground] ) {
            
            DDLogInfo(@"we are not running in background, so ... Save email count (%lu) to Local State Storage",(long)msgCount);
            
            [self _writeFolderStateMessageCount:msgCount andFolder:currentFolder];
            
            // If (the folder contains NO messages), OR
            // (we are NOT loading folder messages from Index
            //   Zero AND the last loaded message was Index One)
            if (msgCount == 0 || (!isFromStart && (lastEnded == 1))) {
                
                DDLogInfo(@"No Messages OR (Not from Start AND Last Ended == 1");
                
                NSUInteger lastEndedIndex = 0;
                if ( msgCount == 0 ) {
                    lastEndedIndex = 1;
                }
                else {
                    lastEndedIndex = lastEnded;
                }
                
                DDLogInfo(@"Save Last Ended Index (%lu) to Local State Storage",(long)lastEndedIndex);
                
                [self _writeFolderStateLastEnded:lastEndedIndex andFolder:currentFolder];
                
                DDLogInfo(@"and send CCMFolderSyncedError to subscriber.");
                
                [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMFolderSyncedError userInfo:nil]];
                return;
            }
        }
        
        NSUInteger from = (NSUInteger) msgCount;
        
        if (!(isFromStart || [self _isRunningInBackground]) && lastEnded != 0) {
            from = lastEnded-1;
        }
        
        NSUInteger batch = (NSUInteger) MIN( ((NSUInteger)batchsize), ((NSUInteger)msgCount) );
        
        uint64_t ullFrom = (uint64_t)from;
        
        batch--;
        
        if ( ullFrom > batch) {
            ullFrom -= batch;
        }
        else {
            ullFrom = 1;
        }
        
        MCOIndexSet* numbers = [MCOIndexSet indexSetWithRange:MCORangeMake(ullFrom, batch)];
        
        MCOIMAPFetchMessagesOperation* imapMessagesFetchOp =
        [self.imapSession fetchMessagesByNumberOperationWithFolder:folderPath
                                                       requestKind:self.user.requestKind
                                                           numbers:numbers];
        
        DDLogInfo(@"BEGIN Fetch Messages for Folder \"%@\".",folderPath);
        
        [imapMessagesFetchOp start:^(NSError* error, NSArray<MCOIMAPMessage*>* imapMessages, MCOIndexSet* vanishedMessages) {
            
            if (error) {
                DDLogInfo(@"Error %@ fetching messages.  Send CCMConnectionError to subscriber.",error.description);
                
                self.connected = NO;
                [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMConnectionError userInfo:nil]];
                
                return;
            }
            
            DDLogInfo(@"got %lu messages.",(unsigned long)imapMessages.count);
            
            [self _processImapMessages:imapMessages subscriber:(id)subscriber currentFolder:currentFolder from:from isFromStart:isFromStart getAll:getAll];
            
        }];//Fetch Messages
    });
    
}

- (void)_processImapMessages:(NSArray<MCOIMAPMessage*>*)imapMessages subscriber:(id)subscriber currentFolder:(NSUInteger)currentFolder from:(NSInteger)from isFromStart:(BOOL)isFromStart getAll:(BOOL)getAll
{
    DDLogInfo(@"ENTERED, num IMAP msgs = %@",@(imapMessages.count));
    
    DDAssert(self.s_queue, @"s_queue must be set");
    
    dispatch_async(self.s_queue, ^{
        
        SyncManager *syncMgr = [SyncManager getSingleton];
        
        // Message ID of the last mail message returned by the IMAP server
        NSString* lastMsgID = [imapMessages lastObject].header.messageID;
        
        for (MCOIMAPMessage* imapMsg in imapMessages) {
            
            
            if (self.isCanceled) {
                DDLogInfo(@"isCancelled == TRUE, so sending Completed to subscriber");
                [subscriber sendCompleted];
                return;
            }
            
            NSString* folderPath = [syncMgr retrieveFolderPathFromFolderState:currentFolder accountNum:self.user.accountNum];
            
            if ( folderPath == nil ) {
                DDLogError(@"Could not get Folder Path from Sync Manager for folder=%@ in account=%@",@(currentFolder),@(self.user.accountNum));
                return;
            }
            
            Mail* email = [Mail mailWithMCOIMAPMessage:imapMsg inFolder:currentFolder andAccount:self.user.accountNum];
            
            DDLogInfo(@"\nEMAIL Subj: \"%@\" | MsgId:  \"%@\" | AcntNum: %@ | FolderNum: %@",
                      email.subject,email.msgID,@(self.user.accountNum),@(currentFolder));
            
            if ([UidEntry hasUidEntrywithMsgId:email.msgID inAccount:self.user.accountNum]) {
                
//                DDLogInfo(@"--- Message already exists in this Account's Databsase");
                
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

-(BOOL) _saveEmail:(Mail*)email folder:(NSInteger)currentFolder
{
    //Cache email if in Background
    if ( [self _isRunningInBackground] ) {
        
        DDLogInfo(@"Running in the Background, so Cache Email.");
        return [self _cacheEmail:currentFolder email:email];
    }
    else {
        DDLogInfo(@"NOT Running in the background, So get next Email.");

        NSInvocationOperation* nextOp
        = [[NSInvocationOperation alloc] initWithTarget:[EmailProcessor getSingleton]
                                               selector:@selector(addEmailWrapper:)
                                                 object:email];
        
        [[EmailProcessor getSingleton].operationQueue addOperation:nextOp];
        [[EmailProcessor getSingleton].operationQueue waitUntilAllOperationsAreFinished];
    }
    
    return NO;
}

- (BOOL)_cacheEmail:(NSInteger)currentFolder email:(Mail *)email
{
    DDLogInfo(@"Cache mail:%@ in Folder:%@",email.sender.displayName,@(currentFolder));
    
    BOOL emailCached = NO;
    
    BOOL isInInbox = (currentFolder == [self.user numFolderWithFolder:inboxFolderType()]);
    BOOL isUnread = !(email.flag & MCOMessageFlagSeen);
    if (isInInbox & isUnread) {
        NSMutableSet* eIds = [self _emailIDs];
        
        if (![eIds containsObject:email.msgID]) {
            Mail* newE = [email copy];
            UidEntry *uid = email.uids[0];
            DDLogInfo(@"Had Cached %@ Emails in account:%@", @(eIds.count), @(uid.accountNum));
            
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
            
            if (isUnread && [AppSettings notifications:(NSInteger)self.user.accountNum]) {
                
                [self _notifyUserOfNewMail:email ci:index conv:conv];
            }
            
            emailCached = YES;
        }
    }
    return emailCached;
}

#pragma mark - Notify User of New Mail


-(void)_notifyUserOfNewMail:(Mail *)email ci:(ConversationIndex *)index conv:(Conversation*)conv
{
    if ( [UNUserNotificationCenter class] ) {   // Exists only on iOS 10 plus
        
        NSString* alertText = [NSString stringWithFormat:@"%@%@",(email.hasAttachments?@"📎 ":@""), email.subject];
        
        // escape % signs
        alertText = [alertText stringByReplacingOccurrencesOfString:@"%" withString:@"%%"];
        
        UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
        DDAssert(center, @"The UNUserNotificationCenter must exist");
        
        [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings * _Nonnull settings) {
            
            if ( settings.authorizationStatus == UNAuthorizationStatusAuthorized ) {
                DDLogInfo(@"The User has Authorized Notifications");
                
                UNMutableNotificationContent* content = [[UNMutableNotificationContent alloc] init];
                
                if ( settings.alertSetting == UNNotificationSettingEnabled ) {
                    
                    DDLogInfo(@"Notification Alerts are Enabled.");
                    
                    content.title = @"CocoaMail"; //[NSString localizedUserNotificationStringForKey:@"NewMailNotifTitle" arguments:nil];
                    content.subtitle = email.sender.displayName;
                    content.body  = alertText;
                }
                else {
                    DDLogInfo(@"Notification Alerts are NOT Enabled.");
                }
                
                if ( settings.soundSetting == UNNotificationSettingEnabled) {
                    DDLogInfo(@"Notification Sounds are Enabled.");
                    
                    content.sound = [UNNotificationSound defaultSound];
                }
                else {
                    DDLogInfo(@"Notification Sounds are NOT Enabled.");
                }
                
                if ( settings.badgeSetting == UNNotificationSettingEnabled ) {
                    DDLogInfo(@"Notification Badge is Enabled.");
                    
                    NSNumber *unreadMailCount = [[NSNumber alloc] initWithInteger:0];
                    content.badge = unreadMailCount;
                }
                else {
                    DDLogInfo(@"Notification Badge is NOT Enabled.");
                }
                
                content.categoryIdentifier = @"MAIL_CATEGORY";
                content.userInfo = @{ @"cIndexIndex"      : @(index.index),
                                      @"cIndexAccountNum" : @(index.user.accountNum) };
                
                UNTimeIntervalNotificationTrigger *trigger = nil;   // trigger the notification right away
                
                UNNotificationRequest *notificationRequest = [UNNotificationRequest requestWithIdentifier:@"NewMessageNotification"
                                                                                                  content:content
                                                                                                  trigger:trigger];
                
                [center addNotificationRequest:notificationRequest
                         withCompletionHandler:^(NSError * _Nullable error) {
                             if ( error ) {
                                 // Report Error
                                 DDLogError(@"Failed to add NUNotificationRequest, error = %@",error);
                             } else {
                                 DDLogInfo(@"Added NUNotifidationRequest.");
                             }
                         }];
            }
            else {
                DDLogInfo(@"The User has NOT Authorized Notifications");
            }
        }];
        
    } else { // user older deprecated notification system
        
        NSString* alertText = [NSString stringWithFormat:@"%@\n%@%@",
                               email.sender.displayName, (email.hasAttachments?@"📎 ":@""), email.subject];
        
        // escape % signs
        alertText = [alertText stringByReplacingOccurrencesOfString:@"%" withString:@"%%"];
        
        UILocalNotification* localNotification = [[UILocalNotification alloc] init];
        
        localNotification.fireDate = [NSDate dateWithTimeIntervalSinceNow:10];
        localNotification.alertBody = alertText;
        localNotification.timeZone = [NSTimeZone defaultTimeZone];
        localNotification.userInfo = @{ @"cIndexIndex"      : @(index.index),
                                        @"cIndexAccountNum" : @(index.user.accountNum) };
        localNotification.category = @"MAIL_CATEGORY";
        
        DDLogDebug(@"Index: %ld",(long)index.index);
        DDLogDebug(@"Conversation: %@",[conv firstMail].subject);
        
        [[UIApplication sharedApplication] presentLocalNotificationNow:localNotification];
    }
    
}

-(NSMutableSet *) _emailIDs
{
    return [NSMutableSet setWithArray:[[AppSettings getSingleton] cache]];
}

-(void) _writeFolderStateMessageCount:(NSUInteger)messageCount andFolder:(NSUInteger)folderNum
{
    if ( self.user.isDeleted ) {
        DDLogInfo(@"User is Deleted, don't write folder message count.");
        return;
    }
    
    SyncManager *sm = [SyncManager getSingleton];
    [sm updateMessageCount:messageCount forFolderNumber:folderNum andAccountNum:self.user.accountNum];
}

-(void) _writeFolderStateLastEnded:(NSUInteger)lastEIndex andFolder:(NSUInteger)folderNum
{
    if ( self.user.isDeleted ) {
        DDLogInfo(@"User is Deleted, don't write folder state last ended.");
        return;
    }
    
    SyncManager *sm = [SyncManager getSingleton];
    [sm updateLastEndedIndex:lastEIndex forFolderNumber:folderNum andAccountNum:self.user.accountNum];
    
    //[[[Accounts sharedInstance] getAccount:self.currentAccountIndex] showProgress];
}

// MARK: - IMAP Sync Service: run up to date cache test - NOT USED!

-(void) runUpToDateCachedTest:(NSArray*)emails
{
    MCOIndexSet* uidsIS = [[MCOIndexSet alloc]init];
    Account *currentAccount = [Accounts sharedInstance].currentAccount;
    NSString* path = [self.user folderServerName:[currentAccount currentFolderIdx]];
    
    NSMutableArray* datas = [[NSMutableArray alloc]init];
    
    for (Mail* email in emails) {
        //TODO: Get the right uid corresponding to the message id and folder
        
        UidEntry* uid_entry = [UidEntry getUidEntryWithFolder:(NSInteger)[currentAccount currentFolderIdx]
                                                        msgID:email.msgID];
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
         
         DDAssert(self.s_queue, @"s_queue must be set");
         
         dispatch_async(self.s_queue, ^{
             [op start:^(NSError* error, NSArray* messages, MCOIndexSet* vanishedMessages) {
                 
                 if (error) {
                     [self _setConnected:NO];
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


// MARK: - IMAP Sync Server: Up to Date Test
// MARK: Called by -[Account runMoreTestData] and -[Account runTestData]

-(void) runUpToDateTest:(NSArray*)convs folderIndex:(NSInteger)folderIdx completed:(void (^)(NSArray<Mail*>* dels, NSArray<Mail*>* ups, NSArray<NSString*>* days))completedBlock
{
    DDLogInfo(@"BEGIN - Folder=%@ ConvCnt=%@",@(folderIdx),@(convs.count));
    
    MCOIndexSet* uidsIS = [[MCOIndexSet alloc]init];
    NSMutableArray<Mail*>* mails = [NSMutableArray arrayWithCapacity:convs.count];
    
    for (Conversation* conv in convs) {
        for (Mail* mail in conv.mails) {
            if ([mail uidEWithFolder:folderIdx]) {
                [uidsIS addIndex:[mail uidEWithFolder:folderIdx].uid];
                [mails addObject:mail];
            }
        }
    }
    
    NSString* path = [self.user folderServerName:(NSUInteger)folderIdx];
    
    DDLogDebug(@"Testing folder \"%@\" with %i emails in accountIndex:%ld", path, uidsIS.count, (long)self.user.accountNum);
    
    if (uidsIS.count == 0) {
        completedBlock(nil, nil, nil);
        return;
    }
    
    NSMutableArray<Mail*>* delDatas = [[NSMutableArray alloc]init];
    NSMutableArray<Mail*>* upDatas = [[NSMutableArray alloc]init];
    NSMutableArray<NSString*>* days = [[NSMutableArray alloc]init];  // from Mail.day

    // Login to the folder's IMAP server
    [[ImapSync doLogin:self.user]
     subscribeError:^(NSError *error) {
         completedBlock(delDatas, upDatas, days);
     } completed:^{
         
         if (!self.connected){
             completedBlock(delDatas, upDatas, days);
             return;
         }
         
         DDAssert(self.s_queue, @"s_queue must be set");
         
         // Get the headers and flags for all the messages in the folder
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wassign-enum"
         MCOIMAPMessagesRequestKind requestKind = MCOIMAPMessagesRequestKindHeaders | MCOIMAPMessagesRequestKindFlags;
#pragma clang diagnostic pop
         MCOIMAPFetchMessagesOperation* op = [self.imapSession fetchMessagesOperationWithFolder:path requestKind:requestKind uids:uidsIS];
         dispatch_async(self.s_queue, ^{
             [op start:^(NSError* error, NSArray* messages, MCOIndexSet* vanishedMessages) {
                 
                 if (error) {
                     [self _setConnected:NO];
                     DDLogError(@"error testing emails in %@, %@", path, error);
                     completedBlock(delDatas, upDatas, days);
                     return;
                 }
                 
                 DDLogDebug(@"Connected and Testing folder \"%@\" (in accountIndex:%ld) for updated and deleted mails", path, (long)self.user.accountNum);
                 
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

@end
