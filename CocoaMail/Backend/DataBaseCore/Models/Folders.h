//
//  Folders.h
//  CocoaMail
//
//  Created by Andy Cerier on 9/7/16.
//  Copyright © 2016 Christopher Hockley. All rights reserved.
//

#import "AppSettings.h"
#import "Folder.h"

@interface Folders : NSObject   // IMAP Account Folder Set
// New:
//      All Account Folders 
//
// Factored out of Account:
//      All Account Mail Indecies       - Redundant if System & User folders combined
//      All Account Conversation IDs    - Redundant if System & User folders combined

typedef NSInteger FolderIndex;
#define UNSET_INDEX (-1)

@property (nonatomic) FolderIndex currentFolderIndex;

-(instancetype)init;

-(void)addFolder:(NSString *)folderName ofType:(BaseFolderType)folderType;
-(void)addUserFoldersWithNames:(NSArray *)userFolderNames;

-(void) setCurrentFolder:(FolderIndex)folder;

-(BOOL) isSystemFolder:(FolderIndex)folder;

-(FolderIndex)firstUserFolderIndex;

-(NSUInteger) folderCount;
-(NSUInteger) userFoldersCount;

-(BaseFolderType)folderTypeForFolder:(FolderIndex)folderIndex;

-(Folder*)folderAtIndex:(FolderIndex)folderIndex;


@end

