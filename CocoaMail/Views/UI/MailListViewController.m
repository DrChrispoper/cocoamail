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
#import "EmailProcessor.h"
#import "AppSettings.h"
#import "DateUtil.h"
#import "SyncManager.h"
#import "SearchRunner.h"
#import "ImapSync.h"
#import "UserFolderViewController.h"
#import <ReactiveCocoa/ReactiveCocoa.h>
#import "CCMStatus.h"
#import "CocoaMail-Swift.h"
#import "PreviewViewController.h"
#import "ConversationViewController.h"
#import "MailListViewController+UIViewControllerPreviewing.h"
//#import "UIScrollView+EmptyDataSet.h"
#import "Flurry.h"
#import "UserSettings.h"
#import "Conversation.h"
#import "Draft.h"


#ifdef USING_INSTABUG
#import <Instabug/Instabug.h>
#endif

@interface MailListViewController () <UITableViewDataSource, UITableViewDelegate, ConversationCellDelegate, UserFolderViewControllerDelegate, MailListDelegate/*, DZNEmptyDataSetSource, DZNEmptyDataSetDelegate*/>

@property (nonatomic, strong) NSMutableArray<NSMutableIndexSet*>* indexSet;
@property (nonatomic, strong) NSMutableSet* deletes;

//@property (nonatomic) NSInteger pageIndex;
//@property (nonatomic) NSInteger deletedSections;
@property (nonatomic) NSInteger countBeforeLoadMore;
@property (nonatomic) NSInteger indexCount;
@property (nonatomic, strong) NSString* folderName;
@property (nonatomic, strong) NSMutableSet* selectedCells;
@property (nonatomic, strong) Person* onlyPerson;
@property (nonatomic) BOOL presentAttach;
@property (nonatomic, strong) UIButton* attachButton;
@property (nonatomic, retain) NSOperationQueue* localFetchQueue;
@property (nonatomic) CCMFolderType folder;
@property (nonatomic) BOOL longPressOnCocoabutton;
@property (nonatomic, strong) UserFolderViewController* chooseUserFolder;
@property (nonatomic) BOOL isDebugMode;
@property (nonatomic) BOOL initialLoading;
@property (nonatomic) BOOL localSearchDone;
@property (nonatomic) BOOL serverSearchDone;
@property (nonatomic) BOOL closing;

@property (nonatomic, strong) UIRefreshControl* refreshC;

@end

@implementation MailListViewController

//static NSInteger pageCount = 15;

