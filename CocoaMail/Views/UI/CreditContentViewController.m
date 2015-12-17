//
//  CreditContentViewController.m
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 06/09/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "CreditContentViewController.h"


@interface CreditContentViewController () <UIScrollViewDelegate>

@property (nonatomic, weak) UIView* contentView;
@property (nonatomic, weak) UIScrollView* scrollView;

@property (nonatomic, strong) NSString* barTitle;

@property (nonatomic, strong) NSArray* btnActions;

@end

@implementation CreditContentViewController

-(void) viewDidLoad
{
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIGlobal standardLightGrey];
    
    UINavigationItem* item = [[UINavigationItem alloc] initWithTitle:@""];
    item.leftBarButtonItem = [self backButtonInNavBar];
    
    [self _setup];

    item.titleView = [WhiteBlurNavBar titleViewForItemTitle:self.barTitle];
    
    [self setupNavBarWith:item overMainScrollView:self.scrollView];
}

-(void) cleanBeforeGoingBack
{
    self.scrollView.delegate = nil;
}

-(BOOL) haveCocoaButton
{
    return NO;
}

-(void) _setup
{
    
    NSString* image;
    NSString* text;
    NSString* name;
    
    
    if ([self.type isEqualToString:@"RF"]) {
        image = @"cocoamail";
        text = NSLocalizedString(@"credits.bio.reinald",@"");
        name = @"Reinald Freling";
        self.barTitle = @"Product Design";
        self.btnActions = @[@"TWITTER", @"MAIL", @"LINKEDIN", @"FACEBOOK"];
    }
    else if ([self.type isEqualToString:@"CH"]) {
        image = @"cocoamail";
        text = NSLocalizedString(@"credits.bio.christopher",@"");
        name = @"Christopher Hockley";
        self.barTitle = @"Development";
        self.btnActions = @[@"TWITTER", @"MAIL", @"LINKEDIN"];
    }
    else if ([self.type isEqualToString:@"CB"]) {
        image = @"cocoamail";
        text = NSLocalizedString(@"credits.bio.christophe",@"");
        name = @"Christophe Branche";
        self.barTitle = @"UI/UX Design";
        self.btnActions = @[@"MAIL", @"LINKEDIN"];
    }
    else if ([self.type isEqualToString:@"PCC"]) {
        image = @"cocoamail";
        text = NSLocalizedString(@"credits.bio.pascal",@"");
        name = @"Pascal Costa-Cunha";
        self.barTitle = @"Helping hand";
        self.btnActions = @[@"LINKEDIN"];
    }
    else if ([self.type isEqualToString:@"T"]) {
        image = nil;
        text = NSLocalizedString(@"credits.bio.thanks",@"");
        name = nil;
        self.barTitle = @"Thanks";
    }
    
    
    CGFloat posY = 44.f ;
    
    UIView* contentView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 10000)];
    contentView.backgroundColor = [UIColor clearColor];
    
    CGFloat WIDTH = contentView.frame.size.width;
    
    if (image != nil) {
        
        UIView* bigOne = [[UIView alloc] initWithFrame:CGRectMake(0, posY, WIDTH, 160)];
        
        bigOne.backgroundColor = self.view.backgroundColor;
        
        UIImageView* iv = [[UIImageView alloc] initWithImage:[UIImage imageNamed:image]];
        
        CGPoint c = CGPointMake(WIDTH / 2, 60);
        iv.center = c;
        [bigOne addSubview:iv];
        
        CGFloat WIDTH_LBL = 240;
        
        UILabel* lbl = [[UILabel alloc] initWithFrame:CGRectMake((WIDTH - WIDTH_LBL) / 2. , 105, WIDTH_LBL, 50)];
        lbl.backgroundColor = [UIColor clearColor];
        lbl.text = name;
        lbl.numberOfLines = 0;
        [bigOne addSubview:lbl];
        lbl.textAlignment = NSTextAlignmentCenter;
        
        [contentView addSubview:bigOne];
        posY += bigOne.frame.size.height;
    }

    UITextView* tv = [[UITextView alloc] initWithFrame:CGRectMake(0, posY, WIDTH-32, 200)];
    tv.font = [UIFont systemFontOfSize:15];
    tv.scrollEnabled = NO;
    tv.userInteractionEnabled = NO;
    tv.text = text;
    [tv setEditable:NO];
    [tv sizeToFit];
    
    UIView* supportTV = [[UIView alloc] initWithFrame:CGRectInset(tv.frame, -16, -25)];
    supportTV.backgroundColor = [UIColor whiteColor];
    [supportTV addSubview:tv];

    CGRect f = supportTV.frame;
    f.origin.x = 0;
    f.origin.y = posY;
    f.size.width = WIDTH;
    supportTV.frame = f;
    
    f = tv.frame;
    f.size.width = WIDTH - 32;
    f.origin.x = 16;
    f.origin.y = 25;
    tv.frame = f;
    
    posY += supportTV.frame.size.height;
    [contentView addSubview:supportTV];
    
    if (self.btnActions.count>0) {
        
        CGFloat height = MAX(60, self.view.frame.size.height - 20 - posY);
        
        UIView* iconView = [[UIView alloc] initWithFrame:CGRectMake(0, posY, WIDTH, height)];
        iconView.backgroundColor = [UIColor whiteColor];
        
        NSMutableArray* btns = [NSMutableArray arrayWithCapacity:self.btnActions.count];
        
        for (NSString* action in self.btnActions) {

            NSString* imgNameOff = nil;
            NSString* imgNameOn = nil;
            
            if ([action isEqualToString:@"TWITTER"]) {
                imgNameOff = @"credits_twitter_off";
                imgNameOn = @"credits_twitter_on";
            }
            else if ([action isEqualToString:@"LINKEDIN"]) {
                imgNameOff = @"credits_linkedin_off";
                imgNameOn = @"credits_linkedin_on";
            }
            else if ([action isEqualToString:@"MAIL"]) {
                imgNameOff = @"edit_off";
                imgNameOn = @"edit_on";
            }
            else if ([action isEqualToString:@"FACEBOOK"]) {
                imgNameOff = @"credits_facebook_off";
                imgNameOn = @"credits_facebook_on";
            }
            
            UIButton* b = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 33, 33)];
            [b setImage:[[UIImage imageNamed:imgNameOff] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateNormal];
            [b setImage:[[UIImage imageNamed:imgNameOn]  imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate] forState:UIControlStateHighlighted];
            [b addTarget:self action:@selector(_tapButton:) forControlEvents:UIControlEventTouchUpInside];
            
            b.tintColor = [UIGlobal noImageBadgeColor];
            b.tag = btns.count;
            [btns addObject:b];
        }
        
        CGFloat stepX = WIDTH / (btns.count + 1);
        CGFloat posX = 0;
        
        for (UIButton* b in btns) {
            posX += stepX;
            b.center = CGPointMake(posX, height - 40);
            [iconView addSubview:b];
            
            CGRect bf = b.frame;
            bf.origin.x = floorf(bf.origin.x);
            b.frame = bf;
        }
        
        [contentView addSubview:iconView];
        posY += iconView.frame.size.height;
        
    }
    
    CGRect fcv = contentView.frame;
    fcv.size.height = posY + 20.f;
    contentView.frame = fcv;
    
    UIScrollView* sv = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    sv.contentSize = contentView.frame.size;
    [sv addSubview:contentView];
    sv.backgroundColor = self.view.backgroundColor;
    sv.scrollIndicatorInsets = UIEdgeInsetsMake(44, 0, 0, 0);
    
    self.contentView = contentView;
    
    [self.view addSubview:sv];
    sv.delegate = self;
    sv.alwaysBounceVertical = YES;
    self.scrollView = sv;
}

-(void) _tapButton:(UIButton*)button
{
    [ViewController presentAlertWIP:@"manage actions here…"];
}

@end
