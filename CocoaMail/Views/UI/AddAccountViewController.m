//
//  AddAccountViewController.m
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 05/09/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "AddAccountViewController.h"

#import "Accounts.h"
#import "EditCocoaButtonView.h"

#import <MailCore/MailCore.h>
#import <Google/SignIn.h>

#import "SyncManager.h"
#import "AppSettings.h"
#import "Reachability.h"
#import "GlobalDBFunctions.h"
#import "ImapSync.h"
#import "CocoaMail-Swift.h"


@interface AddAccountViewController ()

@property (nonatomic, strong) Account* account;
@property (nonatomic, strong) MCOAccountValidator* accountVal;


@end


@interface AddAccountViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate,GIDSignInUIDelegate>

@property (nonatomic, weak) UITableView* table;
@property (nonatomic, strong) NSArray* settings;

@property (nonatomic, weak) UITextField* username;
@property (nonatomic, weak) UITextField* email;
@property (nonatomic, weak) UITextField* password;

@property (nonatomic, weak) EditCocoaButtonView* editCocoa;
@property (nonatomic) NSInteger step;

@property (nonatomic, weak) UIButton* googleBtn;


@end

@implementation AddAccountViewController

-(void) viewDidLoad
{
    [super viewDidLoad];
    
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    
    UINavigationItem* item = [[UINavigationItem alloc] initWithTitle:@""];
    
    if (self.firstRunMode == NO) {
        item.leftBarButtonItem = [self backButtonInNavBar];
    }
    
    [[NSNotificationCenter defaultCenter]
     addObserver:self
     selector:@selector(receiveToggleAuthUINotification:)
     name:@"ToggleAuthUINotification"
     object:nil];
    
    [GIDSignIn sharedInstance].uiDelegate = self;
    
    NSString* title = NSLocalizedString(@"add-account-view.title", @"Add account View Title");
    item.titleView = [WhiteBlurNavBar titleViewForItemTitle:title];
    
    UITableView* table = [[UITableView alloc] initWithFrame:CGRectMake(0,
                                                                       0,
                                                                       screenBounds.size.width,
                                                                       242/*screenBounds.size.height-20*/)
                                                      style:UITableViewStyleGrouped];
    table.contentInset = UIEdgeInsetsMake(44, 0, 60, 0);
    table.scrollIndicatorInsets = UIEdgeInsetsMake(44, 0, 0, 0);
    
    table.backgroundColor = [UIGlobal standardLightGrey];
    self.view.backgroundColor = [UIGlobal standardLightGrey];
    
    [self.view addSubview:table];
    
    [self setupNavBarWith:item overMainScrollView:table];
    
    [self _prepareTable];
    
    table.scrollEnabled = NO;
    
    table.dataSource = self;
    table.delegate = self;
    self.table = table;
    
    UIImageView* cocoa = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"cocoamail"]];
    
    CGFloat posYbutton = screenBounds.size.height - 20 - (70 + 45);
    cocoa.frame = CGRectMake(0, 242, screenBounds.size.width, posYbutton + 35 - 242);
    cocoa.contentMode = UIViewContentModeCenter;
    
    [self.view addSubview:cocoa];
    
    UITapGestureRecognizer* tgr = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_tap:)];
    [cocoa addGestureRecognizer:tgr];
    cocoa.userInteractionEnabled = YES;
    
    UIButton* google = [[UIButton alloc] initWithFrame:CGRectMake(0, posYbutton, screenBounds.size.width, 70 + 45)];
    [google setImage:[UIImage imageNamed:@"signGoogle_on"] forState:UIControlStateNormal];
    [google setImage:[UIImage imageNamed:@"signGoogle_off"] forState:UIControlStateHighlighted];
    [google addTarget:self action:@selector(_google:) forControlEvents:UIControlEventTouchUpInside];
    
    [self.view addSubview:google];
    
    for (Account* a in [Accounts sharedInstance].accounts) {
        if (!a.isAllAccounts && [AppSettings isUsingOAuth:a.idx]) {
            google.hidden = YES;
        }
    }
    self.googleBtn = google;
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    [self.view setFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height)];
}

