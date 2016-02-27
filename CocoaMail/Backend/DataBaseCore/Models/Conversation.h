//
//  Conversation.h
//  CocoaMail
//
//  Created by Christopher Hockley on 26/02/16.
//  Copyright © 2016 Christopher Hockley. All rights reserved.
//

@class Mail;
@class UserSettings;

@interface Conversation : NSObject

@property (nonatomic, strong, readonly) NSMutableArray* mails;

-(NSMutableSet*) foldersType;
-(NSDate*) latestDate;
-(Mail*) firstMail;
-(NSArray*) uidsWithFolder:(NSInteger)folder;
-(BOOL) isInInbox;
-(UserSettings*) user;
-(void) toggleFav;
-(void) addMail:(Mail*)mail;

-(BOOL) hasAttachments;
-(BOOL) isFav;

-(void) moveFromFolder:(NSInteger)fromFolderIdx ToFolder:(NSInteger)toFolderIdx;
-(void) trash;

@end

@interface ConversationIndex : NSObject

@property (nonatomic) NSInteger index;
@property (nonatomic) UserSettings* user;

+(ConversationIndex*) initWithIndex:(NSInteger)index user:(UserSettings*)user;
-(NSDate*) date;
-(NSDate*) day;

@end