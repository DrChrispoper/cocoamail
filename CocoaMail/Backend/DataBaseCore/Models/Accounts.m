//
//  Accounts.m
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 11/08/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "Accounts.h"
#import "AppSettings.h"
#import "Mail.h"
#import "Reachability.h"
#import "SyncManager.h"
#import "SearchRunner.h"
#import "ImapSync.h"

@interface Account ()

@property (nonatomic, strong) NSMutableArray* allsMails;
@property (nonatomic, strong) NSMutableSet * convIDs;

@property (nonatomic, strong) NSArray* userFoldersContent;
@property (nonatomic, strong) NSArray* systemFoldersContent;

@property (nonatomic, strong) NSMutableArray* drafts;

@property (nonatomic, retain) NSOperationQueue *localFetchQueue;

@end


@implementation Accounts

+(Accounts*) sharedInstance
{
    static dispatch_once_t once;
    static Accounts* sharedInstance;
    
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
        sharedInstance.quickSwipeType = QuickSwipeReply;
        
        sharedInstance.accountColors = @[[UIColor colorWithRed:0.01f green:0.49f blue:1.f alpha:1.f],
                                         [UIColor colorWithRed:0.44f green:0.02f blue:1.f alpha:1.f],
                                         [UIColor colorWithRed:1.f green:0.01f blue:0.87f alpha:1.f],
                                         [UIColor colorWithRed:1.f green:0.07f blue:0.01f alpha:1.f],
                                         [UIColor colorWithRed:1.f green:0.49f blue:0.01f alpha:1.f],
                                         [UIColor colorWithRed:0.96f green:0.72f blue:0.02f alpha:1.f],
                                         [UIColor colorWithRed:0.07f green:0.71f blue:0.02f alpha:1.f]];
        
        NSMutableArray *accounts = [[NSMutableArray alloc]initWithCapacity:[AppSettings numActiveAccounts]];
        
        if([AppSettings numActiveAccounts] > 0){
            
            for (int i = 0; i < [AppSettings numActiveAccounts]; i++) {
                NSInteger accountIndex = [AppSettings numAccountForIndex:i];
                Account* a = [self _createAccountMail:[AppSettings username:accountIndex]
                                                color:sharedInstance.accountColors[accountIndex]
                                                 code:[AppSettings initials:accountIndex]
                                                  idx:i];

                [accounts addObject:a];
            }
        }
        
        Account* all = [self _createAllAccountsFrom:accounts];
        [accounts addObject:all];

        sharedInstance.accounts = accounts;
    });
    return sharedInstance;    
}


+(Account*) _createAccountMail:(NSString*)mail color:(UIColor*)color code:(NSString*)code idx:(NSInteger)idx
{
    Account* ac = [Account emptyAccount];
    ac.userMail = mail;
    ac.userColor = color;
    ac.codeName = code;
    ac.idx = idx;
    
    ac.currentFolder = FolderTypeWith(FolderTypeInbox,0);
    
    //Folders Indentation?
    NSArray* tmpFolders = [AppSettings allNonImportantFoldersName:ac.accountNum];
    NSMutableArray* foldersNIndent = [[NSMutableArray alloc]initWithCapacity:tmpFolders.count];
    for (NSString* folderNames in tmpFolders) {
        [foldersNIndent addObject:@[folderNames,@([folderNames containsString:@"]/"])]];
    }
    ac.userFolders = foldersNIndent;
    
    ac.person = [Person createWithName:mail email:ac.userMail icon:nil codeName:code];
    [ac.person linkToAccount:ac];
    [[Persons sharedInstance] registerPersonWithNegativeID:ac.person];
    
    return ac;
}

+(Account*) _createAllAccountsFrom:(NSArray*)accounts
{
    Account* ac = [[Account alloc] init];
    ac.userMail = NSLocalizedString(@"All accounts", @"All accounts");
    ac.userColor = [UIColor blackColor];
    ac.isAllAccounts = YES;
    
    NSMutableArray* userfolders = [NSMutableArray arrayWithCapacity:50];
    for (Account* a in accounts) {
        [userfolders addObjectsFromArray:a.userFolders];
    }
    
    ac.userFolders = userfolders;
    ac.person = [Person createWithName:nil email:nil icon:nil codeName:@"ALL"];
    
    return ac;
}

