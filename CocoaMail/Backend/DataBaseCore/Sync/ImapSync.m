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
#import <Instabug/Instabug.h>
#import "StringUtil.h"

@interface ImapSync ()

@property (nonatomic) NSInteger currentAccountIndex;
@property (nonatomic, strong) MCOIMAPOperation* imapCheckOp;
@property (nonatomic) BOOL isConnecting;
@property (nonatomic) BOOL isWaitingForOAuth;
@property (nonatomic) BOOL isCanceled;


@end

static NSArray * sharedServices = nil;

@implementation ImapSync

/*+(ImapSync*) sharedServices
 {
 return [ImapSync sharedServices:kActiveAccountIndex];
 }*/

+(ImapSync*) sharedServices:(NSInteger)accountIndex
{
    NSAssert(accountIndex < [AppSettings numActiveAccounts], @"Index:%ld is incorrect only %ld active account",(long)accountIndex,(long)[AppSettings numActiveAccounts]);
    
    return [ImapSync allSharedServices:nil][accountIndex];
}

+(NSArray*) allSharedServices:(MCOIMAPSession*)updated
{
    if (updated) {
        sharedServices = nil;
    }
    @synchronized(self) {
        if (sharedServices == nil || sharedServices.count == 0) {
            NSMutableArray* sS = [[NSMutableArray alloc]init];
            
            for (int accountIndex = 0; accountIndex < [AppSettings numActiveAccounts]; accountIndex++) {
                //NSInteger accountIndex = [AppSettings numAccountForIndex:i];
                ImapSync* sharedService = [[super allocWithZone:nil] init];
                sharedService.currentAccountIndex = accountIndex;
                sharedService.connected = NO;
                sharedService.isConnecting = NO;
                sharedService.isWaitingForOAuth = NO;
                
                if (updated && [updated.username isEqualToString:[AppSettings username:accountIndex]]) {
                    sharedService.imapSession = updated;
                    sharedService.connected = YES;
                }
                else {
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
        }
        else {
            return sharedServices;
        }
    }
}

+(void) deleted
{
    sharedServices = nil;
}

+(RACSignal*) doLogin:(NSInteger)accountIndex
{
    return [RACSignal createSignal:^RACDisposable* (id<RACSubscriber> subscriber) {
        ImapSync* sharedService = [ImapSync sharedServices:accountIndex];
        
        /*[sharedService.imapSession setConnectionLogger:^(void*  connectionID, MCOConnectionLogType type, NSData*  data) {
         if(type != MCOConnectionLogTypeReceived && type != MCOConnectionLogTypeSent){
         CCMLog(@"Type:%lu %@",(long)type, [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]);
         }
         }];*/
        
        if (sharedService.connected) {
            [subscriber sendCompleted];
            [[[Accounts sharedInstance] getAccount:accountIndex] setConnected:YES];
        }
        else if (sharedService.isConnecting) {
            [subscriber sendCompleted];
        }
        else {
            if ([ImapSync isNetworkAvailable]) {
                sharedService.isConnecting = YES;
                
                if ([AppSettings isUsingOAuth:sharedService.currentAccountIndex]) {
                    
                    if (!sharedService.isWaitingForOAuth || (sharedService.isWaitingForOAuth && [GIDSignIn sharedInstance].currentUser.authentication)) {
                        
                        if (sharedService.isWaitingForOAuth) {
                            sharedService.imapSession = [[MCOIMAPSession alloc] init];
                            sharedService.imapSession.hostname = [AppSettings imapServer:sharedService.currentAccountIndex];
                            sharedService.imapSession.port = [AppSettings imapPort:sharedService.currentAccountIndex];
                            sharedService.imapSession.username = [AppSettings username:sharedService.currentAccountIndex];
                            sharedService.imapSession.password = [AppSettings password:sharedService.currentAccountIndex];
                            sharedService.imapSession.connectionType = [AppSettings imapEnc:sharedService.currentAccountIndex];
                            sharedService.imapSession.maximumConnections = 6;
                            
                            CCMLog(@"Loggin with new OAuth");
                        }
                        
                        CCMLog(@"Loggin with OAuth with token:%@", [AppSettings oAuth:sharedService.currentAccountIndex]);
                        
                        sharedService.isWaitingForOAuth = NO;
                        
                        sharedService.imapSession.OAuth2Token = [AppSettings oAuth:sharedService.currentAccountIndex];
                        sharedService.imapSession.authType = MCOAuthTypeXOAuth2;
                        sharedService.imapSession.connectionType = MCOConnectionTypeTLS;
                        
                        sharedService.imapCheckOp = [sharedService.imapSession checkAccountOperation];
                        [sharedService.imapCheckOp start:^(NSError* error) {
                            sharedService.isConnecting = NO;
                            
                            if (error) {
                                CCMLog(@"error:%@ loading oauth account:%ld %@", error,(long)sharedService.currentAccountIndex, [AppSettings username:sharedService.currentAccountIndex]);
                                if (![GIDSignIn sharedInstance].currentUser.authentication) {
                                    CCMLog(@"Resign & refresh token");
                                    sharedService.isWaitingForOAuth = YES;
                                    [[GIDSignIn sharedInstance] signOut];
                                    [[GIDSignIn sharedInstance] signIn];
                                    //[[GIDSignIn sharedInstance] signInSilently];
                                }
                                else {
                                    [[[Accounts sharedInstance] getAccount:accountIndex] setConnected:NO];
                                }
                            }
                            else {
                                CCMLog(@"Account:%ld check OK", (long)sharedService.currentAccountIndex);
                                sharedService.connected = YES;
                                [[[Accounts sharedInstance] getAccount:accountIndex] setConnected:YES];
                                [sharedService checkForCachedActions];
                                [sharedService checkFolders];
                            }
                            [subscriber sendCompleted];
                        }];
                    }
                    else { //Waiting for OAuth token to be renewed
                        [subscriber sendCompleted];
                    }
                }
                else { //Not using OAuth
                    sharedService.imapCheckOp = [sharedService.imapSession checkAccountOperation];
                    [sharedService.imapCheckOp start:^(NSError* error) {
                        sharedService.isConnecting = NO;
                        
                        if (error) {
                            sharedService.connected = NO;
                            [[[Accounts sharedInstance] getAccount:accountIndex] setConnected:NO];
                            CCMLog(@"error:%@ loading account:%ld %@", error,(long)sharedService.currentAccountIndex, [AppSettings username:sharedService.currentAccountIndex]);
                        }
                        else {
                            CCMLog(@"Account:%ld CONNECTED", (long)sharedService.currentAccountIndex);
                            sharedService.connected = YES;
                            [[[Accounts sharedInstance] getAccount:accountIndex] setConnected:YES];
                            [sharedService checkForCachedActions];
                            [sharedService checkFolders];
                        }
                        
                        [subscriber sendCompleted];
                    }];
                }
            }
            else { //No internet connection
                [[[Accounts sharedInstance] getAccount:accountIndex] setConnected:NO];
                [subscriber sendError:[NSError errorWithDomain:@"Connect" code:9000 userInfo:nil]];
            }
        }
        
        return [RACDisposable disposableWithBlock:^{
        }];
    }];
}

-(void) cancel
{
    self.isCanceled = YES;
}

-(void) saveCachedData
{
    NSMutableArray* ops = [[NSMutableArray alloc] initWithCapacity:self.cachedData.count];
    EmailProcessor* ep = [EmailProcessor getSingleton];
    
    NSURL* someURL = [[NSURL alloc] initFileURLWithPath:[StringUtil filePathInDocumentsDirectoryForFileName:@"cache"]];
    [[[NSArray alloc]init] writeToURL:someURL atomically:YES];
    
    [AppSettings setCache:[[NSSet alloc]init]];
    
    if (self.cachedData) {
        for (Email* email in self.cachedData) {
            CCMLog(@"Saving Cached Email: %@", email.subject);
            
            NSInvocationOperation* nextOp = [[NSInvocationOperation alloc] initWithTarget:ep selector:@selector(addEmailWrapper:) object:email];
            [ops addObject:nextOp];
        }
    }
    
    [ep.operationQueue addOperations:ops waitUntilFinished:YES];
    
    self.cachedData = nil;
    
}

-(NSInteger) nextFolderToSync
{
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
    NSArray* folders = [AppSettings allFoldersNameforAccountIndex:self.currentAccountIndex];
    for (int indexFolder = 0; indexFolder < folders.count; indexFolder++) {
        if (![[[SyncManager getSingleton] retrieveState:indexFolder accountIndex:self.currentAccountIndex][@"fullsynced"] boolValue]) {
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
            [subscriber sendError:[NSError errorWithDomain:@"Connect" code:9000 userInfo:nil]];
        }
        
        NSInteger currentFolder = [AppSettings importantFolderNumforAccountIndex:self.currentAccountIndex forBaseFolder:FolderTypeAll];
        NSString* folderPath = [AppSettings folderServerName:currentFolder forAccountIndex:self.currentAccountIndex];
        MCOIMAPSearchExpression* expr = [MCOIMAPSearchExpression searchContent:text];
        MCOIMAPSearchOperation* so = [[ImapSync sharedServices:self.currentAccountIndex].imapSession searchExpressionOperationWithFolder:folderPath expression:expr];
        
        [so start:^(NSError* error, MCOIndexSet* searchResult) {
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
            
            if (![ImapSync sharedServices:self.currentAccountIndex].connected) {
                [subscriber sendError:[NSError errorWithDomain:@"Connect" code:9000 userInfo:nil]];
            }
            else {
                MCOIMAPFetchMessagesOperation* imapMessagesFetchOp = [[ImapSync sharedServices:self.currentAccountIndex].imapSession fetchMessagesOperationWithFolder:folderPath requestKind:requestKind uids:searchResult];
                [imapMessagesFetchOp start:^(NSError* error, NSArray* messages, MCOIndexSet* vanishedMessages){
                    
                    if (error) {
                        [subscriber sendError:error];
                        return;
                    }
                    
                    NSInteger __block count = messages.count;
                    
                    for (MCOIMAPMessage* msg in messages) {
                        
                        Email* email = [[Email alloc]init];
                        
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
                        
                        UidEntry* uid_entry = [[UidEntry alloc]init];
                        uid_entry.uid = msg.uid;
                        uid_entry.folder = currentFolder;
                        uid_entry.account = [AppSettings numForData:self.currentAccountIndex];
                        uid_entry.msgId = email.msgId;
                        uid_entry.dbNum = [EmailProcessor dbNumForDate:email.datetime];
                        
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
                        }
                        else {
                            uid_entry.sonMsgId = @"0";
                        }
                        
                        if ([email existsLocally]) {
                            
                            if (![email uidEWithFolder:uid_entry.folder]) {
                                // already have this email in other folder than this one -> add folder in uid_entry
                                
                                NSInvocationOperation* nextOp = [[NSInvocationOperation alloc] initWithTarget:[EmailProcessor getSingleton] selector:@selector(addToFolderWrapper:) object:uid_entry];
                                [[EmailProcessor getSingleton].operationQueue addOperation:nextOp];
                                
                                email.uids = [[NSMutableArray arrayWithArray:email.uids] arrayByAddingObject:uid_entry];
                                
                                [email loadBody];
                                
                            }
                            
                            [subscriber sendNext:email];
                            
                            --count;
                            
                            if (count == 0) {
                                [subscriber sendCompleted];
                            }
                            
                            continue;
                        }
                        
                        NSMutableArray* atts = [[NSMutableArray alloc] initWithCapacity:msg.attachments.count];
                        
                        for (MCOIMAPPart* part in msg.attachments) {
                            Attachment* at = [[Attachment alloc]init];
                            at.mimeType = part.mimeType;
                            at.msgId = email.msgId;
                            at.fileName = part.filename;
                            if ([at.fileName isEqualToString:@""]) {
                                at.fileName = [NSString stringWithFormat:@"No name - %@",email.subject];
                            }
                            at.partID = part.partID;
                            at.size = part.size;
                            at.contentID = @"";
                            [atts addObject:at];
                        }
                        
                        for (MCOIMAPPart* part in msg.htmlInlineAttachments) {
                            Attachment* at = [[Attachment alloc]init];
                            at.mimeType = part.mimeType;
                            at.msgId = email.msgId;
                            at.fileName = part.filename;
                            if ([at.fileName isEqualToString:@""]) {
                                at.fileName = part.contentID;
                            }
                            at.partID = part.partID;
                            at.size = part.size;
                            at.contentID = part.contentID;
                            [atts addObject:at];
                        }
                        
                        email.attachments = atts;
                        
                        email.uids = @[uid_entry];
                        
                        email.body = @"";
                        email.htmlBody = @"";
                        
                        NSInvocationOperation* nextOp = [[NSInvocationOperation alloc] initWithTarget:[EmailProcessor getSingleton] selector:@selector(addEmailWrapper:) object:email];
                        [[EmailProcessor getSingleton].operationQueue addOperation:nextOp];
                        
                        [subscriber sendNext:email];
                        
                        --count;
                        
                        if (count == 0) {
                            [subscriber sendCompleted];
                            //CCMLog(@"Complete sent");
                        }
                        
                        [[[ImapSync sharedServices:self.currentAccountIndex].imapSession plainTextBodyRenderingOperationWithMessage:msg folder:folderPath stripWhitespace:NO] start:^(NSString* plainTextBodyString, NSError* error) {
                            if (plainTextBodyString) {
                                plainTextBodyString = [plainTextBodyString stringByReplacingCharactersInRange:NSMakeRange(0, 1) withString:@""];
                                
                                email.body = plainTextBodyString;
                            }
                            else {
                                email.body = @"";
                            }
                            
                            NSInvocationOperation* nextOp = [[NSInvocationOperation alloc] initWithTarget:[EmailProcessor getSingleton] selector:@selector(updateEmailWrapper:) object:email];
                            [[EmailProcessor getSingleton].operationQueue addOperation:nextOp];
                            
                            /*[[[ImapSync sharedServices:self.currentAccountIndex].imapSession htmlBodyRenderingOperationWithMessage:msg folder:folderPath] start:^(NSString* htmlString, NSError* error) {
                             email.htmlBody = htmlString;
                             
                             
                             }];*/
                        }];
                    }
                }];
            }
        }];
        
        return [RACDisposable disposableWithBlock:^{}];
    }];
}

