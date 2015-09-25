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

@interface FolderViewController () <UITableViewDataSource, UITableViewDelegate>
{
    CRefreshCompletionHandler _completionHandler;
    NSMutableSet *_cachedEmailIDs;
}

@property (nonatomic, weak) UITableView* table;

@end

@implementation FolderViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
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
                                                                       screenBounds.size.height-20)
                                                      style:UITableViewStyleGrouped];
    table.contentInset = UIEdgeInsetsMake(44-30, 0, 60, 0);
    table.scrollIndicatorInsets = UIEdgeInsetsMake(44, 0, 0, 0);
    
    table.backgroundColor = [UIGlobal standardLightGrey];
    
    [self.view addSubview:table];
    
    [self setupNavBarWith:item overMainScrollView:table];

    table.dataSource = self;
    table.delegate = self;    
    self.table = table;
    
    _cachedEmailIDs = [[NSMutableSet alloc] initWithCapacity:1];
    
    [self addPullToRefreshWithDelta:30];
}


-(void) viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    [self.table reloadData];
    
    [[Accounts sharedInstance].currentAccount setCurrentFolder:FolderTypeWith(FolderTypeAll, 0)];
    
    if([Accounts sharedInstance].accountsCount ==  1){
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


-(NSInteger) numberOfSectionsInTableView:(UITableView *)tableView
{
    Account* ac = [[Accounts sharedInstance] currentAccount];
    
    return (ac.userFolders.count>0) ? 2 : 1;
}

-(NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    Account* ac = [[Accounts sharedInstance] currentAccount];
    
    return (section==0) ? [[Accounts sharedInstance].currentAccount systemFolderNames].count : ac.userFolders.count;
}

-(CGFloat) tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return (indexPath.row==0) ? 44.5f : 44.0f;
}

-(UITableViewCell*) tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
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
                count = 0;//TODO:[cac unreadInInbox];
                break;
            case 1:
                colorBubble = [UIColor whiteColor];
                count = 0;//TODO:[cac getConversationsForFolder:FolderTypeWith(1, 0)].count;
                break;
            case 3:
                colorBubble = [UIGlobal bubbleFolderGrey];
                count = 0;//TODO:[cac getConversationsForFolder:FolderTypeWith(3, 0)].count;
                break;
            default:
                break;
        }
        
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"noID"];
        
        if (colorBubble != nil && count>0) {
            
            UILabel* counter = [[UILabel alloc] initWithFrame:CGRectMake(100, (cell.frame.size.height-23)/2, 200, 23)];
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
            NSRange rangeofSub = [text rangeOfString:@"]/"];
            text = [text substringFromIndex:rangeofSub.location+2];
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

-(NSString*)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return (section==0) ? nil : @"My Folders";
}


#pragma mark Table Delegate

-(CGFloat) tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{
    return CGFLOAT_MIN;
}

-(CGFloat) tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    return 30;
}

-(void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    FolderType type;
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

- (void)refreshWithCompletionHandler:(CRefreshCompletionHandler)completionHandler
{
    _completionHandler = completionHandler;
    
    BOOL __block hasNewEmail = NO;
    [[[[SyncManager getSingleton] syncInboxFoldersBackground] deliverOn:[RACScheduler mainThreadScheduler]]
     subscribeNext:^(Email *email) {
        if (![_cachedEmailIDs containsObject:email.msgId])
        {
            hasNewEmail = YES;
            CCMLog(@"Adding emails in cache: %@",email.subject);

            [_cachedEmailIDs addObject:email.msgId];
            
            Conversation* conv = [[Conversation alloc] init];
            [conv addMail:[Mail mail:email]];
            [[[Accounts sharedInstance] getAccount:[AppSettings numIndexForAccount:[email account]]] addConversation:conv];
        }
    } error:^(NSError *error) {
        _completionHandler(hasNewEmail);
    } completed:^{
        _completionHandler(hasNewEmail);
    }];
}

@end
