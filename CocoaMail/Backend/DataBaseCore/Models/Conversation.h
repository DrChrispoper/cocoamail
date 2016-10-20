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

// Mails in this Conversation
// TODO: Might the "mails" array be a "Folder"?
@property (nonatomic, strong, readonly) NSMutableArray* mails;
@property (nonatomic) BOOL isDraft;

-(NSMutableSet*) folders;

-(NSDate*) latestDate;
-(Mail*) firstMail;
-(NSArray*) uidsWithFolder:(NSInteger)folder;
-(BOOL) isInFolder:(NSInteger)folderNum;
-(BOOL) isInInbox;
-(UserSettings*) user;
-(void) toggleFav;
-(void) addMail:(Mail*)mail;

-(BOOL) hasAttachments;
-(BOOL) isFav;
-(BOOL) isUnread;

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
