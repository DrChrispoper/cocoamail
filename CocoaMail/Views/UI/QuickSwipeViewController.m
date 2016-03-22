//
//  QuickSwipeViewController.m
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 04/09/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "QuickSwipeViewController.h"
#import "Conversation.h"
#import "Accounts.h"
#import "ConversationTableViewCell.h"

@interface QuickSwipeViewController () <UITableViewDataSource, UITableViewDelegate, ConversationCellDelegate>

@property (nonatomic, strong) NSMutableArray* convs;
@property (nonatomic, weak) UITableView* table;

@end

@implementation QuickSwipeViewController

-(void) viewDidLoad
{
    [super viewDidLoad];
    
    self.convs = [[NSMutableArray alloc]initWithCapacity:1];

    CGRect screenBounds = [UIScreen mainScreen].bounds;
    
    UINavigationItem* item = [[UINavigationItem alloc] initWithTitle:@""];
    
    item.leftBarButtonItem = [self backButtonInNavBar];
    
    NSString* title = NSLocalizedString(@"quick-swipe.title", @"Quick swipe");
    item.titleView = [WhiteBlurNavBar titleViewForItemTitle:title];
    
    UITableView* table = [[UITableView alloc] initWithFrame:CGRectMake(0,
                                                                       0,
                                                                       screenBounds.size.width,
                                                                       174)
                                                      style:UITableViewStyleGrouped];
    table.contentInset = UIEdgeInsetsMake(44, 0, 0, 0);
    table.scrollIndicatorInsets = UIEdgeInsetsMake(44, 0, 0, 0);
    table.separatorStyle = UITableViewCellSeparatorStyleNone;
    table.backgroundColor = [UIGlobal standardLightGrey];
    
    [table setBounces:NO];
    [table setScrollEnabled:NO];
    
    [self.view addSubview:table];
    
    UITableView* table2 = [[UITableView alloc] initWithFrame:CGRectMake(0,
                                                                       174,
                                                                       screenBounds.size.width,
                                                                       screenBounds.size.height - 174)
                                                      style:UITableViewStyleGrouped];
    table2.contentInset = UIEdgeInsetsMake(0, 0, 0, 0);
    table2.scrollIndicatorInsets = UIEdgeInsetsMake(0, 0, 0, 0);
    table2.backgroundColor = [UIGlobal standardLightGrey];
    [table2 setBounces:NO];
    [table2 setScrollEnabled:NO];

    table.dataSource = self;
    table.delegate = self;
    
    [self.view addSubview:table2];
    
    table2.dataSource = self;
    table2.delegate = self;
    
    self.table = table;
    
    [self setupNavBarWith:item overMainScrollView:table];

    [self setupData];
}

-(void) setupData
{
    Mail* mail = [Mail newMailFormCurrentAccount];
    
    mail.subject = @"Swipe Me!";
    mail.body = @"COCOAMAILSECRECTWEAPON";
    
    Persons* p = [Persons sharedInstance];
    
    if (p.idxCocoaPerson == 0) {
        Person* more = [Person createWithName:@"CocoaMail Support" email:@"support@cocoamail.com" icon:[UIImage imageNamed:@"cocoamail"] codeName:nil];
        p.idxCocoaPerson = [p addPerson:more];
    }
    
    mail.fromPersonID = p.idxCocoaPerson;
    mail.toPersonIDs = @[@(p.idxCocoaPerson)];
    
    Conversation* conv = [[Conversation alloc]init];
    [conv addMail:mail];
    [self.convs addObject:conv];
}

-(void) cleanBeforeGoingBack
{
    self.table.delegate = nil;
    self.table.dataSource = nil;
}

-(BOOL) haveCocoaButton
{
    return NO;
}

#pragma mark - Table Datasource

-(NSInteger) numberOfSectionsInTableView:(UITableView*)tableView
{
    return 1;
}

-(NSInteger) tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section
{
    if (self.table == tableView) {
        return 1;
    }
    
    return 4;
}

-(CGFloat) tableView:(UITableView*)tableView heightForRowAtIndexPath:(NSIndexPath*)indexPath
{
    return (self.table == tableView) ? 90.0f : 52.0f;
}

-(UITableViewCell*) tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath
{
    if (self.table == tableView) {
        Conversation* conv  = self.convs[indexPath.row];
        
        NSString* idToUse = kMAIL_CELL_ID;
        
        ConversationTableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:idToUse];
        
        //if (cell == nil) {
            cell = [[ConversationTableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:idToUse];
            [cell setupWithDelegate:self];
        //}
        
        cell.separatorInset =  UIEdgeInsetsMake(0, CGRectGetWidth(cell.bounds)/2.0, 0, CGRectGetWidth(cell.bounds)/2.0);
        
        [cell fillWithConversation:conv isSelected:NO isDebugMode:NO];
        [cell setAlwaysSwiped];

        return cell;
    }
    else {
        UITableViewCell* cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"noID"];
    
    NSArray* names = @[NSLocalizedString(@"quick-swipe.archive", @"Archive"),
                       NSLocalizedString(@"quick-swipe.delete", @"Delete"),
                       NSLocalizedString(@"quick-swipe.reply", @"Reply"),
                       NSLocalizedString(@"quick-swipe.mark-as-read-unread", @"Mark as read/unread")];
    
    NSArray* imgNames = @[@"swipe_archive", @"swipe_delete", @"swipe_reply_single",@"swipe_read"];
    
    cell.textLabel.text = names[indexPath.row];
    UIImage* img = [[UIImage imageNamed:imgNames[indexPath.row]] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    cell.imageView.image = img;
    cell.imageView.tintColor = [UIGlobal standardBlue];
    
    if ([Accounts sharedInstance].quickSwipeType == indexPath.row) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    }
    else {
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    
    cell.selectionStyle = UITableViewCellSelectionStyleGray;
    
    cell.tintColor = [UIGlobal standardBlue];
    
    return cell;
    }
}

#pragma mark Table Delegate

-(CGFloat) tableView:(UITableView*)tableView heightForFooterInSection:(NSInteger)section
{
    return 0;
}

-(CGFloat) tableView:(UITableView*)tableView heightForHeaderInSection:(NSInteger)section
{
    return 0;
}

-(NSIndexPath*) tableView:(UITableView*)tableView willSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
    if (self.table != tableView) {
        [Accounts sharedInstance].quickSwipeType = indexPath.row;
        [self.table reloadData];
        [tableView reloadData];
    }
    
    return nil;
}

-(void) tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

#pragma mark CellDelegate

-(BOOL) isPresentingDrafts
{
    return NO;
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
    
}

-(void) _commonRemoveCell:(NSIndexPath*)ip
{
    
}

-(void) _removeCell:(ConversationTableViewCell*)cell
{
    
}

-(void) leftActionDoneForCell:(ConversationTableViewCell*)cell
{
    
}

-(void) cell:(ConversationTableViewCell*)cell isChangingDuring:(double)timeInterval
{
    
}

-(void) _manageCocoaButton
{
    
}

-(void) cellIsSelected:(ConversationTableViewCell*)cell
{
    
}

-(void) cellIsUnselected:(ConversationTableViewCell*)cell
{
    
}

-(UIPanGestureRecognizer*) tableViewPanGesture
{
    return self.table.panGestureRecognizer;
}

@end

