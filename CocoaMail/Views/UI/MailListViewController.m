//
//  MailListViewController.m
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 16/07/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "MailListViewController.h"
#import "ConversationTableViewCell.h"
#import "Email.h"
#import "Mail.h"
#import "Attachments.h"
#import "Accounts.h"
#import "EmailProcessor.h"
#import "AppSettings.h"
#import "DateUtil.h"
#import "SyncManager.h"
#import "SearchRunner.h"
#import "ImapSync.h"
#import "UserFolderViewController.h"
#import <ReactiveCocoa/ReactiveCocoa.h>


@interface MailListViewController () <UITableViewDataSource, UITableViewDelegate, ConversationCellDelegate, UserFolderViewControllerDelegate, MailListDelegate>

@property (nonatomic, strong) NSMutableArray* convByDay;
@property (nonatomic, strong) NSMutableIndexSet* indexSet;
@property (nonatomic, weak) UITableView* table;

@property (nonatomic, strong) NSString* folderName;

@property (nonatomic, strong) NSMutableSet* selectedCells;

@property (nonatomic, strong) Person* onlyPerson;

@property (nonatomic) BOOL presentAttach;

@property (nonatomic, retain) NSOperationQueue* localFetchQueue;

@property (nonatomic) CCMFolderType folder;

@property (nonatomic) BOOL longPressOnCocoabutton;

@property (nonatomic, strong) UserFolderViewController* chooseUserFolder;

@end

@implementation MailListViewController

-(instancetype) initWithName:(NSString*)name
{
    self = [super init];
    self.folderName = name;
    
    self.selectedCells = [[NSMutableSet alloc] initWithCapacity:25];
    
    return self;
}

-(instancetype) initWithFolder:(CCMFolderType)folder
{
    NSString* name = nil;
    
    if (folder.type == FolderTypeUser) {
        name = [[Accounts sharedInstance] currentAccount].userFolders[folder.idx][0];
    }
    else {
        name = [[[Accounts sharedInstance] currentAccount] systemFolderNames][folder.type];
    }
    
    self = [self initWithName:name];
    self.folder = folder;
    self.presentAttach = NO;

    return self;
}

-(instancetype) initWithPerson:(Person*)person
{
    self = [self initWithName:person.name];
    
    self.onlyPerson = person;
    self.folder = FolderTypeWith(FolderTypeAll, 0);
    self.presentAttach = YES;
    
    return self;
}

-(BOOL) istheSame:(MailListViewController*)other
{
    if (self.onlyPerson!=nil) {
        return self.onlyPerson == other.onlyPerson;
    }
    
    if (self.folder.type != FolderTypeUser) {
        return (self.folder.type == other.folder.type);
    }
    else if (other.folder.type == FolderTypeUser) {
        return other.folder.idx == self.folder.idx;
    }
    
    return NO;
}

-(void) _applyTrueTitleViewTo:(UINavigationItem*)item
{
    UILabel* l = [WhiteBlurNavBar titleViewForItemTitle:self.folderName];
    item.titleView = l;
}

