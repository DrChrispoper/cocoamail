//
//  QuickSwipeViewController.m
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 04/09/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "QuickSwipeViewController.h"

#import "Accounts.h"

@interface QuickSwipeViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, weak) UITableView* table;

@end


@implementation QuickSwipeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    
    UINavigationItem* item = [[UINavigationItem alloc] initWithTitle:@""];
    
    item.leftBarButtonItem = [self backButtonInNavBar];
    
    NSString* title = NSLocalizedString(@"Quick swipe", @"Quick swipe");
    item.titleView = [WhiteBlurNavBar titleViewForItemTitle:title];
    
    UITableView* table = [[UITableView alloc] initWithFrame:CGRectMake(0,
                                                                       0,
                                                                       screenBounds.size.width,
                                                                       screenBounds.size.height-20)
                                                      style:UITableViewStyleGrouped];
    table.contentInset = UIEdgeInsetsMake(44, 0, 60, 0);
    table.scrollIndicatorInsets = UIEdgeInsetsMake(44, 0, 0, 0);
    
    table.backgroundColor = [UIGlobal standardLightGrey];
    
    [self.view addSubview:table];
    
    [self setupNavBarWith:item overMainScrollView:table];
    
    table.dataSource = self;
    table.delegate = self;
    self.table = table;
    
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


-(NSInteger) numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

-(NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return 4;
}

-(CGFloat) tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return (indexPath.row==0) ? 52.5f : 52.0f;
}


-(UITableViewCell*) tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell* cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"noID"];
    
    
    NSArray* names = @[NSLocalizedString(@"Archive", @"Archive"),
                       NSLocalizedString(@"Delete",@"Delete"),
                       NSLocalizedString(@"Reply",@"Reply"),
                       NSLocalizedString(@"Mark as read/unread",@"Mark as read/unread")];
    
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


#pragma mark Table Delegate

-(CGFloat) tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{
    return 20;
}

-(CGFloat) tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    return 52;
}

-(NSIndexPath*) tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [Accounts sharedInstance].quickSwipeType = indexPath.row;
    [tableView reloadData];
    
    return nil;
}

-(void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end

