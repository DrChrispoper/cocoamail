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
+(void) addUid:(UidEntry*)uid_entry;
+(void) updateNewUID:(UidEntry*)uid_entry;
+(void) removeFromFolderUid:(UidEntry*)uid_entry;
+(void) removeAllMsgID:(NSString*)msgID;
+(UidEntry*) getUidEntryAtPk:(NSInteger)pk;
+(NSMutableArray*) getUidEntries;
+(NSMutableArray*) getUidEntriesinAccountNum:(NSInteger)accountNum andDelete:(BOOL)haveDeleted;
+(NSMutableArray*) getUidEntriesWithFolder:(NSInteger)folderNum inAccountNum:(NSInteger)accountNum;
+(NSMutableArray*) getUidEntriesFrom:(Mail*)email withFolder:(NSInteger)folderNum inAccountNum:(NSInteger)accountNum;
+(UidEntry*) getUidEntryWithFolder:(NSInteger)folderNum msgID:(NSString*)msgID;
+(NSMutableArray<UidEntry*>*) getUidEntriesWithMsgId:(NSString*)msgID;

+(BOOL) hasUidEntrywithMsgId:(NSString*)msgID withFolder:(NSInteger)folderNum inAccount:(NSInteger)accountNum;
+(BOOL) hasUidEntrywithMsgId:(NSString*)msgID inAccount:(NSInteger)accountNum;

+(NSMutableArray*) getUidEntriesWithThread:(NSString*)son_msgId;

+(void) cleanBeforeDeleteinAccountNum:(NSInteger)accountNum;

/// Copy email from origin folder to destination folder.
+(void) move:(UidEntry*)uidE toFolder:(NSInteger)to;
/// Mark as deleted in the origin folder. Expunge origin folder.
+(void) deleteUidEntry:(UidEntry*)uidE;

+(void) copy:(UidEntry*)uidE toFolder:(NSInteger)to;

/// Add Flag
+(void) addFlag:(MCOMessageFlag)flag to:(UidEntry*)uidE;
//+(void) addFlag:(MCOMessageFlag)flag toMsgId:(NSString*)msg_id fromFolder:(NSInteger)folder;
/// Remove Flag
//+(void) removeFlag:(MCOMessageFlag)flag toMsgId:(NSString*)msg_id fromFolder:(NSInteger)folder;
+(void) removeFlag:(MCOMessageFlag)flag to:(UidEntry*)uidE;

+(NSArray*) dbNumsInAccountNum:(NSInteger)accountNum;

@end
