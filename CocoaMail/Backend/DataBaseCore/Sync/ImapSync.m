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
#import <Instabug/Instabug.h>
#import "StringUtil.h"
#import "CCMConstants.h"
#import "UserSettings.h"


@interface ImapSync ()

@property (nonatomic) UserSettings* user;
@property (nonatomic, strong) MCOIMAPOperation* imapCheckOp;
@property (nonatomic) BOOL isCanceled;

@end

static NSArray * sharedServices = nil;


@implementation ImapSync

+(ImapSync*) sharedServices:(UserSettings*)user
{
    NSAssert(user, @"No user at accountNum:%ld",(long)user.accountNum);
    
    NSAssert(!user.isDeleted, @"AccountNum:%ld is deleted",(long)user.accountNum);
    
    for (ImapSync* sharedService in [ImapSync allSharedServices:nil]) {
        if (sharedService.user.accountNum == user.accountNum) {
            return sharedService;
        }
    }
    
    return nil;
}

+(NSArray*) allSharedServices:(MCOIMAPSession*)updated
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
                    NSLog(@"Disconnected");
                }];
            });
        }
    }
    
    sharedServices = nil;
}

+(RACSignal*) doLogin:(UserSettings*)user
{
    return [RACSignal createSignal:^RACDisposable* (id<RACSubscriber> subscriber) {
        ImapSync* sharedService = [ImapSync sharedServices:user];
        
        @synchronized(sharedService) {
            
            if (!sharedService) {
                [subscriber sendCompleted];
            }
            else if (sharedService.connected) {
                [subscriber sendCompleted];
            }
            else if (![ImapSync isNetworkAvailable]) {
                sharedService.connected = NO;
                [subscriber sendError:[NSError errorWithDomain:@"Connect" code:9000 userInfo:nil]];
            }
            else {
                if ([sharedService.user isUsingOAuth]) {
                    
                    NSLog(@"Loggin with OAuth with token:%@", [sharedService.user oAuth]);
                    
                    sharedService.imapSession.OAuth2Token = [sharedService.user oAuth];
                    sharedService.imapSession.authType = MCOAuthTypeXOAuth2;
                    sharedService.imapSession.connectionType = MCOConnectionTypeTLS;
                    sharedService.imapCheckOp = [sharedService.imapSession checkAccountOperation];
                    
                    dispatch_semaphore_t connectionSemaphore = dispatch_semaphore_create(0);
                    
                    dispatch_async([ImapSync sharedServices:user].s_queue, ^{
                        [sharedService.imapCheckOp start:^(NSError* error) {
                            if (error) {
                                NSLog(@"Error:%@ loading oauth account:%@", error, sharedService.user.username);
                                GTMOAuth2Authentication * auth = [GTMOAuth2ViewControllerTouch authForGoogleFromKeychainForName:KEYCHAIN_ITEM_NAME
                                                                                                                       clientID:CLIENT_ID
                                                                                                                   clientSecret:CLIENT_SECRET];
                                if (![auth canAuthorize]) {
                                    NSLog(@"Can't Authorize");
                                    
                                    auth.clientID = CLIENT_ID;
                                    auth.clientSecret = CLIENT_SECRET;
                                    
                                    BOOL didAuth = [GTMOAuth2ViewControllerTouch authorizeFromKeychainForName:KEYCHAIN_ITEM_NAME
                                                                                               authentication:auth
                                                                                                        error:NULL];
                                    if (didAuth) {
                                        NSLog(@"Did Authorize");
                                        [GTMOAuth2ViewControllerTouch saveParamsToKeychainForName:KEYCHAIN_ITEM_NAME authentication:auth];
                                    }
                                    else {
                                        sharedService.connected = NO;
                                        [subscriber sendError:[NSError errorWithDomain:@"Connect" code:9000 userInfo:nil]];
                                    }
                                    
                                    dispatch_semaphore_signal(connectionSemaphore);
                                }
                                else {
                                    NSLog(@"Resign & refresh token");
                                    
                                    NSURL *tokenURL = auth.tokenURL;
                                    
                                    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:tokenURL];
                                    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
                                    
                                    NSString *userAgent = [auth userAgent];
                                    [request setValue:userAgent forHTTPHeaderField:@"User-Agent"];
                                    
                                    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
                                    
                                    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                                        
                                        [auth authorizeRequest:request completionHandler:^(NSError *error) {
                                            
                                            if (!error && [auth accessToken] && ![[auth accessToken] isEqualToString:@""]) {
                                                [sharedService.user setOAuth:[auth accessToken]];
                                                sharedService.imapSession = [AppSettings imapSession:sharedService.user];
                                                sharedService.imapSession.dispatchQueue = sharedService.s_queue;
                                                
                                                NSLog(@"Loggin Again with OAuth with token:%@", [sharedService.user oAuth]);
                                                dispatch_async([ImapSync sharedServices:user].s_queue, ^{
                                                    
                                                    sharedService.imapCheckOp = [sharedService.imapSession checkAccountOperation];
                                                    [sharedService.imapCheckOp start:^(NSError* error) {
                                                        if (!error) {
                                                            NSLog(@"Account:%ld check OK", (long)sharedService.user.accountNum);
                                                            sharedService.connected = YES;
                                                            [sharedService.user.linkedAccount setConnected];
                                                            [sharedService checkForCachedActions];
                                                            [sharedService checkFolders];
                                                            
                                                            [subscriber sendCompleted];
                                                        }
                                                        else {
                                                            NSLog(@"Error:%@ loading oauth account:%@", error, sharedService.user.username);
                                                            [subscriber sendError:[NSError errorWithDomain:@"Connect" code:9000 userInfo:nil]];
                                                        }
                                                        
                                                        dispatch_semaphore_signal(semaphore);
                                                    }];
                                                });
                                            }
                                            else {
                                                NSLog(@"Error:%@ loading oauth account:%@", error, sharedService.user.username);
                                                [subscriber sendError:[NSError errorWithDomain:@"Connect" code:9000 userInfo:nil]];
                                                dispatch_semaphore_signal(semaphore);
                                            }
                                            
                                        }];
                                    }];
                                    
                                    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
                                    dispatch_semaphore_signal(connectionSemaphore);
                                    NSLog(@"Not waiting");
                                }
                            }
                            else {
                                NSLog(@"Account:%ld check OK", (long)sharedService.user.accountNum);
                                sharedService.connected = YES;
                                [sharedService.user.linkedAccount setConnected];
                                [sharedService checkForCachedActions];
                                [sharedService checkFolders];
                                
                                [subscriber sendCompleted];
                                
                                dispatch_semaphore_signal(connectionSemaphore);
                            }
                        }];
                    });
                    
                    dispatch_semaphore_wait(connectionSemaphore, DISPATCH_TIME_FOREVER);
                }
                else { //Not using OAuth
                    sharedService.imapCheckOp = [sharedService.imapSession checkAccountOperation];
                    
                    NSLog(@"Account with Password");
                    
                    dispatch_semaphore_t connectionSemaphore = dispatch_semaphore_create(0);
                    
                    dispatch_async([ImapSync sharedServices:user].s_queue, ^{
                        
                        [sharedService.imapCheckOp start:^(NSError* error) {
                            if (error) {
                                sharedService.connected = NO;
                                NSLog(@"Error:%@ loading account:%@", error, sharedService.user.username);
                                
                                if (error.code == MCOErrorAuthentication) {
                                    [subscriber sendError:[NSError errorWithDomain:@"Credentials" code:9003 userInfo:nil]];
                                }
                                else {
                                    [subscriber sendError:[NSError errorWithDomain:@"Connect" code:9000 userInfo:nil]];
                                }
                            }
                            else {
                                NSLog(@"Account:%ld CONNECTED", (long)sharedService.user.accountNum);
                                sharedService.connected = YES;
                                [sharedService.user.linkedAccount setConnected];
                                [sharedService checkForCachedActions];
                                [sharedService checkFolders];
                                
                                [subscriber sendCompleted];
                            }
                            
                            dispatch_semaphore_signal(connectionSemaphore);
                        }];
                    });
                    
                    dispatch_semaphore_wait(connectionSemaphore, DISPATCH_TIME_FOREVER);
                }
            }
        }
        
        return [RACDisposable disposableWithBlock:^{}];
    }];
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

