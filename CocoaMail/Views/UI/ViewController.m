//
//  ViewController.m
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 14/07/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "ViewController.h"

#import "FolderViewController.h"
#import "MailListViewController.h"
#import "ConversationViewController.h"
#import "ContactsViewController.h"
#import "AttachmentsViewController.h"
#import "SettingsViewController.h"
#import "EditMailViewController.h"
#import "SearchViewController.h"
#import "SignatureViewController.h"
#import "SpamListViewController.h"
#import "UserSettings.h"
#import "Accounts.h"
#import "CocoaButton.h"
#import "SearchRunner.h"
#import "EmailProcessor.h"
#import "AppSettings.h"
//#import <Google/SignIn.h>
#import "DropboxBrowserViewController.h"
#import "PreviewViewController.h"
#import "InViewController.h"
#import "EditMailViewController.h"
#import "ImapSync.h"
#import "AddAccountViewController.h"

#import <Instabug/Instabug.h>

@interface ViewController () <CocoaButtonDatasource/*, GIDSignInUIDelegate*/>

@property (weak, nonatomic) IBOutlet UIView* contentView;

@property (nonatomic, strong) NSMutableArray* viewControllers;

@property (nonatomic, strong) CocoaButton* cocoaButton;
@property (nonatomic) BOOL askAccountsButton;


@property (nonatomic, weak) UIView* animNextView;
@property (nonatomic, weak) UIView* animCurrentView;
@property (nonatomic, weak) UIView* animShadowView;

@property (nonatomic, strong) InViewController* nextVC;

@property (nonatomic, weak) id <UIViewControllerPreviewing> previewingContext;

@end

@implementation ViewController

static ViewController * s_self;

+(ViewController*) mainVC
{
    return s_self;
}

-(InViewController*) topIVC
{
    InViewController* ivc =  [[ViewController mainVC].viewControllers lastObject];
    if ([ivc isKindOfClass:EditMailViewController.class]) {
        ivc = [ViewController mainVC].viewControllers[[ViewController mainVC].viewControllers.count - 2];
    }
    return ivc;
}

+(void) presentAlertWIP:(NSString*)message
{
    UIAlertController* ac = [UIAlertController alertControllerWithTitle:nil message:[NSString stringWithFormat:@"WIP : %@", message] preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:@"I wait…" style:UIAlertActionStyleDefault
                                                          handler:nil];
    [ac addAction:defaultAction];
    
    [s_self presentViewController:ac animated:YES completion:nil];
}

+(void) presentAlertOk:(NSString*)message
{
    UIAlertController* ac = [UIAlertController alertControllerWithTitle:nil message:[NSString stringWithFormat:@"%@", message] preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:@"Ok" style:UIAlertActionStyleDefault
                                                          handler:nil];
    [ac addAction:defaultAction];
    
    [s_self presentViewController:ac animated:YES completion:nil];
}

-(void) viewDidLoad
{
    [super viewDidLoad];
    
    s_self = self;
    
    self.contentView.backgroundColor = [UIColor whiteColor];
    
    self.contentView.clipsToBounds = YES;
    
    //[GIDSignIn sharedInstance].uiDelegate = self;
    
    [[[Accounts sharedInstance] currentAccount] connect];

    [self setup];
    
    CocoaButton* cb = [CocoaButton sharedButton];
    cb.center = CGPointMake(self.view.frame.size.width - 30, self.view.frame.size.height - 30);
    [self.view addSubview:cb];
    cb.datasource = self;
    self.cocoaButton = cb;
}

-(void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
}

-(void) didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

+(void) temporaryHideCocoaButton:(BOOL)hide
{
    [[self mainVC] _manageCocoaButton:!hide];
}

+(void) refreshCocoaButton
{
    [[self mainVC].cocoaButton updateColor];
}

+(void) animateCocoaButtonRefresh:(BOOL)anim
{
    //[[self mainVC].cocoaButton refreshAnimation:anim];
}

-(void) closeCocoaButtonIfNeeded
{
    [self.cocoaButton forceCloseButton];
}

