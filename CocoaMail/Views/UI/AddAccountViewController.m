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
//#import <Google/SignIn.h>
#import "GTMOAuth2Authentication.h"
#import "GTMOAuth2ViewControllerTouch.h"
#import "GTMSessionFetcher.h"
#import "UserSettings.h"
#import "SyncManager.h"
#import "AppSettings.h"
#import "Reachability.h"
#import "GlobalDBFunctions.h"
#import "ImapSync.h"
#import "CocoaMail-Swift.h"
#import "OnePasswordExtension.h"

// 20160731_1356 AJCerier
// Error: "'init' is unavailable"
// Resolution: Added this class extension to make init() availale;
@interface MCOAccountValidator (foo)
- (instancetype) init;
@end

@interface AddAccountViewController () <MailListDelegate>

@property (nonatomic, strong) UserSettings* user;
@property (nonatomic, strong) MCOAccountValidator* accountVal;


@end


@interface AddAccountViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate/*,GIDSignInUIDelegate*/>

@property (nonatomic, weak) UITableView* table;
@property (nonatomic, strong) NSArray* settings;

//@property (nonatomic, weak) UITextField* username;
@property (nonatomic, weak) UITextField* email;
@property (nonatomic, weak) UITextField* password;
@property (nonatomic, weak) UIButton* onePassword;

//@property (nonatomic, weak) EditCocoaButtonView* editCocoa;
//@property (nonatomic) NSInteger step;

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
    
    NSString* title = NSLocalizedString(@"add-account-view.title", @"Add account View Title");
    item.titleView = [WhiteBlurNavBar titleViewForItemTitle:title];
    
    if ([[OnePasswordExtension sharedExtension] isAppExtensionAvailable]) {
        UIButton* attach = [WhiteBlurNavBar navBarButtonWithImage:@"onepassword-navbar" andHighlighted:@"onepassword-navbar-light"];
        [attach setHidden:NO];
        [attach addTarget:self action:@selector(findLoginFrom1Password:) forControlEvents:UIControlEventTouchUpInside];
        item.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:attach];
        self.onePassword = attach;
    }
    
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
    
    //[self.view addSubview:cocoa];
    
    UITapGestureRecognizer* tgr = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_tap:)];
    tgr.cancelsTouchesInView = NO;
    [self.table addGestureRecognizer:tgr];
    
    UIButton* google = [[UIButton alloc] initWithFrame:CGRectMake(0, posYbutton, screenBounds.size.width, 70 + 45)];
    [google setImage:[UIImage imageNamed:@"signGoogle_on"] forState:UIControlStateNormal];
    [google setImage:[UIImage imageNamed:@"signGoogle_off"] forState:UIControlStateHighlighted];
    [google addTarget:self action:@selector(_startOAuth2:) forControlEvents:UIControlEventTouchUpInside];
    
    [self.view addSubview:google];

    self.googleBtn = google;
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
}

-(void) viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];

    [self.view setFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height)];

    NSThread* driverThread = [[NSThread alloc] initWithTarget:self selector:@selector(loadIt) object:nil];
    [driverThread start];
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

- (void) _startOAuth2:(UIButton*)sender
{
    SEL selectorFinish = @selector(viewController:finishedWithAuth:error:);
    SEL selectorButtonCancel = @selector(buttonCancelTapped:);
    
    UINavigationController *navController = [[UINavigationController alloc] init];
    
    UINavigationBar *navigationBar = [[UINavigationBar alloc] initWithFrame:CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, 63)];
    UINavigationItem *navigationItem = [[UINavigationItem alloc] initWithTitle:@"Gmail"];
    UIBarButtonItem *barButtonItemCancel = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCancel target:self action:selectorButtonCancel];
    
    [navigationItem setRightBarButtonItem:barButtonItemCancel];
    [navigationBar setTranslucent:NO];
    [navigationBar setItems:[NSArray arrayWithObjects: navigationItem,nil]];
    
    [navController.view addSubview:navigationBar];
    
    NSInteger accountNum = 1;
    
    for (UserSettings* user in [AppSettings getSingleton].users) {
        if (user.isAll) {
            continue;
        }
        
        accountNum++;
    }
    
    GTMOAuth2ViewControllerTouch *authViewController = [GTMOAuth2ViewControllerTouch controllerWithScope:@"https://mail.google.com/"
                                                                                                clientID:CLIENT_ID
                                                                                            clientSecret:CLIENT_SECRET
                                                                                        keychainItemName:[NSString stringWithFormat:@"%@%ld", TKN_KEYCHAIN_NAME,(long)accountNum]
                                                                                                delegate:self
                                                                                        finishedSelector:selectorFinish];
    [navController addChildViewController:authViewController];
    
    [[ViewController mainVC] presentViewController:navController animated:YES completion:nil];
}

