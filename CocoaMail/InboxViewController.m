//
//  InboxViewController.m
//  CocoaMail
//
//  Created by Christopher Hockley on 19/08/15.
//  Copyright (c) 2015 Christopher Hockley. All rights reserved.
//

#import "InboxViewController.h"

#import "AppSettings.h"
#import "AppDelegate.h"

#import "Reachability.h"

#import "EmailProcessor.h"
#import "SearchRunner.h"
#import "SyncManager.h"
#import "ImapSync.h"

#import "CCMAttachment.h"

@interface InboxViewController (){
    CRefreshCompletionHandler _completionHandler;
    
    NSMutableArray *_allEmailData;
    NSMutableArray *_headEmailData;
    NSMutableArray *_cachedEmailData;
    
    NSMutableSet *_allEmailIDs;
    NSMutableSet *_cachedEmailIDs;
    
    BOOL _showingEmail;
    BOOL _localFetchComplete;
    
    UIRefreshControl *_refreshControl;

    NSArray *_contacts;
}

@property (nonatomic, retain) NSOperationQueue *localFetchQueue;

@end

@implementation InboxViewController

- (id)initWithCoder:(NSCoder *)aDecoder
{
    if(self = [super initWithCoder:aDecoder]){
        _showingEmail = NO;
        self.folderChanged = NO;
    }
    return self;
}

- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    EmailProcessor* ep = [EmailProcessor getSingleton];
    ep.updateSubscriber = self;
    
    if(self.folderChanged) [self folderSelected];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    if (!kisActiveAccountAll && [AppSettings allFoldersNameforAccountIndex:kActiveAccountIndex].count == 0) {
        [self performSegueWithIdentifier:@"PROFIL_FINISH" sender:self];
    }
    
    if(_selectedIndexPath){
        [_headEmailData[_selectedIndexPath.row] loadData];
        [self.tableView reloadRowsAtIndexPaths:@[_selectedIndexPath] withRowAnimation:UITableViewRowAnimationFade];
    }
    
    if(animated) {
        _showingEmail = NO;
        [self.tableView reloadData];
    }
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    
    if (!_headEmailData) {
        _headEmailData = [[NSMutableArray alloc] initWithCapacity:1];
    }
    if (!_allEmailData) {
        _allEmailData = [[NSMutableArray alloc] initWithCapacity:1];
    }
    if (!_allEmailIDs) {
        _allEmailIDs = [[NSMutableSet alloc] initWithCapacity:1];
    }
    if (!_cachedEmailData) {
        _cachedEmailData = [[NSMutableArray alloc] initWithCapacity:1];
    }
    
    self.localFetchQueue = [NSOperationQueue new];
    [self.localFetchQueue setMaxConcurrentOperationCount:1];
    _localFetchComplete = YES;
    
    UINib *celTablelNib = [UINib nibWithNibName:@"EmailTableCell" bundle:nil];
    
    [self.tableView registerNib:celTablelNib forCellReuseIdentifier:@"EmailTableCell"];
    self.tableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    self.definesPresentationContext = YES;
    
    //PullToRefresh
    _refreshControl = [[UIRefreshControl alloc] init];
    [_refreshControl addTarget:self action:@selector(startRefresh)
              forControlEvents:UIControlEventValueChanged];
    [self.tableView addSubview:_refreshControl];

    
    [self doLoadServer:YES];
}

#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return _headEmailData.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell" forIndexPath:indexPath];

    Email *object = _headEmailData[indexPath.row];
    cell.textLabel.text = [object subject];
    return cell;
}

#pragma mark - Fetch Data

- (void)folderSelected
{
    _headEmailData = [[NSMutableArray alloc] initWithCapacity:1];
    _allEmailData = [[NSMutableArray alloc] initWithCapacity:1];
    _allEmailIDs = [[NSMutableSet alloc] initWithCapacity:1];
    [self.tableView reloadData];
    
    [self runLoadData];
}

