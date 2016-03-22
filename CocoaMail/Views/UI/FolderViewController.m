//
//  FolderViewController.m
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 14/07/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "FolderViewController.h"
#import "AppSettings.h"
#import "Accounts.h"
#import <ReactiveCocoa/ReactiveCocoa.h>
#import "SyncManager.h"
#import "Mail.h"
#import "ImapSync.h"
#import "StringUtil.h"
#import "UserSettings.h"

@interface FolderViewController () <UITableViewDataSource, UITableViewDelegate>
{
    CRefreshCompletionHandler _completionHandler;
    BOOL _isBackgroundFetching;
}

@property (nonatomic, weak) UITableView* table;

@end

@implementation FolderViewController

-(void) viewDidLoad
{
    [super viewDidLoad];
    
    _isBackgroundFetching = NO;
    
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    
    Account* currentAccount = [[Accounts sharedInstance] currentAccount];
    
    UINavigationItem* item = [[UINavigationItem alloc] initWithTitle:@""];
    
    UIButton* settingsBtn = [WhiteBlurNavBar navBarButtonWithImage:@"settings_off" andHighlighted:@"settings_on"];
    [settingsBtn addTarget:self action:@selector(_settings) forControlEvents:UIControlEventTouchUpInside];
    item.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:settingsBtn];
    
    item.titleView = [WhiteBlurNavBar titleViewForItemTitle:currentAccount.user.username];
    
    UITableView* table = [[UITableView alloc] initWithFrame:CGRectMake(0, 0, screenBounds.size.width, screenBounds.size.height - 20)
                                                      style:UITableViewStyleGrouped];
    
    table.contentInset = UIEdgeInsetsMake(44 - 30, 0, 60, 0);
    table.scrollIndicatorInsets = UIEdgeInsetsMake(44, 0, 0, 0);
    table.backgroundColor = [UIGlobal standardLightGrey];
    
    [self.view addSubview:table];
    
    [self setupNavBarWith:item overMainScrollView:table];
    
    table.dataSource = self;
    table.delegate = self;
    self.table = table;
    
    [self addPullToRefreshWithDelta:0];

    if (currentAccount && !currentAccount.user.isAll) {
        [ImapSync runInboxUnread:currentAccount.user completed:^{  }];
    }
}

-(void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
}

-(void) viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self.table reloadData];
    
    if ([AppSettings numActiveAccounts] ==  0) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kCREATE_FIRST_ACCOUNT_NOTIFICATION object:nil];
    }
    else {
        [ImapSync runInboxUnread:[Accounts sharedInstance].currentAccount.user completed:^{
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [self.table reloadRowsAtIndexPaths:@[[NSIndexPath indexPathForRow:0 inSection:0]] withRowAnimation:UITableViewRowAnimationNone];
            }];
        }];
    }
}

-(NSArray*) nextViewControllerInfos
{
    return @[kPRESENT_SETTINGS_NOTIFICATION, @""];
}

-(void) _settings
{
    [[NSNotificationCenter defaultCenter] postNotificationName:kPRESENT_SETTINGS_NOTIFICATION object:nil];
}

#pragma mark - Table Datasource

-(NSInteger) numberOfSectionsInTableView:(UITableView*)tableView
{
    Account* ac = [[Accounts sharedInstance] currentAccount];
    
    return (ac.userFolders.count>0) ? 2 : 1;
}

-(NSInteger) tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section
{
    Account* ac = [[Accounts sharedInstance] currentAccount];
    
    BOOL showOutBox = [ac outBoxNb] > 0;
    
    return (section==0) ? ([[Accounts sharedInstance].currentAccount systemFolderNames].count - (showOutBox?0:1)) : ac.userFolders.count;
}

-(CGFloat) tableView:(UITableView*)tableView heightForRowAtIndexPath:(NSIndexPath*)indexPath
{
    return (indexPath.row==0) ? 44.5f : 44.0f;
}

