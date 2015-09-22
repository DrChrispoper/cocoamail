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
@property (nonatomic, strong) MCOAccountValidator *accountVal;

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

- (void)viewDidLoad {
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
    
    NSString* title = NSLocalizedString(@"Add account", @"Add account");
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
    
    CGFloat posYbutton = screenBounds.size.height - 20 - (70+45);
    cocoa.frame = CGRectMake(0, 242, screenBounds.size.width, posYbutton + 35 - 242);
    cocoa.contentMode = UIViewContentModeCenter;
    
    [self.view addSubview:cocoa];
    
    UITapGestureRecognizer* tgr = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_tap:)];
    [cocoa addGestureRecognizer:tgr];
    cocoa.userInteractionEnabled = YES;
    
    UIButton* google = [[UIButton alloc] initWithFrame:CGRectMake(0, posYbutton, screenBounds.size.width, 70+45)];
    [google setImage:[UIImage imageNamed:@"signGoogle_on"] forState:UIControlStateNormal];
    [google setImage:[UIImage imageNamed:@"signGoogle_off"] forState:UIControlStateHighlighted];
    [google addTarget:self action:@selector(_google:) forControlEvents:UIControlEventTouchUpInside];
    
    [self.view addSubview:google];
    self.googleBtn = google;
}

- (void)viewDidAppear:(BOOL)animated
{
    NSThread *driverThread = [[NSThread alloc] initWithTarget:self selector:@selector(loadIt) object:nil];
    [driverThread start];
    return;
}

- (void)loadIt
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
    [[GIDSignIn sharedInstance] signIn];
}

-(void) _hideKeyboard
{
    [self.table endEditing:YES];
}


#define TITLE @"title"
#define CONTENT @"content"

#define TEXT @"t"
#define DACTION @"da"

-(void)_prepareTable
{
    
    NSArray* infos = @[
                       @{TEXT: @"Username", DACTION : @"EDIT_NAME"},
                       @{TEXT: @"Email", DACTION : @"EDIT_MAIL"},
                       @{TEXT: @"Password", DACTION : @"EDIT_PASS"}
                       ];
    
    NSDictionary* Paccounts = @{TITLE:@"", CONTENT:infos};
    
    NSString* tDelete = NSLocalizedString(@"OK", @"OK");
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


-(NSInteger) numberOfSectionsInTableView:(UITableView *)tableView
{
    return self.settings.count;
}

-(NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    NSDictionary* sectionInfos = self.settings[section];
    NSArray* content = sectionInfos[CONTENT];
    
    return content.count;
}

-(CGFloat) tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
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



-(UITableViewCell*) tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    
    NSDictionary* sectionInfos = self.settings[indexPath.section];
    NSArray* content = sectionInfos[CONTENT];
    NSDictionary* infoCell = content[indexPath.row];
    
    
    UITableViewCell* cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"noID"];
    
    
    cell.textLabel.text = infoCell[TEXT];
    
    cell.textLabel.textAlignment = NSTextAlignmentNatural;
    cell.textLabel.textColor = [UIColor blackColor];
    
    cell.accessoryType = UITableViewCellAccessoryNone;
    
    
    CGSize bounds = tableView.bounds.size;
    bounds.height = 44.f;
    
    
    NSString* action = infoCell[DACTION];

    if ([action isEqualToString:@"VALIDATE"]) {
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = [UIGlobal standardBlue];
    }
    else {
        
        UITextField* tf = [[UITextField alloc] initWithFrame:CGRectMake(100, 0, bounds.width - 110, bounds.height)];
        tf.delegate = self;
        [cell addSubview:tf];
        
        tf.autocorrectionType = UITextAutocorrectionTypeNo;
        tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
        
        
        if ([action isEqualToString:@"EDIT_PASS"]) {
            tf.secureTextEntry = YES;
            self.password = tf;
            //self.password.text = @"Qserghuilm7";
        }
        else if ([action isEqualToString:@"EDIT_MAIL"]) {
            tf.keyboardType = UIKeyboardTypeEmailAddress;
            self.email = tf;
            //self.email.text = @"105942@supinfo.com";
        }
        else {
            tf.autocapitalizationType = UITextAutocapitalizationTypeWords;
            self.username = tf;
            //self.username.text = @"Supinfo Chris";
        }
    }
    
    cell.selectionStyle = UITableViewCellSelectionStyleGray;
    
    return cell;
}