-(void) viewDidLoad
{
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIGlobal standardLightGrey];
    
    self.localFetchQueue = [NSOperationQueue new];
    [self.localFetchQueue setMaxConcurrentOperationCount:1];
    
    self.convByDay = [[NSMutableArray alloc]initWithCapacity:100];
    self.indexSet = [[NSMutableIndexSet alloc]init];
    
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    
    UINavigationItem* item = [[UINavigationItem alloc] initWithTitle:@""];
    
    item.leftBarButtonItem = [self backButtonInNavBar];
    
    [self _applyTrueTitleViewTo:item];
    
    if (self.presentAttach) {
        UIButton* attach = [WhiteBlurNavBar navBarButtonWithImage:@"attachment_off" andHighlighted:@"attachment_on"];
        [attach addTarget:self action:@selector(_attach) forControlEvents:UIControlEventTouchUpInside];
        item.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:attach];
    }
    
    UITableView* table = [[UITableView alloc] initWithFrame:CGRectMake(0,
                                                                       0,
                                                                       screenBounds.size.width,
                                                                       screenBounds.size.height - 20)
                                                      style:UITableViewStyleGrouped];
    
    
    CGFloat offsetToUse = 44.f;
    
    if (self.onlyPerson) {
        // TODO edit content + add edit codeName
        UIView* header = [[UIView alloc] initWithFrame:CGRectMake(0, -92, screenBounds.size.width, 92)];
        header.backgroundColor = [UIColor whiteColor];
        
        
        UIView* badge = [self.onlyPerson badgeView];
        badge.center = CGPointMake(33 + 13, 46);
        badge.transform = CGAffineTransformMakeScale(2.f, 2.f);
        [header addSubview:badge];
        
        UILabel* l = [[UILabel alloc] initWithFrame:CGRectMake(26 + 66, 31, screenBounds.size.width -(66 + 26) - 13, 30)];
        l.backgroundColor = header.backgroundColor;
        l.text = self.onlyPerson.email;
        l.font = [UIFont systemFontOfSize:16];
        l.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        
        [header addSubview:l];
        
        
        UIView* line = [[UIView alloc] initWithFrame:CGRectMake(0, 0, screenBounds.size.width, 0.5)];
        line.backgroundColor = [UIGlobal standardLightGrey];
        
        line.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        [header addSubview:line];
        
        [table addSubview:header];
        
        offsetToUse += 92;
    }
    
    table.contentInset = UIEdgeInsetsMake(offsetToUse, 0, 60, 0);
    
    table.scrollIndicatorInsets = UIEdgeInsetsMake(44, 0, 0,0.5);
    table.allowsSelection = false;
    table.rowHeight = 90;
    table.separatorStyle = UITableViewCellSeparatorStyleNone;
    table.backgroundColor = [UIGlobal standardLightGrey];
    
    [self.view addSubview:table];
    
    [self setupNavBarWith:item overMainScrollView:table];
    
    table.dataSource = self;
    table.delegate = self;
    self.table = table;
    

    UIView* headerView = [[UIView alloc] init];
    headerView.backgroundColor = self.table.backgroundColor;
    
    UIButton* button = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [button addTarget:self
               action:@selector(loadMoreServer)
     forControlEvents:UIControlEventTouchDown];
    
    
    [button setEnabled:NO];
    [button setTitle:@"Loading..." forState:UIControlStateNormal];
    
    
    button.frame = CGRectMake(0.0, 0.0, [UIScreen mainScreen].bounds.size.width , 40.0);
    
    [headerView addSubview:button];
    
    self.table.tableFooterView = headerView;
    
    if (!self.onlyPerson) {
        [self addPullToRefreshWithDelta:0];
        //[self.localFetchQueue addOperationWithBlock:^{
        if (self.convByDay.count == 0) {
            [self setupData];
        }
        //}];
    }
}

-(Conversation*) _createAttachs
{
    Conversation* c = [[Conversation alloc] init];
    
    // keep only mail sent by onlyPerson with attachment
    //NSMutableArray* tmp = [NSMutableArray arrayWithCapacity:500];
    for (NSDictionary* d in self.convByDay) {
        NSArray* convs = d[@"list"];
        
        for (ConversationIndex* cI in convs) {
            Conversation* c = [[Accounts sharedInstance] conversationForCI:cI];
            for (Mail* m in c.mails) {
                if ([m haveAttachment]) {
                    if ([m.email.sender.mailbox isEqualToString:self.onlyPerson.email]) {
                        [c addMail:m];
                    }
                }
            }
        }
    }
    
    //c.mails = tmp;
    
    // to have the right title in next VC
    //[c firstMail].title = self.onlyPerson.name;
    
    return c;
}

-(void) _attach
{
    Conversation* c = [self _createAttachs];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kPRESENT_CONVERSATION_ATTACHMENTS_NOTIFICATION object:nil
                                                      userInfo:@{kPRESENT_CONVERSATION_KEY:c}];
}