- (void)buttonCancelTapped:(UIBarButtonItem *)sender {
    [[ViewController mainVC] dismissViewControllerAnimated:YES completion:^(void){}];
}

- (void)viewController:(GTMOAuth2ViewControllerTouch *)viewController finishedWithAuth:(GTMOAuth2Authentication *)authResult error:(NSError *)error {
    [[ViewController mainVC] dismissViewControllerAnimated:YES completion:^(void){}];
    
    if (error != nil) {
        [ViewController presentAlertOk:NSLocalizedString(@"add-account-view.error.try-again",@"There was an issue connecting. Please try to login again.")];
    }
    else {
        [self loadWithAuth:authResult];
    }
}

// 20160824_1055 AJCerier
// Error: "Use of undeclared identifier 'GTMHTTPFetcher'"
// Resolution: Changed GTMHTTPFetcher to GTMSessionFetcher.
- (void)auth:(GTMOAuth2Authentication *)authResult finishedRefreshWithFetcher:(GTMSessionFetcher *)fetcher error:(NSError *)error {
    if (error != nil) {
        [ViewController presentAlertOk:NSLocalizedString(@"add-account-view.error.try-again",@"There was an issue connecting. Please try to login again.")];
    }
    else {
        [self loadWithAuth:authResult];
    }
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
                       //@{TEXT: NSLocalizedString(@"add-account-view.username", @"Label: Username"), DACTION : @"EDIT_NAME"},
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
            tf.returnKeyType = UIReturnKeyDone;
            self.password = tf;
        }
        else if ([action isEqualToString:@"EDIT_MAIL"]) {
            tf.keyboardType = UIKeyboardTypeEmailAddress;
            tf.returnKeyType = UIReturnKeyNext;
            self.email = tf;
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
        self.email.text = [self.email.text stringByReplacingOccurrencesOfString:@" " withString:@""];
        self.password.text = [self.password.text stringByReplacingOccurrencesOfString:@" " withString:@""];

        [self loadAccountWithUsername:self.email.text password:self.password.text oauth2Token:nil];
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
    
    /*if (textField == self.username) {
        [self.email becomeFirstResponder];
    }
    else*/
    if (textField == self.email) {
        [self.password becomeFirstResponder];
    }
    else if (textField == self.password) {
        [self _nextStep];
    }
    
    return YES;
}

-(BOOL) isEmailRegExp:(NSString*)text
{
    NSError* error = NULL;
    NSString* pattern = @"[a-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\\.[a-z0-9!#$%&'*+/=?^_`{|}~-]+)*@(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\\.)+[a-z0-9](?:[a-z0-9-]*[a-z0-9])?";
    NSRegularExpression* regex = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:&error];
    
    if (error) {
        DDLogError(@"%@", error.description);
    }
    
    return [regex matchesInString:text options:NSMatchingReportProgress range:NSMakeRange(0, text.length)].count;
}

-(void) loadWithAuth:(GTMOAuth2Authentication *)auth
{
    self.email.text = [auth userEmail];
    self.password.text = @"";
    
    [self loadAccountWithUsername:[auth userEmail] password:nil oauth2Token:[auth accessToken]];
}