-(void) viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    NSThread* driverThread = [[NSThread alloc] initWithTarget:self selector:@selector(loadIt) object:nil];
    [driverThread start];

    if ([AppSettings numAccounts] == 0){
        UIAlertController* ac = [UIAlertController alertControllerWithTitle:nil
                                                                    message:NSLocalizedString(@"ask-to-sync-data", @"We do some extra sync, can we use data?")
                                                             preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction* yesAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"YES", @"YES") style:UIAlertActionStyleDefault
                                                             handler:^(UIAlertAction* aa) {
                                                                 [AppSettings setSyncOverData:YES];
                                                                }];
        
        UIAlertAction* noAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"NO", @"NO") style:UIAlertActionStyleCancel
                                                             handler:^(UIAlertAction* aa) {
                                                                 [AppSettings setSyncOverData:NO];
                                                             }];
        [ac addAction:yesAction];
        [ac addAction:noAction];
        
        [[ViewController mainVC] presentViewController:ac animated:YES completion:nil];
    }
}

-(void) loadIt
{
    [GlobalDBFunctions tableCheck];
}

-(BOOL) haveCocoaButton
{
    return NO;
}

-(void) _tap:(UITapGestureRecognizer*)tgr
{
    if (tgr.state != UIGestureRecognizerStateEnded) {
        return;
    }
    
    [self _hideKeyboard];
}

-(void) _google:(UIButton*)sender
{
    [[GIDSignIn sharedInstance] signOut];
    [[GIDSignIn sharedInstance] signIn];
}

- (void)signInWillDispatch:(GIDSignIn *)signIn error:(NSError *)error
{
    CCMLog(@"Remove Spinner");
}

-(void) _hideKeyboard
{
    [self.table endEditing:YES];
}

#define TITLE @"title"
#define CONTENT @"content"

#define TEXT @"t"
#define DACTION @"da"

-(void) _prepareTable
{
    
    NSArray* infos = @[
                       @{TEXT: NSLocalizedString(@"add-account-view.username", @"Label: Username"), DACTION : @"EDIT_NAME"},
                       @{TEXT: NSLocalizedString(@"add-account-view.email", @"Label: Email"), DACTION : @"EDIT_MAIL"},
                       @{TEXT: NSLocalizedString(@"add-account-view.password", @"Label: Password"), DACTION : @"EDIT_PASS"}
                       ];
    
    NSDictionary* Paccounts = @{TITLE:@"", CONTENT:infos};
    
    NSString* tDelete = NSLocalizedString(@"add-account-view.ok", @"Button: OK");
    NSDictionary* PDelete = @{TITLE:@"", CONTENT:@[@{TEXT:tDelete, DACTION : @"VALIDATE"}]};
    
    self.settings = @[Paccounts, PDelete];
    
}

-(void) cleanBeforeGoingBack
{
    [self _hideKeyboard];
    self.table.delegate = nil;
    self.table.dataSource = nil;
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
    
    CGFloat base = 44.f;
    
    if (indexPath.row==0) {
        base += .5;
        /*
        if (indexPath.section == 1) {
            base += 60;
        }
         */
    }
    
    return base;
}

-(UITableViewCell*) tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath
{
    
    NSDictionary* sectionInfos = self.settings[indexPath.section];
    NSArray* content = sectionInfos[CONTENT];
    NSDictionary* infoCell = content[indexPath.row];
    
    
    UITableViewCell* cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"noID"];
    
    
    cell.textLabel.text = infoCell[TEXT];
    
    cell.textLabel.textAlignment = NSTextAlignmentNatural;
    cell.textLabel.textColor = [UIColor blackColor];
    
    [cell.textLabel sizeToFit];
    
    cell.accessoryType = UITableViewCellAccessoryNone;
    
    
    CGSize bounds = tableView.bounds.size;
    bounds.height = 44.f;
    
    
    NSString* action = infoCell[DACTION];

    if ([action isEqualToString:@"VALIDATE"]) {
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = [UIGlobal standardBlue];
    }
    else {
        NSInteger labelWidth = MAX(cell.textLabel.frame.size.width+20, 100);
        
        UITextField* tf = [[UITextField alloc] initWithFrame:CGRectMake(labelWidth, 0, bounds.width - labelWidth - 10, bounds.height)];
        tf.delegate = self;
        [cell addSubview:tf];
        
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        
        
        if ([action isEqualToString:@"EDIT_PASS"]) {
            tf.secureTextEntry = YES;
            self.password = tf;
        }
        else if ([action isEqualToString:@"EDIT_MAIL"]) {
            tf.keyboardType = UIKeyboardTypeEmailAddress;
            self.email = tf;
        }
        else {
            tf.autocapitalizationType = UITextAutocapitalizationTypeWords;
            self.username = tf;
        }
    }
    
    cell.selectionStyle = UITableViewCellSelectionStyleGray;
    
    return cell;
}

