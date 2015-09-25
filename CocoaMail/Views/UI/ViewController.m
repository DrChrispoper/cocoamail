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

#import "Accounts.h"
#import "CocoaButton.h"
#import "SearchRunner.h"
#import "EmailProcessor.h"
#import "AppSettings.h"
#import <Google/SignIn.h>
#import "DropboxBrowserViewController.h"

@interface ViewController () <CocoaButtonDatasource, GIDSignInUIDelegate>

@property (weak, nonatomic) IBOutlet UIView *blackStatusBar;
@property (weak, nonatomic) IBOutlet UIView *contentView;

@property (nonatomic, strong) NSMutableArray *viewControllers;

@property (nonatomic, strong) CocoaButton* cocoaButton;
@property (nonatomic) BOOL askAccountsButton;


@property (nonatomic, weak) UIView* animNextView;
@property (nonatomic, weak) UIView* animCurrentView;
@property (nonatomic, weak) UIView* animShadowView;

@property (nonatomic, strong) InViewController* nextVC;

@end




@implementation ViewController


static ViewController* s_self;

+(ViewController*) mainVC
{
    return s_self;
}

+(void) presentAlertWIP:(NSString*)message
{
    UIAlertController* ac = [UIAlertController alertControllerWithTitle:nil message:[NSString stringWithFormat:@"WIP : %@", message] preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:@"I wait…" style:UIAlertActionStyleDefault
                                                          handler:nil];
    [ac addAction:defaultAction];
    
    [s_self presentViewController:ac animated:YES completion:nil];
}



