//
//  Attachemnt.m
//  CocoaMail
//
//  Created by Christopher Hockley on 20/01/2014.
//  Copyright (c) 2014 Christopher Hockley. All rights reserved.
//

#import "CCMAttachment.h"
#import "AttachmentDBAccessor.h"
#import "FMDatabase.h"
#import "Attachments.h"
#import "StringUtil.h"

@implementation CCMAttachment

+(void) addAttachments:(NSArray*)atts
{
    AttachmentDBAccessor* databaseManager = [AttachmentDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        for (CCMAttachment* at in atts) {
            FMResultSet* results = [db executeQuery:@"SELECT * FROM attachments WHERE msg_id = ? AND file_name = ?", at.msgId, at.fileName];

            if (!results.next) {
                [results close];
                if (!at.data) {
                    [db executeUpdate:@"INSERT INTO attachments (file_name,size,mime_type,msg_id,partID,contentID) VALUES (?,?,?,?,?,?);",
                     at.fileName, @(at.size), at.mimeType, at.msgId, at.partID, at.contentID];
                }
                else {
                    [db executeUpdate:@"INSERT INTO attachments (file_name,size,mime_type,msg_id,data,partID,contentID) VALUES (?,?,?,?,?,?,?);",
                     at.fileName, @(at.size), at.mimeType, at.msgId, at.data, at.partID, at.contentID];
                }
            }
            else {
                [results close];
            }
        }
    }];
}

+(void) addAttachmentsUnsafe:(NSMutableArray*)atts
{
    AttachmentDBAccessor* databaseManager = [AttachmentDBAccessor sharedManager];
    
    FMDatabase* database = [FMDatabase databaseWithPath:databaseManager.databaseFilepath];
    [database open];
    
        for (CCMAttachment* at in atts) {
            [database executeUpdate:@"INSERT INTO attachments (file_name,size,mime_type,msg_id,data,partID,contentID) VALUES (?,?,?,?,?,?,?);",
             at.fileName, @(at.size), at.mimeType, at.msgId, at.data, at.partID, at.contentID];
        }
    
    [database close];
}

+(NSMutableArray*) getAttachments
{
    return [Attachment getAttachments:FALSE];
}

+(NSMutableArray*) getAttachments:(BOOL)andInline
{
    NSMutableArray* attachments = [[NSMutableArray alloc] init];
    
    AttachmentDBAccessor* databaseManager = [AttachmentDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        NSString* query;
        
        if (andInline) {
            query = [NSString stringWithFormat:@"SELECT *  FROM attachments"];
        }
        else {
            query = [NSString stringWithFormat:@"SELECT * FROM attachments WHERE contentID = ''"];
        }
        
        FMResultSet* results = [db executeQuery:query];
        
        while ([results next]) {
            Attachment* attachment = [[Attachment alloc] init];
            
            attachment.pk = [results intForColumn:@"pk"];
            attachment.fileName = [results stringForColumn:@"file_name"];
            if (!attachment.fileName) {
                attachment.fileName = @"";
            }
            attachment.size = [results intForColumn:@"size"];
            attachment.mimeType = [results stringForColumn:@"mime_type"];
            attachment.msgId = [results stringForColumn:@"msg_id"];
            attachment.data = [results dataForColumn:@"data"];
            attachment.partID = [results stringForColumn:@"partID"];
            attachment.contentID = [results stringForColumn:@"contentID"];
            
            [attachments addObject:attachment];
        }
    }];
    
    return attachments;
}

+(NSMutableArray*) getAttachmentsWithMsgId:(NSString*)msgId
{
    
    NSMutableArray* attachments = [[NSMutableArray alloc] init];
    
    AttachmentDBAccessor* databaseManager = [AttachmentDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        FMResultSet* results = [db executeQuery:@"SELECT * FROM attachments WHERE msg_id = ? ", msgId];
        
        while ([results next]) {
            Attachment* attachment = [[Attachment alloc] init];
            
            attachment.pk = [results intForColumn:@"pk"];
            attachment.fileName = [results stringForColumn:@"file_name"];
            if (!attachment.fileName) {
                attachment.fileName = @"";
            }
            attachment.size = [results intForColumn:@"size"];
            attachment.mimeType = [results stringForColumn:@"mime_type"];
            attachment.msgId = [results stringForColumn:@"msg_id"];
            attachment.data = [results dataForColumn:@"data"];
            attachment.partID = [results stringForColumn:@"partID"];
            attachment.contentID = [results stringForColumn:@"contentID"];
            
            [attachments addObject:attachment];
        }
    }];
    
    return attachments;
}

