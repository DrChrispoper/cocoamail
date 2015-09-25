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
#import "Reachability.h"
#import "SyncManager.h"
#import "SearchRunner.h"
#import "ImapSync.h"
#import "UserFolderViewController.h"

#import <ReactiveCocoa/ReactiveCocoa.h>

@interface MailListViewController () <UITableViewDataSource, UITableViewDelegate, ConversationCellDelegate, UserFolderViewControllerDelegate>{
    NSMutableSet *_convIDs;
    NSMutableArray *_allData;
    BOOL _showingEmail;
    BOOL _localFetchComplete;
}

@property (nonatomic, strong) NSMutableArray* convByDay;
@property (nonatomic, weak) UITableView* table;

@property (nonatomic, strong) NSString* folderName;

@property (nonatomic, strong) NSMutableSet* selectedCells;

@property (nonatomic, strong) Person* onlyPerson;

@property (nonatomic) BOOL presentAttach;

@property (nonatomic, retain) NSOperationQueue *localFetchQueue;

@property (nonatomic) FolderType folder;

@property (nonatomic) BOOL longPressOnCocoabutton;

@property (nonatomic, strong) UserFolderViewController* chooseUserFolder;

@end



@implementation MailListViewController

-(instancetype) initWithName:(NSString*)name
{
    self = [super init];
    self.folderName = name;
    
    self.selectedCells = [[NSMutableSet alloc] initWithCapacity:25];
    _convIDs = [[NSMutableSet alloc] initWithCapacity:100];
    _allData = [[NSMutableArray alloc] initWithCapacity:100];

    return self;
}

-(instancetype) initWithFolder:(FolderType)folder
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
    return self;
}

-(instancetype) initWithPerson:(Person*)person
{
    self = [self initWithName:person.name];
    
    self.onlyPerson = person;
    self.folder = FolderTypeWith(FolderTypeAll, 0);

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

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    self.view.backgroundColor = [UIGlobal standardLightGrey];
    
    self.localFetchQueue = [NSOperationQueue new];
    [self.localFetchQueue setMaxConcurrentOperationCount:1];
    _localFetchComplete = YES;
    
    self.convByDay = [[NSMutableArray alloc]initWithCapacity:100];
    //self.convByDay[0] = [[NSDictionary alloc]initWithObjectsAndKeys:[[NSMutableArray alloc]init],@"list",@"Today",@"day", nil];
    
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
        
        UILabel* l = [[UILabel alloc] initWithFrame:CGRectMake(26+66, 31, screenBounds.size.width - (66+26) - 13, 30)];
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

    [self addPullToRefreshWithDelta:0];
}

-(Conversation*) _createAttachs
{
    Conversation* c = [[Conversation alloc] init];
    
    // keep only mail sent by onlyPerson with attachment
    //NSMutableArray* tmp = [NSMutableArray arrayWithCapacity:500];
    for (NSDictionary* d in self.convByDay) {
        NSArray* convs = d[@"list"];
        
        for (Conversation* c in convs) {
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
    [EmailProcessor getSingleton].updateSubscriber = nil;
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    [self.table reloadData];
    
    if(!self.onlyPerson && self.convByDay.count == 0){
        [self.localFetchQueue addOperationWithBlock:^{
            [self setupData];
        }];
    }
    
    [self.table reloadData];
    
    _showingEmail = NO;
}

-(void) viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    EmailProcessor* ep = [EmailProcessor getSingleton];
    ep.updateSubscriber = self;
    
    if (!self.onlyPerson) {
        [self runLoadData];
        [self doLoadServer:YES];
    }
    else {
        [self.localFetchQueue addOperationWithBlock:^{
            [[[SearchRunner getSingleton] senderSearch:@[self.onlyPerson]] subscribeNext:^(Email *email) {
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    [self insertRows:email];
                    [self.table reloadData];
                }];
            } completed:^{
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    //[self updateFilteredContentForSearchStrings:nil];
                }];
            }];
        }];
        
        [self doPersonSearchServer];
    } 
}

- (void)viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    //EmailProcessor* ep = [EmailProcessor getSingleton];
    //ep.updateSubscriber = nil;
}