-(NSArray*) nextViewControllerInfos
{
    if (self.presentAttach) {
        Conversation* c = [self _createAttachs];
        
        return @[kPRESENT_CONVERSATION_ATTACHMENTS_NOTIFICATION, c];
    }
    
    return [super nextViewControllerInfos];
}

-(void) cleanBeforeGoingBack
{
    self.table.delegate = nil;
    self.table.dataSource = nil;
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];

    BOOL setHidden = YES;

    if ([Accounts sharedInstance].currentAccount.isAllAccounts) {
        for (Account* ac in [Accounts sharedInstance].accounts) {
            if (!ac.isAllAccounts) {
                if (![[[SyncManager getSingleton] retrieveState:[AppSettings numFolderWithFolder:self.folder forAccountIndex:ac.idx] accountIndex:ac.idx][@"fullsynced"] boolValue]) {
                    setHidden = NO;
                    break;
                }
            }
        }
    }
    else {
        setHidden = [[[SyncManager getSingleton] retrieveState:[AppSettings numFolderWithFolder:self.folder forAccountIndex:[Accounts sharedInstance].currentAccountIdx] accountIndex:[Accounts sharedInstance].currentAccountIdx][@"fullsynced"] boolValue];
    }
    
    [self.table.tableFooterView setHidden:setHidden];

    
    [self.table reloadData];
    
}

-(void) viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    [[Accounts sharedInstance].currentAccount showProgress];

    if ([Accounts sharedInstance].accountsCount ==  1) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kCREATE_FIRST_ACCOUNT_NOTIFICATION object:nil];
    }
    else {
        
        [ViewController animateCocoaButtonRefresh:YES];
        
        if (self.onlyPerson) {
            [[Accounts sharedInstance].currentAccount doPersonSearch:@[self.onlyPerson]];
        }
    }
}

-(void) viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    [ViewController animateCocoaButtonRefresh:NO];
}

-(void) setupData
{
    if (kisActiveAccountAll) {
        for (int idx = 0; idx < [AppSettings numActiveAccounts]; idx++) {
            Account* a = [[Accounts sharedInstance] getAccount:idx];
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [self insertConversations:[a getConversationsForFolder:self.folder]];
                a.mailListSubscriber = self;
            }];
        }
    }
    else {
        Account* a = [[Accounts sharedInstance] currentAccount];
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [self insertConversations:[a getConversationsForFolder:self.folder]];
            a.mailListSubscriber = self;
        }];
    }
}

-(void) insertConversation:(ConversationIndex*)conversationIndex
{
    [self insertConversations:@[conversationIndex]];
}

-(void) removeConversationList:(NSArray*)convs
{
    [ViewController animateCocoaButtonRefresh:NO];
    
    if (convs) {
        [self removeConversations:convs];
    }
    
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [self.table reloadData];
    }];
}

-(void) removeConversations:(NSArray*)convs
{
    for (ConversationIndex* conversationIndex in convs) {
        for (int i = 0 ; i < self.convByDay.count ; i++) {
            NSMutableArray* list = self.convByDay[i][@"list"];
            [list removeObject:conversationIndex];
        }
    }
}

