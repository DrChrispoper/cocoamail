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
#import "GTMHTTPFetcher.h"
#import "UserSettings.h"
#import "SyncManager.h"
#import "AppSettings.h"
#import "Reachability.h"
#import "GlobalDBFunctions.h"
#import "ImapSync.h"
#import "CocoaMail-Swift.h"
#import "OnePasswordExtension.h"

@interface AddAccountViewController ()

@property (nonatomic, strong) UserSettings* user;
@property (nonatomic, strong) MCOAccountValidator* accountVal;


@end


@interface AddAccountViewController () <UITableViewDataSource, UITableViewDelegate, UITextFieldDelegate/*,GIDSignInUIDelegate*/>

@property (nonatomic, weak) UITableView* table;
@property (nonatomic, strong) NSArray* settings;

@property (nonatomic, weak) UITextField* username;
@property (nonatomic, weak) UITextField* email;
@property (nonatomic, weak) UITextField* password;
@property (nonatomic, weak) UIButton* onePassword;

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
    
    /*[[NSNotificationCenter defaultCenter]
     addObserver:self
     selector:@selector(receiveToggleAuthUINotification:)
     name:@"ToggleAuthUINotification"
     object:nil];*/
    
    //[GIDSignIn sharedInstance].uiDelegate = self;
    
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
    
    [self.view addSubview:cocoa];
    
    UITapGestureRecognizer* tgr = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_tap:)];
    [cocoa addGestureRecognizer:tgr];
    cocoa.userInteractionEnabled = YES;
    
    UIButton* google = [[UIButton alloc] initWithFrame:CGRectMake(0, posYbutton, screenBounds.size.width, 70 + 45)];
    [google setImage:[UIImage imageNamed:@"signGoogle_on"] forState:UIControlStateNormal];
    [google setImage:[UIImage imageNamed:@"signGoogle_off"] forState:UIControlStateHighlighted];
    [google addTarget:self action:@selector(_startOAuth2:) forControlEvents:UIControlEventTouchUpInside];
    
    [self.view addSubview:google];
    
    /*for (Account* a in [Accounts sharedInstance].accounts) {
        if (!a.isAllAccounts && [a.user isUsingOAuth]) {
            google.hidden = YES;
        }
    }*/
    
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

-(void) _google:(UIButton*)sender
{
    //[[GIDSignIn sharedInstance] signOut];
    //[[GIDSignIn sharedInstance] signIn];
}

- (void) _startOAuth2:(UIButton*)sender
{
    /*GTMOAuth2Authentication * auth = [GTMOAuth2ViewControllerTouch authForGoogleFromKeychainForName:KEYCHAIN_ITEM_NAME
                                                                                           clientID:CLIENT_ID
                                                                                       clientSecret:CLIENT_SECRET];*/
    
    //if (![auth canAuthorize]) {
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
    
        GTMOAuth2ViewControllerTouch *authViewController = [GTMOAuth2ViewControllerTouch controllerWithScope:@"https://mail.google.com/"
                                                                                                clientID:CLIENT_ID
                                                                                            clientSecret:CLIENT_SECRET
                                                                                        keychainItemName:KEYCHAIN_ITEM_NAME
                                                                                                delegate:self
                                                                                        finishedSelector:selectorFinish];
    [navController addChildViewController:authViewController];
    
    [[ViewController mainVC] presentViewController:navController animated:YES completion:nil];

    //}
    //else {
    //    [auth beginTokenFetchWithDelegate:self didFinishSelector:@selector(auth:finishedRefreshWithFetcher:error:)];
    //}
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

- (void)auth:(GTMOAuth2Authentication *)authResult finishedRefreshWithFetcher:(GTMHTTPFetcher *)fetcher error:(NSError *)error {
    if (error != nil) {
        [ViewController presentAlertOk:NSLocalizedString(@"add-account-view.error.try-again",@"There was an issue connecting. Please try to login again.")];
    }
    else {
        [self loadWithAuth:authResult];
    }
}

/*- (void)signInWillDispatch:(GIDSignIn *)signIn error:(NSError *)error
{
    CCMLog(@"Remove Spinner");
}*/

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
            tf.returnKeyType = UIReturnKeyDone;
            self.password = tf;
        }
        else if ([action isEqualToString:@"EDIT_MAIL"]) {
            tf.keyboardType = UIKeyboardTypeEmailAddress;
            tf.returnKeyType = UIReturnKeyNext;
            self.email = tf;
        }
        else {
            tf.autocapitalizationType = UITextAutocapitalizationTypeWords;
            tf.returnKeyType = UIReturnKeyNext;
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
        
        self.email.text = [self.email.text stringByReplacingOccurrencesOfString:@" " withString:@""];
        self.password.text = [self.password.text stringByReplacingOccurrencesOfString:@" " withString:@""];

        [self loadAccountWithUsername:self.email.text password:self.password.text oauth2Token:nil];
        
    }
    else {
        [Accounts sharedInstance].currentAccountIdx = self.user.accountIndex;
        
        [ViewController refreshCocoaButton];
        
        [self.user.linkedAccount connect];
        [self.user.linkedAccount setCurrentFolder:FolderTypeWith(FolderTypeInbox, 0)];
        
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
    
    if (textField == self.username) {
        [self.email becomeFirstResponder];
    }
    else if (textField == self.email) {
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
        CCMLog(@"%@", error.description);
    }
    
    return [regex matchesInString:text options:NSMatchingReportProgress range:NSMakeRange(0, text.length)].count;
}