-(void) setup
{
    FolderViewController* f = [[FolderViewController alloc] init];

    UIView* nextView;
    
    if ([Accounts sharedInstance].accountsCount !=  1) {
        MailListViewController* inbox = [[MailListViewController alloc] initWithFolder:decodeFolderTypeWith([AppSettings lastFolderIndex].integerValue) ];
        inbox.view.frame = self.contentView.bounds;
        nextView = inbox.view;
    
        self.viewControllers = [NSMutableArray arrayWithObjects:f, inbox, nil];
    }
    else {
        f.view.frame = self.contentView.bounds;
        nextView = f.view;
        
        self.viewControllers = [NSMutableArray arrayWithObjects:f, nil];
    }
    
    [self _manageCocoaButton:YES];
    
    [self.contentView addSubview:nextView];
    
    [self setupNavigation];
    
    UIView* border = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 10, self.view.frame.size.height)];
    border.backgroundColor = [UIColor clearColor];
    border.userInteractionEnabled = YES;
    border.autoresizingMask = UIViewAutoresizingFlexibleHeight;
    
    UIPanGestureRecognizer* pgr = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_panBack:)];
    [border addGestureRecognizer:pgr];
    
    self.customPGR = pgr;
    
    [self.view addSubview:border];
    
    UIView* borderN = [[UIView alloc] initWithFrame:CGRectMake(self.view.frame.size.width-5, 0, 5, self.view.frame.size.height)];
    borderN.backgroundColor = [UIColor clearColor];
    borderN.userInteractionEnabled = YES;
    borderN.autoresizingMask = UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleLeftMargin;
    
    UIPanGestureRecognizer* pgrN = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_panNext:)];
    [borderN addGestureRecognizer:pgrN];
    
    [self.view addSubview:borderN];
}

-(void) _createShadowViewOverAnimCurrentView
{
    UIImageView* iv = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"trans_shadow"]];
    
    iv.backgroundColor = [UIColor clearColor];
    iv.contentMode = UIViewContentModeScaleToFill;
    
    iv.frame = CGRectMake(-3, -20, 3, self.animCurrentView.frame.size.height + 20);
    [self.animCurrentView addSubview:iv];
    
    self.animShadowView = iv;
}