-(void) insertConversations:(NSArray*)pConvs
{
    NSMutableArray* convs = [NSMutableArray arrayWithArray:pConvs];
    
    NSSortDescriptor *sortByDate = [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(date)) ascending:NO];
    [convs sortUsingDescriptors:@[sortByDate]];
    
    for (ConversationIndex* conversationIndex in convs) {
        
        if ([self.indexSet containsIndex:conversationIndex.index]) {
            continue;
        }
        
        [self.indexSet addIndex:conversationIndex.index];
        
        NSDate* convDay = conversationIndex.day;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL added = NO;
            [self.table beginUpdates];

            for (int dayIndex = 0 ; dayIndex < self.convByDay.count ; dayIndex++) {
                
                NSDate* tmpDay = self.convByDay[dayIndex][@"day"];
                NSComparisonResult result = [convDay compare:tmpDay];
                
                if (result == NSOrderedDescending) {
                    //Email Before //Insert section before date //+ email
                    
                    NSDictionary* earlier = @{@"list": [NSMutableArray arrayWithObject:conversationIndex], @"day":convDay};
                    [self.convByDay insertObject:earlier atIndex:dayIndex];
                    [self.table insertSections:[NSIndexSet indexSetWithIndex:dayIndex] withRowAnimation:UITableViewRowAnimationNone];
                    [self.table insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:dayIndex]] withRowAnimation:UITableViewRowAnimationNone];
                    
                    added = YES;
                    break;
                }
                else if (result == NSOrderedSame) {
                    //Add email to section of date
                    NSMutableArray* list = self.convByDay[dayIndex][@"list"];
                    
                    for (int j = 0 ; j < list.count ; j++) {
                        
                        ConversationIndex* cI = list[j];
                        
                        NSComparisonResult result = [conversationIndex.date compare:cI.date];
                        
                        if (result == NSOrderedDescending) {
                            [list insertObject:conversationIndex atIndex:j];
                            [self.table insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:j inSection:dayIndex]] withRowAnimation:UITableViewRowAnimationNone];
                            added = YES;
                            break;
                        }
                    }
                    
                    if (!added) {
                        [list addObject:conversationIndex];
                        [self.table insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:list.count-1 inSection:dayIndex]] withRowAnimation:UITableViewRowAnimationNone];
                        added = YES;
                    }
                    
                    break;
                }
            }
            
            if (!added) {
                //Date section not existing //Add new date //Add email to new date
                NSDictionary* later = @{@"list": [NSMutableArray arrayWithObject:conversationIndex], @"day":convDay};
                [self.convByDay addObject:later];
                [self.table insertSections:[NSIndexSet indexSetWithIndex:self.convByDay.count-1] withRowAnimation:UITableViewRowAnimationNone];
                [self.table insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:self.convByDay.count-1]] withRowAnimation:UITableViewRowAnimationNone];
            }
            [self.table endUpdates];
        });
    }
}

#pragma mark - Cell Delegate

-(BOOL) isPresentingDrafts
{
    return self.folder.type == FolderTypeDrafts;
}

-(UIImageView*) imageViewForQuickSwipeAction
{
    NSArray* imgNames = @[@"swipe_archive", @"swipe_delete", @"swipe_reply_single", @"swipe_read", @"swipe_inbox"];
    NSInteger swipetype = [Accounts sharedInstance].quickSwipeType;
    
    CCMFolderType type;
    
    if (swipetype == QuickSwipeArchive) {
        type.type = FolderTypeAll;
    }
    else if (swipetype == QuickSwipeDelete) {
        type.type = FolderTypeDeleted;
    }
    
    if (self.folder.type == type.type) {
        swipetype = 4;
    }
    
    
    if ([self isPresentingDrafts]) {
        swipetype = QuickSwipeDelete;
    }
    
    UIImageView* arch = [[UIImageView alloc] initWithImage:[UIImage imageNamed:imgNames[swipetype]]];
    
    if (swipetype == QuickSwipeReply) {
        arch.highlightedImage = [UIImage imageNamed:@"swipe_reply_all"];
    }
    else if (swipetype == QuickSwipeMark) {
        arch.highlightedImage = [UIImage imageNamed:@"swipe_unread"];
    }
    
    return arch;
}

-(void) unselectAll
{
    [UIView setAnimationsEnabled:NO];
    
    UINavigationItem* item = self.navBar.items.lastObject;
    [self _applyTrueTitleViewTo:item];
    [self.navBar setNeedsDisplay];
    [UIView setAnimationsEnabled:YES];
    
    NSArray* visibles = self.table.visibleCells;
    
    for (ConversationTableViewCell* cell in visibles) {
        if ([self.selectedCells containsObject:[cell currentID]]) {
            [cell animatedClose];
        }
    }
    [self.selectedCells removeAllObjects];
}