-(BOOL) deleteAccount:(Account*)account
{
    NSMutableArray* tmp = [self.accounts mutableCopy];
    NSInteger removeIdx = [tmp indexOfObject:account];
    
    if (removeIdx != NSNotFound) {
        [tmp removeObjectAtIndex:removeIdx];
        self.accounts = tmp;
        
        if (self.currentAccountIdx >= removeIdx && self.currentAccountIdx>0) {
            self.currentAccountIdx--;
        }
        
        if (self.defaultAccountIdx >= removeIdx && self.defaultAccountIdx>0) {
            self.defaultAccountIdx--;
        }
        
        return YES;
    }
    
    return NO;
}


-(void) addAccount:(Account*)account
{
    [[Persons sharedInstance] registerPersonWithNegativeID:account.person];
    [account.person linkToAccount:account];
    
    NSInteger currentIdx = self.currentAccountIdx;
    NSMutableArray* tmp = [self.accounts mutableCopy];
    NSInteger putIdx = tmp.count - 1;
    
    [tmp insertObject:account atIndex:putIdx];
    self.accounts = tmp;
    
    if (putIdx>=currentIdx) {
        self.currentAccountIdx++;
    }
}

-(void) setCurrentAccountIdx:(NSInteger)currentAccountIdx
{
    _currentAccountIdx = currentAccountIdx;
    [AppSettings setActiveAccount:currentAccountIdx+1];
}

-(void) setDefaultAccountIdx:(NSInteger)defaultAccountIdx
{
    _defaultAccountIdx = defaultAccountIdx;
    [AppSettings setDefaultAccount:defaultAccountIdx+1];
}

-(Account*) currentAccount
{
    if(self.currentAccountIdx >= 0){
        return self.accounts[self.currentAccountIdx];
    }
    
    return nil;
}

-(NSArray*) getAllDrafts
{
    NSMutableArray* alls = [[NSMutableArray alloc] initWithCapacity:50];
    for (Account* a in self.accounts) {
        if (a.isAllAccounts) {
            continue;
        }
        
        NSArray* draft = [a getConversationsForFolder:FolderTypeWith(FolderTypeDrafts, 0)];
        [alls addObjectsFromArray:draft];
        
    }
    return alls;
}

+(NSArray*) systemFolderIcons
{
    return @[@"inbox_off", @"favoris_off", @"sent_off", @"draft_off", @"all_off", @"delete_off", @"spam_off"];
}

+(NSString*) userFolderIcon
{
    return @"folder_off";
}

@end




@implementation Account

+(instancetype) emptyAccount
{
    Account* a = [[Account alloc] init];
    a.drafts = [NSMutableArray arrayWithCapacity:10];
    a.allsMails = [NSMutableArray arrayWithCapacity:500];
    a.convIDs = [NSMutableSet setWithCapacity:500];
    
    return a;
}


-(NSString*) codeName
{
    return self.person.codeName;
}

-(void) setCodeName:(NSString *)codeName
{
    self.person.codeName = codeName;
    [AppSettings setInitials:codeName accountNum:[self accountNum]];
}

-(NSInteger) accountNum
{
    return self.idx+1;
}

-(void) initContent
{
    // create structure
    NSMutableArray* array = [[NSMutableArray alloc] initWithCapacity:7];
    for (int i=0; i<7; i++) {
        [array addObject:[[NSMutableIndexSet alloc] init]];
    }
    self.systemFoldersContent = array;
    
    const NSInteger limite = self.userFolders.count;
    NSMutableArray* arrayU = [[NSMutableArray alloc] initWithCapacity:limite];
    for (int i=0; i<limite; i++) {
        [arrayU addObject:[[NSMutableIndexSet alloc] init]];
    }
    self.userFoldersContent = arrayU;
    
    [self setCurrentFolder:FolderTypeWith(FolderTypeAll, 0)];
    
    self.localFetchQueue = [NSOperationQueue new];
    [self.localFetchQueue setMaxConcurrentOperationCount:1];
    
    [self doLoadServer];
    [self runLoadData];
}

