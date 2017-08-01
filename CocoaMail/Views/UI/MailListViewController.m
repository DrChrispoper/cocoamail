//
//  MailListViewController.m
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 16/07/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "MailListViewController.h"
#import "ConversationTableViewCell.h"
#import "Mail.h"
#import "Attachments.h"
#import "Accounts.h"
#import "CCMConversationsPerAccount.h"
#import "CCMConversationsByDay.h"
#import "EmailProcessor.h"
#import "AppSettings.h"
#import "DateUtil.h"
#import "SyncManager.h"
#import "SearchRunner.h"
//#import "ImapSync.h"
#import "UserFolderViewController.h"
#import <ReactiveCocoa/ReactiveCocoa.h>
#import "CCMStatus.h"
#import "CocoaMail-Swift.h"
#import "PreviewViewController.h"
#import "ConversationViewController.h"
#import "MailListViewController+UIViewControllerPreviewing.h"
//#import "UIScrollView+EmptyDataSet.h"
#import "UserSettings.h"
#import "Conversation.h"
#import "Draft.h"

#ifdef USING_FLURRY
#import "Flurry.h"
#endif

#ifdef USING_INSTABUG
#import <Instabug/Instabug.h>
#endif

@interface MailListViewController () <UITableViewDataSource, UITableViewDelegate, ConversationCellDelegate, UserFolderViewControllerDelegate, MailListDelegate/*, DZNEmptyDataSetSource, DZNEmptyDataSetDelegate*/>

@property (nonatomic, strong) CCMConversationsPerAccount* conversationsPerAccount;
@property (nonatomic, strong) NSMutableSet<ConversationIndex*>* deletes;

//@property (nonatomic) NSInteger pageIndex;
//@property (nonatomic) NSInteger deletedSections;
@property (nonatomic) NSInteger countBeforeLoadMore;
@property (nonatomic) NSInteger indexCount;
@property (nonatomic, strong) NSString* folderName;
@property (nonatomic, strong) NSMutableSet* selectedCells;

// When the user is searching for mails to or from a Person,
// this contains that person.
@property (nonatomic, strong) Person* showOnlyThisPerson;

@property (nonatomic) BOOL presentAttach;
@property (nonatomic, strong) UIButton* attachButton;
@property (nonatomic) CCMFolderType folder;
@property (nonatomic) BOOL longPressOnCocoabutton;
@property (nonatomic, strong) UserFolderViewController* chooseUserFolder;
@property (nonatomic) BOOL isDebugMode;
@property (nonatomic) BOOL initialLoading;
@property (nonatomic) BOOL localSearchDone;
@property (nonatomic) BOOL serverSearchDone;
@property (nonatomic) BOOL viewIsClosing;

@property (nonatomic, strong) UIRefreshControl* refreshControl;

@end

@implementation MailListViewController

//static NSInteger pageCount = 15;

-(instancetype) _initWithName:(NSString*)name
{
    self = [super init];
    if (self) {
        self.folderName = name;
        self.showOnlyThisPerson = nil;
        self.selectedCells = [[NSMutableSet alloc] initWithCapacity:25];
        //self.pageIndex = 1;
        //self.deletedSections = 0;
        self.countBeforeLoadMore = 0;
        self.indexCount = 0;
        self.isDebugMode = NO;
        self.initialLoading = YES;
        self.viewIsClosing = NO;
    }
    return self;
}

-(instancetype) initWithFolder:(CCMFolderType)folder
{
    NSString* name = nil;
    
    // Get the folder name
    if (folder.type == FolderTypeUser) {
        NSUInteger folderIndex = (NSUInteger)folder.idx;
        
        name = [[Accounts sharedInstance] currentAccount].userFolders[folderIndex][0];
    }
    else {
        name = [[[Accounts sharedInstance] currentAccount] systemFolderNames][folder.type];
    }
    
    self = [self _initWithName:name];
    self.folder = folder;
    self.presentAttach = NO;
    
    return self;
}

// This is called when the user has searched for a Person, and we are
// displaying emails to or from that person.
-(instancetype) initWithPerson:(Person*)person
{
    self = [self _initWithName:person.name];
    
    self.folder = CCMFolderTypeAll;     // Show all emails
    self.showOnlyThisPerson = person;   // that are to or from ths person
    self.presentAttach = YES;           // and show the attachments button
    
    return self;
}

-(BOOL) istheSame:(MailListViewController*)other
{
    if (self.showOnlyThisPerson!=nil) {
        return self.showOnlyThisPerson == other.showOnlyThisPerson;
    }
    
    if (self.folder.type != FolderTypeUser) {
        return (self.folder.type == other.folder.type);
    }
    
    if (other.folder.type == FolderTypeUser) {
        return other.folder.idx == self.folder.idx;
    }
    
    return NO;
}

-(void) _applyTrueTitleViewTo:(UINavigationItem*)item
{
    
//    NSInteger mailUnread = 0;
    
//    [ImapSync runInboxUnread:self.[Accounts sharedInstance].currentAccount.user completed:^{}];

    // BETA_ONLY is only enabled during DEBUG
#ifdef BETA_ONLY
    NSUInteger mailCount = [self.convByDay totalConversationCount];
    
    NSUInteger currentAccountIndex = [[Accounts sharedInstance] currentAccountIdx];
    NSInteger unreadCount = [AppSettings inboxUnread:(NSInteger)currentAccountIndex];
    
    NSString *titleWithCounts = [NSString stringWithFormat:@"%@ (%@, %@)",self.folderName,@(mailCount),@(unreadCount)];
    
    UILabel* l = [WhiteBlurNavBar titleViewForItemTitle:titleWithCounts];
#else // not BETA_ONLY
    UILabel* l = [WhiteBlurNavBar titleViewForItemTitle:self.folderName];
#endif
    
    item.titleView = l;
}

-(void) _updateViewTitle
{
    WhiteBlurNavBar *navBar = self.navBar;
    
    UINavigationItem* item = navBar.items.lastObject;
    [self _applyTrueTitleViewTo:item];
    [navBar setNeedsDisplay];
}


