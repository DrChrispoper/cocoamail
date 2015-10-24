//
//  SettingsViewController.m
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 17/08/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "SettingsViewController.h"

#import "Accounts.h"


@interface SettingsViewController () <UITableViewDataSource, UITableViewDelegate>

@property (nonatomic, weak) UITableView* table;

@property (nonatomic, strong) NSArray* settings;

@property (nonatomic, weak) UISwitch* badgeSwitch;

@end

@implementation SettingsViewController

-(void) viewDidLoad
{
    [super viewDidLoad];
    
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    
    UINavigationItem* item = [[UINavigationItem alloc] initWithTitle:@""];

    item.leftBarButtonItem = [self backButtonInNavBar];
    
    NSString* title = NSLocalizedString(@"Settings", @"Settings");
    item.titleView = [WhiteBlurNavBar titleViewForItemTitle:title];
    
    UITableView* table = [[UITableView alloc] initWithFrame:CGRectMake(0,
                                                                       0,
                                                                       screenBounds.size.width,
                                                                       screenBounds.size.height - 20)
                                                      style:UITableViewStyleGrouped];
    table.contentInset = UIEdgeInsetsMake(44, 0, 60, 0);
    table.scrollIndicatorInsets = UIEdgeInsetsMake(44, 0, 0, 0);
    
    table.backgroundColor = [UIGlobal standardLightGrey];
    
    [self.view addSubview:table];
    
    [self setupNavBarWith:item overMainScrollView:table];

//    [self _prepareTable];
    table.dataSource = self;
    table.delegate = self;    
    self.table = table;

}

-(BOOL) haveCocoaButton
{
    return NO;
}

#define TITLE @"title"
#define FOOTER @"footer"
#define CONTENT @"content"

#define BVIEW @"bv"
#define TEXT @"t"
#define ACTION @"a"
#define OBJECT @"o"
#define DACTION @"da"
#define BIMAGE @"bi"

