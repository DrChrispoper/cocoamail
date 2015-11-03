 //
//  ConversationViewController.m
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 03/08/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "ConversationViewController.h"

#import "Persons.h"
#import "Accounts.h"
#import "MCOMessageView.h"
#import "AppSettings.h"
#import "UserFolderViewController.h"
#import "EmailProcessor.h"
#import <QuickLook/QuickLook.h>
#import "StringUtil.h"
#import "ImapSync.h"

@class SingleMailView;

@protocol SingleMailViewDelegate <NSObject>

-(Mail*) mailDisplayed:(SingleMailView*)mailView;
-(void) mailView:(SingleMailView*)mailView changeHeight:(CGFloat)deltaHeight;
-(void) makeConversationFav:(BOOL)isFav;
-(void) openURL:(NSURL*)url;
-(void) shareAttachment:(Attachment*)att;

@end


@interface ConversationViewController () <UIScrollViewDelegate, SingleMailViewDelegate, UserFolderViewControllerDelegate, QLPreviewControllerDataSource, QLPreviewControllerDelegate, UIDocumentInteractionControllerDelegate> {
    NSArray* _activityItems;
}

@property (nonatomic, weak) UIView* contentView;
@property (nonatomic, weak) UIScrollView* scrollView;

@property (nonatomic, strong) NSMutableArray* allMailViews;

@property (nonatomic) CCMFolderType folder;

@property (nonatomic, strong) UserFolderViewController* chooseUserFolder;

@end


@interface SingleMailView : UIView <MCOMessageViewDelegate, CCMAttachmentViewDelegate>

-(void) setupWithText:(NSString*)texte extended:(BOOL)extended;

@property (nonatomic, strong) NSString* textContent;
@property (nonatomic, strong) UIView* htmlView;
@property (nonatomic, weak) id<SingleMailViewDelegate> delegate;

@property (nonatomic) CGFloat posXtoUsers;
@property (nonatomic, weak) UIImageView* favori;
@property (nonatomic, weak) UIImageView* markAsRead;

@property (nonatomic) NSInteger idxInConversation;
@property (nonatomic) CGFloat height;

@property (nonatomic, weak) UIButton* favoriBtn;

-(void) updateFavUI:(BOOL)isFav;

@end

@implementation ConversationViewController

-(void) viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    //
    Persons* p = [Persons sharedInstance];
    
    if (p.idxMorePerson == 0) {
        Person* more = [Person createWithName:nil email:nil icon:[UIImage imageNamed:@"recipients_off"] codeName:nil];
        p.idxMorePerson = [p addPerson:more];
    }
    // TODO put it elsewhere
    
    self.folder = [AppSettings typeOfFolder:[Accounts sharedInstance].currentAccount.currentFolderIdx forAccountIndex:kActiveAccountIndex];

    
    self.view.backgroundColor = [UIGlobal standardLightGrey];
    
    Mail* mail = [self.conversation firstMail];
    
    UINavigationItem* item = [[UINavigationItem alloc] initWithTitle:@""];
    
    item.leftBarButtonItem = [self backButtonInNavBar];

    if ([self.conversation haveAttachment]) {
        UIButton* attach = [WhiteBlurNavBar navBarButtonWithImage:@"attachment_off" andHighlighted:@"attachment_on"];
        [attach addTarget:self action:@selector(_attach) forControlEvents:UIControlEventTouchUpInside];
        item.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:attach];
    }
    
    item.titleView = [WhiteBlurNavBar titleViewForItemTitle:mail.title];
    
    [self _setup];
    
    [self setupNavBarWith:item overMainScrollView:self.scrollView];
}

-(void) cleanBeforeGoingBack
{
    self.scrollView.delegate = nil;    
}

-(void) _attach
{
    [[NSNotificationCenter defaultCenter] postNotificationName:kPRESENT_CONVERSATION_ATTACHMENTS_NOTIFICATION object:nil
                                                      userInfo:@{kPRESENT_CONVERSATION_KEY:self.conversation}];
}

