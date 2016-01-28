//
//  Mail.m
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 16/07/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "Mail.h"
#import "Email.h"

#import "Persons.h"
#import "Accounts.h"
#import "AppSettings.h"
#import "DateUtil.h"

@implementation Mail

static NSDateFormatter * s_df_day = nil;
static NSDateFormatter * s_df_hour = nil;


+(void) initialize
{
    s_df_day = [[NSDateFormatter alloc] init];
    s_df_day.dateFormat = @"d MMM yy";
    
    s_df_hour = [[NSDateFormatter alloc] init];
    s_df_hour.dateStyle = NSDateFormatterNoStyle;
    s_df_hour.timeStyle = NSDateFormatterShortStyle;
    
    // to init attachments
}

-(Mail*) replyMail:(BOOL)replyAll
{
    Mail* mail = [Mail newMailFormCurrentAccount];
    
    mail.title = self.title;
    
    NSInteger currentAccountIndex = [[Persons sharedInstance] indexForPerson:[Accounts sharedInstance].currentAccount.person];

    if (replyAll) {
        NSMutableArray* currents = [self.toPersonID mutableCopy];
        
        if (currentAccountIndex != self.fromPersonID) {
            [currents addObject:@(self.fromPersonID)];
        }
        
        [currents removeObject:@(currentAccountIndex)];
        
        mail.toPersonID = currents;
    }
    else {
        if (currentAccountIndex != self.fromPersonID) {
            mail.toPersonID = @[@(self.fromPersonID)];
        }
    }
    
    mail.content = @"";
    mail.attachments = nil;
    
    mail.fromMail = self;
    
    return mail;
}

-(Mail*) transfertMail
{
    Mail* mail = [self replyMail:NO];
    mail.toPersonID = nil;
    mail.attachments = self.attachments;
    
    Person* from = [[Persons sharedInstance] getPersonID:self.fromPersonID];
    NSString* wrote = NSLocalizedString(@"compose-view.content.transfer", @"wrote");
    NSString* oldcontent = [NSString stringWithFormat:@"\n\n%@ %@ :\n\n%@\n", from.name, wrote, self.email.htmlBody];
    
    mail.transferContent = oldcontent;
    
    mail.fromMail = nil;
    
    return mail;
}

-(NSData*) rfc822DataWithAccountIdx:(NSInteger)idx isBcc:(BOOL)isBcc
{
    if (!self.content) {
        self.content = @"";
    }
    else {
        //self.content = [self.content stringByRemovingPercentEncoding];
        //self.content = [self.content stringByReplacingOccurrencesOfString:@"\n" withString:@"<br/>"];
        //self.content = [self.content stringByReplacingOccurrencesOfString:@"\r" withString:@"<br/>"];
    }
    
    MCOMessageBuilder* builder = [[MCOMessageBuilder alloc] init];
    [[builder header] setFrom:[MCOAddress addressWithDisplayName:[AppSettings name:idx] mailbox:[AppSettings username:idx]]];
    
    NSMutableArray* to = [[NSMutableArray alloc] init];
    
    for (NSNumber* personID in self.toPersonID) {
        Person* p = [[Persons sharedInstance] getPersonID:[personID intValue]];
        MCOAddress* newAddress = [MCOAddress addressWithMailbox:p.email];
        [to addObject:newAddress];
    }
    
    if (!isBcc) {
        [[builder header] setTo:to];
    }
    else {
        [[builder header] setBcc:to];
    }
    
    [builder setHTMLBody:self.content];

    if (self.fromMail) {
        [[builder header] setReferences:@[self.fromMail.email.getSonID]];
        [[builder header] setInReplyTo: @[self.fromMail.email.msgId]];
        
        //Not adding the Yuk! :D
        //Person* from = [[Persons sharedInstance] getPersonID:self.fromMail.fromPersonID];
        //NSString* wrote = NSLocalizedString(@"compose-view.content.transfer", @"wrote");
        
        //[builder setHTMLBody:[NSString stringWithFormat:@"%@<br/>%@ %@ :<br/><br/>%@<br/>",self.content, from.name, wrote, self.fromMail.email.htmlBody]];
    }
    
    [[builder header] setSubject:self.title];
    
    
    //NSString* documentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
    //NSString* filesSubdirectory = [NSTemporaryDirectory()  stringByAppendingPathComponent:@""];
    //NSString* localFilePath = [stringByAppendingPathComponent:file.name];
    
    for (Attachment* att in [self attachments]) {
        [builder addAttachment:[MCOAttachment attachmentWithData:att.data filename:att.fileName]];
    }
    
    
    return [builder data];
}