+(NSMutableArray*) getAttachmentsWithMsgId:(NSString*)msgId isInline:(BOOL)isInline
{
    NSMutableArray* attachments = [[NSMutableArray alloc] init];
    
    AttachmentDBAccessor* databaseManager = [AttachmentDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        FMResultSet* results;
        
        if (isInline) {
            results = [db executeQuery:@"SELECT * FROM attachments WHERE msg_id = ? and contentID <> ''", msgId];
        }
        else {
            results = [db executeQuery:@"SELECT * FROM attachments WHERE msg_id = ? and contentID = ''", msgId];
        }
        
        while ([results next]) {
            Attachment* attachment = [[Attachment alloc] init];
            
            attachment.pk = [results intForColumn:@"pk"];
            attachment.fileName = [results stringForColumn:@"file_name"];
            if (!attachment.fileName) {
                attachment.fileName = @"";
            }
            attachment.size = [results intForColumn:@"size"];
            attachment.mimeType = [results stringForColumn:@"mime_type"];
            attachment.msgId = [results stringForColumn:@"msg_id"];
            attachment.data = [results dataForColumn:@"data"];
            attachment.partID = [results stringForColumn:@"partID"];
            attachment.contentID = [results stringForColumn:@"contentID"];
            
            [attachments addObject:attachment];
        }
    }];
    
    return attachments;
}
/*+(BOOL)searchAttachmentswithMsgId:(NSString*)msgId
{
    __block BOOL result = NO;
    
    AttachmentDBAccessor* databaseManager = [AttachmentDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        
        FMResultSet* results = [db executeQuery:@"SELECT pk FROM attachments WHERE msg_id = ?", msgId];
        
        if([results next]) result = YES;
        
        [results close];
    }];
    
    return result;
    
}*/

+(void) updateData:(CCMAttachment*)attachment
{
    AttachmentDBAccessor* databaseManager = [AttachmentDBAccessor sharedManager];
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        [db executeUpdate:@"UPDATE attachments set data = ? WHERE msg_id = ? AND partID = ?", attachment.data, attachment.msgId, attachment.partID];
    }];
}

+(void) clearAttachments
{
    AttachmentDBAccessor* databaseManager = [AttachmentDBAccessor sharedManager];
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        [db executeUpdate:@"UPDATE attachments set data = ? ", nil];
    }];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray* paths = NSSearchPathForDirectoriesInDomains (NSDocumentDirectory, NSUserDomainMask, YES);
    NSString* documentsDirectory = paths[0];
    documentsDirectory = [documentsDirectory stringByAppendingPathComponent:@"AttachmentsCache"];
    
    NSError *error = nil;
    for (NSString *file in [fm contentsOfDirectoryAtPath:documentsDirectory error:&error]) {
        BOOL success = [fm removeItemAtPath:[NSString stringWithFormat:@"%@%@", documentsDirectory, file] error:&error];
        if (!success || error) {
            // it failed.
        }
    }
}

+(void) tableCheck
{
    AttachmentDBAccessor* databaseManager = [AttachmentDBAccessor sharedManager];
    
    [databaseManager.databaseQueue inDatabase:^(FMDatabase* db) {
        
        if (![db executeUpdate:@"CREATE TABLE attachments (pk INTEGER PRIMARY KEY, file_name TEXT, size INTEGER, mime_type TEXT, msg_id VARCHAR(32), data BLOB, partID TEXT, contentID TEXT)"]) {
            CCMLog(@"errorMessage = %@", db.lastErrorMessage);
        }
        
        if (![db executeUpdate:@"CREATE INDEX IF NOT EXISTS attachments_msg_id on attachments(msg_id);"]) {
            CCMLog(@"errorMessage = %@", db.lastErrorMessage);
        }
        
    }];
}

-(BOOL) isEqual:(id)other
{
    if (other == self) {
        return YES;
    }
    
    if (!other || ![other isKindOfClass:[self class]]) {
        return NO;
    }
    
    return [self isEqualToAttachment:other];
}

-(BOOL) isEqualToAttachment:(CCMAttachment*)attachment
{
    if (self == attachment) {
        return YES;
    }
    
    if (![[self data] isEqualToData:[attachment data]]) {
        return NO;
    }
    
    return YES;
}

-(NSUInteger) hash
{
    return [self.data hash];
}

-(BOOL) isInline
{
    return ![self.contentID isEqualToString:@""];
}


@end