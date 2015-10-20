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
#import <Google/SignIn.h>
#import "ViewController.h"

@interface ImapSync ()

@property (nonatomic) NSInteger currentAccountIndex;
@property (nonatomic, strong) MCOIMAPOperation *imapCheckOp;
@property (nonatomic) BOOL connected;
@property (nonatomic) BOOL isConnecting;

@end

@implementation ImapSync

+ (ImapSync *)sharedServices {
    return [ImapSync sharedServices:kActiveAccountIndex];
}

+ (ImapSync *)sharedServices:(NSInteger)accountIndex {
    NSAssert(accountIndex < [AppSettings numActiveAccounts], @"Index:%li is incorrect only %li active account",(long)accountIndex,(long)[AppSettings numActiveAccounts]);
    
    return [ImapSync allSharedServices:nil][accountIndex];
}

+ (NSArray *)allSharedServices:(MCOIMAPSession *)updated {
    static NSArray * sharedServices = nil;
    
    if (updated) {
        sharedServices = nil;
    }
    @synchronized(self) {
        if (sharedServices == nil || sharedServices.count == 0) {
            NSMutableArray *sS = [[NSMutableArray alloc]init];
            
            for (int accountIndex = 0; accountIndex < [AppSettings numActiveAccounts]; accountIndex++) {
                //NSInteger accountIndex = [AppSettings numAccountForIndex:i];
                ImapSync *sharedService = [[super allocWithZone:nil] init];
                sharedService.currentAccountIndex = accountIndex;
                sharedService.connected = NO;
                sharedService.isConnecting = NO;
                
                if (updated && [updated.username isEqualToString:[AppSettings username:accountIndex]]) {
                    sharedService.imapSession = updated;
                    sharedService.connected = YES;
                } else {
                    sharedService.imapSession = [[MCOIMAPSession alloc] init];
                    sharedService.imapSession.hostname = [AppSettings imapServer:accountIndex];
                    sharedService.imapSession.port = [AppSettings imapPort:accountIndex];
                    sharedService.imapSession.username = [AppSettings username:accountIndex];
                    sharedService.imapSession.password = [AppSettings password:accountIndex];
                    sharedService.imapSession.connectionType = [AppSettings imapEnc:accountIndex];
                    sharedService.imapSession.maximumConnections = 6;
                    sharedService.connected = NO;
                }
                
                [sS addObject:sharedService];
            }
            sharedServices = [[NSArray alloc]initWithArray:sS];
            
            return sharedServices;
        } else {
            return sharedServices;
        }
    }
}

+ (RACSignal *)doLogin:(NSInteger)accountIndex {
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        ImapSync *sharedService = [ImapSync allSharedServices:nil][accountIndex];
        
        //[sharedService.imapSession setConnectionLogger:^(void * connectionID, MCOConnectionLogType type, NSData * data) {
            //if(type != MCOConnectionLogTypeReceived && type != MCOConnectionLogTypeSent){
               //. CCMLog(@"Type:%lu %@",(long)type, [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
            //}
        //}];
        
        if (!sharedService.connected && !sharedService.isConnecting) {
           // Reachability *networkReachability = [Reachability reachabilityForInternetConnection];
           // NetworkStatus networkStatus = [networkReachability currentReachabilityStatus];
            
            if ([ImapSync isNetworkAvailable]) {
                sharedService.isConnecting = YES;
                
                if ([AppSettings isUsingOAuth:sharedService.currentAccountIndex]) {
                    
                    sharedService.imapSession.OAuth2Token = [AppSettings oAuth:sharedService.currentAccountIndex];
                    sharedService.imapSession.authType = MCOAuthTypeXOAuth2;
                    
                    sharedService.imapCheckOp = [sharedService.imapSession checkAccountOperation];
                    [sharedService.imapCheckOp start:^(NSError *error) {
                        sharedService.isConnecting = NO;
                        
                        if (error) {
                            sharedService.connected = NO;
                            CCMLog(@"error:%@ loading account:%li %@", error,(long)sharedService.currentAccountIndex, [AppSettings username:sharedService.currentAccountIndex]);
                            //NSAssert(!error, @"Connection error?");
                            [[GIDSignIn sharedInstance] signInSilently];
                        } else {
                            CCMLog(@"Account:%li check OK", (long)sharedService.currentAccountIndex);
                            sharedService.connected = YES;
                            [sharedService checkForCachedActions];
                        }
                        [subscriber sendCompleted];
                    }];
                } else {
                    sharedService.imapCheckOp = [sharedService.imapSession checkAccountOperation];
                    [sharedService.imapCheckOp start:^(NSError *error) {
                        sharedService.isConnecting = NO;
                        
                        if (error) {
                            sharedService.connected = NO;
                            CCMLog(@"error:%@ loading account:%li %@", error,(long)sharedService.currentAccountIndex, [AppSettings username:sharedService.currentAccountIndex]);
                        } else {
                            CCMLog(@"Account:%li CONNECTED", (long)sharedService.currentAccountIndex);
                            sharedService.connected = YES;
                            [sharedService checkForCachedActions];
                        }
                        [subscriber sendCompleted];
                    }];
                }
            } else {
                [subscriber sendError:[NSError errorWithDomain:@"Connect" code:9000 userInfo:nil]];
            }
        } else {
            [subscriber sendCompleted];
        }
        
        return [RACDisposable disposableWithBlock:^{
        }];
    }];
}