-(NSString*) tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section
{
    NSDictionary* sectionInfos = self.settings[section];
    
    return sectionInfos[TITLE];
}

#pragma mark Table Delegate

-(CGFloat) tableView:(UITableView*)tableView heightForFooterInSection:(NSInteger)section
{
    return CGFLOAT_MIN;
}

-(CGFloat) tableView:(UITableView*)tableView heightForHeaderInSection:(NSInteger)section
{
    return 10;
}

-(void) _nextStep
{

    if (self.step == 0) {
        
        [self loadWithEmail:self.email.text pwd:self.password.text];
        
    }
    else {
        
        [[Accounts sharedInstance] addAccount:self.account];

        //if ([Accounts sharedInstance].accounts.count==2) {
            // it's the first account
        [Accounts sharedInstance].currentAccountIdx = self.account.idx;
        
        [self.account initContent];
        
        [ViewController refreshCocoaButton];
        
        [self.account connect];
        [self.account setCurrentFolder:FolderTypeWith(FolderTypeInbox, 0)];
        
        /*}else if ([Accounts sharedInstance].accounts.count > 2) {
            [Accounts sharedInstance].currentAccountIdx = self.account.accountIdx;
            [self.account initContent];
            [ViewController refreshCocoaButton];
        }*/
        
        [[NSNotificationCenter defaultCenter] postNotificationName:kBACK_NOTIFICATION object:nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:kACCOUNT_CHANGED_NOTIFICATION object:nil];
    }
    
}

-(NSIndexPath*) tableView:(UITableView*)tableView willSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
    if (indexPath.section == 0) {
        UITableViewCell* cell = [tableView cellForRowAtIndexPath:indexPath];
        NSArray* alls = [cell subviews];
        
        for (UIView* v in alls) {
            if ([v isKindOfClass:[UITextField class]]) {
                [v becomeFirstResponder];
                break;
            }
        }
    }
    else {
        [self _hideKeyboard];
        [self _nextStep];
    }
    
    return nil;
}

-(void) tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

#pragma mark - TextField delegate

-(BOOL) textFieldShouldReturn:(UITextField*)textField
{
    [textField resignFirstResponder];
    
    return YES;
}

-(BOOL) isEmailRegExp:(NSString*)text
{
    NSError* error = NULL;
    NSString* pattern = @"[a-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\\.[a-z0-9!#$%&'*+/=?^_`{|}~-]+)*@(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\\.)+[a-z0-9](?:[a-z0-9-]*[a-z0-9])?";
    NSRegularExpression* regex = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:&error];
    
    if (error) {
        CCMLog(@"%@", error.description);
    }
    
    return [regex matchesInString:text options:NSMatchingReportProgress range:NSMakeRange(0, text.length)].count;
}

-(void) receiveToggleAuthUINotification:(NSNotification*)notification
{
    if ([[notification name] isEqualToString:@"ToggleAuthUINotification"] && [notification userInfo][@"accessToken"]) {

        NSString* accessToken = [notification userInfo][@"accessToken"];
        NSString* email = [notification userInfo][@"email"];
        NSString* name = [notification userInfo][@"name"];
    
        self.email.text = email;
        self.username.text = name;
        self.password.text = @"";
    
        self.accountVal = [[MCOAccountValidator alloc]init];
        self.accountVal.email = email;
        self.accountVal.username = email;
        self.accountVal.OAuth2Token = accessToken;
    
        [self load];
    }
}

-(void) loadWithEmail:(NSString*)username pwd:(NSString*)password
{
    self.accountVal = [[MCOAccountValidator alloc]init];
    self.accountVal.username = username;
    self.accountVal.password = password;
    [self load];
}

