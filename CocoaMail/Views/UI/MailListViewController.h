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

@protocol MailListDelegate;


@interface MailListViewController : InViewController <CocoaButtonDatasource>

-(instancetype) initWithFolder:(CCMFolderType)folder;
-(instancetype) initWithPerson:(Person*)person;

-(BOOL) istheSame:(MailListViewController*)other;
-(void) reFetch:(BOOL)forceRefresh;
-(void) removeConversationList:(NSArray*)convs;

@property (nonatomic, weak) UITableView* table;
@property (nonatomic, strong) NSMutableArray* convByDay;
@property (nonatomic, weak) id <UIViewControllerPreviewing> previewingContext;

@end

@protocol MailListDelegate

-(void) removeConversationList:(NSArray*)convs;
-(void) reFetch:(BOOL)forceRefresh;
-(BOOL) isPresentingDrafts;

@end