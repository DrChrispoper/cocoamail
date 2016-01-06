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
#import "CCMStatus.h"


@interface MailListViewController () <UITableViewDataSource, UITableViewDelegate, ConversationCellDelegate, UserFolderViewControllerDelegate, MailListDelegate>

@property (nonatomic, strong) NSMutableArray* convByDay;
@property (nonatomic, strong) NSMutableArray<NSMutableIndexSet*>* indexSet;

@property (nonatomic) NSInteger pageIndex;
@property (nonatomic) NSInteger countBeforeLoadMore;
@property (nonatomic) NSInteger indexCount;
@property (nonatomic, weak) UITableView* table;
@property (nonatomic, strong) NSString* folderName;
@property (nonatomic, strong) NSMutableSet* selectedCells;
@property (nonatomic, strong) Person* onlyPerson;
@property (nonatomic) BOOL presentAttach;
@property (nonatomic, strong) UIButton* attachButton;
@property (nonatomic, retain) NSOperationQueue* localFetchQueue;
@property (nonatomic) CCMFolderType folder;
@property (nonatomic) BOOL longPressOnCocoabutton;
@property (nonatomic, strong) UserFolderViewController* chooseUserFolder;

@end

@implementation MailListViewController

static NSInteger pageCount = 15;

-(instancetype) initWithName:(NSString*)name
{
    self = [super init];
    self.folderName = name;
    
    self.selectedCells = [[NSMutableSet alloc] initWithCapacity:25];
    self.pageIndex = 1;
    self.countBeforeLoadMore = 0;
    self.indexCount = 0;
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
    self.indexSet = [[NSMutableArray alloc]initWithCapacity:[Accounts sharedInstance].accountsCount];
    
    for (Account* a in [Accounts sharedInstance].accounts) {
        if (!a.isAllAccounts) {
            [self.indexSet addObject:[[NSMutableIndexSet alloc]init]];
        }
    }
    
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    
    UINavigationItem* item = [[UINavigationItem alloc] initWithTitle:@""];
    
    item.leftBarButtonItem = [self backButtonInNavBar];
    
    [self _applyTrueTitleViewTo:item];
    
    if (self.presentAttach) {
        UIButton* attach = [WhiteBlurNavBar navBarButtonWithImage:@"attachment_off" andHighlighted:@"attachment_on"];
        [attach setHidden:YES];
        [attach addTarget:self action:@selector(_attach) forControlEvents:UIControlEventTouchUpInside];
        item.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:attach];
        self.attachButton = attach;
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
        [l setUserInteractionEnabled:YES];
        
        UILongPressGestureRecognizer* lpgr = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(_longPress:)];
        lpgr.minimumPressDuration = 1;
        [l addGestureRecognizer:lpgr];
        
        UITapGestureRecognizer* tgr = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_press:)];
        [header addGestureRecognizer:tgr];
        
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
    
    UIActivityIndicatorView* button = [[UIActivityIndicatorView alloc]initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    button.frame = CGRectMake(0.0, 0.0, [UIScreen mainScreen].bounds.size.width , 40.0);
    [button startAnimating];
    
    [headerView addSubview:button];
    
    self.table.tableFooterView = headerView;
    
    if (!self.onlyPerson) {
        [self addPullToRefreshWithDelta:0];
    }
    
    if (self.convByDay.count == 0) {
        [self setupData];
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
            Conversation* con = [[Accounts sharedInstance] conversationForCI:cI];
            for (Mail* m in con.mails) {
                if ([m haveAttachment]) {
                    //if ([m.email.sender.mailbox isEqualToString:self.onlyPerson.email]) {
                        [c addMail:m];
                    //   break;
                    //}
                }
            }
        }
    }
    
    //c.mails = tmp;
    
    // to have the right title in next VC
    [c firstMail].title = self.onlyPerson.name;
    
    return c;
}

-(void) _attach
{
    Conversation* c = [self _createAttachs];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kPRESENT_CONVERSATION_ATTACHMENTS_NOTIFICATION object:nil
                                                      userInfo:@{kPRESENT_CONVERSATION_KEY:c}];
}

-(void) _longPress:(UILongPressGestureRecognizer*)lpgr
{
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.persistent = YES;
    pasteboard.string = self.onlyPerson.email;
    [CCMStatus showStatus:NSLocalizedString(@"Email copied", @"Email copied to pasteboad")];
    [CCMStatus dismissAfter:1];
}

-(void) _press:(UITapGestureRecognizer*)tgr
{
    Mail* mail = [Mail newMailFormCurrentAccount];
    
    NSInteger personIndex = [[Persons sharedInstance] indexForPerson:self.onlyPerson];
    
    mail.toPersonID = @[@(personIndex)];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kPRESENT_EDITMAIL_NOTIFICATION object:nil userInfo:@{kPRESENT_MAIL_KEY:mail}];
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
    self.pageIndex = 1;
    self.countBeforeLoadMore = 0;
    self.indexCount = 0;
    
    self.table.delegate = nil;
    self.table.dataSource = nil;
    [[SearchRunner getSingleton] cancel];
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    [[Accounts sharedInstance] currentAccount].mailListSubscriber = self;

    [self reFetch];
}

