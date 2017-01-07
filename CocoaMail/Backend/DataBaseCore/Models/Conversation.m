//
//  Conversation.m
//  CocoaMail
//
//  Created by Christopher Hockley on 26/02/16.
//  Copyright © 2016 Christopher Hockley. All rights reserved.
//

#import "Conversation.h"
#import "Accounts.h"
#import "DateUtil.h"
#import "Mail.h"
#import "UserSettings.h"

@implementation Conversation

static NSDateFormatter * s_df_day = nil;
static NSDateFormatter * s_df_hour = nil;

+(void) initialize
{
    s_df_day = [[NSDateFormatter alloc] init];
    s_df_day.dateFormat = @"d MMM yy";
    
    s_df_hour = [[NSDateFormatter alloc] init];
    s_df_hour.dateStyle = NSDateFormatterNoStyle;
    s_df_hour.timeStyle = NSDateFormatterShortStyle;
}

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
    return [self firstMail].datetime;
}

-(Mail*) firstMail
{
    return [self.mails firstObject];
}

-(NSArray*) uidsWithFolder:(NSInteger)folder
{
    NSMutableArray* uids = [[NSMutableArray alloc]init];
    for (Mail* m in self.mails) {
        if ([m uidEWithFolder:folder]) {
            [uids addObject:[m uidEWithFolder:folder]];
        }
    }
    
    return uids;
}

-(BOOL) isInFolder:(NSInteger)folderNum
{
    for (Mail* mail in self.mails) {
        if ([mail isInFolder:folderNum]) {
            return YES;
        }
    }
    return NO;
}

-(BOOL) isInInbox
{
    return [self uidsWithFolder:[[self user] numFolderWithFolder:FolderTypeWith(FolderTypeInbox, 0)]].count > 0;
}

-(UserSettings*) user
{
    return [self firstMail].user;
}

-(void) toggleFav
{
    BOOL isStarred = [self isFav];
    [self.user.linkedAccount star:!isStarred conversation:self];

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
}

-(void) addMail:(Mail*)mail
{
    for (Mail* tmpMail in self.mails) {
        if ([tmpMail isEqualToMail:mail]) {
            return;
        }
    }
    
    [self.mails addObject:mail];
    
    NSSortDescriptor* sortByDate = [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(datetime)) ascending:NO];
    [self.mails sortUsingDescriptors:@[sortByDate]];
}

-(BOOL) hasAttachments
{
    for (Mail* m in self.mails) {
        if ([m hasAttachments]) {
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

-(BOOL) isUnread
{
    for (Mail* m in self.mails) {
        if (![m isRead]) {
            return true;
        }
    }
    
    return false;
}

-(void) moveFromFolder:(NSInteger)fromFolderIdx ToFolder:(NSInteger)toFolderIdx
{
    for (Mail* m in self.mails) {
        [m moveFromFolder:fromFolderIdx ToFolder:toFolderIdx];
    }
    
    [self foldersType];
}

-(void) trash
{
    for (Mail* m in self.mails) {
        [m trash];
    }
    
    [self foldersType];
}

-(BOOL) isEqualToConversation:(Conversation*)conv
{
    if (!conv) {
        return NO;
    }
    
    if ((![[self.firstMail sonID] isEqualToString:@"0"]) & (![[self.firstMail sonID] isEqualToString:@""])) {
        return [[self.firstMail sonID] isEqualToString:[conv.firstMail sonID]];
    }
    
    return [self.firstMail.msgID isEqualToString:conv.firstMail.msgID];
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

// Return a Set of all the Folder Types of all the Mails in this Conversation
-(NSMutableSet*) foldersType
{
    NSMutableSet* tempFodles = [[NSMutableSet alloc] init];
    
    NSArray<Mail*>* tmp = [self.mails copy];  // copy in case self.mails changes while in this func?
    
    if (self.isDraft) {
        [tempFodles addObject:@(encodeFolderTypeWith(FolderTypeWith(FolderTypeDrafts, 0)))];
    }
    else {
        for (Mail* mail in tmp) {
            mail.uids = [UidEntry getUidEntriesWithMsgId:mail.msgID];
            
            for (UidEntry* uid in mail.uids) {
                CCMFolderType Fuser = [[AppSettings userWithNum:uid.accountNum] typeOfFolder:uid.folder];
                [tempFodles addObject:@(encodeFolderTypeWith(Fuser))];
            }
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
        _user = nil;
    }
    
    return self;
}

+(ConversationIndex*) initWithIndex:(NSInteger)index user:(UserSettings*)user
{
    ConversationIndex* cI = [[ConversationIndex alloc]init];
    cI.index = index;
    cI.user = user;
    
    return cI;
}

-(NSDate*) date
{
    Conversation* conversation = [[Accounts sharedInstance] conversationForCI:self];
    return [conversation firstMail].datetime;
}

-(NSDate*) day
{
    Conversation* conversation = [[Accounts sharedInstance] conversationForCI:self];
    NSString* stringDate = [[DateUtil getSingleton] humanDate:[conversation firstMail].datetime];
    
    return [s_df_day dateFromString:stringDate];
}

@end