-(void) releaseContent
{
    self.allsMails = nil;
    self.userFoldersContent = nil;
    self.systemFoldersContent = nil;
    // let the drafts
}

-(void) _addCon:(NSUInteger)idx toFoldersContent:(NSSet*)folders;
{
    for (NSNumber* Fuser in folders) {
        [self _addIdx:idx inArray:decodeFolderTypeWith([Fuser integerValue])];
    }
}

-(void) _addIdx:(NSUInteger)idx inArray:(FolderType)type
{
    NSMutableIndexSet* set = nil;
    if (type.type == FolderTypeUser) {
        set = self.userFoldersContent[type.idx];
    }
    else {
        set = self.systemFoldersContent[type.type];
    }
    [set addIndex:idx];
}

-(void) addConversation:(Conversation*)conv
{
    NSUInteger index = [self.allsMails indexOfObject:conv];
    
    if(index == NSNotFound){
        [self.allsMails addObject:conv];
        [self _addIdx:self.allsMails.count-1 inArray:FolderTypeWith(FolderTypeAll, 0)];
        [self _addCon:self.allsMails.count-1 toFoldersContent:conv.foldersType];
    }
    else {
        Conversation * con = self.allsMails[index];
        for(Mail* m in conv.mails){
            [con addMail:m];
        }
    }
}

-(NSMutableArray*) getConversationsForFolder:(FolderType)type
{
    
    /*if (type.type == FolderTypeDrafts) {
        
        if (self.isAllAccounts) {
            return [[Accounts sharedInstance] getAllDrafts];
        }
        
        NSMutableArray* res = [NSMutableArray arrayWithCapacity:self.drafts.count];
        
        [self.drafts enumerateObjectsWithOptions:0
                                      usingBlock:^(id obj, NSUInteger idx, BOOL* stop){
                                          Conversation* c = [[Conversation alloc] init];
                                          c.mails = [[NSMutableArray alloc]initWithObjects:obj,nil];
                                          [res addObject:c];
                                      }];
        return res;
    }*/
    
    NSMutableIndexSet* set = nil;
    if (type.type == FolderTypeUser) {
        set = self.userFoldersContent[type.idx];
    }
    else {
        set = self.systemFoldersContent[type.type];
    }
    
    NSMutableArray* res = [NSMutableArray arrayWithCapacity:[set count]];
    
    [self.allsMails enumerateObjectsAtIndexes:set
                                      options:0
                                   usingBlock:^(id obj, NSUInteger idx, BOOL* stop){
                                       [res addObject:obj];
                                   }];

    return res;

}