-(NSArray*) nextViewControllerInfos
{
    if ([self.conversation haveAttachment]) {
        return @[kPRESENT_CONVERSATION_ATTACHMENTS_NOTIFICATION, self.conversation];
    }

    return [super nextViewControllerInfos];
}

-(void) _setup
{
    
    CGFloat posY = 44.f + 5;
    
    
    UIView* contentView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 10000)];
    contentView.backgroundColor = [UIColor clearColor];
  
    // title
    UILabel* lbl = [[UILabel alloc] initWithFrame:self.view.bounds];
    lbl.text = [self.conversation firstMail].title;
    lbl.numberOfLines = 0;
    lbl.textColor = [UIColor whiteColor];
    //lbl.font = [UIFont boldSystemFontOfSize:16];
    //lbl.textAlignment = NSTextAlignmentCenter;
    lbl.font = [UIFont systemFontOfSize:16];
    lbl.textAlignment = NSTextAlignmentNatural;
    
    [lbl sizeToFit];
    
    CGRect tf = lbl.frame;
    tf.size = CGSizeMake(self.view.bounds.size.width - 16, tf.size.height + 36);
    tf.origin = CGPointMake(8, -tf.size.height + 30);
    lbl.frame = tf;
    
    UIView* supportTitle = [[UIView alloc] initWithFrame:tf];
    
    supportTitle.backgroundColor = [UIColor colorWithWhite:180. / 255. alpha:1.0];
    supportTitle.layer.cornerRadius = 20;
    supportTitle.layer.masksToBounds = YES;
    
    tf.origin = CGPointMake(8, 15);
    tf.size.width -= 16;
    tf.size.height -= 30;
    lbl.frame = tf;
    lbl.backgroundColor = supportTitle.backgroundColor;
    
    [supportTitle addSubview:lbl];
    
    [contentView addSubview:supportTitle];
    //
    
    self.allMailViews = [NSMutableArray arrayWithCapacity:self.conversation.mails.count];
    
    NSInteger idx = 0;
    
    for (Mail* m in self.conversation.mails) {
    
        NSString* day = m.day;
        NSString* hour = m.hour;
        NSString* mail = m.content;

        posY = [self _addHeaderDay:day hour:hour atYPos:posY inView:contentView];
        posY = [self _addMail:mail withIndex:idx extended:(idx==0) atYPos:posY inView:contentView];
        
        idx++;
    }
    
    CGRect f = contentView.frame;
    f.size.height = posY + 44.f;
    contentView.frame = f;
    
    
    if (contentView.frame.size.height > self.view.bounds.size.height - 40.f) {
        f.size.height += 40.f;
        contentView.frame = f;
    }
    
    
    UIScrollView* sv = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    sv.contentSize = contentView.frame.size;
    [sv addSubview:contentView];
    sv.backgroundColor = self.view.backgroundColor;
    sv.scrollIndicatorInsets = UIEdgeInsetsMake(44, 0, 0, 0);
    self.contentView = contentView;
    
    [self.view addSubview:sv];
    sv.delegate = self;
    sv.alwaysBounceVertical = YES;
    sv.scrollsToTop = YES;
    self.scrollView = sv;
}

-(Mail*) mailDisplayed:(SingleMailView*)mailView;
{
    return self.conversation.mails[mailView.idxInConversation];
}

-(void) makeConversationFav:(BOOL)isFav
{
    //Account* ac = [[Accounts sharedInstance] currentAccount];
    //[ac manage:self.conversation isFav:isFav];
    
    for (SingleMailView* smv in self.allMailViews) {
        [smv updateFavUI:isFav];
    }
}