- (void)saveCachedData {
    if (self.cachedData) {
        EmailProcessor *ep = [EmailProcessor getSingleton];
        
        for (Email *email in self.cachedData) {
            CCMLog(@"Saving Cached Email: %@", email.subject);
            
            if ([email.uids count] == 0) {
                CCMLog(@"Houston on a un probleme avec les emails en cache");
                continue;
            }
            NSInvocationOperation *nextOp = [[NSInvocationOperation alloc] initWithTarget:ep selector:@selector(addEmailWrapper:) object:email];
            [ep.operationQueue addOperation:nextOp];
            UidEntry *uidE = email.uids[0];
            [self writeFinishedFolderState:[SyncManager getSingleton] dbNum:@([EmailProcessor dbNumForDate:email.datetime]) withAccountIndex:[AppSettings indexForAccount:uidE.account] andFolder:uidE.folder];
        }
    }
}

- (NSInteger)nextFolderToSync {
    if (![[[SyncManager getSingleton] retrieveState:[AppSettings importantFolderNumforAccountIndex:self.currentAccountIndex forBaseFolder:FolderTypeAll] accountIndex:self.currentAccountIndex][@"fullsynced"] boolValue]) {
        return [AppSettings importantFolderNumforAccountIndex:self.currentAccountIndex forBaseFolder:FolderTypeAll];
    }
    
    if (![[[SyncManager getSingleton] retrieveState:[AppSettings importantFolderNumforAccountIndex:self.currentAccountIndex forBaseFolder:FolderTypeInbox] accountIndex:self.currentAccountIndex][@"fullsynced"] boolValue]) {
        return [AppSettings importantFolderNumforAccountIndex:self.currentAccountIndex forBaseFolder:FolderTypeInbox];
    }
    
    if (![[[SyncManager getSingleton] retrieveState:[AppSettings importantFolderNumforAccountIndex:self.currentAccountIndex forBaseFolder:FolderTypeFavoris] accountIndex:self.currentAccountIndex][@"fullsynced"] boolValue]) {
        if ([AppSettings importantFolderNumforAccountIndex:self.currentAccountIndex forBaseFolder:FolderTypeFavoris] != -1) {
            return [AppSettings importantFolderNumforAccountIndex:self.currentAccountIndex forBaseFolder:FolderTypeFavoris];
        }
    }
    
    if (![[[SyncManager getSingleton] retrieveState:[AppSettings importantFolderNumforAccountIndex:self.currentAccountIndex forBaseFolder:FolderTypeSent] accountIndex:self.currentAccountIndex][@"fullsynced"] boolValue]) {
        return [AppSettings importantFolderNumforAccountIndex:self.currentAccountIndex forBaseFolder:FolderTypeSent];
    }
    NSArray *folders = [AppSettings allFoldersNameforAccountIndex:self.currentAccountIndex];
    for (int indexFolder = 0; indexFolder < folders.count; indexFolder++) {
        if (![[[SyncManager getSingleton] retrieveState:indexFolder accountIndex:self.currentAccountIndex][@"fullsynced"] boolValue]) {
            return indexFolder;
        }
    }
    
    return -1;
}