-(instancetype) initWithName:(NSString*)name
{
    self = [super init];
    self.folderName = name;
    
    self.selectedCells = [[NSMutableSet alloc] initWithCapacity:25];
    //self.pageIndex = 1;
    //self.deletedSections = 0;
    self.countBeforeLoadMore = 0;
    self.indexCount = 0;
    self.isDebugMode = NO;
    self.initialLoading = YES;
    self.closing = NO;
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
    self.folder = CCMFolderTypeAll;
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
    
    [self check3DTouch];
    
    self.view.backgroundColor = [UIGlobal standardLightGrey];
    
    self.localFetchQueue = [NSOperationQueue new];
    [self.localFetchQueue setMaxConcurrentOperationCount:1];
    
    self.convByDay = [[NSMutableArray alloc]initWithCapacity:100];
    self.indexSet = [[NSMutableArray alloc]initWithCapacity:[Accounts sharedInstance].accountsCount];
    self.deletes = [[NSMutableSet alloc]init];

    for (Account* a in [Accounts sharedInstance].accounts) {
        if (!a.user.isAll) {
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
        
        UIView* badge = [self.onlyPerson doubleBadgeView];
        badge.center = CGPointMake(33 + 13, 46);
        //badge.transform = CGAffineTransformMakeScale(2.f, 2.f);
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
    
    [headerView setHidden:YES];
    
    self.table.tableFooterView = headerView;
    
    if (!self.onlyPerson) {
        self.refreshC = [[UIRefreshControl alloc] init];
        [self.table addSubview:self.refreshC];
        [self.refreshC addTarget:self action:@selector(refreshTable) forControlEvents:UIControlEventValueChanged];
        //[self addPullToRefreshWithDelta:0];
        //table.emptyDataSetSource = self;
        //table.emptyDataSetDelegate = self;
    }
    
    if (self.convByDay.count == 0) {
        [self setupData];
    }
}

- (void)refreshTable {
    [[Accounts sharedInstance].currentAccount refreshCurrentFolder];
    //[[Accounts sharedInstance].currentAccount localFetchMore:NO];
    //[ImapSync runInboxUnread:[Accounts sharedInstance].currentAccount.user];
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
        
        [self reload];
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
                if ([m hasAttachments]) {
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
    //[c firstMail].subject = self.onlyPerson.name;
    
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
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.persistent = YES;
    pasteboard.string = self.onlyPerson.email;
    [CCMStatus showStatus:NSLocalizedString(@"Email copied", @"Email copied to pasteboad") dismissAfter:2 code:0];
}

-(void) _press:(UITapGestureRecognizer*)tgr
{
    Draft* draft = [Draft newDraftFormCurrentAccount];
    
    //NSInteger personIndex = [[Persons sharedInstance] indexForPerson:self.onlyPerson];
    
    draft.toPersons = [NSMutableArray arrayWithArray:@[self.onlyPerson.email]];
    
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
    //self.pageIndex = 1;
    self.countBeforeLoadMore = 0;
    self.indexCount = 0;
    self.closing = YES;

    self.table.delegate = nil;
    self.table.dataSource = nil;
    [[SearchRunner getSingleton] cancel];
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    //self.table.emptyDataSetSource = self;
    //self.table.emptyDataSetDelegate = self;
    
    if (self.indexSet.count < [AppSettings numActiveAccounts]) {
        [self.indexSet addObject:[[NSMutableIndexSet alloc]init]];
    }
    
    [[Accounts sharedInstance] currentAccount].mailListSubscriber = self;
    
    [self serverSearchDone:YES];

    //[self reFetch:YES];
}

-(void) viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self becomeFirstResponder];
    
    [[Accounts sharedInstance] appeared];
    
    //[[CocoaButton sharedButton] enterLevel:1];
    //[[Accounts sharedInstance].currentAccount showProgress];
    
    if (self.onlyPerson) {
        [[Accounts sharedInstance].currentAccount doPersonSearch:self.onlyPerson];
    }
}

-(void) viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    [self.table setContentOffset:self.table.contentOffset animated:NO];
    
    //[[Accounts sharedInstance] currentAccount].mailListSubscriber = nil;

    if (!self.onlyPerson) {
        //self.table.emptyDataSetSource = nil;
        //self.table.emptyDataSetDelegate = nil;
    }
    
    
    [ViewController animateCocoaButtonRefresh:NO];
}

-(void) setupData
{
    DDLogDebug(@"-[MailListViewController setupData]");
    if (kisActiveAccountAll) {
        DDLogDebug(@"\tActive Account is \"All\" Account");
        for (int idx = 0; idx < [AppSettings numActiveAccounts]; idx++) {
            Account* a = [[Accounts sharedInstance] account:idx];
            a.mailListSubscriber = self;
            [self insertConversations:[a getConversationsForFolder:self.folder]];
        }
    }
    else {
        Account* a = [[Accounts sharedInstance] currentAccount];
        DDLogDebug(@"\tActive Account Index = %ld\n",[a idx]);
        a.mailListSubscriber = self;
        [self insertConversations:[[Accounts sharedInstance].currentAccount getConversationsForFolder:self.folder]];
    }
}

-(void) removeConversationList:(NSArray *)convs
{
    
    if (convs) {
        [self _removeConversation:convs];
    }
    else {
        [self performSelectorOnMainThread:@selector(reload)
                               withObject:nil
                            waitUntilDone:NO];
    }
}

-(void) _removeConversation:(NSArray*)convs
{
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{

    NSMutableArray* ips = [[NSMutableArray alloc]init];
    
    for (ConversationIndex* pConversationIndex in convs) {
        
        if ([self.indexSet[pConversationIndex.user.accountIndex] containsIndex:pConversationIndex.index]) {
            
            NSLog(@"ConversationIndex:%ld in Account:%ld", (long)pConversationIndex.index, (unsigned long)pConversationIndex.user.accountNum);
            
            BOOL found = NO;
            
            for (NSInteger section = 0; section < self.convByDay.count ;section++) {
                NSArray* list = self.convByDay[section][@"list"];
                
                for (NSInteger row = 0; row < list.count; row++) {
                    ConversationIndex* conversationIndex = list[row];
                    
                    if (conversationIndex.index == pConversationIndex.index) {
                        [ips addObject:[NSIndexPath indexPathForRow:row inSection:section]];
                        found = YES;
                        break;
                    }
                }
                
                if (found) break;
            }
        }
    }
    
        [self _commonRemoveConvs:ips];
    }];
}