-(NSInteger) nextFolderToSync
{
    if (![[[SyncManager getSingleton] retrieveState:[self.user importantFolderNumforBaseFolder:FolderTypeAll] accountNum:self.user.accountNum][@"fullsynced"] boolValue]) {
        return [self.user importantFolderNumforBaseFolder:FolderTypeAll];
    }
    
    if (![[[SyncManager getSingleton] retrieveState:[self.user importantFolderNumforBaseFolder:FolderTypeInbox] accountNum:self.user.accountNum][@"fullsynced"] boolValue]) {
        return [self.user importantFolderNumforBaseFolder:FolderTypeInbox];
    }
    
    if (![[[SyncManager getSingleton] retrieveState:[self.user importantFolderNumforBaseFolder:FolderTypeFavoris] accountNum:self.user.accountNum][@"fullsynced"] boolValue]) {
        if ([self.user importantFolderNumforBaseFolder:FolderTypeFavoris] != -1) {
            return [self.user importantFolderNumforBaseFolder:FolderTypeFavoris];
        }
    }
    
    if (![[[SyncManager getSingleton] retrieveState:[self.user importantFolderNumforBaseFolder:FolderTypeSent] accountNum:self.user.accountNum][@"fullsynced"] boolValue]) {
        return [self.user importantFolderNumforBaseFolder:FolderTypeSent];
    }
    
    NSArray* folders = [self.user allFoldersDisplayNames];
    for (int indexFolder = 0; indexFolder < folders.count; indexFolder++) {
        if (![[[SyncManager getSingleton] retrieveState:indexFolder accountNum:self.user.accountNum][@"fullsynced"] boolValue]) {
            return indexFolder;
        }
    }
    
    return -1;
}