-(RACSignal*) runSearchPerson:(Person*)person
{
    @weakify(self);
    
    return [RACSignal createSignal:^RACDisposable* (id<RACSubscriber> subscriber) {
        @strongify(self);
        
        if (![ImapSync isNetworkAvailable]) {
            [subscriber sendError:[NSError errorWithDomain:@"Connect" code:9000 userInfo:nil]];
        }
        
        NSInteger currentFolder = [AppSettings importantFolderNumforAccountIndex:self.currentAccountIndex forBaseFolder:FolderTypeAll];
        NSString* folder = [AppSettings folderServerName:currentFolder forAccountIndex:self.currentAccountIndex];
        MCOIMAPSearchExpression* expr = [MCOIMAPSearchExpression searchRecipient:person.email];
        MCOIMAPSearchOperation* so = [[ImapSync sharedServices:self.currentAccountIndex].imapSession searchExpressionOperationWithFolder:folder expression:expr];
        
        [so start:^(NSError* error, MCOIndexSet* searchResult) {
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
            
            if (![ImapSync sharedServices:self.currentAccountIndex].connected) {
                [subscriber sendError:[NSError errorWithDomain:@"Connect" code:9000 userInfo:nil]];
            }
            else {
                MCOIMAPFetchMessagesOperation* imapMessagesFetchOp = [[ImapSync sharedServices:self.currentAccountIndex].imapSession fetchMessagesOperationWithFolder:folder requestKind:requestKind uids:searchResult];
                [imapMessagesFetchOp start:^(NSError* error, NSArray* messages, MCOIndexSet* vanishedMessages){
                    
                    if (error) {
                        [subscriber sendError:error];
                        return;
                    }
                    
                    NSInteger __block count = messages.count;
                    
                    for (MCOIMAPMessage* msg in messages) {
                        
                        NSMutableDictionary* folderState = [[SyncManager getSingleton] retrieveState:currentFolder accountIndex:self.currentAccountIndex];
                        NSString* folderPath = folderState[@"folderPath"];
                        
                        Email* email = [[Email alloc]init];
                        
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
                        
                        UidEntry* uid_entry = [[UidEntry alloc]init];
                        uid_entry.uid = msg.uid;
                        uid_entry.folder = currentFolder;
                        uid_entry.account = [AppSettings numForData:self.currentAccountIndex];
                        uid_entry.msgId = email.msgId;
                        uid_entry.dbNum = [EmailProcessor dbNumForDate:email.datetime];
                        
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
                        }
                        else {
                            uid_entry.sonMsgId = @"0";
                        }
                        
                        if ([email existsLocally]) {
                            
                            if (![email uidEWithFolder:uid_entry.folder]) {
                                // already have this email in other folder than this one -> add folder in uid_entry
                                
                                NSInvocationOperation* nextOp = [[NSInvocationOperation alloc] initWithTarget:[EmailProcessor getSingleton] selector:@selector(addToFolderWrapper:) object:uid_entry];
                                [[EmailProcessor getSingleton].operationQueue addOperation:nextOp];
                                
                                email.uids = [[NSMutableArray arrayWithArray:email.uids] arrayByAddingObject:uid_entry];
                                
                                [email loadBody];
                                [subscriber sendNext:email];
                                
                                --count;
                                
                                if (count == 0) {
                                    [subscriber sendCompleted];
                                }
                                
                                continue;
                            }
                            --count;
                            
                            if (count == 0) {
                                [subscriber sendCompleted];
                            }
                            //We already have email with folder
                            continue;
                        }
                        
                        NSMutableArray* atts = [[NSMutableArray alloc] initWithCapacity:msg.attachments.count];
                        
                        for (MCOIMAPPart* part in msg.attachments) {
                            Attachment* at = [[Attachment alloc]init];
                            at.mimeType = part.mimeType;
                            at.msgId = email.msgId;
                            at.fileName = part.filename;
                            if ([at.fileName isEqualToString:@""]) {
                                at.fileName = [NSString stringWithFormat:@"No name - %@",email.subject];
                            }
                            at.partID = part.partID;
                            at.size = part.size;
                            at.contentID = @"";
                            [atts addObject:at];
                        }
                        
                        for (MCOIMAPPart* part in msg.htmlInlineAttachments) {
                            Attachment* at = [[Attachment alloc]init];
                            at.mimeType = part.mimeType;
                            at.msgId = email.msgId;
                            at.fileName = part.filename;
                            if ([at.fileName isEqualToString:@""]) {
                                at.fileName = part.contentID;
                            }
                            at.partID = part.partID;
                            at.size = part.size;
                            at.contentID = part.contentID;
                            [atts addObject:at];
                        }
                        
                        email.attachments = atts;
                        
                        email.uids = @[uid_entry];
                        
                        [[[ImapSync sharedServices:self.currentAccountIndex].imapSession plainTextBodyRenderingOperationWithMessage:msg folder:folderPath stripWhitespace:NO] start:^(NSString* plainTextBodyString, NSError* error) {
                            if (plainTextBodyString) {
                                plainTextBodyString = [plainTextBodyString stringByReplacingCharactersInRange:NSMakeRange(0, 1) withString:@""];
                                
                                email.body = plainTextBodyString;
                            }
                            else {
                                email.body = @"";
                            }
                            
                            [[[ImapSync sharedServices:self.currentAccountIndex].imapSession htmlBodyRenderingOperationWithMessage:msg folder:folderPath] start:^(NSString* htmlString, NSError* error) {
                                email.htmlBody = htmlString;
                                
                                NSInvocationOperation* nextOp = [[NSInvocationOperation alloc] initWithTarget:[EmailProcessor getSingleton] selector:@selector(addEmailWrapper:) object:email];
                                [[EmailProcessor getSingleton].operationQueue addOperation:nextOp];
                                
                                [subscriber sendNext:email];
                                
                                --count;
                                
                                if (count == 0) {
                                    [subscriber sendCompleted];
                                }
                            }];
                        }];
                    }
                }];
            }
        }];
        
        return [RACDisposable disposableWithBlock:^{}];
    }];
}