+(Mail*) mail:(Email*)email
{
    Mail* mail = [[Mail alloc]init];
    
    NSString* name = email.sender.displayName;
    
    if (!name || [name isEqualToString:@""]) {
        name = email.sender.mailbox;
    }
    
    NSString* codeName = [name uppercaseString];
    codeName = [codeName stringByReplacingOccurrencesOfString:@" " withString:@""];
    codeName = [codeName substringToIndex:(codeName.length < 3)?codeName.length:3];
    
    mail.fromPersonID = [[Persons sharedInstance]indexForPerson:[Person createWithName:name email:email.sender.mailbox icon:nil codeName:codeName]];
    mail.date = email.datetime;
    mail.title = email.subject;
    
    NSString* content = email.body;//infos[@"content"];
    
    NSArray* tmp = [NSMutableArray arrayWithArray:email.tos];
    tmp = [tmp arrayByAddingObjectsFromArray:email.ccs];
    tmp = [tmp arrayByAddingObjectsFromArray:email.bccs];

    NSMutableArray* ids = [[NSMutableArray alloc]initWithCapacity:tmp.count];
    
    for (MCOAddress* address in tmp) {
        NSString* name = address.displayName;
        
        if (!name || [name isEqualToString:@""]) {
            name = address.mailbox;
        }
        
        NSString* codeName = [name uppercaseString];
        codeName = [codeName stringByReplacingOccurrencesOfString:@" " withString:@""];
        codeName = [codeName substringToIndex:(codeName.length < 3)?codeName.length:3];

        
        [ids addObject:@([[Persons sharedInstance]indexForPerson:[Person createWithName:name email:address.mailbox icon:nil codeName:codeName]])];
    }
    
    mail.toPersonID = ids;
    
    mail.day = [s_df_day stringFromDate:email.datetime];
    mail.hour = [s_df_hour stringFromDate:email.datetime];
    
    mail.content = content;
    mail.email = email;
    
    return mail;
}

-(NSArray*) attachments
{
    return self.email.attachments;
}

-(void) setAttachments:(NSArray*)attachments
{
    self.email.attachments = attachments;
}

-(BOOL) haveAttachment
{
    return [self.email hasAttachments];
}

-(BOOL) isFav
{
    return (self.email.flag & MCOMessageFlagFlagged);
}

-(BOOL) isRead
{
    return (self.email.flag & MCOMessageFlagSeen);
}

-(void) toggleFav
{
    [self.email star];
}

-(void) toggleRead
{
    [self.email read];
}

-(NSString*) mailID
{
    return self.email.msgId;
}

+(NSInteger) isTodayOrYesterday:(NSString*)dateString
{
    NSDate* today = [NSDate date];
    NSString* todayS = [s_df_day stringFromDate:today];
    
    if ([dateString isEqualToString:todayS]) {
        return 0;
    }
    
    NSDate* yesterday = [today dateByAddingTimeInterval:- 60 * 60 * 24];
    NSString* yesterdayS = [s_df_day stringFromDate:yesterday];
    
    if ([dateString isEqualToString:yesterdayS]) {
        return -1;
    }
    
    return 1;
}

+(Mail*) newMailFormCurrentAccount
{
    Mail* mail = [[Mail alloc] init];
    
    Accounts* allAccounts = [Accounts sharedInstance];
    
    mail.email = [[Email alloc]init];

    if (allAccounts.currentAccount.isAllAccounts) {
        mail.fromPersonID = -(1 + [Accounts sharedInstance].defaultAccountIdx);
        [mail.email setAccountNum:[[AppSettings getSingleton] numAccountForIndex:[Accounts sharedInstance].defaultAccountIdx]];

    }
    else {
        mail.fromPersonID = -(1 + [Accounts sharedInstance].currentAccountIdx);
        [mail.email setAccountNum:[[AppSettings getSingleton] numAccountForIndex:[Accounts sharedInstance].currentAccountIdx]];
    }
    
    return mail;
}

-(BOOL) isEqualToMail:(Mail*)mail
{
    if (!mail) {
        return NO;
    }
    
    return [self.mailID isEqualToString:mail.mailID];
}

-(BOOL) isEqual:(id)object
{
    if (self == object) {
        return YES;
    }
    
    if (![object isKindOfClass:[Mail class]]) {
        return NO;
    }
    
    return [self isEqualToMail:(Mail*)object];
}


@end

@implementation Conversation

-(instancetype) init
{
    self = [super init];
    
    if (self) {
        _mails = [[NSMutableArray alloc]initWithCapacity:1];
    }
    
    return self;
}

