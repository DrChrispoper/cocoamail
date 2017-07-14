//
//  UserFolderViewController.m
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 08/09/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "UserFolderViewController.h"
#import "UserSettings.h"

@interface UserFolderViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, weak) UITableView* table;

@end

@implementation UserFolderViewController

-(void) viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    
    UINavigationItem* item = [[UINavigationItem alloc] initWithTitle:@""];
    
    UIButton* back = [WhiteBlurNavBar navBarButtonWithImage:@"editmail_cancel_off" andHighlighted:@"editmail_cancel_on"];
    [back addTarget:self action:@selector(_back) forControlEvents:UIControlEventTouchUpInside];
    item.leftBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:back];
    
    item.titleView = [WhiteBlurNavBar titleViewForItemTitle:NSLocalizedString(@"move-email-to-folder-view.title", @"My Folders")];
    
    
    UITableView* table = [[UITableView alloc] initWithFrame:CGRectMake(0,
                                                                       0,
                                                                       screenBounds.size.width,
                                                                       screenBounds.size.height - 20)
                                                      style:UITableViewStyleGrouped];
    table.contentInset = UIEdgeInsetsMake(44 - 30, 0, 60, 0);
    table.scrollIndicatorInsets = UIEdgeInsetsMake(44, 0, 0, 0);
    
    table.backgroundColor = [UIGlobal standardLightGrey];
    
    [self.view addSubview:table];
    
    [self setupNavBarWith:item overMainScrollView:table];
    
    table.dataSource = self;
    table.delegate = self;
    self.table = table;
}

-(void) _back
{
    [self.delegate chooseUserFolderCancel];
}

#pragma mark - Table Datasource

-(NSInteger) numberOfSectionsInTableView:(UITableView*)tableView
{
    return 1;
}

-(NSInteger) tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section
{
    Account* ac = [[Accounts sharedInstance] currentAccount];
    
    return (NSInteger)ac.userFolders.count;
}

-(CGFloat) tableView:(UITableView*)tableView heightForRowAtIndexPath:(NSIndexPath*)indexPath
{
    return (indexPath.row==0) ? 44.5f : 44.0f;
}

-(UITableViewCell*) tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath
{
    NSString* imageName = [Accounts userFolderIcon];
    
    Account* cac = [[Accounts sharedInstance] currentAccount];
    
    NSUInteger folderIndex = (NSUInteger)indexPath.row;
    NSString* text = [cac userFolderNameAtIndex:folderIndex];
    BOOL indentation = [cac userFolderAtIndexContainsPathDelimiter:folderIndex];
    
    NSString* reuseID = @"kCellAccountPerso";
    
    UITableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:reuseID];
    
    if (cell==nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseID];
    }
    
    cell.separatorInset = UIEdgeInsetsMake(0, 53 + 27 * indentation, 0, 0);
    
    cell.textLabel.text = text;
    UIImage* img = [[UIImage imageNamed:imageName] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    cell.imageView.image = img;
    cell.imageView.tintColor = cac.user.color;
    
    cell.selectionStyle = UITableViewCellSelectionStyleGray;
    
    return cell;
}

#pragma mark Table Delegate

-(CGFloat) tableView:(UITableView*)tableView heightForFooterInSection:(NSInteger)section
{
    return CGFLOAT_MIN;
}

-(CGFloat) tableView:(UITableView*)tableView heightForHeaderInSection:(NSInteger)section
{
    return 50;
}

-(void) tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
    CCMFolderType type = FolderTypeWith(FolderTypeUser, indexPath.row);
    [self.delegate chooseUserFolder:type];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

@end