- (RACSignal *)runSearchThing:(NSArray *)things {
    @weakify(self);
    
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        @strongify(self);
        
        if (![ImapSync isNetworkAvailable]) {
            [subscriber sendError:[NSError errorWithDomain:@"Connect" code:9000 userInfo:nil]];
        }
        
        NSInteger currentFolder = [AppSettings importantFolderNumforAccountIndex:self.currentAccountIndex forBaseFolder:FolderTypeAll];
        NSString *folder = [AppSettings folderName:currentFolder forAccountIndex:self.currentAccountIndex];
        MCOIMAPSearchExpression *expr = [MCOIMAPSearchExpression searchRecipient:((Person *)things[0]).email];
        MCOIMAPSearchOperation *so = [[ImapSync sharedServices:self.currentAccountIndex].imapSession searchExpressionOperationWithFolder:folder expression:expr];
        
        [so start:^(NSError *error, MCOIndexSet *searchResult) {
            if (error) {
                [subscriber sendError:error];
                return;
            }
            
            if (searchResult.count == 0) {
                [subscriber sendCompleted];
                return;
            }
            
            MCOIMAPMessagesRequestKind requestKind =
            MCOIMAPMessagesRequestKindHeaders |
            MCOIMAPMessagesRequestKindStructure |
            MCOIMAPMessagesRequestKindInternalDate |
            MCOIMAPMessagesRequestKindHeaderSubject |
            MCOIMAPMessagesRequestKindFlags;
            
            if ([[AppSettings identifier:self.currentAccountIndex] isEqualToString:@"gmail"]) {
                requestKind |= MCOIMAPMessagesRequestKindGmailThreadID;
            }
            
            MCOIMAPFetchMessagesOperation *imapMessagesFetchOp = [[ImapSync sharedServices:self.currentAccountIndex].imapSession fetchMessagesByNumberOperationWithFolder:folder requestKind:requestKind numbers:searchResult];
            [imapMessagesFetchOp start:^(NSError *error, NSArray *messages, MCOIndexSet *vanishedMessages){
                
                if (error) {
                    [subscriber sendError:error];
                    return;
                }
                
                NSInteger __block count = messages.count;
                
                for (MCOIMAPMessage *msg in messages) {
                    
                    NSMutableDictionary *folderState = [[SyncManager getSingleton] retrieveState:currentFolder accountIndex:self.currentAccountIndex];
                    NSString *folderPath = folderState[@"folderPath"];
                    
                    Email *email = [[Email alloc]init];
                    
                    if (!msg.header.from.displayName) {
                        msg.header.from = [MCOAddress addressWithDisplayName:[msg.header.from.mailbox componentsSeparatedByString:@"@"].firstObject mailbox:msg.header.from.mailbox];
                    }
                    
                    email.sender = msg.header.from;
                    email.subject = msg.header.subject;
                    
                    if (!email.subject) {
                        email.subject = @"";
                    }
                    email.datetime = msg.header.receivedDate;
                    email.msgId = msg.header.messageID;
                    email.accountNum = [AppSettings numForData:self.currentAccountIndex];
                    
                    UidEntry *uid_entry = [[UidEntry alloc]init];
                    uid_entry.uid = msg.uid;
                    uid_entry.folder = currentFolder;
                    uid_entry.account = [AppSettings numForData:self.currentAccountIndex];
                    uid_entry.msgId = email.msgId;
                    
                    email.tos = msg.header.to;
                    
                    if (!email.tos) {
                        email.tos = [[NSArray alloc]init];
                    }
                    email.ccs = msg.header.cc;
                    
                    if (!email.ccs) {
                        email.ccs = [[NSArray alloc]init];
                    }
                    email.bccs = msg.header.bcc;
                
                    if (!email.bccs) {
                        email.bccs = [[NSArray alloc]init];
                    }
                    email.flag = msg.flags;
                    
                    //email.references = msg.header.references;
                    
                    if (msg.gmailThreadID) {
                        uid_entry.sonMsgId = [NSString stringWithFormat:@"%llu", msg.gmailThreadID];
                    }
                    else if (msg.header.references) {
                        uid_entry.sonMsgId = msg.header.references[0];
                    } else {
                        uid_entry.sonMsgId = @"0";
                    }
                    
                    if ([email existsLocally]) {
                        
                        if (![email uidEWithFolder:uid_entry.folder]) {
                            // already have this email in other folder than this one -> add folder in uid_entry
                            
                            if (currentFolder == 0 && !(email.flag & MCOMessageFlagSeen) && [AppSettings badgeCount] == 0) {
                                [UIApplication sharedApplication].applicationIconBadgeNumber++;
                            }
                            
                            NSInvocationOperation *nextOp = [[NSInvocationOperation alloc] initWithTarget:[EmailProcessor getSingleton] selector:@selector(addToFolderWrapper:) object:uid_entry];
                            [[EmailProcessor getSingleton].operationQueue addOperation:nextOp];
                            
                            MCOIMAPMessageRenderingOperation *op = [[ImapSync sharedServices:self.currentAccountIndex].imapSession plainTextBodyRenderingOperationWithMessage:msg folder:folderPath];
                            [op start:^(NSString *plainTextBodyString, NSError *error) {
                                email.body =  plainTextBodyString;
                                
                                [subscriber sendNext:email];
                                
                                --count;
                                
                                
                                [self writeFinishedFolderState:[SyncManager getSingleton] dbNum:@([EmailProcessor dbNumForDate:email.datetime]) withAccountIndex:self.currentAccountIndex andFolder:currentFolder];
                                
                                
                                if (count == 0) {
                                    [subscriber sendCompleted];
                                }
                            }];
                            continue;
                        }
                        --count;
                        
                        if (count == 0) {
                            [subscriber sendCompleted];
                            //CCMLog(@"Complete sent");
                        }
                        //We already have email with folder
                        continue;
                    }
                    
                    if (currentFolder == 0 && !(email.flag & MCOMessageFlagSeen) && [AppSettings badgeCount] == 0) {
                        [UIApplication sharedApplication].applicationIconBadgeNumber++;
                    }
                    
                    NSMutableArray *atts = [[NSMutableArray alloc] initWithCapacity:msg.attachments.count];
                    
                    for (MCOIMAPPart *part in msg.attachments) {
                        Attachment *at = [[Attachment alloc]init];
                        at.mimeType = part.mimeType;
                        at.msgId = email.msgId;
                        at.fileName = part.filename;
                        at.partID = part.partID;
                        at.size = part.size;
                        at.contentID = @"";
                        [atts addObject:at];
                    }
                    
                    for (MCOIMAPPart *part in msg.htmlInlineAttachments) {
                        Attachment *at = [[Attachment alloc]init];
                        at.mimeType = part.mimeType;
                        at.msgId = email.msgId;
                        at.fileName = part.filename;
                        at.partID = part.partID;
                        at.size = part.size;
                        at.contentID = part.contentID;
                        [atts addObject:at];
                    }
                    
                    email.attachments = atts;
                    
                    email.uids = @[uid_entry];
                    
                    [[[ImapSync sharedServices:self.currentAccountIndex].imapSession plainTextBodyRenderingOperationWithMessage:msg folder:folderPath stripWhitespace:NO] start:^(NSString *plainTextBodyString, NSError *error) {
                        email.body =  plainTextBodyString?:@"";
                        [[[ImapSync sharedServices:self.currentAccountIndex].imapSession htmlBodyRenderingOperationWithMessage:msg folder:folderPath] start:^(NSString *htmlString, NSError *error) {
                            email.htmlBody = htmlString;
                            
                            NSInvocationOperation *nextOp = [[NSInvocationOperation alloc] initWithTarget:[EmailProcessor getSingleton] selector:@selector(addEmailWrapper:) object:email];
                            [[EmailProcessor getSingleton].operationQueue addOperation:nextOp];
                            [self writeFinishedFolderState:[SyncManager getSingleton] dbNum:@([EmailProcessor dbNumForDate:email.datetime]) withAccountIndex:self.currentAccountIndex andFolder:currentFolder];
                            
                            [subscriber sendNext:email];
                            
                            --count;
                            
                            if (count == 0) {
                                [subscriber sendCompleted];
                                //CCMLog(@"Complete sent");
                            }
                        }];
                    }];
                }
            }];
        }];
        
        return [RACDisposable disposableWithBlock:^{}];
    }];
}