- (void)doLoadServer:(BOOL)refresh
{
    BOOL __block new = NO;
    //[_cocoaButton.activityServerIndicatorView startAnimating];
    
    Reachability *networkReachability = [Reachability reachabilityForInternetConnection];
    NetworkStatus networkStatus = [networkReachability currentReachabilityStatus];
    if (networkStatus == NotReachable) {
        //[_cocoaButton.activityServerIndicatorView stopAnimating];
        [_refreshControl endRefreshing];
    } else {
        
        RACSignal *newEmailsSignal = [[[SyncManager getSingleton] syncActiveFolderFromStart:refresh] deliverOn:[RACScheduler mainThreadScheduler]];
        
        [newEmailsSignal subscribeNext:^(Email *email) {
            new = YES;
            [self insertRows:email];
        } error:^(NSError *error) {
            CCMLog(@"Error: %@",error.localizedDescription);
            //[_cocoaButton.activityServerIndicatorView stopAnimating];
            [_refreshControl endRefreshing];
        } completed:^{
            if (!new) {
                
            }
            
            //[_cocoaButton.activityServerIndicatorView stopAnimating];
            [_refreshControl endRefreshing];
            
            [self importantFoldersRefresh:2];
        }];
    }
}

- (void)runLoadData
{
    if(_localFetchComplete){
        _localFetchComplete = NO;
        [self.localFetchQueue addOperationWithBlock:^{
            [[[SearchRunner getSingleton] activeFolderSearch:_allEmailData.count]
             subscribeNext:^(Email *email) {
                 [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                     [self insertRows:email];
                 }];
             }
             completed:^{
                 [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                     _localFetchComplete = YES;
                     
                     if (!kisActiveAccountAll) {
                         if (_allEmailData.count != 0){
                             [[ImapSync sharedServices] runUpToDateTest:_allEmailData completed:^{
                                 //_serverTestComplete = YES;
                                 //[ViewController animateCocoaButtonRefresh:(_serverTestComplete&&_serverFetchComplete)];
                             }];
                         }
                     }
                     else {
                         for (NSInteger accountIndex = 0; accountIndex < [AppSettings numActiveAccounts]; accountIndex++) {
                             if (_allEmailData.count != 0){
                                 [[ImapSync sharedServices:accountIndex] runUpToDateTest:_allEmailData completed:^{
                                     //_serverTestComplete = YES;
                                     //[ViewController animateCocoaButtonRefresh:(_serverTestComplete&&_serverFetchComplete)];
                                 }];
                             }
                         }
                     }
                 }];
             }];
        }];
    }
}

#pragma mark - Process Data

- (void)insertRows:(Email *)email
{
    email.hasAttachments |= [CCMAttachment searchAttachmentswithMsgId:email.msgId];
    
    if (![email uidEWithFolder:[[Accounts sharedInstance].currentAccount currentFolderIdx]]) {
        CCMLog(@"Issue adding email but not in active folder");
        return;
    }
    
    for (Email * mail in _allEmailData) {
        if ([mail.msgId isEqualToString:email.msgId]) {
            CCMLog(@"Email already loaded");
            return;
        }
    }
    
    [_allEmailData addObject:email];
    
    NSSortDescriptor* sortByDate = [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(datetime)) ascending:NO];
    [_headEmailData sortUsingDescriptors:@[sortByDate]];
    
    [self.tableView reloadData];
}

#pragma mark - Data Update

- (void)deliverUpdate:(NSArray *)emails
{
    [self emailUpdate:emails];
}

- (void)deliverDelete:(NSArray *)emails
{
    [self emailDeleted:emails];
}

- (void)emailDeleted:(NSArray *)emails
{
    for (Email *email in emails) {
        for(int i = 0; i < [_headEmailData count]; i++) {
            Email* tempEmail = _headEmailData[i];
            if([tempEmail.msgId isEqualToString:email.msgId]) {
                [_headEmailData removeObjectAtIndex:i];
                [self removeEmail:email.msgId];
                [self.tableView deleteRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:i inSection:0]] withRowAnimation:UITableViewRowAnimationFade];
                
                break;
            }
        }
        [self.tableView reloadData];
    }
}

- (void)cellDelete:(NSIndexPath *)ip{
    [_headEmailData removeObjectAtIndex:ip.row];
    [self.tableView deleteRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationFade];
}