- (void)viewDidLoad {
    [super viewDidLoad];
    
    s_self = self;
    
    self.blackStatusBar.backgroundColor = [UIColor whiteColor];
    self.contentView.backgroundColor = [UIColor whiteColor];
    
    self.contentView.clipsToBounds = YES;
    
    [GIDSignIn sharedInstance].uiDelegate = self;
    
    [[[Accounts sharedInstance] currentAccount] connect];
    
    [self setup];
    
    CocoaButton* cb = [CocoaButton sharedButton];
    cb.center = CGPointMake(self.view.frame.size.width - 30, self.view.frame.size.height - 30);
    [self.view addSubview:cb];
    cb.datasource = self;
    self.cocoaButton = cb;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

+(void) temporaryHideCocoaButton:(BOOL) hide
{
    [[self mainVC] _manageCocoaButton:!hide];
}

+(void) refreshCocoaButton
{
    [[self mainVC].cocoaButton updateColor];
}

+(void) animateCocoaButtonRefresh:(BOOL)anim
{
    [[self mainVC].cocoaButton refreshAnimation:anim];
}


-(void) closeCocoaButtonIfNeeded
{
    [self.cocoaButton forceCloseButton];
}



- (void)setup
{
    
    FolderViewController* f = [[FolderViewController alloc] init];
    f.view.frame = self.contentView.bounds;
    [self.contentView addSubview:f.view];
    
    self.viewControllers = [NSMutableArray arrayWithObject:f];
    
    [self setupNavigation];
    
    
    UIView* border = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 5, self.view.frame.size.height)];
    border.backgroundColor = [UIColor clearColor];
    border.userInteractionEnabled = YES;
    border.autoresizingMask = UIViewAutoresizingFlexibleHeight;
    
    UIPanGestureRecognizer* pgr = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_panBack:)];
    [border addGestureRecognizer:pgr];
    
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
    
    iv.frame = CGRectMake(-3, -20, 3, self.animCurrentView.frame.size.height +20);
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
            InViewController* vc = [self.viewControllers objectAtIndex:self.viewControllers.count-2];
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
            
            const CGFloat invPourc = 1.f - (caped / self.view.frame.size.width);
            
            self.animCurrentView.transform = CGAffineTransformMakeTranslation(caped, 0);
            
            self.animShadowView.alpha = invPourc;
            self.animNextView.transform = CGAffineTransformMakeTranslation(-(self.view.frame.size.width / 4)*invPourc, 0);
            
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
                                     self.animShadowView=nil;
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
            
            CGFloat invPourc = - (caped / self.view.frame.size.width);
            
            self.animNextView.transform = CGAffineTransformMakeTranslation(self.view.frame.size.width+caped, 0);
            
            self.animShadowView.alpha = invPourc;
            self.animCurrentView.transform = CGAffineTransformMakeTranslation(-(self.view.frame.size.width / 4)*invPourc, 0);
            
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
                                     self.animShadowView=nil;
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
                                     self.animShadowView=nil;
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
    [[NSNotificationCenter defaultCenter] addObserverForName:kCREATE_FIRST_ACCOUNT_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock: ^(NSNotification* notif){
        
        AddAccountViewController* f = [[AddAccountViewController alloc] init];
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
    
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kPRESENT_FOLDER_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock: ^(NSNotification* notif){
        
        if ([self _checkInteractionAndBlock]) {
            return;
        }
        
        [[SearchRunner getSingleton] cancel];

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
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kPRESENT_SETTINGS_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock: ^(NSNotification* notif){
        if ([self _checkInteractionAndBlock]) {
            return;
        }
        SettingsViewController* f = [[SettingsViewController alloc] init];
        [self _animatePushVC:f];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kSETTINGS_CREDIT_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock: ^(NSNotification* notif){
        if ([self _checkInteractionAndBlock]) {
            return;
        }
        CreditViewController* f = [[CreditViewController alloc] init];
        [self _animatePushVC:f];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kSETTINGS_CREDIT2_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock: ^(NSNotification* notif){
        if ([self _checkInteractionAndBlock]) {
            return;
        }
        CreditContentViewController* f = [[CreditContentViewController alloc] init];
        f.type = [notif.userInfo objectForKey:kSETTINGS_KEY];
        [self _animatePushVC:f];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kSETTINGS_CLOUD_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock: ^(NSNotification* notif){
        if ([self _checkInteractionAndBlock]) {
            return;
        }
        CloudViewController* f = [[CloudViewController alloc] init];
        f.cloudServiceName = [notif.userInfo objectForKey:kSETTINGS_KEY];
        [self _animatePushVC:f];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kSETTINGS_MAIN_ACCOUNT_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock: ^(NSNotification* notif){
        if ([self _checkInteractionAndBlock]) {
            return;
        }
        DefaultAccountViewController* f = [[DefaultAccountViewController alloc] init];
        [self _animatePushVC:f];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kSETTINGS_SWIPE_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock: ^(NSNotification* notif){
        if ([self _checkInteractionAndBlock]) {
            return;
        }
        QuickSwipeViewController* f = [[QuickSwipeViewController alloc] init];
        [self _animatePushVC:f];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kSETTINGS_NOTIF_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock: ^(NSNotification* notif){
        if ([self _checkInteractionAndBlock]) {
            return;
        }
        NotificationViewController* f = [[NotificationViewController alloc] init];
        [self _animatePushVC:f];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kSETTINGS_ACCOUNT_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock: ^(NSNotification* notif){
        if ([self _checkInteractionAndBlock]) {
            return;
        }
        AccountViewController* f = [[AccountViewController alloc] init];
        f.account = [notif.userInfo objectForKey:kSETTINGS_KEY];
        [self _animatePushVC:f];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kSETTINGS_ADD_ACCOUNT_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock: ^(NSNotification* notif){
        if ([self _checkInteractionAndBlock]) {
            return;
        }
        AddAccountViewController* f = [[AddAccountViewController alloc] init];
        [self _animatePushVC:f];
    }];
    
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kPRESENT_CONVERSATION_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock: ^(NSNotification* notif){
        if ([self _checkInteractionAndBlock]) {
            return;
        }
        ConversationViewController* f = [[ConversationViewController alloc] init];
        f.conversation = [notif.userInfo objectForKey:kPRESENT_CONVERSATION_KEY];
        [self _animatePushVC:f];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kPRESENT_CONVERSATION_ATTACHMENTS_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock: ^(NSNotification* notif){
        if ([self _checkInteractionAndBlock]) {
            return;
        }
        AttachmentsViewController* f = [[AttachmentsViewController alloc] init];
        f.conversation = [notif.userInfo objectForKey:kPRESENT_CONVERSATION_KEY];
        [self _animatePushVC:f];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kPRESENT_CONTACTS_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock: ^(NSNotification* notif){
        if ([self _checkInteractionAndBlock]) {
            return;
        }
        ContactsViewController* f = [[ContactsViewController alloc] init];
        f.mail = [notif.userInfo objectForKey:kPRESENT_MAIL_KEY];
        [self _animatePushVC:f];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kPRESENT_SEARCH_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock: ^(NSNotification* notif){
        if ([self _checkInteractionAndBlock]) {
            return;
        }
        SearchViewController* f = [[SearchViewController alloc] init];
        [self _animatePushVC:f];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kPRESENT_EDITMAIL_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock: ^(NSNotification* notif){
        if ([self _checkInteractionAndBlock]) {
            return;
        }
        EditMailViewController* f = [[EditMailViewController alloc] init];
        f.mail = [notif.userInfo objectForKey:kPRESENT_MAIL_KEY];
        [self _animatePushVC:f];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kPRESENT_DROPBOX_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock: ^(NSNotification* notif){
        if ([self _checkInteractionAndBlock]) {
            return;
        }
        
        DropboxBrowserViewController *f = [[DropboxBrowserViewController alloc]init];
        f.rootViewDelegate = [notif.userInfo objectForKey:kPRESENT_DELEGATE_KEY];
        f.deliverDownloadNotifications = YES;
        f.shouldDisplaySearchBar = YES;
        
        //[self _animatePushVC:f];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kBACK_TO_INBOX_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock: ^(NSNotification* notif){
        
        [[SearchRunner getSingleton] cancel];
        
        if (self.viewControllers.count>3) {
            NSRange toRemove;
            toRemove.location = 2;
            toRemove.length = self.viewControllers.count - 3;
            [self.viewControllers removeObjectsInRange:toRemove];
        }
        
        if (self.viewControllers.count>2) {
            MailListViewController* f = [[MailListViewController alloc] initWithFolder:FolderTypeWith(FolderTypeInbox, 0)];
            [self.viewControllers replaceObjectAtIndex:1 withObject:f];
        }
        
        
        [[NSNotificationCenter defaultCenter] postNotificationName:kBACK_NOTIFICATION object:nil];
    }];
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kBACK_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock: ^(NSNotification* notif){
        [[SearchRunner getSingleton] cancel];

        if (self.viewControllers.count == 1) {
            return;
        }
        
        if ([self _checkInteractionAndBlock]) {
            return;
        }
        
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
        //
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
    
    [[NSNotificationCenter defaultCenter] addObserverForName:kACCOUNT_CHANGED_NOTIFICATION object:nil queue:[NSOperationQueue mainQueue]  usingBlock: ^(NSNotification* notif){
        
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
            MailListViewController* inbox = [[MailListViewController alloc] initWithFolder:[AppSettings typeOfFolder:[Accounts sharedInstance].currentAccount.currentFolderIdx forAccount:[AppSettings activeAccount]]];
            inbox.view.frame = self.contentView.bounds;
            nextView = inbox.view;
            
            self.viewControllers = [NSMutableArray arrayWithObjects:f, inbox, nil];
        }
        
        [self _manageCocoaButton:[f haveCocoaButton]];
        
        [self.contentView insertSubview:nextView belowSubview:lastView];
        
        [lastView removeFromSuperview];
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
        if (res != nil)
            return res;
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
        FolderType folder = [AppSettings typeOfFolder:[A currentAccount].currentFolderIdx forAccount:[A currentAccountIdx]+1];
        [[A currentAccount] releaseContent];
        A.currentAccountIdx = button.tag;
        
        if(folder.type != FolderTypeUser) {
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
    
    NSArray* alls = [Accounts sharedInstance].getAllTheAccounts;
    NSMutableArray* buttons = [NSMutableArray arrayWithCapacity:alls.count];
    NSInteger currentAIdx = [Accounts sharedInstance].currentAccountIdx;
    
    NSInteger idx = 0;
    for (Account* a in alls) {
        
        if (idx == currentAIdx) {
            idx++;
            continue;
        }
        
        UIButton* b = [[UIButton alloc] initWithFrame:baseRect];
        
        b.backgroundColor = a.userColor;
        [b setTitle:a.codeName forState:UIControlStateNormal];
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

-(BOOL) cocoabuttonLongPress:(CocoaButton *)cocoabutton
{
    InViewController* currentVC = [self.viewControllers lastObject];
    
    if ([currentVC conformsToProtocol:@protocol(CocoaButtonDatasource)]) {
        id<CocoaButtonDatasource> src = (id<CocoaButtonDatasource>)currentVC;
        return [src cocoabuttonLongPress:cocoabutton];
    }
    
    self.askAccountsButton = YES;
    return YES;
}

-(BOOL) automaticCloseFor:(CocoaButton *)cocoabutton
{
    InViewController* currentVC = [self.viewControllers lastObject];
    
    if ([currentVC conformsToProtocol:@protocol(CocoaButtonDatasource)]) {
        id<CocoaButtonDatasource> src = (id<CocoaButtonDatasource>)currentVC;
        return [src automaticCloseFor:cocoabutton];
    }
    
    return YES;
}

#pragma mark - Background Sync

- (void)refreshWithCompletionHandler:(CRefreshCompletionHandler)completionHandler
{
    for (UIViewController* vc in self.viewControllers) {
        if ([vc isKindOfClass:[FolderViewController class]]) {
            [((FolderViewController*)vc) refreshWithCompletionHandler:completionHandler];
            break;
        }
    }
}


@end