-(NSDate*) latestDate
{
    return [[self firstMail] date];
}

-(Mail*) firstMail
{
    return [self.mails firstObject];
}

-(NSArray*) uidsWithFolder:(NSInteger)folder
{
    NSMutableArray* uids = [[NSMutableArray alloc]init];
    for (Mail* m in self.mails) {
        if ([m.email uidEWithFolder:folder]) {
            [uids addObject:[m.email uidEWithFolder:folder]];
        }
    }
    
    return uids;
}

-(BOOL) isInInbox
{
    return [self uidsWithFolder:[AppSettings numFolderWithFolder:FolderTypeWith(FolderTypeInbox, 0) forAccountIndex:[self accountIdx]]].count > 0;
}


-(NSInteger) accountIdx
{
    return [[AppSettings getSingleton] indexForAccount:[self firstMail].email.accountNum];
}

-(void) toggleFav
{
    BOOL isStarred = [self isFav];
    
    if(isStarred) {
        for (Mail* m in self.mails) {
            if ([m isFav]) {
                [[self firstMail] toggleFav];
            }
        }
    }
    else {
        [[self firstMail] toggleFav];
    }
    
    
    [[[Accounts sharedInstance] accounts][self.accountIdx] star:!isStarred conversation:self];
    
}

-(void) addMail:(Mail*)mail
{
    for (Mail* tmpMail in self.mails) {
        if ([tmpMail isEqualToMail:mail]) {
            return;
        }
    }
    
    [self.mails addObject:mail];
    
    NSSortDescriptor* sortByDate = [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(date)) ascending:NO];
    [self.mails sortUsingDescriptors:@[sortByDate]];
}

-(BOOL) haveAttachment
{
    for (Mail* m in self.mails) {
        if ([m.email hasAttachments]) {
            return true;
        }
    }
    
    return false;
}

-(BOOL) isFav
{
    for (Mail* m in self.mails) {
        if ([m isFav]) {
            return true;
        }
    }
    
    return false;
}

-(void) moveFromFolder:(NSInteger)fromFolderIdx ToFolder:(NSInteger)toFolderIdx
{
    for (Mail* m in self.mails) {
        [m.email moveFromFolder:fromFolderIdx ToFolder:toFolderIdx];
    }
    
    [self foldersType];
}

-(void) trash
{
    for (Mail* m in self.mails) {
        [m.email trash];
    }
    
    [self foldersType];
}

-(BOOL) isEqualToConversation:(Conversation*)conv
{
    if (!conv) {
        return NO;
    }
    
    if ((![[self.firstMail.email getSonID] isEqualToString:@"0"]) & (![[self.firstMail.email getSonID] isEqualToString:@""])) {
        return [[self.firstMail.email getSonID] isEqualToString:[conv.firstMail.email getSonID]];
    }
    
    return [self.firstMail.mailID isEqualToString:conv.firstMail.mailID];
}

-(BOOL) isEqual:(id)object
{
    if (self == object) {
        return YES;
    }
    
    if (![object isKindOfClass:[Conversation class]]) {
        return NO;
    }
    
    return [self isEqualToConversation:(Conversation*)object];
}

-(NSMutableSet*) foldersType
{
    NSMutableSet* tempFodles= [[NSMutableSet alloc] init];
    
    for (Mail* mail in self.mails) {
        mail.email.uids = [UidEntry getUidEntriesWithMsgId:mail.email.msgId];
        
        for (UidEntry* uid in mail.email.uids) {
            CCMFolderType Fuser = [AppSettings typeOfFolder:uid.folder forAccountIndex:[[AppSettings getSingleton] indexForAccount:uid.account]];
            [tempFodles addObject:@(encodeFolderTypeWith(Fuser))];
        }
    }
    
    return tempFodles;
}

@end

@implementation ConversationIndex

-(instancetype) init
{
    self = [super init];
    
    if (self) {
        _index = 0;
        _account = 0;
    }
    
    return self;
}

+(ConversationIndex*) initWithIndex:(NSInteger)index Account:(NSInteger)account
{
    ConversationIndex* cI = [[ConversationIndex alloc]init];
    cI.index = index;
    cI.account = account;
    
    return cI;
}

-(NSDate*) date
{
    Conversation* conversation = [[Accounts sharedInstance] conversationForCI:self];
    return [conversation firstMail].email.datetime;
}

-(NSDate*) day
{
    Conversation* conversation = [[Accounts sharedInstance] conversationForCI:self];
    NSString* stringDate = [[DateUtil getSingleton] humanDate:[conversation firstMail].email.datetime];
    
    return [s_df_day dateFromString:stringDate];
}

@end