- (RACSignal *)runFolder:(NSInteger)folder fromStart:(BOOL)isFromStart fromAccount:(BOOL)getAll {
    BOOL isInBackground = UIApplicationStateBackground == [UIApplication sharedApplication].applicationState;
    
    if (folder == -1) {
        folder = [self nextFolderToSync];
    }
    
    NSInteger currentFolder = folder;
    
    /*if (currentFolder != -1) {
     CCMLog(@"Syncing folder(%li) %@ in account %@",(long)currentFolder, [AppSettings folderName:currentFolder forAccount:self.currentAccount],[AppSettings username:self.currentAccount]);
     }*/
    
    if (!self.cachedData) {
        self.cachedData = [[NSMutableArray alloc]initWithCapacity:1];
        self.emailIDs = [[NSMutableSet alloc]initWithCapacity:1];
    }
    
    MCOIMAPMessagesRequestKind requestKind =
    MCOIMAPMessagesRequestKindHeaders |
    MCOIMAPMessagesRequestKindStructure |
    MCOIMAPMessagesRequestKindInternalDate |
    MCOIMAPMessagesRequestKindHeaderSubject |
    MCOIMAPMessagesRequestKindFlags;
    
    if ([[AppSettings identifier:self.currentAccountIndex] isEqualToString:@"gmail"]) {
        requestKind |= MCOIMAPMessagesRequestKindGmailThreadID;
    }
    
    @weakify(self);
    
    return [RACSignal createSignal:^RACDisposable *(id<RACSubscriber> subscriber) {
        @strongify(self);
        // get list of all folders
        
        if (![ImapSync isNetworkAvailable]) {
            [subscriber sendError:[NSError errorWithDomain:@"Connect" code:9000 userInfo:nil]];
        }
        else if (currentFolder == -1) {
            [subscriber sendError:[NSError errorWithDomain:@"All synced" code:9001 userInfo:nil]];
        }
        else if (isInBackground && currentFolder != [AppSettings importantFolderNumforAccountIndex:self.currentAccountIndex forBaseFolder:FolderTypeInbox]) {
            [subscriber sendCompleted];
        }
        else {
        [[ImapSync doLogin:self.currentAccountIndex] subscribeCompleted:^{
            
            MCOIMAPFetchFoldersOperation *fio = [[ImapSync sharedServices:self.currentAccountIndex].imapSession fetchAllFoldersOperation];
            [fio start:^(NSError *error, NSArray *folders) {
                if (error) {
                    [subscriber sendError:error];
                    
                    return;
                }
                else if (folders.count == 0) {
                    [subscriber sendCompleted];
                    
                    return;
                }//Fetch folder issue
                SyncManager *sm = [SyncManager getSingleton];
                EmailProcessor *emailProcessor = [EmailProcessor getSingleton];
                // mark folders that were deleted on the server as deleted on the client
                int i = 0;
                
                while (i < [sm folderCount:self.currentAccountIndex]) {
                    NSDictionary *folderState = [sm retrieveState:i accountIndex:self.currentAccountIndex];
                    NSString *folderPath = folderState[@"folderPath"];
                    
                    if ([sm isFolderDeleted:i accountIndex:self.currentAccountIndex]) {
                        CCMLog(@"Folder is deleted: %i %li", i, (long)self.currentAccountIndex);
                    }
                    
                    if (![sm isFolderDeleted:i accountIndex:self.currentAccountIndex] && ![[folders valueForKey:@"path"] containsObject:folderPath]) {
                        CCMLog(@"Folder %@ has been deleted - deleting FolderState", folderPath);
                        [sm markFolderDeleted:i accountIndex:self.currentAccountIndex];
                        i = 0;
                    }
                    i++;
                }
                
                NSMutableDictionary *folderState = [sm retrieveState:currentFolder accountIndex:self.currentAccountIndex];
                NSString *folderPath = folderState[@"folderPath"];
                
                MCOIMAPFolderInfoOperation *folder = [[ImapSync sharedServices:self.currentAccountIndex].imapSession folderInfoOperation:folderPath];
                NSInteger lastEnded = [folderState[@"lastended"] integerValue];
                
                [folder start:^(NSError *error, MCOIMAPFolderInfo *info) {
                    if (error) {
                        [subscriber sendError:error];
                        return;
                    }
                    
                    int batchsize = 20;
                    
                    if (!isFromStart) {
                        batchsize = 50;
                    }
                    
                    [self writeFinishedFolderState:sm emailCount:[info messageCount] withAccountIndex:self.currentAccountIndex andFolder:currentFolder];
                    
                    if ([info messageCount] == 0 || (!isFromStart && (lastEnded == 1))) {
                        NSInteger lE = ([info messageCount] == 0)?1:lastEnded;
                        [self writeFinishedFolderState:sm lastEnded:lE withAccountIndex:self.currentAccountIndex andFolder:currentFolder];
                        
                        if (currentFolder == [AppSettings importantFolderNumforAccountIndex:self.currentAccountIndex  forBaseFolder:FolderTypeAll]) {
                            //NSDictionary *userInfo = @{NSLocalizedDescriptionKey: NSLocalizedString(@"Full Sync done.", nil)};
                            //NSError *er = [NSError errorWithDomain:@"CocoaErrorDomain" code:-57 userInfo:userInfo];
                            //[AppSettings firstFullSyncDone];
                            [subscriber sendCompleted];
                            return;
                        }
                        
                        [subscriber sendCompleted];
                        return;
                    }
                    
                    NSInteger from = [info messageCount];
                    
                    if (!(isFromStart || isInBackground) && lastEnded != 0) {
                        from = lastEnded-1;
                    }
                    
                    uint64_t batch = MIN(batchsize, [info messageCount]);
                    
                    batch--;
                    
                    if (from > batch) {
                        from -= batch;
                    } else {
                        from = 1;
                    }
                    
                    //CCMLog(@"Checking account:%li folder:%@ from:%li batch:%llu",(long)self.currentAccount, folderPath,(long)from,batch);
                    CCMLog(@"Account:%ld Folder:%@ %li%% complete fetching %ld to %llu of %u", (long)self.currentAccountIndex, folderPath,(long)((from + batch) * 100) / [info messageCount], (long)(from), (from + batch), [info messageCount]);
                    
                    MCOIndexSet *numbers = [MCOIndexSet indexSetWithRange:MCORangeMake(from, batch)];
                    MCOIMAPFetchMessagesOperation *imapMessagesFetchOp = [[ImapSync sharedServices:self.currentAccountIndex].imapSession fetchMessagesByNumberOperationWithFolder:folderPath requestKind:requestKind numbers:numbers];
                    [imapMessagesFetchOp start:^(NSError *error, NSArray *messages, MCOIndexSet *vanishedMessages){
                        if (error) {
                            [subscriber sendError:error];
                            return;
                        }
                        NSInteger __block count = messages.count;
                        
                        for (MCOIMAPMessage *msg in messages) {
                            
                            NSMutableDictionary *folderState = [sm retrieveState:currentFolder accountIndex:self.currentAccountIndex];
                            NSString *folderPath = folderState[@"folderPath"];
                            
                            Email *email = [[Email alloc]init];
                            
                            if (!msg.header.from.displayName) {
                                msg.header.from = [MCOAddress addressWithDisplayName:[msg.header.from.mailbox componentsSeparatedByString:@"@"].firstObject mailbox:msg.header.from.mailbox];
                            }
                            
                            email.sender = msg.header.from;
                            email.subject = msg.header.subject;
                            
                            if (!email.subject) {
                                email.subject = @"";
                            }
                            email.datetime = msg.header.receivedDate;
                            email.msgId = msg.header.messageID;
                            email.accountNum = [AppSettings numForData:self.currentAccountIndex];
                            UidEntry *uid_entry = [[UidEntry alloc]init];
                            uid_entry.uid = msg.uid;
                            uid_entry.folder = currentFolder;
                            uid_entry.account = email.accountNum;
                            uid_entry.msgId = email.msgId;
                            
                            email.tos = msg.header.to;
                            
                            if (!email.tos) {
                                email.tos = [[NSArray alloc]init];
                            }
                            email.ccs = msg.header.cc;
                            
                            if (!email.ccs) {
                                email.ccs = [[NSArray alloc]init];
                            }
                            email.bccs = msg.header.bcc;
                            
                            if (!email.bccs) {
                                email.bccs = [[NSArray alloc]init];
                            }
                            email.flag = msg.flags;
                            
                            //email.references = msg.header.references;
                            
                            if (msg.gmailThreadID) {
                                uid_entry.sonMsgId = [NSString stringWithFormat:@"%llu", msg.gmailThreadID];
                            }
                            else if(msg.header.references) {
                                uid_entry.sonMsgId = msg.header.references[0];
                            } else {
                                uid_entry.sonMsgId = @"0";
                            }
                            
                            if ([email existsLocally]) {
                                
                                if (![email uidEWithFolder:uid_entry.folder]) {
                                    // already have this email in other folder than this one -> add folder in uid_entry
                                    
                                    if (currentFolder == 0 && !(email.flag & MCOMessageFlagSeen) && [AppSettings badgeCount] == 0) {
                                        [UIApplication sharedApplication].applicationIconBadgeNumber++;
                                    }
                                    
                                    NSInvocationOperation *nextOp = [[NSInvocationOperation alloc] initWithTarget:emailProcessor selector:@selector(addToFolderWrapper:) object:uid_entry];
                                    [emailProcessor.operationQueue addOperation:nextOp];
                                    
                                    MCOIMAPMessageRenderingOperation *op = [[ImapSync sharedServices:self.currentAccountIndex].imapSession plainTextBodyRenderingOperationWithMessage:msg folder:folderPath];
                                    [op start:^(NSString *plainTextBodyString, NSError *error) {
                                        email.body = plainTextBodyString;
                                        email.uids = [[NSMutableArray arrayWithArray:email.uids] arrayByAddingObject:uid_entry];
                                        
                                        if (currentFolder == [Accounts sharedInstance].currentAccount.currentFolderIdx) {
                                            [subscriber sendNext:email];
                                        }
                                        
                                        --count;
                                        
                                        if (!isInBackground) {
                                            [self writeFinishedFolderState:sm dbNum:@([EmailProcessor dbNumForDate:email.datetime]) withAccountIndex:self.currentAccountIndex andFolder:currentFolder];
                                        }
                                        
                                        if (count == 0) {
                                            [subscriber sendCompleted];
                                        }
                                    }];
                                    continue;
                                }
                                --count;
                                
                                if (count == 0) {
                                    [subscriber sendCompleted];
                                    //CCMLog(@"Complete sent");
                                }
                                //We already have email with folder
                                continue;
                            }
                            
                            if (currentFolder == 0 && !(email.flag & MCOMessageFlagSeen) && [AppSettings badgeCount] == 0) {
                                [UIApplication sharedApplication].applicationIconBadgeNumber++;
                            }
                            
                            NSMutableArray *atts = [[NSMutableArray alloc] initWithCapacity:msg.attachments.count + msg.htmlInlineAttachments.count];
                            
                            for (MCOIMAPPart *part in msg.attachments) {
                                Attachment *at = [[Attachment alloc]init];
                                at.mimeType = part.mimeType;
                                at.msgId = email.msgId;
                                at.fileName = part.filename;
                                at.partID = part.partID;
                                at.size = part.size;
                                at.contentID = @"";
                                [atts addObject:at];
                            }
                            
                            for (MCOIMAPPart *part in msg.htmlInlineAttachments) {
                                Attachment *at = [[Attachment alloc]init];
                                at.mimeType = part.mimeType;
                                at.msgId = email.msgId;
                                at.fileName = part.filename;
                                at.partID = part.partID;
                                at.size = part.size;
                                at.contentID = part.contentID;
                                [atts addObject:at];
                            }
                            
                            email.attachments = atts;
                            
                            email.uids = @[uid_entry];
                            
                            [[[ImapSync sharedServices:self.currentAccountIndex].imapSession plainTextBodyRenderingOperationWithMessage:msg folder:folderPath stripWhitespace:NO] start:^(NSString *plainTextBodyString, NSError *error) {
                                email.body =  plainTextBodyString?:@"";
                                [[[ImapSync sharedServices:self.currentAccountIndex].imapSession htmlBodyRenderingOperationWithMessage:msg folder:folderPath] start:^(NSString *htmlString, NSError *error) {
                                    email.htmlBody = htmlString;
                                    
                                    //Cache email if in Background
                                    if (isInBackground) {
                                        BOOL isInInbox = (currentFolder == [AppSettings importantFolderNumforAccountIndex:self.currentAccountIndex forBaseFolder:FolderTypeInbox]);
                                        BOOL isUnread = !(email.flag & MCOMessageFlagSeen);
                                        
                                        if (isInInbox & isUnread) {
                                            if (![self.emailIDs containsObject:email.msgId]) {
                                                CCMLog(@"Had Cached Email: %li", (unsigned long)self.emailIDs.count);
                                                CCMLog(@"Notifying Email: %@", email.subject);
                                                [self.cachedData addObject:email];
                                                [self.emailIDs addObject:email.msgId];
                                                
                                                if ([AppSettings notifications]) {
                                                    UILocalNotification *localNotification = [[UILocalNotification alloc] init];
                                                    localNotification.fireDate = [NSDate dateWithTimeIntervalSinceNow:10];
                                                    NSString *alertText = [[NSString alloc]initWithFormat:@"%@\n%@%@", email.sender.displayName, (email.hasAttachments?@"📎 ":@""), email.subject];
                                                    localNotification.alertBody = alertText;
                                                    localNotification.timeZone = [NSTimeZone defaultTimeZone];
                                                    [[UIApplication sharedApplication] scheduleLocalNotification:localNotification];
                                                }
                                            }
                                        }
                                    } else {
                                        NSInvocationOperation *nextOp = [[NSInvocationOperation alloc] initWithTarget:emailProcessor selector:@selector(addEmailWrapper:) object:email];
                                        [emailProcessor.operationQueue addOperation:nextOp];
                                        [self writeFinishedFolderState:sm dbNum:@([EmailProcessor dbNumForDate:email.datetime]) withAccountIndex:self.currentAccountIndex andFolder:currentFolder];
                                    }
                                    
                                    if ((currentFolder == [Accounts sharedInstance].currentAccount.currentFolderIdx) | getAll) {
                                        [subscriber sendNext:email];
                                    }
                                    --count;
                                    
                                    if (count == 0) {
                                        [subscriber sendCompleted];
                                    }
                                }];
                            }];
                        }
                    }];//Fetch Messages
                    
                    if (!isFromStart && !isInBackground) {
                        [self writeFinishedFolderState:sm lastEnded:from withAccountIndex:self.currentAccountIndex andFolder:currentFolder];
                    }
                }];//Fetch folder Info
            }];//Fetch All Folders
        }];
        }
        
        return [RACDisposable disposableWithBlock:^{
        }];
    }];
}

