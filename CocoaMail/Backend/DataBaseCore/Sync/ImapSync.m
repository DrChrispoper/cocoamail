

//
//  ImapSync.m
//  CocoaMail
//
//  Created by Christopher Hockley on 20/01/2012.
//  Copyright (c) 2012 Christopher Hockley. All rights reserved.

#import "ImapSync.h"
#import "SyncManager.h"
#import "AppSettings.h"
#import "AppDelegate.h"
#import "SearchRunner.h"
#import "EmailProcessor.h"
#import "UidEntry.h"
#import "CachedAction.h"
#import "Attachments.h"
#import "Reachability.h"
#import <libextobjc/EXTScope.h>
#import "Mail.h"

#import "GTMAppAuth.h"
#import "GTMSessionFetcher.h"

#import "ViewController.h"
#import "StringUtil.h"
#import "CCMConstants.h"
#import "UserSettings.h"

#import <MailCore/MCOConstants.h>       // for MCOErrorDomain
#import <MailCore/MCOIndexSet.h>
#import <MailCore/MailCore.h>

#import <NotificationCenter/NotificationCenter.h>
#import <UserNotifications/UserNotifications.h>
#import <UserNotificationsUI/UserNotificationsUI.h>

#import <CocoaLumberjack/CocoaLumberjack.h>

#ifdef USING_INSTABUG
#import <Instabug/Instabug.h>
#endif

extern NSString *const CCMCategoryIdentifier;
extern NSString *const CCMDeleteTriggerIdentifier;

#define ONE_MONTH_IN_SECONDS    ( 60 * 60 * 24 * 30 )



@interface ImapSync ()

@property (nonatomic, strong) NSMutableArray* cachedData;
@property (nonatomic) UserSettings* user;
@property (nonatomic, strong) MCOIMAPOperation* imapCheckOp;
@property (nonatomic) BOOL isCanceled;

@end

static NSArray<ImapSync*>* sharedServices = nil;        // Obj-C now allows Class Parameters - maybe try that?


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
        }
    }
    
    DDLogError(@"Unable to find Account Number %@",@(user.accountNum));
        
    return nil;
}

+(NSArray<ImapSync*>*) allSharedServices:(MCOIMAPSession*)update
{
    DDLogVerbose(@"ENTERED");
    
    @synchronized(sharedServices) {
        
        if (update) {
            DDLogDebug(@"Updating IMAP Session, so generate new sharedServices.");
            sharedServices = nil;
        }
    
        // If we already have one or more shared services, then return them
        if (sharedServices && sharedServices.count > 0) {
            DDLogDebug(@"RETURNING existing sharedServices[0..%@]",@(sharedServices.count));
            return sharedServices;
        }
        
        // Create new sharedServices, one for each user.
        
        NSMutableArray<ImapSync*>* newSharedServices = [[NSMutableArray alloc]init];
        
        NSArray<UserSettings*>* allUsers = [AppSettings getSingleton].users;
        
        // Create a new ImapSync Shared Service for each (non deleted) user
        for (UserSettings* user in allUsers ) {
            
            if (user.isDeleted) {
                continue;   // next UserSettings
            }
            
            DDLogDebug(@"Create new IMAP Shared Service to for Account \"%@\" (# %@)",user.username,@(user.accountNum));
            
            // Create and set up new Imap Sync Shared Service
            ImapSync* sharedService = [[super allocWithZone:nil] init];
            sharedService.user = user;
            sharedService.connected = NO;
            sharedService.s_queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0);
            
            // If an updated Imap Session was passed in, and its username matches this user, then update the new service
            if (update && [update.username isEqualToString:user.username]) {
                sharedService.imapSession = update;
                sharedService.imapSession.dispatchQueue = sharedService.s_queue;
                sharedService.connected = YES;
            }
            else {
                // method was called with update=nil, or update is not for this user
                
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
        
        sharedServices = [NSArray arrayWithArray:newSharedServices];
        
        return sharedServices;
        
    } // end @synchronized(sharedServices)
}

// MARK: - IMAP Sync Service: is Network available via WiFi

// Can we sync Data across WiFi or Cell (if allowed)
+(BOOL) canFullSync
{
    Reachability* networkReachability = [Reachability reachabilityForInternetConnection];
    NetworkStatus networkStatus = [networkReachability currentReachabilityStatus];
    
    BOOL canFullSync = [[AppSettings getSingleton] canSyncOverData] || (networkStatus == ReachableViaWiFi);
    
    if ( !canFullSync ) {
        DDLogInfo(@"returning FALSE");
    } else {
        DDLogVerbose(@"returning TRUE");
    }
    
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
            DDLogWarn(@"IMAP Folder Path \"%@\" is not prefixed by \"%@\"",folder.path,folderPathPrefix);
        }
        
    } else {
        DDLogDebug(@"IMAP Namespace has NO Prefix.");
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

+(void) getInboxUnreadCountForUser:(UserSettings*)user completed:(void (^)(void))completedBlock
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
    
    [self _runUnreadCount:user folder:inboxFolderType() completed:completedBlock];
}

+(void) _runUnreadCount:(UserSettings*)user folder:(CCMFolderType)folder completed:(void (^)(void))completedBlock
{
    DDLogInfo(@"ENTERED");

    dispatch_queue_t imapDispatchQueue = [ImapSync sharedServices:user].s_queue;
    DDAssert(imapDispatchQueue, @"IMAP Displatch Queue must exist!");
    dispatch_async(imapDispatchQueue, ^{
        
        NSInteger folderNumber = [user numFolderWithFolder:folder];
        if ( folderNumber == -1 ) {
            DDLogWarn(@"folder number is -1");
        }
        else {
            // have a folder number
            
            NSString* serverFolderPath = [user folderServerName:folderNumber];
            MCOIMAPSearchExpression* expr = [MCOIMAPSearchExpression searchUnread];
            MCOIMAPSearchOperation* so = [[ImapSync sharedServices:user].imapSession searchExpressionOperationWithFolder:serverFolderPath expression:expr];
            
            [so start:^(NSError* error, MCOIndexSet* searchResult) {
                DDLogVerbose(@"STARTED Search for All Unread Mails Operation");
                
                if (!error) {
                    DDLogInfo(@"Folder \"%@\" has %@ unread mails.",
                              serverFolderPath,@(searchResult.count));
                    
                    // TODO: To be used for OTHER mailboxes, this should be other than Inbox only!
                    [AppSettings setInboxUnread:searchResult.count accountIndex:(NSInteger)user.accountIndex];
                }
                else {
                    //                - On failure, `error` will be set with `MCOErrorDomain` as domain and an
                    //                error code available in MCOConstants.h, `searchResult` will be nil
                    DDLogError(@"Search for All Unread Mails Operation Failed, error = %@",error);
                }
                
                if (completedBlock) {
                    completedBlock();
                }
            }];
        }
    });
 
}



// MARK: - IMAP Sync Service: set this IMAP service as Cancelled

-(void) cancel
{
    self.isCanceled = YES;
}

// MARK: - IMAP Sync Service: save Cached Data - removes cache object

-(void) saveCachedData
{
//    NSMutableArray* ops = [[NSMutableArray alloc] initWithCapacity:self.cachedData.count];
//    /*EmailProcessor* ep = [EmailProcessor getSingleton];
//     
//     NSURL* someURL = [[NSURL alloc] initFileURLWithPath:[StringUtil filePathInDocumentsDirectoryForFileName:@"cache"]];
//     [[[NSArray alloc]init] writeToURL:someURL atomically:YES];
//     
//     if (self.cachedData) {
//     for (Mail* mail in self.cachedData) {
//     DDLogInfo(@"Saving Cached Email: %@", mail.subject);
//     
//     NSInvocationOperation* nextOp = [[NSInvocationOperation alloc] initWithTarget:ep selector:@selector(addEmailWrapper:) object:mail];
//     [ops addObject:nextOp];
//     }
//     }
//     
//     [ep.operationQueue addOperations:ops waitUntilFinished:YES];*/
    
    self.cachedData = nil;
    
}

// MARK: - Local Methods, called by multiple methos
// Like dispatch_sync but works on current queue
// See: https://stackoverflow.com/questions/10984732/why-cant-we-use-a-dispatch-sync-on-the-current-queue/15725847#15725847
//
static inline void dispatch_synchronized (dispatch_queue_t queue,
                                          dispatch_block_t block)
{
    dispatch_queue_set_specific (queue, (__bridge const void * _Nonnull)(queue), (void *)1, NULL);
    if (dispatch_get_specific ((__bridge const void * _Nonnull)(queue)))
        block ();
    else
        dispatch_sync (queue, block);
}