-(void) _commonRemoveCell:(NSIndexPath*)ip
{
    // change in model
    NSDictionary* dayInfos = self.convByDay[ip.section];
    NSMutableArray* ma = dayInfos[@"list"];
    [ma removeObjectAtIndex:ip.row];
    
    // change in UI
    if (ma.count < 1) {
        [self.convByDay removeObjectAtIndex:ip.section];
        
        NSIndexSet* set = [NSIndexSet indexSetWithIndex:ip.section];
        [self.table deleteSections:set withRowAnimation:UITableViewRowAnimationLeft];
    }
    else {
        [self.table deleteRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationLeft];
    }
}

-(void) _removeCell:(ConversationTableViewCell*)cell
{
    NSIndexPath* ip = [self.table indexPathForCell:cell];
    [self _commonRemoveCell:ip];
    [self cell:cell isChangingDuring:0.3];
}

-(void) leftActionDoneForCell:(ConversationTableViewCell*)cell
{
    NSIndexPath* indexPath = [self.table indexPathForCell:cell];
    NSDictionary* mailsDay = self.convByDay[indexPath.section];
    NSArray* convs = mailsDay[@"list"];
    ConversationIndex* conversationIndex = convs[indexPath.row];
    
    QuickSwipeType swipetype = [Accounts sharedInstance].quickSwipeType;
    
    switch (swipetype) {
        case QuickSwipeReply:
        {
            Mail* m = [[[Accounts sharedInstance] conversationForCI:conversationIndex] firstMail];
            Mail* repm = [m replyMail:[cell isReplyAll]];
            [[NSNotificationCenter defaultCenter] postNotificationName:kPRESENT_EDITMAIL_NOTIFICATION object:nil userInfo:@{kPRESENT_MAIL_KEY:repm}];
            break;
        }
        case QuickSwipeMark:
        {
            break;
        }
        default:
        {
            // QuickSwipeArchive / QuickSwipeDelete
            CCMFolderType type;
            type.type = (swipetype == QuickSwipeArchive) ? FolderTypeAll : FolderTypeDeleted;
            
            // back action
            if (self.folder.type == type.type) {
                type.type = FolderTypeInbox;
            }
            else if ([self isPresentingDrafts]) {
                type.type = FolderTypeDeleted;
            }
            
            if ([[Accounts sharedInstance].accounts[conversationIndex.account] moveConversationAtIndex:conversationIndex.index from:self.folder to:type]) {
                [self _removeCell:cell];
            }
            break;
        }
    }
    
}

-(void) cell:(ConversationTableViewCell*)cell isChangingDuring:(double)timeInterval
{
    CGPoint point = CGPointMake(100, self.table.contentOffset.y + self.table.contentInset.top);
    CGRect bigger = CGRectInset(cell.frame, -500, 0);
    
    if (CGRectContainsPoint(bigger, point)) {
        [self.navBar computeBlurForceNewDuring:timeInterval];
    }
}

-(void) _manageCocoaButton
{
    CocoaButton* cb = [CocoaButton sharedButton];
    UINavigationItem* item = self.navBar.items.lastObject;
    const NSInteger nbSelected = self.selectedCells.count;
    
    if (nbSelected==0) {
        [cb forceCloseHorizontal];
        [self _applyTrueTitleViewTo:item];
    }
    else {
        if (nbSelected==1) {
            [cb forceOpenHorizontal];
        }
        
        UILabel* l = [[UILabel alloc] init];
        NSString* formatString = NSLocalizedString(@"%d Selected", @"%d Selected");
        l.text = [NSString stringWithFormat:formatString, nbSelected];
        l.textColor = [[Accounts sharedInstance] currentAccount].userColor;
        [l sizeToFit];
        item.titleView = l;
    }
    
    [self.navBar setNeedsDisplay];
}

-(void) cellIsSelected:(ConversationTableViewCell*)cell
{
    NSString* ID = [cell currentID];
    [self.selectedCells addObject:ID];
    [self _manageCocoaButton];
}

-(void) cellIsUnselected:(ConversationTableViewCell*)cell
{
    NSString* ID = [cell currentID];
    [self.selectedCells removeObject:ID];
    [self _manageCocoaButton];
}