-(void) load
{
    if (!self.accountVal.OAuth2Token) {
        NSString* email = self.email.text;
        NSString* password = self.password.text;
    
        if (!email.length || !password.length) {
            return;
        }
    
        if (![self isEmailRegExp:email]) {
            [ViewController presentAlertWIP:NSLocalizedString(@"add-account-view.error.invalid-email", @"Alert message: Invalid Email")];
            return;
        }
    }
    
    Reachability* networkReachability = [Reachability reachabilityForInternetConnection];
    NetworkStatus networkStatus = [networkReachability currentReachabilityStatus];
    
    if (networkStatus == NotReachable) {
        [ViewController presentAlertWIP:NSLocalizedString(@"add-account-view.error.no-internet", @"Alert message: Not connected to Internet")];
        return;
    }
    
    AddAccountViewController* __weak bself = self;
    
    [PKHUD sharedHUD].userInteractionOnUnderlyingViewsEnabled = FALSE;
    [PKHUD sharedHUD].contentView = [[PKHUDTextView alloc]initWithText:NSLocalizedString(@"add-account-view.loading-hud.fetching-settings", @"HUD Message: Fetching settings...")];
    [[PKHUD sharedHUD] show];
    
    [MCOMailProvidersManager sharedManager];
    
    [self.accountVal setImapEnabled:YES];
    [self.accountVal setSmtpEnabled:YES];
    
    [self.accountVal start:^() {
        AddAccountViewController* strongSelf = bself;
        
        if (!strongSelf.accountVal.imapError && !strongSelf.accountVal.smtpError) {
            [strongSelf saveSettings];
        }
        else {
            CCMLog(@"error loading imap account: %@", strongSelf.accountVal.imapError);
            CCMLog(@"error loading smtp account: %@", strongSelf.accountVal.smtpError);
            
            [[PKHUD sharedHUD] hideWithAnimated:YES];

            if (strongSelf.accountVal.imapError.code == MCOErrorAuthentication) {
                [ViewController presentAlertOk:NSLocalizedString(@"add-account-view.error.wrong-credentials", @"Alert message: Wrong credentials")];
                
            }
            else if(strongSelf.accountVal.imapError.code == MCOErrorConnection)  {
                if (networkStatus != NotReachable) {
                    [ViewController presentAlertOk:NSLocalizedString(@"add-account-view.error.try-again",@"There was an issue connecting. Please try to login again.")];//NSLocalizedString(@"add-account-view.error.no-server-settings", @"Unknown Server Settings")];
                }
                else {
                    [ViewController presentAlertOk:NSLocalizedString(@"add-account-view.error.no-internet",@"Connection error. There seems to be not internet connection.")];//NSLocalizedString(@"add-account-view.error.no-server-settings", @"Unknown Server Settings")];
                }
            }
            else {
                [ViewController presentAlertOk:NSLocalizedString(@"add-account-view.error.email-not-supported", @"Alert message: This email provider is not supported")];
            }
        }
    }];
}

