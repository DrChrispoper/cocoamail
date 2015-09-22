//
//  CloudViewController.m
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 03/09/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "CloudViewController.h"

@interface CloudViewController ()

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


-(void) _tap
{
    self.mainButton.selected = !self.mainButton.selected;
    self.mainImage.highlighted = !self.mainImage.highlighted;
    
    [ViewController presentAlertWIP:@"do the link…"];
}

-(BOOL) haveCocoaButton
{
    return NO;
}


@end