- (void)writeFinishedFolderState:(SyncManager *)sm emailCount:(NSInteger)count withAccountIndex:(NSInteger)accountIndex andFolder:(NSInteger)folder {
    // used by fetchFrom to write the finished state for this round of syncing to disk
    NSMutableDictionary *syncState = [sm retrieveState:folder accountIndex:accountIndex];
    syncState[@"emailCount"] = @(count);
    
    [sm persistState:syncState forFolderNum:folder accountIndex:accountIndex];
}

- (void)writeFinishedFolderState:(SyncManager *)sm lastEnded:(NSInteger)lastEIndex withAccountIndex:(NSInteger)accountIndex andFolder:(NSInteger)folder {
    // used by fetchFrom to write the finished state for this round of syncing to disk
    NSMutableDictionary *syncState = [sm retrieveState:folder accountIndex:accountIndex];
    syncState[@"lastended"] = @(lastEIndex);
    syncState[@"fullsynced"] = @(lastEIndex == 1);
    
    [sm persistState:syncState forFolderNum:folder accountIndex:accountIndex];
}

- (void)writeFinishedFolderState:(SyncManager *)sm dbNum:(NSNumber *)dbNum withAccountIndex:(NSInteger)accountIndex andFolder:(NSInteger)folder {
    // used by fetchFrom to write the finished state for this round of syncing to disk
    NSMutableDictionary *syncState = [sm retrieveState:folder accountIndex:accountIndex];
    
    if (dbNum != nil) { // record which dbNums elements from this folder occur in
        NSMutableArray *dbNumsArray = [NSMutableArray arrayWithArray:syncState[@"dbNums"]];
        NSSet *dbNumsSet = [NSSet setWithArray:dbNumsArray];
        
        if (![dbNumsSet containsObject:dbNum]) {
            [dbNumsArray addObject:dbNum];
        }
        
        NSSortDescriptor *sortOrder = [NSSortDescriptor sortDescriptorWithKey:@"self" ascending:NO];
        syncState[@"dbNums"] = [dbNumsArray sortedArrayUsingDescriptors:@[sortOrder]];
    }
    
    [sm persistState:syncState forFolderNum:folder accountIndex:accountIndex];
}