-(void) checkConversationsUpdate
{
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        
        NSMutableArray* reAddConvs = [[NSMutableArray alloc] init];
        
        for (int dayIndex = 0 ; dayIndex < self.convByDay.count ; dayIndex++) {
            
            NSDate* tmpDay = self.convByDay[dayIndex][@"day"];
            
            NSMutableArray* list = self.convByDay[dayIndex][@"list"];
            
            for (int j = 0 ; j < list.count ; j++) {
                ConversationIndex* cI = list[j];
                
                NSComparisonResult dayresult = [cI.day compare:tmpDay];
                
                if (dayresult != NSOrderedSame) {
                    [reAddConvs addObject:cI];
                    continue;
                }
                
                if (j+1 < list.count) {
                    ConversationIndex* cINext = list[j+1];
                    
                    NSComparisonResult dateresult = [cINext.date compare:cI.date];
                    
                    if (dateresult != NSOrderedAscending) {
                        [list exchangeObjectAtIndex:j withObjectAtIndex:j+1];
                    }
                }
            }
        }
        
        if (reAddConvs.count > 0) {
            NSLog(@"%ld Conversation Time Updated",(unsigned long)reAddConvs.count);
            [self _removeConversation:reAddConvs];
            [self insertConversations:reAddConvs];
        }
        
    }];
}

-(void) updateDays:(NSArray*)days
{
    if (!days || days.count == 0){
        return;
    }
    
    NSMutableIndexSet* sections = [[NSMutableIndexSet alloc] init];
    
    for (NSString* day in days) {
        NSDateFormatter* s_df_day = [[NSDateFormatter alloc] init];
        s_df_day.dateFormat = @"d MMM yy";
        NSDate* dayDate = [s_df_day dateFromString:day];
        
        for (int dayIndex = 0 ; dayIndex < self.convByDay.count ; dayIndex++) {
            NSDate* tmpDay = self.convByDay[dayIndex][@"day"];
            if ([dayDate compare:tmpDay] == NSOrderedSame){
                [sections addIndex:dayIndex];
            }
        }
    }
    
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [self.table beginUpdates];
        [self.table reloadSections:sections withRowAnimation:UITableViewRowAnimationNone];
        [self.table endUpdates];
    }];

}