#pragma mark - viewDidLoad supporting methods
-(void)_setupConversations
{
    self.convByDay = [[CCMConversationsByDay alloc] initWithDayCapacity:100]; // 100 days
    
    // conversationsPerAccount is an NSMutableAreray of index sets, one for each account
    //      conversationsPerAccount[account] -> NSMutableIndexSet
    NSUInteger numberAccounts = [Accounts sharedInstance].accountsCount;
    self.conversationsPerAccount = [[CCMConversationsPerAccount alloc] initWithAccountCapacity:numberAccounts];
    
    // Set of conversation indecies
    self.deletes = [[NSMutableSet alloc]init];
    
    for (Account* a in [Accounts sharedInstance].accounts) {
        if (!a.user.isAll) {
            // Add a new empty account mail index set for each non-All account
            [self.conversationsPerAccount appendEmptyAccount];
        }
    }
    
    if ( [self.convByDay isEmpty] ) {
        [self setupData];
    }
    return;
}
-(UIView*)_setupHeaderViewOfColor:(UIColor*)backgroundColor
{
    UIView* headerView = [[UIView alloc] init];
    headerView.backgroundColor = backgroundColor;
    
    UIActivityIndicatorView* button = [[UIActivityIndicatorView alloc]initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    button.frame = CGRectMake(0.0, 0.0, [UIScreen mainScreen].bounds.size.width , 40.0);
    [button startAnimating];
    
    [headerView addSubview:button];
    
    [headerView setHidden:YES];
    
    return headerView;
}

#pragma mark viewDidLoad

-(void) viewDidLoad
{
    [super viewDidLoad];
    
    [self check3DTouch];
    
    self.view.backgroundColor = [UIGlobal standardLightGrey];
    
    [self _setupConversations];
    
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    
    UINavigationItem* item = [[UINavigationItem alloc] initWithTitle:@""];
    
    item.leftBarButtonItem = [self backButtonInNavBar];
    
    [self _applyTrueTitleViewTo:item];
    
    if (self.presentAttach) {  // when self initialized via initWithPerson
        
        UIButton* attach = [WhiteBlurNavBar navBarButtonWithImage:@"attachment_off" andHighlighted:@"attachment_on"];
        [attach setHidden:YES];
        [attach addTarget:self
                   action:@selector(_attach)
         forControlEvents:UIControlEventTouchUpInside];
        item.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:attach];
        self.attachButton = attach;
    }
    
    UITableView* tableView = [[UITableView alloc] initWithFrame:CGRectMake(0,
                                                                       0,
                                                                       screenBounds.size.width,
                                                                       screenBounds.size.height - 20)
                                                      style:UITableViewStyleGrouped];
    
    CGFloat offsetToUse = 44.f;
    
    if (self.showOnlyThisPerson) {
        
        // TODO: Note use of FIXED point locations!
        
        // TODO: edit content + add edit codeName
        UIView* header = [[UIView alloc] initWithFrame:CGRectMake(0, -92, screenBounds.size.width, 92)];
        header.backgroundColor = [UIColor whiteColor];
        
        UIView* badge = [self.showOnlyThisPerson doubleBadgeView];
        badge.center = CGPointMake(33 + 13, 46);
        //badge.transform = CGAffineTransformMakeScale(2.f, 2.f);
        [header addSubview:badge];
        
        UILabel* l = [[UILabel alloc] initWithFrame:CGRectMake(26 + 66, 31, screenBounds.size.width -(66 + 26) - 13, 30)];
        l.backgroundColor = header.backgroundColor;
        l.text = self.showOnlyThisPerson.email;
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
        
        [tableView addSubview:header];
        
        offsetToUse += 92;
    }
    
    tableView.contentInset = UIEdgeInsetsMake(offsetToUse, 0, 60, 0);
    
    tableView.scrollIndicatorInsets = UIEdgeInsetsMake(44, 0, 0,0.5);
    tableView.allowsSelection = false;
    tableView.rowHeight = 90;
    tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    tableView.backgroundColor = [UIGlobal standardLightGrey];
    
    [self.view addSubview:tableView];
    
    [self setupNavBarWith:item overMainScrollView:tableView];
    
    tableView.dataSource = self;
    tableView.delegate = self;
    self.tableView = tableView;     // save to retain the view when this method goes out of scope
    
    tableView.tableFooterView = [self _setupHeaderViewOfColor:tableView.backgroundColor];
    
    // If NOT displaying only this one person's emails ...
    if (!self.showOnlyThisPerson) {
        
        self.refreshControl = [[UIRefreshControl alloc] init];
        [tableView addSubview:self.refreshControl];
        [self.refreshControl addTarget:self action:@selector(_refreshTable) forControlEvents:UIControlEventValueChanged];
        //[self addPullToRefreshWithDelta:0];
        //table.emptyDataSetSource = self;
        //table.emptyDataSetDelegate = self;
    }
    
}

- (void)_refreshTable {
    
    DDLogInfo(@"START BACKGROUND REFRESH TABLE");

    [[Accounts sharedInstance].currentAccount refreshCurrentFolder];
    [self _updateViewTitle];
    //[[Accounts sharedInstance].currentAccount localFetchMore:NO];
    //[ImapSync runInboxUnread:[Accounts sharedInstance].currentAccount.user completed:^{}];
}

- (BOOL)canBecomeFirstResponder {
    return YES;
}

- (void)motionEnded:(UIEventSubtype)motion withEvent:(UIEvent *)event {
    if (UIEventSubtypeMotionShake) {
       /* self.isDebugMode = !self.isDebugMode;
        
        [PKHUD sharedHUD].userInteractionOnUnderlyingViewsEnabled = FALSE;
        [PKHUD sharedHUD].contentView = [[PKHUDTextView alloc]initWithText:self.isDebugMode?@"Debug Mode On":@"Debug Mode Off"];
        [[PKHUD sharedHUD] show];
        [[PKHUD sharedHUD] hideAfterDelay:2.0];*/
        
        [self _reloadTableView];
    }
}

-(Conversation*) _createAttachs
{
    __block Conversation* c = [[Conversation alloc] init];
    
    // keep only mail sent by showOnlyThisPerson with attachment
    //NSMutableArray* tmp = [NSMutableArray arrayWithCapacity:500];
    

    [self.convByDay enumerateAllMailsUsingBlock:^(Mail *m)
    {
        if ([m hasAttachments]) {
            //if ([m.email.sender.mailbox isEqualToString:self.showOnlyThisPerson.email]) {
            [c addMail:m];
            //   break;
            //}
        }
    }];

    //c.mails = tmp;
    
    // to have the right title in next VC
    //[c firstMail].subject = self.showOnlyThisPerson.name;
    
    if (self.attachSubscriber) {
        [self.attachSubscriber reloadWithConversation:c];
    }
    
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
    DDAssert(self.showOnlyThisPerson,@"showOnlyThisPerson must be set");
    
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.persistent = YES;
    pasteboard.string = self.showOnlyThisPerson.email;
    [CCMStatus showStatus:NSLocalizedString(@"Email copied", @"Email copied to pasteboad") dismissAfter:2 code:0];
}

-(void) _press:(UITapGestureRecognizer*)tgr
{
    DDAssert(self.showOnlyThisPerson, @"showOnlyThisPerson must be set");
    
    Draft* draft = [Draft newDraftFormCurrentAccount];
    
    //NSInteger personIndex = [[Persons sharedInstance] indexForPerson:self.showOnlyThisPerson];
    
    draft.toPersons = [NSMutableArray arrayWithArray:@[self.showOnlyThisPerson.email]];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kPRESENT_EDITMAIL_NOTIFICATION object:nil userInfo:@{kPRESENT_MAIL_KEY:draft}];
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
    @synchronized (self.tableView) {
        
    UITableView* localTable = self.tableView;

    //self.pageIndex = 1;
    self.countBeforeLoadMore = 0;
    self.indexCount = 0;
    self.viewIsClosing = YES;

    localTable.delegate = nil;
    localTable.dataSource = nil;
    [[SearchRunner getSingleton] cancel];
        
    } // end synchronized
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    //self.table.emptyDataSetSource = self;
    //self.table.emptyDataSetDelegate = self;
    
    if ([self.conversationsPerAccount accountCount] < [AppSettings numActiveAccounts]) {
        [self.conversationsPerAccount appendEmptyAccount]; // TODO: why one?
    }
    
    [[Accounts sharedInstance] currentAccount].mailListDelegate = self;
    
    [self serverSearchDone:YES];

    [self reFetch:YES];  // was commented out; AJC uncommented it
}

-(void) viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self becomeFirstResponder];
    
    [[Accounts sharedInstance] appeared];
    
    //[[CocoaButton sharedButton] enterLevel:1];
    //[[Accounts sharedInstance].currentAccount showProgress];
    
    if (self.showOnlyThisPerson) {
        [[Accounts sharedInstance].currentAccount doPersonSearch:self.showOnlyThisPerson];
    }
}

-(void) viewWillDisappear:(BOOL)animated
{
    @synchronized (self.tableView) {
        
    UITableView* localTable = self.tableView;
    
    [super viewWillDisappear:animated];
    
    [localTable setContentOffset:localTable.contentOffset animated:NO];
        
    }  // end synchronized
    
    //[[Accounts sharedInstance] currentAccount].mailListDelegate = nil;

//    if (!self.showOnlyThisPerson) {
        //self.table.emptyDataSetSource = nil;
        //self.table.emptyDataSetDelegate = nil;
//    }
    
    
    [ViewController animateCocoaButtonRefresh:NO];
}

-(void) setupData
{
    DDLogInfo(@"ENTERED");
    
    // If we are showing the All Mail account ...
    BOOL isActiveAccountAll = [[Accounts sharedInstance] currentAccount].user.isAll;
    if (isActiveAccountAll) {
        
        DDLogDebug(@"Active Account is \"All\" Account");
        
        for (Account *account in [[Accounts sharedInstance] accounts]) {
            [self _addConversationsForAccount:account folder:self.folder];
        }
    }
    else { // We are showing the Current account ...
        
        Account* acnt = [[Accounts sharedInstance] currentAccount];
        DDLogDebug(@"Active Account Index = Current Account = %ld\n",(long)acnt.idx);
        [self _addConversationsForAccount:acnt folder:self.folder];
    }
}