-(void) setupData
{
    //self.convByDay = [[NSMutableArray alloc]initWithCapacity:100];
    //CCMLog(@"Folder:%@, %ld ",self.folderName, (long)[AppSettings numFolderWithFolder:self.folder forAccount:[Accounts sharedInstance].currentAccountIdx]);

    if([AppSettings activeAccount] == -1){
        for (int idx = 0; idx < [AppSettings numActiveAccounts]; idx++) {
            for (Conversation* conv in [[[Accounts sharedInstance] getAccount:idx] getConversationsForFolder:self.folder]) {
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    [self insertConversation:conv];
                    [self.table reloadData];
                }];
            }
        }
    }else {
        for (Conversation* conv in [[[Accounts sharedInstance] currentAccount] getConversationsForFolder:self.folder]) {
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [self insertConversation:conv];
                [self.table reloadData];
            }];
        }
    }

    //[self.table reloadData];
}

-(void)insertConversation:(Conversation*)conv
{
    NSIndexPath *index = [NSIndexPath indexPathForRow:0 inSection:0];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateFormat = @"d MMM yy";
    
    if (![[[conv firstMail].email getSonID] isEqualToString:@"0"]){
        [_convIDs addObject:[[conv firstMail].email getSonID]];
    }
    
    //CCMLog(@"%@",[conv firstMail].email.subject);
    //for (UidEntry* uid in [conv firstMail].email.uids) {
        //CCMLog(@"%ld",(long)uid.folder);
    //}
    
    
    NSString *stringDate = [[DateUtil getSingleton] humanDate:[conv firstMail].email.datetime];
    NSDate* emailDate = [dateFormatter dateFromString:stringDate];

    for (int i = 0;i < self.convByDay.count;i++) {
        NSDate* tmpDate = [dateFormatter dateFromString:self.convByDay[i][@"day"]];
        NSComparisonResult result = [emailDate compare:tmpDate];
        
        if(result == NSOrderedDescending){
            //Email Before //Insert section before date //+ email
            NSDictionary* earlier = @{@"list": [NSMutableArray arrayWithObject:conv], @"day":stringDate};
            [self.convByDay insertObject:earlier atIndex:i];
            
            return;
        }
        else if (result == NSOrderedSame){
            //Add email to section of date
            NSMutableArray* list = self.convByDay[i][@"list"];
            [list addObject:conv];
            
            return;
        }
        
        index = [NSIndexPath indexPathForRow:0 inSection:i + 1];
    }
    
    //Date section not existing //Add new date //Add email to new date
    NSDictionary* later = @{@"list": [NSMutableArray arrayWithObject:conv], @"day":stringDate};
    [self.convByDay addObject:later];
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
    
    FolderType type;
    if (swipetype==QuickSwipeArchive) {
        type.type = FolderTypeAll;
    }
    else if (swipetype==QuickSwipeDelete){
        type.type = FolderTypeDeleted;
    }
    
    if (self.folder.type == type.type) {
        swipetype = 4;
    }
    
    
    if ([self isPresentingDrafts]) {
        swipetype = 1;
    }
    
    UIImageView* arch = [[UIImageView alloc] initWithImage:[UIImage imageNamed:imgNames[swipetype]]];
    if (swipetype==QuickSwipeReply) {
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
    
    UINavigationItem* item =self.navBar.items.lastObject;
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

-(void)_commonRemoveCell:(NSIndexPath*)ip
{
    // change in model
    NSDictionary* dayInfos = self.convByDay[ip.section];
    NSMutableArray* ma = dayInfos[@"list"];
    [ma removeObjectAtIndex:ip.row];
    
    // change in UI
    if (ma.count<1) {
        [self.convByDay removeObjectAtIndex:ip.section];
        
        NSIndexSet* set = [NSIndexSet indexSetWithIndex:ip.section];
        [self.table deleteSections:set withRowAnimation:UITableViewRowAnimationLeft];
    }
    else {
        [self.table deleteRowsAtIndexPaths:@[ip] withRowAnimation:UITableViewRowAnimationLeft];
    }
    
    // TODO deleting cells disturb the nav bar blur cache !!!
    
}

-(void) _removeCell:(ConversationTableViewCell *)cell
{
    NSIndexPath* ip = [self.table indexPathForCell:cell];
    [self _commonRemoveCell:ip];
    [self cell:cell isChangingDuring:0.3];
}

-(void) leftActionDoneForCell:(ConversationTableViewCell *)cell
{
    NSIndexPath* indexPath = [self.table indexPathForCell:cell];
    NSDictionary* mailsDay = self.convByDay[indexPath.section];
    NSArray* convs = mailsDay[@"list"];
    Conversation* conv = convs[indexPath.row];
    
    QuickSwipeType swipetype = [Accounts sharedInstance].quickSwipeType;
    
    switch (swipetype) {
        case QuickSwipeReply:
        {
            Mail* m = [conv firstMail];
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
            FolderType type;
            type.type = (swipetype==QuickSwipeArchive) ? FolderTypeAll : FolderTypeDeleted;
            
            // back action
            if (self.folder.type == type.type) {
                type.type = FolderTypeInbox;
            }
            
            Account* ac = [[Accounts sharedInstance] currentAccount];
            if ([ac moveConversation:conv from:self.folder to:type]) {
                [self _removeCell:cell];
            }
            
            break;
        }
    }
    
}

-(void) cell:(ConversationTableViewCell*)cell isChangingDuring:(double)timeInterval;
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
    UINavigationItem* item =self.navBar.items.lastObject;
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

-(NSInteger) numberOfSectionsInTableView:(UITableView *)tableView
{
    return self.convByDay.count;
}


-(NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSDictionary* dayContent = self.convByDay[section];
    NSArray* content = dayContent[@"list"];
    return content.count;
}


-(UITableViewCell*) tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSDictionary* mailsDay = self.convByDay[indexPath.section];
    NSArray* convs = mailsDay[@"list"];
    
    Conversation* conv = convs[indexPath.row];
    
    NSString* idToUse = (conv.mails.count>1) ? kCONVERSATION_CELL_ID : kMAIL_CELL_ID;
    
    ConversationTableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:idToUse];
    
    if (cell == nil) {
        cell = [[ConversationTableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:idToUse];
        [cell setupWithDelegate:self];
    }
    
    BOOL isSelected = [self.selectedCells containsObject:[conv firstMail].mailID];
    [cell fillWithConversation:conv isSelected:isSelected];
    
    return cell;
}


-(NSString*)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    NSDictionary* dayContent = self.convByDay[section];
    NSString* dateS = dayContent[@"day"];
    
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

-(CGFloat) tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    return 24;
}