-(RACSignal*) runSearchText:(NSString*)text
{
    @weakify(self);
    
    return [RACSignal createSignal:^RACDisposable* (id<RACSubscriber> subscriber) {
        @strongify(self);
        
        if (![ImapSync isNetworkAvailable]) {
            self.connected = NO;
            [subscriber sendError:[NSError errorWithDomain:@"Connect" code:9000 userInfo:nil]];
        }
        
        NSInteger currentFolder = [self.user importantFolderNumforBaseFolder:FolderTypeAll];
        NSString* folderPath = [self.user folderServerName:currentFolder];
        MCOIMAPSearchExpression* expr = [MCOIMAPSearchExpression searchContent:text];
        MCOIMAPSearchOperation* so = [self.imapSession searchExpressionOperationWithFolder:folderPath expression:expr];
        
        dispatch_async(self.s_queue, ^{
            [so start:^(NSError* error, MCOIndexSet* searchResult) {
                if (error) {
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
    @weakify(self);
    
    return [RACSignal createSignal:^RACDisposable* (id<RACSubscriber> subscriber) {
        @strongify(self);
        
        if (![ImapSync isNetworkAvailable]) {
            self.connected = NO;
            [subscriber sendError:[NSError errorWithDomain:@"Connect" code:9000 userInfo:nil]];
        }
        
        NSInteger currentFolder = [self.user importantFolderNumforBaseFolder:FolderTypeAll];
        MCOIMAPSearchExpression* expr = [MCOIMAPSearchExpression searchRecipient:person.email];
        MCOIMAPSearchOperation* so = [self.imapSession searchExpressionOperationWithFolder:[self.user folderServerName:currentFolder]
                                                                                expression:expr];
        dispatch_async(self.s_queue, ^{
            [so start:^(NSError* error, MCOIndexSet* searchResult) {
                if (error) {
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
        [subscriber sendCompleted];
        return;
    }
    
    if (!self.connected) {
        [subscriber sendError:[NSError errorWithDomain:@"Connect" code:9000 userInfo:nil]];
    }
    else {
        MCOIMAPFetchMessagesOperation* imapMessagesFetchOp = [self.imapSession fetchMessagesOperationWithFolder:[self.user folderServerName:currentFolder]
                                                                                                    requestKind:self.user.requestKind
                                                              
                                                                                                           uids:searchResult];
        dispatch_async(self.s_queue, ^{
            [imapMessagesFetchOp start:^(NSError* error, NSArray<MCOIMAPMessage*>* messages, MCOIndexSet* vanishedMessages){
                
                if (error) {
                    [subscriber sendError:error];
                    return;
                }
                
                NSString* lastMsgID = [messages firstObject].header.messageID;
                
                for (MCOIMAPMessage* msg in [messages reverseObjectEnumerator]) {
                    [self _saveSearchedEmail:msg inFolder:currentFolder withSubscriber:subscriber lastMsgID:lastMsgID];
                }
                
            }];
            
        });
    }
    
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
            if (plainTextBodyString) {
                plainTextBodyString = [plainTextBodyString stringByReplacingCharactersInRange:NSMakeRange(0, 1) withString:@""];
                
                email.body = plainTextBodyString;
            }
            else {
                email.body = @"";
            }
            
            [[self.imapSession htmlBodyRenderingOperationWithMessage:msg folder:folderPath] start:^(NSString* htmlString, NSError* error) {
                email.htmlBody = htmlString;
                
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

-(void) checkFolders
{
    MCOIMAPFetchFoldersOperation* fio = [self.imapSession fetchAllFoldersOperation];
    
    dispatch_async(self.s_queue, ^{
        [fio start:^(NSError* error, NSArray* folders) {
            if (!error && !folders && folders.count > 0) {
                SyncManager* sm = [SyncManager getSingleton];
                
                int indexPath = 0;
                
                NSMutableArray* dispNamesFolders = [[NSMutableArray alloc] initWithCapacity:1];
                
                for (MCOIMAPFolder* folder in folders) {
                    BOOL exists = NO;
                    
                    int i = 0;
                    
                    while (i < [sm folderCount:self.user.accountNum]) {
                        NSDictionary* folderState = [sm retrieveState:i accountNum:self.user.accountNum];
                        NSString* folderPath = folderState[@"folderPath"];
                        
                        if ([[folder path] isEqualToString:folderPath]) {
                            exists = YES;
                            break;
                        }
                        
                        i++;
                    }
                    
                    if (!exists) {
                        NSString* dispName = [[[self.imapSession defaultNamespace] componentsFromPath:[folder path]] componentsJoinedByString:@"/"];
                        [dispNamesFolders addObject:dispName];
                        
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
                    NSMutableArray* all = [NSMutableArray arrayWithArray:self.user.allFoldersDisplayNames];
                    [all addObjectsFromArray:dispNamesFolders];
                    
                    [self.user setAllFoldersDisplayNames:all];
                }
            }
        }];
    });
}

-(RACSignal*) runFolder:(NSInteger)folder fromStart:(BOOL)isFromStart fromAccount:(BOOL)getAll
{
    BOOL isInBackground = UIApplicationStateBackground == [UIApplication sharedApplication].applicationState;
    
    if (folder == -1) {
        folder = [self nextFolderToSync];
    }
    
    NSInteger currentFolder = folder;
    
    if (!self.cachedData) {
        self.cachedData = [[NSMutableArray alloc]initWithCapacity:1];
    }
    
    @weakify(self);
    
    return [RACSignal startLazilyWithScheduler:[RACScheduler schedulerWithPriority:RACSchedulerPriorityBackground] block:^(id<RACSubscriber> subscriber) {
        @strongify(self);
        // get list of all folders
        
        if (self.isCanceled) {
            [subscriber sendCompleted];
        }
        else if (![ImapSync isNetworkAvailable]) {
            self.connected = NO;
            [subscriber sendError:[NSError errorWithDomain:@"Connect" code:9000 userInfo:nil]];
        }
        else if (currentFolder == -1) {
            [subscriber sendError:[NSError errorWithDomain:@"All synced" code:9001 userInfo:nil]];
        }
        else if (isInBackground && currentFolder != [self.user importantFolderNumforBaseFolder:FolderTypeInbox]) {
            [subscriber sendCompleted];
        }
        else {
            [[ImapSync doLogin:self.user] subscribeError:^(NSError *error) {
                [subscriber sendError:error];
            } completed:^{
                
                if (!self.connected) {
                    if (isInBackground) {
                        [subscriber sendCompleted];
                    }
                    else {
                        [subscriber sendError:[NSError errorWithDomain:@"Connect" code:9000 userInfo:nil]];
                    }
                }
                else {
                    MCOIMAPFetchFoldersOperation* fio = [self.imapSession fetchAllFoldersOperation];
                    dispatch_async(self.s_queue, ^{
                        [fio start:^(NSError* error, NSArray* folders) {
                            if (error) {
                                [subscriber sendError:error];
                                
                                return;
                            }
                            else if (!folders || folders.count == 0) {
                                [subscriber sendCompleted];
                                
                                return;
                            }//Fetch folder issue
                            
                            dispatch_async(self.s_queue, ^{
                                
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
                                        NSLog(@"Error %@ with folder %@",error.description, folderPath);
                                        
                                        [subscriber sendError:error];
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
                                        
                                        //NSLog(@"Folder:%@ has %d emails", folderPath, [info messageCount]);
                                        
                                        if (!isInBackground) {
                                            [self _writeFinishedFolderState:sm emailCount:[info messageCount] andFolder:currentFolder];
                                            
                                            if ([info messageCount] == 0 || (!isFromStart && (lastEnded == 1))) {
                                                NSInteger lE = ([info messageCount] == 0)?1:lastEnded;
                                                [self _writeFinishedFolderState:sm lastEnded:lE andFolder:currentFolder];
                                                
                                                [subscriber sendError:[NSError errorWithDomain:@"Folder synced" code:9002 userInfo:nil]];
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
                                                [subscriber sendError:error];
                                                return;
                                            }
                                            
                                            dispatch_async(self.s_queue, ^{
                                                
                                                NSString* lastMsgID = [messages lastObject].header.messageID;
                                                
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
        
        BOOL isInInbox = (currentFolder == [self.user importantFolderNumforBaseFolder:FolderTypeInbox]);
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
    
    MCOIMAPFetchMessagesOperation* op = [self.imapSession  fetchMessagesOperationWithFolder:path requestKind:MCOIMAPMessagesRequestKindFlags uids:uidsIS];
    
    dispatch_async(self.s_queue, ^{
        [op start:^(NSError* error, NSArray* messages, MCOIndexSet* vanishedMessages) {
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
    return;
}

-(void) runUpToDateTest:(NSArray*)convs folderIndex:(NSInteger)folderIdx completed:(void (^)(NSArray* dels, NSArray* ups))completedBlock
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
        completedBlock(nil, nil);
        return;
    }
    
    NSMutableArray* delDatas = [[NSMutableArray alloc]init];
    NSMutableArray* upDatas = [[NSMutableArray alloc]init];
    
    [[ImapSync doLogin:self.user]
     subscribeError:^(NSError *error) {
         completedBlock(delDatas, upDatas);
     } completed:^{
         
         if (!self.connected){
             completedBlock(delDatas, upDatas);
             return;
         }
         
         MCOIMAPFetchMessagesOperation* op = [self.imapSession fetchMessagesOperationWithFolder:path requestKind:MCOIMAPMessagesRequestKindHeaders | MCOIMAPMessagesRequestKindFlags uids:uidsIS];
         dispatch_async(self.s_queue, ^{
             [op start:^(NSError* error, NSArray* messages, MCOIndexSet* vanishedMessages) {
                 
                 if (error) {
                     NSLog(@"error testing emails in %@, %@", path, error);
                     completedBlock(delDatas, upDatas);
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
                 
                 completedBlock(delDatas, upDatas);
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

+(BOOL) isNetworkAvailable
{
    Reachability* networkReachability = [Reachability reachabilityForInternetConnection];
    NetworkStatus networkStatus = [networkReachability currentReachabilityStatus];
    
    return (networkStatus != NotReachable);
}

+(BOOL) canFullSync
{
    Reachability* networkReachability = [Reachability reachabilityForInternetConnection];
    NetworkStatus networkStatus = [networkReachability currentReachabilityStatus];
    
    return [[AppSettings getSingleton] canSyncOverData] || (networkStatus == ReachableViaWiFi);
}

+(void) runInboxUnread:(UserSettings*)user
{
    [ImapSync runInboxUnread:user completed:^{}];
}

+(void) runInboxUnread:(UserSettings*)user completed:(void (^)(void))completedBlock
{
    if (![ImapSync isNetworkAvailable] | user.isAll) {
        completedBlock();
        return;
    }
    
    dispatch_async([ImapSync sharedServices:user].s_queue, ^{
        NSInteger currentFolder = [user  importantFolderNumforBaseFolder:FolderTypeInbox];
        NSString* folder = [user folderServerName:currentFolder];
        MCOIMAPSearchExpression* expr = [MCOIMAPSearchExpression searchUnread];
        MCOIMAPSearchOperation* so = [[ImapSync sharedServices:user].imapSession searchExpressionOperationWithFolder:folder expression:expr];
        
        [so start:^(NSError* error, MCOIndexSet* searchResult) {
            if (!error) {
                [AppSettings setInboxUnread:searchResult.count accountIndex:user.accountIndex];
            }
            completedBlock();
        }];
    });
}



@end
