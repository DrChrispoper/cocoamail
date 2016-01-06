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
#import "Email.h"
#import "SyncManager.h"
#import "Mail.h"
#import "ImapSync.h"


@interface FolderViewController () <UITableViewDataSource, UITableViewDelegate>
{
    CRefreshCompletionHandler _completionHandler;
    NSMutableSet* _cachedEmailIDs;
    BOOL _isBackgroundFetching;
}

@property (nonatomic, weak) UITableView* table;

@end

@implementation FolderViewController

-(void) viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    _isBackgroundFetching = NO;
    
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    
    Account* currentAccount = [[Accounts sharedInstance] currentAccount];
    
    UINavigationItem* item = [[UINavigationItem alloc] initWithTitle:@""];
    
    UIButton* settingsBtn = [WhiteBlurNavBar navBarButtonWithImage:@"settings_off" andHighlighted:@"settings_on"];
    [settingsBtn addTarget:self action:@selector(_settings) forControlEvents:UIControlEventTouchUpInside];
    item.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:settingsBtn];
    
    item.titleView = [WhiteBlurNavBar titleViewForItemTitle:currentAccount.userMail];

    
    UITableView* table = [[UITableView alloc] initWithFrame:CGRectMake(0,
                                                                       0,
                                                                       screenBounds.size.width,
                                                                       screenBounds.size.height - 20)
                                                      style:UITableViewStyleGrouped];
    table.contentInset = UIEdgeInsetsMake(44 - 30, 0, 60, 0);
    table.scrollIndicatorInsets = UIEdgeInsetsMake(44, 0, 0, 0);
    
    table.backgroundColor = [UIGlobal standardLightGrey];
    
    NSUbiquitousKeyValueStore* store = [NSUbiquitousKeyValueStore
                                        defaultStore];
    if (store) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(storeChanged:)
                                                     name:NSUbiquitousKeyValueStoreDidChangeExternallyNotification
                                                   object:store];
        [store synchronize];
    }
    
    [self.view addSubview:table];
    
    [self setupNavBarWith:item overMainScrollView:table];

    table.dataSource = self;
    table.delegate = self;    
    self.table = table;
    
    _cachedEmailIDs = [[NSMutableSet alloc] initWithCapacity:1];
    
    if (currentAccount && !currentAccount.isAllAccounts) {
        [ImapSync runInboxUnread:currentAccount.idx];
    }
}

-(void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    if ([AppSettings numActiveAccounts] !=  0) {
        [ImapSync runInboxUnread:[Accounts sharedInstance].currentAccountIdx];
    }
}

-(void) viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self.table reloadData];
    
    if ([AppSettings numActiveAccounts] ==  0) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kCREATE_FIRST_ACCOUNT_NOTIFICATION object:nil];
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
    
    return (section==0) ? [[Accounts sharedInstance].currentAccount systemFolderNames].count : ac.userFolders.count;
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
                colorBubble = cac.userColor;
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
        
        if (indentation) {
            NSRange rangeofSub = [text rangeOfString:@"/"];
            text = [text substringFromIndex:rangeofSub.location + 1];
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
    cell.imageView.tintColor = cac.userColor;
    
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
    
    if (!_isBackgroundFetching) {
        _isBackgroundFetching = YES;
    [[[[SyncManager getSingleton] syncInboxFoldersBackground] deliverOn:[RACScheduler mainThreadScheduler]]
     subscribeNext:^(Email* email) {
        if (![_cachedEmailIDs containsObject:email.msgId]) {
            hasNewEmail = YES;
            CCMLog(@"Adding emails in cache: %@", email.subject);

            [_cachedEmailIDs addObject:email.msgId];
            
            Conversation* conv = [[Conversation alloc] init];
            [conv addMail:[Mail mail:email]];
            NSUInteger index = [[[Accounts sharedInstance] getAccount:[AppSettings indexForAccount:email.accountNum]] addConversation:conv];
            
            BOOL isUnread = !(email.flag & MCOMessageFlagSeen);
            
            if (isUnread && [AppSettings notifications]) {
                UILocalNotification* localNotification = [[UILocalNotification alloc] init];
                localNotification.fireDate = [NSDate dateWithTimeIntervalSinceNow:10];
                NSString* alertText = [[NSString alloc]initWithFormat:@"%@\n%@%@", email.sender.displayName, (email.hasAttachments?@"📎 ":@""), email.subject];
                localNotification.alertBody = alertText;
                localNotification.timeZone = [NSTimeZone defaultTimeZone];
                localNotification.userInfo = @{@"index":@(index),
                                               @"accountNum":@(email.accountNum)};
                localNotification.category = @"MAIL_CATEGORY";
                
                [[UIApplication sharedApplication] scheduleLocalNotification:localNotification];
            }
        }
    } error:^(NSError* error) {
        _isBackgroundFetching = NO;
        _completionHandler(hasNewEmail);
    } completed:^{
        _isBackgroundFetching = NO;
        _completionHandler(hasNewEmail);
    }];
    }
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
