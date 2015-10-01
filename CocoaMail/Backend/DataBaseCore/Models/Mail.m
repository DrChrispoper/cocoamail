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

@implementation Mail

static NSDateFormatter* s_df_day = nil;
static NSDateFormatter* s_df_hour = nil;


+(void) initialize
{
    s_df_day = [[NSDateFormatter alloc] init];
    s_df_day.dateStyle = NSDateFormatterMediumStyle;
    s_df_day.timeStyle = NSDateFormatterNoStyle;
    
    s_df_hour = [[NSDateFormatter alloc] init];
    s_df_hour.dateStyle = NSDateFormatterNoStyle;
    s_df_hour.timeStyle = NSDateFormatterShortStyle;
    
    // to init attachments
}

-(Mail*) replyMail:(BOOL)replyAll
{
    Mail* mail = [Mail newMailFormCurrentAccount];
    
    mail.title = self.title;
    
    if (replyAll) {
        
        NSMutableArray* currents = [self.toPersonID mutableCopy];
        
        [currents addObject:@(self.fromPersonID)];
        [currents removeObject:@(mail.fromPersonID)];
        
        mail.toPersonID = currents;
        
    }
    else {
        mail.toPersonID = @[@(self.fromPersonID)];
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
    NSString* wrote = NSLocalizedString(@"wrote", @"wrote");
    NSString* oldcontent = [NSString stringWithFormat:@"\n\n%@ %@ :\n\n%@\n", from.name, wrote, self.content];
    mail.content = oldcontent;
    
    mail.fromMail = nil;
    
    return mail;
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

-(NSArray*)attachments
{
    return self.email.attachments;
}

-(void)setAttachments:(NSArray*)attachments
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
    
    NSDate* yesterday = [today dateByAddingTimeInterval:-60*60*24];
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
    if (allAccounts.currentAccountIdx == allAccounts.accountsCount -1) {
        mail.fromPersonID = -(1+[Accounts sharedInstance].defaultAccountIdx);;
    }
    else {
        mail.fromPersonID = -(1+[Accounts sharedInstance].currentAccountIdx);
    }
    
    mail.email = [[Email alloc]init];
    
    return mail;
}

- (BOOL)isEqualToMail:(Mail *)mail {
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
    
    return [self isEqualToMail:(Mail *)object];
}

@end


@implementation Conversation

-(instancetype)init
{
    self = [super init];
    if (self) {
        _mails = [[NSMutableArray alloc]initWithCapacity:1];
        _foldersType = [[NSMutableSet alloc]initWithCapacity:1];
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

-(void) addMail:(Mail *)mail
{
    for (UidEntry* uid in mail.email.uids) {
        //if (uid.account != kActiveAccount) {
        //    CCMLog(@"WTF: %@",uid.msgId);
        //}
        CCMFolderType Fuser = [AppSettings typeOfFolder:uid.folder forAccountIndex:[AppSettings indexForAccount:uid.account]];
        [self.foldersType addObject:@(encodeFolderTypeWith(Fuser))];
    }
    
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

-(void) moveFromFolder:(NSInteger)fromFolderIdx ToFolder:(NSInteger)toFolderIdx
{
    for (Mail* m in self.mails) {
        [m.email moveFromFolder:fromFolderIdx ToFolder:toFolderIdx];
    }
}

- (BOOL)isEqualToConversation:(Conversation *)conv {
    if (!conv) {
        return NO;
    }
    
    if (![[self.firstMail.email getSonID] isEqualToString:@"0"]) {
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
    
    return [self isEqualToConversation:(Conversation *)object];
}


@end

