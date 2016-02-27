//
//  UidEntry.h
//  CocoaMail
//
//  Created by Christopher Hockley on 20/01/2012.
//  Copyright (c) 2012 Christopher Hockley. All rights reserved.
//

#import <MailCore/MailCore.h>

@class Mail;

@interface UidEntry : NSObject <NSCopying>

@property (assign) NSInteger pk;
@property (nonatomic, readwrite) uint32_t uid;
@property (nonatomic, readwrite) NSInteger folder;
@property (nonatomic, readwrite) NSInteger accountNum;
@property (nonatomic, readwrite,copy) NSString* msgID;
@property (nonatomic, readwrite,copy) NSString* sonMsgID;
@property (nonatomic, readwrite) NSInteger dbNum;


+(void) tableCheck;
+(BOOL) addUid:(UidEntry*)uid_entry;
+(BOOL) updateNewUID:(UidEntry*)uid_entry;
+(BOOL) removeFromFolderUid:(UidEntry*)uid_entry;
+(UidEntry*) getUidEntryAtPk:(NSInteger)pk;
+(NSMutableArray*) getUidEntries;
+(NSMutableArray*) getUidEntriesinAccount:(NSInteger)accountIndex andDelete:(BOOL)haveDeleted;
+(NSMutableArray*) getUidEntriesWithFolder:(NSInteger)folderNum inAccount:(NSInteger)accountIndex;
+(NSMutableArray*) getUidEntriesFrom:(Mail*)email withFolder:(NSInteger)folderNum inAccount:(NSInteger)accountIndex;
+(UidEntry*) getUidEntryWithFolder:(NSInteger)folderNum msgID:(NSString*)msgID;
+(NSMutableArray*) getUidEntriesWithMsgId:(NSString*)msgID;
+(BOOL) hasUidEntrywithMsgId:(NSString*)md5hash withFolder:(NSInteger)folderNum;
+(NSMutableArray*) getUidEntriesWithThread:(NSString*)son_msgId;

+(void) cleanBeforeDeleteinAccount:(NSInteger)accountIndex;

/// Copy email from origin folder to destination folder.
+(void) move:(UidEntry*)uidE toFolder:(NSInteger)to;
/// Mark as deleted in the origin folder. Expunge origin folder.
+(void) deleteUidEntry:(UidEntry*)uidE;

+(void) copy:(UidEntry*)uidE toFolder:(NSInteger)to;

/// Add Flag
+(void) addFlag:(MCOMessageFlag)flag to:(UidEntry*)uidE;
+(void) addFlag:(MCOMessageFlag)flag toMsgId:(NSString*)msg_id fromFolder:(NSInteger)folder;
/// Remove Flag
+(void) removeFlag:(MCOMessageFlag)flag toMsgId:(NSString*)msg_id fromFolder:(NSInteger)folder;
+(void) removeFlag:(MCOMessageFlag)flag to:(UidEntry*)uidE;

+(NSArray*) dbNumsInAccount:(NSInteger)accountIndex;

@end