-(void) _prepareTable
{
    NSArray* accounts = [[Accounts sharedInstance] accounts];
    NSMutableArray* as = [NSMutableArray arrayWithCapacity:accounts.count];
    NSMutableArray* da = [NSMutableArray arrayWithCapacity:1];

    NSInteger idx = -1;
    
    for (Account* a in accounts) {
        idx++;
        
        if ([a isAllAccounts]) {
            continue;
        }
        
        [as addObject:@{BVIEW: [a.person badgeView], TEXT : a.userMail, ACTION : kSETTINGS_ACCOUNT_NOTIFICATION, OBJECT:a}];
        
        if (idx == [Accounts sharedInstance].defaultAccountIdx) {
            [da addObject:@{BVIEW: [a.person badgeView], TEXT : a.userMail, ACTION : kSETTINGS_MAIN_ACCOUNT_NOTIFICATION}];
        }
        
    }
    
    if (as.count<5) {
        NSString* addAccount = NSLocalizedString(@"Add account", @"Add account");
        [as addObject:@{BVIEW : [[UIView alloc] init], TEXT : addAccount, ACTION : kSETTINGS_ADD_ACCOUNT_NOTIFICATION}];
    }
    
    NSString* tAccount = NSLocalizedString(@"ACCOUNTS", @"ACCOUNTS");
    NSDictionary* Paccounts = @{TITLE:tAccount, FOOTER:@"", CONTENT:as};
    
    NSString* tDAccount = NSLocalizedString(@"DEFAULT ACCOUNT", @"DEFAULT ACCOUNT");
    NSString* fDAccount = NSLocalizedString(@"Default account used to send emails when using unified Inbox", @"Default account used to send emails when using unified Inbox");
    NSDictionary* PdftAccount = @{TITLE:tDAccount, FOOTER:fDAccount, CONTENT:da};
    
    NSArray* clouds = @[
                        @{BIMAGE:@"icone_dropbox", TEXT: @"Dropbox", ACTION : kSETTINGS_CLOUD_NOTIFICATION, OBJECT: @"Dropbox"},
                        //@{BIMAGE:@"icone_icloud", TEXT: @"iCloud", ACTION : kSETTINGS_CLOUD_NOTIFICATION, OBJECT: @"iCloud"},
                        //@{BIMAGE:@"icone_google", TEXT: @"Google Drive", ACTION : kSETTINGS_CLOUD_NOTIFICATION, OBJECT: @"Google Drive"},
                        //@{BIMAGE:@"icone_box", TEXT: @"Box", ACTION : kSETTINGS_CLOUD_NOTIFICATION, OBJECT: @"Box"}
                        ];
    
    NSString* tCloud = NSLocalizedString(@"CLOUD SERVICES", @"CLOUD SERVICES");
    NSDictionary* Pclouds = @{TITLE:tCloud, FOOTER:@"", CONTENT:clouds};
    
    NSString* tNotif = NSLocalizedString(@"Notifications", @"Notifications");
    NSString* tBadge = NSLocalizedString(@"Display badge count", @"Display badge count");
    NSString* tSwipe = NSLocalizedString(@"Quick Swipe", @"Quick Swipe");
    
    NSArray* displays = @[
                          @{TEXT: tSwipe, ACTION : kSETTINGS_SWIPE_NOTIFICATION},
                          @{TEXT: tBadge, DACTION : @"BADGE_COUNT"},
                          @{TEXT: tNotif, ACTION : kSETTINGS_NOTIF_NOTIFICATION}
                        ];
    
    NSString* tDisplay = NSLocalizedString(@"DISPLAY", @"DISPLAY");
    NSDictionary* Pdisplay = @{TITLE:tDisplay, FOOTER:@"", CONTENT:displays};

    NSString* tCredit = NSLocalizedString(@"Credits", @"Credits");
    NSDictionary* Pcredit = @{TITLE:@"", FOOTER:@"",
                              CONTENT:@[@{TEXT:tCredit, ACTION:kSETTINGS_CREDIT_NOTIFICATION}]
                              };
    
    NSString* tDelete = NSLocalizedString(@"Delete stored attachments", @"Delete stored attachments");
    NSDictionary* PDelete = @{TITLE:@"", FOOTER:@"",
                              CONTENT:@[@{TEXT:tDelete, DACTION : @"CLEAR"}]
                              };
    
    /*NSDictionary* PNavbar = @{TITLE:@"", FOOTER:@"",
                              CONTENT:@[@{TEXT:@"Blurred nav bar", DACTION : @"NAV_BAR_BLUR"},
                                        @{TEXT:@"Opaque nav bar", DACTION : @"NAV_BAR_SOLID"}]
                              };
    */
    self.settings = @[Paccounts, PdftAccount, Pclouds, Pdisplay, Pcredit, PDelete/*, PNavbar*/];
    
}

-(void) cleanBeforeGoingBack
{
    self.table.delegate = nil;
    self.table.dataSource = nil;
}

-(void) viewWillAppear:(BOOL)animated
{
    [self _prepareTable];
    [self.table reloadData];
}

#pragma mark - Table Datasource

-(NSInteger) numberOfSectionsInTableView:(UITableView*)tableView
{
    return self.settings.count;
}

-(NSInteger) tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section
{
    NSDictionary* sectionInfos = self.settings[section];
    NSArray* content = sectionInfos[CONTENT];
    
    return content.count;
}

-(CGFloat) tableView:(UITableView*)tableView heightForRowAtIndexPath:(NSIndexPath*)indexPath
{
    return (indexPath.row==0) ? 52.5f : 52.0f;
}

