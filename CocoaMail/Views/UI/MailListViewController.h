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
#import "InViewController.h"
#import "AttachmentsViewController.h"
#import "CCMConversationsByDay.h"

//@protocol MailListDelegate;
@class ConversationIndex;

@interface MailListViewController : InViewController <CocoaButtonDatasource>

-(instancetype) initWithFolder:(CCMFolderType)folder;
-(instancetype) initWithPerson:(Person*)person;

-(BOOL) istheSame:(MailListViewController*)other;
-(void) reFetch:(BOOL)forceRefresh;
-(void) removeConversationList:(NSArray<ConversationIndex*>*)convs;

@property (nonatomic, weak) UITableView* tableView;
@property (nonatomic, strong) CCMConversationsByDay *convByDay;
@property (nonatomic, weak) id <UIViewControllerPreviewing> previewingContext;
@property (nonatomic, weak) AttachmentsViewController* attachSubscriber;

@end

@protocol MailListDelegate

-(void) localSearchDone:(BOOL)done;
-(void) serverSearchDone:(BOOL)done;
-(void) removeConversationList:(NSArray<ConversationIndex*>*)convs;
-(void) updateDays:(NSArray<NSString*>*)days;
-(void) reFetch:(BOOL)forceRefresh;
-(BOOL) isPresentingDrafts;
-(void) insertConversationIndex:(ConversationIndex*)ci;
-(void) reloadTableView;

@end