-(void) saveSettings
{
    CCMLog(@"2 - Start saving settings");
    
    NSInteger newAccountIndex = [Accounts sharedInstance].accountsCount - 1;
    
    CCMLog(@"3 - Start setting Folders");
    
    [PKHUD sharedHUD].contentView = [[PKHUDTextView alloc]initWithText:NSLocalizedString(@"add-account-view.loading-hud.account-in-config", @"HUD Message: Account Configuration...")];
    [[PKHUD sharedHUD] show];
    
    MCOIMAPSession* imapSession = [[MCOIMAPSession alloc] init];
    
    imapSession.hostname = self.accountVal.imapServer.hostname;
    imapSession.port = self.accountVal.imapServer.port;
    imapSession.username = self.accountVal.username ;
    imapSession.password = self.accountVal.password;
    
    if (self.accountVal.OAuth2Token) {
        imapSession.OAuth2Token = self.accountVal.OAuth2Token;
        imapSession.authType = MCOAuthTypeXOAuth2;
    }
    imapSession.connectionType = self.accountVal.imapServer.connectionType;

    MCOIMAPFetchNamespaceOperation* namespaceOp = [imapSession fetchNamespaceOperation];
    [namespaceOp start:^(NSError* error, NSDictionary* namespaces) {
        if (error) {
            CCMLog(@"%@", error.description);
            [[PKHUD sharedHUD] hideWithAnimated:YES];
            
            return ;
        }
        
        MCOIMAPNamespace*  nameSpace = namespaces[MCOIMAPNamespacePersonal];
        MCOIMAPFetchFoldersOperation*  op = [imapSession fetchAllFoldersOperation];
        [imapSession setDefaultNamespace:nameSpace];
        
        [op start:^(NSError*  error, NSArray* folders) {
            if (error) {
                CCMLog(@"%@", error.description);
                [[PKHUD sharedHUD] hideWithAnimated:YES];
                
                return ;
            }
    
            [[SyncManager getSingleton] addAccountState];
            
            [AppSettings setSettingsWithAccountVal:self.accountVal accountIndex:newAccountIndex];
            MCOMailProvider* accountProvider = [[MCOMailProvidersManager sharedManager] providerForIdentifier:[AppSettings identifier:newAccountIndex]];

            [ImapSync allSharedServices:imapSession];

            [AppSettings setName:self.username.text accountIndex:newAccountIndex];
                
            [AppSettings setSignature:NSLocalizedString(@"add-account-view.default-settings.signature", @"Default Account Signature") accountIndex:newAccountIndex];
                
            [AppSettings setBadgeCount:0];
            [AppSettings setNotifications:YES accountIndex:newAccountIndex];
            [[Accounts sharedInstance] setCurrentAccountIdx:newAccountIndex];
            
            if (newAccountIndex == 0) {
                [AppSettings setDefaultAccountIndex:newAccountIndex];
            }
            
            NSMutableArray* flagedFolders = [[NSMutableArray alloc] init];
            NSMutableArray* otherFolders = [[NSMutableArray alloc] init];
            MCOIMAPFolder*  __block inboxfolder;
            MCOIMAPFolder*  __block allMailFolder;
            
            for (MCOIMAPFolder* folder in folders) {

                if (folder.flags & MCOIMAPFolderFlagNoSelect) {
                    continue;
                }
                
                if (folder.flags & MCOIMAPFolderFlagInbox || [folder.path  isEqualToString: @"INBOX"]) {
                    CCMLog(@"Inbox:%@", folder.path);
                    inboxfolder = folder;
                }
                else if ([accountProvider.allMailFolderPath isEqualToString:folder.path] || folder.flags & MCOIMAPFolderFlagAll || folder.flags & MCOIMAPFolderFlagAllMail || [@"Archive" isEqualToString:folder.path]) {
                    CCMLog(@"All:%@", folder.path);
                    allMailFolder = folder;
                }
                else if (![@(folder.flags) isEqualToNumber:@0]) {
                    CCMLog(@"Flagged:%@", folder.path);
                    [flagedFolders addObject:folder];
                }
                else {
                    CCMLog(@"other:%@", folder.path);
                    [otherFolders addObject:folder];
                }
            }
            
            NSString*  __block newAllMail = @"Archive";
            
            if (!allMailFolder) {
                //Create folder
                MCOIMAPOperation*  op = [imapSession createFolderOperation:newAllMail];
                [op start:^(NSError*  error) {
                    if (!error) {
                        
                        MCOIMAPFetchFoldersOperation*  op = [imapSession fetchAllFoldersOperation];
                        [imapSession setDefaultNamespace:nameSpace];
                        
                        [op start:^(NSError*  error, NSArray* folders) {
                            
                            for (MCOIMAPFolder* folder in folders) {
                                
                                if (folder.flags & MCOIMAPFolderFlagNoSelect) {
                                    continue;
                                }
                                
                                if (folder.flags & MCOIMAPFolderFlagInbox || [folder.path  isEqualToString: @"INBOX"]) {
                                    inboxfolder = folder;
                                }
                                else if ([accountProvider.allMailFolderPath isEqualToString:folder.path] || folder.flags & MCOIMAPFolderFlagAll || folder.flags & MCOIMAPFolderFlagAllMail || [newAllMail isEqualToString:folder.path]) {
                                    allMailFolder = folder;
                                }
                                else if (![@(folder.flags) isEqualToNumber:@0]) {
                                    [flagedFolders addObject:folder];
                                }
                                else {
                                    [otherFolders addObject:folder];
                                }
                            }
                            [self finishFoldersFlaged:flagedFolders others:otherFolders inbox:inboxfolder all:allMailFolder imapSession:imapSession newAccountIndex:newAccountIndex];
                        }];
                    }
                    else {
                        //Account not supported
                        [[PKHUD sharedHUD] hideWithAnimated:YES];
                        [ViewController presentAlertWIP:NSLocalizedString(@"add-account-view.error.email-not-supported", @"Alert Message: This email provider is not supported")];
                    }
                }];
            }
            else {
                [self finishFoldersFlaged:flagedFolders others:otherFolders inbox:inboxfolder all:allMailFolder imapSession:imapSession newAccountIndex:newAccountIndex];
            }
        }];
    }];
}

