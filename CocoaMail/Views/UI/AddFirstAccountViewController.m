//
//  AddFirstAccountViewController.m
//  CocoaMail
//
//  Created by Christopher Hockley on 21/03/16.
//  Copyright © 2016 Christopher Hockley. All rights reserved.
//

#import "AddFirstAccountViewController.h"
#import "Accounts.h"
#import "EditCocoaButtonView.h"
#import <MailCore/MailCore.h>
//#import <Google/SignIn.h>
#import "GTMOAuth2Authentication.h"
#import "GTMOAuth2ViewControllerTouch.h"
#import "UserSettings.h"
#import "SyncManager.h"
#import "AppSettings.h"
#import "Reachability.h"
#import "GlobalDBFunctions.h"
#import "ImapSync.h"
#import "CocoaMail-Swift.h"
#import "OnePasswordExtension.h"
#import "LoginTableViewCell.h"

// 20160731_1356 AJCerier
// Error: "'init' is unavailable"
// Resolution: Added this class extension to make init() availale;
@interface MCOAccountValidator (foo)
- (instancetype) init;
@end

@interface AddFirstAccountViewController () <MailListDelegate>

@property (nonatomic, strong) UserSettings* user;
@property (nonatomic, strong) MCOAccountValidator* accountValidator;


@end


@interface AddFirstAccountViewController () <UITextFieldDelegate/*,GIDSignInUIDelegate*/>

//@property (nonatomic, weak) UITableView* table;
@property (nonatomic, strong) NSArray* settings;

@property (nonatomic, weak) UITextField* email;
@property (nonatomic, weak) UITextField* password;
@property (nonatomic, weak) UIButton* onePassword;

@property (nonatomic, weak) UIButton* googleBtn;
@property (nonatomic, weak) UIView* Ok;


@end

@implementation AddFirstAccountViewController

