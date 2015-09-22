//
//  DefaultAccountViewController.m
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 04/09/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "DefaultAccountViewController.h"

#import "Accounts.h"

@interface DefaultAccountViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, weak) UITableView* table;

@end


@implementation DefaultAccountViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    
    UINavigationItem* item = [[UINavigationItem alloc] initWithTitle:@""];
    
    item.leftBarButtonItem = [self backButtonInNavBar];
    
    NSString* title = NSLocalizedString(@"Default account", @"Default account");
    item.titleView = [WhiteBlurNavBar titleViewForItemTitle:title];
    
    UITableView* table = [[UITableView alloc] initWithFrame:CGRectMake(0,
                                                                       0,
                                                                       screenBounds.size.width,
                                                                       screenBounds.size.height-20)
                                                      style:UITableViewStyleGrouped];
    table.contentInset = UIEdgeInsetsMake(44, 0, 0, 0);
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
    return [Accounts sharedInstance].accounts.count - 1;
}

-(CGFloat) tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return (indexPath.row==0) ? 52.5f : 52.0f;
}


-(UITableViewCell*) tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    Account* a = [Accounts sharedInstance].accounts[indexPath.row];
    
    UITableViewCell* cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"noID"];
    
    
    cell.textLabel.text = a.userMail;
    
    
    UIView* v = [a.person badgeView];
    
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(33.f, 33.f), NO, [UIScreen mainScreen].scale);
    UIImage* img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    cell.imageView.image = img;
    [cell.imageView addSubview:v];
    
    
    cell.textLabel.textAlignment = NSTextAlignmentNatural;
    cell.textLabel.textColor = [UIColor blackColor];
    

    if ([Accounts sharedInstance].defaultAccountIdx == indexPath.row) {
        cell.accessoryType = UITableViewCellAccessoryCheckmark;
    }
    else {
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    
    cell.selectionStyle = UITableViewCellSelectionStyleGray;
    
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
    [Accounts sharedInstance].defaultAccountIdx = indexPath.row;
    [tableView reloadData];
    
    return nil;
}

-(void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}



@end
