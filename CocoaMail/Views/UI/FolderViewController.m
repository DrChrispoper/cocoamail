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

#define kIMPORTANT_FOLDERS_SECTION    0
#define kUSER_FOLDERS_SECTION         1

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
        [ImapSync getInboxUnreadCountForUser:currentAccount.user completed:^{  }];
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
        [ImapSync getInboxUnreadCountForUser:[Accounts sharedInstance].currentAccount.user completed:^{
            [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                [self.table reloadData];
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
    
    NSInteger numberOfSections = 1;     // The Important Folders
    
    BOOL haveUserFolders = (ac.userFolders.count > 0);
    
    if ( haveUserFolders ) {
        numberOfSections+=1;    // Add one section for the user folders
    }
    
    return numberOfSections;
}

-(NSInteger) tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section
{
    Account* curAccount = [[Accounts sharedInstance] currentAccount];
    
    NSInteger numberOfRows = 0;
    
    if (section==kIMPORTANT_FOLDERS_SECTION) {

        numberOfRows = curAccount.systemFolderNames.count;
        
        BOOL showOutBox = [curAccount outBoxNb] > 0;
        if ( !showOutBox ) {
            numberOfRows -= 1;
        }
    }
    else { // User Folders Section
        
        numberOfRows = curAccount.userFolders.count;
    }
    return numberOfRows;
}

-(CGFloat) tableView:(UITableView*)tableView heightForRowAtIndexPath:(NSIndexPath*)indexPath
{
    return (indexPath.row==0) ? 44.5f : 44.0f;
}

-(UITableViewCell*) tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath
{
    UITableViewCell* cell;
    
    NSString* folderName = @"";
    NSString* imageName = nil;
    
    Account* currentAcnt = [[Accounts sharedInstance] currentAccount];
    
    if (indexPath.section == kIMPORTANT_FOLDERS_SECTION) { // This is the first section (ie. Important folders)
        
        UIColor* colorBubble = nil;
        
        NSUInteger count = 0;
        NSArray *systemFolderNames = [[Accounts sharedInstance].currentAccount systemFolderNames];
        folderName = (NSString*)systemFolderNames[(NSUInteger) indexPath.row];
        
        NSArray *sysFolderIcons = [Accounts systemFolderIcons];
        imageName = sysFolderIcons[(NSUInteger) indexPath.row];
        
        switch (indexPath.row) {
            case 0: // INBOX folder
                colorBubble = currentAcnt.user.color;
                count = [currentAcnt unreadInInbox];
                break;
            case 1: // FLAGGED folder
                colorBubble = [UIColor whiteColor];
                count = [currentAcnt favorisCount];
                break;
            case 3: // DRAFTS folder
                colorBubble = [UIGlobal bubbleFolderGrey];
                count = [currentAcnt draftCount];
                break;
            case 7: // OUTBOX folder
                colorBubble = [UIGlobal bubbleFolderGrey];
                count = [currentAcnt outBoxNb];
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
    else { // User Folders Section
        
        NSUInteger folderNumber = (NSUInteger)indexPath.row;
        
        BOOL indentation = [currentAcnt userFolderAtIndexContainsPathDelimiter:folderNumber];
        
        NSString *fullPathFolderName = [currentAcnt userFolderNameAtIndex:folderNumber];
        
        NSString *delimiter = currentAcnt.user.folderPathDelimiter;
        DDAssert(delimiter, @"There must be a folder path delimiter");
        DDAssert(delimiter.length, @"The folder path delimiter must have a length");
        
        NSArray<NSString*>* folderPathComponents = [fullPathFolderName componentsSeparatedByString:delimiter];
        
        folderName = [folderPathComponents lastObject];
        
        if ( ![folderPathComponents[0] containsString:@"[Gmail]"] && indentation) {
            //NSRange rangeofSub = [text rangeOfString:@"/"];
            //text = [text substringFromIndex:rangeofSub.location + 1];
            
            imageName = [Accounts userFolderPadIcon];   // Not Google Mail
        }
        else {
            // Is Google Mail and includes a path delimiter
            
            imageName = [Accounts userFolderIcon];

            indentation = FALSE;;
        }
        
        NSString* reuseID = @"kCellAccountPerso";
        
        cell = [tableView dequeueReusableCellWithIdentifier:reuseID];
        
        if (cell==nil) {
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseID];
        }
        
        cell.separatorInset = UIEdgeInsetsMake(0, 53 + 27 * indentation, 0, 0);
    }
    
    DDLogDebug(@"\t FolderViewController TableCell = \"%@\"",folderName);
    
    cell.textLabel.text = folderName;
    UIImage* img = [[UIImage imageNamed:imageName] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    cell.imageView.image = img;
    cell.imageView.tintColor = currentAcnt.user.color;
    
    cell.selectionStyle = UITableViewCellSelectionStyleGray;
    
    return cell;
}

-(NSString*) tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section
{
    NSString *sectionTitle = nil;
    
    if ( section > kIMPORTANT_FOLDERS_SECTION ) { // User Folders Section
        sectionTitle = NSLocalizedString(@"folder-view.header.user-folders", @"My Folders");
    }
    return sectionTitle;
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
    CCMFolderType folderType;
    
    if (indexPath.section == kIMPORTANT_FOLDERS_SECTION) {
        if (indexPath.row == 7) {
            [[[Accounts sharedInstance] currentAccount] sendOutboxs];
            [tableView deselectRowAtIndexPath:indexPath animated:YES];
            return;
        }
        folderType.type = indexPath.row;
        folderType.idx = 0;
    }
    else {
        folderType.type = FolderTypeUser;
        folderType.idx = indexPath.row;
    }
    
    [[[Accounts sharedInstance] currentAccount] setCurrentFolder:folderType];
    NSNumber* encodedType = @(encodeFolderTypeWith(folderType));
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
             DDLogInfo(@"subscribeNext received for syncInboxFoldersBackground");

             hasNewEmail = YES;
         } error:^(NSError* error) {
             NSDate *fetchEnd = [NSDate date];
             NSTimeInterval timeElapsed = [fetchEnd timeIntervalSinceDate:fetchStart];
             DDLogDebug(@"Background Fetch Duration: %f seconds", timeElapsed);
             
             //_isBackgroundFetching = NO;
             self->_completionHandler(hasNewEmail);
         } completed:^{
             NSDate *fetchEnd = [NSDate date];
             NSTimeInterval timeElapsed = [fetchEnd timeIntervalSinceDate:fetchStart];
             DDLogDebug(@"Background Fetch Duration: %f seconds", timeElapsed);
             
             //_isBackgroundFetching = NO;
             self->_completionHandler(hasNewEmail);
         }];
    //}
}

- (void)storeChanged:(NSNotification*)notification
{
    /*NSDictionary *userInfo = [notification userInfo];
     NSNumber *reason = [userInfo objectForKey:NSUbiquitousKeyValueStoreChangeReasonKey];
     
     if (reason) {
     NSInteger reasonValue = [reason integerValue];
     DDLogDebug(@"storeChanged with reason %ld", (long)reasonValue);
     
     if ((reasonValue == NSUbiquitousKeyValueStoreServerChange) ||
     (reasonValue == NSUbiquitousKeyValueStoreInitialSyncChange)) {
     
     NSArray *keys = [userInfo objectForKey:NSUbiquitousKeyValueStoreChangedKeysKey];
     NSUbiquitousKeyValueStore *store = [NSUbiquitousKeyValueStore defaultStore];
     NSUserDefaults *userDefaults = [NSUserDefaults standardUserDefaults];
     
     for (NSString *key in keys) {
     id value = [store objectForKey:key];
     [userDefaults setObject:value forKey:key];
     DDLogDebug(@"storeChanged updated value for %@",key);
     }
     }
     }*/
}

@end