-(void) viewDidLoad
{
    [super viewDidLoad];
    
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    
    UINavigationItem* item = [[UINavigationItem alloc] initWithTitle:@""];

    self.view.clipsToBounds = NO;

    UIImageView* cocoa = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"background_iphone"]];
    cocoa.frame = CGRectMake(0, -20, screenBounds.size.width, screenBounds.size.height);
    cocoa.contentMode = UIViewContentModeCenter;
    cocoa.clipsToBounds = NO;
    
    [self.view addSubview:cocoa];
    
    //NSString* title = NSLocalizedString(@"add-account-view.title", @"Add account View Title");
    //item.titleView = [WhiteBlurNavBar titleViewForItemTitle:title];
    
    /*UITableView* table = [[UITableView alloc] initWithFrame:CGRectMake(0,
                                                                       20,
                                                                       screenBounds.size.width,
                                                                       242screenBounds.size.height-20)
                                                      style:UITableViewStyleGrouped];
    table.contentInset = UIEdgeInsetsMake(44, 0, 60, 0);
    table.scrollIndicatorInsets = UIEdgeInsetsMake(44, 0, 0, 0);
    table.separatorStyle = UITableViewCellSeparatorStyleNone;
    
    table.backgroundColor = [UIColor clearColor];*/
    
    self.view.backgroundColor = [UIColor clearColor];
    
    //Email
    
    CGFloat WIDTH = screenBounds.size.width;
    CGFloat height = 44;
    
    CGFloat posY = 20;

    UIImage* rBack = [[UIImage imageNamed:@"cell_mail_unread"] resizableImageWithCapInsets:UIEdgeInsetsMake(22, 30, 22, 30)];
    UIImageView* inIV = [[UIImageView alloc] initWithImage:rBack];
    inIV.frame = CGRectMake(8 , posY , WIDTH - 16, height);
    
    UITextField* tf = [[UITextField alloc] initWithFrame:CGRectMake(20, 0, inIV.bounds.size.width - 20, 45)];
    tf.autocorrectionType = UITextAutocorrectionTypeNo;
    tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    
    [inIV addSubview:tf];
    
    self.email = tf;
    self.email.userInteractionEnabled = YES;
    self.email.placeholder = NSLocalizedString(@"add-account-view.email", @"Email");
    self.email.keyboardType = UIKeyboardTypeEmailAddress;
    self.email.returnKeyType = UIReturnKeyNext;
    self.email.delegate = self;
    
    inIV.userInteractionEnabled = YES;
    inIV.clipsToBounds = YES;
    [self.view addSubview:inIV];
    
    //Password
    
    posY = posY + 44 + 10;
    
    UIImageView* pinIV = [[UIImageView alloc] initWithImage:rBack];
    pinIV.frame = CGRectMake(8 , posY , WIDTH - 16, height);
    
    UITextField* ptf = [[UITextField alloc] initWithFrame:CGRectMake(20, 0, inIV.bounds.size.width - 20, 45)];
    ptf.autocorrectionType = UITextAutocorrectionTypeNo;
    ptf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    
    [pinIV addSubview:ptf];
    
    self.password = ptf;
    
    self.password.placeholder = NSLocalizedString(@"account-view.main-details.password", @"Password");
    self.password.secureTextEntry = YES;
    self.password.returnKeyType = UIReturnKeyDone;
    self.password.delegate = self;

    UIButton* fav = [[UIButton alloc] initWithFrame:CGRectMake(inIV.bounds.size.width - 33.f - 5.5, 5.5, 33.F, 33.F)];
    [fav setImage:[UIImage imageNamed:@"onepassword-toolbar"] forState:UIControlStateNormal];
    [fav setImage:[UIImage imageNamed:@"onepassword-toolbar-light"] forState:UIControlStateHighlighted];
    
    fav.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [pinIV addSubview:fav];
    pinIV.userInteractionEnabled = YES;

    self.onePassword = fav;
    [self.onePassword addTarget:self action:@selector(findLoginFrom1Password:) forControlEvents:UIControlEventTouchUpInside];

    self.onePassword.hidden = YES;

    if ([[OnePasswordExtension sharedExtension] isAppExtensionAvailable]) {
        self.onePassword.hidden = NO;
    }
    
    pinIV.clipsToBounds = YES;
    [self.view addSubview:pinIV];
    
    
    posY = posY + 44 + 10;
    
    UIImageView* okinIV = [[UIImageView alloc] initWithImage:rBack];
    okinIV.frame = CGRectMake(8, posY, WIDTH - 16, height);
    
    UITextField* oktf = [[UITextField alloc] initWithFrame:CGRectMake(20, 0, inIV.bounds.size.width - 20, 45)];
    oktf.autocorrectionType = UITextAutocorrectionTypeNo;
    oktf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    oktf.text = NSLocalizedString(@"add-account-view.ok", @"Button: OK");
    oktf.textAlignment = NSTextAlignmentCenter;
    
    oktf.delegate = self;
    
    [okinIV addSubview:oktf];
    okinIV.userInteractionEnabled = YES;
    okinIV.alpha = .5f;
    okinIV.clipsToBounds = YES;
    self.Ok = okinIV;
    [self.view addSubview:okinIV];
    
    //[self.view addSubview:table];
    
    if (self.firstRunMode == NO) {
        item.leftBarButtonItem = [self backButtonInNavBar];
    }
    
    //[self setupSimpleNavBarWith:item andWidth:screenBounds.size.width];
    
    //[self _prepareTable];
    
    //table.scrollEnabled = NO;
    
    //table.dataSource = self;
    //table.delegate = self;
    //self.table = table;
    
    CGFloat posYbutton = screenBounds.size.height - 20 - (70 + 45);
    
    UITapGestureRecognizer* tgr = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_tap:)];
    [self.view addGestureRecognizer:tgr];
    self.view.userInteractionEnabled = YES;
    
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
    [self.view endEditing:YES];
}

#define TITLE @"title"
#define CONTENT @"content"

#define TEXT @"t"
#define DACTION @"da"