-(CGFloat) tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{
    return CGFLOAT_MIN;
}

-(UIView*) tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
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

-(NSIndexPath*) tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    return nil;
}

-(void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}


#pragma mark - CocoaButton

-(BOOL) cocoabuttonLongPress:(CocoaButton *)cocoabutton
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

-(void) _executeMoveOnSelectedCellsTo:(FolderType)toFolder
{
    // find the conversations
    NSMutableArray* res = [[NSMutableArray alloc] initWithCapacity:self.selectedCells.count];
    NSMutableArray* resIP = [[NSMutableArray alloc] initWithCapacity:self.selectedCells.count];
    
    NSInteger section = 0;
    for (NSDictionary* mailsDay in self.convByDay) {
        NSArray* convs = mailsDay[@"list"];
        NSInteger row = 0;
        
        for (Conversation* conv in convs) {
            
            NSString* mailID = [conv firstMail].mailID;
            if ([self.selectedCells containsObject:mailID]) {
                [res addObject:conv];
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
    
    Account* ac = [[Accounts sharedInstance] currentAccount];
    for (Conversation* conv in res) {
        if ([ac moveConversation:conv from:self.folder to:toFolder]) {
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
    
    FolderType toFolder;
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

-(void) chooseUserFolder:(FolderType)folder
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

#pragma mark - Process Data

- (void)insertRows:(Email *)email
{
    //If we are looking at Starred and there is no Starred Folder
    //We load all emails and hide emails not starred :D
    //Writing this I'm realising how bad this fix is but bricolage ftw! This case will rarely come up
    if ([AppSettings activeAccount] != -1 &&
        self.folder.type == FolderTypeFavoris &&
        [AppSettings importantFolderNumForAcct:[AppSettings activeAccount]  forBaseFolder:FolderTypeFavoris] ==  [AppSettings importantFolderNumForAcct:[AppSettings activeAccount]  forBaseFolder:FolderTypeAll] &&
        !(email.flag & MCOMessageFlagFlagged)) {
        
        return;
    }
    
    email.hasAttachments |= [CCMAttachment searchAttachmentswithMsgId:email.msgId];
    
    //if (![email uidEWithFolder:[AppSettings numFolderWithFolder:self.folder forAccount:[[Accounts sharedInstance].currentAccount currentFolderIdx]]])
        //![email haveSonInFolder:[[Accounts sharedInstance].currentAccount currentFolderIdx]]/*![email uidEWithFolder:[[Accounts sharedInstance].currentAccount currentFolderIdx]]*/) {
    //{
    //    CCMLog(@"Is email %@ in conversation of folder %@ ?",email.subject,self.folderName);
    //    return;
    //}
    
    [_allData addObject:email];
    
    NSIndexPath *index = [NSIndexPath indexPathForRow:0 inSection:0];
    NSDateFormatter *dateFormatter = [[NSDateFormatter alloc] init];
    dateFormatter.dateFormat = @"d MMM yy";
    
    //If conversation exists
    if (![[email getSonID] isEqualToString:@"0"] && [_convIDs containsObject:[email getSonID]]) {
        for (NSDictionary* tmpDay in self.convByDay) {
            for (Conversation* conv in tmpDay[@"list"]) {
                if ([[[conv firstMail].email getSonID] isEqualToString:[email getSonID]]) {
                    [conv addMail:[Mail mail:email]];

                    NSSortDescriptor* sortByDate = [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(latestDate)) ascending:NO];
                    [tmpDay[@"list"] sortUsingDescriptors:@[sortByDate]];
                    
                    return;
                }
            }
        }
    }
    else {
        Conversation* conv = [[Conversation alloc] init];
        [conv addMail:[Mail mail:email]];
        
        if(!self.onlyPerson){
            [[[Accounts sharedInstance] currentAccount] addConversation:conv];
        }
        
        if (![[email getSonID] isEqualToString:@"0"]){
            [_convIDs addObject:[email getSonID]];
        }
        
        NSString *stringDate = [[DateUtil getSingleton] humanDate:email.datetime];
        NSDate* emailDate = [dateFormatter dateFromString:stringDate];
        
        for (int i = 0;i < self.convByDay.count;i++) {

            NSDate* tmpDate = [dateFormatter dateFromString:self.convByDay[i][@"day"]];
            
            NSComparisonResult result = [emailDate compare:tmpDate];
            
            if(result == NSOrderedDescending){
                //Email Before
                //Insert section before date
                //+ email
                NSDictionary* earlier = @{@"list": [NSMutableArray arrayWithObject:conv], @"day":stringDate};
                [self.convByDay insertObject:earlier atIndex:i];
                
                return;
            }
            else if (result == NSOrderedSame){
                //Add email to section of date
                NSMutableArray* list = self.convByDay[i][@"list"];
                [list addObject:conv];
                
                NSSortDescriptor* sortByDate = [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(latestDate)) ascending:NO];
                [list sortUsingDescriptors:@[sortByDate]];
                
                return;
            }
            
            index = [NSIndexPath indexPathForRow:0 inSection:i + 1];
        }
        
        //Date section not existing
        //Add new date
        //Add email to new date
        NSDictionary* later = @{@"list": [NSMutableArray arrayWithObject:conv], @"day":stringDate};
        [self.convByDay addObject:later];
    }
}


#pragma mark - EmailProcessorDelegate

- (void)deliverUpdate:(NSArray *)emails
{
    CCMLog(@"update");

    for (Email *email in emails) {
        for(NSDictionary* current in self.convByDay) {
            //Email* tempEmail = _headEmailData[i];
            NSString* convDay = [[DateUtil getSingleton] humanDate:email.datetime];
            
            if ([convDay isEqualToString:current[@"day"]]) {
                NSArray* convs = current[@"list"];
                for (int row = 0; row < convs.count ; row++) {
                    if([[[convs[row] firstMail].email getSonID] isEqualToString:email.getSonID]  &&
                       [[convs[row] mails] count] == 0){
                        CCMLog(@"Update Email");
                        //[self _removeCell:(ConversationTableViewCell*)[self.table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:section]]];
                    }
                }
            }
            
            /*if([tempEmail.msgId isEqualToString:email.msgId]) {
             tempEmail.flag |= email.flag;
             [_headEmailData setObject:tempEmail atIndexedSubscript:i];
             
             [self.table reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:i inSection:0]] withRowAnimation:UITableViewRowAnimationFade];
             break;
             }*/
        }
    }
}

-(void) deleteRow:(Conversation*)conversation
{
    for (int section = 0; section < self.convByDay.count ; section++) {
        NSArray* convs = self.convByDay[section][@"list"];
        for (int row = 0; row < convs.count ; row++) {
            if ([[[convs[row] firstMail].email getSonID] isEqualToString:[[conversation firstMail].email getSonID]]) {
                CCMLog(@"Delete Email");
                [self _removeCell:(ConversationTableViewCell*)[self.table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:section]]];
                return;
            }
        }
    }
}

- (void)deliverDelete:(NSArray *)emails
{
    CCMLog(@"Delete");

    for (Email *email in emails) {
        if ([email haveSonInFolder:[AppSettings numFolderWithFolder:self.folder forAccount:[Accounts sharedInstance].currentAccountIdx+1]]) {
            continue;
        }
        for (int section = 0; section < self.convByDay.count ; section++) {
            
            if ([[[DateUtil getSingleton] humanDate:email.datetime] isEqualToString:self.convByDay[section][@"day"]]) {
                NSArray* convs = self.convByDay[section][@"list"];
                for (int row = 0; row < convs.count ; row++) {
                    if([[[convs[row] firstMail].email getSonID] isEqualToString:email.getSonID]  &&
                       [[convs[row] mails] count] == 0){
                        CCMLog(@"Delete Email");
                        [self _removeCell:(ConversationTableViewCell*)[self.table cellForRowAtIndexPath:[NSIndexPath indexPathForRow:row inSection:section]]];
                    }
                }
            }
            

            //Email* tempEmail = _headEmailData[i];
            /*if([tempEmail.msgId isEqualToString:email.msgId]) {
             [_headEmailData removeObjectAtIndex:i];
             [self.table deleteRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:i inSection:0]] withRowAnimation:UITableViewRowAnimationFade];
             
             break;
             }*/
        }
        [self.table reloadData];
    }
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
         if(![AppSettings isFirstFullSyncDone]){
             [self foldersSync];
         }
     }];
}

#pragma mark - Fetch Data

- (void)doLoadServer:(BOOL)refresh
{
    BOOL __block new = NO;
    //[_cocoaButton.activityServerIndicatorView startAnimating];
    
    Reachability *networkReachability = [Reachability reachabilityForInternetConnection];
    NetworkStatus networkStatus = [networkReachability currentReachabilityStatus];
    if (networkStatus == NotReachable) {
        //[_cocoaButton.activityServerIndicatorView stopAnimating];
        //[self.pullToRefresh endRefreshing];
    } else {
        
        RACSignal *newEmailsSignal = [[[SyncManager getSingleton] syncActiveFolderFromStart:refresh] deliverOn:[RACScheduler mainThreadScheduler]];
        
        [newEmailsSignal subscribeNext:^(Email *email) {
            new = YES;
            [self insertRows:email];
            [self.table reloadData];
        } error:^(NSError *error) {
            CCMLog(@"Error: %@",error.localizedDescription);
            //[_cocoaButton.activityServerIndicatorView stopAnimating];
            //[self.pullToRefresh endRefreshing];
        } completed:^{
            if (!new) {}
            
            CCMLog(@"Done");
            
            //[_cocoaButton.activityServerIndicatorView stopAnimating];
            //[self.pullToRefresh endRefreshing];
            
            [self importantFoldersRefresh:2];
        }];
    }
}

- (void)doPersonSearchServer
{
    //[_cocoaButton.activityServerIndicatorView startAnimating];
    
    Reachability *networkReachability = [Reachability reachabilityForInternetConnection];
    NetworkStatus networkStatus = [networkReachability currentReachabilityStatus];
    if (networkStatus == NotReachable) {
        //[_cocoaButton.activityServerIndicatorView stopAnimating];
        //[self.pullToRefresh endRefreshing];
    } else {
        
        RACSignal *newEmailsSignal = [[[SyncManager getSingleton] searchThings:@[self.onlyPerson]] deliverOn:[RACScheduler mainThreadScheduler]];
        
        [newEmailsSignal subscribeNext:^(Email *email) {
            [self insertRows:email];
            [self.table reloadData];
        } error:^(NSError *error) {
            CCMLog(@"Error: %@",error.localizedDescription);
        } completed:^{
        }];
    }
}

- (void)runLoadData
{
    if(_localFetchComplete){
        _localFetchComplete = NO;
        [self.localFetchQueue addOperationWithBlock:^{
            [[[SearchRunner getSingleton] activeFolderSearch:_allData.count]
             subscribeNext:^(Email *email) {
                 [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                     [self insertRows:email];
                     //if (_allData.count>5) {
                         [self.table reloadData];
                     //}
                 }];
             }
             completed:^{
                 [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                     [self.table reloadData];
                     
                     _localFetchComplete = YES;
                     
                     if ([AppSettings activeAccount] != -1) {
                         if (_allData.count != 0){
                             [[ImapSync sharedServices] runUpToDateTest:_allData];
                         }
                     }
                     else {
                         for (int i = 0; i < [AppSettings numActiveAccounts]; i++) {
                             if (_allData.count != 0){
                                 [[ImapSync sharedServices:[AppSettings numAccountForIndex:i]] runUpToDateTest:_allData];
                             }
                         }
                     }
                 }];
             }];
        }];
    }
}

@end