- (void)loadAccountWithUsername:(NSString *)username
                       password:(NSString *)password
                    oauth2Token:(NSString *)oauth2Token
{
    // 20160824_1151 AJCerier
    // Error: No visible interface for MCOAccountValidator
    //      declares the selector 'initValidator'.
    // Discussion:
    //      Change 'initValidator' to 'init'.
    //      init() exists in MCOAccountValidator and its superclass
    //      MCOOperation.
    //      However, init is marked as NS_UNAVAILABLE in the superclass,
    //      and is not included in the MCOAccountValidator header.
    // Resolution:
    //      My solution is to add an extension to MCOAccountValidator
    //      to the top of this file which makes init available.
    self.accountVal = [[MCOAccountValidator alloc] init];
    self.accountVal.username = username;
    self.accountVal.password = password;
    
    if (oauth2Token) {
        self.accountVal.email = username;
        self.accountVal.OAuth2Token = oauth2Token;
    }
    
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
            DDLogError(@"error loading imap account: %@", strongSelf.accountVal.imapError);
            DDLogError(@"error loading smtp account: %@", strongSelf.accountVal.smtpError);
            
            [[PKHUD sharedHUD] hideWithAnimated:YES];
            
            if (strongSelf.accountVal.imapError.code == MCOErrorAuthentication || strongSelf.accountVal.smtpError.code == MCOErrorAuthentication) {
                [ViewController presentAlertOk:NSLocalizedString(@"add-account-view.error.wrong-credentials", @"Alert message: Wrong credentials")];
                
            }
            else if(strongSelf.accountVal.imapError.code == MCOErrorConnection || strongSelf.accountVal.smtpError.code == MCOErrorConnection)  {
                if (networkStatus != NotReachable) {
                    [ViewController presentAlertOk:NSLocalizedString(@"add-account-view.error.try-again",@"There was an issue connecting. Please try to login again.")];//NSLocalizedString(@"add-account-view.error.no-server-settings", @"Unknown Server Settings")];
                }
                else {
                    [ViewController presentAlertOk:NSLocalizedString(@"add-account-view.error.no-internet",@"Connection error. There seems to be not internet connection.")];//NSLocalizedString(@"add-account-view.error.no-server-settings", @"Unknown Server Settings")];
                }
            }
            else if (strongSelf.accountVal.imapError.code == MCOErrorGmailApplicationSpecificPasswordRequired || strongSelf.accountVal.smtpError.code == MCOErrorGmailApplicationSpecificPasswordRequired) {
                [ViewController presentAlertOk:NSLocalizedString(@"add-account-view.error.try-again",@"There was an issue connecting. Please try to login again.")];
            }
            else {
                [ViewController presentAlertOk:NSLocalizedString(@"add-account-view.error.email-not-supported", @"Alert message: This email provider is not supported")];
            }
        }
    }];
}

-(void) saveSettings
{
    DDLogInfo(@"2 - Start setting Folders");
    
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
            DDLogError(@"%@", error.description);
            [[PKHUD sharedHUD] hideWithAnimated:YES];
            
            return ;
        }
        
        MCOIMAPNamespace*  nameSpace = namespaces[MCOIMAPNamespacePersonal];
        MCOIMAPFetchFoldersOperation*  op = [imapSession fetchAllFoldersOperation];
        [imapSession setDefaultNamespace:nameSpace];
        
        [op start:^(NSError*  error, NSArray* folders) {
            if (error) {
                DDLogError(@"%@", error.description);
                [[PKHUD sharedHUD] hideWithAnimated:YES];
                
                return ;
            }
            
            MCOMailProvider* accountProvider = [[MCOMailProvidersManager sharedManager] providerForIdentifier:self.accountVal.identifier];
            
            NSMutableArray* flagedFolders = [[NSMutableArray alloc] init];
            NSMutableArray* otherFolders = [[NSMutableArray alloc] init];
            MCOIMAPFolder*  __block inboxfolder;
            MCOIMAPFolder*  __block allMailFolder;
            
            for (MCOIMAPFolder* folder in folders) {
                
                if (folder.flags & MCOIMAPFolderFlagNoSelect) {
                    continue;
                }
                
                if (folder.flags & MCOIMAPFolderFlagInbox || [folder.path  isEqualToString: @"INBOX"]) {
                    DDLogDebug(@"Inbox:%@", folder.path);
                    inboxfolder = folder;
                }
                else if ([accountProvider.allMailFolderPath isEqualToString:folder.path] || folder.flags & MCOIMAPFolderFlagAll || folder.flags & MCOIMAPFolderFlagAllMail || [@"Archive" isEqualToString:folder.path]) {
                    DDLogDebug(@"All:%@", folder.path);
                    allMailFolder = folder;
                }
                else if (![@(folder.flags) isEqualToNumber:@0]) {
                    DDLogDebug(@"Flagged:%@", folder.path);
                    [flagedFolders addObject:folder];
                }
                else {
                    DDLogDebug(@"other:%@", folder.path);
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
                            [self _finishFoldersFlaged:flagedFolders others:otherFolders inbox:inboxfolder all:allMailFolder imapSession:imapSession];
                        }];
                    }
                    else {
                        DDLogDebug(@"[AddFirstAccountViewController saveSettings:]");
                        DDLogDebug(@"      Failed to create folder \"Archive\", NSError = %@",[error description]);

                        //Account not supported
                        [[PKHUD sharedHUD] hideWithAnimated:YES];
                        [ViewController presentAlertWIP:NSLocalizedString(@"add-account-view.error.email-not-supported", @"Alert Message: This email provider is not supported")];
                    }
                }];
            }
            else {
                [self _finishFoldersFlaged:flagedFolders others:otherFolders inbox:inboxfolder all:allMailFolder imapSession:imapSession];
            }
        }];
    }];
}

