//
//  PreviewViewController.m
//  CocoaMail
//
//  Created by Christopher Hockley on 15/01/16.
//  Copyright © 2016 Christopher Hockley. All rights reserved.
//

#import "PreviewViewController.h"
#import "Persons.h"
#import "MCOMessageView.h"
#import "Accounts.h"
#import "EmailProcessor.h"

@interface PreviewViewController () <MCOMessageViewDelegate>

@property (nonatomic, strong) UIView* htmlView;

@property (nonatomic) CGFloat posXtoUsers;
@property (nonatomic, weak) UIImageView* favori;
@property (nonatomic, weak) UIImageView* markAsRead;

@property (nonatomic) CGFloat height;

@end

@implementation PreviewViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIColor clearColor];
    
    [self setupWithMail:[self.conversation firstMail]];
}

-(void) setupWithMail:(Mail*)mail
{
    [self.view.subviews.firstObject removeFromSuperview];
    
    Person* person = [[Persons sharedInstance] getPersonID:mail.fromPersonID];
    
    CGFloat WIDTH = self.view.bounds.size.width;
    
    UIImage* rBack = [[UIImage imageNamed:@"cell_mail_unread"] resizableImageWithCapInsets:UIEdgeInsetsMake(22, 30, 22, 30)];
    UIImageView* inIV = [[UIImageView alloc] initWithImage:rBack];
    
    inIV.frame = self.view.frame;
    
    UILabel* n = [[UILabel alloc] initWithFrame:CGRectMake(44, 0, inIV.bounds.size.width - 88, 45)];
    n.textColor = [UIColor colorWithWhite:0.47 alpha:1.0];
    n.font = [UIFont systemFontOfSize:16];
    n.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [inIV addSubview:n];
    
    UIView* perso = [[UIView alloc] initWithFrame:CGRectMake(5.5, 5.5, 33, 33)];
    perso.backgroundColor = [UIColor clearColor];
    perso.autoresizingMask = UIViewAutoresizingFlexibleRightMargin;
    [perso addSubview:[person badgeView]];
    [inIV addSubview:perso];
    
    CGFloat xPos = inIV.bounds.size.width - 33.f - 5.5;
    CGFloat step = 33.f + 1.f;
    
    NSArray* subarray = mail.toPersonID;
    
    if (mail.toPersonID.count>3) {
        NSRange r;
        r.length = 2;
        r.location = mail.toPersonID.count - 2;
        
        NSMutableArray* tmp = [[mail.toPersonID subarrayWithRange:r] mutableCopy];
        
        [tmp insertObject:@([Persons sharedInstance].idxMorePerson) atIndex:0];
        subarray = tmp;
    }
    
    for (NSNumber* userID in subarray) {
        
        Person* p = [[Persons sharedInstance] getPersonID:[userID integerValue]];
        UIView* perso = [[UIView alloc] initWithFrame:CGRectMake(xPos, 5.5, 33, 33)];
        perso.backgroundColor = [UIColor clearColor];
        perso.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        [perso addSubview:[p badgeView]];
        [inIV addSubview:perso];
        
        xPos -= step;
    }
    
    self.posXtoUsers = xPos + 33.f;
    
    UIView* sep = [[UIView alloc] initWithFrame:CGRectMake(0, 44, inIV.bounds.size.width, 1)];
    sep.backgroundColor = [UIColor colorWithWhite:0.96 alpha:1.0];
    sep.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [inIV addSubview:sep];
    
    CGSize size = CGSizeMake(WIDTH - 30,  self.view.frame.size.height - 48);
    
    size.width = ceilf(size.width);
    
    const CGFloat topBorder = 14.f;
    
    MCOMessageView* view = [[MCOMessageView alloc]initWithFrame:CGRectMake(8, 48.f + topBorder, size.width, size.height)];
    [view setMail:mail];
    view.delegate = self;
    self.htmlView = view;
    
    [inIV addSubview:self.htmlView];
    
    if (person.isGeneric) {
        n.text = mail.email.sender.displayName;;
    }
    else {
        n.text = person.name;
    }
    
    inIV.userInteractionEnabled = YES;
    
    inIV.clipsToBounds = YES;
    
    [self.view addSubview:inIV];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

#pragma mark - Preview Actions

- (NSArray<id<UIPreviewActionItem>> *)previewActionItems
{
    // setup a list of preview actions
    NSString* title1;
    
    if ([self.conversation firstMail].isRead) {
        title1 = @"Mark as Unread";
    }
    else {
        title1 = @"Mark as Read";
    }
    
    NSString* title2;
    
    if ([self.conversation isFav]) {
        title2 = @"Remove Star";
    }
    else {
        title2 = @"Mark as Starred";
    }
    
    UIPreviewAction *action1 = [UIPreviewAction actionWithTitle:title1 style:UIPreviewActionStyleDefault handler:^(UIPreviewAction * _Nonnull action, UIViewController * _Nonnull previewViewController) {
        [[self.conversation firstMail] toggleRead];
        [self.table reloadRowsAtIndexPaths:@[self.indexPath] withRowAnimation:UITableViewRowAnimationFade];
    }];
    
    UIPreviewAction *action2 = [UIPreviewAction actionWithTitle:title2 style:UIPreviewActionStyleDefault handler:^(UIPreviewAction * _Nonnull action, UIViewController * _Nonnull previewViewController) {
        [self.conversation toggleFav];
        [self.table reloadRowsAtIndexPaths:@[self.indexPath] withRowAnimation:UITableViewRowAnimationFade];
    }];
    
    UIPreviewAction *action3 = [UIPreviewAction actionWithTitle:NSLocalizedString(@"quick-swipe.archive", @"Archive") style:UIPreviewActionStyleDestructive handler:^(UIPreviewAction * _Nonnull action, UIViewController * _Nonnull previewViewController) {
        Account* ac = [[Accounts sharedInstance] getAccount:self.conversation.accountIdx];
        
        SEL selector = NSSelectorFromString(@"deleteRow:");
        
        if ([EmailProcessor getSingleton].updateSubscriber != nil && [[EmailProcessor getSingleton].updateSubscriber respondsToSelector:selector]) {
            ((void (*)(id, SEL, Conversation*))[[EmailProcessor getSingleton].updateSubscriber methodForSelector:selector])([EmailProcessor getSingleton].updateSubscriber, selector,self.conversation);
        }
        
        [ac moveConversation:self.conversation from:[AppSettings typeOfFolder:[Accounts sharedInstance].currentAccount.currentFolderIdx forAccountIndex:kActiveAccountIndex] to:FolderTypeWith(FolderTypeAll, 0)];
    }];

    // add them to an arrary
    NSArray *actions = @[action1, action2, action3];
    
    // and return them
    return actions;
}

- (void)webViewLoaded:(UIWebView *)webView
{
    
}

@end