-(void) _addConversationsForAccount:(Account*)account folder:(CCMFolderType)folder
{
    DDLogInfo(@"ENTERED, folder index = %@",@(folder.idx));
    
    account.mailListDelegate = self;
    
    NSMutableArray<ConversationIndex*>* conversationsForFolder = [account getConversationsForFolder:folder];
    
    DDLogDebug(@"\t\tAccount Folder has %@ Conversations",@(conversationsForFolder.count));
    
    [self insertConversations:conversationsForFolder];
}

-(void) removeConversationList:(NSArray<ConversationIndex*>*)convs
{
    DDLogInfo(@"ENTERED");
    
    if (convs) {
        [self _removeConversation:convs];
    }
    else {
        [self _reloadTableViewOnMainThread];
    }
}

-(void) _removeConversation:(NSArray<ConversationIndex*>*)convs
{
    DDLogDebug(@"ENTERED, Remove %lu conversations",(unsigned long)convs.count);
    
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{

        NSMutableArray<NSIndexPath*>* ips = [[NSMutableArray alloc]init];
        
        for (ConversationIndex* convIndex in convs) {
            
            if ([self.conversationsPerAccount containsConversationIndex:(NSUInteger)convIndex.index
                                                              inAccount:(NSUInteger)convIndex.user.accountIndex]) {
                
                DDLogDebug(@"ConversationIndex:%ld in Account:%ld",
                          (long)convIndex.index,
                          (unsigned long)convIndex.user.accountNum);
                
                BOOL found = NO;
                
                NSUInteger dayCount = [self.convByDay dayCount];
                
                for (NSUInteger dayIndex = 0; dayIndex < dayCount ;dayIndex++) {  // Day Index is the table Section
                    
                    NSUInteger convCount = [self.convByDay conversationCountOnDay:dayIndex];

                    for (NSUInteger conv = 0; conv < convCount; conv++) { // Conv is the table Row
                        
                        ConversationIndex* conversationIndex = [self.convByDay conversation:conv onDay:dayIndex ];
                        
                        if (conversationIndex.index == convIndex.index) {
                            
                            [ips addObject:[NSIndexPath indexPathForRow:(NSInteger)conv inSection:(NSInteger)dayIndex]];
                            found = YES;
                            break;
                        }
                        
                    } // end for each conversation (on day)
                    
                    if (found) break;
                    
                } // end for each day
            }
        }
    
        [self _commonRemoveConvs:ips];
    }];
}

-(void) checkConversationsUpdate
{
    DDLogInfo(@"ENTERED");
    
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        
        NSMutableArray* reAddConvs = [[NSMutableArray alloc] init];
        
        NSUInteger dayCount = [self.convByDay dayCount];
        for (NSUInteger dayIndex = 0 ; dayIndex < dayCount ; dayIndex++) {
            
            NSDate* tmpDay = [self.convByDay dateForDay:dayIndex];
            if ( tmpDay == nil ) {
                DDLogError(@"No NSDate for day index %@",@(dayIndex));
                continue;   // skip to next dayIndex
            }
            
            NSUInteger convsOnDay = [self.convByDay conversationCountOnDay:dayIndex];
            
            for (NSUInteger j = 0 ; j < convsOnDay; j++) {
                
                ConversationIndex* cI = [self.convByDay conversation:j onDay:dayIndex];
                
                // If this converstation index's date matches the dayIndex date
                NSComparisonResult dayresult = [cI.day compare:tmpDay];
                
                // If the two dates are NOT equal
                if (dayresult != NSOrderedSame) {
                    [reAddConvs addObject:cI];
                    continue;
                }
                
                if ( j+1 < convsOnDay ) {
                    
//                    ConversationIndex* cINext = list[j+1];
                    ConversationIndex* cINext = [self.convByDay conversation:(j+1) onDay:dayIndex];

                    NSComparisonResult dateresult = [[cINext date] compare:[cI date]];
                    
                    if (dateresult != NSOrderedAscending) {
                        [self.convByDay exchangeConversationsAtIndex:j withConversationAtIndex:j+1 onDay:dayIndex];
                    }
                }
            }
        }
        
        if (reAddConvs.count > 0) {
            DDLogDebug(@"%ld Conversation Time Updated",(unsigned long)reAddConvs.count);
            [self _removeConversation:reAddConvs];
            [self insertConversations:reAddConvs];
        }
        
    }];
}

// Update Day Sections
-(void) updateDays:(NSArray<NSString *>*)days
{
    DDAssert(days,@"Days array must exist.");
    
    if (days.count == 0){
        DDLogDebug(@"Zero days in array, nothing to do.");
        return;
    }
    
    DDLogDebug(@"days.count = %@; days.elements = %@.",@(days.count),days.description);
    
    NSMutableIndexSet* daySections = [[NSMutableIndexSet alloc] init];  // unique unsigned integers
    
    // Create an index set "sections" containing the indexes off all the
    // dates in our Conversations By Day structure (Days.Conversations.Mails)
    // that match one or more of the day dates passed in.
    for (NSString* day in days) {
        
        NSDateFormatter* s_df_day = [[NSDateFormatter alloc] init];
        s_df_day.dateFormat = @"d MMM yy";
        NSDate* dayDate = [s_df_day dateFromString:day];
        
        NSUInteger dayCount = [self.convByDay dayCount];
        for (NSUInteger dayIndex = 0 ; dayIndex < dayCount ; dayIndex++) {
            
            NSDate* tmpDay = [self.convByDay dateForDay:dayIndex];      // returns nil on error
            if ( tmpDay == nil ) {
                DDLogError(@"No NSDate for day index %@",@(dayIndex));
                continue;   // skip to next dayIndex
            }

            if (tmpDay && [dayDate compare:tmpDay] == NSOrderedSame){
                [daySections addIndex:dayIndex];
            }
        }
    }
    
    DDLogInfo(@"Number of table sections to update = %@",@(daySections.count));
    
        
    UITableView* strongTable = self.tableView;
    
    // Update Mail List "Day Section Headers"
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        
        @synchronized (self.tableView) {
            
            [strongTable beginUpdates];
            [strongTable reloadSections:daySections withRowAnimation:UITableViewRowAnimationNone];
            [strongTable endUpdates];
        } // end synchronized

    }];

}

- (BOOL)_findMessageToOrFromPerson:(Person*)person inConversation:(ConversationIndex*)ci
{
    Person *currentAccountPerson = [Accounts sharedInstance].currentAccount.person;
    
    NSInteger personID = [[Persons sharedInstance] indexForPerson:person];
    NSInteger meID     = [[Persons sharedInstance] indexForPerson:currentAccountPerson];
    
    for (Mail* mail in [[[Accounts sharedInstance] conversationForCI:ci] mails]) {
      
        // if this message is From this person
        if (mail.fromPersonID == personID) {
            return TRUE;
        }
        
        // If this message is from "me" and to "person"
        if (mail.fromPersonID == meID && [mail.toPersonIDs containsObject:@(personID)]) {
            return TRUE;
        }
    }
    return FALSE;
}
                          

// TODO: insertConversationIndex needs refactoring -- too big