-(void) sendMail:(Mail*)mail bcc:(BOOL)isBcc
{
    NSInteger accountNum = self.accountNum;
    
    MCOMailProvider *accountProvider = [[MCOMailProvidersManager sharedManager] providerForIdentifier:[AppSettings identifier:accountNum]];
    
    NSArray *smtpServicesArray = accountProvider.smtpServices;
    MCONetService *service = smtpServicesArray[0];
    
    MCOSMTPSession *smtpSession = [[MCOSMTPSession alloc] init];
    smtpSession.hostname = service.hostname ;
    smtpSession.port = service.port;
    smtpSession.username = [AppSettings username:accountNum];
    smtpSession.password = [AppSettings password:accountNum];
    smtpSession.connectionType = service.connectionType;
    
    CCMLog(@"Sending with:%@ port:%u authType:%ld",smtpSession.hostname,smtpSession.port,(long)MCOAuthTypeSASLNone);
    
    MCOMessageBuilder * builder = [[MCOMessageBuilder alloc] init];
    [[builder header] setFrom:[MCOAddress addressWithDisplayName:[AppSettings name:accountNum] mailbox:[AppSettings username:accountNum]]];
    
    NSMutableArray *to = [[NSMutableArray alloc] init];
    
    for(NSNumber* personID in mail.toPersonID) {
        Person *p = [[Persons sharedInstance] getPersonID:[personID intValue]];
        MCOAddress *newAddress = [MCOAddress addressWithMailbox:p.email];
        [to addObject:newAddress];
    }
    
    if (!isBcc) {
        [[builder header] setTo:to];
    }else{
        [[builder header] setBcc:to];
    }
    
    /*if (mail.email && !self.fwd) {
        if (mail.email.getSonID)
            [[builder header] setReferences:@[mail.email.getSonID]];
        [[builder header] setInReplyTo: @[mail.email.msgId]];
    }*/
    
    [[builder header] setSubject:mail.title];
    
    [builder setTextBody:mail.content];
    
    //NSString *documentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
    //NSString *filesSubdirectory = [NSTemporaryDirectory()  stringByAppendingPathComponent:@""];
    //NSString *localFilePath = [stringByAppendingPathComponent:file.name];

    for (Attachment *att in [mail attachments]) {
        [builder addAttachment:[MCOAttachment attachmentWithData:att.data filename:att.fileName]];
    }
    
    
    NSData * rfc822Data = [builder data];
    
    MCOSMTPSendOperation *sendOperation = [smtpSession sendOperationWithData:rfc822Data];
    [sendOperation start:^(NSError *error) {
        
        if(error) {
            CCMLog(@"%@ Error sending email:%@", [AppSettings username:accountNum], error);
        } else {
            CCMLog(@"%@ Successfully sent email!", [AppSettings username:accountNum]);
        }
    }];
    
    if ([self.drafts containsObject:mail]) {
        [self.drafts removeObject:mail];
    }
    
    //NSInteger index = self.allsMails.count;
    
    Conversation* c = [[Conversation alloc] init];
    [c addMail:mail];
    [self.allsMails addObject:c];
    
    //[self _addIdx:index inArray:FolderTypeWith(FolderTypeSent, 0)];
}

-(void) saveDraft:(Mail*)mail
{
    if (![self.drafts containsObject:mail]) {
        [self.drafts addObject:mail];
    }
}

-(void) deleteDraft:(Mail*)mail
{
    [self.drafts removeObject:mail];
}

-(BOOL) moveConversation:(Conversation*)conversation from:(FolderType)folderFrom to:(FolderType)folderTo
{
    NSUInteger idx = [self.allsMails indexOfObject:conversation];
    
    NSMutableIndexSet* setTo = nil;
    if (folderTo.type == FolderTypeUser) {
        setTo = self.userFoldersContent[folderTo.idx];
    }
    else {
        setTo = self.systemFoldersContent[folderTo.type];
    }
    
    switch (folderTo.type) {
        case FolderTypeInbox:
        case FolderTypeAll:
        case FolderTypeDeleted:
        case FolderTypeSpam:
        case FolderTypeUser:
            break;
        default:
            NSLog(@"move to this folder not implemented");
            return NO;
            break;
    }
    
    NSMutableIndexSet* setFrom = nil;
    if (folderFrom.type == FolderTypeUser) {
        setFrom = self.userFoldersContent[folderFrom.idx];
    }
    else {
        setFrom = self.systemFoldersContent[folderFrom.type];
    }
    
    BOOL remove = YES;
    
    switch (folderFrom.type) {
        case FolderTypeFavoris:
        case FolderTypeAll:
            remove = (folderFrom.type == FolderTypeDeleted || folderFrom.type == FolderTypeSpam);
            break;
        case FolderTypeInbox:
        case FolderTypeDeleted:
        case FolderTypeSpam:
        case FolderTypeUser:
            break;
        default:
            NSLog(@"move from this folder not implemented");
            return NO;
            break;
    }
    
    [conversation moveFromFolder:[AppSettings numFolderWithFolder:folderFrom forAccount:self.accountNum] ToFolder:[AppSettings numFolderWithFolder:folderTo forAccount:self.accountNum]];

    if (remove) {
        [setFrom removeIndex:idx];
    }
    [setTo addIndex:idx];
    
    return remove;
}