-(void) mailView:(SingleMailView*)mailView changeHeight:(CGFloat)deltaHeight
{
    
    CGFloat limite = mailView.frame.origin.y;
    
    for (UIView* v in self.contentView.subviews) {
        
        if (v.frame.origin.y > limite) {
            CGRect f = v.frame;
            f.origin.y += deltaHeight;
            v.frame = f;
        }
    }
    
    UIView* lastView = self.contentView.subviews.lastObject;
    CGFloat maxY = lastView.frame.origin.y + lastView.frame.size.height;
    
    CGRect ctF = self.contentView.frame;
    ctF.size.height = maxY + 44;
    self.contentView.frame = ctF;
    
    if (self.contentView.frame.size.height > self.view.bounds.size.height - 40.f) {
        ctF.size.height += 40.f;
        self.contentView.frame = ctF;
    }
    
    
    self.scrollView.contentSize = self.contentView.frame.size;
}

-(void) openURL:(NSURL*)url
{
    QLPreviewController* previewController = [[QLPreviewController alloc]init];
    previewController.delegate = self;
    previewController.dataSource = self;
    previewController.currentPreviewItemIndex = 0;
    
    _activityItems = @[url];
    
    [self.view.window.rootViewController presentViewController:previewController animated:YES completion:nil];
}

#pragma mark - QLPreviewControllerDataSource

-(NSInteger) numberOfPreviewItemsInPreviewController:(QLPreviewController*)previewController
{
    return _activityItems.count;
}

-(id) previewController:(QLPreviewController*)previewController previewItemAtIndex:(NSInteger)index
{
    return _activityItems[index];
}

-(void) previewControllerWillDismiss:(QLPreviewController*)controller
{
    //    [[UIApplication sharedApplication] setStatusBarHidden:YES];
    //    [self setNeedsStatusBarAppearanceUpdate];
}

-(void) shareAttachment:(Attachment*)att
{
    NSString* filePath = [StringUtil filePathInDocumentsDirectoryForAttachmentFileName:att.fileName];
    [att.data writeToFile:filePath atomically:YES];
    NSURL* URL = [NSURL fileURLWithPath:filePath];
    
    UIDocumentInteractionController* documentInteractionController = [UIDocumentInteractionController interactionControllerWithURL:URL];
    documentInteractionController.delegate = self;
    [documentInteractionController presentOpenInMenuFromRect:CGRectMake(0, 0, 0, 0) inView:self.view animated:YES];
     
}

-(CGFloat) _addMail:(NSString*)mail withIndex:(NSInteger)idx extended:(BOOL)extended atYPos:(CGFloat)posY inView:(UIView*)v
{
    
    CGFloat WIDTH = self.view.bounds.size.width;
    
    SingleMailView* smv = [[SingleMailView alloc] initWithFrame:CGRectMake(0, posY, WIDTH, 100)];
    smv.idxInConversation = idx;
    smv.delegate = self;
    
    [smv setupWithText:mail extended:extended];
    
    CGFloat height = smv.bounds.size.height;
    [v addSubview:smv];
    
    [self.allMailViews addObject:smv];
    
    return posY + height + 2;
}

-(CGFloat) _addHeaderDay:(NSString*)day hour:(NSString*)hour atYPos:(CGFloat)posY inView:(UIView*)v
{
    CGFloat WIDTH = self.view.bounds.size.width;
    
    UIView* support = [[UIView alloc] initWithFrame:CGRectMake(0, posY, WIDTH, 20.f)];
    support.backgroundColor = [UIColor clearColor];
    [v addSubview:support];
    
    UILabel* lbl = [[UILabel alloc] initWithFrame:CGRectMake(10, 0, 160, 18)];
    lbl.backgroundColor = self.view.backgroundColor;
    lbl.text = day;
    lbl.textColor = [UIColor colorWithWhite:0.58 alpha:1.0];
    lbl.font = [UIFont systemFontOfSize:13];
    [support addSubview:lbl];
    
    UILabel* lblH = [[UILabel alloc] initWithFrame:CGRectMake(WIDTH - 160 - 10, 0, 160, 18)];
    lblH.backgroundColor = self.view.backgroundColor;
    lblH.text = hour;
    lblH.textColor = [UIColor blackColor];
    lblH.textAlignment = NSTextAlignmentRight;
    lblH.textColor = [UIColor colorWithWhite:0.58 alpha:1.0];
    lblH.font = [UIFont systemFontOfSize:13];
    [support addSubview:lblH];
    
    if (posY>50.f) {
        UIView* line = [[UIView alloc] initWithFrame:CGRectMake(WIDTH / 2.f - 1.f, -2.f, 2.f, 21.f)];
        line.backgroundColor = [UIColor whiteColor];
        [support addSubview:line];
    }
    
    return posY + 19.f;
}