-(void) insertConversationIndex:(ConversationIndex*)ci
{
   [[NSOperationQueue mainQueue] addOperationWithBlock:^{
       if (self.closing) {
           return ;
       }
       
    if (self.onlyPerson) {
    NSInteger personID = [[Persons sharedInstance] indexForPerson:self.onlyPerson];
    NSInteger meID = [[Persons sharedInstance] indexForPerson:[Accounts sharedInstance].currentAccount.person];
    
    BOOL found = false;

    for (Mail* mail in [[[Accounts sharedInstance] conversationForCI:ci] mails]) {
        
        if (mail.fromPersonID == personID) {
            found = true;
        }
        else if (mail.fromPersonID == meID) {
            for (NSNumber* toPersonID in mail.toPersonIDs) {
                if ([toPersonID integerValue] == personID) {
                    found = true;
                    break;
                }
            }
        }
        
        if (found) {
            break;
        }
    }
    
    if(!found){
        return;
    }
    }
    
    if ([self.indexSet[ci.user.accountIndex] containsIndex:ci.index]) {
        return;
    }
    
    Conversation* conv = [[Accounts sharedInstance] conversationForCI:ci];
    
    NSInteger currentFolderIdx = [conv.user numFolderWithFolder:self.folder];
    
    if (currentFolderIdx != [conv.user numFolderWithFolder:FolderTypeWith(FolderTypeAll, 0)]) {
        
        [conv foldersType];
        
        BOOL isInFolder = NO;
        
        for (Mail* mail in conv.mails) {
            if ([mail uidEWithFolder:currentFolderIdx]) {
                isInFolder = YES;
                break;
            }
        }
        
        if (!isInFolder) {
#ifdef USING_INSTABUG
            IBGLog([NSString stringWithFormat:@"Insert cell: Conversation with error:%ld",(long)ci.index]);
#endif
            NSLog(@"Insert cell: Conversation with error:%ld",(long)ci.index);
            
            Account* a = [[Accounts sharedInstance] account:conv.user.accountIndex];
            [a deleteIndex:ci.index fromFolder:self.folder];
            return;
        }
    }
    
    NSSortDescriptor *sortByDate = [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(date)) ascending:NO];

    [self.indexSet[ci.user.accountIndex] addIndex:ci.index];
    
    NSDate* convDay = ci.day;
    
    BOOL added = NO;
    
    for (int dayIndex = 0 ; dayIndex < self.convByDay.count ; dayIndex++) {
        
        NSDate* tmpDay = self.convByDay[dayIndex][@"day"];
        NSComparisonResult result = [convDay compare:tmpDay];
        
        if (result == NSOrderedDescending) {
            //Email Before //Insert section before date //+ email
            
            NSDictionary* earlier = @{@"list": [NSMutableArray arrayWithObject:ci], @"day":convDay};
            [self.convByDay insertObject:earlier atIndex:dayIndex];
            
            //NSLog(@"numberOfSections: %d", [self.table numberOfSections]);
            //NSLog(@"self.convByDay: %d", [self.convByDay count]);
            //NSInteger pager = MIN(self.convByDay.count, (pageCount * self.pageIndex)+1-self.deletedSections);
            //NSLog(@"pager: %d", pager);
            
            [self.table beginUpdates];
            [self.table insertSections:[NSIndexSet indexSetWithIndex:dayIndex] withRowAnimation:UITableViewRowAnimationFade];
            //[self.table insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
            [self.table endUpdates];
            
            added = YES;
            break;
        }
        else if (result == NSOrderedSame) {
            //Add email to section of date
            NSMutableArray* list = self.convByDay[dayIndex][@"list"];
            
            [list sortUsingDescriptors:@[sortByDate]];
            
            for (int j = 0 ; j < list.count ; j++) {
                
                ConversationIndex* cI = list[j];
                
                NSComparisonResult result = [ci.date compare:cI.date];
                
                if (result == NSOrderedDescending) {
                    [list insertObject:ci atIndex:j];
                    [self.table beginUpdates];
                    if (self.convByDay.count > dayIndex) {
                    [self.table insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:j inSection:dayIndex]] withRowAnimation:UITableViewRowAnimationFade];
                    }else {
                        NSLog(@"Something went wrong with convByDay");
                    }
                    [self.table endUpdates];
                    added = YES;
                    break;
                }
            }
            
            if (!added) {
                [list addObject:ci];
                [self.table beginUpdates];
                if (self.convByDay.count > dayIndex) {
                [self.table insertRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:list.count-1 inSection:dayIndex]] withRowAnimation:UITableViewRowAnimationFade];
                }else {
                    NSLog(@"Something went wrong with convByDay");
                }
                [self.table endUpdates];
                added = YES;
            }
            
            break;
        }
    }
    
    if (!added) {
        //Date section not existing //Add new date //Add email to new date
        NSDictionary* later = @{@"list": [NSMutableArray arrayWithObject:ci], @"day":convDay};
        [self.convByDay addObject:later];
        
        //NSLog(@"numberOfSections: %d", [self.table numberOfSections]);
        //NSLog(@"self.convByDay: %d", [self.convByDay count]);
        //NSInteger pager = MIN(self.convByDay.count, (pageCount * self.pageIndex)+1-self.deletedSections);
        //NSLog(@"pager: %d", pager);
        
        //if(self.convByDay.count < pager) {
            [self.table beginUpdates];
            [self.table insertSections:[NSIndexSet indexSetWithIndex:self.convByDay.count-1] withRowAnimation:UITableViewRowAnimationFade];
            [self.table endUpdates];
        //}
    }
}];

}

