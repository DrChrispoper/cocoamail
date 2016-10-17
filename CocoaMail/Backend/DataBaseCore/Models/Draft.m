//
//  Draft.m
//  CocoaMail
//
//  Created by Christopher Hockley on 01/03/16.
//  Copyright © 2016 Christopher Hockley. All rights reserved.
//

#import "Draft.h"
#import "Accounts.h"
#import "UserSettings.h"
#import "RegExCategories.h"
#import "ImapSync.h"

@implementation Draft

- (id)initWithCoder:(NSCoder *)decoder {
    self = [super init];
    if (!self) {
        return nil;
    }
    
    self.accountNum = [decoder decodeIntegerForKey:@"accountNum"];
    self.toPersons = [decoder decodeObjectForKey:@"toPersons"];
    self.isBcc = [decoder decodeBoolForKey:@"isBcc"];
    self.transferContent = [decoder decodeObjectForKey:@"transferContent"];
    self.fromMailMsgID = [decoder decodeObjectForKey:@"fromMailMsgID"];
    self.subject = [decoder decodeObjectForKey:@"subject"];
    self.body = [decoder decodeObjectForKey:@"body"];
    self.msgID = [decoder decodeObjectForKey:@"msgID"];
    self.datetime = [decoder decodeObjectForKey:@"datetime"];
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder
{
    [encoder encodeInteger:self.accountNum forKey:@"accountNum"];
    [encoder encodeObject:self.toPersons forKey:@"toPersons"];
    [encoder encodeBool:self.isBcc forKey:@"isBcc"];
    [encoder encodeObject:self.transferContent forKey:@"transferContent"];
    [encoder encodeObject:self.fromMailMsgID forKey:@"fromMailMsgID"];
    [encoder encodeObject:self.subject forKey:@"subject"];
    [encoder encodeObject:self.body forKey:@"body"];
    [encoder encodeObject:self.msgID forKey:@"msgID"];
    [encoder encodeObject:self.datetime forKey:@"datetime"];
}

+(Draft *)newDraftFormCurrentAccount
{
    Draft* draft = [[Draft alloc] init];
    
    Accounts* allAccounts = [Accounts sharedInstance];
    
    if (allAccounts.currentAccount.user.isAll) {
        draft.accountNum = [AppSettings userWithIndex:[Accounts sharedInstance].defaultAccountIdx].accountNum;
    }
    else {
        draft.accountNum = [Accounts sharedInstance].currentAccount.user.accountNum;
    }
    
    draft.msgID = [NSString stringWithFormat:@"%i", [[AppSettings getSingleton] draftCount]];
    
    draft.toPersons = [[NSMutableArray alloc] init];
    draft.body = @"";
    
    return draft;

}

-(NSArray *) attachments
{
    return [CCMAttachment getAttachmentsWithMsgID:self.msgID];
}

// Save Draft to "drafts" folder as "draft_<msgID>"
-(void)saveToDraftsFolder
{
    self.datetime = [NSDate date];
    
    NSString *documentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString* folderPath = [documentsDirectory stringByAppendingPathComponent:@"drafts"];
    NSString* fileName = [folderPath stringByAppendingPathComponent:[NSString stringWithFormat:@"draft_%@", self.msgID]];

    [NSKeyedArchiver archiveRootObject:self toFile:fileName];
    
    [[AppSettings userWithNum:self.accountNum].linkedAccount addLocalDraft:self];
}

-(void)deleteDraft
{
    [[AppSettings userWithNum:self.accountNum].linkedAccount deleteDraft:self];
    
    NSString *documentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString* folderPath = [documentsDirectory stringByAppendingPathComponent:@"drafts"];
    NSString* fileName = [folderPath stringByAppendingPathComponent:[NSString stringWithFormat:@"draft_%@", self.msgID]];

    if ([[NSFileManager defaultManager] removeItemAtPath:fileName error:nil]) {
        DDLogInfo(@"Local draft file deleted");
    }
}

-(void) appendToSent:(NSString*)rfc822DataFilename
{
    UserSettings* user = [AppSettings userWithNum:self.accountNum];
    
    NSString* sentPath = [user folderServerName:[user numFolderWithFolder:CCMFolderTypeSent]];
    
    MCOIMAPAppendMessageOperation* addOp = [[ImapSync sharedServices:user].imapSession
                                            appendMessageOperationWithFolder:sentPath
                                            contentsAtPath:rfc822DataFilename
                                            flags:MCOMessageFlagSeen
                                            customFlags:nil];
    
    dispatch_async([ImapSync sharedServices:user].s_queue, ^{
        [addOp start:^(NSError * error, uint32_t createdUID) {
            if (error == nil) {
                NSString *documentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
                NSString* folderPath = [documentsDirectory stringByAppendingPathComponent:@"outbox"];
                NSString* fileName = [folderPath stringByAppendingPathComponent:[NSString stringWithFormat:@"outbox_%@", self.msgID]];
                
                if ([[NSFileManager defaultManager] removeItemAtPath:fileName error:nil]) {
                    DDLogInfo(@"Local outbox file deleted");
                }
            }
        }];
        
    });

}

-(BOOL)saveOuboxDraft
{
    [self deleteDraft];
    
    self.datetime = [NSDate date];
    
    NSString *documentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString* folderPath = [documentsDirectory stringByAppendingPathComponent:@"outbox"];
    NSString* fileName = [folderPath stringByAppendingPathComponent:[NSString stringWithFormat:@"draft_%@", self.msgID]];
    
    return  [NSKeyedArchiver archiveRootObject:self toFile:fileName];
}

-(void)deleteOutboxDraft
{
    [[AppSettings userWithNum:self.accountNum].linkedAccount deleteDraft:self];
    
    NSString *documentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString* folderPath = [documentsDirectory stringByAppendingPathComponent:@"outbox"];
    NSString* fileName = [folderPath stringByAppendingPathComponent:[NSString stringWithFormat:@"draft_%@", self.msgID]];
    
    if ([[NSFileManager defaultManager] removeItemAtPath:fileName error:nil]) {
        DDLogInfo(@"Local draft file deleted");
    }
}

-(NSString*)rfc822DataTo:(NSArray *)toPersonIDs
{
    MCOMessageBuilder* builder = [[MCOMessageBuilder alloc] init];
    UserSettings* user = [AppSettings userWithNum:self.accountNum];
    [[builder header] setFrom:[MCOAddress addressWithDisplayName:[user name] mailbox:[user username]]];
    
    NSMutableArray* to = [[NSMutableArray alloc] init];
    
    for (NSNumber* personID in toPersonIDs) {
        Person* p = [[Persons sharedInstance] getPersonWithID:[personID intValue]];
        MCOAddress* newAddress = [MCOAddress addressWithMailbox:p.email];
        [to addObject:newAddress];
    }
    
    if (!self.isBcc) {
        [[builder header] setTo:to];
    }
    else {
        [[builder header] setBcc:to];
    }
    
    NSMutableString* links = [NSMutableString string];
    
    for (Attachment* att in [self attachments]) {
        if (att.size != 0) {
            [builder addAttachment:[MCOAttachment attachmentWithData:att.data filename:att.fileName]];
        }
        else {
            [links appendString:[NSString stringWithFormat:@"<a href='%@' download>%@</a>", [[NSString alloc] initWithData:att.data encoding:NSUTF8StringEncoding], att.fileName]];
        }
    }
    
    [builder setHTMLBody:[NSString stringWithFormat:@"%@<br/>%@", self.body, links]];
    
    if (self.fromMailMsgID) {
        [[builder header] setInReplyTo: @[self.fromMailMsgID]];
    }
    
    [[builder header] setSubject:self.subject];
    
    //NSString* lk = [NSString stringWithFormat:@"<a href='%@' download>%@</a>", link, attach.fileName];

    NSString *documentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString* folderPath = [documentsDirectory stringByAppendingPathComponent:@"drafts"];
    NSString* fileName = [folderPath stringByAppendingPathComponent:[NSString stringWithFormat:@"outbox_%@", self.msgID]];
    NSError* error;
    
    [builder writeToFile:fileName error:&error];

    if (error) {
        DDLogError(@"error saving outbox message :%@", error.description);
    }
    
    return fileName;
}

-(Mail*) fromMail
{
    NSArray* uids = [UidEntry getUidEntriesWithMsgId:self.fromMailMsgID];
    for (UidEntry* e in uids) {
        return [Mail getMailWithMsgId:e.msgID dbNum:e.dbNum];
    }
    
    return nil;
}

@end