- (void)runUpToDateCachedTest:(NSArray *)emails {
    MCOIndexSet *uidsIS = [[MCOIndexSet alloc]init];
    NSString *path = [AppSettings folderName:[[Accounts sharedInstance].currentAccount currentFolderIdx] forAccountIndex:self.currentAccountIndex];
    
    NSMutableArray *datas = [[NSMutableArray alloc]init];
    
    for (Email *email in emails) {
        //TODO: Get the right uid corresponding to the message id and folder
        
        UidEntry *uid_entry = [UidEntry getUidEntryWithFolder:[[Accounts sharedInstance].currentAccount currentFolderIdx] msgId:email.msgId];
        [uidsIS addIndex:uid_entry.uid];
        
        NSMutableDictionary *dict = [NSMutableDictionary dictionary];
        dict[@"email"] = email;
        dict[@"uid_entry"] = uid_entry;
        [datas addObject:dict];
    }
    
    MCOIMAPFetchMessagesOperation *op = [[ImapSync sharedServices].imapSession  fetchMessagesOperationWithFolder:path requestKind:MCOIMAPMessagesRequestKindFlags uids:uidsIS];
    
    [op start:^(NSError *error, NSArray *messages, MCOIndexSet *vanishedMessages) {
        EmailProcessor *ep = [EmailProcessor getSingleton];
        
        for (MCOIMAPMessage *msg in messages) {
            //If in this folder or cross check in other folder
            if ([uidsIS containsIndex:msg.uid]) {
                //Don't Delete
                [uidsIS removeIndex:msg.uid];
            }
        }
        
        NSMutableArray *delDatas = [[NSMutableArray alloc]init];
        NSMutableArray *upDatas = [[NSMutableArray alloc]init];
        
        
        for (NSMutableDictionary *data in datas) {
            UidEntry *uid_entry = data[@"uid_entry"];
            Email *email = data[@"email"];
            
            if ([uidsIS containsIndex:uid_entry.uid]) {
                //Remove email from local folder
                [delDatas addObject:data];
            } else {
                for (MCOIMAPMessage *msg in messages) {
                    if (msg.uid == uid_entry.uid && !(msg.flags & email.flag)) {
                        email.flag = msg.flags;
                        data[@"email"] = email;
                        [upDatas addObject:data];
                    }
                }
                
            }
        }
        [ep removeFromFolderWrapper:delDatas];
        [ep updateFlag:upDatas];
    }];
    return;
}

