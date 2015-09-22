//
//  Accounts.h
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 11/08/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "Persons.h"

@class Conversation;
@class Account;
@class Mail;


typedef enum : NSUInteger {
    QuickSwipeArchive,
    QuickSwipeDelete,
    QuickSwipeReply,
    QuickSwipeMark
} QuickSwipeType;


@interface Accounts : NSObject

+(Accounts*) sharedInstance;

+(NSArray*) systemFolderIcons;
+(NSString*) userFolderIcon;

@property (nonatomic, strong) NSArray* accountColors;
@property (nonatomic) QuickSwipeType quickSwipeType;
@property (nonatomic) BOOL navBarBlurred;

@property (nonatomic) NSInteger defaultAccountIdx;
@property (nonatomic) BOOL showBadgeCount;
// TODO save these config values
@property (nonatomic, strong) NSArray* accounts;
@property (nonatomic) NSInteger currentAccountIdx;

-(Account*) currentAccount;

-(void) addAccount:(Account*)account;
-(BOOL) deleteAccount:(Account*)account;

@end


typedef enum : NSUInteger {
    FolderTypeInbox,
    FolderTypeFavoris,
    FolderTypeSent,
    FolderTypeDrafts,
    FolderTypeAll,
    FolderTypeDeleted,
    FolderTypeSpam,
    FolderTypeUser
} BaseFolderType;

typedef struct FolderType {
    BaseFolderType type;
    NSInteger idx;
} FolderType;

static inline FolderType FolderTypeWith(BaseFolderType t, NSInteger idx)
{
    FolderType type;
    type.type = t;
    type.idx = idx;
    return type;
}

static inline NSInteger encodeFolderTypeWith(FolderType t)
{
    return t.type * 4096 + t.idx;
}

static inline FolderType decodeFolderTypeWith(NSInteger code)
{
    FolderType type;
    type.type = code / 4096;
    type.idx = code % 4096;
    return type;
}


@interface Account : NSObject

@property (nonatomic, getter=codeName, setter=setCodeName:) NSString* codeName;
@property (nonatomic, strong) NSString* userMail;
@property (nonatomic, strong) UIColor* userColor;
@property (nonatomic) NSInteger idx;

@property (nonatomic, strong) NSArray* userFolders;
@property (nonatomic) NSInteger currentFolderIdx;
-(void) setCurrentFolder:(FolderType)folder;
@property (nonatomic, strong) Person* person;

@property (nonatomic) BOOL isAllAccounts;
//
@property (nonatomic) BOOL notificationEnabled;
// TODO save it (config)

+(instancetype) emptyAccount;

-(NSInteger) accountNum;
-(void) initContent;
-(void) releaseContent;

-(void) addConversation:(Conversation*)conv;
-(NSMutableArray*) getConversationsForFolder:(FolderType)type;
-(BOOL) moveConversation:(Conversation*)conversation from:(FolderType)folderFrom to:(FolderType)folderTo;
// return NO if not removed from form folder, YES if really removed

-(NSInteger) unreadInInbox;

-(void) sendMail:(Mail*)mail bcc:(BOOL)isBcc;
-(void) saveDraft:(Mail*)mail;
-(void) deleteDraft:(Mail*)mail;

-(NSArray*) systemFolderNames;

@end
