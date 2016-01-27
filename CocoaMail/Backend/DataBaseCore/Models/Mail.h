//
//  Mail.h
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 16/07/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import <Foundation/Foundation.h>

#import "Attachments.h"
#import "Email.h"


@interface Mail : NSObject

@property (nonatomic) NSInteger fromPersonID;
@property (nonatomic, strong) NSArray* toPersonID;
@property (nonatomic, strong) NSString* title;
@property (nonatomic, strong) NSString* content;
@property (nonatomic, strong) NSString* transferContent;

@property (nonatomic, strong) NSDate* date;

@property (nonatomic, strong) NSString* day;
@property (nonatomic, strong) NSString* hour;

@property (nonatomic, strong) Email* email;

@property (nonatomic, strong) Mail* fromMail;

-(Mail*) replyMail:(BOOL)replyAll;
-(Mail*) transfertMail;
+(Mail*) mail:(Email*)email;
-(NSData*) rfc822DataWithAccountIdx:(NSInteger)idx isBcc:(BOOL)isBcc;

-(NSArray*) attachments;
-(void) setAttachments:(NSArray*)attachments;
-(BOOL) haveAttachment;

-(BOOL) isFav;
-(BOOL) isRead;
-(void) toggleFav;
-(void) toggleRead;

-(NSString*) mailID;

+(NSInteger) isTodayOrYesterday:(NSString*)dateString;
+(Mail*) newMailFormCurrentAccount;


@end


@interface Conversation : NSObject

@property (nonatomic, strong, readonly) NSMutableArray* mails;

-(NSMutableSet*) foldersType;
-(NSDate*) latestDate;
-(Mail*) firstMail;
-(NSArray*) uidsWithFolder:(NSInteger)folder;
-(BOOL) isInInbox;
-(NSInteger) accountIdx;
-(void) toggleFav;
-(void) addMail:(Mail*)mail;

-(BOOL) haveAttachment;
-(BOOL) isFav;

-(void) moveFromFolder:(NSInteger)fromFolderIdx ToFolder:(NSInteger)toFolderIdx;
-(void) trash;

@end

@interface ConversationIndex : NSObject

@property (nonatomic) NSInteger index;
@property (nonatomic) NSInteger account;

+(ConversationIndex*) initWithIndex:(NSInteger)index Account:(NSInteger)account;
-(NSDate*) date;
-(NSDate*) day;

@end