- (void)runUpToDateTest:(NSArray *)convs completed:(void (^)(void))completedBlock {
    MCOIndexSet *uidsIS = [[MCOIndexSet alloc]init];
    NSString *path = [AppSettings folderName:[[Accounts sharedInstance].currentAccount currentFolderIdx] forAccountIndex:self.currentAccountIndex];
   //NSInteger activeA = self.currentAccount;
    
    NSMutableArray *emails = [NSMutableArray arrayWithCapacity:100];
    
    //for (int i = 0; i < emails.count; i++) {
    for (Conversation *conv in convs) {
        for (Mail *mail in conv.mails) {
            if ([mail.email uidEWithFolder:[[Accounts sharedInstance].currentAccount currentFolderIdx]]) {
                if (!kisActiveAccountAll) {
                    [uidsIS addIndex:[mail.email uidEWithFolder:[[Accounts sharedInstance].currentAccount currentFolderIdx]].uid];
                    [emails addObject:mail.email];
                }
                else if([mail.email uidEWithFolder:[[Accounts sharedInstance].currentAccount currentFolderIdx]].account == [AppSettings numForData:self.currentAccountIndex]) {
                    [uidsIS addIndex:[mail.email uidEWithFolder:[[Accounts sharedInstance].currentAccount currentFolderIdx]].uid];
                    [emails addObject:mail.email];
                }
            }
        }
    }
    
    [[ImapSync doLogin:self.currentAccountIndex] subscribeCompleted:^{
        
        MCOIMAPFetchMessagesOperation *op = [self.imapSession  fetchMessagesOperationWithFolder:path requestKind:MCOIMAPMessagesRequestKindFlags uids:uidsIS];
        
        [op start:^(NSError *error, NSArray *messages, MCOIndexSet *vanishedMessages) {
            if (error) {
                CCMLog(@"error testing emails, %@", error);
                return;
            }
            
            EmailProcessor *ep = [EmailProcessor getSingleton];
            
            for (MCOIMAPMessage *msg in messages) {
                //If in this folder or cross check in other folder
                if ([uidsIS containsIndex:msg.uid]) {
                    //Don't Delete
                    [uidsIS removeIndex:msg.uid];
                }
            }
            
            NSMutableArray *delDatas = [[NSMutableArray alloc]init];
            NSMutableArray *upDatas = [[NSMutableArray alloc]init];
            
            for (Email *email in emails) {
                UidEntry *uid_entry = [email uidEWithFolder:[[Accounts sharedInstance].currentAccount currentFolderIdx]];
                
                if ([uidsIS containsIndex:uid_entry.uid]) {
                    //Remove email from local folder
                    [delDatas addObject:email];
                } else {
                    for (MCOIMAPMessage *msg in messages) {
                        if (msg.uid == uid_entry.uid && !(msg.flags & email.flag)) {
                            if (msg.flags == MCOMessageFlagNone && email.flag == MCOMessageFlagNone) {
                                continue;
                            }
                            email.flag = msg.flags;
                            [upDatas addObject:email];
                        }
                    }
                    
                }
            }
            
            if (delDatas.count > 0) {
                CCMLog(@"Delete %lu emails", (unsigned long)delDatas.count);
                [ep removeFromFolderWrapper:delDatas];
            }
            
            if (upDatas.count > 0) {
                CCMLog(@"Update %lu emails", (unsigned long)upDatas.count);
                [ep updateFlag:upDatas];
            }
            
            completedBlock();
        }];
        
    }];
    return;
}

- (void)checkForCachedActions {
    NSMutableArray *cachedActions = [CachedAction getActionsForAccount:[AppSettings numForData:self.currentAccountIndex]];
    
    for (CachedAction *cachedAction in cachedActions) {
        [cachedAction doAction];
    }
}

+ (BOOL)isNetworkAvailable {
    char *hostname;
    struct hostent *hostinfo;
    hostname = "google.com";
    hostinfo = gethostbyname (hostname);
    if (hostinfo == NULL){
        //CCMLog(@"-> no connection!\n");
        return NO;
    }
    else{
        //CCMLog(@"-> connection established!\n");
        return YES;
    }
}

@end