// Insert a conversation into the local data structures and update the visible table view.
//
-(void) insertConversationIndex:(ConversationIndex*)ciToInsert
{
    DDLogInfo(@"Conversation Index date = %@",ciToInsert.date.description);
    
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        
        [self.tableView beginUpdates];
        
        if (self.viewIsClosing) {
            DDLogDebug(@"View is closing, so return");
            return;
        }
       
        if (self.showOnlyThisPerson) {
            // If the conversation does not contain a message to or from showOnlyThisPerson ...
            if (![self _findMessageToOrFromPerson:self.showOnlyThisPerson
                                   inConversation:ciToInsert]) {
                DDLogDebug(@"Showing single person AND conversation does not include a message to or from this person, so return");
                return;
            }
        }
    
        // If this account already contains this conversation ...
        if ([self.conversationsPerAccount containsConversationIndex:(NSUInteger)ciToInsert.index
                                                          inAccount:(NSUInteger)ciToInsert.user.accountIndex]) {
            DDLogDebug(@"Account already contains this conversation, so return");
            return;
        }
                
        Conversation* convToInsert = [[Accounts sharedInstance] conversationForCI:ciToInsert];
        
        // folder currently being displayed in the view
        NSInteger curFolderIndex = [convToInsert.user numFolderWithFolder:self.folder];
        NSInteger allFolderIndex = [convToInsert.user numFolderWithFolder:allFolderType()];
        
        // if the current folder is NOT the All messages folder ...
        if (curFolderIndex != allFolderIndex) {
            
            // Prefetch conversation UIDs from Mail Database
            [convToInsert foldersType];  // return ignored ... queries DB to get uid's for msgId????
            
            BOOL isInFolder = [convToInsert isInFolder:curFolderIndex];
            
            if (!isInFolder) {  // If the conversation to insert is NOT in the current folder
#ifdef USING_INSTABUG
                IBGLogError(@"Conversation with index %ld, failed to insert.",(long)ciToInsert.index);
#endif
                DDLogError(@"Conversation with index %ld, failed to insert, so return.",(long)ciToInsert.index);
                
                Account* a = [[Accounts sharedInstance] account:convToInsert.user.accountIndex];
                
                [a deleteIndex:ciToInsert.index fromFolder:self.folder];
                return;
            }
        }
    
        [self.conversationsPerAccount addConversationIndex:ciToInsert.index
                                                forAccount:ciToInsert.user.accountIndex];
                
        BOOL added = NO;
        
        NSUInteger dayCount = [self.convByDay dayCount];
        for (NSUInteger dayIndex = 0 ; dayIndex < dayCount ; dayIndex++) {
            
            DDLogVerbose(@"DAY INDEX %@",@(dayIndex));
            
            // NB: Day (Date Only) Comparison
            NSDate* indexedDayDate = [self.convByDay dateForDay:dayIndex];
            if ( indexedDayDate == nil ) {
                DDLogError(@"No NSDate for day index %@",@(dayIndex));
                continue;   // skip to next dayIndex
            }

            NSDate* convToInsertDate = [ciToInsert day];
            
            NSComparisonResult dayComparisonResult = [convToInsertDate compare:indexedDayDate];
            
            if (dayComparisonResult == NSOrderedDescending) {
                //Email Before //Insert section before date //+ email  << Not Andy's comment
                
                [self.convByDay insertNewDayWithConservationIndex:ciToInsert andDate:ciToInsert.day atDayIndex:dayIndex];
                
                //DDLogDebug(@"numberOfSections: %d", [self.table numberOfSections]);
                //DDLogDebug(@"self.convByDay: %d", [self.convByDay dayCount]);
                //NSInteger pager = MIN([self.convByDay dayCount], (pageCount * self.pageIndex)+1-self.deletedSections);
                //DDLogDebug(@"pager: %d", pager);
                
                [self _insertTableSection:dayIndex];
                
                added = YES;
                break;
            }
            else if (dayComparisonResult == NSOrderedSame) {
                //Add email to section of date
                
                [self.convByDay sortConversationsByDateForDay:dayIndex];
                
                NSUInteger convCount = [self.convByDay conversationCountOnDay:dayIndex];
                
                for (NSUInteger convIndex = 0 ; convIndex < convCount ; convIndex++) {  // For each of the day's conversations ...
                    
                    // NB: datetime comparison to find position of conversation In Time in Dated Section
                    NSDate *indexedConvDate = [self.convByDay datetimeForConversation:convIndex onDay:dayIndex];
                    NSDate *insertConvDate  = [ciToInsert date];
                
                    NSComparisonResult convComparisonResult = [insertConvDate compare:indexedConvDate];
                    
                    if (convComparisonResult == NSOrderedDescending) {

                        [self.convByDay insertConversation:ciToInsert atConversationArrayIndex:convIndex onDay:dayIndex];
                        
                        if ( [self.convByDay dayCount] > dayIndex) { // if not, dayIndex range error
                            
                            [self _insertTableRow:convIndex inSection:dayIndex];
                            
                        }else {
                            DDLogError(@"Something went wrong with convByDay");
                        }
                        
                        added = YES;
                        
                        break; // break out of the convIndex for loop
                    }
//                    else {
//                        DDLogDebug(@"DO NOTHING (Conv Comparison Result not Descending).");
//                    }
                    
                } // end for convIndex
                
                if (!added) {
                    // Store index/date into conversations for covDay
                    
                    [self.convByDay appendConversation:ciToInsert onDay:dayIndex];
                    
                    if ( [self.convByDay dayCount] > dayIndex) { // validate dayIndex
                        
                        NSUInteger convIndex = [self.convByDay conversationCountOnDay:dayIndex] - 1;     // append conversation to end of section
                        
                        [self _insertTableRow:convIndex inSection:dayIndex];
                    }else {
                        DDLogError(@"Something went wrong with convByDay");
                    }
                    
                    added = YES;
                }
                
                break;
                
            } // NSOrderedSame
//            else {
//                DDLogDebug(@"DO NOTHING - Day Date Compare Results == Ascending");
//            }
            
        } // end for dayIndex
        
        if (!added) {
            //Date section not existing //Add new date //Add email to new date
            [self.convByDay appendNewDayWithConversationIndex:ciToInsert andDate:ciToInsert.day];
            
            //DDLogDebug(@"numberOfSections: %d", [self.table numberOfSections]);
            //DDLogDebug(@"self.convByDay: %d", [self.convByDay dayCount]);
            //NSInteger pager = MIN([self.convByDay dayCount], (pageCount * self.pageIndex)+1-self.deletedSections);
            //DDLogDebug(@"pager: %d", pager);
            
            //if( [self.convByDay dayCount] < pager) {
            
            NSUInteger dayIndex = [self.convByDay dayCount] - 1;  // insert at end of sections
            
            [self _insertTableSection:dayIndex];    // no need to insert row into section

            //}
        }
        
        [self.tableView endUpdates];
    }];
    
}

-(void)_insertTableSection:(NSUInteger)section
{
    @synchronized (self.tableView) {
        
        UITableView *localTable = self.tableView;
        
        DDLogDebug(@"Insert Section = %@",@(section));
        
        NSIndexSet *indexSet = [NSIndexSet indexSetWithIndex:section];
        
        [localTable beginUpdates];
        
        [localTable insertSections:indexSet withRowAnimation:UITableViewRowAnimationFade];
        
        [localTable endUpdates];
        
    } // end synchronized
}
-(void)_insertTableRow:(NSUInteger)row inSection:(NSUInteger)section
{
    @synchronized (self.tableView) {
        
        UITableView *localTable = self.tableView;

        DDLogDebug(@"Insert Row %@ in Section %@",@(row),@(section));

        [localTable beginUpdates];
        
        NSArray<NSIndexPath*> *indexPaths = @[ [NSIndexPath indexPathForRow:(NSInteger)row
                                                                  inSection:(NSInteger)section] ];
        
        [localTable insertRowsAtIndexPaths:indexPaths withRowAnimation:UITableViewRowAnimationFade];
        
        [localTable endUpdates];
        
    } // end synchronized
}

