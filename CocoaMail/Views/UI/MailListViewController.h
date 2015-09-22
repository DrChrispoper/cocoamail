//
//  MailListViewController.h
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 16/07/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "ViewController.h"
#import "CocoaButton.h"
#import "Persons.h"
#import "Accounts.h"

@interface MailListViewController : InViewController <CocoaButtonDatasource>

-(instancetype) initWithFolder:(FolderType)folder;
-(instancetype) initWithPerson:(Person*)person;

-(BOOL) istheSame:(MailListViewController*)other;

@end