-(NSString*)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    NSDictionary* sectionInfos = self.settings[section];
    return sectionInfos[TITLE];
}


#pragma mark Table Delegate

-(CGFloat) tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{
    return CGFLOAT_MIN;
}

-(CGFloat) tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
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
        
        [[Accounts sharedInstance].currentAccount setCurrentFolder:FolderTypeWith(FolderTypeInbox, 0)];
        
        [self loadFirstInboxEmails];
        
        /*}else if ([Accounts sharedInstance].accounts.count > 2) {
            [Accounts sharedInstance].currentAccountIdx = self.account.accountIdx;
            [self.account initContent];
            [ViewController refreshCocoaButton];
        }*/
        
        [[NSNotificationCenter defaultCenter] postNotificationName:kBACK_NOTIFICATION object:nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:kACCOUNT_CHANGED_NOTIFICATION object:nil];
    }
    
}


-(NSIndexPath*) tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath
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

-(void) tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

#pragma mark - TextField delegate

-(BOOL) textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    return YES;
}



- (BOOL)isEmailRegExp:(NSString *)text
{
    NSError *error = NULL;
    NSString *pattern = @"[a-z0-9!#$%&'*+/=?^_`{|}~-]+(?:\\.[a-z0-9!#$%&'*+/=?^_`{|}~-]+)*@(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\\.)+[a-z0-9](?:[a-z0-9-]*[a-z0-9])?";
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:&error];
    if (error) {
        CCMLog(@"%@",error.description);
    }
    return [regex matchesInString:text options:NSMatchingReportProgress range:NSMakeRange(0, text.length)].count;
}