//- (void)_InsertConversation:(ConversationIndex *)ciToInsert
//{
//    BOOL conversationAddedToConvByDate = NO;
//
//    // To find where to insert this conversation, we look through the convByDate array
//    NSInteger dayCount = [self.convByDay dayCount];
//    for (int dayIndex = 0 ; dayIndex < dayCount ; dayIndex++) {
//        
//        NSDate* indexedDayDate = [self.convByDay dateForDay:dayIndex];
//          (add indexedDayDate nil check - see elsewehere in this file)
//        
//        NSComparisonResult result = [ciToInsert.day compare:indexedDayDate];
//        
//        if (result == NSOrderedDescending) {
//            //Email Before //Insert section before date //+ email
//            
//            [self.convByDay insertNewDayWithConservationIndex:ciToInsert andDate:ciToInsert.day atDayIndex:dayIndex];
//            
//            conversationAddedToConvByDate = YES;
//            break;
//        }
//        else if (result == NSOrderedSame) { // same day, so search through the coversations on that date
//            //Add email to section of date
//            
//            [self.convByDay sortConversationsByDateForDay:dayIndex];
//            
//            NSInteger conCount = [self.convByDay conversationCountOnDay:dayIndex];
//            
//            for (int convArrayIndex = 0 ; convArrayIndex < conCount ; convArrayIndex++) {
//                
//                ConversationIndex* indexedConversationIndex = [self.convByDay conversation:convArrayIndex onDay:dayIndex];
//                
//                NSComparisonResult result = [ciToInsert.date compare:indexedConversationIndex.date];
//                
//                if (result == NSOrderedDescending) {
//                    
//                    [self.convByDay insertConversation:ciToInsert atConversationArrayIndex:convArrayIndex onDay:dayIndex];
//                    
//                    conversationAddedToConvByDate = YES;
//                    break;
//                }
//            }
//            
//            if (!conversationAddedToConvByDate) {
//                // Add at end
//                [self.convByDay appendConversation:ciToInsert onDay:dayIndex];
//                conversationAddedToConvByDate = YES;
//            }
//            
//            break;
//        }
//    }
//    
//    if (!conversationAddedToConvByDate) {
//        //Date section not existing //Add new date //Add email to new date
//        [self.convByDay appendNewDayWithConversationIndex:ciToInsert andDate:ciToInsert.day];
//    }
//}

// Given an array of ConversationIndex (from a folder)
// If each one is not already found in the Conversations Per Accounty ...
//      Then add it to both the4 Conversations Per Account and Conversations By Day structures
-(void) insertConversations:(NSArray<ConversationIndex*>*) folderConversations  // array of folder's conversations
{
    DDAssert(folderConversations, @"Method cannot be passed a nil");
    
    if ( folderConversations.count == 0 ) {
        DDLogWarn(@"ZERO Folder Conversations to insert, returning.");
    } else {
        DDLogDebug(@"Will put %ld Conversations into Mail List Table",(long)folderConversations.count);
        
        if (self.showOnlyThisPerson) {
            DDLogDebug(@"showOnlyThisPerson == TRUE");
            folderConversations = [self _filterResultsForPerson:folderConversations];
        }
        
        NSMutableArray<ConversationIndex*>* folderConvs = [folderConversations mutableCopy];
        
        // TODO: If pConvs/convs only has one entry, then sort by date seems unnedsecary
        NSSortDescriptor *sortByDate = [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(date)) ascending:NO];
        [folderConvs sortUsingDescriptors:@[sortByDate]];
        
        //[[NSOperationQueue mainQueue] addOperationWithBlock:^{
        
        for (ConversationIndex* conversationIndex in folderConvs) {
            
            if ([self.conversationsPerAccount containsConversationIndex:(NSUInteger)conversationIndex.index
                                                              inAccount:conversationIndex.user.accountIndex]) {
                continue;
            }
            
            Conversation* conv = [[Accounts sharedInstance] conversationForCI:conversationIndex];
            
            NSInteger currentFolderIdx = [conv.user numFolderWithFolder:self.folder];
            
            if (currentFolderIdx != [conv.user numFolderWithFolder:allFolderType()]) {
                
                // Prefetch conversation UIDs from Mail Database (?)
                [conv foldersType];
                
                BOOL isInFolder = [conv isInFolder:currentFolderIdx];
                
                if (!isInFolder) {
#ifdef USING_INSTABUG
                    IBGLogWarn(@"Insert cell: Conversation with error:%ld",(long)conversationIndex.index);
#endif
                    DDLogWarn(@"Insert cell: Conversation with error:%ld",(long)conversationIndex.index);
                    
                    Account* a = [[Accounts sharedInstance] account:conv.user.accountIndex];
                    [a deleteIndex:conversationIndex.index fromFolder:self.folder];
                    continue;
                }
            }
            
            [self.conversationsPerAccount addConversationIndex:(NSUInteger)conversationIndex.index
                                                    forAccount:conversationIndex.user.accountIndex];
            
            [self.convByDay insertConversation:conversationIndex];
        }
        
        [self _reloadTableViewOnMainThread];
        
        self.initialLoading = NO;
    }
    
    [self _updateViewTitle];
    //}];
}

-(NSMutableArray*) _filterResultsForPerson:(NSArray<ConversationIndex*>*)convs
{
    NSMutableArray* current = [convs mutableCopy];
    
    NSInteger personID = [[Persons sharedInstance] indexForPerson:self.showOnlyThisPerson];
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
                for (NSNumber* toPersonID in mail.toPersonIDs) {
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
    NSUInteger swipetype = [Accounts sharedInstance].quickSwipeType;
    
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
    else if((self.folder.type == FolderTypeAll && swipetype == QuickSwipeArchive) || (self.folder.type == FolderTypeDeleted && swipetype == QuickSwipeDelete)) {
        //We archive emails from the archive folder if they are already in the Inbox
        arch.highlightedImage = [UIImage imageNamed:@"swipe_inbox"];
    }
    
    return arch;
}

-(void) unselectAll
{
    WhiteBlurNavBar *localNavBar = self.navBar;
    
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        
        [UIView setAnimationsEnabled:NO];
        
        UINavigationItem* item = localNavBar.items.lastObject;
        [self _applyTrueTitleViewTo:item];
        [localNavBar setNeedsDisplay];
        [UIView setAnimationsEnabled:YES];
        
        @synchronized (self.tableView) {

            NSArray* visibles = self.tableView.visibleCells;
            
            for (ConversationTableViewCell* cell in visibles) {
                if ([self.selectedCells containsObject:[cell currentID]]) {
                    [cell animatedClose];
                }
            }
            [self.selectedCells removeAllObjects];
            
        } // end synchronized
    }];
}

-(void) _commonRemoveConvs:(NSMutableArray<NSIndexPath*>*)conversationIndexPaths
{
    DDLogInfo(@"ENTERED");

    NSMutableIndexSet* conversationSectionIndeciesToDelete = [[NSMutableIndexSet alloc] init];
    
    [conversationIndexPaths sortUsingSelector:@selector(compare:)];
    
    NSMutableArray<NSIndexPath*>* conversationRowIndeciesToDelete
        = [[NSMutableArray alloc] initWithCapacity:conversationIndexPaths.count];
    
    for (NSIndexPath* indexPath in [conversationIndexPaths reverseObjectEnumerator]) {
        // change in model
        
        NSUInteger dayIndex = (NSUInteger)indexPath.section;    // table section is day index
        NSUInteger conIndex = (NSUInteger)indexPath.row;        // table row is conversation index on that day
        
        ConversationIndex *cIndex = [self.convByDay conversation:conIndex onDay:dayIndex];
        
        DDLogInfo(@"Conversation in acntNum %@ indexNum %@ is in: dayIndex %@ conIndex %@.",
                  @(cIndex.index),@(cIndex.user.accountIndex),@(dayIndex),@(conIndex));
        
        if ([self.conversationsPerAccount containsConversationIndex:(NSUInteger)cIndex.index
                                                          inAccount:cIndex.user.accountIndex]) {
        
            NSUInteger dayCount = [self.convByDay dayCount];
            NSUInteger conCount = [self.convByDay conversationCountOnDay:dayIndex];
            
            DDLogInfo(@"    There is a total of %@ days.",@(dayCount));
            DDLogInfo(@"    Our conversation's day has %@ conversations.",@(conCount));
            
            
            if ( conCount == 1 ) {
                
                if ( dayIndex < dayCount ) {
                    DDLogInfo(@"dayIndex %@ is less than dayCount %@, AND there is only a single conversation on this day, so add the dayIndex to the Days-To-Delete",
                              @(dayIndex),@(dayCount));
                
                    [self.convByDay removeDayAtIndex:dayIndex];
                    [conversationSectionIndeciesToDelete addIndex:dayIndex];
                }
            }
            else {

                if ( conIndex < conCount ) {
                    DDLogInfo(@"conIndex %@ is less than conCount %@, so add this coversation to the Conversations-To-Remove",
                              @(conIndex),@(conCount));
                
                    [self.convByDay removeConversation:conIndex onDay:dayIndex];
                    [conversationRowIndeciesToDelete addObject:indexPath];
                }
            }
        
            [self.conversationsPerAccount removeConversationIndex:(NSUInteger)cIndex.index
                                                       forAccount:cIndex.user.accountIndex];
        } // end if
    } // end for
    
    //self.deletedSections = self.deletedSections + is.count;
    
    @synchronized (self.tableView) {
        
    UITableView *localTable = self.tableView;

    [localTable beginUpdates];
    
    NSInteger sectionCount = [self.tableView numberOfSections];
    DDLogInfo(@"table has %@ sections.",@(sectionCount));
    IBGLog(@"table has %@ sections.",@(sectionCount));
    for ( NSInteger idx = 0; idx < sectionCount; idx++) {
        NSInteger rowCount = [self.tableView numberOfRowsInSection:idx];
        DDLogInfo(@"Section %@ has %@ rows.",@(idx),@(rowCount));
        IBGLog(@"Section %@ has %@ rows.",@(idx),@(rowCount));
    }
    
    
    DDLogInfo(@"Delete Rows (conversations): %@",conversationRowIndeciesToDelete.description);
    IBGLog(@"Delete Rows (conversations): %@",conversationRowIndeciesToDelete.description);
    [localTable deleteRowsAtIndexPaths:conversationRowIndeciesToDelete withRowAnimation:UITableViewRowAnimationFade];

    NSUInteger conversationSectionsToDeleteCount = conversationSectionIndeciesToDelete.count;
    if ( conversationSectionsToDeleteCount > 0) {
        
        DDLogInfo(@"Delete Sections (days): %@",@(conversationSectionsToDeleteCount));
        IBGLog(@"Delete Sections (days): %@",@(conversationSectionsToDeleteCount));
        
        [localTable deleteSections:conversationSectionIndeciesToDelete withRowAnimation:UITableViewRowAnimationFade];
    }
    
    [localTable endUpdates];

    //[localTable reloadEmptyDataSet];
        
    } // end synchronized
}