+(BOOL)isRunningInForeground
{
    return ([ImapSync isRunningInBackground] == FALSE);
}
+(BOOL)isRunningInBackground
{
    __block UIApplicationState appState;
    
    // Run this query on the main queue, block till finished
    dispatch_synchronized(dispatch_get_main_queue(), ^{
        UIApplication *app = [UIApplication sharedApplication];
        appState = [app applicationState];
    });
        
    BOOL isInBackground = ( appState == UIApplicationStateBackground);

    DDLogVerbose(@"\tApp isInBackground = %@",(isInBackground==TRUE?@"TRUE":@"FALSE") );
    
    return isInBackground;
}
+(BOOL) _isNetworkAvailable
{
    Reachability* networkReachability = [Reachability reachabilityForInternetConnection];
    NetworkStatus networkStatus = [networkReachability currentReachabilityStatus];
    
    DDLogDebug(@"%@",[self _networkStatusText:networkStatus]);
    
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
    DDLogDebug(@"Try to log in to \"%@\"",user.imapHostname);
    
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
    DDLogInfo(@"Andy is CURIOUS: \"user\" %@ \"sharedService.user\"",(user == sharedService.user?@"DOES":@"DOES NOT"));

    
    if (![ImapSync _isNetworkAvailable]) {
        
        DDLogError(@"Network is not available, send CCMConnectionError to subscriber.");
        
        return [RACSignal startEagerlyWithScheduler:[RACScheduler scheduler] block:^(id<RACSubscriber> subscriber) {
            sharedService.connected = NO;
            [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain
                                                      code:CCMConnectionError
                                                  userInfo:nil]];
        }];
    }
    
    
    if ( sharedService.signal ) {
        
        DDLogInfo(@"Returning (existing) Shared IMAP Sync Service Signal");
        
        return sharedService.signal;
    }
    
    DDLogInfo(@"CREATE NEW Shared IMAP Sync Service Signal.");
    
    sharedService.signal = [RACSignal startEagerlyWithScheduler:[RACScheduler scheduler]
                      block:^(id<RACSubscriber> subscriber)
    {
        if (sharedService.connected) {
            DDLogInfo(@"Shared IMAP Sync Service: is Connected");
            [subscriber sendCompleted];
            return;
        }

        if ([sharedService.user isUsingOAuth]) {
            DDLogInfo(@"Shared IMAP Sync Service: Attempt log in with OAuth.");

            [self _loginWithOAuth:sharedService forUser:user withSubscriber:subscriber];
        }
        else { //Not using OAuth
            DDLogDebug(@"Shared IMAP Sync Service: Attempt log in with Password.");

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

+(GTMAppAuthFetcherAuthorization*)getGoogleAuthFromKeychainForUser:(UserSettings*)user
{
    // Try to load in the new keychain format
    id<GTMFetcherAuthorizationProtocol> authFromKeychain =
    [GTMAppAuthFetcherAuthorization authorizationFromKeychainForName:NEW_USR_TKN_KEYCHAIN_NAME];
    
    // If no data found in the new format, try to deserialize data from GTMOAuth2
    if (!authFromKeychain) {
        
        // Tries to load the data serialized by GTMOAuth2 using old keychain name.
        // If you created a new client id, be sure to use the *previous* client id and secret here.
        authFromKeychain =
        [GTMOAuth2KeychainCompatibility authForGoogleFromKeychainForName:OLD_USR_TKN_KEYCHAIN_NAME
                                                                clientID:CLIENT_ID
                                                            clientSecret:CLIENT_SECRET];
        if (authFromKeychain) {
            // Remove previously stored GTMOAuth2-formatted data.
            [GTMOAuth2KeychainCompatibility removeAuthFromKeychainForName:OLD_USR_TKN_KEYCHAIN_NAME];
            // Serialize to Keychain in GTMAppAuth format.
            [GTMAppAuthFetcherAuthorization saveAuthorization:(GTMAppAuthFetcherAuthorization *)authFromKeychain
                                            toKeychainForName:NEW_USR_TKN_KEYCHAIN_NAME];
        }
    }
    return (GTMAppAuthFetcherAuthorization*)authFromKeychain;
}

+(void) _showImapCheckOpError:(NSError*)error
{
    /*
     * Display IMAP Check Error code debugging information
     */
    
    switch ( error.code ) {
        case MCOErrorConnection:
            /** An error related to the connection occurred.*/
            /** It could not connect or it's been disconnected.*/
            DDLogWarn(@"IMAP Check Account Operation returned Error \"Could not Connect\"");
            break;
            
        case MCOErrorAuthentication:
            
            // Use DDLogWarn so icon appears to pull attention
            DDLogWarn(@"IMAP Check Account Operation returned Error \"Invalid OAuth Credentials\"");
            break;
            
        default:
            DDLogWarn(@"IMAP Check Account Operatation returned unknown error code %@, see \"MCOConstants.h\"",@(error.code));
            break;
    }
    DDLogInfo(@"Will attempt Google OAuth reauthorization");
}

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
        
        // imapCheckOp will try to login, using the OAuth2 access token if one has been set
        [sharedService.imapCheckOp start:^(NSError* error) {
            
            // If NO error doing the IMAP Check operation ...
            if (error == nil) {
                
                DDLogDebug(@"Account:%ld check OK", (long)sharedService.user.accountNum);
                sharedService.connected = YES;
                [sharedService.user.linkedAccount setConnected];
                [sharedService _checkForCachedActions];
                [sharedService _getImapFolderNamesAndUpdateLocal];
                
                DDLogInfo(@"IMAP host \"%@\" OAuth login successful.",sharedService.user.imapHostname);
                
                [subscriber sendCompleted];
            }
            else { // the IMAP Check Operation returned an error
                
                if ( [error.domain isEqual:MCOErrorDomain] ) {
                    [ImapSync _showImapCheckOpError:error];
                }
                
                /*
                 * Get any existing Auth info from the keychain.
                 */
                
                // Get Authorization Info from the Keychain
//                GTMAppAuthFetcherAuthorization* auth = [GTMOAuth2KeychainCompatibility authForGoogleFromKeychainForName:USR_TKN_KEYCHAIN_NAME
//                                                                                                       clientID:CLIENT_ID
//                                                                                                   clientSecret:CLIENT_SECRET];
                
                // Attempt to deserialize from Keychain in GTMAppAuth format.
                GTMAppAuthFetcherAuthorization* authFromKeychain = [ImapSync getGoogleAuthFromKeychainForUser:user];
                if ( authFromKeychain == nil ) {
                    DDLogError(@"getGoogleAuthFromKeychainForUser Failed to return a GTMAppAuthFetcherAuthorization.\"");
                    [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMAppAuthError userInfo:nil]];
                }
                
                user.linkedAccount.authorization = authFromKeychain; // both point to same object
                
//                [auth setUserEmail:sharedService.user.username];

                // See if we are NOT already authorized (e.g. don't have a token or have an error from trying to access the token)
                if ( ![authFromKeychain canAuthorize] ) {

                    OIDServiceConfiguration *configuration =
                    [GTMAppAuthFetcherAuthorization configurationForGoogle];
                    
                    OIDAuthorizationRequest *authRequest =
                    [[OIDAuthorizationRequest alloc] initWithConfiguration:configuration
                                                                  clientId:kNewClientID
                                                              clientSecret:kClientSecret
                                                                    scopes:@[OIDScopeOpenID, OIDScopeProfile]
                                                               redirectURL:[NSURL URLWithString:kRedirectUrl]
                                                              responseType:OIDResponseTypeCode
                                                      additionalParameters:nil];
                    
                    AppDelegate *appDelegate = (AppDelegate *)[UIApplication sharedApplication].delegate;
                    
                    // performs authentication request, storing the auth flow in the app delegate so it can be processed
                    // when it reutrns to the app
                    appDelegate.currentAuthorizationFlow =
                    [OIDAuthState authStateByPresentingAuthorizationRequest:authRequest
                                                   presentingViewController:[ViewController mainVC]
                                                                   callback:^(OIDAuthState *_Nullable authState,
                                                                              NSError *_Nullable error) {
                                                                       
                                                                       if (authState) {
                                                                           
                                                                           [GTMAppAuthFetcherAuthorization
                                                                            saveAuthorization:(GTMAppAuthFetcherAuthorization *)authFromKeychain
                                                                                                           toKeychainForName:NEW_USR_TKN_KEYCHAIN_NAME];
                                                                       } else {
                                                                           // what goes here?
                                                                           
                                                                           // maybe one of these calls: ??
                                                                           [subscriber sendCompleted];

                                                                       }
                                                                   }];
                }
                else { // We are authorized (e.g. We have a valid token)
                    
                    // This call will refresh if required
                    [authFromKeychain.authState performActionWithFreshTokens:
                     ^(NSString * _Nullable accessToken, NSString * _Nullable idToken, NSError * _Nullable error) {
                         
                         if ( error ) {
                             // A token refresh failed
                             DDLogError(@"Google OAuth Token Refresh Error = \"%@\"",error.localizedDescription);
                         }
                         else {
                             // we have a valid token
                             
                             // If we received an access token, and it is not an em,pty string ..
                             if ( accessToken && ![accessToken isEqualToString:@""] ) {
                                 
                                 DDLogDebug(@"\tNew Access Token");
                                 
                                 [sharedService.user setOAuth:accessToken];
                                 sharedService.imapSession = [AppSettings imapSession:sharedService.user];
                                 sharedService.imapSession.dispatchQueue = sharedService.s_queue;
                                 
                                 dispatch_queue_t imapDispatchQueue = [ImapSync sharedServices:user].s_queue;
                                 DDAssert(imapDispatchQueue, @"IMAP Displatch Queue must exist!");
                                 dispatch_async(imapDispatchQueue, ^{
                                     
                                     DDLogDebug(@"\tdo IMAP Check operation with OAuth2 token:\"%@\"", [sharedService.user oAuth]);
                                     
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
                         }
                    }];
                }
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
                [sharedService.user.linkedAccount setConnected];    // calls down to runData
                [sharedService _checkForCachedActions];
                [sharedService _getImapFolderNamesAndUpdateLocal];
                
                DDLogInfo(@"IMAP host \"%@\" Password login complete.",sharedService.user.imapHostname);
                
                [subscriber sendCompleted];
            }
            
        }];
    });
}

-(void) _checkForCachedActions
{
    NSMutableArray* cachedActions = [CachedAction getActionsForAccount:self.user.accountNum];
    
    DDLogDebug(@"Doing %@ cached actions.",@(cachedActions.count));
    
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
            
            DDLogDebug(@"STARTED IMAP Session Fetch All Folders Operation");
            
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
    
    DDLogDebug(@"Check Folder Names for Updates, IMAP folder count = %lu",
              (unsigned long)imapFolders.count);
    
    int folderIndex = 0;
    
    NSMutableArray* newFolderNames = [[NSMutableArray alloc] initWithCapacity:imapFolders.count];
    
    for (MCOIMAPFolder* imapFolder in imapFolders) {
        
        BOOL imapFolderMatchesLocalFolder = [self _localFolderMatchesImapFolder:imapFolder];
        
        // If the IMAP Folder being checked was not found in the Local Folders
        // then it is a NEW folder and needs to be added.
        if ( imapFolderMatchesLocalFolder == FALSE ) {
            
            DDLogInfo(@"IMAP folder \"%@\" NOT found in local folders.",[imapFolder path]);
            
            NSString *dispName = [ImapSync displayNameForFolder:imapFolder usingSession:self.imapSession];
            
            DDAssert(dispName, @"Display Name must exist.");
            
            [newFolderNames addObject:dispName];
            
            [self addFolder:imapFolder withName:dispName toAccount:(NSUInteger)self.user.accountNum];
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
        [syncManager retrieveFolderPathFromFolderState:(NSInteger)localFolderIndex
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

#pragma mark - getImapMessagesInFolder local methods

// ONLY called when loadImapMessagesIntoDatabaseForFolder (nee runFolder) is passed a folder value of -1
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
        DDLogDebug(@"ALL Folder Not Synced, do it next");
        return allFolderNum;
    }

//    if (![[[SyncManager getSingleton] retrieveState:[self.user numFolderWithFolder:inboxFolderType()] accountNum:self.user.accountNum][@"fullsynced"] boolValue]) {
//        return [self.user numFolderWithFolder:inboxFolderType()];
//    }
    
    NSInteger inboxFolderNumber = [self _folderIndexForBaseFolderType:FolderTypeInbox];
    if ( [self _folderIsNotSynced:inboxFolderNumber] ){
        DDLogDebug(@"Inbox Folder Not Synced, do it next");
        return inboxFolderNumber;
    }
    
//    if (![[[SyncManager getSingleton] retrieveState:[self.user numFolderWithFolder:FolderTypeWith(FolderTypeFavoris, 0)] accountNum:self.user.accountNum][@"fullsynced"] boolValue]) {
//        if ([self.user numFolderWithFolder:FolderTypeWith(FolderTypeFavoris, 0)] != -1) {
//            return [self.user numFolderWithFolder:FolderTypeWith(FolderTypeFavoris, 0)];
//        }
//    }
        
    NSInteger favorisFolderNumber = [self _folderIndexForBaseFolderType:FolderTypeFavoris];
    if ( [self _folderIsNotSynced:favorisFolderNumber] ){
        DDLogDebug(@"Favoris Folder Not Synced, do next");
        return favorisFolderNumber;
    }
    
//    if (![[[SyncManager getSingleton] retrieveState:[self.user numFolderWithFolder:FolderTypeWith(FolderTypeSent, 0)] accountNum:self.user.accountNum][@"fullsynced"] boolValue]) {
//        return [self.user numFolderWithFolder:FolderTypeWith(FolderTypeSent, 0)];
//    }
    
    NSInteger sentFolderNumber = [self _folderIndexForBaseFolderType:FolderTypeSent];
    if ( [self _folderIsNotSynced:sentFolderNumber] ){
        DDLogDebug(@"Sent Folder Not Synced, do next");
        return sentFolderNumber;
    }
    
    // Return the first unsynced user folder
    NSArray* folders = [self.user allFoldersDisplayNames];
    for (int indexFolder = 0; indexFolder < folders.count; indexFolder++) {
        
        if ( [self _folderIsNotSynced:indexFolder] ) {
            DDLogDebug(@"User Folder %ld Not Synced, do next",(long)indexFolder);
            return indexFolder;
        }
    }
    
    DDLogWarn(@"Could not find next folder to sync, returning -1");
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
    DDLogInfo(@"*** ENTRY POINT ***");

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
    DDLogInfo(@"*** ENTRY POINT ***");

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
    DDLogInfo(@"ENTERED");
    
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
    
    DDLogInfo(@"ENTERED: (v1) Cache mail:%@ in Folder:%@",email.sender.displayName,@(currentFolder));
    
    if ([UidEntry hasUidEntrywithMsgId:email.msgID inAccount:self.user.accountNum]) {
        
        [email loadBody];
        
        if (![UidEntry hasUidEntrywithMsgId:email.msgID withFolder:currentFolder inAccount:self.user.accountNum]) {
            // already have this email in other folder than this one -> add folder in uid_entry
            
            UidEntry *uidEntry = [email uidEntryInFolder:currentFolder];
            if ( uidEntry ) {
                
                NSInvocationOperation* nextOp = [[NSInvocationOperation alloc] initWithTarget:[EmailProcessor getSingleton] selector:@selector(addToFolderWrapper:) object:uidEntry];
                
                nextOp.completionBlock = ^{
                    [subscriber sendNext:email];
                };
                
                [[EmailProcessor getSingleton].operationQueue addOperation:nextOp];
            }
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
            
            DDLogDebug(@"Fetching Rendered Text Body from IMAP Server.");
            
            if (plainTextBodyString) {
                plainTextBodyString = [plainTextBodyString stringByReplacingCharactersInRange:NSMakeRange(0, 1) withString:@""];
                
                email.body = plainTextBodyString;
            }
            else {
                email.body = @"";
            }
            
            [[self.imapSession htmlBodyRenderingOperationWithMessage:msg folder:folderPath] start:^(NSString* htmlString, NSError* error) {
                email.htmlBody = htmlString;
                
                DDLogDebug(@"START IMAP Session HTML Body Rendering Operation");
                
                // Save email body and attachments
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
    DDLogInfo(@"*** ENTRY POINT ***");

//    NSString* dispName = [ImapSync displayNameForFolder:folder usingSession:imapSession];
    
    // TODO: Where is adding folder to IMAP server???
    
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
    DDLogDebug(@"Folder Index = %@, Path = \"%@\"",@(folderIndex),folderPath);

    MCOIMAPFolderInfoOperation* folderOp = [self.imapSession folderInfoOperation:folderPath];
    
    [folderOp start:^(NSError* error, MCOIMAPFolderInfo* info) {
        
        DDLogDebug(@"BEGAN IMAP Folder Get Info Operation on %@",folderPath);
        
        if (error) {
            DDLogError(@"IMAP Folder Get Info Operation Error = %@",error);
        } else {
            
            DDLogDebug(@"Got Folder Sync State from folder %ld for IMAP folder \"%@\"",(long)folderIndex,folderPath);
            
            int msgCount = [info messageCount];
            
            [self _writeFolderStateMessageCount:msgCount andFolder:folderIndex];
            
        }
    }];
}


// MARK: - IMAP Sync Services: Update all folders and mail from the IMAP Server (nee runFolder)

// "folder" is a Folder Index, or -1
// (nee runFolder)
-(RACSignal*) loadImapMessagesIntoDatabaseForFolder:(NSInteger)folder fromStart:(BOOL)isFromStart gettingAll:(BOOL)gettingAll
{
    DDLogInfo(@"*** ENTRY POINT ***");

    DDLogInfo(@"folder=%@ fromStart=%@ getAll=%@",
              @(folder),
              (isFromStart==TRUE?@"TRUE":@"FALSE"),
              (gettingAll==TRUE?@"TRUE":@"FALSE"));

    
    if (folder == -1) {
        DDLogDebug(@"folderIndex = -1, so getting next folder to sync.");
        folder = [self _nextFolderToSync];
        DDLogInfo(@"[self _nextFolderToSync] returned folder number %@",@(folder));
    }
    DDLogDebug(@"folderIndex = %@",@(folder));
    
    NSInteger currentFolder = folder;
    
    if (!self.cachedData) {
        self.cachedData = [[NSMutableArray alloc]initWithCapacity:1];
    }
    
    @weakify(self);
    
    return [RACSignal startLazilyWithScheduler:[RACScheduler schedulerWithPriority:RACSchedulerPriorityBackground]
                                         block:^(id<RACSubscriber> subscriber) {
        
        @strongify(self);
        
        DDLogDebug(@"BEGIN BLOCK - RACSchedulerPriorityBackground - Get List of All IMAP Folders");
        
        // get list of all folders from the IMAP Server
        
        if (self.isCanceled) {
            DDLogDebug(@"IMAP Sync Service CANCELLED, runFolder COMPLETED");
            
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
        else if ([ImapSync isRunningInBackground] && currentFolder != [self.user inboxFolderNumber]) {
            
            DDLogInfo(@"Running in Background && folder is not Inbox folder. We are completed.");

            [subscriber sendCompleted];
        }
        else {
            // if running in background, we only execute this for an INBOX
            
            [self _logIntoImapServer:subscriber currentFolder:currentFolder isFromStart:isFromStart getAll:gettingAll];
        }
    }];
}

// MARK: Local methods for runFolder:

- (void)_logIntoImapServer:(id<RACSubscriber>)subscriber currentFolder:(NSInteger)currentFolder isFromStart:(BOOL)isFromStart getAll:(BOOL)getAll
{
    DDLogDebug(@"IMAP Server=\"%@\"",self.user.imapHostname);
    
    [[ImapSync doLogin:self.user] subscribeError:^(NSError *error) {
        DDLogError(@"Login attempt failed. Send ERROR CCMConnectionError to subscriber");
        [subscriber sendError:error];
    } completed:^{
        DDLogDebug(@"COMPLETED doLogin:\"%@\"", self.user.imapHostname );
        
        if (!self.connected) {
            DDLogDebug(@"NOT Connected.");
            
            if ( [ImapSync isRunningInBackground] ) {
                DDLogDebug(@"NOT CONNECTED in BACKGROUND, so send COMPLETED to subscriber");
                
                [subscriber sendCompleted];
            }
            else {
                DDLogError(@"NOT in BACKGROUND. Send ERROR CCMConnectionError to subscriber");
                
                [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMConnectionError userInfo:nil]];
            }
        }
        else { // we are connected
            DDLogInfo(@"Login to IMAP server \"%@\" successful, retrieve IMAP folders.",self.user.imapHostname);
            
            [self _getImapFolders:subscriber currentFolder:currentFolder isFromStart:isFromStart getAll:getAll];
        }
    }];
}

- (void)_getImapFolders:(id)subscriber currentFolder:(NSInteger)currentFolder isFromStart:(BOOL)isFromStart getAll:(BOOL)getAll
{
    DDLogDebug(@"currentFolder=%@ fromStart=%@ getAll=%@",
              @(currentFolder),
              (isFromStart?@"TRUE":@"FALSE"),
              (getAll?@"TRUE":@"FALSE"));
    
    DDAssert(self.s_queue, @"s_queue must be set");

    MCOIMAPFetchFoldersOperation* fio = [self.imapSession fetchAllFoldersOperation];
    dispatch_async(self.s_queue, ^{
        
        DDLogDebug(@"BEGIN Fetch All IMAP Folders Operation");
        
        [fio start:^(NSError* error, NSArray<MCOIMAPFolder*>* imapFolders) {
            
            if (error) {
                DDLogError(@"Fetch All IMAP Folders Failed, error = %@.",error.description);
                
                self.connected = NO;
                
                [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMConnectionError userInfo:nil]];
                
                return;
            }
            
            if (!imapFolders || imapFolders.count == 0) {
                
                DDLogInfo(@"Fetch All IMAP Folders Success, but NO Folders.");
                [subscriber sendCompleted];
                
                return;
            }
            
            DDLogInfo(@"IMAP server \"%@\" has %@ folders.",self.user.imapHostname,@(imapFolders.count));
            
            [self _processFoldersAndGetImapMessages:subscriber currentFolder:currentFolder isFromStart:isFromStart getAll:getAll imapFolders:imapFolders];
            
        }];//Fetch All Folders
    });
}



- (void)_processFoldersAndGetImapMessages:(id)subscriber currentFolder:(NSInteger)currentFolder isFromStart:(BOOL)isFromStart getAll:(BOOL)getAll imapFolders:(NSArray<MCOIMAPFolder*>*)imapFolders
{
    DDLogInfo(@"currentFolder=%@ fromStart=%@ getAll=%@",
              @(currentFolder),
              (isFromStart?@"TRUE":@"FALSE"),
              (getAll?@"TRUE":@"FALSE"));
    
    DDAssert(self.s_queue, @"s_queue must be set");
    
    dispatch_async(self.s_queue, ^{
        
        BOOL aFolderWasDeleted = [self _checkLocalFoldersForDeletionOnIMAPServer:imapFolders];
        
        if ( aFolderWasDeleted ) {
            
            DDLogInfo(@"IMAP server \"%@\" has at least one deleted folder.", self.user.imapHostname);

            [self _replaceDeletedImportantFolders:currentFolder imapFolders:imapFolders];
        }
        
        [self _getImapMessages:currentFolder subscriber:subscriber isFromStart:isFromStart getAll:getAll];
        
        [subscriber sendCompleted];
    });
}

- (BOOL)_checkLocalFoldersForDeletionOnIMAPServer:(NSArray<MCOIMAPFolder*>*)imapFolders
{
    DDLogDebug(@"MCOIMAPFolder count = %@",@(imapFolders.count));
    
    SyncManager* syncMgr = [SyncManager getSingleton];
    
    // mark folders that were deleted on the server as deleted on the client
    NSInteger localFolderIndex = 0;
    NSInteger localFolderCount = (NSInteger)[syncMgr folderCount:self.user.accountNum];
    
    DDLogDebug(@"We have %@ local folders.",@(localFolderCount));
    
    NSUInteger deletedFolderCount = 0;
    
    // Check each local folder, and if it is not found on the IMAP server,
    // then mark it deleted on locally.
    while (localFolderIndex < localFolderCount) {
        
        NSString* localFolderPath =
        [syncMgr retrieveFolderPathFromFolderState:localFolderIndex
                                        accountNum:self.user.accountNum];
        
        BOOL folderIsDeletedLocally =
        [syncMgr isFolderDeletedLocally:localFolderIndex accountNum:self.user.accountNum];
        
        // If the local folder is marked as deleted ...
        if ( folderIsDeletedLocally ) {
            DDLogDebug(@"Local Folder %@: \"%@\" is (already) marked deleted locally.",@(localFolderIndex),localFolderPath);
            deletedFolderCount++;
        }
        else { // folder is not deleted locally
//            DDLogInfo(@"Local Folder %@: \"%@\" is NOT marked deleted locally.",@(localFolderIndex),localFolderPath);

//            BOOL folderDeletedOnImapServer ? ![imapFolders containsObject:localFolderPath];  // is imapFolders = [folders valueForKey @"path"]?
            BOOL folderDeletedOnImapServer = ![self _folderPath:localFolderPath isFoundInIMAPFolders:imapFolders];
            
            // If the local folder is deleted on the server ...
            if ( folderDeletedOnImapServer ) {
                DDLogDebug(@"Local Folder %@: \"%@\" is not found on the IMAP Server (i.e. its been deleted), so mark local folder as deleted.",@(localFolderIndex),localFolderPath);
                
                [syncMgr markFolderDeleted:localFolderIndex accountNum:self.user.accountNum];
                localFolderIndex = 0;
                deletedFolderCount++;
            }
//            else {
//                DDLogDebug(@"\t\tIMAP Folder matching local folder exists, no work required.");
//            }
        }
        
        localFolderIndex++;
    }
    
    DDLogInfo(@">>> %@ folders were deleted.",@(deletedFolderCount));
    
    return (deletedFolderCount > 0);
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
    
    DDLogDebug(@"Current Folder = %@, MCOIMAPFolder count = %@",@(currentFolder),@(imapFolders.count));
    
    // If the Current Folder is one of the deleted folders, and it is an Important
    // folder, then try to find a replacement folder.
    
    BOOL currentFolderIsDeletedLocally =
    [syncMgr isFolderDeletedLocally:currentFolder accountNum:self.user.accountNum];
    
    if ( currentFolderIsDeletedLocally ) {
        
        DDLogWarn(@"Current Folder %@ is deleted locally",@(currentFolder));
        
        CCMFolderType folderHandle = [self.user typeOfFolder:currentFolder];
        
        BOOL currentFolderIsAnImportantFolder = (folderHandle.type != FolderTypeUser);
        
        if ( currentFolderIsAnImportantFolder ) {
            
            DDLogDebug(@"\tThis an Important Folder, so earch for a match (replacement) IMAP folder.");
            
            MCOMailProvider* accountProvider = [[MCOMailProvidersManager sharedManager] providerForIdentifier:self.user.identifier];
            
            // For each IMAP Folder
            for (MCOIMAPFolder* imapFolder in imapFolders) {
                
                DDLogDebug(@"Next IMAP Folder \"%@\" from array of all IMAP folders.", imapFolder.path);
                
                if (imapFolder.flags & MCOIMAPFolderFlagNoSelect) {
                    DDLogDebug(@"\thas NO Flags");
                    continue;
                }
                
                NSString *imapFolderName = [ImapSync displayNameForFolder:imapFolder usingSession:self.imapSession];
                
                if ( ![imapFolderName isEqualToString:imapFolder.path] ) {
                    DDLogDebug(@"IMAP Folder Path = \"%@\", IMAP Folder Name = \"%@\"",imapFolder.path,imapFolderName);
                }
                
                NSString* importantImapFolderPath = @"";
                
                switch ( folderHandle.type ) {
                    case FolderTypeInbox:
                        if ( (imapFolder.flags == MCOIMAPFolderFlagInbox) || [imapFolderName  isEqualToString: @"INBOX"] ) {
                            importantImapFolderPath = imapFolderName;
                            DDLogDebug(@"\tIs the INBOX folder.");
                        }
                        break;
                    case FolderTypeFavoris:
                        if ( ([accountProvider.starredFolderPath isEqualToString:imapFolderName] || (imapFolder.flags == MCOIMAPFolderFlagFlagged)) ) {
                            importantImapFolderPath = imapFolderName;
                            DDLogDebug(@"\tIs the FLAGGED folder.");
                        }
                        break;
                    case FolderTypeSent:
                        if ( ([accountProvider.sentMailFolderPath isEqualToString:imapFolderName] || (imapFolder.flags == MCOIMAPFolderFlagSentMail)) ) {
                            importantImapFolderPath = imapFolderName;
                            DDLogDebug(@"\tIs the SENT folder.");
                        }
                        break;
                    case FolderTypeDrafts:
                        if ( ([accountProvider.draftsFolderPath isEqualToString:imapFolderName] || (imapFolder.flags == MCOIMAPFolderFlagDrafts)) ) {
                            importantImapFolderPath = imapFolderName;
                            DDLogDebug(@"\tIs the DRAFTS folder.");
                        }
                        break;
                    case FolderTypeAll:
                        if ( ([accountProvider.allMailFolderPath isEqualToString:imapFolderName] || ((imapFolder.flags == MCOIMAPFolderFlagAll) || (imapFolder.flags == MCOIMAPFolderFlagAllMail))) ) {
                            importantImapFolderPath = imapFolderName;
                            DDLogDebug(@"\tIs the ARCHIVE folder.");
                        }
                        break;
                    case FolderTypeDeleted:
                        if ( ([accountProvider.trashFolderPath isEqualToString:imapFolderName] || (imapFolder.flags == MCOIMAPFolderFlagTrash)) ) {
                            importantImapFolderPath = imapFolderName;
                            DDLogDebug(@"\tIs the TRASH folder.");
                        }
                        break;
                    case FolderTypeSpam:
                        if ( ([accountProvider.spamFolderPath isEqualToString:imapFolderName] || (imapFolder.flags == MCOIMAPFolderFlagSpam)) ) {
                            importantImapFolderPath = imapFolderName;
                            DDLogDebug(@"\tIs the SPAM folder.");
                        }
                        break;
                    default:
                        DDLogError(@"/tIs UNKNOWN Important folder type (%@).",@(folderHandle.type));
                        break;
                }
                
                BOOL thisImapFolderIsImportant = ![importantImapFolderPath isEqualToString:@""];
                
                if ( thisImapFolderIsImportant ) {
                    
                    DDLogDebug(@"\tImportant Folder Path = \"%@\"", importantImapFolderPath);
                    
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
                            
                            [self.user setImportantFolderNum:(NSInteger)localFolderIndex forBaseFolder:folderHandle.type];
                            
                            
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
    
    DDLogInfo(@"folder num = %@",@(currentFolder));
    
    NSInteger acntNumber = self.user.accountNum;
    
    NSString* folderPath =
    [syncMgr retrieveFolderPathFromFolderState:currentFolder accountNum:acntNumber];
    
    if ( folderPath == nil ) {
        DDLogError(@"Unable to retrieve folder path for folder=%@ and account=%@",
                   @(currentFolder),@(acntNumber));
        NSError *folderPathError = [NSError errorWithDomain:CCMErrorDomain code:CCMFolderPathError userInfo:nil];
        [subscriber sendError:folderPathError];
        return;
    }
    
    NSInteger lastEnded = [syncMgr retrieveLastEndedFromFolderState:currentFolder accountNum:acntNumber];
    
    if ( lastEnded == -1 )  {
        DDLogError(@"Unable to retrieve last ended for folder=%@ and account=%@",
                   @(currentFolder),@(acntNumber));
        NSError *syncManagerError = [NSError errorWithDomain:CCMErrorDomain code:CCMSyncMgrError userInfo:nil];
        [subscriber sendError:syncManagerError];
        return;
    }
    
    if ( lastEnded < 0 ) {
        DDLogError(@"lastEnded (%@) should be a positive integer, setting to 1.",@(lastEnded));
        lastEnded = 1;
        [syncMgr updateLastEndedIndex:lastEnded forFolderNumber:currentFolder andAccountNum:acntNumber];
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
        
        DDLogInfo(@"IMAP Server \"%@\" folder \"%@\" has %@ mail messages.",
                  self.user.imapHostname, folderPath, @(imapFolderInfo.messageCount));
        
        [self _fetchImapMessages:subscriber
                   currentFolder:currentFolder
                     isFromStart:isFromStart
                          getAll:getAll
                      folderPath:folderPath
                    messageCount:imapFolderInfo.messageCount
                       lastEnded:lastEnded];
        
        [subscriber sendCompleted];
    }];
}

- (void)_fetchImapMessages:(id)subscriber currentFolder:(NSInteger)currentFolder isFromStart:(BOOL)isFromStart getAll:(BOOL)getAll folderPath:(NSString *)folderPath messageCount:(NSInteger)msgCount lastEnded:(NSInteger)lastEnded
{
    DDLogDebug(@"currFolder=%@ isFromStart=%@ getAll=%@ path = \"%@\" msgCount=%@ lastEnded=%@",
              @(currentFolder),(isFromStart?@"TRUE":@"FALSE"),(getAll?@"TRUE":@"FALSE"),folderPath,@(msgCount),@(lastEnded));
    
    DDAssert(self.s_queue, @"s_queue must be set");

    dispatch_async(self.s_queue, ^{
        
        int batchsize = 50;
        
        if ( [ImapSync isRunningInForeground] ) {
            
            DDLogInfo(@"IMAP server \"%@\" folder \"%@\", save msg count (%@) to FolderStates.",
                      self.user.imapHostname, folderPath, @(msgCount) );
            
            // Save the folder mail count to local memory
            [self _writeFolderStateMessageCount:msgCount andFolder:currentFolder];
            
            
//            if ( msgCount == 0 ) {
//                DDLogInfo(@"Message count is Zero");
//                [self _writeFolderStateLastEnded:1 andFolder:currentFolder];
//            }
//            else if ( lastEnded == 1 && !isFromStart ) {
//
//                [self _writeFolderStateLastEnded:0 andFolder:currentFolder];
//            }
//            else {
//                [self _writeFolderStateLastEnded:lastEnded andFolder:currentFolder];
//
//            }
            
            // TODO: Check this against original code - is msgCount == 0 really an error?
            
            // If (the folder contains NO messages), OR
            // (we are NOT loading folder messages from Index
            //   Zero AND the last loaded message was Index One)
            if (msgCount == 0 || (!isFromStart && (lastEnded == 1))) {
                
                DDLogDebug(@"No Messages OR (Not from Start AND Last Ended == 1");
                
                NSInteger lastEndedIndex = 0;
                if ( msgCount == 0 ) {
                    lastEndedIndex = 1;
                }
                else {
                    lastEndedIndex = lastEnded;
                }
                
                DDLogInfo(@"IMAP server \"%@\" folder \"%@\", save Last Ended index (%@) to FolderStates.",
                          self.user.imapHostname, folderPath, @(lastEndedIndex) );

                [self _writeFolderStateLastEnded:lastEndedIndex andFolder:currentFolder];
                
                [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMFolderSyncedError userInfo:nil]];
                return;
            }
        }
        
        NSInteger from = msgCount;
        
        if ( !isFromStart && [ImapSync isRunningInForeground] && lastEnded != 0) {
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
        
        [imapMessagesFetchOp start:^(NSError* error, NSArray<MCOIMAPMessage*>* imapMessages, MCOIndexSet* vanishedMessages) {
            
            if (error) {
                DDLogInfo(@"Error %@ fetching messages.  Send CCMConnectionError to subscriber.",error.description);
                
                self.connected = NO;
                [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMConnectionError userInfo:nil]];
                
                return;
            }
            
            DDLogInfo(@"IMAP server \"%@\" folder \"%@\", Loaded %@ IMAP messages.",
                      self.user.imapHostname, folderPath, @(imapMessages.count) );
            
            if ( imapMessages.count > 0 ) {
                [self _processImapMessages:imapMessages subscriber:(id)subscriber currentFolder:currentFolder from:from isFromStart:isFromStart getAll:getAll];
            }
            
        }];//Fetch Messages
    });
    
}


- (void)_processImapMessages:(NSArray<MCOIMAPMessage*>*)imapMessages subscriber:(id)subscriber currentFolder:(NSInteger)currentFolder from:(NSInteger)from isFromStart:(BOOL)isFromStart getAll:(BOOL)getAll
{
    DDLogVerbose(@"ENTERED, num IMAP msgs = %@",@(imapMessages.count));
    
    DDAssert(self.s_queue, @"s_queue must be set");
    
    dispatch_async(self.s_queue, ^{
        
        SyncManager *syncMgr = [SyncManager getSingleton];
        
        NSString* folderPath = [syncMgr retrieveFolderPathFromFolderState:currentFolder accountNum:self.user.accountNum];
        
        if ( folderPath == nil ) {
            DDLogError(@"Could not get Folder Path from Sync Manager for folder=%@ in account=%@",@(currentFolder),@(self.user.accountNum));
            [subscriber sendError:[NSError errorWithDomain:CCMErrorDomain code:CCMFolderPathError userInfo:nil]];
            return;
        }
        
        // Message ID of the last mail message returned by the IMAP server
        NSString* lastMsgID = [imapMessages lastObject].header.messageID;
        
        for (MCOIMAPMessage* imapMsg in imapMessages) {
            
            if (self.isCanceled) {
                DDLogInfo(@"isCancelled == TRUE, so sending Completed to subscriber");
                [subscriber sendCompleted];
                return;
            }
            
            Mail* email = [Mail mailWithMCOIMAPMessage:imapMsg inFolder:currentFolder andAccount:self.user.accountNum];
            
            DDLogVerbose(@"\nEMAIL Subj: \"%@\" | MsgId:  \"%@\" | AcntNum: %@ | FolderNum: %@",
                      email.subject,email.msgID,@(self.user.accountNum),@(currentFolder));
            
            if ([UidEntry hasUidEntrywithMsgId:email.msgID inAccount:self.user.accountNum]) {
                
                DDLogVerbose(@"--- Message already exists in this Account's Databsase");
                
                if (![UidEntry hasUidEntrywithMsgId:email.msgID withFolder:currentFolder inAccount:self.user.accountNum]) {
                    
                    // already have this email in other folder than this one -> add folder in uid_entry
                    
                    DDLogVerbose(@"--- Message DOES NOT already exist in this Account's Database in Folder \"%@\", ADDING.",@(currentFolder));
                    
                    UidEntry *uidEntry = [email uidEntryInFolder:currentFolder];
                    if ( uidEntry ) {
                        
                        NSInvocationOperation* nextOp = [[NSInvocationOperation alloc] initWithTarget:[EmailProcessor getSingleton] selector:@selector(addToFolderWrapper:) object:uidEntry];
                        
                        nextOp.completionBlock = ^{
                            if ((currentFolder == [Accounts sharedInstance].currentAccount.currentFolderIdx) | getAll) {
                                [email loadBody];
                                [subscriber sendNext:email];
                            }
                        };
                        
                        [[EmailProcessor getSingleton].operationQueue addOperation:nextOp];
                    }
                }
                else {
                    DDLogDebug(@"--- Message already exists in this Account's Database in Folder \"%@\"",@(currentFolder));
                    
                }
                
                if ([email.msgID isEqualToString:lastMsgID]) {
                    if (!isFromStart && [ImapSync isRunningInForeground]) {
                        [self _writeFolderStateLastEnded:from andFolder:currentFolder];
                    }
                }
                
                //We already have this email in this folder
                continue;
            }
            else {
                DDLogVerbose(@"--- Message DOES NOT already exist in this Account's Databsase");
            }
            
            
            [[self.imapSession
              plainTextBodyRenderingOperationWithMessage:imapMsg folder:folderPath stripWhitespace:NO] start:^(NSString* plainTextBodyString, NSError* error) {
                
                DDLogVerbose(@"Loading Email from IMAP Server into Database");
                
                if (plainTextBodyString) {
                    plainTextBodyString = [plainTextBodyString stringByReplacingCharactersInRange:NSMakeRange(0, 1) withString:@""];
                    
                    email.body = plainTextBodyString;
                }
                else {
                    email.body = @"";
                }
                
                NSDate* currentDateAndTime = [NSDate date];
                NSDate* oneMonthBeforeCurrentDateAndTime = [currentDateAndTime dateByAddingTimeInterval:- ONE_MONTH_IN_SECONDS];
                
                // TODO: A better date range might be (last date in inbox - first date in inbox)
                
                // If the email message is older than one month ....
                if ([email.datetime compare:oneMonthBeforeCurrentDateAndTime] == NSOrderedAscending) {
                    
                    [self _saveEmailToDatabase:currentFolder email:email from:from getAll:getAll isFromStart:isFromStart lastMsgID:lastMsgID subscriber:subscriber];
                }
                else { // the email message is not older than one month, render its HTML body now (kinda klugey, huh?)
                    
                    [[self.imapSession htmlBodyRenderingOperationWithMessage:imapMsg folder:folderPath] start:^(NSString* htmlString, NSError* error) {
                        
                        email.htmlBody = htmlString;
                        
                        [self _saveEmailToDatabase:currentFolder email:email from:from getAll:getAll isFromStart:isFromStart lastMsgID:lastMsgID subscriber:subscriber];
                    }];
                }
            }];
        }
    });
    
}

- (void)_saveEmailToDatabase:(NSInteger)currentFolder email:(Mail *)email from:(NSInteger)from getAll:(BOOL)getAll isFromStart:(BOOL)isFromStart lastMsgID:(NSString *)lastMsgID subscriber:(id)subscriber {
    
    BOOL isCached = [self _cacheOrSaveEmail:email toFolder:currentFolder];
    
    if ((currentFolder == [Accounts sharedInstance].currentAccount.currentFolderIdx) | getAll) {
        if ( [ImapSync isRunningInBackground] ) {
            if (isCached) {
                [subscriber sendNext:email];
            }
        }
        else {
            [subscriber sendNext:email];
        }
    }
    
    // if this is the last email in the folder ...
    if ([email.msgID isEqualToString:lastMsgID]) {
        
        // If isFromStart==NO adn we are running in the foreground ...
        if ( !isFromStart && [ImapSync isRunningInForeground] ) {
            // Save the FolderState's Last Ended value to the Sync Manager and its backup file
            [self _writeFolderStateLastEnded:from andFolder:currentFolder];
        }
        
        // Notify the subscriber that there are no more emails.
        [subscriber sendCompleted];
    }
}

-(BOOL) _cacheOrSaveEmail:(Mail*)email toFolder:(NSInteger)currentFolder
{
    DDLogInfo(@"ENTERED: (v2) Cache mail: \"%@\" in Folder %@",email.sender.displayName,@(currentFolder));

    //Cache email if in Background
    if ( [ImapSync isRunningInBackground] ) {
        
        DDLogVerbose(@"Running in the Background, so Cache Email.");
        return [self _cacheEmail:currentFolder email:email];    // return YES if email cached
    }
    
    // Save the email
    DDLogVerbose(@"NOT Running in the background, so save mail in database.");
    
    // Save email body and attachments
    NSInvocationOperation* nextOp
    = [[NSInvocationOperation alloc] initWithTarget:[EmailProcessor getSingleton]
                                           selector:@selector(addEmailWrapper:)
                                             object:email];
    
    [[EmailProcessor getSingleton].operationQueue addOperation:nextOp];
    [[EmailProcessor getSingleton].operationQueue waitUntilAllOperationsAreFinished];
    
    return NO;
}

// Save a mail message when we are running in the background

- (BOOL)_cacheEmail:(NSInteger)currentFolder email:(Mail *)email
{
    DDLogInfo(@"ENTERED: (v3) Cache mail:%@ in Folder:%@",email.sender.displayName,@(currentFolder));
    
    BOOL emailCached = NO;  // for return
    
    BOOL isInInbox = (currentFolder == [self.user numFolderWithFolder:inboxFolderType()]);
    BOOL isUnread = !(email.flag & MCOMessageFlagSeen);
    
    // if the message is in the inbox and is undread ..
    if (isInInbox & isUnread) {
        
        NSMutableSet* eIds = [self _emailIDs];
        
        // if this mail message is not already in the cached messages set ...
        if (![eIds containsObject:email.msgID]) {
            
            // Add this mail message to the cache ...
            Mail* newE = [email copy];
            UidEntry *uid = email.uids[0];
            DDLogVerbose(@"Had Cached %@ Emails in account:%@", @(eIds.count), @(uid.accountNum));
            
            //[self.cachedData addObject:newE];
            [eIds addObject:newE.msgID];
            [AppSettings getSingleton].cache = [eIds allObjects];
            
            // Save email body and attachments to the database
            NSInvocationOperation* nextOp = [[NSInvocationOperation alloc] initWithTarget:[EmailProcessor getSingleton] selector:@selector(addEmailWrapper:) object:email];
            [[EmailProcessor getSingleton].operationQueue addOperation:nextOp];
            [[EmailProcessor getSingleton].operationQueue waitUntilAllOperationsAreFinished];
            
            Conversation* conv = [[Conversation alloc] init];
            [conv addMail:email];
            
            ConversationIndex* index = [ConversationIndex initWithIndex:[email.user.linkedAccount addConversation:conv] user:email.user]; ;
            
            // if the message is unread and this account allows notifications ...
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
        
        NSString *dateText = [NSDateFormatter localizedStringFromDate:[NSDate date]
                                                            dateStyle:NSDateFormatterShortStyle
                                                            timeStyle:NSDateFormatterShortStyle];
        
        UNUserNotificationCenter *center = [UNUserNotificationCenter currentNotificationCenter];
        DDAssert(center, @"The UNUserNotificationCenter must exist");
        
        [center getNotificationSettingsWithCompletionHandler:^(UNNotificationSettings * _Nonnull settings) {
            
            if ( settings.authorizationStatus == UNAuthorizationStatusAuthorized ) {
                DDLogInfo(@"The User has Authorized Notifications");
                
                UNMutableNotificationContent* content = [[UNMutableNotificationContent alloc] init];
                
                if ( settings.alertSetting == UNNotificationSettingEnabled ) {
                    
                    DDLogInfo(@"Notification Alerts are Enabled.");
                    
                    content.title = email.sender.displayName;
                    content.subtitle = dateText;
                    content.body  = alertText;
                    
                    // group notifications by mail host
                    content.threadIdentifier = self.imapSession.hostname;
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
                    
                    NSNumber *unreadMailCount = [[NSNumber alloc] initWithInteger:[UIApplication sharedApplication].applicationIconBadgeNumber];   // is this necessary?  Doesn't setting this App Property update the badge?
                    content.badge = unreadMailCount;
                }
                else {
                    DDLogInfo(@"Notification Badge is NOT Enabled.");
                }
                
                content.categoryIdentifier = CCMCategoryIdentifier;
                content.userInfo = @{ @"cIndexIndex"      : @(index.index),
                                      @"cIndexAccountNum" : @(index.user.accountNum) };
                
                UNTimeIntervalNotificationTrigger *trigger = [UNTimeIntervalNotificationTrigger triggerWithTimeInterval:5 repeats:FALSE];   // allow 5 seconds between notifications
                
                UNNotificationRequest *notificationRequest = [UNNotificationRequest requestWithIdentifier:email.msgID
                                                                                                  content:content
                                                                                                  trigger:trigger];
                
                [center addNotificationRequest:notificationRequest
                         withCompletionHandler:^(NSError * _Nullable error) {
                             if ( error ) {
                                 // Report Error
                                 DDLogError(@"Failed to add UNNotificationRequest, error = %@",error);
                             } else {
                                 DDLogInfo(@"Added UNNotifidationRequest.");
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
        localNotification.category = CCMCategoryIdentifier;
        
        DDLogDebug(@"Index: %ld",(long)index.index);
        DDLogDebug(@"Conversation: %@",[conv firstMail].subject);
        
        // Call UIApplication on the main thread
        dispatch_async(dispatch_get_main_queue(), ^{
            [[UIApplication sharedApplication] presentLocalNotificationNow:localNotification];
        });
    }
    
}

-(NSMutableSet *) _emailIDs
{
    return [NSMutableSet setWithArray:[[AppSettings getSingleton] cache]];
}

-(void) _writeFolderStateMessageCount:(NSInteger)messageCount andFolder:(NSInteger)folderNum
{
    if ( self.user.isDeleted ) {
        DDLogInfo(@"User is Deleted, don't write folder message count.");
        return;
    }
    
    SyncManager *sm = [SyncManager getSingleton];
    [sm updateMessageCount:messageCount forFolderNumber:folderNum andAccountNum:self.user.accountNum];
}

-(void) _writeFolderStateLastEnded:(NSInteger)lastEIndex andFolder:(NSInteger)folderNum
{
    if ( self.user.isDeleted ) {
        DDLogInfo(@"User is Deleted, don't write folder state last ended.");
        return;
    }
    
    SyncManager *sm = [SyncManager getSingleton];
    [sm updateLastEndedIndex:lastEIndex forFolderNumber:folderNum andAccountNum:self.user.accountNum];
}


// MARK: - IMAP Sync Server - Supporting Methods

// All mail in the first argument MINUS all emails in the second argument,
// results in all local mails not on the server (i.e. deleted)

- (MCOIndexSet*) _localFolderMailMessages:(MCOIndexSet *)indeciesOfAllMailMessagesInFolder
                   noLongerOnImapServer:(NSArray<MCOIMAPMessage*>*)imapMessages
{
    DDLogInfo(@"Local Folder Mail Index Count = %@",@(indeciesOfAllMailMessagesInFolder.count));
    DDLogInfo(@"IMAP Folder Mail Count = %@",@(imapMessages.count));
    
    MCOIndexSet* indeciesOfLocalMailNotFoundInIMAPMail = [indeciesOfAllMailMessagesInFolder copy];
    
    for (MCOIMAPMessage* imapMsg in imapMessages) {
        
        DDAssert(imapMsg.uid, @"Message UID must exist.");
        
        // If the IMAP message is found in the local folder
        if ( [indeciesOfLocalMailNotFoundInIMAPMail containsIndex:imapMsg.uid] ) {
            
            // then remove that message from the indecies set
            [indeciesOfLocalMailNotFoundInIMAPMail removeIndex:imapMsg.uid];
        }
    }
    
    DDLogInfo(@"Returing: Local Folder Mail NOT FOUND in IMAP Folder Mail: %@",@(indeciesOfLocalMailNotFoundInIMAPMail.count));
    
    // Returns only those Local mail messages not found in the IMAP messages (i.e. they are removed or updated)
    return indeciesOfLocalMailNotFoundInIMAPMail;
}

- (NSMutableArray<Mail *>*) _mailMessages:(NSArray<Mail*>*)localMessages
                                 inFolder:(NSInteger)folderIndex
             notFoundInImapFolderMessages:(NSArray<MCOIMAPMessage*>*)imapMessages
{
    DDLogInfo(@"Local Folder Mail Index Count = %@",@(localMessages.count));
    DDLogInfo(@"IMAP Folder Mail Count = %@",@(imapMessages.count));
    
    NSMutableArray<Mail*>* deletedMessages = [[NSMutableArray alloc] init];
    
    for (Mail *localMsg in localMessages) {
        
        UidEntry *uidEntry = [localMsg uidEntryInFolder:folderIndex];
        if ( uidEntry ) {
            
            BOOL matchingIMAPMessage = NO;
            for (MCOIMAPMessage* imapMsg in imapMessages) {
                
                // If there universal ID numbers match ...
                if ( uidEntry.uid == imapMsg.uid ) {
                    
                    // the local mail message is also on the IMAP server, so not deleted
                    
                    matchingIMAPMessage = YES;
                    break;   // on to testing the next local message
                }
            }
            
            if ( matchingIMAPMessage == NO ) {
                [deletedMessages addObject:localMsg];
            }
        }
    }
    return deletedMessages;
}

- (NSMutableArray<Mail*>*) _mailMessages:(NSArray<Mail *> *)mailMessages
                              inFolder:(NSInteger)folderIdx
          withMessagesWithChangedFlags:(NSArray *)imapMessages
{
    NSMutableArray<Mail*>* updatedMails = [NSMutableArray array];
    
    for (Mail* mailMsg in mailMessages) {
        
        // get the UID of the message in the folder
        UidEntry* mailMsgUID = [mailMsg uidEntryInFolder:folderIdx];
        if ( mailMsgUID ) {
            
            // For every fetched IMAP message
            for (MCOIMAPMessage* imapMsg in imapMessages) {
                
                // if the Imap Messaage and the Local Message have the same UID but different FLAG
                if (imapMsg.uid == mailMsgUID.uid && imapMsg.flags != mailMsg.flag) {
                    // then update the local message flag
                    mailMsg.flag = imapMsg.flags;
                    
                    // and add the local message to the list of update mail messages
                    [updatedMails addObject:mailMsg];
                }
            }
        }
    }
    return updatedMails;
}


// MARK: - IMAP Sync Server: Update/Delete a Local Folder's emails from the IMAP Server.  Does not Add.

// Fetch IMAP Mail Message *Headers* and *Flags* ONLY, and determine which Local Memory mail messages (in the given folder)
// have been deleted or updated.  Call the completion handler with a list of the Days with updated or deleted messages.

// nee runUpToDateTest

// TODO: Why not do "Added" messages at the same time?

-(void) updateLocalMailFromImapServerInConversations:(NSArray<Conversation*>*)conversationsInFolder ofFolder:(NSInteger)folderIdx completed:(void (^)(NSArray<NSString*>* days))completedBlock
{
    DDLogInfo(@"*** ENTRY POINT ***");
    
    // NB: This does NOT add New Mails to the conversations, it only updates mail with changed flags, or removes deleted entries.

    NSString* path = [self.user folderServerName:folderIdx];
    
    DDAssert( path && path.length , @"Folder Path must exist.");
    
    DDLogInfo(@"Local Mail Folder \"%@\" (%@) has %@ conversations.", path, @(folderIdx), @(conversationsInFolder.count) );
    
    
    MCOIndexSet* indeciesOfAllMailMessagesInLocalFolder = [MCOIndexSet indexSet];  // array of index , each a Unsigned Integer
    NSMutableArray<Mail*>* allMailMessagesInLocalFolder = [NSMutableArray arrayWithCapacity:conversationsInFolder.count]; // mimimum size
    
    // Create the indecies of all mail messages in all the conversations in a folder.
    // ALso Create an array of Mail of all the mail messages in the conversations in a folder.
    
    // For each conversation in the folder
    for (Conversation* conv in conversationsInFolder) {

        // For each mail message in this conversation ...
        for (Mail* mail in conv.mails) {

            // If this mail message contains at least one UID contained in the folder ..
            UidEntry *uidEntry = [mail uidEntryInFolder:folderIdx];

            // If the return value is not nil (ie. not an error)
            if ( uidEntry ) {
                // Add this UID to the IndexSet of all mail messages in the folder
                [indeciesOfAllMailMessagesInLocalFolder addIndex:uidEntry.uid];

                // Add this mail message to the Array of all mail messages in this folderr
                [allMailMessagesInLocalFolder addObject:mail];
            }
        }
    }
    
//    if ( allMailMessagesInLocalFolder.count < conversationsInFolder.count ) {
//        DDLogWarn(@"Why is number of messages (%@) less than numnber of conversations (%@)?",@(allMailMessagesInLocalFolder.count),@(conversationsInFolder.count));
//    }
    
    if (indeciesOfAllMailMessagesInLocalFolder.count == 0) {
        DDLogWarn(@"Local Folder \"%@\" has zero mail messages, nothing to update or delete, so returning.",path);
        completedBlock(nil);
        return;
    }
    
    DDLogInfo(@"Local Mail Folder \"%@\" (%@) has %@ messages and %@ indecies.", path, @(folderIdx), @(allMailMessagesInLocalFolder.count), @(indeciesOfAllMailMessagesInLocalFolder.count));
 
    DDLogInfo(@"CALLING doLogin:\"%@\"", self.user.imapHostname );

    // Login to the folder's IMAP server
    [[ImapSync doLogin:self.user] subscribeError:^(NSError *error) {
        
        switch (error.code) {
            case CCMConnectionError:
                DDLogError(@"login for user \"%@\" failed with Connection Error.",self.user.name);
                break;
                
            default:
                DDLogError(@"doLogin of user %@ failed with error= %@",self.user.imapHostname,error);
                break;
        }
        completedBlock(nil);
        
     } completed:^{
         DDLogInfo(@"COMPLETED doLogin:\"%@\"SUCCESSFULLY)", self.user.imapHostname );
         
         if (!self.connected){
             DDLogWarn(@"doLogin succeeded, but not connected, returning.");
             completedBlock(nil);
             return;
         }
         
         DDAssert(self.s_queue, @"s_queue must be set");
         
         // Get the headers and flags for all the messages in the folder
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wassign-enum"
         MCOIMAPMessagesRequestKind requestKind = MCOIMAPMessagesRequestKindHeaders | MCOIMAPMessagesRequestKindFlags;
#pragma clang diagnostic pop
         
         dispatch_async(self.s_queue, ^{
             
             MCOIMAPFetchMessagesOperation* op = [self.imapSession fetchMessagesOperationWithFolder:path
                                                                                        requestKind:requestKind
                                                                                               uids:indeciesOfAllMailMessagesInLocalFolder];
             
             [op start:^(NSError* error, NSArray* imapMessages, MCOIndexSet* vanishedMessages) {
                 
                 if (error) {
                     [self _setConnected:NO];
                     DDLogError(@"Fetching IMAP Messages at path \"%@\" failed, error=%@, returning.", path, error);
                     completedBlock(nil);
                     return;
                 }
                 
                 DDLogInfo(@"IMAP Server returned headers and flags for %@ IMAP Mail Messages.", @(imapMessages.count));
                 
                 
                 EmailProcessor* emailProcessor = [EmailProcessor getSingleton];
                 
                 // *************************************************************************************
                 // Updated Mails = Local Messages, with a matching IMAP Message, that has changed Flags
                 // *************************************************************************************

                 // Create an array of the mail messages that need to be updated
                 NSMutableArray<Mail*>* updatedMails = [self _mailMessages:allMailMessagesInLocalFolder
                                                                  inFolder:folderIdx
                                              withMessagesWithChangedFlags:imapMessages];
                 
                  DDLogInfo(@"IMAP folder \"%@\" will update %@ mail messages in local folder.", path, @(updatedMails.count));
                 
                 if (updatedMails.count > 0) {
                     // Update mail in DB and Local store
                     NSInvocationOperation* nextOp
                     = [[NSInvocationOperation alloc] initWithTarget:emailProcessor
                                                            selector:@selector(updateFlag:)
                                                              object:updatedMails];
                     
                     [emailProcessor.operationQueue addOperation:nextOp];
                 }

                 
                 // *************************************************************************************
                 // Deleted Mails = Local Messages no longer found in Imap Messages
                 // *************************************************************************************

                 NSMutableArray<Mail*>* deletedMails = [self _mailMessages:(NSArray *)allMailMessagesInLocalFolder
                                                                  inFolder:folderIdx
                                              notFoundInImapFolderMessages:imapMessages];

                 DDLogInfo(@"IMAP folder \"%@\" will delete %@ mail messages in local folder.", path,         @(deletedMails.count));

                 if (deletedMails.count > 0) {

                     NSDictionary* data = [[NSDictionary alloc] initWithObjects:@[deletedMails,@(folderIdx)] forKeys:@[@"datas",@"folderIdx"]];
                     
                     // Delete UID and mail message from DB and Local store
                     NSInvocationOperation* nextOp
                     = [[NSInvocationOperation alloc] initWithTarget:emailProcessor
                                                            selector:@selector(removeFromFolderWrapper:)
                                                              object:data];
                     
                     [emailProcessor.operationQueue addOperation:nextOp];
                 }
                 
                 
                 // *************************************************************************************
                 // Create an array of the dates of all the days that had msgs updated or deleted
                 // *************************************************************************************

                 
                 // Make sure deleted Mails Days are included in the list of mail days to be passed to the delegate
                 NSMutableArray<NSString*>* mailsDays = [[NSMutableArray alloc]init];  // from Mail.day
                 
                 // At this point mailsDays is empty
                 for (Mail* deletedMail in deletedMails) {
                     
                     if (![mailsDays containsObject:deletedMail.day]) {  // don't add duplicates
                         [mailsDays addObject:deletedMail.day];
                     }
                 }
                 
                 // Make sure updated Mails Days are included in the list of mail days to be passed to the delegate
                 
                 // At this point mailsDays contains all days with one or more deleted mails
                 for (Mail* updatedMail in updatedMails) {
                     
                     if (![mailsDays containsObject:updatedMail.day]) {     // Don't add duplicates
                         [mailsDays addObject:updatedMail.day];
                     }
                 }
                 // At this point mailsDays contains all (unique) days having any updated or deleted mails
                 
                 DDLogInfo(@"Calling completion block with %@ days with updated messages.",@(mailsDays.count));
                 
                 completedBlock(mailsDays);
             }];
         });
     }];
    return;
}



@end