/*-(void) receiveToggleAuthUINotification:(NSNotification*)notification
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
}*/

-(void) loadWithAuth:(GTMOAuth2Authentication *)auth
{
    self.email.text = [auth userEmail];
    self.username.text = [auth userEmail];
    self.password.text = @"";
    
    [self loadAccountWithUsername:[auth userEmail] password:nil oauth2Token:[auth accessToken]];
}

- (void)loadAccountWithUsername:(NSString *)username
                       password:(NSString *)password
                    oauth2Token:(NSString *)oauth2Token
{
    self.accountVal = [[MCOAccountValidator alloc]init];
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
            else if (strongSelf.accountVal.imapError.code == MCOErrorGmailApplicationSpecificPasswordRequired) {
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
    CCMLog(@"2 - Start setting Folders");
    
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
                            [self _finishFoldersFlaged:flagedFolders others:otherFolders inbox:inboxfolder all:allMailFolder imapSession:imapSession];
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
                [self _finishFoldersFlaged:flagedFolders others:otherFolders inbox:inboxfolder all:allMailFolder imapSession:imapSession];
            }
        }];
    }];
}

-(void) _finishFoldersFlaged:(NSMutableArray*)flagedFolders others:(NSMutableArray*)otherFolders inbox:(MCOIMAPFolder*)inboxfolder all:(MCOIMAPFolder*)allMailFolder imapSession:(MCOIMAPSession*)imapSession
{
    CCMLog(@"3 - Finish Folders");
    
    //User Settings
    UserSettings* user = [[AppSettings getSingleton] createNewUser];
    [user setUsername:self.email.text];
    [user setName:self.username.text];
    [user setSignature:NSLocalizedString(@"add-account-view.default-settings.signature", @"Default Account Signature")];
    [user setColor: [AppSettings defaultColors][user.accountIndex]];
    
    [AppSettings setNotifications:YES accountNum:user.accountNum];
    
    if (user.accountIndex == 0) {
        [AppSettings setDefaultAccountNum:user.accountNum];
    }
    
    NSString* mail = self.email.text;
    NSUInteger loc = [mail rangeOfString:@"@"].location;
    NSUInteger locDot = [mail rangeOfString:@"." options:NSBackwardsSearch].location;
    
    if (loc != NSNotFound && loc > 2 &&  locDot != NSNotFound && loc < locDot) {
        NSString* code = [[mail substringToIndex:3] uppercaseString];
        [user setInitials:code];
    }
    
    [AppSettings setSettingsWithAccountVal:self.accountVal user:user];

    //Account of User
    Account* ac = [Account emptyAccount];
    [ac setNewUser:user];
    
    ac.person = [Person createWithName:user.name email:user.username icon:nil codeName:user.initials];
    
    //Folder Settings
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
        if ((folder.flags == MCOIMAPFolderFlagInbox) || [folder.path  isEqualToString: @"INBOX"]) {
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
        
        NSString* dispName = [[[imapSession defaultNamespace] componentsFromPath:[folder path]] componentsJoinedByString:[NSString stringWithFormat:@"%c",[folder delimiter]]];
        [dispNamesFolders addObject:dispName];
        
        NSDictionary* folderState = @{ @"accountNum" : @(user.accountNum),
                                       @"folderDisplayName":dispName,
                                       @"folderPath":folder.path,
                                       @"deleted":@false,
                                       @"fullsynced":@false,
                                       @"lastended":@0,
                                       @"flags":@(folder.flags),
                                       @"emailCount":@(0)};
        
        [[SyncManager getSingleton] addFolderState:folderState accountNum:user.accountNum];
        
        MCOIMAPFolderInfoOperation* folderOp = [imapSession folderInfoOperation:folder.path];
        [folderOp start:^(NSError* error, MCOIMAPFolderInfo* info) {
            if (!error) {
                NSMutableDictionary* syncState = [[SyncManager getSingleton] retrieveState:indexPath accountNum:user.accountNum];
                syncState[@"emailCount"] = @([info messageCount]);
                [[SyncManager getSingleton] persistState:syncState forFolderNum:indexPath accountNum:user.accountNum];
            }
        }];
        
        indexPath++;
    }
    
    if ([user importantFolderNumforBaseFolder:FolderTypeFavoris] == -1) {
        [user setImportantFolderNum:[user importantFolderNumforBaseFolder:FolderTypeAll] forBaseFolder:FolderTypeFavoris];
    }
    
    [user setAllFoldersDisplayNames:dispNamesFolders];
    
    NSArray* tmpFolders = [user allNonImportantFoldersName];
    NSMutableArray* foldersNIndent = [[NSMutableArray alloc]initWithCapacity:tmpFolders.count];
    for (NSString* folderNames in tmpFolders) {
        [foldersNIndent addObject:@[folderNames, @([folderNames containsString:@"/"])]];
    }
    
    ac.userFolders = foldersNIndent;
    
    [[Accounts sharedInstance] addAccount:ac];
    
    CCMLog(@"4 - Go!");
    
    [[PKHUD sharedHUD] hideWithAnimated:NO];
    
    self.user = user;
    self.step = 1;
    
    EditCocoaButtonView* ecbv = [EditCocoaButtonView editCocoaButtonViewForAccount:ac];
    ecbv.frame = CGRectMake(0, 55, ecbv.frame.size.width, ecbv.frame.size.height);
    [self.view addSubview:ecbv];
    self.editCocoa = ecbv;
    [ecbv becomeFirstResponder];
        
    UINavigationItem* item = [self.navBar.items firstObject];
    NSString* title = NSLocalizedString(@"add-account-view.title-for-cocoa-button", @"Title: Your Cocoa button");
    item.titleView = [WhiteBlurNavBar titleViewForItemTitle:title];
    [self.navBar setNeedsDisplay];
        
    self.googleBtn.hidden = YES;
    
    [ImapSync allSharedServices:imapSession];
    [user.linkedAccount connect];
}


-(void) findLoginFrom1Password:(id)sender
{
    [[OnePasswordExtension sharedExtension] findLoginForURLString:@"https://putcocoa.in" forViewController:self sender:sender completion:^(NSDictionary *loginDictionary, NSError *error) {
        if (loginDictionary.count == 0) {
            if (error.code != AppExtensionErrorCodeCancelledByUser) {
                NSLog(@"Error invoking 1Password App Extension for find login: %@", error);
            }
            return;
        }
        
        self.email.text = loginDictionary[AppExtensionUsernameKey];
        self.password.text = loginDictionary[AppExtensionPasswordKey];
    }];
}

@end



