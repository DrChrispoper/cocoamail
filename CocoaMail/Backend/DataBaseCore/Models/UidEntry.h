//
//  UidEntry.h
//  CocoaMail
//
//  Created by Christopher Hockley on 20/01/2012.
//  Copyright (c) 2012 Christopher Hockley. All rights reserved.
//

#import <MailCore/MailCore.h>

@class Email;

@interface UidEntry : NSObject <NSCopying>

@property (assign) NSInteger pk;
@property (nonatomic, readwrite) uint32_t uid;
@property (nonatomic, readwrite) NSInteger folder;
@property (nonatomic, readwrite) NSInteger account;
@property (nonatomic, readwrite,copy) NSString* msgId;
@property (nonatomic, readwrite,copy) NSString* sonMsgId;
@property (nonatomic, readwrite) NSInteger dbNum;


+(void) tableCheck;
+(BOOL) addUid:(UidEntry*)uid_entry;
+(BOOL) removeFromFolderUid:(UidEntry*)uid_entry;
+(UidEntry*) getUidEntryAtPk:(NSInteger)pk;
+(NSMutableArray*) getUidEntries;
+(NSMutableArray*) getUidEntriesWithFolder:(NSInteger)folderNum inAccount:(NSInteger)accountIndex;
+(NSMutableArray*) getUidEntriesFrom:(Email*)email withFolder:(NSInteger)folderNum inAccount:(NSInteger)accountIndex;
+(UidEntry*) getUidEntryWithFolder:(NSInteger)folderNum msgId:(NSString*)msgId;
+(NSMutableArray*) getUidEntriesWithMsgId:(NSString*)msgId;
+(BOOL) hasUidEntrywithMsgId:(NSString*)md5hash withFolder:(NSInteger)folderNum;
+(NSMutableArray*) getUidEntriesWithThread:(NSString*)son_msgId;

/// Copy email from origin folder to destination folder.
//+(void) moveMsgId:(NSString*)msg_id inFolder:(NSInteger)from toFolder:(NSInteger)to;
+(void) move:(UidEntry*)uidE toFolder:(NSInteger)to;
/// Mark as deleted in the origin folder. Expunge origin folder.
//+(void) deleteMsgId:(NSString*)msg_id fromfolder:(NSInteger)folder;
+(void) deleteUidEntry:(UidEntry*)uidE;
+(void) deleteAllfromAccount:(NSInteger)accountN;
/// Add Flag
+(BOOL) addFlag:(MCOMessageFlag)flag to:(UidEntry*)uidE;
+(BOOL) addFlag:(MCOMessageFlag)flag toMsgId:(NSString*)msg_id fromFolder:(NSInteger)folder;
/// Remove Flag
+(BOOL) removeFlag:(MCOMessageFlag)flag toMsgId:(NSString*)msg_id fromFolder:(NSInteger)folder;
+(BOOL) removeFlag:(MCOMessageFlag)flag to:(UidEntry*)uidE;

+(NSArray*) dbNumsInAccount:(NSInteger)accountIndex;

@end