-(UIPanGestureRecognizer*) tableViewPanGesture
{
    return self.table.panGestureRecognizer;
}

#pragma mark - Table Datasource

-(NSInteger) numberOfSectionsInTableView:(UITableView*)tableView
{
    return self.convByDay.count;
}

-(NSInteger) tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section
{
    NSDictionary* dayContent = self.convByDay[section];
    NSArray* content = dayContent[@"list"];
    
    return content.count;
}

-(UITableViewCell*) tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath
{
    NSDictionary* mailsDay = self.convByDay[indexPath.section];
    NSArray* convs = mailsDay[@"list"];
    
    //Conversation* conv = convs[indexPath.row];
    ConversationIndex* conversationIndex = convs[indexPath.row];
    Conversation* conv = [[Accounts sharedInstance] conversationForCI:conversationIndex];
    
    NSString* idToUse = (conv.mails.count > 1) ? kCONVERSATION_CELL_ID : kMAIL_CELL_ID;
    
    ConversationTableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:idToUse];
    
    if (cell == nil) {
        cell = [[ConversationTableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:idToUse];
        [cell setupWithDelegate:self];
    }
    
    BOOL isSelected = [self.selectedCells containsObject:[conv firstMail].mailID];
    [cell fillWithConversation:conv isSelected:isSelected];
    
    return cell;
}

-(NSString*) tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section
{
    NSDictionary* dayContent = self.convByDay[section];
    NSString* dateS = [[DateUtil getSingleton] humanDate:dayContent[@"day"]];
    
    NSInteger idx = [Mail isTodayOrYesterday:dateS];
    
    if (idx == 0) {
        return NSLocalizedString(@"Today", @"Today");
    }
    else if (idx == -1) {
        return NSLocalizedString(@"Yesterday", @"Yesterday");
    }
    
    return dateS;
}

#pragma mark Table Delegate

-(CGFloat) tableView:(UITableView*)tableView heightForHeaderInSection:(NSInteger)section
{
    return 24;
}

-(UIView*) tableView:(UITableView*)tableView viewForHeaderInSection:(NSInteger)section
{
    
    UIView* support = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 320, 24)];
    support.backgroundColor = tableView.backgroundColor;
    
    UILabel* h = [[UILabel alloc] initWithFrame:CGRectMake(8, 0, 300, 24)];
    h.backgroundColor = support.backgroundColor;
    h.textColor = [UIColor colorWithWhite:0.58 alpha:1.0];
    h.text =  [self tableView:tableView titleForHeaderInSection:section];
    h.font = [UIFont systemFontOfSize:13];
    [support addSubview:h];
    
    return support;
}

-(NSIndexPath*) tableView:(UITableView*)tableView willSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
    return nil;
}

-(void) tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

#pragma mark - CocoaButton

-(BOOL) cocoabuttonLongPress:(CocoaButton*)cocoabutton
{
    self.longPressOnCocoabutton = YES;
    
    return YES;
}

