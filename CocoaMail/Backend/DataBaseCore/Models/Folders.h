//
//  Folders.h
//  CocoaMail
//
//  Created by Andy Cerier on 9/7/16.
//  Copyright © 2016 Christopher Hockley. All rights reserved.
//

#import "AppSettings.h"
#import "Folder.h"
#import "CCMConstants.h"

@interface Folders : NSObject   // IMAP Account Folder Set
// New:
//      All Account Folders 
//
// Factored out of Account:
//      All Account Mail Indecies       - Redundant if System & User folders combined
//      All Account Conversation IDs    - Redundant if System & User folders combined
 

@property (nonatomic) FolderIndex currentFolderIndex;

-(instancetype)init;



-(void)addFolder:(NSString *)folderName ofType:(FolderType)folderType;
-(void)addUserFoldersWithNames:(NSArray *)userFolderNames;

-(void) setCurrentFolder:(FolderIndex)folder;

-(FolderIndex)firstUserFolderIndex;
-(NSUInteger) folderCount;
-(NSUInteger) userFoldersCount;

-(Folder*)folderAtIndex:(FolderIndex)folderIndex;
-(FolderType)folderTypeForFolderAtIndex:(FolderIndex)folderIndex;
-(BOOL)isUserFolder:(FolderIndex)folderIndex;
-(BOOL)isSystemFolder:(FolderIndex)folderIndex;


-(FolderIndex)folderIndexForFolderNamed:(NSString *)folderName;

-(void)setFolders:(NSArray *)folders;


@end