-(NSArray*) buttonsWideFor:(CocoaButton*)cocoabutton
{
    UIButton* b1 = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 33, 33)];
    [b1 setImage:[UIImage imageNamed:@"edit_off"] forState:UIControlStateNormal];
    [b1 setImage:[UIImage imageNamed:@"edit_on"] forState:UIControlStateHighlighted];
    [b1 addTarget:self action:@selector(_editMail) forControlEvents:UIControlEventTouchUpInside];
    
    UIButton* b2 = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 33, 33)];
    [b2 setImage:[UIImage imageNamed:@"button_archive_off"] forState:UIControlStateNormal];
    [b2 setImage:[UIImage imageNamed:@"button_archive_on"] forState:UIControlStateHighlighted];
    b2.tag = 1;
    [b2 addTarget:self action:@selector(_chooseAction:) forControlEvents:UIControlEventTouchUpInside];
    


    UIButton* b3 = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 33, 33)];
    [b3 setImage:[UIImage imageNamed:@"button_folder_off"] forState:UIControlStateNormal];
    [b3 setImage:[UIImage imageNamed:@"button_folder_on"] forState:UIControlStateHighlighted];
    b3.tag = 2;
    [b3 addTarget:self action:@selector(_chooseAction:) forControlEvents:UIControlEventTouchUpInside];

    UIButton* b4 = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 33, 33)];
    [b4 setImage:[UIImage imageNamed:@"button_delete_off"] forState:UIControlStateNormal];
    [b4 setImage:[UIImage imageNamed:@"button_delete_on"] forState:UIControlStateHighlighted];
    b4.tag = 0;
    [b4 addTarget:self action:@selector(_chooseAction:) forControlEvents:UIControlEventTouchUpInside];
    
    /*if (self.folder.type==FolderTypeDeleted) {
        [b4 setImage:[UIImage imageNamed:@"button_delete_off"] forState:UIControlStateNormal];
        [b4 setImage:[UIImage imageNamed:@"button_delete_on"] forState:UIControlStateHighlighted];
    }
    else if (self.folder.type==FolderTypeAll) {
        [b2 setImage:[UIImage imageNamed:@"button_archive_off"] forState:UIControlStateNormal];
        [b2 setImage:[UIImage imageNamed:@"button_archive_on"] forState:UIControlStateHighlighted];
    }*/
    
    return @[b1, b2, b3, b4];
}

-(void) _editMail
{
    [[NSNotificationCenter defaultCenter] postNotificationName:kPRESENT_EDITMAIL_NOTIFICATION object:nil];
}

-(void) _executeMoveOnSelectedCellsTo:(CCMFolderType)toFolder
{
    Account* ac = [[Accounts sharedInstance] currentAccount];
    
    SEL selector = NSSelectorFromString(@"deleteRow:");
    
    if ([EmailProcessor getSingleton].updateSubscriber != nil && [[EmailProcessor getSingleton].updateSubscriber respondsToSelector:selector]) {
        ((void (*)(id, SEL, Conversation*))[[EmailProcessor getSingleton].updateSubscriber methodForSelector:selector])([EmailProcessor getSingleton].updateSubscriber, selector,self.conversation);
    }

    [ac moveConversation:self.conversation from:self.folder to:toFolder];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kBACK_NOTIFICATION object:nil];
    
    [[CocoaButton sharedButton] forceCloseButton];
}