-(void) insertConversations:(NSArray*)pConvs
{
    DDLogDebug(@"-[MailListViewController insertConverstations:]");
    DDLogDebug(@"\tConversations array count = %ld",(long)[pConvs count]);
    
    if (self.onlyPerson) {
        pConvs = [self _filterResultsForPerson:pConvs];
    }
    
    NSMutableArray* convs = [NSMutableArray arrayWithArray:pConvs];
    
    NSSortDescriptor *sortByDate = [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(date)) ascending:NO];
    [convs sortUsingDescriptors:@[sortByDate]];
    
    //[[NSOperationQueue mainQueue] addOperationWithBlock:^{
    
        for (ConversationIndex* conversationIndex in convs) {
            
            if ([self.indexSet[conversationIndex.user.accountIndex] containsIndex:conversationIndex.index]) {
                continue;
            }
            
            Conversation* conv = [[Accounts sharedInstance] conversationForCI:conversationIndex];
            
            NSInteger currentFolderIdx = [conv.user numFolderWithFolder:self.folder];
            
            if (currentFolderIdx != [conv.user numFolderWithFolder:FolderTypeWith(FolderTypeAll, 0)]) {
                
                [conv foldersType];
                
                BOOL isInFolder = [conv isInFolder:currentFolderIdx];
                
                if (!isInFolder) {
#ifdef USING_INSTABUG
                    IBGLog([NSString stringWithFormat:@"Insert cell: Conversation with error:%ld",(long)conversationIndex.index]);
#endif
                    NSLog(@"Insert cell: Conversation with error:%ld",(long)conversationIndex.index);
                    
                    Account* a = [[Accounts sharedInstance] account:conv.user.accountIndex];
                    [a deleteIndex:conversationIndex.index fromFolder:self.folder];
                    continue;
                }
            }
            
            [self.indexSet[conversationIndex.user.accountIndex] addIndex:conversationIndex.index];
            
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
                    
                    [list sortUsingDescriptors:@[sortByDate]];
                    
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
        
        [self reload];
        self.initialLoading = NO;
    //}];
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
    else if((self.folder.type == FolderTypeAll && swipetype == QuickSwipeArchive) || (self.folder.type == FolderTypeDeleted && swipetype == QuickSwipeDelete)) {
        //We archive emails from the archive folder if they are already in the Inbox
        arch.highlightedImage = [UIImage imageNamed:@"swipe_inbox"];
    }
    
    return arch;
}

-(void) unselectAll
{
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        
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
    }];
}