-(NSArray*) buttonsHorizontalFor:(CocoaButton*)cocoaButton
{
    if (self.longPressOnCocoabutton) {
        self.longPressOnCocoabutton = NO;
        
        return nil;
    }
    
    const CGRect baseRect = cocoaButton.bounds;
    UIColor* color = [[Accounts sharedInstance] currentAccount].userColor;
    
    
    NSInteger folderType = self.folder.type;
    
    NSString* delete_icon = @"swipe_cocoabutton_delete";
    NSString* archive_icon = @"swipe_cocoabutton_archive";
    NSString* spam_icon = @"swipe_cocoabutton_spam";
    NSString* inbox_icon = @"swipe_inbox";
    
    
    NSArray* content = @[delete_icon];
    
    if (![self isPresentingDrafts]) {
        
        if (folderType==FolderTypeAll) {
            archive_icon = inbox_icon;
        }
        else if (folderType==FolderTypeDeleted) {
            delete_icon = inbox_icon;
        }
        else if (folderType==FolderTypeSpam) {
            spam_icon = inbox_icon;
        }
        
        content = @[delete_icon, archive_icon, @"swipe_cocoabutton_folder", spam_icon];
    }
    
    NSMutableArray* buttons = [NSMutableArray arrayWithCapacity:content.count];
    
    NSInteger idx = 0;
    
    for (NSString* iconName in content) {
        
        UIButton* b = [[UIButton alloc] initWithFrame:baseRect];
        b.backgroundColor = color;
        
        b.layer.cornerRadius = 22;
        b.layer.masksToBounds = YES;
        
        b.tag = idx;
        [b addTarget:self action:@selector(_chooseAction:) forControlEvents:UIControlEventTouchUpInside];
        
        UIImageView* iv = [[UIImageView alloc] initWithImage:[UIImage imageNamed:iconName]];
        iv.center = b.center;
        CGFloat scale = 44.f / 33.f;
        iv.transform = CGAffineTransformMakeScale(scale, scale);
        
        [b addSubview:iv];
        
        [buttons addObject:b];
        
        idx++;
    }
    
    
    UIButton* b = [[UIButton alloc] initWithFrame:baseRect];
    b.backgroundColor = color;
    [b setImage:[UIImage imageNamed:@"swipe_cocoabutton_close"] forState:UIControlStateNormal];
    [b setImage:[UIImage imageNamed:@"swipe_cocoabutton_close"] forState:UIControlStateHighlighted];
    b.layer.cornerRadius = 22;
    b.layer.masksToBounds = YES;
    [b addTarget:self action:@selector(_closeActions) forControlEvents:UIControlEventTouchUpInside];
    [cocoaButton replaceMainButton:b];
    
    return buttons;
}

-(void) _closeActions
{
    [UIView animateWithDuration:0.2
                     animations:^{
                         [self unselectAll];
                     }];
    [[CocoaButton sharedButton] forceCloseButton];
}

-(void) _executeMoveOnSelectedCellsTo:(CCMFolderType)toFolder
{
    if (encodeFolderTypeWith(self.folder) == encodeFolderTypeWith(toFolder)) {
        [self unselectAll];
        return;
    }
    
    NSMutableArray* res = [[NSMutableArray alloc] initWithCapacity:self.selectedCells.count];
    NSMutableArray* resIP = [[NSMutableArray alloc] initWithCapacity:self.selectedCells.count];
    
    NSInteger section = 0;
    
    for (NSDictionary* mailsDay in self.convByDay) {
        NSArray* convs = mailsDay[@"list"];
        NSInteger row = 0;
        
        for (ConversationIndex* conversationIndex in convs) {
            Conversation* conv = [[Accounts sharedInstance] conversationForCI:conversationIndex];
            
            NSString* mailID = [conv firstMail].mailID;
            
            if ([self.selectedCells containsObject:mailID]) {
                [res addObject:conversationIndex];
                [resIP addObject:[NSIndexPath indexPathForRow:row inSection:section]];
            }
            
            row++;
        }
        
        if (res.count == self.selectedCells.count) {
            break;
        }
        section++;
    }
    // TODO find a less expensive way to do that
    
    BOOL animDissapear = NO;
    
    for (ConversationIndex* conversationIndex in res) {
        Account* ac = [[Accounts sharedInstance] getAccount:conversationIndex.account];
        
        if ([ac moveConversationAtIndex:conversationIndex.index from:self.folder to:toFolder]) {
            animDissapear = YES;
        }
    }
    
    if (animDissapear) {
        
        [self.table beginUpdates];
        
        for (NSIndexPath* ip in [resIP reverseObjectEnumerator]) {
            [self _commonRemoveCell:ip];
        }
        
        NSArray* cells = self.table.visibleCells;
        
        for (ConversationTableViewCell* cell in cells) {
            if ([self.selectedCells containsObject:[cell currentID]]) {
                [self cell:cell isChangingDuring:0.3];
            }
        }
        
        [self.table endUpdates];
        
        UINavigationItem* item = self.navBar.items.lastObject;
        [self _applyTrueTitleViewTo:item];
        
    }
    else {
        [self unselectAll];
    }
    
    
    [self.selectedCells removeAllObjects];
    [[CocoaButton sharedButton] forceCloseButton];
}

