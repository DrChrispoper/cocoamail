//
//  Folders.m
//  CocoaMail
//
//  Created by Andy Cerier on 9/7/16.
//  Copyright © 2016 Christopher Hockley. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "AppSettings.h"
#import "Folders.h"
#import <CocoaLumberjack/CocoaLumberjack.h>

#define ARIBITRARY_NUMBER_OF_FOLDERS    500

@implementation Folders {
    NSMutableArray *_folders;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _folders = [[NSMutableArray alloc] initWithCapacity:ARIBITRARY_NUMBER_OF_FOLDERS];
        self.currentFolderIndex = UNSET_INDEX;
        [self _addSystemFolders];
    }
    return self;
}


- (void)_addSystemFolders
{
    [self addFolder:NSLocalizedString(@"Inbox", @"Inbox")
             ofType:FolderTypeInbox];
    [self addFolder:NSLocalizedString(@"Favoris", @"Favoris")
             ofType:FolderTypeFavoris];
    [self addFolder:NSLocalizedString(@"Sent", @"Sent")
             ofType:FolderTypeSent];
    [self addFolder:NSLocalizedString(@"Drafts", @"Drafts")
             ofType:FolderTypeDrafts];
    [self addFolder:NSLocalizedString(@"All emails", @"All emails")
             ofType:FolderTypeAll];
    [self addFolder:NSLocalizedString(@"Deleted", @"Deleted")
             ofType:FolderTypeDeleted];
    [self addFolder:NSLocalizedString(@"Spam", @"Spam")
             ofType:FolderTypeSpam];
    [self addFolder:NSLocalizedString(@"Outbox", @"Outbox")
             ofType:FolderTypeOutbox];
    
}
- (FolderIndex)_lastFolderIndex
{
    return [_folders count] - 1;
}

- (BOOL)_validFolderIndex:(FolderIndex)folderIndex
{
    return ( folderIndex >= 0 && folderIndex <= [self _lastFolderIndex]);
}

// ALL add Folder calls should go through here
-(void)addFolder:(NSString *)folderName ofType:(BaseFolderType)folderType;
{
    Folder *newFolder = [[Folder alloc] initWithType:folderType
                                               named:folderName];
    if ( newFolder == nil) {
        DDLogError(@"Failed to create a new Folder.");
    } else {
        [_folders addObject:newFolder];

        if ( folderType == FolderTypeUser ) {
            // Do User Folder specific initialization
            
            // TODO Add User Folder Icon
        } else {
            // Do System Folder specific initialization
            
            // Assure System Folder type value equals its folder index
            FolderIndex lastIndex = [self _lastFolderIndex];
            DDAssert(lastIndex == folderType, @"System Folder Index (%lu) MUST EQUAL Base Type (%lu)",
                     (unsigned long)lastIndex, (unsigned long)folderType);
            
            // TODO Add System Folder Icon and PadIcon
        }
        
        // Add remaining
        
    }
    
}
-(void) setCurrentFolder:(FolderIndex)folderIndex
{
#warning AJC: is -1 (UNSET_INDEX) valid?
    
    if ( [self _validFolderIndex:folderIndex] ) {
        self.currentFolderIndex = folderIndex;
        
    } else {
        DDLogError(@"Not a valid folder index (%lu)",folderIndex);
    }
}


-(void)addUserFoldersWithNames:(NSArray <NSString *>*)userFolderNames
{
    for (NSString *folderName in userFolderNames) {
        [self addFolder:folderName  ofType:FolderTypeUser];
    }
}

-(FolderIndex)firstUserFolderIndex
{
    FolderIndex folderIndex = 0;
    
    for ( Folder *folder in _folders ) {
        if ( folder.IMAPFolderType == FolderTypeUser) {
            // We found thei first User Folder
            return folderIndex;
        } else {
            folderIndex++;
        }
    }
    DDLogError(@"Could not find first User Folder. Folder Count = %lu",(unsigned long)[self folderCount]);
    
    return -1;
}

-(NSUInteger) folderCount
{
    return [_folders count];
}
-(NSUInteger) userFoldersCount
{
    NSUInteger folderIndex = 0;
    NSUInteger allFolderCount = [self folderCount];
    
    // Find first folder of tye user
    for (; folderIndex < allFolderCount; folderIndex ++)
#warning AJC: WIP
    return count;
}

-(BOOL) isSystemFolder:(FolderIndex)folder
{
    
}


-(BaseFolderType)folderTypeForFolder:(FolderIndex)folderIndex
{
    if ( folderIndex > kLastSystemFolderIndex ) {
        return FolderTypeUser;
    }
    return (BaseFolderType)folderIndex;
}

// Returns NIL on bad inde
-(Folder*)folderAtIndex:(FolderIndex)folderIndex
{
    Folder *folder = nil;
    
    if ( [self _validFolderIndex:folderIndex] ) {
        folder = _folders[folderIndex];
    }
    return folder;
}


@end

