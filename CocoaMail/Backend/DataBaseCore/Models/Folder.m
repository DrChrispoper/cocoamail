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
#import "Folder.h"

@implementation Folder

-(instancetype)initWithType:(FolderType)folderType named:(NSString *)folderName
{
    self = [super init];
    if (self) {
        self.IMAPFolderName = [NSString stringWithString:folderName];
#warning Is '/' guaranteed to be the only mailbox path connector?
        self.IMAPFolderNameContainsIndentation = [folderName containsString:@"/"];
        self.IMAPFolderType = folderType;
    }
    return self;
}

-(BOOL)isAllFolder
{
    return (self.IMAPFolderType == FolderTypeAll);
}
-(BOOL)isDraftsFolder
{
    return (self.IMAPFolderType == FolderTypeDrafts);
}
-(BOOL)isUserFolder
{
    return (self.IMAPFolderType >= FolderTypeUser);
}

@end
