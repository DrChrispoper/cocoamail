//
//  Email.h
//  CocoaMail
//
//  Created by Christopher Hockley on 20/01/2012.
//  Copyright (c) 2012 Christopher Hockley. All rights reserved.
//

#import <MailCore/MailCore.h>
#import "FMDB.h"
#import "UidEntry.h"
#import "FMDatabase.h"

@interface Email : NSObject <NSCopying> {
	NSInteger pk;
    MCOAddress* sender;

	NSArray* tos;
	NSArray* ccs;
	NSArray* bccs;
	
	NSDate* datetime;
	
	NSString* msgId;
    
	MCOMessageFlag flag;
	NSString* subject;
	NSString* body;
    NSString* htmlBody;
    
    NSArray* inlineAttachments;
    NSArray* attachments;
    NSArray* uids;
}
//email
@property (assign) NSInteger pk;
@property (nonatomic,readwrite,strong) NSDate* datetime;

@property (nonatomic,readwrite,strong) MCOAddress* sender;

@property (nonatomic,readwrite,copy) NSArray* tos;
@property (nonatomic,readwrite,copy) NSArray* ccs;
@property (nonatomic,readwrite,copy) NSArray* bccs;

@property (nonatomic,readwrite,strong) NSArray* toPersonIDs;

@property (nonatomic,readwrite,copy) NSString* htmlBody;

@property (nonatomic,readwrite,copy) NSString* msgId;
@property (nonatomic,readwrite) MCOMessageFlag flag;

//search
@property (nonatomic,readwrite,copy) NSString* subject;
@property (nonatomic,readwrite,copy) NSString* body;

//ToFetch
@property (nonatomic,readwrite,copy) NSArray* inlineAttachments;
@property (nonatomic,readwrite,copy) NSArray* attachments;
@property (nonatomic,readwrite,copy) NSArray* uids;

@property (assign) BOOL hasAttachments;

- (void)loadData;
- (BOOL)existsLocally;
- (NSInteger)account;
- (UidEntry*)uidEWithFolder:(NSInteger)folderNum;
- (NSString*)getSonID;
- (BOOL)haveSonInFolder:(NSInteger)folderIdx;
- (NSArray*)getSons;
- (void)fetchAllAttachments;

+ (void)tableCheck;
+ (void)tableCheck:(FMDatabase *)db;
+ (NSInteger)insertEmail:(Email *) email;
+ (NSInteger)insertEmailUnsafe:(Email *)email;
+ (void)updateEmailFlag:(Email*)email;
+ (BOOL)removeEmail:(NSString *)msgId;
+ (NSMutableArray *)getEmails;
+ (Email*)resToEmail:(FMResultSet*)result;

- (void)moveFromFolder:(NSInteger)fromFolderIdx ToFolder:(NSInteger)toFolderIdx;
- (void)archive;
- (void)trash;
- (void)star;
- (void)read;

@end