- (void) receiveToggleAuthUINotification:(NSNotification *) notification {
    if ([[notification name] isEqualToString:@"ToggleAuthUINotification"]) {

        NSString *accessToken = [notification userInfo][@"accessToken"];;
        NSString *email = [notification userInfo][@"email"];
        NSString *name = [notification userInfo][@"name"];
    
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

- (void)loadWithEmail:(NSString *)username pwd:(NSString*)password
{
    self.accountVal = [[MCOAccountValidator alloc]init];
    self.accountVal.username = username;
    self.accountVal.password = password;
    [self load];
}

- (void)load
{
    
    if(!self.accountVal.OAuth2Token){
        NSString *email = self.email.text;
        NSString *password = self.password.text;
    
        if (!email.length || !password.length) {
            return;
        }
    
        if (![self isEmailRegExp:email]) {
            [ViewController presentAlertWIP:@"Invalid Email"];
            return;
        }
    }
    
    Reachability *networkReachability = [Reachability reachabilityForInternetConnection];
    NetworkStatus networkStatus = [networkReachability currentReachabilityStatus];
    if (networkStatus == NotReachable) {
        [ViewController presentAlertWIP:@"Not connected to Internet"];
    }
    
    AddAccountViewController* __weak bself = self;
    
    [PKHUD sharedHUD].userInteractionOnUnderlyingViewsEnabled = FALSE;
    [PKHUD sharedHUD].contentView = [[PKHUDTextView alloc]initWithText:@"Fetching settings..."];
    [[PKHUD sharedHUD] show];
    
    [MCOMailProvidersManager sharedManager];
    
    [self.accountVal start:^() {
        AddAccountViewController *strongSelf = bself;
        
        if (!strongSelf.accountVal.imapError && !strongSelf.accountVal.smtpError) {
            [strongSelf saveSettings];
        } else {
            CCMLog(@"error loading imap account: %@", strongSelf.accountVal.imapError);
            CCMLog(@"error loading smtp account: %@", strongSelf.accountVal.smtpError);
            if (strongSelf.accountVal.imapError.code == MCOErrorAuthentication) {
                [[PKHUD sharedHUD] hideWithAnimated:YES];
                [ViewController presentAlertWIP:@"Wrong credentials"];
                
            }
            else if(strongSelf.accountVal.imapError.code == MCOErrorNoValidServerFound)  {
                [[PKHUD sharedHUD] hideWithAnimated:YES];
                [ViewController presentAlertWIP:@"Unknown Server Settings"];
            }
            else {
                [[PKHUD sharedHUD] hideWithAnimated:YES];
                [ViewController presentAlertWIP:@"This email provider is not supported"];
            }
            //[[PKHUD sharedHUD] hideWithAnimated:YES];
        }
    }];
}

- (void)saveSettings
{
    CCMLog(@"2 - Start saving settings");
    
    NSInteger newAccountNum = [Accounts sharedInstance].accounts.count;
    
    CCMLog(@"3 - Start setting Folders");
    
    [PKHUD sharedHUD].contentView = [[PKHUDTextView alloc]initWithText:@"Account Configuration..."];
    [[PKHUD sharedHUD] show];
    
    [AppSettings setSettingsWithAccountVal:self.accountVal accountNum:newAccountNum];
    MCOIMAPSession *imapSession = [AppSettings imapSession:newAccountNum];
    
    MCOIMAPFetchNamespaceOperation *namespaceOp = [imapSession fetchNamespaceOperation];
    [namespaceOp start:^(NSError *error, NSDictionary *namespaces) {
        if (error) {
            CCMLog(@"%@",error.description);
            [[PKHUD sharedHUD] hideWithAnimated:YES];
            return ;
        }
        
        MCOIMAPNamespace * nameSpace = namespaces[MCOIMAPNamespacePersonal];
        MCOMailProvider *accountProvider = [[MCOMailProvidersManager sharedManager] providerForIdentifier:[AppSettings identifier:newAccountNum]];
        MCOIMAPFetchFoldersOperation * op = [imapSession fetchAllFoldersOperation];
        [imapSession setDefaultNamespace:nameSpace];
        
        [op start:^(NSError * error, NSArray *folders) {
            if (error) {
                CCMLog(@"%@",error.description);
                [[PKHUD sharedHUD] hideWithAnimated:YES];
                return ;
            }
    
                [[SyncManager getSingleton] addAccountState];
            
                [ImapSync allSharedServices:imapSession];

                [AppSettings setName:self.username.text accountNum:newAccountNum];
                
                [AppSettings setFirstSync:YES];
                [AppSettings setSignature:@"Sweet love sent from the Cocoamail app!" accountNum:newAccountNum];
                
                [AppSettings setBadgeCount:0];
                [AppSettings setNotifications:YES];
                [AppSettings setDataInitVersion];
                [AppSettings setActiveAccount:newAccountNum];
            
            if(newAccountNum == 1){
                [AppSettings setDefaultAccount:1];
            }
                
            
            
            NSMutableArray *flagedFolders = [[NSMutableArray alloc] init];
            NSMutableArray *otherFolders = [[NSMutableArray alloc] init];
            MCOIMAPFolder * __block inboxfolder;
            MCOIMAPFolder * __block allMailFolder;
            
            for (MCOIMAPFolder *folder in folders) {

                if(folder.flags & MCOIMAPFolderFlagNoSelect)
                    continue;
                
                if (folder.flags & MCOIMAPFolderFlagInbox || [folder.path  isEqualToString: @"INBOX"]) {
                    inboxfolder = folder;
                }
                else if ([accountProvider.allMailFolderPath isEqualToString:folder.path] ||
                         folder.flags & MCOIMAPFolderFlagAll ||
                         folder.flags & MCOIMAPFolderFlagAllMail ||
                         [@"Archive" isEqualToString:folder.path])
                {
                    allMailFolder = folder;
                }
                else if (![@(folder.flags) isEqualToNumber:@0]) {
                    [flagedFolders addObject:folder];
                }
                else{
                    [otherFolders addObject:folder];
                }
            }
            
            NSString * __block newAllMail = @"Archive";
            
            if (!allMailFolder) {
                //Create folder
                MCOIMAPOperation * op = [imapSession createFolderOperation:newAllMail];
                [op start:^(NSError * error) {
                    if (!error) {
                        
                        MCOIMAPFetchFoldersOperation * op = [imapSession fetchAllFoldersOperation];
                        [imapSession setDefaultNamespace:nameSpace];
                        
                        [op start:^(NSError * error, NSArray *folders) {
                            
                            for (MCOIMAPFolder *folder in folders) {
                                
                                if(folder.flags & MCOIMAPFolderFlagNoSelect)
                                    continue;
                                
                                if (folder.flags & MCOIMAPFolderFlagInbox || [folder.path  isEqualToString: @"INBOX"]) {
                                    inboxfolder = folder;
                                }
                                else if ([accountProvider.allMailFolderPath isEqualToString:folder.path] ||
                                         folder.flags & MCOIMAPFolderFlagAll ||
                                         folder.flags & MCOIMAPFolderFlagAllMail ||
                                         [newAllMail isEqualToString:folder.path])
                                {
                                    allMailFolder = folder;
                                }
                                else if (![@(folder.flags) isEqualToNumber:@0]) {
                                    [flagedFolders addObject:folder];
                                }
                                else{
                                    [otherFolders addObject:folder];
                                }
                            }
                            [self finishFoldersFlaged:flagedFolders others:otherFolders inbox:inboxfolder all:allMailFolder imapSession:imapSession accountNum:newAccountNum];
                        }];
                    }
                    else {
                        //Account not supported
                        [[PKHUD sharedHUD] hideWithAnimated:YES];
                        [ViewController presentAlertWIP:@"This email provider is not supported"];
                    }
                }];
            }
            else {
                [self finishFoldersFlaged:flagedFolders others:otherFolders inbox:inboxfolder all:allMailFolder imapSession:imapSession accountNum:newAccountNum];
            }
        }];
    }];
}

- (void)finishFoldersFlaged:(NSMutableArray *)flagedFolders others:(NSMutableArray *)otherFolders inbox:(MCOIMAPFolder *)inboxfolder all:(MCOIMAPFolder *)allMailFolder imapSession:(MCOIMAPSession *)imapSession accountNum:(NSInteger)newAccountNum
{
    CCMLog(@"4 - Finish Folders");
    
    SyncManager *sm = [SyncManager getSingleton];
    
    MCOMailProvider *accountProvider = [[MCOMailProvidersManager sharedManager] providerForIdentifier:[AppSettings identifier:newAccountNum]];
    
    NSSortDescriptor *pathDescriptor = [[NSSortDescriptor alloc] initWithKey:NSStringFromSelector(@selector(path)) ascending:YES selector:@selector(caseInsensitiveCompare:)];
    NSMutableArray *sortedFolders = [[NSMutableArray alloc] init];
    [sortedFolders addObject:inboxfolder];
    [sortedFolders addObjectsFromArray:[flagedFolders sortedArrayUsingDescriptors:@[pathDescriptor]]];
    [sortedFolders addObjectsFromArray:[otherFolders sortedArrayUsingDescriptors:@[pathDescriptor]]];
    [sortedFolders addObject:allMailFolder];
    
    int indexPath = 0;
    
    NSMutableArray *dispNamesFolders = [[NSMutableArray alloc] initWithCapacity:1];
    
    [AppSettings setImportantFolderNum:-1 forBaseFolder:FolderTypeInbox forAccount:newAccountNum];
    [AppSettings setImportantFolderNum:-1 forBaseFolder:FolderTypeFavoris forAccount:newAccountNum];
    [AppSettings setImportantFolderNum:-1 forBaseFolder:FolderTypeSent forAccount:newAccountNum];
    [AppSettings setImportantFolderNum:-1 forBaseFolder:FolderTypeDrafts forAccount:newAccountNum];
    [AppSettings setImportantFolderNum:-1 forBaseFolder:FolderTypeAll forAccount:newAccountNum];
    [AppSettings setImportantFolderNum:-1 forBaseFolder:FolderTypeDeleted forAccount:newAccountNum];
    [AppSettings setImportantFolderNum:-1 forBaseFolder:FolderTypeSpam forAccount:newAccountNum];
    
    for(MCOIMAPFolder* folder in sortedFolders) {

        //Inbox
        if ((folder.flags == MCOIMAPFolderFlagInbox) || [folder.path  isEqualToString: @"INBOX"]) {
            [AppSettings setImportantFolderNum:indexPath forBaseFolder:FolderTypeInbox forAccount:newAccountNum];
        }
        //Starred
        else if([accountProvider.starredFolderPath isEqualToString:folder.path] || (folder.flags == MCOIMAPFolderFlagFlagged))
        {
            [AppSettings setImportantFolderNum:indexPath forBaseFolder:FolderTypeFavoris forAccount:newAccountNum];
        }
        //Sent
        else if([accountProvider.sentMailFolderPath isEqualToString:folder.path] || (folder.flags == MCOIMAPFolderFlagSentMail))
        {
            [AppSettings setImportantFolderNum:indexPath forBaseFolder:FolderTypeSent forAccount:newAccountNum];
        }
        //Draft
        else if([accountProvider.draftsFolderPath isEqualToString:folder.path] || (folder.flags == MCOIMAPFolderFlagDrafts))
        {
            [AppSettings setImportantFolderNum:indexPath forBaseFolder:FolderTypeDrafts forAccount:newAccountNum];
        }
        //Archive
        else if([accountProvider.allMailFolderPath isEqualToString:folder.path] || ((folder.flags == MCOIMAPFolderFlagAll) || (folder.flags == MCOIMAPFolderFlagAllMail)) || [allMailFolder.path isEqualToString:folder.path])
        {
            [AppSettings setImportantFolderNum:indexPath forBaseFolder:FolderTypeAll forAccount:newAccountNum];
        }
        //Trash
        else if([accountProvider.trashFolderPath isEqualToString:folder.path] || (folder.flags == MCOIMAPFolderFlagTrash))
        {
            [AppSettings setImportantFolderNum:indexPath forBaseFolder:FolderTypeDeleted forAccount:newAccountNum];
        }
        //Spam
        else if([accountProvider.spamFolderPath isEqualToString:folder.path] || (folder.flags == MCOIMAPFolderFlagSpam))
        {
            [AppSettings setImportantFolderNum:indexPath forBaseFolder:FolderTypeSpam forAccount:newAccountNum];
        }
        
        NSString* dispName = [[[imapSession defaultNamespace] componentsFromPath:[folder path]] componentsJoinedByString:@"/"];
        [dispNamesFolders addObject:dispName];
        
        NSDictionary* folderState = @{ @"accountNum" : @(newAccountNum),
                                       @"folderDisplayName":dispName,
                                       @"folderPath":folder.path,
                                       @"deleted":@false,
                                       @"fullsynced":@false,
                                       @"lastended":@0,
                                       @"flags":@(folder.flags),
                                       @"dbNums":@[]};
        
        [sm addFolderState:folderState accountNum:newAccountNum];
        
        indexPath++;
    }
    
    if([AppSettings importantFolderNumForAcct:newAccountNum forBaseFolder:FolderTypeFavoris] == -1){
        [AppSettings setImportantFolderNum:[AppSettings importantFolderNumForAcct:newAccountNum forBaseFolder:FolderTypeAll] forBaseFolder:FolderTypeFavoris forAccount:newAccountNum];
    }
    
    [AppSettings setFoldersName:dispNamesFolders forAccount:newAccountNum];
    
    CCMLog(@"5 - Go!");
    
    [[PKHUD sharedHUD] hideWithAnimated:NO];
    
    Account* ac = [Account emptyAccount];
    ac.userColor = [[Accounts sharedInstance] accountColors][newAccountNum-1];
    [AppSettings setColor:ac.userColor accountNum:newAccountNum];
    ac.idx = newAccountNum-1;
    
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
        NSArray* tmpFolders = [AppSettings allNonImportantFoldersName:newAccountNum];
        NSMutableArray* foldersNIndent = [[NSMutableArray alloc]initWithCapacity:tmpFolders.count];
        for (NSString* folderNames in tmpFolders) {
            [foldersNIndent addObject:@[folderNames,@([folderNames containsString:@"]/"])]];
        }
        ac.userFolders = foldersNIndent;
        
        EditCocoaButtonView* ecbv = [EditCocoaButtonView editCocoaButtonViewForAccount:self.account];
        ecbv.frame = CGRectMake(0, 55, ecbv.frame.size.width, ecbv.frame.size.height);
        [self.view addSubview:ecbv];
        self.editCocoa = ecbv;
        [ecbv becomeFirstResponder];
        
        UINavigationItem* item = [self.navBar.items firstObject];
        NSString* title = NSLocalizedString(@"Your Cocoa button", @"Your Cocoa button");
        item.titleView = [WhiteBlurNavBar titleViewForItemTitle:title];
        [self.navBar setNeedsDisplay];
        
        self.googleBtn.hidden = YES;
    }
}

- (void)loadFirstInboxEmails
{
    if ([[Reachability reachabilityForInternetConnection] currentReachabilityStatus] != NotReachable) {
        [[[[SyncManager getSingleton] syncActiveFolderFromStart:YES] deliverOn:[RACScheduler mainThreadScheduler]]
         subscribeNext:^(Email *email) {}
         error:^(NSError *error) {
             CCMLog(@"Error: %@",error.localizedDescription);
         }
         completed:^{}];
    }
}


@end



