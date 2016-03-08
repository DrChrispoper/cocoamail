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
    
    return draft;

}

-(NSArray *) attachments
{
    return [CCMAttachment getAttachmentsWithMsgID:self.msgID];
}

-(void)save
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
    [[AppSettings userWithNum:self.accountNum].linkedAccount deleteDraft:self.msgID];
        
    NSFileManager *filemgr = [NSFileManager defaultManager];
    NSString *draftPath = @"drafts";
    
    NSString *documentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString* folderPath = [documentsDirectory stringByAppendingPathComponent:draftPath];
    
    if (![filemgr fileExistsAtPath:folderPath]) {
        [filemgr createDirectoryAtPath:folderPath withIntermediateDirectories:NO attributes:nil error:nil];
    }
        
    NSArray *dirFiles = [filemgr contentsOfDirectoryAtPath:folderPath error:nil];
        
    for (NSString* fileName in dirFiles) {
        if ([fileName isEqualToString:[NSString stringWithFormat:@"draft_%@",self.msgID]]) {
            NSString* localPath = [folderPath stringByAppendingPathComponent:fileName];
            if ([filemgr removeItemAtPath:localPath error:nil]) {
                NSLog(@"Local draft deleted");
            }
        }
    }
}

-(NSData *)rfc822DataTo:(NSArray *)toPersonIDs
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
    
    [builder setHTMLBody:self.body];
    
    if (self.fromMailMsgID) {
        [[builder header] setInReplyTo: @[self.fromMailMsgID]];
    }
    
    [[builder header] setSubject:self.subject];
    
    for (Attachment* att in [self attachments]) {
        [builder addAttachment:[MCOAttachment attachmentWithData:att.data filename:att.fileName]];
    }
    
    
    return [builder data];
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
