//
//  CloudViewController.m
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 03/09/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "CloudViewController.h"

#import <Google/SignIn.h>
#import <BoxBrowseSDK/BoxBrowseSDK.h>
#import "DropboxBrowserViewController.h"

@interface CloudViewController () <BOXFolderViewControllerDelegate,GIDSignInUIDelegate>

@property (nonatomic, readwrite, strong) UINavigationController *navControllerForBrowseSDK;

@property (nonatomic, weak) UIImageView* mainImage;
@property (nonatomic, weak) UIButton* mainButton;

@end

@implementation CloudViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    
    self.view.backgroundColor = [UIGlobal standardLightGrey];
    
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    
    UINavigationItem* item = [[UINavigationItem alloc] initWithTitle:@""];
    item.leftBarButtonItem = [self backButtonInNavBar];
    item.titleView = [WhiteBlurNavBar titleViewForItemTitle: self.cloudServiceName];
    
    [GIDSignIn sharedInstance].uiDelegate = self;

    UIImageView* iv = [[UIImageView alloc] initWithFrame:CGRectMake(0, 50, screenBounds.size.width, 120)];
    iv.contentMode = UIViewContentModeCenter;
    
    NSString* mini = [self.cloudServiceName lowercaseString];
    
    NSInteger posSpace = [mini rangeOfString:@" "].location;
    
    if (posSpace != NSNotFound) {
        mini = [mini substringToIndex:posSpace];
    }
    
    
    iv.highlightedImage = [UIImage imageNamed:[NSString stringWithFormat:@"%@_on", mini]];
    iv.image = [UIImage imageNamed:[NSString stringWithFormat:@"%@_off", mini]];
    
    [self.view addSubview:iv];
    self.mainImage = iv;
    
    UIButton* action = [[UIButton alloc] initWithFrame:CGRectMake(0, 170, screenBounds.size.width, 52)];
    action.backgroundColor = [UIColor whiteColor];
    action.tintColor = [UIGlobal standardBlue];
    
    NSString* link = NSLocalizedString(@"Link account", @"Link account");
    NSString* unlink = NSLocalizedString(@"Unlink account", @"Link account");
    
    [action setTitle:link forState:UIControlStateNormal];
    [action setTitle:unlink forState:UIControlStateSelected];
    [action setTitle:unlink forState:UIControlStateSelected|UIControlStateHighlighted];
    [action setTitleColor:[UIGlobal standardBlue] forState:UIControlStateNormal];
    [action setTitleColor:[UIColor blackColor] forState:UIControlStateSelected];
    [action setTitleColor:[UIColor lightGrayColor] forState:UIControlStateHighlighted];
    [action setTitleColor:[UIColor lightGrayColor] forState:UIControlStateHighlighted|UIControlStateSelected];
    
    [action addTarget:self action:@selector(_tap) forControlEvents:UIControlEventTouchUpInside];
    
    [self.view addSubview:action];
    self.mainButton = action;
    
    [self setupSimpleNavBarWith:item andWidth:screenBounds.size.width];
    
}

-(void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    if([self.cloudServiceName isEqualToString:@"Dropbox"]){
        if ([[DBSession sharedSession] isLinked]) {
            [self.mainButton setSelected:YES];
            [self.mainImage setHighlighted:YES];
        }
    }
}

-(void) _tap
{
    //self.mainButton.selected = !self.mainButton.selected;
   // self.mainImage.highlighted = !self.mainImage.highlighted;
    
    if([self.cloudServiceName isEqualToString:@"Dropbox"]){
        if (![[DBSession sharedSession] isLinked]) {
            [[DBSession sharedSession] linkFromController:self];
        } else {
            [[DBSession sharedSession] unlinkAll];
            UIAlertController* alertView = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"Account Unlinked!", @"Title of alert view when unlinking Dropbox")
                                                                               message:NSLocalizedString(@"Your dropbox account has been unlinked", @"Message of alert view when unlinking Dropbox")
                                                                        preferredStyle:UIAlertControllerStyleAlert];
            [alertView addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Ok", @"Confirmation of alert view when unlinking Dropbox") style:UIAlertActionStyleDefault handler:nil]];
            
            [self presentViewController:alertView
                               animated:YES
                             completion:nil];
        }
    }
    else if([self.cloudServiceName isEqualToString:@"Google Drive"]){
        if (![[GIDSignIn sharedInstance] hasAuthInKeychain]) {
            [[GIDSignIn sharedInstance] signIn];
        }
    }
    else if([self.cloudServiceName isEqualToString:@"Box"]){
        [BOXContentClient setClientID:@"tut475ti6ir0y715hx0gddn8vtkk91fh" clientSecret:@"ftiL9SaaR8ScITDpanlZg4whbbOkllNz"];
        BOXFolderViewController *folderViewController = [[BOXFolderViewController alloc] initWithContentClient:[BOXContentClient defaultClient]];
        folderViewController.delegate = self;
        
        // You must load it in a UINavigationController.
        self.navControllerForBrowseSDK = [[UINavigationController alloc] initWithRootViewController:folderViewController];
        [self presentViewController:self.navControllerForBrowseSDK animated:YES completion:nil];
    }
    else {
        [ViewController presentAlertWIP:@"do the link…"];
    }
}

-(BOOL) haveCocoaButton
{
    return NO;
}

- (void)itemsViewControllerDidTapCloseButtton:(BOXItemsViewController *)itemsViewController
{
    // If you don't implement this, the navigation controller will be dismissed for you.
    // Only implement if you need to customize behavior.
    NSLog(@"Did tap close button");
    [self.navControllerForBrowseSDK dismissViewControllerAnimated:YES completion:nil];
}

@end