-(void) _chooseAction:(UIButton*)button
{
    [CocoaButton animateHorizontalButtonCancelTouch:button];
    
    CCMFolderType toFolder;
    toFolder.idx = 0;
    BOOL doNothing = NO;
    
    switch (button.tag) {
        case 0:
            toFolder.type = (self.folder.type == FolderTypeDeleted) ? FolderTypeInbox : FolderTypeDeleted;
            break;
        case 1:
            toFolder.type = (self.folder.type == FolderTypeAll) ? FolderTypeInbox : FolderTypeAll;
            break;
        case 2:
        {
            doNothing = YES;
            
            UserFolderViewController* ufvc = [[UserFolderViewController alloc] init];
            ufvc.delegate = self;
            
            ufvc.view.frame = self.view.bounds;
            
            [self.view addSubview:ufvc.view];
            
            self.chooseUserFolder = ufvc;
            
            
            [ViewController temporaryHideCocoaButton:YES];
            
            ufvc.view.transform = CGAffineTransformMakeTranslation(0, self.view.frame.size.height);
            
            [UIView animateWithDuration:0.3
                             animations:^{
                                 ufvc.view.transform = CGAffineTransformIdentity;
                             }];
            
            /*
             UIAlertController* ac = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
             
             NSInteger idx = 0;
             for (NSArray* folder in [[Accounts sharedInstance] currentAccount].userFolders) {
             
             if (self.folder.type == FolderTypeUser && idx == self.folder.idx) {
             continue;
             }
             
             NSString* folderName = folder[0];
             
             UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:folderName style:UIAlertActionStyleDefault
             handler:^(UIAlertAction* aa) {
             [self _executeMoveOnSelectedCellsTo:FolderTypeWith(FolderTypeUser, idx)];
             }];
             [ac addAction:defaultAction];
             }
             
             if (ac.actions.count == 0) {
             UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:@"Create a folder" style:UIAlertActionStyleDefault
             handler:^(UIAlertAction* aa) {
             // TODO …
             }];
             [ac addAction:defaultAction];
             }
             
             UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", @"Cancel") style:UIAlertActionStyleCancel
             handler:nil];
             [ac addAction:defaultAction];
             
             ac.view.tintColor = [UIColor blackColor];
             
             ViewController* vc = [ViewController mainVC];
             [vc presentViewController:ac animated:YES completion:nil];
             */
            break;
        }
        case 3:
            toFolder.type = (self.folder.type == FolderTypeSpam) ? FolderTypeInbox : FolderTypeSpam;
            break;
        default:
            NSLog(@"WTF !!!");
            doNothing = YES;
            break;
    }
    
    if (!doNothing) {
        [self _executeMoveOnSelectedCellsTo:toFolder];
    }
}

-(void) chooseUserFolder:(CCMFolderType)folder
{
    [self _executeMoveOnSelectedCellsTo:folder];
    [self chooseUserFolderCancel];
}

-(void) chooseUserFolderCancel
{
    UserFolderViewController* ufvc = self.chooseUserFolder;
    
    [ViewController temporaryHideCocoaButton:NO];
    
    [UIView animateWithDuration:0.3
                     animations:^{
                         ufvc.view.transform = CGAffineTransformMakeTranslation(0, self.view.frame.size.height);
                     }
                     completion:^(BOOL fini){
                         [ufvc.view removeFromSuperview];
                         self.chooseUserFolder = nil;
                     }];
}

-(NSArray*) buttonsWideFor:(CocoaButton*)cocoabutton
{
    return nil;
}

-(BOOL) automaticCloseFor:(CocoaButton*)cocoabutton
{
    return self.selectedCells.count == 0;
}

-(void) startRefresh
{
    [[Accounts sharedInstance].currentAccount doLoadServer:YES];
}

#pragma mark - Fetch Data

-(void) loadMoreServer
{
    [[Accounts sharedInstance].currentAccount doLoadServer:NO];
}

@end
