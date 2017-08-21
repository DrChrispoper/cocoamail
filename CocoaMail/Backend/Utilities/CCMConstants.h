//
//  CCMConstants.h
//  CocoaMail
//
//  Created by Christopher Hockley on 26/09/15.
//  Copyright © 2015 Christopher Hockley. All rights reserved.
//

#ifndef CCMConstants_h
#define CCMConstants_h

typedef NS_ENUM(NSUInteger, QuickSwipeType) {
    QuickSwipeArchive,
    QuickSwipeDelete,
    QuickSwipeReply,
    QuickSwipeMark
};

typedef NS_ENUM(NSInteger, BaseFolderType) {
    FolderTypeInbox,
    FolderTypeFavoris,
    FolderTypeSent,
    FolderTypeDrafts,
    FolderTypeAll,
    FolderTypeDeleted,
    FolderTypeSpam,
    FolderTypeUser,
};

typedef struct CCMFolderType{
    BaseFolderType type;
    NSInteger idx;
} CCMFolderType;

static CCMFolderType CCMFolderTypeInbox     = { FolderTypeInbox, 0 };
static CCMFolderType CCMFolderTypeFavoris   = { FolderTypeFavoris, 0 };
static CCMFolderType CCMFolderTypeSent      = { FolderTypeSent, 0 };
static CCMFolderType CCMFolderTypeDrafts    = { FolderTypeDrafts, 0 };
static CCMFolderType CCMFolderTypeAll       = { FolderTypeAll, 0 };
static CCMFolderType CCMFolderTypeDeleted   = { FolderTypeDeleted, 0 };
static CCMFolderType CCMFolderTypeSpam      = { FolderTypeSpam, 0 };


static const NSUInteger kImportantFolderTypeMaxIndex = FolderTypeSpam;
static const NSUInteger kImportantFolderTypeCount = kImportantFolderTypeMaxIndex + 1;
static const NSUInteger kAllFolderTypeCount = FolderTypeUser + 1;

static inline BOOL CCMFolderTypeTypeIsValid(BaseFolderType type)
{
    return ( type >= 0 && type <= kImportantFolderTypeMaxIndex );
}

static inline CCMFolderType FolderTypeWith(BaseFolderType t, NSInteger idx)
{
    CCMFolderType type;
    type.type = t;
    type.idx = idx;
    
    return type;
}

static inline CCMFolderType inboxFolderType()
{
    return FolderTypeWith(FolderTypeInbox, 0);
}

static inline CCMFolderType allFolderType()
{
    return FolderTypeWith(FolderTypeAll, 0);
}

static inline NSUInteger encodeFolderTypeWith(CCMFolderType t)
{
    BaseFolderType folderType = t.type;
    
    if ( CCMFolderTypeTypeIsValid(folderType) == FALSE ) {
        DDLogError(@"Bad CCMFolderType.type value %@",@(folderType));
        return 0;
    }
    return (t.type * 4096) + (NSUInteger)t.idx;
}

static inline NSNumber* numberWithFolderType(BaseFolderType t)
{
    return @(encodeFolderTypeWith(FolderTypeWith(t, 0)));
}

static inline CCMFolderType decodeFolderTypeWith(NSInteger code)
{
    BaseFolderType folderType = (BaseFolderType)(code / 4096);
    
    if ( CCMFolderTypeTypeIsValid(folderType) == FALSE ) {
        DDLogError(@"Bad CCMFolderType.type value %@",@(folderType));
        return inboxFolderType(); // needed something herer, so used inbox folder type
    }
    CCMFolderType type;
    type.type = (BaseFolderType)(code / 4096);
    type.idx = code % 4096;
    
    return type;
}

static inline BOOL folderTypeIsUserFolder(CCMFolderType folder)
{
    return ( folder.type == FolderTypeUser );
}
static inline BOOL folderTypeIsSystemFolder(CCMFolderType folder)
{
    // If a folder is not a user folder, then it is a system folder
    return ( ! folderTypeIsUserFolder(folder) );
}
#endif /* CCMConstants_h */
