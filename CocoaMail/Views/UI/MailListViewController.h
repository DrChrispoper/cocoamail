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
-(void) insertConversation:(ConversationIndex*)con;
-(void) removeConversationList:(NSArray*)convs;

@end

@protocol MailListDelegate

-(void) removeConversationList:(NSArray*)convs;
-(void) insertConversation:(ConversationIndex*)con;
-(BOOL) isPresentingDrafts;

@end