-(void) checkFolders
{
    MCOIMAPFetchFoldersOperation* fio = [[ImapSync sharedServices:self.currentAccountIndex].imapSession fetchAllFoldersOperation];
    [fio start:^(NSError* error, NSArray* folders) {
        if (!error && !folders && folders.count > 0) {
            SyncManager* sm = [SyncManager getSingleton];
            
            int indexPath = 0;
            
            NSMutableArray* dispNamesFolders = [[NSMutableArray alloc] initWithCapacity:1];
            
            for (MCOIMAPFolder* folder in folders) {
                BOOL exists = NO;
                
                int i = 0;
                
                while (i < [sm folderCount:self.currentAccountIndex]) {
                    NSDictionary* folderState = [sm retrieveState:i accountIndex:self.currentAccountIndex];
                    NSString* folderPath = folderState[@"folderPath"];
                    
                    if ([[folder path] isEqualToString:folderPath]) {
                        exists = YES;
                        break;
                    }
                    
                    i++;
                }
                
                if (!exists) {
                    NSString* dispName = [[[[ImapSync sharedServices:self.currentAccountIndex].imapSession defaultNamespace] componentsFromPath:[folder path]] componentsJoinedByString:@"/"];
                    [dispNamesFolders addObject:dispName];
                    
                    NSDictionary* folderState = @{ @"accountNum" : @(self.currentAccountIndex),
                                                   @"folderDisplayName":dispName,
                                                   @"folderPath":folder.path,
                                                   @"deleted":@false,
                                                   @"fullsynced":@false,
                                                   @"lastended":@0,
                                                   @"flags":@(folder.flags),
                                                   @"emailCount":@(0)};
                    
                    [sm addFolderState:folderState accountIndex:self.currentAccountIndex];
                    
                    MCOIMAPFolderInfoOperation* folderOp = [[ImapSync sharedServices:self.currentAccountIndex].imapSession folderInfoOperation:folder.path];
                    [folderOp start:^(NSError* error, MCOIMAPFolderInfo* info) {
                        if (!error) {
                            NSMutableDictionary* syncState = [sm retrieveState:indexPath accountIndex:self.currentAccountIndex];
                            syncState[@"emailCount"] = @([info messageCount]);
                            [sm persistState:syncState forFolderNum:indexPath accountIndex:self.currentAccountIndex];
                        }
                    }];
                }
                
                indexPath++;
            }
            
            [AppSettings setFoldersName:dispNamesFolders forAccountIndex:self.currentAccountIndex];
        }
    }];
}