- (void)removeEmail:(NSString *)msgId{
    for (int i = 0;i<_allEmailData.count;i++) {
        if ([[_allEmailData[i] msgId] isEqualToString:msgId]) {
            [_allEmailData removeObjectAtIndex:i];
            break;
        }
    }
}

- (void)emailUpdate:(NSArray *)emails
{
    for (Email *email in emails) {
        for(int i = 0; i < [_headEmailData count]; i++) {
            Email* tempEmail = _headEmailData[i];
            
            if([tempEmail.msgId isEqualToString:email.msgId]) {
                tempEmail.flag |= email.flag;
                [_headEmailData setObject:tempEmail atIndexedSubscript:i];
                
                [self.tableView reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:i inSection:0]] withRowAnimation:UITableViewRowAnimationFade];
                break;
            }
        }
    }
}

#pragma mark - view unload

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    SearchRunner *sem = [SearchRunner getSingleton];
    [sem cancel];
    
    EmailProcessor* ep = [EmailProcessor getSingleton];
    ep.updateSubscriber = nil;
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    _headEmailData = nil;
}

#pragma mark - Background Sync

- (void)refreshWithCompletionHandler:(CRefreshCompletionHandler)completionHandler
{
    _completionHandler = completionHandler;
    if (!_cachedEmailIDs) {
        CCMLog(@"%lu email IDS",(unsigned long)_allEmailIDs.count);
        _cachedEmailIDs = _allEmailIDs;
    }
    
    RACSignal *newEmailsSignal = [[[SyncManager getSingleton] syncInboxFoldersBackground] deliverOn:[RACScheduler mainThreadScheduler]];
    
    BOOL __block hasNewEmail = NO;
    [newEmailsSignal subscribeNext:^(Email *email) {
        CCMLog(@"%lu cached Emails",(unsigned long)_cachedEmailIDs.count);
        if (![email uidEWithFolder:[[Accounts sharedInstance].currentAccount currentFolderIdx]]) {
            CCMLog(@"Issue adding email but not active folder");
            return;
        }
        if (![_cachedEmailIDs containsObject:email.msgId]) {
            hasNewEmail = YES;
            CCMLog(@"Adding emails in cache: %@",email.subject);
            [_cachedEmailData addObject:email];
            [_cachedEmailIDs addObject:email.msgId];
            [self insertRows:email];
            CCMLog(@"%lu cached Emails",(unsigned long)_cachedEmailIDs.count);
        }
    } error:^(NSError *error) {
        _completionHandler(hasNewEmail);
    } completed:^{
        _completionHandler(hasNewEmail);
    }];
}


-(void)startRefresh
{
    Reachability *networkReachability = [Reachability reachabilityForInternetConnection];
    NetworkStatus networkStatus = [networkReachability currentReachabilityStatus];
    if (networkStatus == NotReachable) {
        //self.navigationItem.title = @"There IS NO internet connection";
        //[self dismissAfter:3.0];
    }
    else {
        [self doLoadServer:YES];
    }
}

- (void)importantFoldersRefresh:(NSInteger)pFolder
{
    NSInteger __block folder = pFolder;
    
    //If last important folder start full sync
    if (folder >= 4) {
        [self foldersSync];
        return;
    }
    
    if(_showingEmail)return;
    
    [[[SyncManager getSingleton] refreshImportantFolder:folder]
     subscribeNext:^(Email *email) {}
     error:^(NSError *error) { CCMLog(@"Error: %@",error.localizedDescription);}
     completed:^{
         CCMLog(@"Important Folders refresh completed");
         [self importantFoldersRefresh:++folder];
     }];
}

- (void)foldersSync
{
    if(_showingEmail)return;
    
    [[[SyncManager getSingleton] syncFolders]
     subscribeNext:^(Email *email) {}
     error:^(NSError *error) {
         CCMLog(@"Error: %@",error.localizedDescription);
     }
     completed:^{
         CCMLog(@"Important folders sync completed");
         //if(![AppSettings isFirstFullSyncDone]){
             [self foldersSync];
         //}
     }];
}


@end