-(void) _chooseAction:(UIButton*)button
{
    //[CocoaButton animateHorizontalButtonCancelTouch:button];
    
    CCMFolderType toFolder;
    toFolder.idx = 0;
    BOOL doNothing = NO;
    
    switch (button.tag) {
        case 0:
            toFolder.type = FolderTypeDeleted;//(self.folder.type == FolderTypeDeleted) ? FolderTypeInbox : FolderTypeDeleted;
            break;
        case 1:
            toFolder.type = FolderTypeAll;//(self.folder.type == FolderTypeAll) ? FolderTypeInbox : FolderTypeAll;
            break;
        case 2:
        {
            UserFolderViewController* ufvc = [[UserFolderViewController alloc] init];
            ufvc.delegate = self;
            
            ufvc.view.frame = self.view.bounds;
            
            [self.view addSubview:ufvc.view];
            
            self.chooseUserFolder = ufvc;
            
            
            [ViewController temporaryHideCocoaButton:YES];
            
            ufvc.view.transform = CGAffineTransformMakeTranslation(0, self.view.frame.size.height);
            
            [UIView animateWithDuration:0.3
                             animations:^{
                                 ufvc.view.transform = CGAffineTransformIdentity;
                             }];
            break;
        }
        default:
            NSLog(@"WTF !!!");
            doNothing = YES;
            break;
    }
    
    if (!doNothing) {
        [self _executeMoveOnSelectedCellsTo:toFolder];
    }
}

-(void) chooseUserFolder:(CCMFolderType)folder
{
    [self _executeMoveOnSelectedCellsTo:folder];
    [self chooseUserFolderCancel];
}

-(void) chooseUserFolderCancel
{
    UserFolderViewController* ufvc = self.chooseUserFolder;
    
    [ViewController temporaryHideCocoaButton:NO];
    
    [UIView animateWithDuration:0.3
                     animations:^{
                         ufvc.view.transform = CGAffineTransformMakeTranslation(0, self.view.frame.size.height);
                     }
                     completion:^(BOOL fini){
                         [ufvc.view removeFromSuperview];
                         self.chooseUserFolder = nil;
                     }];
    
    
}

-(NSArray*) buttonsHorizontalFor:(CocoaButton*)cocoabutton
{
    return nil;
}

-(BOOL) automaticCloseFor:(CocoaButton*)cocoabutton
{
    return YES;
}

-(BOOL) cocoabuttonLongPress:(CocoaButton*)cocoabutton
{
    return NO;
}

@end

@implementation SingleMailView