-(RACSignal*) runFolder:(NSInteger)folder fromStart:(BOOL)isFromStart fromAccount:(BOOL)getAll
{
    BOOL isInBackground = UIApplicationStateBackground == [UIApplication sharedApplication].applicationState;
    
    if (folder == -1) {
        folder = [self nextFolderToSync];
    }
    
    NSInteger currentFolder = folder;
    
    /*if (currentFolder != -1) {
     CCMLog(@"Syncing folder(%ld) %@ in account %@",(long)currentFolder, [AppSettings folderName:currentFolder forAccount:self.currentAccount],[AppSettings username:self.currentAccount]);
     }*/
    
    if (!self.cachedData) {
        self.cachedData = [[NSMutableArray alloc]initWithCapacity:1];
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
    
    return [RACSignal startLazilyWithScheduler:[RACScheduler schedulerWithPriority:RACSchedulerPriorityBackground] block:^(id<RACSubscriber> subscriber) {
        @strongify(self);
        // get list of all folders
        
        if (self.isCanceled) {
            [subscriber sendCompleted];
        }
        else if (![ImapSync isNetworkAvailable]) {
            [subscriber sendError:[NSError errorWithDomain:@"Connect" code:9000 userInfo:nil]];
        }
        else if (currentFolder == -1) {
            [subscriber sendError:[NSError errorWithDomain:@"All synced" code:9001 userInfo:nil]];
        }
        else if (isInBackground && currentFolder != [AppSettings importantFolderNumforAccountIndex:self.currentAccountIndex forBaseFolder:FolderTypeInbox]) {
            [subscriber sendCompleted];
        }
        else {
            [[ImapSync doLogin:self.currentAccountIndex] subscribeError:^(NSError *error) {
                CCMLog(@"connection error");
            } completed:^{
                if (![ImapSync sharedServices:self.currentAccountIndex].connected) {
                    if (isInBackground) {
                        [subscriber sendCompleted];
                    }
                    else {
                        [subscriber sendError:[NSError errorWithDomain:@"Connect" code:9000 userInfo:nil]];
                    }
                }
                else {
                    MCOIMAPFetchFoldersOperation* fio = [[ImapSync sharedServices:self.currentAccountIndex].imapSession fetchAllFoldersOperation];
                    [fio start:^(NSError* error, NSArray* folders) {
                        if (error) {
                            [subscriber sendError:error];
                            
                            return;
                        }
                        else if (!folders || folders.count == 0) {
                            [subscriber sendCompleted];
                            
                            return;
                        }//Fetch folder issue
                        SyncManager* sm = [SyncManager getSingleton];
                        EmailProcessor* emailProcessor = [EmailProcessor getSingleton];
                        // mark folders that were deleted on the server as deleted on the client
                        int i = 0;
                        
                        while (i < [sm folderCount:self.currentAccountIndex]) {
                            NSDictionary* folderState = [sm retrieveState:i accountIndex:self.currentAccountIndex];
                            NSString* folderPath = folderState[@"folderPath"];
                            
                            if ([sm isFolderDeleted:i accountIndex:self.currentAccountIndex]) {
                                CCMLog(@"Folder is deleted: %i %ld", i, (long)self.currentAccountIndex);
                            }
                            
                            if (![sm isFolderDeleted:i accountIndex:self.currentAccountIndex] && ![[folders valueForKey:@"path"] containsObject:folderPath]) {
                                CCMLog(@"Folder %@ has been deleted - deleting FolderState", folderPath);
                                [sm markFolderDeleted:i accountIndex:self.currentAccountIndex];
                                i = 0;
                            }
                            
                            i++;
                        }
                        
                        NSMutableDictionary* folderState = [sm retrieveState:currentFolder accountIndex:self.currentAccountIndex];
                        NSString* folderPath = folderState[@"folderPath"];
                        
                        MCOIMAPFolderInfoOperation* folder = [[ImapSync sharedServices:self.currentAccountIndex].imapSession folderInfoOperation:folderPath];
                        NSInteger lastEnded = [folderState[@"lastended"] integerValue];
                        
                        [folder start:^(NSError* error, MCOIMAPFolderInfo* info) {
                            if (error) {
                                [subscriber sendError:error];
                                return;
                            }
                            if (self.isCanceled) {
                                [subscriber sendCompleted];
                                return;
                            }
                            
                            int batchsize = 20;
                            
                            //if (!isFromStart) {
                            batchsize = 50;
                            //}
                            
                            if (!isInBackground) {
                                [self writeFinishedFolderState:sm emailCount:[info messageCount] withAccountIndex:self.currentAccountIndex andFolder:currentFolder];
                                
                                if ([info messageCount] == 0 || (!isFromStart && (lastEnded == 1))) {
                                    NSInteger lE = ([info messageCount] == 0)?1:lastEnded;
                                    [self writeFinishedFolderState:sm lastEnded:lE withAccountIndex:self.currentAccountIndex andFolder:currentFolder];
                                    
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
                            
                            if (!isFromStart) {
                                //CCMLog(@"Account:%ld Folder:%@ %ld%% complete fetching %ld to %llu of %u", (long)self.currentAccountIndex, folderPath,(long)(100 - ((from - 1)*  100) / [info messageCount]), (long)(from), (from + batch), [info messageCount]);
                            }
                            else {
                                //CCMLog(@"Account:%ld Folder:%@ refreshing from %ld", (long)self.currentAccountIndex, folderPath, (long)(from));
                            }
                            
                            MCOIndexSet* numbers = [MCOIndexSet indexSetWithRange:MCORangeMake(from, batch)];
                            MCOIMAPFetchMessagesOperation* imapMessagesFetchOp = [[ImapSync sharedServices:self.currentAccountIndex].imapSession fetchMessagesByNumberOperationWithFolder:folderPath requestKind:requestKind numbers:numbers];
                            [imapMessagesFetchOp start:^(NSError* error, NSArray* messages, MCOIndexSet* vanishedMessages){
                                if (error) {
                                    [subscriber sendError:error];
                                    return;
                                }
                                NSInteger __block count = messages.count;
                                
                                for (MCOIMAPMessage* msg in messages) {
                                    if (self.isCanceled) {
                                        [subscriber sendCompleted];
                                        return;
                                    }
                                    
                                    NSMutableDictionary* folderState = [sm retrieveState:currentFolder accountIndex:self.currentAccountIndex];
                                    NSString* folderPath = folderState[@"folderPath"];
                                    
                                    Email* email = [[Email alloc]init];
                                    
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
                                    UidEntry* uid_entry = [[UidEntry alloc]init];
                                    uid_entry.uid = msg.uid;
                                    uid_entry.folder = currentFolder;
                                    uid_entry.account = email.accountNum;
                                    uid_entry.msgId = email.msgId;
                                    uid_entry.dbNum = [EmailProcessor dbNumForDate:email.datetime];
                                    
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
                                    }
                                    else {
                                        uid_entry.sonMsgId = @"0";
                                    }
                                    
                                    if ([email existsLocally]) {
                                        
                                        if (![email uidEWithFolder:uid_entry.folder]) {
                                            // already have this email in other folder than this one -> add folder in uid_entry
                                            
                                            email.uids = [[NSMutableArray arrayWithArray:email.uids] arrayByAddingObject:uid_entry];
                                            
                                            NSInvocationOperation* nextOp = [[NSInvocationOperation alloc] initWithTarget:emailProcessor selector:@selector(addToFolderWrapper:) object:uid_entry];
                                            
                                            nextOp.completionBlock = ^{
                                                if ((currentFolder == [Accounts sharedInstance].currentAccount.currentFolderIdx) | getAll) {
                                                    [email loadBody];
                                                    [subscriber sendNext:email];
                                                }
                                            };
                                            
                                            [emailProcessor.operationQueue addOperation:nextOp];
                                            
                                            --count;
                                            
                                            if (count == 0) {
                                                if (!isFromStart && !isInBackground) {
                                                    [self writeFinishedFolderState:sm lastEnded:from withAccountIndex:self.currentAccountIndex andFolder:currentFolder];
                                                }
                                                [subscriber sendCompleted];
                                            }
                                            continue;
                                        }
                                        --count;
                                        
                                        if (count == 0) {
                                            if (!isFromStart && !isInBackground) {
                                                [self writeFinishedFolderState:sm lastEnded:from withAccountIndex:self.currentAccountIndex andFolder:currentFolder];
                                            }
                                            [subscriber sendCompleted];
                                        }
                                        //We already have email with folder
                                        continue;
                                    }
                                    
                                    NSMutableArray* atts = [[NSMutableArray alloc] initWithCapacity:msg.attachments.count + msg.htmlInlineAttachments.count];
                                    
                                    for (MCOAbstractPart* part in msg.attachments) {
                                        if([part isKindOfClass:[MCOIMAPPart class]]) {
                                            MCOIMAPPart* imapPart = (MCOIMAPPart*)part;
                                            
                                            Attachment* at = [[Attachment alloc]init];
                                            at.mimeType = part.mimeType;
                                            at.msgId = email.msgId;
                                            at.fileName = part.filename;
                                            if ([at.fileName isEqualToString:@""]) {
                                                at.fileName = [NSString stringWithFormat:@"No name - %@",email.subject];
                                            }
                                            at.partID = imapPart.partID;
                                            at.size = imapPart.size;
                                            at.contentID = @"";
                                            [atts addObject:at];
                                        }
                                        else if([part isKindOfClass:[MCOIMAPMultipart class]]) {
                                            MCOIMAPMultipart* imapParts = (MCOIMAPMultipart*)part;
                                            
                                            NSMutableString* string = [NSMutableString new];
                                            
                                            for (MCOIMAPPart* imapPart in imapParts.parts) {
                                                [string appendString:imapPart.filename];
                                            }
                                            
                                            [Instabug reportBugWithComment:[NSString stringWithFormat:@"The inline attachment in msg is Multipart %lu, subject:%@; parts:%@", (long)imapParts.partType ,msg.header.subject, string] screenshot:nil];                                        }
                                    }
                                    
                                    for (MCOAbstractPart* part in msg.htmlInlineAttachments) {
                                        if([part isKindOfClass:[MCOIMAPPart class]]) {
                                            MCOIMAPPart* imapPart = (MCOIMAPPart*)part;
                                            
                                            Attachment* at = [[Attachment alloc]init];
                                            at.mimeType = part.mimeType;
                                            at.msgId = email.msgId;
                                            at.fileName = part.filename;
                                            if ([at.fileName isEqualToString:@""]) {
                                                at.fileName = part.contentID;
                                            }
                                            at.partID = imapPart.partID;
                                            at.size = imapPart.size;
                                            at.contentID = part.contentID;
                                            [atts addObject:at];
                                        }
                                        else if([part isKindOfClass:[MCOIMAPMultipart class]]) {
                                            MCOIMAPMultipart* imapParts = (MCOIMAPMultipart*)part;
                                            
                                            NSMutableString* string = [NSMutableString new];
                                            
                                            for (MCOIMAPPart* imapPart in imapParts.parts) {
                                                [string appendString:imapPart.filename];
                                            }
                                            
                                            [Instabug reportBugWithComment:[NSString stringWithFormat:@"The inline attachment in msg is Multipart %lu, subject:%@; parts:%@", (long)imapParts.partType ,msg.header.subject, string] screenshot:nil];
                                        }
                                    }
                                    
                                    email.attachments = atts;
                                    
                                    email.uids = @[uid_entry];
                                    
                                    [[[ImapSync sharedServices:self.currentAccountIndex].imapSession plainTextBodyRenderingOperationWithMessage:msg folder:folderPath stripWhitespace:NO] start:^(NSString* plainTextBodyString, NSError* error) {
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
                                            --count;
                                            
                                            if (count == 0) {
                                                if (!isFromStart && !isInBackground) {
                                                    [self writeFinishedFolderState:sm lastEnded:from withAccountIndex:self.currentAccountIndex andFolder:currentFolder];
                                                }
                                                [subscriber sendCompleted];
                                            }
                                        }
                                        else {
                                            [[[ImapSync sharedServices:self.currentAccountIndex].imapSession htmlBodyRenderingOperationWithMessage:msg folder:folderPath] start:^(NSString* htmlString, NSError* error) {
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
                                                --count;
                                                
                                                if (count == 0) {
                                                    if (!isFromStart && !isInBackground) {
                                                        [self writeFinishedFolderState:sm lastEnded:from withAccountIndex:self.currentAccountIndex andFolder:currentFolder];
                                                    }
                                                    [subscriber sendCompleted];
                                                }
                                            }];
                                        }
                                    }];
                                }
                            }];//Fetch Messages
                        }];//Fetch folder Info
                    }];//Fetch All Folders
                }
            }];
        }
    }];
}

-(BOOL) _saveEmail:(Email*)email inBackground:(BOOL)isInBackground folder:(NSInteger)currentFolder
{
    //Cache email if in Background
    if (isInBackground) {
        
        BOOL isInInbox = (currentFolder == [AppSettings importantFolderNumforAccountIndex:self.currentAccountIndex forBaseFolder:FolderTypeInbox]);
        BOOL isUnread = !(email.flag & MCOMessageFlagSeen);
        
        if (isInInbox & isUnread) {
            NSMutableSet* eIds = [self emailIDs];
            if (![eIds containsObject:email.msgId]) {
                Email* newE = [email copy];
                CCMLog(@"Had Cached %ld Emails in account:%ld", (unsigned long)eIds.count, (long)[email.uids[0] account]);
                
                [self.cachedData addObject:newE];
                [eIds addObject:newE.msgId];
                [AppSettings setCache:eIds];
                
                NSInvocationOperation* nextOp = [[NSInvocationOperation alloc] initWithTarget:[EmailProcessor getSingleton] selector:@selector(addToFolderWrapper:) object:newE.uids[0]];
                [[EmailProcessor getSingleton].operationQueue addOperation:nextOp];
                [[EmailProcessor getSingleton].operationQueue waitUntilAllOperationsAreFinished];
                
                Conversation* conv = [[Conversation alloc] init];
                [conv addMail:[Mail mail:email]];
                NSUInteger index = [[[Accounts sharedInstance] getAccount:[AppSettings indexForAccount:email.accountNum]] addConversation:conv];
                
                BOOL isUnread = !(email.flag & MCOMessageFlagSeen);
                
                if (isUnread && [AppSettings notifications:self.currentAccountIndex]) {
                    UILocalNotification* localNotification = [[UILocalNotification alloc] init];
                    localNotification.fireDate = [NSDate dateWithTimeIntervalSinceNow:10];
                    NSString* alertText = [[NSString alloc]initWithFormat:@"%@\n%@%@", email.sender.displayName, (email.hasAttachments?@"📎 ":@""), email.subject];
                    alertText = [alertText stringByReplacingOccurrencesOfString:@"%" withString:@"%%"];
                    localNotification.alertBody = alertText;
                    localNotification.timeZone = [NSTimeZone defaultTimeZone];
                    localNotification.userInfo = @{@"index":@(index),
                                                   @"accountNum":@(email.accountNum)};
                    localNotification.category = @"MAIL_CATEGORY";
                    
                    [[UIApplication sharedApplication] presentLocalNotificationNow:localNotification];
                }
                
                return YES;
            }
        }
    } else {
        NSInvocationOperation* nextOp = [[NSInvocationOperation alloc] initWithTarget:[EmailProcessor getSingleton] selector:@selector(addEmailWrapper:) object:email];
        
        [[EmailProcessor getSingleton].operationQueue addOperation:nextOp];
        [[EmailProcessor getSingleton].operationQueue waitUntilAllOperationsAreFinished];
    }
    
    return NO;
}

-(NSMutableSet *) emailIDs
{
    return [NSMutableSet setWithArray:[AppSettings cache]];
}

-(void) writeFinishedFolderState:(SyncManager*)sm emailCount:(NSInteger)count withAccountIndex:(NSInteger)accountIndex andFolder:(NSInteger)folder
{
    if (![AppSettings isAccountDeleted:accountIndex]) {
        
        // used by fetchFrom to write the finished state for this round of syncing to disk
        NSMutableDictionary* syncState = [sm retrieveState:folder accountIndex:accountIndex];
        syncState[@"emailCount"] = @(count);
        
        [sm persistState:syncState forFolderNum:folder accountIndex:accountIndex];
    }
}

-(void) writeFinishedFolderState:(SyncManager*)sm lastEnded:(NSInteger)lastEIndex withAccountIndex:(NSInteger)accountIndex andFolder:(NSInteger)folder
{
    // used by fetchFrom to write the finished state for this round of syncing to disk
    if (![AppSettings isAccountDeleted:accountIndex]) {
        NSMutableDictionary* syncState = [sm retrieveState:folder accountIndex:accountIndex];
        syncState[@"lastended"] = @(lastEIndex);
        syncState[@"fullsynced"] = @(lastEIndex == 1);
        
        [sm persistState:syncState forFolderNum:folder accountIndex:accountIndex];
        [[[Accounts sharedInstance] getAccount:accountIndex] showProgress];
    }
}

-(void) runUpToDateCachedTest:(NSArray*)emails
{
    MCOIndexSet* uidsIS = [[MCOIndexSet alloc]init];
    NSString* path = [AppSettings folderServerName:[[Accounts sharedInstance].currentAccount currentFolderIdx] forAccountIndex:self.currentAccountIndex];
    
    NSMutableArray* datas = [[NSMutableArray alloc]init];
    
    for (Email* email in emails) {
        //TODO: Get the right uid corresponding to the message id and folder
        
        UidEntry* uid_entry = [UidEntry getUidEntryWithFolder:[[Accounts sharedInstance].currentAccount currentFolderIdx] msgId:email.msgId];
        [uidsIS addIndex:uid_entry.uid];
        
        NSMutableDictionary* dict = [NSMutableDictionary dictionary];
        dict[@"email"] = email;
        dict[@"uid_entry"] = uid_entry;
        [datas addObject:dict];
    }
    
    if (!self.connected){
        return;
    }
    
    MCOIMAPFetchMessagesOperation* op = [[ImapSync sharedServices:self.currentAccountIndex].imapSession  fetchMessagesOperationWithFolder:path requestKind:MCOIMAPMessagesRequestKindFlags uids:uidsIS];
    
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
            Email* email = data[@"email"];
            
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
    return;
}

-(void) runUpToDateTest:(NSArray*)convs folderIndex:(NSInteger)folderIdx completed:(void (^)(NSArray* dels, NSArray* ups))completedBlock
{
    MCOIndexSet* uidsIS = [[MCOIndexSet alloc]init];
    NSString* path = [AppSettings folderServerName:folderIdx forAccountIndex:self.currentAccountIndex];
    
    NSMutableArray* emails = [NSMutableArray arrayWithCapacity:convs.count];
    
    for (Conversation* conv in convs) {
        for (Mail* mail in conv.mails) {
            if ([mail.email uidEWithFolder:folderIdx]) {
                [uidsIS addIndex:[mail.email uidEWithFolder:folderIdx].uid];
                [emails addObject:mail.email];
            }
        }
    }
    
    CCMLog(@"Testing folder %@ with %i emails in accountIndex:%ld", path, uidsIS.count, (long)self.currentAccountIndex);
    
    if (uidsIS.count == 0) {
        completedBlock(nil, nil);
        return;
    }
    
    NSMutableArray* delDatas = [[NSMutableArray alloc]init];
    NSMutableArray* upDatas = [[NSMutableArray alloc]init];
    
    [[ImapSync doLogin:self.currentAccountIndex]
     subscribeError:^(NSError *error) {
         completedBlock(delDatas, upDatas);
     } completed:^{
         
         if (!self.connected){
             completedBlock(delDatas, upDatas);
             return;
         }
         
         MCOIMAPFetchMessagesOperation* op = [self.imapSession fetchMessagesOperationWithFolder:path requestKind:MCOIMAPMessagesRequestKindHeaders | MCOIMAPMessagesRequestKindFlags uids:uidsIS];
         
         [op start:^(NSError* error, NSArray* messages, MCOIndexSet* vanishedMessages) {
             
             if (error) {
                 CCMLog(@"error testing emails in %@, %@", path, error);
                 completedBlock(delDatas, upDatas);
                 return;
             }
             
             
             
             CCMLog(@"Connected and Testing folder %@ in accountIndex:%ld", path, (long)self.currentAccountIndex);
             
             EmailProcessor* ep = [EmailProcessor getSingleton];
             
             for (MCOIMAPMessage* msg in messages) {
                 //If in this folder or cross check in other folder
                 if ([uidsIS containsIndex:msg.uid]) {
                     //Don't Delete
                     [uidsIS removeIndex:msg.uid];
                 }
             }
             
             for (Email* email in emails) {
                 UidEntry* uid_entry = [email uidEWithFolder:folderIdx];
                 
                 if ([uidsIS containsIndex:uid_entry.uid]) {
                     //Remove email from local folder
                     [delDatas addObject:email];
                 }
                 else {
                     for (MCOIMAPMessage* msg in messages) {
                         if (msg.uid == uid_entry.uid && msg.flags != email.flag) {
                             email.flag = msg.flags;
                             [upDatas addObject:email];
                         }
                     }
                 }
             }
             
             if (delDatas.count > 0) {
                 CCMLog(@"Delete %lu emails", (unsigned long)delDatas.count);
                 NSDictionary* data = [[NSDictionary alloc]initWithObjects:@[delDatas,@(folderIdx)] forKeys:@[@"datas",@"folderIdx"]];
                 NSInvocationOperation* nextOp = [[NSInvocationOperation alloc] initWithTarget:ep selector:@selector(removeFromFolderWrapper:) object:data];
                 [ep.operationQueue addOperation:nextOp];
             }
             
             if (upDatas.count > 0) {
                 CCMLog(@"Update %lu emails", (unsigned long)upDatas.count);
                 NSInvocationOperation* nextOp = [[NSInvocationOperation alloc] initWithTarget:ep selector:@selector(updateFlag:) object:upDatas];
                 [ep.operationQueue addOperation:nextOp];
             }
             
             completedBlock(delDatas, upDatas);
         }];
     }];
    return;
}

-(void) checkForCachedActions
{
    NSMutableArray* cachedActions = [CachedAction getActionsForAccount:[AppSettings numForData:self.currentAccountIndex]];
    
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
    
    return [AppSettings canSyncOverData] || (networkStatus == ReachableViaWiFi);
}

+(void) runInboxUnread:(NSInteger)accountIndex
{
    if (![ImapSync isNetworkAvailable] | ([Accounts sharedInstance].accountsCount == accountIndex)) {
        return;
    }
    
    NSInteger currentFolder = [AppSettings importantFolderNumforAccountIndex:accountIndex forBaseFolder:FolderTypeInbox];
    NSString* folder = [AppSettings folderServerName:currentFolder forAccountIndex:accountIndex];
    MCOIMAPSearchExpression* expr = [MCOIMAPSearchExpression searchUnread];
    MCOIMAPSearchOperation* so = [[ImapSync sharedServices:accountIndex].imapSession searchExpressionOperationWithFolder:folder expression:expr];
    
    [so start:^(NSError* error, MCOIndexSet* searchResult) {
        if (!error) {
            [AppSettings setInboxUnread:searchResult.count accountIndex:accountIndex];
        }
    }];
}



@end