-(NSInteger) unreadInInbox
{
    NSArray* a = [self getConversationsForFolder:FolderTypeWith(FolderTypeInbox, 0)];
    
    NSInteger count = 0;
    for (Conversation* c in a) {
        
        if (![c firstMail].isRead) {
            count++;
        }
    }
    
    return count;
}

-(void) setCurrentFolder:(FolderType)folder
{
    NSString* name = nil;
    if (folder.type == FolderTypeUser) {
        name = [[Accounts sharedInstance] currentAccount].userFolders[folder.idx];
        NSArray* names = [AppSettings allFoldersName:[AppSettings activeAccount]];
        for (int i = 0; i < names.count; i++) {
            if ([name isEqualToString:names[i]]){
                self.currentFolderIdx = i;
                return;
            }
        }
    }
    else {
        self.currentFolderIdx = [AppSettings importantFolderNumForAcct:[AppSettings activeAccount] forBaseFolder:folder.type];
    }
}

- (void)insertRows:(Email *)email
{
    if ([_convIDs containsObject:[email getSonID]]) {
        for (NSUInteger idx = 0; idx < self.allsMails.count; idx++) {
            Conversation* conv = self.allsMails[idx];
            if ([[[conv firstMail].email getSonID] isEqualToString:[email getSonID]]) {
                [conv addMail:[Mail mail:email]];
                [self _addCon:idx toFoldersContent:conv.foldersType];
                return;
            }
        }
    }
    else {
        Conversation* conv = [[Conversation alloc]init];
        [conv addMail:[Mail mail:email]];
        [_convIDs addObject:[email getSonID]];
        [self addConversation:conv];
        [self.allsMails addObject:conv];
    }
}

#pragma mark - Fetch Data

- (void)doLoadServer
{
    if ([[Reachability reachabilityForInternetConnection] currentReachabilityStatus] != NotReachable) {
        [[[[SyncManager getSingleton] syncFolders] deliverOn:[RACScheduler mainThreadScheduler]]
         subscribeNext:^(Email *email) {
             [self insertRows:email];
         }
         error:^(NSError *error) {
             CCMLog(@"Error: %@",error.localizedDescription);
         }
         completed:^{
             //if(![AppSettings isFirstFullSyncDone]){
                 [self doLoadServer];
             //}
         }];
    }
}

- (void)runLoadData
{
        [self.localFetchQueue addOperationWithBlock:^{
            [[[SearchRunner getSingleton] allFoldersSearchInAccount:self.accountNum]
             subscribeNext:^(Email *email) {
                 [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                     //CCMLog(@"Adding email");
                     [self insertRows:email];
                 }];
             }
             completed:^{
                 [[NSOperationQueue mainQueue] addOperationWithBlock:^{

                     if (self.idx != -1) {
                         if (self.allsMails.count != 0){
                             ///[[ImapSync sharedServices] runUpToDateTest:self.allsMails];
                         }
                     }
                 }];
             }];
        }];
}

-(NSArray*) systemFolderNames
{
    NSMutableArray* names = [[NSMutableArray alloc]init];
    
    [names addObject:NSLocalizedString(@"Inbox", @"Inbox")];
    [names addObject:NSLocalizedString(@"Favoris", @"Favoris")];
    if ([AppSettings importantFolderNumForAcct:self.idx-1 forBaseFolder:FolderTypeSent] != -1) { [names addObject:NSLocalizedString(@"Sent", @"Sent")]; }
    if ([AppSettings importantFolderNumForAcct:self.idx-1 forBaseFolder:FolderTypeDrafts] != -1) { [names addObject:NSLocalizedString(@"Drafts", @"Drafts")]; }
    [names addObject:NSLocalizedString(@"All emails", @"All emails")];
    if ([AppSettings importantFolderNumForAcct:self.idx-1 forBaseFolder:FolderTypeDeleted] != -1) { [names addObject:NSLocalizedString(@"Deleted", @"Deleted")]; }
    if ([AppSettings importantFolderNumForAcct:self.idx-1 forBaseFolder:FolderTypeSpam] != -1) { [names addObject:NSLocalizedString(@"Spam", @"Spam")]; }
    
    return names;
}

@end