-(void) setupWithText:(NSString*)texte extended:(BOOL)extended;
{

    [self.subviews.firstObject removeFromSuperview];
    
    Mail* mail = [self.delegate mailDisplayed:self];
    Person* person = [[Persons sharedInstance] getPersonID:mail.fromPersonID];
    
    self.textContent = texte;
    
    CGFloat WIDTH = self.bounds.size.width;
    
    UIImage* rBack = [[UIImage imageNamed:@"cell_mail_unread"] resizableImageWithCapInsets:UIEdgeInsetsMake(22, 30, 22, 30)];
    UIImageView* inIV = [[UIImageView alloc] initWithImage:rBack];
    
    CGFloat height = (extended) ? 100 : 44;
    
    inIV.frame = CGRectMake(8 , 0 , WIDTH - 16, height);
    
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
    
    if (extended) {
        
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
        
        self.favori = nil;
    }
    else {
        
        UIImageView* fav = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"cell_favoris_off"] highlightedImage:[UIImage imageNamed:@"cell_favoris_on"]];
        CGRect f = fav.frame;
        f.origin.x = xPos;
        f.origin.y = 5.5;
        fav.frame = f;
        fav.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
        [inIV addSubview:fav];
        self.favori = fav;
        fav.highlighted = [mail isFav];
        
        xPos -= step;
    }
    self.posXtoUsers = xPos + 33.f;
    
    
    UIView* sep = [[UIView alloc] initWithFrame:CGRectMake(0, 44, inIV.bounds.size.width, 1)];
    sep.backgroundColor = [UIColor colorWithWhite:0.96 alpha:1.0];
    sep.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [inIV addSubview:sep];
    
    
    
    if (extended) {
        
        //UIFont* textFont = [UIFont systemFontOfSize:16];
        
        //CGSize size = [texte boundingRectWithSize:CGSizeMake(WIDTH - 30, 5000) options:NSStringDrawingUsesLineFragmentOrigin attributes:@{NSFontAttributeName:textFont} context:nil].size;
        CGSize size = CGSizeMake(WIDTH - 30,  ([UIScreen mainScreen].bounds.size.height / 2));

        size.width = ceilf(size.width);
        size.height = ceilf(size.height);
        //self.height = size.height;
        
        const CGFloat topBorder = 14.f;
        
        //TODO:For now they are all html
        /*if (![mail.email.body containsString:@"http"]) {
            UILabel* text = [[UILabel alloc] initWithFrame:CGRectMake(8, 48.f + topBorder, size.width, size.height)];
            text.text = texte;
            text.font = textFont;
            text.numberOfLines = 0;
            text.textAlignment = NSTextAlignmentJustified;
            [inIV addSubview:text];
        }
        else {*/
            if (!self.htmlView) {
                self.height = size.height = ([UIScreen mainScreen].bounds.size.height / 2);
                MCOMessageView* view = [[MCOMessageView alloc]initWithFrame:CGRectMake(8, 48.f + topBorder, size.width, size.height)];
                [view setHtml:mail.email.htmlBody];
                view.delegate = self;
                self.htmlView = view;
            }
            else {
                size.height = self.height;
                [self.htmlView setFrame:CGRectMake(8, 48.f + topBorder, size.width, size.height)];
            }

            [inIV addSubview:self.htmlView];
        //}

        
        CGRect f = inIV.frame;
        f.size.height = 90 + size.height + topBorder * 2.f;
        inIV.frame = f;
        
        height = f.size.height;
        
        n.text = person.name;

        f = n.frame;
        f.size.width = self.posXtoUsers - f.origin.x;
        n.frame = f;

        UIView* av = [self _createAttachments:mail.attachments];
        
        if (av != nil) {
            
            CGRect f = inIV.frame;
            f.size.height += av.frame.size.height + 30;
            inIV.frame = f;
            
            f = av.frame;
            f.origin.y = height - 45 + 15;
            av.frame = f;
            
            height = inIV.frame.size.height;
            [inIV addSubview:av];
        }
        
        
    }
    else {
        n.text = [texte stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    }
    
    inIV.userInteractionEnabled = YES;
    
    UITapGestureRecognizer* tgr = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_extend:)];
    [inIV addGestureRecognizer:tgr];
    
    inIV.clipsToBounds = YES;
    
    
    CGRect f = self.frame;
    f.size.height = height;
    self.frame = f;

    
    self.favoriBtn = nil;
    
    if (extended) {
        NSArray* btns = @[@"unread_o", @"forward_o", @"reply_o", @"replyall_o", @"cell_favoris_o"];
        
        
        CGRect baseFrame = CGRectMake(5.5f, height - 33.f - 5.5f, 33.f, 33.f);
        
        CGFloat stepX = ((inIV.frame.size.width - 33.f - 5.5f) - baseFrame.origin.x ) / 4.f;
        
        NSInteger idxTag = 1;
        
        for (NSString* name in btns) {
            
            UIButton* b = [[UIButton alloc] initWithFrame:baseFrame];
            UIImage* onImg = [UIImage imageNamed:[NSString stringWithFormat:@"%@n", name]];
            
            [b setImage:[UIImage imageNamed:[NSString stringWithFormat:@"%@ff", name]] forState:UIControlStateNormal];
            [b setImage:onImg forState:UIControlStateHighlighted];
            [b setImage:onImg forState:UIControlStateSelected];
            [b setImage:onImg forState:UIControlStateSelected | UIControlStateHighlighted];
            [inIV addSubview:b];
            
            baseFrame.origin.x = floorf(baseFrame.origin.x + stepX);
            
            
            if (name == [btns lastObject]) {
                [b addTarget:self action:@selector(_fav:) forControlEvents:UIControlEventTouchUpInside];
                b.selected = mail.isFav;
                self.favoriBtn = b;
            }
            else if (name == [btns firstObject]) {
                [b addTarget:self action:@selector(_masr:) forControlEvents:UIControlEventTouchUpInside];
                b.selected = mail.isRead;
            }
            else {
                b.tag = idxTag++;
                
                [b addTarget:self action:@selector(_openEdit:) forControlEvents:UIControlEventTouchUpInside];
            }
            
        }
    }
    
    [self addSubview:inIV];
}

