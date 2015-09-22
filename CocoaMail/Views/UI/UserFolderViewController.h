//
//  UserFolderViewController.h
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 08/09/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "InViewController.h"

#import "Accounts.h"


@protocol UserFolderViewControllerDelegate

-(void) chooseUserFolder:(FolderType)folder;
-(void) chooseUserFolderCancel;

@end


@interface UserFolderViewController : InViewController

@property (nonatomic, weak) id<UserFolderViewControllerDelegate> delegate;

@end