-(void) _finishFoldersFlaged:(NSMutableArray*)flagedFolders others:(NSMutableArray*)otherFolders inbox:(MCOIMAPFolder*)inboxfolder all:(MCOIMAPFolder*)allMailFolder imapSession:(MCOIMAPSession*)imapSession
{
    DDLogInfo(@"3 - Finish Folders");
    
    //User Settings
    UserSettings* user = [[AppSettings getSingleton] createNewUser];
    [user setUsername:self.email.text];
    [user setName:@""];
    [user setSignature:NSLocalizedString(@"add-account-view.default-settings.signature", @"Default Account Signature")];
    [user setColor: [AppSettings defaultColors][user.accountIndex]];
    
    [AppSettings setNotifications:YES accountNum:user.accountNum];
    
    if (user.accountIndex == 0) {
        [AppSettings setDefaultAccountNum:user.accountNum];
    }
    
    NSString* mail = self.email.text;
    
    NSString* code = [[mail substringToIndex:3] uppercaseString];
    [user setInitials:code];
    
    /*NSUInteger loc = [mail rangeOfString:@"@"].location;
    NSUInteger locDot = [mail rangeOfString:@"." options:NSBackwardsSearch].location;
    
    if (loc != NSNotFound &&  locDot != NSNotFound && loc < locDot && (locDot-loc) > 2) {
        NSString* code = [[mail substringWithRange:NSMakeRange(loc+1, 3)] uppercaseString];
        [user setInitials:code];
    }
    else {
        NSString* code = [[mail substringToIndex:3] uppercaseString];
        [user setInitials:code];
    }*/
    
    [AppSettings setSettingsWithAccountVal:self.accountVal user:user];
    
    //Account of User
    Account* ac = [Account emptyAccount];
    [ac setNewUser:user];
    
    ac.person = [Person createWithName:user.name email:user.username icon:nil codeName:user.initials];
    
    DDLogInfo(@"Adding first Account:\n%@",[ac description]);

    // Folder Settings
    MCOMailProvider* accountProvider = [[MCOMailProvidersManager sharedManager] providerForIdentifier:user.identifier];
    
    NSSortDescriptor* pathDescriptor = [[NSSortDescriptor alloc] initWithKey:NSStringFromSelector(@selector(path)) ascending:YES selector:@selector(caseInsensitiveCompare:)];
    
    NSMutableArray* sortedFolders = [[NSMutableArray alloc] init];
    
    [sortedFolders addObject:inboxfolder];
    [sortedFolders addObjectsFromArray:[flagedFolders sortedArrayUsingDescriptors:@[pathDescriptor]]];
    [sortedFolders addObjectsFromArray:[otherFolders sortedArrayUsingDescriptors:@[pathDescriptor]]];
    [sortedFolders addObject:allMailFolder];
    
    int indexPath = 0;
    
    NSMutableArray* dispNamesFolders = [[NSMutableArray alloc] initWithCapacity:1];
    
    [[SyncManager getSingleton] addAccountState];
    
    for (MCOIMAPFolder* folder in sortedFolders) {
        
        //Inbox
        if ( (folder.flags == MCOIMAPFolderFlagInbox) ||
             ([folder.path  isEqualToString: @"INBOX"]) ) {
            [user setImportantFolderNum:indexPath forBaseFolder:FolderTypeInbox];
        } //Starred
        else if([accountProvider.starredFolderPath isEqualToString:folder.path] || (folder.flags == MCOIMAPFolderFlagFlagged)) {
            [user setImportantFolderNum:indexPath forBaseFolder:FolderTypeFavoris];
        } //Sent
        else if([accountProvider.sentMailFolderPath isEqualToString:folder.path] || (folder.flags == MCOIMAPFolderFlagSentMail)) {
            [user setImportantFolderNum:indexPath forBaseFolder:FolderTypeSent];
        } //Draft
        else if([accountProvider.draftsFolderPath isEqualToString:folder.path] || (folder.flags == MCOIMAPFolderFlagDrafts)) {
            [user setImportantFolderNum:indexPath forBaseFolder:FolderTypeDrafts];
        } //Archive
        else if([accountProvider.allMailFolderPath isEqualToString:folder.path] || ((folder.flags == MCOIMAPFolderFlagAll) || (folder.flags == MCOIMAPFolderFlagAllMail)) || [allMailFolder.path isEqualToString:folder.path]) {
            [user setImportantFolderNum:indexPath forBaseFolder:FolderTypeAll];
        } //Trash
        else if([accountProvider.trashFolderPath isEqualToString:folder.path] || (folder.flags == MCOIMAPFolderFlagTrash)) {
            [user setImportantFolderNum:indexPath forBaseFolder:FolderTypeDeleted];
        } //Spam
        else if([accountProvider.spamFolderPath isEqualToString:folder.path] || (folder.flags == MCOIMAPFolderFlagSpam)) {
            [user setImportantFolderNum:indexPath forBaseFolder:FolderTypeSpam];
        }
        

        ImapSync *imapSync = [ImapSync sharedServices:user];
        
        NSString *dispName = [imapSync addFolder:folder toUser:user atIndex:indexPath usingImapSession:imapSession];
        
//        NSString *dispName = [imapSync displayNameForFolder:folder  usingSession:imapSession];
        
        [dispNamesFolders addObject:dispName];

//        [[SyncManager getSingleton] addNewStateForFolder:folder
//                                                   named:dispName
//                                              forAccount:user.accountNum];
//        
//        [imapSync updatePersistentStateOfFolder:folder
//                                        atIndex:indexPath
//                               forAccountNumber:user.accountNum];
        
        indexPath++;
    }
    
    if ([user numFolderWithFolder:CCMFolderTypeFavoris] == -1) {
        [user setImportantFolderNum:[user numFolderWithFolder:CCMFolderTypeAll] forBaseFolder:FolderTypeFavoris];
    }
    
    [user setAllFoldersDisplayNames:dispNamesFolders];
        
    ac.userFolders = [ac userFolderNames];
    
    [[Accounts sharedInstance] addAccount:ac];
    
    DDLogInfo(@"4 - Go!");
    
    [PKHUD sharedHUD].contentView = [[PKHUDTextView alloc]initWithText:NSLocalizedString(@"add-account-view.loading-hud.fetching-emails", @"HUD Message: Fetching first emails")];
    [[PKHUD sharedHUD] show];
    
    self.user = user;
    /*self.step = 1;
    
    EditCocoaButtonView* ecbv = [EditCocoaButtonView editCocoaButtonViewForAccount:ac];
    ecbv.frame = CGRectMake(0, 55, ecbv.frame.size.width, ecbv.frame.size.height);
    [self.view addSubview:ecbv];
    self.editCocoa = ecbv;
    [ecbv becomeFirstResponder];
        
    UINavigationItem* item = [self.navBar.items firstObject];
    NSString* title = NSLocalizedString(@"add-account-view.title-for-cocoa-button", @"Title: Your Cocoa button");
    item.titleView = [WhiteBlurNavBar titleViewForItemTitle:title];
    [self.navBar setNeedsDisplay];*/
        
    self.googleBtn.hidden = YES;
    
    [ImapSync allSharedServices:imapSession];
    
    [ac connect];
    
    [Accounts sharedInstance].currentAccountIdx = self.user.accountIndex;
    
    [ViewController refreshCocoaButton];
    ac.mailListSubscriber = self;
    
    [ac refreshCurrentFolder];
}