-(void) updateFavUI:(BOOL)isFav
{
    self.favoriBtn.selected = isFav;
    self.favori.highlighted = isFav;
}

-(UIView*) _createAttachments:(NSArray*)attachs
{
    if (attachs.count == 0) {
        return nil;
    }
    
    CGFloat WIDTH = self.bounds.size.width;
    
    const CGFloat stepY = 73.f;
    
    UIView* v = [[UIView alloc] initWithFrame:CGRectMake(8, 0, WIDTH - 32, stepY * attachs.count)];
    v.backgroundColor = [UIColor whiteColor];
    CGFloat posY = 0.f;
    
    NSInteger idx = 0;
    
    for (Attachment* a in attachs) {
        
        AttachmentView* av = [[AttachmentView alloc] initWithWidth:WIDTH-32 leftMarg:0];
        av.delegate = self;
        CGRect f = av.frame;
        f.origin.y = posY;
        av.frame = f;
        
        [av fillWith:a];
        [v addSubview:av];
        
        UIView* line = [[UIView alloc] initWithFrame:CGRectMake(0, posY, WIDTH - 32, 0.5)];
        line.backgroundColor = [UIGlobal standardLightGrey];
        [v addSubview:line];
        
        idx++;
        posY += stepY;
    }
    
    UIView* line = [[UIView alloc] initWithFrame:CGRectMake(0, posY, WIDTH - 32, 0.5)];
    line.backgroundColor = [UIGlobal standardLightGrey];
    [v addSubview:line];
    
    return v;
}

-(void) _openEdit:(UIButton*)button
{
    Mail* m = [self.delegate mailDisplayed:self];
    
    Mail* repm = nil;
    
    if (button.tag==1) {
        repm = [m transfertMail];
    }
    else if (button.tag==2) {
        repm = [m replyMail:NO];
    }
    else {
        repm = [m replyMail:YES];
    }

    [[NSNotificationCenter defaultCenter] postNotificationName:kPRESENT_EDITMAIL_NOTIFICATION object:nil userInfo:@{kPRESENT_MAIL_KEY:repm}];
}

-(void) _masr:(UIButton*)button
{
    Mail* mail = [self.delegate mailDisplayed:self];
    [mail toggleRead];
    button.selected = mail.isRead;
}

-(void) _fav:(UIButton*)button
{
    Mail* mail = [self.delegate mailDisplayed:self];
    [mail toggleFav];
    [self.delegate makeConversationFav:!mail.isFav];
}