-(void) leftActionDoneForCell:(ConversationTableViewCell*)cell
{
    @synchronized (self.tableView) {

    UITableView *localTable = self.tableView;
    
    NSIndexPath* indexPath = [localTable indexPathForCell:cell];
    
    NSUInteger conIndex = (NSUInteger)indexPath.row;
    NSUInteger dayIndex = (NSUInteger)indexPath.section;
    
    ConversationIndex* conversationIndex = [self.convByDay conversation:conIndex onDay:dayIndex];
    
    QuickSwipeType swipetype = [Accounts sharedInstance].quickSwipeType;
    
    switch (swipetype) {
        case QuickSwipeReply:
        {
            Mail* m = [[[Accounts sharedInstance] conversationForCI:conversationIndex] firstMail];
            Draft* repm = [m replyDraft:[cell isReplyAll]];
            [[NSNotificationCenter defaultCenter] postNotificationName:kPRESENT_EDITMAIL_NOTIFICATION object:nil userInfo:@{kPRESENT_MAIL_KEY:repm }];
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
            CCMFolderType totype = (swipetype == QuickSwipeArchive) ? CCMFolderTypeAll : CCMFolderTypeDeleted;
            
            Conversation* conv = [[Accounts sharedInstance] conversationForCI:conversationIndex];
            // back action
            if (self.folder.type == totype.type) {
                //We archive emails from the archive folder if they are already in the Inbox
                if(![conv isInInbox]) {
                    totype = CCMFolderTypeInbox;
                }
                else {
                    fromtype = CCMFolderTypeInbox;
                }
            }
            else if ([self isPresentingDrafts]) {
                totype = CCMFolderTypeDeleted;
            }
            
#ifdef USING_INSTABUG
            IBGLogDebug(@"Swipe Move conversation (%ld) from %lu to %lu", (long)conversationIndex.index, (unsigned long)fromtype.type, (unsigned long)totype.type);
#endif
             DDLogDebug(@"Swipe Move conversation (%ld) from %lu to %lu", (long)conversationIndex.index, (unsigned long)fromtype.type, (unsigned long)totype.type);
            
#ifdef USING_FLURRY
            NSString* fromFolderString;
            NSString* toFolderString;
            
            if (self.folder.type == FolderTypeUser) {
                fromFolderString = @"UserFolder";
            }
            else {
                fromFolderString = [conv.user.linkedAccount systemFolderNames][self.folder.idx];
            }
            
            if (totype.type == FolderTypeUser) {
                toFolderString = @"UserFolder";
            }
            else {
                toFolderString = [conv.user.linkedAccount systemFolderNames][totype.type];
            }
            
            
            NSDictionary *articleParams = [NSDictionary dictionaryWithObjectsAndKeys:
                                           fromFolderString, @"from_Folder",
                                           toFolderString, @"to_Folder",
                                           @"Quick_Swipe", @"action_Location"
                                           ,nil];
            [Flurry logEvent:@"Conversation Moved" withParameters:articleParams];
#endif
            
            if ([conversationIndex.user.linkedAccount moveConversationAtIndex:(NSUInteger)conversationIndex.index
                                                                         from:fromtype to:totype updateUI:FALSE]) {
                if (encodeFolderTypeWith(fromtype) == encodeFolderTypeWith(self.folder)) {
                    NSIndexPath* ip = [localTable indexPathForCell:cell];
                    [self _commonRemoveConvs:[@[ip] mutableCopy]];
                }
                else {
                    [localTable reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
                }
            }
            else {
                [localTable reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationFade];
            }
            
            break;
        }
    }
        
    } // end synchronized
}

-(void) cell:(ConversationTableViewCell*)cell isChangingDuring:(double)timeInterval
{
    @synchronized (self.tableView) {

    UITableView *tbl = self.tableView;
    
    CGPoint point = CGPointMake(100, tbl.contentOffset.y + tbl.contentInset.top);
    CGRect bigger = CGRectInset(cell.frame, -500, 0);
    
    if (CGRectContainsPoint(bigger, point)) {
        [self.navBar computeBlurForceNewDuring:timeInterval];
    }
        
    } // end synchronized
}

-(void) _manageCocoaButton
{
    __weak WhiteBlurNavBar *navBar = self.navBar;
    
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        
        CocoaButton* cb = [CocoaButton sharedButton];
        UINavigationItem* item = navBar.items.lastObject;
        const NSUInteger numberSelectedCells = self.selectedCells.count;
        
        if (numberSelectedCells==0) {
            [cb forceCloseHorizontal];
            [self _applyTrueTitleViewTo:item];
        }
        else {
            NSString* formatString = NSLocalizedString(@"%d Selected", @"Title when emails selected");
            
            if (numberSelectedCells==1) {
//                formatString =       NSLocalizedString(@"%d Selected", @"Title when emails selected");
                [cb forceOpenHorizontal];
            }
            
            UILabel* l = [[UILabel alloc] init];
            l.text = [NSString stringWithFormat:formatString, numberSelectedCells];
            l.textColor = [[Accounts sharedInstance] currentAccount].user.color;
            [l sizeToFit];
            
            item.titleView = l;
        }
        
        [self.navBar setNeedsDisplay];
        
    }];
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
    return self.tableView.panGestureRecognizer;
}

-(void)_reloadTableViewOnMainThread
{
    DDLogInfo(@"ENTERED");
    
    [self performSelectorOnMainThread:@selector(_reloadTableView)
                           withObject:nil
                        waitUntilDone:NO];
}

-(void) _reloadTableView
{

    //self.deletedSections = 0;
    
    DDAssert(self.tableView,@"tableView must be set.");
    
//    @synchronized (self.tableView) {
        
        DDLogInfo(@"Reload mail list.");
        [self.tableView reloadData];  // in UITableViewDataSource
        
//    } // end synchronized
    
    // If there are deleted mails ...
    if (self.deletes.count > 0) {
        
        dispatch_async(dispatch_get_main_queue(),^{
            [self removeConversationList:[self.deletes allObjects]];
        });
    }
}


// MARK: - UITableViewDataSource