-(UITableViewCell*) tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath
{
    UITableViewCell* cell;
    
    NSString* text = @"";
    NSString* imageName = nil;
    
    Account* cac = [[Accounts sharedInstance] currentAccount];
    
    if (indexPath.section == 0) {
        
        UIColor* colorBubble = nil;
        
        NSUInteger count = 0;
        text = [[Accounts sharedInstance].currentAccount systemFolderNames][indexPath.row];
        imageName = [Accounts systemFolderIcons][indexPath.row];
        
        switch (indexPath.row) {
            case 0:
                colorBubble = cac.user.color;
                count = [cac unreadInInbox];
                break;
            case 1:
                colorBubble = [UIColor whiteColor];
                count = [cac favorisCount];
                break;
            case 3:
                colorBubble = [UIGlobal bubbleFolderGrey];
                count = [cac draftCount];
                break;
            case 7:
                colorBubble = [UIGlobal bubbleFolderGrey];
                count = [cac outBoxNb];
                break;
            default:
                break;
        }
        
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"noID"];
        
        if (colorBubble != nil && count>0) {
            
            UILabel* counter = [[UILabel alloc] initWithFrame:CGRectMake(100, (cell.frame.size.height - 23) / 2, 200, 23)];
            counter.backgroundColor = colorBubble;
            counter.text = [NSString stringWithFormat:@"%lu", (unsigned long)count];
            
            
            counter.textColor = [UIColor whiteColor];
            
            if (counter.textColor == counter.backgroundColor) {
                counter.textColor = [UIGlobal bubbleFolderGrey];
            }
            
            counter.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
            counter.layer.cornerRadius = 11.5;
            counter.layer.masksToBounds = YES;
            [counter sizeToFit];
            
            counter.textAlignment = NSTextAlignmentCenter;
            
            CGRect f = counter.frame;
            f.size.width += 14;
            f.size.height = 23;
            f.origin.x = cell.frame.size.width - 16 - f.size.width;
            counter.frame = f;
            
            [cell addSubview:counter];
        }
    }
    else {
        
        imageName = [Accounts userFolderIcon];
        NSArray* subfolder = [cac userFolders][indexPath.row];
        
        NSInteger indentation = [subfolder[1] integerValue];
        
        text = subfolder[0];
        
        NSArray<NSString*>* texts = [text componentsSeparatedByString:@"/"];
        
        text = [texts lastObject];
        
        if (![texts[0] containsString:@"[Gmail]"] && indentation) {
            //NSRange rangeofSub = [text rangeOfString:@"/"];
            //text = [text substringFromIndex:rangeofSub.location + 1];
            imageName = [Accounts userFolderPadIcon];
        }
        else {
            indentation = 0;
        }
        
        NSString* reuseID = @"kCellAccountPerso";
        
        cell = [tableView dequeueReusableCellWithIdentifier:reuseID];
        
        if (cell==nil) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseID];
        }
        
        cell.separatorInset = UIEdgeInsetsMake(0, 53 + 27 * indentation, 0, 0);
    }
    
    cell.textLabel.text = text;
    UIImage* img = [[UIImage imageNamed:imageName] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    cell.imageView.image = img;
    cell.imageView.tintColor = cac.user.color;
    
    cell.selectionStyle = UITableViewCellSelectionStyleGray;
    
    return cell;
}

-(NSString*) tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section
{
    return (section==0) ? nil : NSLocalizedString(@"folder-view.header.user-folders", @"My Folders");
}

#pragma mark Table Delegate

-(CGFloat) tableView:(UITableView*)tableView heightForFooterInSection:(NSInteger)section
{
    return CGFLOAT_MIN;
}

-(CGFloat) tableView:(UITableView*)tableView heightForHeaderInSection:(NSInteger)section
{
    return 30;
}

-(void) tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
    CCMFolderType type;
    
    if (indexPath.section == 0) {
        if (indexPath.row == 7) {
            [[[Accounts sharedInstance] currentAccount] sendOutboxs];
            return;
        }
        type.type = indexPath.row;
        type.idx = 0;
    }
    else {
        type.type = FolderTypeUser;
        type.idx = indexPath.row;
    }
    
    [[[Accounts sharedInstance] currentAccount] setCurrentFolder:type];
    NSNumber* encodedType = @(encodeFolderTypeWith(type));
    [[NSNotificationCenter defaultCenter] postNotificationName:kPRESENT_FOLDER_NOTIFICATION object:nil userInfo:@{kPRESENT_FOLDER_TYPE:encodedType}];
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

#pragma mark - Background SyncWupsWup

-(void) refreshWithCompletionHandler:(CRefreshCompletionHandler)completionHandler
{
    _completionHandler = completionHandler;
    
    BOOL __block hasNewEmail = NO;
    
    NSDate *fetchStart = [NSDate date];
    
    //if (!_isBackgroundFetching) {
        //_isBackgroundFetching = YES;
        [[[[SyncManager getSingleton] syncInboxFoldersBackground] deliverOn:[RACScheduler mainThreadScheduler]]
         subscribeNext:^(Mail* email) {
             hasNewEmail = YES;
         } error:^(NSError* error) {
             NSDate *fetchEnd = [NSDate date];
             NSTimeInterval timeElapsed = [fetchEnd timeIntervalSinceDate:fetchStart];
             NSLog(@"Background Fetch Duration: %f seconds", timeElapsed);
             
             //_isBackgroundFetching = NO;
             _completionHandler(hasNewEmail);
         } completed:^{
             NSDate *fetchEnd = [NSDate date];
             NSTimeInterval timeElapsed = [fetchEnd timeIntervalSinceDate:fetchStart];
             NSLog(@"Background Fetch Duration: %f seconds", timeElapsed);
             
             //_isBackgroundFetching = NO;
             _completionHandler(hasNewEmail);
         }];
    //}
}

- (void)storeChanged:(NSNotification*)notification
{
    /*NSDictionary *userInfo = [notification userInfo];
     NSNumber *reason = [userInfo objectForKey:NSUbiquitousKeyValueStoreChangeReasonKey];
     
     if (reason) {
     NSInteger reasonValue = [reason integerValue];
     NSLog(@"storeChanged with reason %ld", (long)reasonValue);
     
     if ((reasonValue == NSUbiquitousKeyValueStoreServerChange) ||
     (reasonValue == NSUbiquitousKeyValueStoreInitialSyncChange)) {
     
     NSArray *keys = [userInfo objectForKey:NSUbiquitousKeyValueStoreChangedKeysKey];
     NSUbiquitousKeyValueStore *store = [NSUbiquitousKeyValueStore defaultStore];
     NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
     
     for (NSString *key in keys) {
     id value = [store objectForKey:key];
     [userDefaults setObject:value forKey:key];
     NSLog(@"storeChanged updated value for %@",key);
     }
     }
     }*/
}

@end