-(void) _extend:(UITapGestureRecognizer*)tgr
{
    
    if (tgr.enabled==false || tgr.state != UIGestureRecognizerStateEnded) {
        return;
    }
    
    UIView* mailView = tgr.view;
    
    CGPoint pos = [tgr locationInView:mailView];
    
    if (pos.y < 45) {
        
        
        if (pos.x < 45) {
            Mail* mail = [self.delegate mailDisplayed:self];
            Person* person = [[Persons sharedInstance] getPersonID:mail.fromPersonID];
            [[NSNotificationCenter defaultCenter] postNotificationName:kPRESENT_FOLDER_NOTIFICATION object:nil userInfo:@{kPRESENT_FOLDER_PERSON:person}];
            return;
        }
        
        if (pos.x > self.posXtoUsers) {
            
            if (self.bounds.size.height>50) {
                [[NSNotificationCenter defaultCenter] postNotificationName:kPRESENT_CONTACTS_NOTIFICATION object:nil userInfo:@{kPRESENT_MAIL_KEY:[self.delegate mailDisplayed:self]}];
            }
            else {
                Mail* mail = [self.delegate mailDisplayed:self];
                [self.delegate makeConversationFav:!mail.isFav];
            }
            return;
        }
        
        
        CGFloat nextHeight = 44.f;
        
        if (mailView.bounds.size.height>50) {
            [self setupWithText:self.textContent extended:NO];
            nextHeight = 44.f;
        }
        else {
            [self setupWithText:self.textContent extended:YES];
            nextHeight = self.bounds.size.height;
        }
        
        CGFloat diff = nextHeight - mailView.frame.size.height;
        
        CGRect f = mailView.frame;
        f.size.height = nextHeight;
        mailView.frame = f;
        
        
        [self.delegate mailView:self changeHeight:diff];
        
    }
    
}

-(void) webViewLoaded:(UIWebView*)webView
{
    self.height = webView.frame.size.height;
    
    CGFloat oldFrame = self.frame.size.height;

    CCMLog(@"Height:%f", self.height);
    
    [self setupWithText:self.textContent extended:YES];
    
    CGFloat nextHeight = self.bounds.size.height;
    
    CCMLog(@"BoundsHeight:%f", nextHeight);
    CCMLog(@"FrameHeight:%f", oldFrame);
    
    CGFloat diff = nextHeight - oldFrame;
    
    CCMLog(@"DiffHeight:%f", diff);

    
    CGRect f = self.frame;
    f.size.height = nextHeight;
    self.frame = f;
    
    [self.delegate mailView:self changeHeight:diff];
}

-(void) openURL:(NSURL*)url
{
    [self.delegate openURL:url];
}

-(void) shareAttachment:(Attachment*)att
{
    [self.delegate shareAttachment:att];
}

-(MCOAttachment*) partForUniqueID:(NSString*)partID
{
    for (Mail* mail in ((ConversationViewController*)self.delegate).conversation.mails) {
        for (Attachment* att in mail.attachments) {
        
            if (att.isInline && [att.contentID isEqualToString:partID]) {
            /*if(!att.data){
             
             MCOIMAPFetchContentOperation*  op = [[ImapSync sharedServices].imapSession fetchMessageAttachmentOperationWithFolder:[AppSettings folderName:[AppSettings activeFolder]]
             uid:[UidEntry getUidEntryWithFolder:[AppSettings activeFolder] msgId:att.msgId].uid
             partID:att.partID
             encoding:MCOEncodingBase64];
             op.progress = ^(unsigned int current, unsigned int maximum){
             CCMLog(@"%u, %u", current,maximum);
             };
             
             [op start:^(NSError*  error, NSData*  partData) {
             if(error){
             CCMLog(@"%@",error);
             return;
             }
             att.data = partData;
             [Attachment updateData:att];
             }];
             
             
             }*/
            
                MCOAttachment* attM = [[MCOAttachment alloc]init];
                attM.data = att.data;
                
                return attM;
            }
        }
    }
    
    return nil;
}

@end