-(NSInteger) numberOfSectionsInTableView:(UITableView*)tableView
{
    NSInteger sectionCount = (NSInteger)[self.convByDay dayCount];
    
    DDLogInfo(@"Section count = %@",@(sectionCount));
    if ( sectionCount == 0 ) {
        DDLogWarn(@"ZERO sections in Mail List.");
    }
    
    return sectionCount;    //MIN([self.convByDay dayCount], (pageCount * self.pageIndex)+1-self.deletedSections);
}

-(NSInteger) tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section
{
    NSInteger conversationCountOnDay = (NSInteger)[self.convByDay conversationCountOnDay:(NSUInteger)section];
    
    DDLogInfo(@"Section %@ has %@ rows.",@(section),@(conversationCountOnDay));
    if ( conversationCountOnDay == 0 ) {
        DDLogWarn(@"ZERO conversations in section %@",@(section));
    }
    
    return conversationCountOnDay;
}

// MARK: - >>> cellForRowAtIndexPath <<<

-(UITableViewCell*) tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath
{
    NSUInteger dayIndex = (NSUInteger)indexPath.section;
    NSUInteger conIndex = (NSUInteger)indexPath.row;
    
    DDLogInfo(@"indexPath.section(eg. dayIndex)=%@, indexPath.row(eg conIndex)=%@",@(dayIndex),@(conIndex));
    
//    NSMutableArray<ConversationIndex*>* convs = [self.convByDay conversationsForDay:indexPath.section];
//    ConversationIndex* conversationIndex = convs[indexPath.row];
    
    ConversationIndex* conversationIndex = [self.convByDay conversation:conIndex onDay:dayIndex];
    Conversation* conv = [[Accounts sharedInstance] conversationForCI:conversationIndex];
    
    if (self.presentAttach && [conv hasAttachments]) {
        [self.attachButton setHidden:NO];
    }
    
    
    NSUInteger dayCount = [self.convByDay dayCount];
    NSUInteger conCount = [self.convByDay conversationCountOnDay:dayIndex];
    
    BOOL lastSection = (dayIndex == dayCount - 1);//(indexPath.section == pageCount * self.pageIndex || indexPath.section == dayCount - 1);
    BOOL lastRow     = (conIndex == conCount - 1);
    
    if ( lastSection && lastRow && !self.showOnlyThisPerson ) {
        
        DDLogDebug(@"Last Section && Last Row && NOT showing person search results");
        DDLogVerbose(@"\tLast Section = ( dayIndex (%ld) == dayCount (%ld - 1) )",
                  (long)dayIndex,(unsigned long)dayCount);
        DDLogVerbose(@"\tLast Row     = ( conIndex (%ld) == conCount (%ld - 1) )",
                  (long)conIndex,(unsigned long)conCount);
        
        if (self.indexCount != self.countBeforeLoadMore) { // at present these are ALWAYS the same
            DDLogDebug(@"\tindex count NOT equal to count before load more, so calling reFetch");
            [self reFetch:NO];
        }
        else if (self.localSearchDone) {
            DDLogDebug(@"\tLocal Search Done, calling account.localFetchMore");
            [[Accounts sharedInstance].currentAccount localFetchMore:YES];
        }
        else {
            DDLogDebug(@"\tNOT (indexCount != countBeforeLoadMore)\n\tNOT (localSearchDone)");
        }
    }
    
    
    NSString* idToUse = (conv.mails.count > 1) ? kCONVERSATION_CELL_ID : kMAIL_CELL_ID;
    
    ConversationTableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:idToUse];
    
    if (cell == nil) {
        cell = [[ConversationTableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:idToUse];
        [cell setupWithDelegate:self];
    }
    
    
    // If this is not the All Folder or the Drafts Folder ...
    if (self.folder.type != FolderTypeAll && self.folder.type != FolderTypeDrafts) {
        
        NSMutableString* fldrsStill = [NSMutableString string];
        
        for (NSNumber* fldr in conv.foldersType) {
            [fldrsStill appendFormat:@" %lu",(unsigned long)decodeFolderTypeWith([fldr integerValue]).type];
        }
        
        NSInteger currentFolderIdx = [conv.user numFolderWithFolder:self.folder];

        BOOL isInFolder = [conv isInFolder:currentFolderIdx];
        
        if (!isInFolder) {
            DDLogInfo(@"Showing cell, Conversation of %ld (%ld) - %@ -in folders %@ ",
                      (long)conv.mails.count, (long)conversationIndex.index,[conv firstMail].subject, fldrsStill);
            
            // Add this Conversation Index to those to be deleted
            [self.deletes addObject:conversationIndex];
        }
    }
    
    BOOL isSelected = [self.selectedCells containsObject:[conv firstMail].msgID];
    
    [cell fillWithConversation:conv isSelected:isSelected isDebugMode:self.isDebugMode];
    
    if ( cell && cell.textLabel && cell.textLabel.text ) {
        DDLogInfo(@"returining \"%@\" cell.",cell.textLabel.text);
    }
    
    return cell;
}

-(NSString*) tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section
{
    NSUInteger dayIndex = (NSUInteger)section;
    
    NSDate* convDate = [self.convByDay dateForDay:dayIndex];
    if ( convDate == nil ) {
        DDLogError(@"No NSDate for day index %@",@(dayIndex));
        return @"";
    }
    
    NSString* dateS = [[DateUtil getSingleton] humanDate:convDate];

    NSInteger idx = [Mail isTodayOrYesterday:dateS];
    
    if (idx == 0) {
        return NSLocalizedString(@"mail-list-view.date-header.today", @"Today");
    }
    else if (idx == -1) {
        return NSLocalizedString(@"mail-list-view.date-header.yesterday", @"Yesterday");
    }
    
    return dateS;
}

// MARK: - UITableViewDelegate

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 90;
}

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
    UIColor* color = [[Accounts sharedInstance] currentAccount].user.color;
    
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
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        
        NSMutableArray<ConversationIndex*>* res = [[NSMutableArray alloc] initWithCapacity:self.selectedCells.count];
        
        NSUInteger dayCount = [self.convByDay dayCount];
        for (NSUInteger section = 0; section < dayCount; section++ ) {
            
            NSUInteger conCount = [self.convByDay conversationCountOnDay:section];
            for ( NSUInteger row = 0; row < conCount; row++) {
                
                ConversationIndex* conversationIndex = [self.convByDay conversation:row onDay:section];
                
                Conversation* conv = [[Accounts sharedInstance] conversationForCI:conversationIndex];
                
                NSString* mailID = [conv firstMail].msgID;
                
                if ([self.selectedCells containsObject:mailID]) {
                    [res addObject:conversationIndex];
                }
            }
            if (res.count == self.selectedCells.count) {
                break;
            }
        }
        
//        for (NSDictionary* mailsDay in self.convByDay) {
//            
//            NSArray* convs = mailsDay[@"list"];
//            
//            NSInteger row = 0;
//            
//            for (ConversationIndex* conversationIndex in convs) {
//                
//                
//                Conversation* conv = [[Accounts sharedInstance] conversationForCI:conversationIndex];
//                
//                NSString* mailID = [conv firstMail].msgID;
//                
//                if ([self.selectedCells containsObject:mailID]) {
//                    [res addObject:conversationIndex];
//                }
//                
//                row++;
//                
//                
//                
//                
//                
//            }
//            
//            if (res.count == self.selectedCells.count) {
//                break;
//            }
//            section++;
//        }
        // TODO find a less expensive way to do that
        
        NSMutableArray<ConversationIndex*>* dels = [[NSMutableArray alloc] init];
        
        for (ConversationIndex* conversationIndex in res) {
            Account* ac = [[Accounts sharedInstance] account:conversationIndex.user.accountIndex];
            
#ifdef USING_INSTABUG
            IBGLogDebug(@"Bulk Move conversation (%ld) from %lu to %lu", (long)conversationIndex.index, (unsigned long)self.folder.type, (unsigned long)toFolder.type);
#endif
            DDLogDebug(@"Bulk Move conversation (%ld) from %lu to %lu", (long)conversationIndex.index, (unsigned long)self.folder.type, (unsigned long)toFolder.type);
            
#ifdef USING_FLURRY
            NSString* fromFolderString;
            NSString* toFolderString;
            
            if (self.folder.type == FolderTypeUser) {
                fromFolderString = @"UserFolder";
            }
            else {
                fromFolderString = [ac systemFolderNames][self.folder.idx];
            }
            
            if (toFolder.type == FolderTypeUser) {
                toFolderString = @"UserFolder";
            }
            else {
                toFolderString = [ac systemFolderNames][toFolder.idx];
            }
            
            NSDictionary *articleParams = [NSDictionary dictionaryWithObjectsAndKeys:
                                           fromFolderString, @"from_Folder",
                                           toFolderString, @"to_Folder",
                                           @"Bulk_Selection", @"action_Location"
                                           ,nil];
            
            [Flurry logEvent:@"Conversation Moved" withParameters:articleParams];
#endif
            
            if([ac moveConversationAtIndex:(NSUInteger)conversationIndex.index from:self.folder to:toFolder updateUI:FALSE]) {
                [dels addObject:conversationIndex];
            }
            
        }
        
        if (dels.count > 0) {
            [self removeConversationList:dels];
        }
        
        [self unselectAll];
        
        [self.selectedCells removeAllObjects];
        [[CocoaButton sharedButton] forceCloseButton];
        
    });
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
            DDLogError(@"WTF !!!");
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

