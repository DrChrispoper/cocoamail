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

@protocol MailListDelegate;


@interface MailListViewController : InViewController <CocoaButtonDatasource>

-(instancetype) initWithFolder:(CCMFolderType)folder;
-(instancetype) initWithPerson:(Person*)person;

-(BOOL) istheSame:(MailListViewController*)other;
-(void) insertConversation:(Conversation*)con;
-(void) updatedConversationList:(NSMutableArray*)convs;

@end

@protocol MailListDelegate

-(void) updatedConversationList:(NSMutableArray*)convs;
-(void) insertConversation:(Conversation*)con;
-(BOOL) isPresentingDrafts;

@end