//
//  Folders.h
//  CocoaMail
//
//  Created by Andy Cerier on 9/7/16.
//  Copyright © 2016 Christopher Hockley. All rights reserved.
//

#import "AppSettings.h"

typedef NSUInteger FolderIndex;
#define UNSET_INDEX (-1)

typedef NS_ENUM(NSInteger, FolderType) {
    FolderTypeNotSet = 0,
    FolderTypeInbox,
    FolderTypeFavoris,
    FolderTypeSent,
    FolderTypeDrafts,
    FolderTypeAll,
    FolderTypeDeleted,
    FolderTypeSpam,
    FolderTypeOutbox,
    FolderTypeUser
};
#define kLastSystemFolderIndex (FolderTypeOutbox)

@interface Folder : NSObject   // IMAP Folder

//      Folder Name
@property (nonatomic) NSString* IMAPFolderName;
//      Folder Type (System vs. User)
@property (nonatomic) FolderType IMAPFolderType;
//      Folder Name Contains "/"
@property (nonatomic) BOOL IMAPFolderNameContainsIndentation;
//      Folder Icon & Pad  Icon
@property (nonatomic) NSString *icon;
@property (nonatomic) NSString *padIcon;
//      Folder Mail Conversation Indecies
@property (nonatomic) NSArray<NSMutableIndexSet*>* conversations;
//      Move into this Folder rules (special rules for system folders)
//          Can Move to Folder Type
//          Can Move from Folder Type

//      Folder mail message indecies
@property (nonatomic) NSArray<NSMutableIndexSet*>* mailIndecies;

//-(instancetype)initWithName:(NSString *)name;

-(instancetype)initWithType:(FolderType)folderType named:(NSString *)folderName;

-(BOOL)isAllFolder;
-(BOOL)isDraftsFolder;
-(BOOL)isUserFolder;

@end