-(void) serverSearchDone:(BOOL)done
{
    if (done) {
        [[PKHUD sharedHUD] hideWithAnimated:NO];
        
        self.user.linkedAccount.mailListSubscriber = nil;
        
        [[NSNotificationCenter defaultCenter] postNotificationName:kBACK_NOTIFICATION object:nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:kACCOUNT_CHANGED_NOTIFICATION object:nil];
    }
}

-(void) localSearchDone:(BOOL)done {}
-(void) removeConversationList:(NSArray*)convs {}
-(void) reFetch:(BOOL)forceRefresh {}
-(BOOL) isPresentingDrafts { return NO; }


-(void) findLoginFrom1Password:(id)sender
{
    [[OnePasswordExtension sharedExtension] findLoginForURLString:@"https://putcocoa.in" forViewController:self sender:sender completion:^(NSDictionary *loginDictionary, NSError *error) {
        if (loginDictionary.count == 0) {
            if (error.code != AppExtensionErrorCodeCancelledByUser) {
                DDLogError(@"Error invoking 1Password App Extension for find login: %@", error);
            }
            return;
        }
        
        self.email.text = loginDictionary[AppExtensionUsernameKey];
        self.password.text = loginDictionary[AppExtensionPasswordKey];
    }];
}

-(void) insertConversationIndex:(ConversationIndex*)ci
{
    
}

- (void)updateDays:(NSArray *)days
{
    
}

@end