-(void) _commonRemoveConvs:(NSMutableArray*)ips
{
    NSMutableIndexSet* is = [[NSMutableIndexSet alloc] init];
    
    [ips sortUsingSelector:@selector(compare:)];
    
    NSMutableArray* tmpIps = [[NSMutableArray alloc] initWithCapacity:ips.count];
    
    for (NSIndexPath* ip in [ips reverseObjectEnumerator]) {
        // change in model
        NSMutableArray* list  = self.convByDay[ip.section][@"list"];
        ConversationIndex* cIndex = list[ip.row];
        
        
        if ([self.indexSet[cIndex.user.accountIndex] containsIndex:cIndex.index]) {
            if (list.count == 1) {
                NSLog(@"Delete section:%li self.convByDay.count:%li", (long)ip.section, (unsigned long)self.convByDay.count);

                if (ip.section < self.convByDay.count) {
                    [self.convByDay removeObjectAtIndex:ip.section];
                    [is addIndex:ip.section];
                }
            }
            else {
                NSLog(@"Delete cell section:%li row:%li list.count:%li", (long)ip.section, (long)ip.row, (unsigned long)list.count);

                if (ip.row < list.count) {
                    [list removeObjectAtIndex:ip.row];
                    [tmpIps addObject:ip];
                }
            }
            
            [self.indexSet[cIndex.user.accountIndex] removeIndex:cIndex.index];
        }
    }
    
    //self.deletedSections = self.deletedSections + is.count;
    
    [self.table beginUpdates];
    
    [self.table deleteRowsAtIndexPaths:tmpIps withRowAnimation:UITableViewRowAnimationFade];

    if (is.count > 0) {
        [self.table deleteSections:is withRowAnimation:UITableViewRowAnimationFade];
    }
    
    [self.table endUpdates];

    //[self.table reloadEmptyDataSet];
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
            
#ifdef USING_INSTABUG
            IBGLog([NSString stringWithFormat:@"Swipe Move conversation (%ld) from %lu to %lu", (long)conversationIndex.index, (unsigned long)fromtype.type, (unsigned long)totype.type]);
#endif
             NSLog(@"Swipe Move conversation (%ld) from %lu to %lu", (long)conversationIndex.index, (unsigned long)fromtype.type, (unsigned long)totype.type);
            
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
            
            if ([conversationIndex.user.linkedAccount moveConversationAtIndex:conversationIndex.index from:fromtype to:totype updateUI:FALSE]) {
                if (encodeFolderTypeWith(fromtype) == encodeFolderTypeWith(self.folder)) {
                    NSIndexPath* ip = [self.table indexPathForCell:cell];
                    [self _commonRemoveConvs:[@[ip] mutableCopy]];
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
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        
        CocoaButton* cb = [CocoaButton sharedButton];
        UINavigationItem* item = self.navBar.items.lastObject;
        const NSInteger nbSelected = self.selectedCells.count;
        
        if (nbSelected==0) {
            [cb forceCloseHorizontal];
            [self _applyTrueTitleViewTo:item];
        }
        else {
            NSString* formatString = NSLocalizedString(@"%d Selected", @"Title when emails selected");
            
            if (nbSelected==1) {
                formatString = NSLocalizedString(@"%d Selected", @"Title when emails selected");
                [cb forceOpenHorizontal];
            }
            
            UILabel* l = [[UILabel alloc] init];
            l.text = [NSString stringWithFormat:formatString, nbSelected];
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
    return self.table.panGestureRecognizer;
}

#pragma mark - Table Datasource

-(void) reload
{
    DDLogDebug(@"ENTERED MailListView reload");
    //self.deletedSections = 0;
    
    [self.table reloadData];
    
    dispatch_async(dispatch_get_main_queue(),^{
        if (self.deletes.count > 0) {
            DDLogDebug(@"%ld Conversations to delete", (unsigned long)self.deletes.count);
            [self removeConversationList:[self.deletes allObjects]];
        }
    });
}

-(NSInteger) numberOfSectionsInTableView:(UITableView*)tableView
{
    return self.convByDay.count;//MIN(self.convByDay.count, (pageCount * self.pageIndex)+1-self.deletedSections);
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
    
    if (self.presentAttach && [conv hasAttachments]) {
        [self.attachButton setHidden:NO];
    }
    
    BOOL lastSection = (indexPath.section == self.convByDay.count - 1);//(indexPath.section == pageCount * self.pageIndex || indexPath.section == self.convByDay.count - 1);
    BOOL lastRow = indexPath.row == ([convs count] - 1);
    
    if (!self.onlyPerson && self.indexCount != self.countBeforeLoadMore && lastSection && lastRow) {
        [self reFetch:NO];
    }
    
    if (self.localSearchDone && !self.onlyPerson && self.indexCount == self.countBeforeLoadMore && lastSection && lastRow) {
        NSLog(@"Last and Searching");
        [[Accounts sharedInstance].currentAccount localFetchMore:YES];
    }
    
    NSString* idToUse = (conv.mails.count > 1) ? kCONVERSATION_CELL_ID : kMAIL_CELL_ID;
    
    ConversationTableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:idToUse];
    
    if (cell == nil) {
        cell = [[ConversationTableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:idToUse];
        [cell setupWithDelegate:self];
    }
    
    if (self.folder.type != FolderTypeAll && self.folder.type != FolderTypeDrafts) {
        
        NSMutableString* fldrsStill = [NSMutableString string];
        
        for (NSNumber* fldr in conv.foldersType) {
            [fldrsStill appendFormat:@" %lu",(unsigned long)decodeFolderTypeWith([fldr integerValue]).type];
        }
        
        BOOL isInFolder = NO;
        NSInteger currentFolderIdx = [conv.user numFolderWithFolder:self.folder];

        for (Mail* mail in conv.mails) {
            if ([mail uidEWithFolder:currentFolderIdx]) {
                isInFolder = YES;
                break;
            }
        }
        
        if (!isInFolder) {
            NSLog(@"%@",[NSString stringWithFormat:@"Showing cell, Conversation of %ld (%ld) - %@ -in folders %@ ", (long)conv.mails.count, (long)conversationIndex.index,[conv firstMail].subject, fldrsStill]);
            
            [self.deletes addObject:conversationIndex];
        }
    }
    
    BOOL isSelected = [self.selectedCells containsObject:[conv firstMail].msgID];
    
    [cell fillWithConversation:conv isSelected:isSelected isDebugMode:self.isDebugMode];
    
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
        
        
        NSMutableArray* res = [[NSMutableArray alloc] initWithCapacity:self.selectedCells.count];
        
        NSInteger section = 0;
        
        for (NSDictionary* mailsDay in self.convByDay) {
            NSArray* convs = mailsDay[@"list"];
            NSInteger row = 0;
            
            for (ConversationIndex* conversationIndex in convs) {
                Conversation* conv = [[Accounts sharedInstance] conversationForCI:conversationIndex];
                
                NSString* mailID = [conv firstMail].msgID;
                
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
        
        NSMutableArray* dels = [[NSMutableArray alloc] init];
        
        for (ConversationIndex* conversationIndex in res) {
            Account* ac = [[Accounts sharedInstance] account:conversationIndex.user.accountIndex];
            
#ifdef USING_INSTABUG
            IBGLog([NSString stringWithFormat:@"Bulk Move conversation (%ld) from %lu to %lu", (long)conversationIndex.index, (unsigned long)self.folder.type, (unsigned long)toFolder.type]);
#endif
            NSLog(@"Bulk Move conversation (%ld) from %lu to %lu", (long)conversationIndex.index, (unsigned long)self.folder.type, (unsigned long)toFolder.type);
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
            
            if([ac moveConversationAtIndex:conversationIndex.index from:self.folder to:toFolder updateUI:FALSE]) {
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

-(void) localSearchDone:(BOOL)done
{
    self.localSearchDone = done;
    
    NSLog(@"%@ searching local", done?@"Not":@"");
    
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        [self.table.tableFooterView setHidden:self.localSearchDone];
    }];
}

-(void) serverSearchDone:(BOOL)done
{
    self.serverSearchDone = done;
    
    if (self.serverSearchDone) {
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [self.refreshC endRefreshing];
        }];
    }
    else {
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [self.refreshC beginRefreshing];
        }];
    }
}

- (void)reFetch:(BOOL)forceRefresh
{
    DDLogDebug(@"ENTERED reFetch:(BOOL)forceRefresh=%@",
               (forceRefresh?@"TRUE":@"FALSE"));
    
    [[NSOperationQueue mainQueue] addOperationWithBlock:^{
        
        NSInteger mailCountBefore = 0;
        
        for (NSMutableIndexSet* indexSet in self.indexSet) {
            mailCountBefore += indexSet.count;
        }
        
        //if (self.convByDay.count <= pageCount * self.pageIndex ) {
            if (kisActiveAccountAll) {
                for (int idx = 0; idx < [AppSettings numActiveAccounts]; idx++) {
                    Account* a = [[Accounts sharedInstance] account:idx];
                    [self insertConversations:[a getConversationsForFolder:self.folder]];
                    
                }
            }
            else { // Not the "All" Mails view
                
                Account* a = [[Accounts sharedInstance] currentAccount];
                [self insertConversations:[a getConversationsForFolder:self.folder]];
            }
        //}
        
        [self checkConversationsUpdate];
        
        NSInteger mailCountAfer = 0;
        
        for (NSMutableIndexSet* indexSet in self.indexSet) {
            mailCountAfer += indexSet.count;
        }
        
        self.indexCount = mailCountAfer;
        self.countBeforeLoadMore =  mailCountAfer;//MIN(mailCountAfer, self.countBeforeLoadMore + pageCount);
        
        
        [self _createAttachs];
        
        //NSLog(@"self.indexCount:%ld", (long)self.indexCount);
        
        if (!forceRefresh && self.countBeforeLoadMore == mailCountAfer) {
            /*[self.table performSelectorOnMainThread:@selector(reloadEmptyDataSet)
                                         withObject:nil
                                      waitUntilDone:NO];*/
            
            DDLogDebug(@"NOT Refreshing MailListView because forceRefresh is FALSE, AND ( countBeforeLoadMore(%lu) EQUALS mailCountAfter(%lu) )",
                       self.countBeforeLoadMore,mailCountAfer);
            return;
        }
        
        DDLogDebug(@"*** Refresing MailListView ***");
        
        //self.pageIndex++;
        [self performSelectorOnMainThread:@selector(reload)
                               withObject:nil
                            waitUntilDone:NO];
        
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
    NSString *text = self.initialLoading?@"":self.onlyPerson?NSLocalizedString(@"No emails.", @"No emails."):NSLocalizedString(@"No more emails.", @"No more emails.");
    
    NSDictionary *attributes = @{NSFontAttributeName: [UIFont boldSystemFontOfSize:18.0f],
                                 NSForegroundColorAttributeName: [UIColor darkGrayColor]};
    
    return [[NSAttributedString alloc] initWithString:text attributes:attributes];
}

- (NSAttributedString *)descriptionForEmptyDataSet:(UIScrollView *)scrollView
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

@end
