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

-(instancetype)initWithType:(BaseFolderType)folderType named:(NSString *)folderName
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

@end