//
//  Folders.h
//  CocoaMail
//
//  Created by Andy Cerier on 9/7/16.
//  Copyright © 2016 Christopher Hockley. All rights reserved.
//

#import "AppSettings.h"


@interface Folder : NSObject   // IMAP Folder
// Factored out of Account:
//      Folder Name
@property (nonatomic) NSString* IMAPFolderName;
//      Folder Name Contains "/"
@property (nonatomic) BOOL IMAPFolderNameContainsIndentation;
//      Folder Type (System vs. User)
@property (nonatomic) BaseFolderType IMAPFolderType;
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

-(instancetype)initWithType:(BaseFolderType)folderType named:(NSString *)folderName;

@end