-(void) viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    //TODO:TODO? :)
    //[[CocoaButton sharedButton] enterLevel:1];
    
    [[Accounts sharedInstance].currentAccount showProgress];
        
    if (self.onlyPerson) {
        [[Accounts sharedInstance].currentAccount doPersonSearch:self.onlyPerson];
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
            a.mailListSubscriber = self;
            [self insertConversations:[a getConversationsForFolder:self.folder]];
        }
    }
    else {
        Account* a = [[Accounts sharedInstance] currentAccount];
        a.mailListSubscriber = self;
        [self insertConversations:[[Accounts sharedInstance].currentAccount getConversationsForFolder:self.folder]];
    }
}

-(void) removeConversationList:(NSArray *)convs
{
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        
        if (convs) {
            [self _removeConversation:convs];
        }
        else {
            [self.table reloadData];
        }
    }];
}

-(void) _removeConversation:(NSArray*)convs
{
    for (ConversationIndex* pConversationIndex in convs) {

        if (![self.indexSet[pConversationIndex.account] containsIndex:pConversationIndex.index]) {
            continue;
        }
        
        BOOL found = NO;
        
        for (NSInteger section = 0; section < self.convByDay.count ;section++) {
            NSArray* list = self.convByDay[section][@"list"];
            
            for (NSInteger row = 0; row < list.count; row++) {
                ConversationIndex* conversationIndex = list[row];
                
                if (conversationIndex.index == pConversationIndex.index) {
                    [self _commonRemoveCell:[NSIndexPath indexPathForRow:row inSection:section]];
                    found = YES;
                    break;
                }
            }
        
            if (found) break;
        }
    }
    
    [self.table reloadData];
}

-(void) insertConversations:(NSArray*)pConvs
{
    if (self.onlyPerson) {
        pConvs = [self _filterResultsForPerson:pConvs];
    }
    
    NSMutableArray* convs = [NSMutableArray arrayWithArray:pConvs];
    
    NSSortDescriptor *sortByDate = [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(date)) ascending:NO];
    [convs sortUsingDescriptors:@[sortByDate]];
    
    for (ConversationIndex* conversationIndex in convs) {
        
        if ([self.indexSet[conversationIndex.account] containsIndex:conversationIndex.index]) {
            continue;
        }
        
        [self.indexSet[conversationIndex.account] addIndex:conversationIndex.index];
        
        NSDate* convDay = conversationIndex.day;
        
        BOOL added = NO;
        
        for (int dayIndex = 0 ; dayIndex < self.convByDay.count ; dayIndex++) {
            
            NSDate* tmpDay = self.convByDay[dayIndex][@"day"];
            NSComparisonResult result = [convDay compare:tmpDay];
            
            if (result == NSOrderedDescending) {
                //Email Before //Insert section before date //+ email
                
                NSDictionary* earlier = @{@"list": [NSMutableArray arrayWithObject:conversationIndex], @"day":convDay};
                [self.convByDay insertObject:earlier atIndex:dayIndex];
                
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
                        added = YES;
                        break;
                    }
                }
                
                if (!added) {
                    [list addObject:conversationIndex];
                    added = YES;
                }
                
                break;
            }
        }
        
        if (!added) {
            //Date section not existing //Add new date //Add email to new date
            NSDictionary* later = @{@"list": [NSMutableArray arrayWithObject:conversationIndex], @"day":convDay};
            [self.convByDay addObject:later];
        }
    }
    
    [self.table reloadData];
}