-(void) finishFoldersFlaged:(NSMutableArray*)flagedFolders others:(NSMutableArray*)otherFolders inbox:(MCOIMAPFolder*)inboxfolder all:(MCOIMAPFolder*)allMailFolder imapSession:(MCOIMAPSession*)imapSession newAccountIndex:(NSInteger)newAccountIndex
{
    CCMLog(@"4 - Finish Folders");
    
    SyncManager* sm = [SyncManager getSingleton];
    
    MCOMailProvider* accountProvider = [[MCOMailProvidersManager sharedManager] providerForIdentifier:[AppSettings identifier:newAccountIndex]];
    
    NSSortDescriptor* pathDescriptor = [[NSSortDescriptor alloc] initWithKey:NSStringFromSelector(@selector(path)) ascending:YES selector:@selector(caseInsensitiveCompare:)];
    NSMutableArray* sortedFolders = [[NSMutableArray alloc] init];
    [sortedFolders addObject:inboxfolder];
    [sortedFolders addObjectsFromArray:[flagedFolders sortedArrayUsingDescriptors:@[pathDescriptor]]];
    [sortedFolders addObjectsFromArray:[otherFolders sortedArrayUsingDescriptors:@[pathDescriptor]]];
    [sortedFolders addObject:allMailFolder];
    
    int indexPath = 0;
    
    NSMutableArray* dispNamesFolders = [[NSMutableArray alloc] initWithCapacity:1];
    
    [AppSettings setImportantFolderNum:-1 forBaseFolder:FolderTypeInbox forAccountIndex:newAccountIndex];
    [AppSettings setImportantFolderNum:-1 forBaseFolder:FolderTypeFavoris forAccountIndex:newAccountIndex];
    [AppSettings setImportantFolderNum:-1 forBaseFolder:FolderTypeSent forAccountIndex:newAccountIndex];
    [AppSettings setImportantFolderNum:-1 forBaseFolder:FolderTypeDrafts forAccountIndex:newAccountIndex];
    [AppSettings setImportantFolderNum:-1 forBaseFolder:FolderTypeAll forAccountIndex:newAccountIndex];
    [AppSettings setImportantFolderNum:-1 forBaseFolder:FolderTypeDeleted forAccountIndex:newAccountIndex];
    [AppSettings setImportantFolderNum:-1 forBaseFolder:FolderTypeSpam forAccountIndex:newAccountIndex];
    
    for (MCOIMAPFolder* folder in sortedFolders) {

        //Inbox
        if ((folder.flags == MCOIMAPFolderFlagInbox) || [folder.path  isEqualToString: @"INBOX"]) {
            [AppSettings setImportantFolderNum:indexPath forBaseFolder:FolderTypeInbox forAccountIndex:newAccountIndex];
        } //Starred
        else if([accountProvider.starredFolderPath isEqualToString:folder.path] || (folder.flags == MCOIMAPFolderFlagFlagged)) {
            [AppSettings setImportantFolderNum:indexPath forBaseFolder:FolderTypeFavoris forAccountIndex:newAccountIndex];
        } //Sent
        else if([accountProvider.sentMailFolderPath isEqualToString:folder.path] || (folder.flags == MCOIMAPFolderFlagSentMail)) {
            [AppSettings setImportantFolderNum:indexPath forBaseFolder:FolderTypeSent forAccountIndex:newAccountIndex];
        } //Draft
        else if([accountProvider.draftsFolderPath isEqualToString:folder.path] || (folder.flags == MCOIMAPFolderFlagDrafts)) {
            [AppSettings setImportantFolderNum:indexPath forBaseFolder:FolderTypeDrafts forAccountIndex:newAccountIndex];
        } //Archive
        else if([accountProvider.allMailFolderPath isEqualToString:folder.path] || ((folder.flags == MCOIMAPFolderFlagAll) || (folder.flags == MCOIMAPFolderFlagAllMail)) || [allMailFolder.path isEqualToString:folder.path]) {
            [AppSettings setImportantFolderNum:indexPath forBaseFolder:FolderTypeAll forAccountIndex:newAccountIndex];
        } //Trash
        else if([accountProvider.trashFolderPath isEqualToString:folder.path] || (folder.flags == MCOIMAPFolderFlagTrash)) {
            [AppSettings setImportantFolderNum:indexPath forBaseFolder:FolderTypeDeleted forAccountIndex:newAccountIndex];
        } //Spam
        else if([accountProvider.spamFolderPath isEqualToString:folder.path] || (folder.flags == MCOIMAPFolderFlagSpam)) {
            [AppSettings setImportantFolderNum:indexPath forBaseFolder:FolderTypeSpam forAccountIndex:newAccountIndex];
        }
        
        NSString* dispName = [[[imapSession defaultNamespace] componentsFromPath:[folder path]] componentsJoinedByString:@"/"];
        [dispNamesFolders addObject:dispName];
        
        NSDictionary* folderState = @{ @"accountNum" : @(newAccountIndex),
                                       @"folderDisplayName":dispName,
                                       @"folderPath":folder.path,
                                       @"deleted":@false,
                                       @"fullsynced":@false,
                                       @"lastended":@0,
                                       @"flags":@(folder.flags),
                                       @"emailCount":@(0)};
        
        [sm addFolderState:folderState accountIndex:newAccountIndex];
        
        MCOIMAPFolderInfoOperation* folderOp = [imapSession folderInfoOperation:folder.path];
        [folderOp start:^(NSError* error, MCOIMAPFolderInfo* info) {
            if (!error) {
                NSMutableDictionary* syncState = [sm retrieveState:indexPath accountIndex:newAccountIndex];
                syncState[@"emailCount"] = @([info messageCount]);
                [sm persistState:syncState forFolderNum:indexPath accountIndex:newAccountIndex];
            }
        }];
        
        indexPath++;
    }
    
    if ([AppSettings importantFolderNumforAccountIndex:newAccountIndex forBaseFolder:FolderTypeFavoris] == -1) {
        [AppSettings setImportantFolderNum:[AppSettings importantFolderNumforAccountIndex:newAccountIndex forBaseFolder:FolderTypeAll] forBaseFolder:FolderTypeFavoris forAccountIndex:newAccountIndex];
    }
    
    [AppSettings setFoldersName:dispNamesFolders forAccountIndex:newAccountIndex];
    
    CCMLog(@"5 - Go!");
    
    [[PKHUD sharedHUD] hideWithAnimated:NO];
    
    Account* ac = [Account emptyAccount];

    ac.userColor = [AppSettings defaultColors][newAccountIndex];
    
    [AppSettings setColor:ac.userColor accountIndex:newAccountIndex];
    ac.idx = newAccountIndex;
    
    BOOL added = NO;
    
    NSString* mail = self.email.text;
    NSUInteger loc = [mail rangeOfString:@"@"].location;
    NSUInteger locDot = [mail rangeOfString:@"." options:NSBackwardsSearch].location;
    
    if (loc != NSNotFound && loc > 2 &&  locDot != NSNotFound && loc < locDot) {
        NSString* code = [[mail substringToIndex:3] uppercaseString];
        ac.codeName = code;
        Person* p = [Person createWithName:self.username.text email:mail icon:nil codeName:code];
        added = YES;
        ac.person = p;
    }
    
    
    if (self.username.text.length>2) {
        added = YES;
    }
    
    if (added) {
        ac.userMail = mail;
        //ac.userFolders = [AppSettings allNonImportantFoldersName:newAccountNum];
        self.account = ac;
        
        self.step = 1;
        NSArray* tmpFolders = [AppSettings allNonImportantFoldersNameforAccountIndex:newAccountIndex];
        NSMutableArray* foldersNIndent = [[NSMutableArray alloc]initWithCapacity:tmpFolders.count];
        
        for (NSString* folderNames in tmpFolders) {
            [foldersNIndent addObject:@[folderNames, @([folderNames containsString:@"]/"])]];
        }
        
        ac.userFolders = foldersNIndent;
        
        EditCocoaButtonView* ecbv = [EditCocoaButtonView editCocoaButtonViewForAccount:self.account];
        ecbv.frame = CGRectMake(0, 55, ecbv.frame.size.width, ecbv.frame.size.height);
        [self.view addSubview:ecbv];
        self.editCocoa = ecbv;
        [ecbv becomeFirstResponder];
        
        UINavigationItem* item = [self.navBar.items firstObject];
        NSString* title = NSLocalizedString(@"add-account-view.title-for-cocoa-button", @"Title: Your Cocoa button");
        item.titleView = [WhiteBlurNavBar titleViewForItemTitle:title];
        [self.navBar setNeedsDisplay];
        
        self.googleBtn.hidden = YES;
    }
}


@end