-(void) _panBack:(UIPanGestureRecognizer*)pgr
{
    if (pgr.enabled==NO) {
        return;
    }
    
    if (self.viewControllers.count<2) {
        return;
    }
    
    
    switch (pgr.state) {
        case UIGestureRecognizerStateBegan:
        {
            InViewController* vc = [self.viewControllers objectAtIndex:self.viewControllers.count - 2];
            self.animNextView = vc.view;
            
            InViewController* f = [self.viewControllers lastObject];
            self.animCurrentView = f.view;
            
            self.animNextView.userInteractionEnabled = NO;
            self.animCurrentView.userInteractionEnabled = NO;
            
            [self _createShadowViewOverAnimCurrentView];
            
            self.animNextView.transform = CGAffineTransformMakeTranslation(-self.view.frame.size.width / 4, 0);
            
            [self.contentView insertSubview:self.animNextView belowSubview:self.animCurrentView];
            
            self.cocoaButton.userInteractionEnabled = NO;
            break;
        }
            
        case UIGestureRecognizerStateChanged:
        {
            CGPoint p = [pgr translationInView:pgr.view];
            
            CGFloat caped = MAX(0, p.x);
            caped = MIN(caped, self.view.frame.size.width);
            
            const CGFloat invPourc = 1.f -(caped / self.view.frame.size.width);
            
            self.animCurrentView.transform = CGAffineTransformMakeTranslation(caped, 0);
            
            self.animShadowView.alpha = invPourc;
            self.animNextView.transform = CGAffineTransformMakeTranslation(-(self.view.frame.size.width / 4) * invPourc, 0);
            break;
        }
            
        case UIGestureRecognizerStateEnded:
        {
            self.animNextView.userInteractionEnabled = YES;
            self.animCurrentView.userInteractionEnabled = YES;
            self.cocoaButton.userInteractionEnabled = YES;
            
            CGPoint v = [pgr velocityInView:pgr.view];
            
            if (v.x>0) {
                [[NSNotificationCenter defaultCenter] postNotificationName:kBACK_NOTIFICATION object:nil];
            }
            else {
                [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
                
                [UIView animateWithDuration:0.2
                                      delay:0
                                    options:UIViewAnimationOptionCurveEaseOut
                                 animations:^{
                                     self.animCurrentView.transform = CGAffineTransformIdentity;
                                     self.animShadowView.alpha = 1.;
                                 }
                                 completion:^(BOOL fini) {
                                     [self.animNextView removeFromSuperview];
                                     self.animNextView = nil;
                                     self.animCurrentView = nil;
                                     [self.animShadowView removeFromSuperview];
                                     self.animShadowView = nil;
                                     [[UIApplication sharedApplication] endIgnoringInteractionEvents];
                                 }];
            }
            break;
        }
            
        default:
        {
            self.animNextView.userInteractionEnabled = YES;
            self.animCurrentView.userInteractionEnabled = YES;
            self.cocoaButton.userInteractionEnabled = YES;
            break;
        }
    }
    /*
     CGPoint v = [pgr velocityInView:pgr.view];
     CGPoint p = [pgr translationInView:pgr.view];
     NSLog(@"%d| %@ --> %@", pgr.state,  NSStringFromCGPoint(p), NSStringFromCGPoint(v));
     */
}

-(void) _panNext:(UIPanGestureRecognizer*)pgr
{
    if (pgr.enabled==NO) {
        return;
    }
    
    switch (pgr.state) {
        case UIGestureRecognizerStateBegan:
        {
            InViewController* vc = [self.viewControllers lastObject];
            
            NSArray* infos = [vc nextViewControllerInfos];
            
            if (infos.count!=2) {
                return;
            }
            
            
            NSString* first = [infos firstObject];
            
            if ([first isEqualToString:kPRESENT_CONVERSATION_ATTACHMENTS_NOTIFICATION]) {
                AttachmentsViewController* f = [[AttachmentsViewController alloc] init];
                f.conversation = [infos lastObject];
                
                self.nextVC = f;
            }
            else if ([first isEqualToString:kPRESENT_SETTINGS_NOTIFICATION]) {
                SettingsViewController* f = [[SettingsViewController alloc] init];
                self.nextVC = f;
            }
            else {
                // is there another case ?
                return;
            }
            
            self.animCurrentView = self.nextVC.view;
            [self _createShadowViewOverAnimCurrentView];
            self.animNextView = self.nextVC.view;
            
            
            self.animCurrentView = vc.view;
            
            self.animNextView.userInteractionEnabled = NO;
            self.animCurrentView.userInteractionEnabled = NO;
            
            self.animNextView.transform = CGAffineTransformMakeTranslation(self.view.frame.size.width, 0);
            
            [self.contentView insertSubview:self.animNextView aboveSubview:self.animCurrentView];
            
            self.cocoaButton.userInteractionEnabled = NO;
            break;
        }
            
        case UIGestureRecognizerStateChanged:
        {
            if (self.nextVC==nil) {
                return;
            }
            
            CGPoint p = [pgr translationInView:pgr.view];
            
            CGFloat caped = MIN(0, p.x);
            caped = MAX(caped, -self.view.frame.size.width);
            
            CGFloat invPourc = -(caped / self.view.frame.size.width);
            
            self.animNextView.transform = CGAffineTransformMakeTranslation(self.view.frame.size.width + caped, 0);
            
            self.animShadowView.alpha = invPourc;
            self.animCurrentView.transform = CGAffineTransformMakeTranslation(-(self.view.frame.size.width / 4) * invPourc, 0);
            break;
        }
            
        case UIGestureRecognizerStateEnded:
        {
            if (self.nextVC==nil) {
                return;
            }
            
            self.animNextView.userInteractionEnabled = YES;
            self.animCurrentView.userInteractionEnabled = YES;
            self.cocoaButton.userInteractionEnabled = YES;
            
            CGPoint v = [pgr velocityInView:pgr.view];
            
            [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
            
            if (v.x>0) {
                // cancel
                self.nextVC = nil;
                
                [UIView animateWithDuration:0.2
                                      delay:0
                                    options:UIViewAnimationOptionCurveEaseOut
                                 animations:^{
                                     self.animNextView.transform = CGAffineTransformMakeTranslation(self.view.frame.size.width, 0);
                                     self.animCurrentView.transform = CGAffineTransformIdentity;
                                     self.animShadowView.alpha = 1.;
                                 }
                                 completion:^(BOOL fini) {
                                     [self.animNextView removeFromSuperview];
                                     self.animNextView = nil;
                                     self.animCurrentView = nil;
                                     [self.animShadowView removeFromSuperview];
                                     self.animShadowView = nil;
                                     [[UIApplication sharedApplication] endIgnoringInteractionEvents];
                                 }];
                
            }
            else {
                // validate
                
                [self _manageCocoaButton:[self.nextVC haveCocoaButton]];
                
                [self.viewControllers addObject:self.nextVC];
                self.nextVC = nil;
                
                [UIView animateWithDuration:0.2
                                      delay:0
                                    options:UIViewAnimationOptionCurveEaseOut
                                 animations:^{
                                     
                                     self.animNextView.transform = CGAffineTransformIdentity;
                                     self.animCurrentView.transform = CGAffineTransformMakeTranslation(-(self.view.frame.size.width / 4), 0);;
                                     self.animShadowView.alpha = 0.;
                                 }
                                 completion:^(BOOL fini) {
                                     
                                     [self.animCurrentView removeFromSuperview];
                                     self.animNextView = nil;
                                     self.animCurrentView = nil;
                                     [self.animShadowView removeFromSuperview];
                                     self.animShadowView = nil;
                                     [[UIApplication sharedApplication] endIgnoringInteractionEvents];
                                 }];
            }
            break;
        }
            
        default:
        {
            self.nextVC = nil;
            self.animNextView.userInteractionEnabled = YES;
            self.animCurrentView.userInteractionEnabled = YES;
            self.cocoaButton.userInteractionEnabled = YES;
            break;
        }
    }
}

-(BOOL) _checkInteractionAndBlock
{
    BOOL already = [[UIApplication sharedApplication] isIgnoringInteractionEvents];
    
    if (already) {
        return YES;
    }
    
    [[UIApplication sharedApplication] beginIgnoringInteractionEvents];
    
    return NO;
}

-(void) setupNavigation
{
    [[NSNotificationCenter defaultCenter] addObserverForName:kCREATE_FIRST_ACCOUNT_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock:^(NSNotification* notif){
        IBGLog(kCREATE_FIRST_ACCOUNT_NOTIFICATION);
        
        AddFirstAccountViewController* f = [[AddFirstAccountViewController alloc] init];
        f.firstRunMode = YES;
        
        if (self.viewControllers.count==1) {
            
            if ([self _checkInteractionAndBlock]) {
                return;
            }
            
            [self _animatePushVC:f];
            return;
        }
        
        if (self.viewControllers.count>2) {
            NSRange toRemove;
            toRemove.location = 1;
            toRemove.length = self.viewControllers.count - 2;
            [self.viewControllers removeObjectsInRange:toRemove];
        }
        
        [self.viewControllers insertObject:f atIndex:1];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:kBACK_NOTIFICATION object:nil];
        
    }];
    
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kPRESENT_FOLDER_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock:^(NSNotification* notif){
        
        if ([self _checkInteractionAndBlock]) {
            return;
        }
        
        IBGLog(kPRESENT_FOLDER_NOTIFICATION);

        //[[SearchRunner getSingleton] cancel];
        [[[Accounts sharedInstance] currentAccount] cancelSearch];

        MailListViewController* f = nil;
        Person* person = [notif.userInfo objectForKey:kPRESENT_FOLDER_PERSON];
        
        if (person != nil) {
            f = [[MailListViewController alloc] initWithPerson:person];
        }
        else {
            NSNumber* codedType = [notif.userInfo objectForKey:kPRESENT_FOLDER_TYPE];
            f = [[MailListViewController alloc] initWithFolder:decodeFolderTypeWith(codedType.integerValue)];
        }
        
        // don't open the same view twice
        BOOL doNothing = NO;
        InViewController* last = [self.viewControllers lastObject];
        
        if ([last isKindOfClass:[MailListViewController class]]) {
            MailListViewController* mlvc = (MailListViewController*)last;
            
            if ([f istheSame:mlvc]) {
                doNothing = YES;
            }
        }
        
        if (doNothing) {
            [[UIApplication sharedApplication] endIgnoringInteractionEvents];
        }
        else {
            [self _animatePushVC:f];
        }
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kPRESENT_SETTINGS_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock:^(NSNotification* notif){
        if ([self _checkInteractionAndBlock]) {
            return;
        }
        IBGLog(kPRESENT_SETTINGS_NOTIFICATION);
        SettingsViewController* f = [[SettingsViewController alloc] init];
        [self _animatePushVC:f];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kSETTINGS_CREDIT_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock:^(NSNotification* notif){
        if ([self _checkInteractionAndBlock]) {
            return;
        }
        IBGLog(kSETTINGS_CREDIT_NOTIFICATION);
        CreditViewController* f = [[CreditViewController alloc] init];
        [self _animatePushVC:f];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kSETTINGS_CREDIT2_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock:^(NSNotification* notif){
        if ([self _checkInteractionAndBlock]) {
            return;
        }
        IBGLog(kSETTINGS_CREDIT2_NOTIFICATION);
        CreditContentViewController* f = [[CreditContentViewController alloc] init];
        f.type = [notif.userInfo objectForKey:kSETTINGS_KEY];
        [self _animatePushVC:f];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kSETTINGS_SPAMTEST_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock:^(NSNotification* notif){
        if ([self _checkInteractionAndBlock]) {
            return;
        }
        IBGLog(kSETTINGS_SPAMTEST_NOTIFICATION);
        SpamListViewController* f = [[SpamListViewController alloc] init];
        [self _animatePushVC:f];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kSETTINGS_CLOUD_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock:^(NSNotification* notif){
        if ([self _checkInteractionAndBlock]) {
            return;
        }
        IBGLog(kSETTINGS_CLOUD_NOTIFICATION);
        CloudViewController* f = [[CloudViewController alloc] init];
        f.cloudServiceName = [notif.userInfo objectForKey:kSETTINGS_KEY];
        [self _animatePushVC:f];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kSETTINGS_MAIN_ACCOUNT_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock:^(NSNotification* notif){
        if ([self _checkInteractionAndBlock]) {
            return;
        }
        IBGLog(kSETTINGS_MAIN_ACCOUNT_NOTIFICATION);
        DefaultAccountViewController* f = [[DefaultAccountViewController alloc] init];
        [self _animatePushVC:f];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kSETTINGS_SWIPE_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock:^(NSNotification* notif){
        if ([self _checkInteractionAndBlock]) {
            return;
        }
        IBGLog(kSETTINGS_SWIPE_NOTIFICATION);
        QuickSwipeViewController* f = [[QuickSwipeViewController alloc] init];
        [self _animatePushVC:f];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kSETTINGS_NOTIF_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock:^(NSNotification* notif){
        if ([self _checkInteractionAndBlock]) {
            return;
        }
        IBGLog(kSETTINGS_NOTIF_NOTIFICATION);
        NotificationViewController* f = [[NotificationViewController alloc] init];
        [self _animatePushVC:f];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kSETTINGS_ACCOUNT_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock:^(NSNotification* notif){
        if ([self _checkInteractionAndBlock]) {
            return;
        }
        IBGLog(kSETTINGS_ACCOUNT_NOTIFICATION);
        AccountViewController* f = [[AccountViewController alloc] init];
        f.account = [notif.userInfo objectForKey:kSETTINGS_KEY];
        [self _animatePushVC:f];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kSETTINGS_ACCOUNT_SIGN_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock:^(NSNotification* notif){
        if ([self _checkInteractionAndBlock]) {
            return;
        }
        IBGLog(kSETTINGS_ACCOUNT_SIGN_NOTIFICATION);
        SignatureViewController* f = [[SignatureViewController alloc] init];
        f.account = [notif.userInfo objectForKey:kSETTINGS_KEY];
        [self _animatePushVC:f];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kSETTINGS_ADD_ACCOUNT_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock:^(NSNotification* notif){
        if ([self _checkInteractionAndBlock]) {
            return;
        }
        IBGLog(kSETTINGS_ADD_ACCOUNT_NOTIFICATION);
        AddAccountViewController* f = [[AddAccountViewController alloc] init];
        [self _animatePushVC:f];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kPRESENT_CONVERSATION_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock:^(NSNotification* notif){
        if ([self _checkInteractionAndBlock]) {
            return;
        }
        IBGLog(kPRESENT_CONVERSATION_NOTIFICATION);
        ConversationViewController* f = [[ConversationViewController alloc] init];
        f.conversation = [notif.userInfo objectForKey:kPRESENT_CONVERSATION_KEY];
        [self _animatePushVC:f];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kPRESENT_CONVERSATION_ATTACHMENTS_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock:^(NSNotification* notif){
        if ([self _checkInteractionAndBlock]) {
            return;
        }
        IBGLog(kPRESENT_CONVERSATION_ATTACHMENTS_NOTIFICATION);
        
        AttachmentsViewController* f = [[AttachmentsViewController alloc] init];
        f.conversation = [notif.userInfo objectForKey:kPRESENT_CONVERSATION_KEY];
        
        InViewController* vc = [self.viewControllers lastObject];
        
        if ([vc isKindOfClass:[MailListViewController class]]) {
            ((MailListViewController*)vc).attachSubscriber = f;
        }
        
        
        [self _animatePushVC:f];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kPRESENT_CONTACTS_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock:^(NSNotification* notif){
        if ([self _checkInteractionAndBlock]) {
            return;
        }
        IBGLog(kPRESENT_CONTACTS_NOTIFICATION);
        ContactsViewController* f = [[ContactsViewController alloc] init];
        f.mail = [notif.userInfo objectForKey:kPRESENT_MAIL_KEY];
        [self _animatePushVC:f];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kPRESENT_SEARCH_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock:^(NSNotification* notif){
        if ([self _checkInteractionAndBlock]) {
            return;
        }
        IBGLog(kPRESENT_SEARCH_NOTIFICATION);
        [[[Accounts sharedInstance] currentAccount] cancelSearch];

        SearchViewController* f = [[SearchViewController alloc] init];
        [self _animatePushVC:f];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kPRESENT_EDITMAIL_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock:^(NSNotification* notif){
        if ([self _checkInteractionAndBlock]) {
            return;
        }
        IBGLog(kPRESENT_EDITMAIL_NOTIFICATION);
        EditMailViewController* f = [[EditMailViewController alloc] init];
        f.draft = [notif.userInfo objectForKey:kPRESENT_MAIL_KEY];
        [self _animatePushVC:f];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kPRESENT_DROPBOX_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock:^(NSNotification* notif){
        if ([self _checkInteractionAndBlock]) {
            return;
        }
        IBGLog(kPRESENT_DROPBOX_NOTIFICATION);
        
        DropboxBrowserViewController* f = [[DropboxBrowserViewController alloc]init];
        f.rootViewDelegate = [notif.userInfo objectForKey:kPRESENT_DELEGATE_KEY];
        f.deliverDownloadNotifications = YES;
        f.shouldDisplaySearchBar = YES;
        
        //[self _animatePushVC:f];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kBACK_TO_INBOX_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock:^(NSNotification* notif){
        IBGLog(kBACK_TO_INBOX_NOTIFICATION);

        //[[SearchRunner getSingleton] cancel];
        
        if (self.viewControllers.count>3) {
            NSRange toRemove;
            toRemove.location = 2;
            toRemove.length = self.viewControllers.count - 3;
            [self.viewControllers removeObjectsInRange:toRemove];
        }
        
        if (self.viewControllers.count>2) {
            MailListViewController* f = [[MailListViewController alloc] initWithFolder:[[AppSettings userWithIndex:kActiveAccountIndex] typeOfFolder:kActiveFolderIndex]];
            [self.viewControllers replaceObjectAtIndex:1 withObject:f];
        }
        
        
        [[NSNotificationCenter defaultCenter] postNotificationName:kBACK_NOTIFICATION object:nil];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kBACK_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock:^(NSNotification* notif){
        //[[SearchRunner getSingleton] cancel];

        if (self.viewControllers.count == 1) {
            return;
        }
        
        if ([self _checkInteractionAndBlock]) {
            return;
        }
        IBGLog(kBACK_NOTIFICATION);

        InViewController* vc = [self.viewControllers lastObject];
        [vc cleanBeforeGoingBack];
        UIView* lastView = vc.view;
        [self.viewControllers removeLastObject];
        
        UIView* nextView = nil;
        InViewController* f = [self.viewControllers lastObject];
        
        // tweak to realod nav bar after settings view
        if ([vc isKindOfClass:[SettingsViewController class]] && [f isKindOfClass:[FolderViewController class]]) {
            FolderViewController* f = [[FolderViewController alloc] init];
            f.view.frame = self.contentView.bounds;
            nextView = f.view;
            [self.contentView insertSubview:nextView belowSubview:lastView];
            
            self.viewControllers = [NSMutableArray arrayWithObject:f];
        }
        else {
            nextView = f.view;
            [self.contentView insertSubview:nextView belowSubview:lastView];
        }
        
        [self.cocoaButton forceCloseButton];
        
        UIViewAnimationOptions animOption = UIViewAnimationOptionCurveEaseOut;
        
        if (self.animShadowView==nil) {
            nextView.transform = CGAffineTransformMakeTranslation(-self.view.frame.size.width / 4, 0);
            
            self.animNextView = nextView;
            self.animCurrentView = lastView;
            
            [self _createShadowViewOverAnimCurrentView];
            
            animOption = UIViewAnimationOptionCurveEaseInOut;
        }
        
        
        [UIView animateWithDuration:0.25
                              delay:0
                            options:animOption
                         animations:^{
                             self.animShadowView.alpha = 0.;
                             self.animNextView.transform = CGAffineTransformIdentity;
                             self.animCurrentView.transform = CGAffineTransformMakeTranslation(self.view.bounds.size.width, 0);
                         }
                         completion:^(BOOL fini) {
                             self.animNextView.userInteractionEnabled = YES;
                             
                             [self.animShadowView removeFromSuperview];
                             self.animShadowView = nil;
                             
                             [self.animCurrentView removeFromSuperview];
                             self.animCurrentView = nil;
                             
                             self.animNextView = nil;
                             
                             [[UIApplication sharedApplication] endIgnoringInteractionEvents];
                             
                             [self _manageCocoaButton:[f haveCocoaButton]];
                         }];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kACCOUNT_CHANGED_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock:^(NSNotification* notif){
        IBGLog(kACCOUNT_CHANGED_NOTIFICATION);

        //[[Parser sharedParser] cleanConversations];
        
        BOOL inFolders = self.viewControllers.count == 1;
        
        InViewController* vc = [self.viewControllers lastObject];
        UIView* lastView = vc.view;
        
        FolderViewController* f = [[FolderViewController alloc] init];
        
        UIView* nextView = f.view;
        
        if (inFolders) {
            self.viewControllers = [NSMutableArray arrayWithObject:f];
        }
        else {
            [[[Accounts sharedInstance] currentAccount] cancelSearch];
            MailListViewController* inbox = [[MailListViewController alloc] initWithFolder:[[AppSettings userWithIndex:kActiveAccountIndex] typeOfFolder:kActiveFolderIndex]];
            inbox.view.frame = self.contentView.bounds;
            nextView = inbox.view;
            
            self.viewControllers = [NSMutableArray arrayWithObjects:f, inbox, nil];
        }
        
        [self _manageCocoaButton:YES];
        
        [self.contentView insertSubview:nextView belowSubview:lastView];
        
        [lastView removeFromSuperview];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kQUICK_ACTION_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock:^(NSNotification* notif){
        IBGLog(kQUICK_ACTION_NOTIFICATION);
        
        BOOL inFolders = self.viewControllers.count == 1;
        
        if (!inFolders) {
            [[NSNotificationCenter defaultCenter] postNotificationName:kACCOUNT_CHANGED_NOTIFICATION object:nil];
        }
        else {
            [[NSNotificationCenter defaultCenter] postNotificationName:kPRESENT_FOLDER_NOTIFICATION object:nil userInfo:@{kPRESENT_FOLDER_TYPE:[notif.userInfo objectForKey:kPRESENT_FOLDER_TYPE]}];
        }
        
    }];
}

-(void) _animatePushVC:(InViewController*)nextVC
{
    InViewController* currentVC = [self.viewControllers lastObject];
    UIView* currentView = currentVC.view;
    
    UIView* nextView = nextVC.view;
    CGRect frameForSpring = self.contentView.bounds;
    frameForSpring.size.width += 100;
    nextView.frame = frameForSpring;
    
    [self.contentView addSubview:nextView];
    [self.viewControllers addObject:nextVC];
    
    [self.cocoaButton forceCloseButton];
    
    self.animCurrentView = nextView;
    [self _createShadowViewOverAnimCurrentView];
    self.animShadowView.alpha = 0.;
    
    nextView.transform = CGAffineTransformMakeTranslation(self.view.bounds.size.width, 0);
    
    
    [UIView animateWithDuration:0.25
                          delay:0
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{
                         nextView.transform = CGAffineTransformIdentity;
                         currentView.transform = CGAffineTransformMakeTranslation(-self.view.frame.size.width / 4, 0);
                         self.animShadowView.alpha = 1.;
                     }
                     completion:^(BOOL fini) {
                         [currentView removeFromSuperview];
                         nextView.frame = self.contentView.bounds;
                         
                         [self.animShadowView removeFromSuperview];
                         self.animShadowView = nil;
                         
                         self.animCurrentView = nil;
                         
                         [[UIApplication sharedApplication] endIgnoringInteractionEvents];
                         
                         [self _manageCocoaButton:[nextVC haveCocoaButton]];
                         
                     }];
}

-(void) _manageCocoaButton:(BOOL)appear
{
    if (appear) {
        if (self.cocoaButton.alpha == 0.) {
            [self.view addSubview:self.cocoaButton];
            [UIView animateWithDuration:0.25
                             animations:^{
                                 self.cocoaButton.alpha = 1.;
                             }
                             completion:nil
             ];
        }
    }
    else {
        if (self.cocoaButton.alpha == 1.) {
            [UIView animateWithDuration:0.25
                             animations:^{
                                 self.cocoaButton.alpha = 0.;
                             }
                             completion:^(BOOL fini) {
                                 [self.cocoaButton removeFromSuperview];
                             }
             ];
        }
    }
}
// Cocoa button

-(void) _openAccounts
{
    [UIView animateWithDuration:0.2 animations:^{
        [self.cocoaButton forceCloseButton];
    }
                     completion:^(BOOL fini){
                         self.askAccountsButton = YES;
                         [self.cocoaButton openHorizontal];
                     }];
    
}

-(void) _editMail
{
    [[NSNotificationCenter defaultCenter] postNotificationName:kPRESENT_EDITMAIL_NOTIFICATION object:nil];
}

-(void) _search
{
    InViewController* ivc = [self.viewControllers lastObject];
    
    if ([ivc isKindOfClass:[SearchViewController class]]) {
        return;
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kPRESENT_SEARCH_NOTIFICATION object:nil];
}

-(NSArray*) buttonsWideFor:(CocoaButton*)cocoabutton
{
    InViewController* currentVC = [self.viewControllers lastObject];
    
    if ([currentVC conformsToProtocol:@protocol(CocoaButtonDatasource)]) {
        id<CocoaButtonDatasource> src = (id<CocoaButtonDatasource>)currentVC;
        NSArray* res = [src buttonsWideFor:cocoabutton];
        
        if (res != nil) {
            return res;
        }
    }
    
    
    UIButton* b1 = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 33, 33)];
    [b1 setImage:[UIImage imageNamed:@"edit_off"] forState:UIControlStateNormal];
    [b1 setImage:[UIImage imageNamed:@"edit_on"] forState:UIControlStateHighlighted];
    [b1 addTarget:self action:@selector(_editMail) forControlEvents:UIControlEventTouchUpInside];
    
    UIButton* b2 = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 33, 33)];
    [b2 setImage:[UIImage imageNamed:@"search_off"] forState:UIControlStateNormal];
    [b2 setImage:[UIImage imageNamed:@"search_on"] forState:UIControlStateHighlighted];
    [b2 addTarget:self action:@selector(_search) forControlEvents:UIControlEventTouchUpInside];
    
    UIButton* b3 = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 33, 33)];
    [b3 setImage:[UIImage imageNamed:@"accounts_off"] forState:UIControlStateNormal];
    [b3 setImage:[UIImage imageNamed:@"accounts_on"] forState:UIControlStateHighlighted];
    [b3 addTarget:self action:@selector(_openAccounts) forControlEvents:UIControlEventTouchUpInside];
    
    NSArray* buttons = @[b1, b2, b3];
    
    return buttons;
}

-(void) _moreAccount
{
    [[NSNotificationCenter defaultCenter] postNotificationName:kSETTINGS_ADD_ACCOUNT_NOTIFICATION object:nil];
}

-(void) _applyAccountButton:(UIButton*)button
{
    [self.cocoaButton closeHorizontalButton:button refreshCocoaButtonAndDo:^{
        
        Accounts* A = [Accounts sharedInstance];
        CCMFolderType folder = [[A currentAccount].user typeOfFolder:[A currentAccount].currentFolderIdx];
        [[A currentAccount] releaseContent];
        A.currentAccountIdx = button.tag;

        if (folder.type != FolderTypeUser) {
            [[A currentAccount] setCurrentFolder:folder];
        }
        else {
            [[A currentAccount] setCurrentFolder:FolderTypeWith(FolderTypeAll, 0)];
        }
    
        [[A currentAccount] connect];

        [[NSNotificationCenter defaultCenter] postNotificationName:kACCOUNT_CHANGED_NOTIFICATION object:nil];
    }];
}

-(NSArray*) _accountsButtons
{
    const CGRect baseRect = self.cocoaButton.bounds;
    
    NSArray* alls = [Accounts sharedInstance].accounts;
    NSMutableArray* buttons = [NSMutableArray arrayWithCapacity:alls.count];
    NSInteger currentAIdx = [Accounts sharedInstance].currentAccountIdx;
    
    NSInteger idx = 0;
    
    for (Account* a in alls) {
        if (!a.user.isAll && a.user.isDeleted) {
            continue;
        }
        
        if (alls.count == 2 && a.user.isAll) {
            continue;
        }
        
        if (idx == currentAIdx) {
            idx++;
            continue;
        }
        
        UIButton* b = [[UIButton alloc] initWithFrame:baseRect];
        
        b.backgroundColor = a.user.color;
        [b setTitle:a.user.initials forState:UIControlStateNormal];
        b.layer.cornerRadius = 22;
        b.layer.masksToBounds = YES;
        b.titleLabel.font = [UIFont systemFontOfSize:13];
        
        b.tag = idx;
        [b addTarget:self action:@selector(_applyAccountButton:) forControlEvents:UIControlEventTouchUpInside];
        
        [buttons addObject:b];
        
        idx++;
    }
    
    // more btn
    if (buttons.count<5) {
        UIButton* b = [[UIButton alloc] initWithFrame:baseRect];
        b.backgroundColor = [UIColor blackColor];
        [b setImage:[UIImage imageNamed:@"add_accounts"] forState:UIControlStateNormal];
        [b setImage:[UIImage imageNamed:@"add_accounts"] forState:UIControlStateHighlighted];
        b.layer.cornerRadius = 22;
        b.layer.masksToBounds = YES;
        [b addTarget:self action:@selector(_moreAccount) forControlEvents:UIControlEventTouchUpInside];
        [buttons addObject:b];
    }
    
    return buttons;
}

-(NSArray*) buttonsHorizontalFor:(CocoaButton*)cocoabutton
{
    if (self.askAccountsButton) {
        self.askAccountsButton = NO;
        
        return [self _accountsButtons];
    }
    
    InViewController* currentVC = [self.viewControllers lastObject];
    
    if ([currentVC conformsToProtocol:@protocol(CocoaButtonDatasource)]) {
        id<CocoaButtonDatasource> src = (id<CocoaButtonDatasource>)currentVC;
        NSArray* res = [src buttonsHorizontalFor:cocoabutton];
        
        if (res!=nil) {
            return res;
        }
    }
    
    return [self _accountsButtons];
}

-(BOOL) cocoabuttonLongPress:(CocoaButton*)cocoabutton
{
    InViewController* currentVC = [self.viewControllers lastObject];
    
    if ([currentVC conformsToProtocol:@protocol(CocoaButtonDatasource)]) {
        id<CocoaButtonDatasource> src = (id<CocoaButtonDatasource>)currentVC;
        
        return [src cocoabuttonLongPress:cocoabutton];
    }
    
    self.askAccountsButton = YES;
    
    return YES;
}

-(BOOL) automaticCloseFor:(CocoaButton*)cocoabutton
{
    InViewController* currentVC = [self.viewControllers lastObject];
    
    if ([currentVC conformsToProtocol:@protocol(CocoaButtonDatasource)]) {
        id<CocoaButtonDatasource> src = (id<CocoaButtonDatasource>)currentVC;
        
        return [src automaticCloseFor:cocoabutton];
    }
    
    return YES;
}

#pragma mark - Background Sync

-(void) refreshWithCompletionHandler:(CRefreshCompletionHandler)completionHandler
{
    for (UIViewController* vc in self.viewControllers) {
        if ([vc isKindOfClass:[FolderViewController class]]) {
            [((FolderViewController*)vc) refreshWithCompletionHandler:completionHandler];
            return;
        }
    }
}

-(BOOL) shouldAutorotate{
    return YES;
}

-(UIInterfaceOrientationMask) supportedInterfaceOrientations{
    return UIInterfaceOrientationMaskPortrait;
}

@end