-(NSMutableArray*) _filterResultsForPerson:(NSArray*)convs
{
    NSMutableArray* current = [convs mutableCopy];
    
    NSInteger personID = [[Persons sharedInstance] indexForPerson:self.onlyPerson];
    NSInteger meID = [[Persons sharedInstance] indexForPerson:[Accounts sharedInstance].currentAccount.person];
    NSMutableArray* next = [NSMutableArray arrayWithCapacity:current.count];
    
    for (ConversationIndex* c in current) {
        
        for (Mail* mail in [[[Accounts sharedInstance] conversationForCI:c] mails]) {
            BOOL found = false;
            
            if (mail.fromPersonID == personID) {
                [next addObject:c];
                found = true;
            }
            else if (mail.fromPersonID == meID) {
                for (NSNumber* toPersonID in mail.toPersonID) {
                    if ([toPersonID integerValue] == personID) {
                        [next addObject:c];
                        found = true;
                        break;
                    }
                }
            }
            
            if (found) {
                break;
            }
        }
    }
    
    return next;
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
    
    /*if (self.folder.type == type.type) {
        swipetype = 4;
    }*/
    
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
    else if(self.folder.type == type.type && swipetype == QuickSwipeArchive) {
        //We archive emails from the archive folder if they are already in the Inbox
        arch.highlightedImage = [UIImage imageNamed:@"swipe_inbox"];
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
    NSMutableArray* ma  = self.convByDay[ip.section][@"list"];
    ConversationIndex* cIndex = ma[ip.row];
    
    [self.indexSet[cIndex.account] removeIndex:cIndex.index];
    
    if (ma.count == 1) {
        [self.convByDay removeObjectAtIndex:ip.section];
    }
    else {
        [ma removeObjectAtIndex:ip.row];
    }
    
    [self.table reloadData];
}

-(void) _removeCell:(ConversationTableViewCell*)cell
{
    NSIndexPath* ip = [self.table indexPathForCell:cell];
    [self _commonRemoveCell:ip];
    //[self cell:cell isChangingDuring:0.3];
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
            CCMFolderType fromtype = self.folder;
            
            // QuickSwipeArchive / QuickSwipeDelete
            CCMFolderType totype;
            totype.type = (swipetype == QuickSwipeArchive) ? FolderTypeAll : FolderTypeDeleted;
            
            Conversation* conv = [[Accounts sharedInstance] conversationForCI:conversationIndex];
            // back action
            if (self.folder.type == totype.type) {
                //We archive emails from the archive folder if they are already in the Inbox
                if(![conv isInInbox]) {
                    totype.type = FolderTypeInbox;
                }
                else {
                    fromtype.type = FolderTypeInbox;
                }
            }
            else if ([self isPresentingDrafts]) {
                totype.type = FolderTypeDeleted;
            }
            
            if ([[Accounts sharedInstance].accounts[conversationIndex.account] moveConversationAtIndex:conversationIndex.index from:fromtype to:totype]) {
                if (encodeFolderTypeWith(fromtype) == encodeFolderTypeWith(self.folder)) {
                   [self _removeCell:cell];
                }
                else {
                    [self.table reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
                }
            }
            else {
                [self.table reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
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
        NSString* formatString = NSLocalizedString(@"%d Selected multiple", @"Title when emails selected");
        
        if (nbSelected==1) {
            formatString = NSLocalizedString(@"%d Selected", @"Title when emails selected");
            [cb forceOpenHorizontal];
        }
        
        UILabel* l = [[UILabel alloc] init];
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
    return MIN(self.convByDay.count, (pageCount * self.pageIndex)+1);
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
    
    ConversationIndex* conversationIndex = convs[indexPath.row];
    Conversation* conv = [[Accounts sharedInstance] conversationForCI:conversationIndex];

    if (self.presentAttach && [conv haveAttachment]) {
        [self.attachButton setHidden:NO];
    }
    
    BOOL lastSection = (indexPath.section == pageCount * self.pageIndex || indexPath.section == self.convByDay.count - 1);
    BOOL lastRow = indexPath.row == ([convs count] - 1);
    
    if (!self.onlyPerson && self.indexCount != self.countBeforeLoadMore && lastSection && lastRow) {
        [self reFetch];
    }
    
    if (!self.onlyPerson && self.indexCount == self.countBeforeLoadMore && lastSection && lastRow) {
        [[Accounts sharedInstance].currentAccount localFetchMore:YES];
    }
    
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
        return NSLocalizedString(@"mail-list-view.date-header.today", @"Today");
    }
    else if (idx == -1) {
        return NSLocalizedString(@"mail-list-view.date-header.yesterday", @"Yesterday");
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
    
    NSInteger section = 0;
    
    for (NSDictionary* mailsDay in self.convByDay) {
        NSArray* convs = mailsDay[@"list"];
        NSInteger row = 0;
        
        for (ConversationIndex* conversationIndex in convs) {
            Conversation* conv = [[Accounts sharedInstance] conversationForCI:conversationIndex];
            
            NSString* mailID = [conv firstMail].mailID;
            
            if ([self.selectedCells containsObject:mailID]) {
                [res addObject:conversationIndex];
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
    
    [self unselectAll];
    
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

#pragma mark - Fetch Data

- (void)reFetch
{
    NSInteger mailCountBefore = 0;

    for (NSMutableIndexSet* indexSet in self.indexSet) {
        mailCountBefore += indexSet.count;
    }
    
    if (self.convByDay.count <= pageCount * self.pageIndex ) {
        if (kisActiveAccountAll) {
            for (int idx = 0; idx < [AppSettings numActiveAccounts]; idx++) {
                Account* a = [[Accounts sharedInstance] getAccount:idx];
                [self insertConversations:[a getConversationsForFolder:self.folder]];
                
            }
        }
        else {
            Account* a = [[Accounts sharedInstance] currentAccount];
            [self insertConversations:[a getConversationsForFolder:self.folder]];
        }
    }
    
    NSInteger mailCountAfer = 0;
    
    for (NSMutableIndexSet* indexSet in self.indexSet) {
        mailCountAfer += indexSet.count;
    }
    
    self.indexCount = mailCountAfer;
    self.countBeforeLoadMore =  MIN(mailCountAfer, self.countBeforeLoadMore + pageCount);
    
    [self.table.tableFooterView setHidden:(self.countBeforeLoadMore == mailCountAfer)];

    if (self.countBeforeLoadMore == mailCountAfer) {
        return;
    }
    
    self.pageIndex++;
    [self.table reloadData];
}

@end