-(void) _prepareTable
{
    
    NSArray* infos = @[
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
    //self.table.delegate = nil;
    //self.table.dataSource = nil;
}

-(void) _nextStep
{
        self.email.text = [self.email.text stringByReplacingOccurrencesOfString:@" " withString:@""];
        self.password.text = [self.password.text stringByReplacingOccurrencesOfString:@" " withString:@""];
        
        [self loadAccountWithUsername:self.email.text password:self.password.text oauth2Token:nil];
}

#pragma mark - TextField delegate

-(BOOL) textFieldShouldReturn:(UITextField*)textField
{
    [textField resignFirstResponder];
    
    if (textField == self.email) {
        [self.password becomeFirstResponder];
    }
    else if (textField == self.password) {
        [self _nextStep];
    }
    
    return YES;
}

- (BOOL)textFieldShouldBeginEditing:(UITextField *)textField
{
    if (textField != self.email && textField != self.password) {
        [self _hideKeyboard];
        [self _nextStep];
        return NO;
    }
    
    return YES;
}

- (BOOL)textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
{
    if (self.password.text.length > 4 && [self isEmailRegExp:self.email.text]) {
        [self.Ok setAlpha:1.];
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
    self.accountValidator = [[MCOAccountValidator alloc] init];
    self.accountValidator.username = username;
    self.accountValidator.password = password;
    
    if (oauth2Token) {
        self.accountValidator.email = username;
        self.accountValidator.OAuth2Token = oauth2Token;
    }
    
    [self load];
}

-(void) load
{
    // If we do not have an OAuth 2 Token ...
    if (!self.accountValidator.OAuth2Token) {
        
        DDLogInfo(@"No OAuth 2 Token");
        
        NSString* email = self.email.text;
        NSString* password = self.password.text;
        
        if (!email.length || !password.length) {
            DDLogWarn(@"No Email Address or no Password.");
            return;
        }
        
        if (![self isEmailRegExp:email]) {
            DDLogInfo(@"Invalid Email Address structure.");
            
            [ViewController presentAlertWIP:NSLocalizedString(@"add-account-view.error.invalid-email", @"Alert message: Invalid Email")];
            return;
        }
    }
    
    
    
    Reachability* networkReachability = [Reachability reachabilityForInternetConnection];
    NetworkStatus networkStatus = [networkReachability currentReachabilityStatus];
    
    if (networkStatus == NotReachable) {
        DDLogWarn(@"Network Not Reachable.");
        
        [ViewController presentAlertWIP:NSLocalizedString(@"add-account-view.error.no-internet", @"Alert message: Not connected to Internet")];
        return;
    }
    
    AddFirstAccountViewController* __weak bself = self;
    
    [PKHUD sharedHUD].userInteractionOnUnderlyingViewsEnabled = FALSE;
    [PKHUD sharedHUD].contentView = [[PKHUDTextView alloc]initWithText:NSLocalizedString(@"add-account-view.loading-hud.fetching-settings", @"HUD Message: Fetching settings...")];
    [[PKHUD sharedHUD] showOnView:nil];
    
    [MCOMailProvidersManager sharedManager];
    
    [self.accountValidator setImapEnabled:YES];
    [self.accountValidator setSmtpEnabled:YES];
    
    DDLogInfo(@"Starting Account Validation.");

    [self.accountValidator start:^() {
        
        AddFirstAccountViewController* strongSelf = bself;
        
        if (!strongSelf.accountValidator.imapError && !strongSelf.accountValidator.smtpError) {
            DDLogInfo(@"Email Address and Password Validated.");
            [strongSelf saveSettings];
        }
        else {
            DDLogError(@"Error loading imap account: %@", strongSelf.accountValidator.imapError);
            DDLogError(@"Error loading smtp account: %@", strongSelf.accountValidator.smtpError);
            
            [[PKHUD sharedHUD] hideWithAnimated:YES completion:nil];
            
            BOOL authenticationError =
            ( strongSelf.accountValidator.imapError.code == MCOErrorAuthentication ||
              strongSelf.accountValidator.smtpError.code == MCOErrorAuthentication );
            
            if ( authenticationError ) {
                
                DDLogError(@"Account IMAP or SMTP Authentication Error");
                
                [ViewController presentAlertOk:NSLocalizedString(@"add-account-view.error.wrong-credentials", @"Alert message: Wrong credentials")];
                
            }
            else if(strongSelf.accountValidator.imapError.code == MCOErrorConnection ||
                    strongSelf.accountValidator.smtpError.code == MCOErrorConnection)  {
                
                
                if (networkStatus != NotReachable) {
                    
                    DDLogError(@"Account IMAP or SMTP Connection Error - Network Not Reachable.");
                    
                    [ViewController presentAlertOk:NSLocalizedString(@"add-account-view.error.try-again",@"There was an issue connecting. Please try to login again.")];//NSLocalizedString(@"add-account-view.error.no-server-settings", @"Unknown Server Settings")];
                }
                else {
                    
                    DDLogError(@"Account IMAP or SMTP Connection Error - Issue Unknown.");

                    [ViewController presentAlertOk:NSLocalizedString(@"add-account-view.error.no-internet",@"Connection error. There seems to be not internet connection.")];//NSLocalizedString(@"add-account-view.error.no-server-settings", @"Unknown Server Settings")];
                }
            }
            else if (strongSelf.accountValidator.imapError.code == MCOErrorGmailApplicationSpecificPasswordRequired ||
                     strongSelf.accountValidator.smtpError.code == MCOErrorGmailApplicationSpecificPasswordRequired) {
                
                DDLogError(@"Account IMAP or SMTP Gmail Password Error");

                [ViewController presentAlertOk:NSLocalizedString(@"add-account-view.error.try-again",@"There was an issue connecting. Please try to login again.")];
            }
            else {
                
                DDLogError(@"Account IMAP or SMTP Error - Mail Provider Not Supported.");

                [ViewController presentAlertOk:NSLocalizedString(@"add-account-view.error.email-not-supported", @"Alert message: This email provider is not supported")];
            }
        }
    }];
}

-(void) saveSettings
{
    DDLogDebug(@"2 - Start setting Folders (saveSettings)");
    
    [PKHUD sharedHUD].contentView = [[PKHUDTextView alloc]initWithText:NSLocalizedString(@"add-account-view.loading-hud.account-in-config", @"HUD Message: Account Configuration...")];
    [[PKHUD sharedHUD] showOnView:nil];
    
    MCOIMAPSession* imapSession = [[MCOIMAPSession alloc] init];
    
    imapSession.hostname = self.accountValidator.imapServer.hostname;
    imapSession.port = self.accountValidator.imapServer.port;
    imapSession.username = self.accountValidator.username ;
    imapSession.password = self.accountValidator.password;
    
    if (self.accountValidator.OAuth2Token) {
        imapSession.OAuth2Token = self.accountValidator.OAuth2Token;
        imapSession.authType = MCOAuthTypeXOAuth2;
    }
    imapSession.connectionType = self.accountValidator.imapServer.connectionType;
    
    MCOIMAPFetchNamespaceOperation* namespaceOp = [imapSession fetchNamespaceOperation];
    [namespaceOp start:^(NSError* error, NSDictionary* namespaces) {
        if (error) {
            DDLogError(@"MCOIMAPFetchNamespaceOperation Error: %@", error.description);
            [[PKHUD sharedHUD] hideWithAnimated:YES completion:nil];
            
            return ;
        }
        
        MCOIMAPNamespace*  nameSpace = namespaces[MCOIMAPNamespacePersonal];
        [imapSession setDefaultNamespace:nameSpace];
        
        MCOIMAPFetchFoldersOperation*  op = [imapSession fetchAllFoldersOperation];
        [op start:^(NSError*  error, NSArray* folders) {
            
            DDLogInfo(@"Getting IMAP Folders.");
            
            if (error) {
                DDLogError(@"MCOIMAPFetchFoldersOperation Error: %@", error.description);
                [[PKHUD sharedHUD] hideWithAnimated:YES completion:nil];
                
                return ;
            }
            
            MCOMailProvider* accountProvider = [[MCOMailProvidersManager sharedManager] providerForIdentifier:self.accountValidator.identifier];
            
            NSMutableArray* flagedFolders = [[NSMutableArray alloc] init];
            NSMutableArray* otherFolders = [[NSMutableArray alloc] init];
            MCOIMAPFolder*  __block inboxfolder;
            MCOIMAPFolder*  __block allMailFolder;
            
            DDLogDebug(@"Processing %ld folders:",(long)[folders count]);
            
            for (MCOIMAPFolder* folder in folders) {
                
                if (folder.flags & MCOIMAPFolderFlagNoSelect) {
                    DDLogDebug(@"Folder flags includes MCOIMAPFolderFlagNoSelect");
                    continue;
                }
                
                NSString* folderName = [ImapSync displayNameForFolder:folder usingSession:imapSession];
                DDLogInfo(@"Folder Path = \"%@\", Folder Name = \"%@\"",folder.path,folderName);

                if (folder.flags & MCOIMAPFolderFlagInbox || [folderName  isEqualToString: @"INBOX"]) {
                    DDLogVerbose(@"Folder is INBOX");
                    inboxfolder = folder;
                }
                else if ([accountProvider.allMailFolderPath isEqualToString:folderName] || folder.flags & MCOIMAPFolderFlagAll || folder.flags & MCOIMAPFolderFlagAllMail || [@"Archive" isEqualToString:folderName]) {
                    DDLogVerbose(@"Folder is ALL MAIL FOLDER");
                    allMailFolder = folder;
                }
                else if (![@(folder.flags) isEqualToNumber:@0]) {
                    DDLogVerbose(@"Folder is FLAGGED (%ld)",(long)folder.flags);
                    [flagedFolders addObject:folder];
                }
                else {
                    DDLogVerbose(@"Folder is of some OTHER type");
                    [otherFolders addObject:folder];
                }
            }
            
            NSString*  __block newAllMail = @"Archive";
            
            if (!allMailFolder) {
                
                //Create folder
                MCOIMAPOperation*  op = [imapSession createFolderOperation:newAllMail];
                [op start:^(NSError*  error) {
                    
                    DDLogInfo(@"Creating All Mail Folder on IMAP Server");
                    
                    if (!error) {
                        
                        DDLogInfo(@"Getting IMAP Folders (again).");
                        
                        MCOIMAPFetchFoldersOperation*  op = [imapSession fetchAllFoldersOperation];
                        [imapSession setDefaultNamespace:nameSpace];
                        
                        [op start:^(NSError*  error, NSArray* folders) {
                            
                            DDLogDebug(@"Processing %ld IMAP folders:",(long)[folders count]);

                            for (MCOIMAPFolder* folder in folders) {
                                
                                if (folder.flags & MCOIMAPFolderFlagNoSelect) {
                                    DDLogInfo(@"Folder has NO flags.");
                                    continue;
                                }
                                
                                NSString* folderName = [ImapSync displayNameForFolder:folder usingSession:imapSession];
                                DDLogInfo(@"Folder Path = \"%@\", Folder Name = \"%@\"",folder.path,folderName);

                                if (folder.flags & MCOIMAPFolderFlagInbox || [folderName  isEqualToString: @"INBOX"]) {
                                    DDLogInfo(@"Folder is INBOX");
                                    inboxfolder = folder;
                                }
                                else if ([accountProvider.allMailFolderPath isEqualToString:folderName] || folder.flags & MCOIMAPFolderFlagAll || folder.flags & MCOIMAPFolderFlagAllMail || [newAllMail isEqualToString:folderName]) {
                                    DDLogInfo(@"Folder is ALL MAIL FOLDER");

                                    allMailFolder = folder;
                                }
                                else if (![@(folder.flags) isEqualToNumber:@0]) {
                                    DDLogInfo(@"Folder is FLAGGED (%ld)",(long)folder.flags);

                                    [flagedFolders addObject:folder];
                                }
                                else {
                                    DDLogVerbose(@"Folder is of some OTHER type");
                                    [otherFolders addObject:folder];
                                }
                            }
                            [self _finishFoldersFlaged:flagedFolders others:otherFolders inbox:inboxfolder all:allMailFolder imapSession:imapSession];
                        }];
                    }
                    else {
                        DDLogWarn(@"[AddFirstAccountViewController saveSettings:]");
                        DDLogWarn(@"      Failed to create folder \"Archive\", NSError = %@",[error description]);
                        
                        //Account not supported
                        [[PKHUD sharedHUD] hideWithAnimated:YES completion:nil];
                        [ViewController presentAlertWIP:NSLocalizedString(@"add-account-view.error.email-not-supported", @"Alert Message: This email provider is not supported")];
                    }
                }];
            }
            else {
                DDLogInfo(@"Have All Mail folder.");
                
                [self _finishFoldersFlaged:flagedFolders others:otherFolders inbox:inboxfolder all:allMailFolder imapSession:imapSession];
            }
        }];
    }];
}

// MARK: - _finishFoldersFlaged

-(void) _finishFoldersFlaged:(NSMutableArray*)flagedFolders others:(NSMutableArray*)otherFolders inbox:(MCOIMAPFolder*)inboxfolder all:(MCOIMAPFolder*)allMailFolder imapSession:(MCOIMAPSession*)imapSession
{
    DDLogDebug(@"3 - Finish Folders");
    
    UserSettings *user = [self _createUserSettings];
    
    Account *account = [self _addFirstAccount:user];
    
    //Folder Settings
    
    // Store the folder path delimiter character and folder path prefix (if any) into user settings.
    user.folderPathDelimiter = [NSString stringWithFormat:@"%c" , imapSession.defaultNamespace.mainDelimiter];
    user.folderPathPrefix    = imapSession.defaultNamespace.mainPrefix;
    
    NSSortDescriptor* pathDescriptor = [[NSSortDescriptor alloc] initWithKey:NSStringFromSelector(@selector(path))
                                                                   ascending:YES
                                                                    selector:@selector(caseInsensitiveCompare:)];
    
    // Create a sorted array of all folders
    NSMutableArray* sortedImapFolders = [[NSMutableArray alloc] init];
    [sortedImapFolders addObject:inboxfolder];
    [sortedImapFolders addObjectsFromArray:[flagedFolders sortedArrayUsingDescriptors:@[pathDescriptor]]];
    [sortedImapFolders addObjectsFromArray:[otherFolders sortedArrayUsingDescriptors:@[pathDescriptor]]];
    [sortedImapFolders addObject:allMailFolder];
    
    
    NSMutableArray* dispNamesFolders = [[NSMutableArray alloc] initWithCapacity:1];
    
    [[SyncManager getSingleton] addAccountState];
    
    ImapSync *imapSync = [ImapSync sharedServices:user];
    DDAssert(imapSync, @"imapSync must exist.");
    
    MCOMailProvider* accountProvider = [[MCOMailProvidersManager sharedManager] providerForIdentifier:user.identifier];
    
    // Store Special Folder indecies into UserSettings and Collect all Folder Names
    int imapFolderIndex = 0;
    for (MCOIMAPFolder* folder in sortedImapFolders) {
        
        // If this folder is a "special" folder, then store its index into the UserSettings
        
        NSString *folderName = [ImapSync displayNameForFolder:folder usingSession:imapSession];
        DDLogInfo(@"Folder Path = \"%@\", Folder Name = \"%@\"",folder.path,folderName);

        // TODO: This looks like a speed optimisation opportunity
        
        //Inbox
        if ((folder.flags == MCOIMAPFolderFlagInbox) || [folderName  isEqualToString: @"INBOX"]) {
            [user setImportantFolderNum:imapFolderIndex forBaseFolder:FolderTypeInbox];
        } //Starred
        else if( ( accountProvider.starredFolderPath && [accountProvider.starredFolderPath isEqualToString:folderName] )
                 || (folder.flags == MCOIMAPFolderFlagFlagged)) {
            [user setImportantFolderNum:imapFolderIndex forBaseFolder:FolderTypeFavoris];
        } //Sent
        else if([accountProvider.sentMailFolderPath isEqualToString:folderName] || (folder.flags == MCOIMAPFolderFlagSentMail)) {
            [user setImportantFolderNum:imapFolderIndex forBaseFolder:FolderTypeSent];
        } //Draft
        else if([accountProvider.draftsFolderPath isEqualToString:folderName] || (folder.flags == MCOIMAPFolderFlagDrafts)) {
            [user setImportantFolderNum:imapFolderIndex forBaseFolder:FolderTypeDrafts];
        } //Archive
        else if([accountProvider.allMailFolderPath isEqualToString:folderName] || ((folder.flags == MCOIMAPFolderFlagAll) || (folder.flags == MCOIMAPFolderFlagAllMail)) || [allMailFolder.path isEqualToString:folderName]) {
            [user setImportantFolderNum:imapFolderIndex forBaseFolder:FolderTypeAll];
        } //Trash
        else if([accountProvider.trashFolderPath isEqualToString:folderName] || (folder.flags == MCOIMAPFolderFlagTrash)) {
            [user setImportantFolderNum:imapFolderIndex forBaseFolder:FolderTypeDeleted];
        } //Spam
        else if([accountProvider.spamFolderPath isEqualToString:folderName] || (folder.flags == MCOIMAPFolderFlagSpam)) {
            [user setImportantFolderNum:imapFolderIndex forBaseFolder:FolderTypeSpam];
        }
        
        NSString *dispName = [ImapSync displayNameForFolder:folder usingSession:imapSession];
        
        DDAssert(dispName, @"Display Name must exist.");
        
        [dispNamesFolders addObject:dispName];
        
        [imapSync addFolder:folder withName:dispName toAccount:user.accountNum];
        
        imapFolderIndex++;
    }
    
    // If no Favorites Folder was found ...
    if ([user numFolderWithFolder:CCMFolderTypeFavoris] == -1) {
        // Create one
        [user setImportantFolderNum:[user numFolderWithFolder:CCMFolderTypeAll] forBaseFolder:FolderTypeFavoris];
    }
    
    // Store Sorted Folder Names into UserSettings
    [user setAllFoldersDisplayNames:dispNamesFolders];
    
    account.userFolders = [account userFolderNames];
    
    [[Accounts sharedInstance] addAccount:account];
    
    DDLogDebug(@"4 - Go!");
    
    [PKHUD sharedHUD].contentView = [[PKHUDTextView alloc]initWithText:NSLocalizedString(@"add-account-view.loading-hud.fetching-emails", @"HUD Message: Fetching first emails")];
    [[PKHUD sharedHUD] showOnView:nil];
    
    self.user = user;
    self.googleBtn.hidden = YES;
    
    [ImapSync allSharedServices:imapSession];
    
    // Connect to the server
    [account connect];
    
    [Accounts sharedInstance].currentAccountIdx = self.user.accountIndex;
    
    [ViewController refreshCocoaButton];
    
    account.mailListSubscriber = self;
    
    [account refreshCurrentFolder];
}

- (UserSettings *)_createUserSettings
{
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
    
    // Create User Code for UI
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
    
    [AppSettings setSettingsWithAccountVal:self.accountValidator user:user];
    
    return user;
}

- (Account *)_addFirstAccount:(UserSettings *)user
{
    // Create Account object for user
    Account* ac = [Account emptyAccount];
    
    [ac setNewUser:user];
    
    ac.person = [Person createWithName:user.name email:user.username icon:nil codeName:user.initials];
    
    DDLogVerbose(@"Adding first Account:\n%@",[ac description]);
 
    return ac;
}

// MARK: -



-(void) serverSearchDone:(BOOL)done
{
    if (done) {
        [[PKHUD sharedHUD] hideWithAnimated:NO completion:nil];

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

-(UIStatusBarStyle)preferredStatusBarStyle{
    return UIStatusBarStyleLightContent;
}

-(void) insertConversationIndex:(ConversationIndex*)ci
{
    DDLogWarn(@"Called empty function!");
}

- (void)updateDays:(NSArray *)days
{
    DDLogWarn(@"Called empty function!");
}

@end

