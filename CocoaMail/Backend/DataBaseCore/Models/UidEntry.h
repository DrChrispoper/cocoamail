//
//  UidEntry.h
//  CocoaMail
//
//  Created by Christopher Hockley on 20/01/2012.
//  Copyright (c) 2012 Christopher Hockley. All rights reserved.
//

#import <MailCore/MailCore.h>

@class Conversation;

@interface UidEntry : NSObject <NSCopying>{
    NSInteger pk;
    uint32_t uid;
    NSInteger folder;
    NSInteger account;
    NSString* msgId;
    NSString* sonMsgId;
}

@property (assign) NSInteger pk;
@property (nonatomic, readwrite) uint32_t uid;
@property (nonatomic, readwrite) NSInteger folder;
@property (nonatomic, readwrite) NSInteger account;
@property (nonatomic, readwrite,copy) NSString* msgId;
@property (nonatomic, readwrite,copy) NSString* sonMsgId;

+(void) tableCheck;
+(BOOL) addUid:(UidEntry*)uid_entry;
+(BOOL) addUidUnsafe:(UidEntry*)uid_entry;
+(BOOL) removeFromFolderUid:(UidEntry*)uid_entry;
+(BOOL) removeFromAllFoldersUid:(UidEntry*)uid_entry;
+(UidEntry*) getUidEntryAtPk:(NSInteger)pk;
+(NSMutableArray*) getUidEntries;
+(NSMutableArray*) getUidEntriesWithFolder:(NSInteger)folderNum;
+(NSMutableArray*) getUidEntriesFrom:(Conversation*)conversation withFolder:(NSInteger)folderNum;
+(UidEntry*) getUidEntryWithFolder:(NSInteger)folderNum msgId:(NSString*)msgId;
+(NSMutableArray*) getUidEntriesWithMsgId:(NSString*)msgId;
+(BOOL) hasUidEntrywithMsgId:(NSString*)md5hash withFolder:(NSInteger)folderNum;
+(NSMutableArray*) getUidEntriesWithThread:(NSString*)son_msgId;

/// Copy email from origin folder to destination folder.
+(BOOL) moveMsgId:(NSString*)msg_id inFolder:(NSInteger)from toFolder:(NSInteger)to;
+(BOOL) move:(UidEntry*)uidE toFolder:(NSInteger)to;
/// Mark as deleted in the origin folder. Expunge origin folder.
+(BOOL) deleteMsgId:(NSString*)msg_id fromfolder:(NSInteger)folder;
+(BOOL) delete:(UidEntry*)uidE;
+(void) deleteAllfromAccount:(NSInteger)accountN;
/// Add Flag
+(BOOL) addFlag:(MCOMessageFlag)flag to:(UidEntry*)uidE;
+(BOOL) addFlag:(MCOMessageFlag)flag toMsgId:(NSString*)msg_id fromFolder:(NSInteger)folder;
/// Remove Flag
+(BOOL) removeFlag:(MCOMessageFlag)flag toMsgId:(NSString*)msg_id fromFolder:(NSInteger)folder;
+(BOOL) removeFlag:(MCOMessageFlag)flag to:(UidEntry*)uidE;


@end