-(UITableViewCell*) tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath
{
    NSDictionary* sectionInfos = self.settings[indexPath.section];
    NSArray* content = sectionInfos[CONTENT];
    NSDictionary* infoCell = content[indexPath.row];
    
    
    UITableViewCell* cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"noID"];
    
    cell.textLabel.text = infoCell[TEXT];

    if ([infoCell objectForKey:BVIEW] != nil) {
        UIView* v = infoCell[BVIEW];
    
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(33.f, 33.f), NO, [UIScreen mainScreen].scale);
        UIImage* img = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
    
        cell.imageView.image = img;
        [cell.imageView addSubview:v];
    }
    else {
        NSArray* alls = cell.imageView.subviews;
        
        for (UIView* v in alls) {
            [v removeFromSuperview];
        }
        
        NSString* imgName = infoCell[BIMAGE];
        
        cell.imageView.image = (imgName.length>0) ? [UIImage imageNamed:imgName] : nil;
    }
    
    cell.textLabel.textAlignment = NSTextAlignmentNatural;
    cell.textLabel.textColor = [UIColor blackColor];
    
    if (infoCell[DACTION]!=nil) {

        NSString* action = infoCell[DACTION];
        
        cell.accessoryView = nil;
        
        if ([action isEqualToString:@"BADGE_COUNT"]) {
            UISwitch* s = [[UISwitch alloc] init];
            s.onTintColor = [UIGlobal standardBlue];
            [s addTarget:self action:@selector(_switchBadge:) forControlEvents:UIControlEventValueChanged];
            cell.accessoryView = s;
            [s setOn:[AppSettings badgeCount]];
            self.badgeSwitch = s;
        }
        else if ([action isEqualToString:@"NAV_BAR_BLUR"]) {
            cell.accessoryType = ([Accounts sharedInstance].navBarBlurred) ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
        }
        else if ([action isEqualToString:@"NAV_BAR_SOLID"]) {
            cell.accessoryType = ([Accounts sharedInstance].navBarBlurred) ? UITableViewCellAccessoryNone : UITableViewCellAccessoryCheckmark;
        }
        else if ([action isEqualToString:@"CLEAR"]) {
            cell.accessoryType = UITableViewCellAccessoryNone;
            
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.textLabel.textColor = [UIGlobal standardBlue];
            
        }
        
    }
    else if (infoCell[ACTION]!=nil) {
        cell.accessoryView = nil;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    
    cell.selectionStyle = UITableViewCellSelectionStyleGray;
    
    return cell;
}

-(NSString*) tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section
{
    NSDictionary* sectionInfos = self.settings[section];
    
    return sectionInfos[TITLE];
}

-(NSString*) tableView:(UITableView*)tableView titleForFooterInSection:(NSInteger)section
{
    NSDictionary* sectionInfos = self.settings[section];
    
    return sectionInfos[FOOTER];
}

#pragma mark Table Delegate

-(CGFloat) tableView:(UITableView*)tableView heightForFooterInSection:(NSInteger)section
{
    NSDictionary* sectionInfos = self.settings[section];
    NSString* info = sectionInfos[FOOTER];
    
    return (info.length>0) ? 46 :CGFLOAT_MIN;
}

-(CGFloat) tableView:(UITableView*)tableView heightForHeaderInSection:(NSInteger)section
{
    return 52;
}

-(NSIndexPath*) tableView:(UITableView*)tableView willSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
    NSDictionary* sectionInfos = self.settings[indexPath.section];
    NSArray* content = sectionInfos[CONTENT];
    NSDictionary* infoCell = content[indexPath.row];
    
    NSString* directAction = infoCell[DACTION];

    if (directAction.length>0) {
        
        NSArray* reload = nil;
        
        if ([directAction isEqualToString:@"BADGE_COUNT"]) {
            [self.badgeSwitch setOn:!self.badgeSwitch.on animated:YES];
            [self _switchBadge:self.badgeSwitch];
        }
        else if ([directAction isEqualToString:@"NAV_BAR_BLUR"]) {
            [Accounts sharedInstance].navBarBlurred = YES;
            
            reload = @[indexPath, [NSIndexPath indexPathForRow:indexPath.row + 1 inSection:indexPath.section]];
        }
        else if ([directAction isEqualToString:@"NAV_BAR_SOLID"]) {
            [Accounts sharedInstance].navBarBlurred = NO;
            reload = @[indexPath, [NSIndexPath indexPathForRow:indexPath.row - 1 inSection:indexPath.section]];
        }
        else if ([directAction isEqualToString:@"CLEAR"]) {
            [ViewController presentAlertWIP:@"clear attachments…"];
        }
        
        if (reload.count > 0) {
            [tableView reloadRowsAtIndexPaths:reload withRowAnimation:UITableViewRowAnimationNone];
        }
    
        return nil;
    }
    
    NSString* action = infoCell[ACTION];
    
    if (action.length>0) {
        
        id object = infoCell[OBJECT];
        
        if (object != nil) {
            [[NSNotificationCenter defaultCenter] postNotificationName:action object:nil userInfo:@{kSETTINGS_KEY:object}];
        } else {
            [[NSNotificationCenter defaultCenter] postNotificationName:action object:nil userInfo:nil];
        }
        
        return nil;
    }
    
    return nil;
}

-(void) tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

-(void) _switchBadge:(UISwitch*)sender
{
    [AppSettings setBadgeCount:![AppSettings badgeCount]];
}

@end