-(void) localSearchDone:(BOOL)done
{
    self.localSearchDone = done;
    
    DDLogInfo(@"%@ searching local", done?@"Not":@"");
    
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        @synchronized (self.tableView) {
            [self.tableView.tableFooterView setHidden:self.localSearchDone];
        } // end synchronized

    }];
}

-(void) serverSearchDone:(BOOL)done
{
    self.serverSearchDone = done;
    
    if (self.serverSearchDone) {
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            DDLogInfo(@"End RefreshControl refresh");
            [self.refreshControl endRefreshing];
        }];
    }
    else {
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            DDLogInfo(@"Begin RefreshControl refrest");
            [self.refreshControl beginRefreshing];
        }];
    }
}

- (void)reFetch:(BOOL)forceRefresh
{
    DDLogInfo(@"forceRefresh = %@]",(forceRefresh?@"TRUE":@"FALSE"));
    
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        
//        NSInteger mailCountBefore = [self.conversationsPerAccount conversationsInAllAccounts];
        
        //if (self.convByDay.count <= pageCount * self.pageIndex ) {
        BOOL isActiveAccountAll = [[Accounts sharedInstance] currentAccount].user.isAll;
        if (isActiveAccountAll) {
            NSUInteger activeAccounts = (NSUInteger)[AppSettings numActiveAccounts];
            for (NSUInteger idx = 0; idx < activeAccounts; idx++) {
                Account* a = [[Accounts sharedInstance] account:idx];
                [self insertConversations:[a getConversationsForFolder:self.folder]];
                
            }
        }
        else { // Not the "All" Mails account
            
            Account* currAcnt = [[Accounts sharedInstance] currentAccount];
            
            NSMutableArray<ConversationIndex*>* convForFolder = [currAcnt getConversationsForFolder:self.folder];
            
            [self insertConversations:convForFolder];
        }
        //}
        
        [self checkConversationsUpdate];
        
        NSInteger mailCountAfer = (NSInteger)[self.conversationsPerAccount conversationsInAllAccounts];
        
        self.indexCount = mailCountAfer;
        self.countBeforeLoadMore =  mailCountAfer;//MIN(mailCountAfer, self.countBeforeLoadMore + pageCount);
        
        
        [self _createAttachs];
        
        //DDLogDebug(@"self.indexCount:%ld", (long)self.indexCount);
        
        if (!forceRefresh && self.countBeforeLoadMore == mailCountAfer) {
            /*[self.table performSelectorOnMainThread:@selector(reloadEmptyDataSet)
                                         withObject:nil
                                      waitUntilDone:NO];*/
            
            DDLogDebug(@"NOT Refreshing MailListView because forceRefresh is FALSE, AND ( countBeforeLoadMore(%lu) EQUALS mailCountAfter(%lu) )",
                       (long)self.countBeforeLoadMore,(long)mailCountAfer);
            return;
        }
        
        [self _reloadTableViewOnMainThread];
    }];
}

#pragma mark - EmptyDataSet

- (UIImage *)imageForEmptyDataSet:(UIScrollView *)scrollView
{
    return self.initialLoading?nil:[self isInbox]?[UIImage imageNamed:@"zeromail"]:nil;
}

- (CAAnimation *)imageAnimationForEmptyDataSet:(UIScrollView *)scrollView
{
    CABasicAnimation *animation = [CABasicAnimation animationWithKeyPath: @"transform"];
    
    animation.fromValue = [NSValue valueWithCATransform3D:CATransform3DIdentity];
    animation.toValue = [NSValue valueWithCATransform3D:CATransform3DMakeRotation(M_PI_2, 0.0, 0.0, 1.0)];
    
    animation.duration = 0.25;
    animation.cumulative = YES;
    animation.repeatCount = MAXFLOAT;
    
    return animation;
}

- (NSAttributedString *)titleForEmptyDataSet:(UIScrollView *)scrollView
{
    NSString *text = self.initialLoading?@"":self.showOnlyThisPerson?NSLocalizedString(@"No emails.", @"No emails."):NSLocalizedString(@"No more emails.", @"No more emails.");
    
    NSDictionary *attributes = @{NSFontAttributeName: [UIFont boldSystemFontOfSize:18.0f],
                                 NSForegroundColorAttributeName: [UIColor darkGrayColor]};
    
    return [[NSAttributedString alloc] initWithString:text attributes:attributes];
}

- (NSAttributedString *)ForEmptyDataSet:(UIScrollView *)scrollView
{
    NSString *text = self.initialLoading?@"":[self isInbox]?NSLocalizedString(@"Go get some cocoa!", @"Go get some cocoa!"):@"";
    
    NSMutableParagraphStyle *paragraph = [NSMutableParagraphStyle new];
    paragraph.lineBreakMode = NSLineBreakByWordWrapping;
    paragraph.alignment = NSTextAlignmentCenter;
    
    NSDictionary *attributes = @{NSFontAttributeName: [UIFont systemFontOfSize:14.0f],
                                 NSForegroundColorAttributeName: [UIColor lightGrayColor],
                                 NSParagraphStyleAttributeName: paragraph};
    
    return [[NSAttributedString alloc] initWithString:text attributes:attributes];
}

/*- (NSAttributedString *)buttonTitleForEmptyDataSet:(UIScrollView *)scrollView forState:(UIControlState)state
 {
 NSDictionary *attributes = @{NSFontAttributeName: [UIFont boldSystemFontOfSize:17.0f]};
 
 return [[NSAttributedString alloc] initWithString:@"All mail" attributes:attributes];
 }*/

- (BOOL) emptyDataSetShouldAllowImageViewAnimate:(UIScrollView *)scrollView
{
    return YES;
}

- (BOOL)emptyDataSetShouldDisplay:(UIScrollView *)scrollView
{
    return YES;
}

- (BOOL)emptyDataSetShouldAllowTouch:(UIScrollView *)scrollView
{
    return YES;
}

- (BOOL)emptyDataSetShouldAllowScroll:(UIScrollView *)scrollView
{
    return YES;
}

-(BOOL) isInbox
{
    return (self.folder.type == FolderTypeInbox);
}

-(NSString *) description
{
    NSMutableString *txt = [NSMutableString string];
    
    [txt appendString:@"\n\n *** MailListViewController ***"];
    
    // convByDay is a Mutable Array of Dictionaries
//    NSInteger convCount = [self.convByDay dayCount];
//    [txt appendFormat:@"\n\tconvByDay has %ld entries",(long)convCount];
//    
//    for ( NSInteger conv = 0; conv < convCount; conv++ ) {
//        NSDictionary *convDict = self.convByDay[conv];
//        
//        [txt appendFormat:@"\n\tconvByDay[%ld]: %@",(long)conv,convDict];
//    }
    
    [txt appendString:@"\n * Conversations Per Account: "];
    [txt appendString:[self.conversationsPerAccount description]];
    
    [txt appendString:@"\n * Conversations By Day:"];
    [txt appendString:[self.convByDay description]];
    
    [txt appendString:@"\n *** MailListViewController description end *** "];
    return txt;
}

@end
