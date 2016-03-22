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
#import "ARSafariActivity.h"
#import "FindQuote.h"
#import "Flurry.h"
#import "ViewController.h"
#import "UserSettings.h"
#import "Draft.h"

@import SafariServices;

@class SingleMailView;

@protocol SingleMailViewDelegate <NSObject>

-(Mail*) mailDisplayed:(SingleMailView*)mailView;
-(void) mailView:(SingleMailView*)mailView changeHeight:(CGFloat)deltaHeight;
-(void) openURL:(NSURL*)url;
-(void) openWebURL:(NSURL*)url;
-(void) openLongURL:(NSURL*)url;
-(void) openContentID:(NSString*)cid;
-(void) openLongContentID:(NSString*)cid;
-(void) shareAttachment:(Attachment*)att;
-(void) scrollTo:(CGPoint)offset;
-(BOOL) isConversation;

@end


@interface ConversationViewController () <UIScrollViewDelegate, SingleMailViewDelegate, UserFolderViewControllerDelegate, QLPreviewControllerDataSource, QLPreviewControllerDelegate, UIDocumentInteractionControllerDelegate, SFSafariViewControllerDelegate> {
    NSArray* _activityItems;
}

@property (nonatomic, weak) UIView* contentView;
@property (nonatomic, weak) UIScrollView* scrollView;

@property (nonatomic, strong) NSMutableArray* allMailViews;

@property (nonatomic) CCMFolderType folder;
@property (nonatomic) CGPoint contentOffset;

@property (nonatomic, strong) UserFolderViewController* chooseUserFolder;

@end


@interface SingleMailView : UIView <MCOMessageViewDelegate, CCMAttachmentViewDelegate>

-(void) setupWithText:(Mail*)texte extended:(BOOL)extended;

@property (nonatomic, strong) UIView* htmlView;
@property (nonatomic, weak) id<SingleMailViewDelegate> delegate;

@property (nonatomic) CGFloat posXtoUsers;
@property (nonatomic, weak) UIImageView* favori;
@property (nonatomic, weak) UIImageView* markAsRead;

@property (nonatomic) NSInteger idxInConversation;
@property (nonatomic) CGFloat height;

@property (nonatomic, weak) UIButton* favoriBtn;
@property (nonatomic, strong) UIView* attchView;

-(void) updateFavUI:(BOOL)isFav;
-(void) refreshAtts;

@end

@implementation ConversationViewController

-(void) viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    self.contentOffset = CGPointMake(0,0);
    
    Persons* p = [Persons sharedInstance];
    
    if (p.idxMorePerson == 0) {
        Person* more = [Person createWithName:nil email:nil icon:[UIImage imageNamed:@"recipients_off"] codeName:nil];
        p.idxMorePerson = [p addPerson:more];
    }
    // TODO put it elsewhere
    
    self.folder = [[AppSettings userWithIndex:kActiveFolderIndex] typeOfFolder:[Accounts sharedInstance].currentAccount.currentFolderIdx];

    self.view.backgroundColor = [UIGlobal standardLightGrey];
    
    Mail* mail = [self.conversation firstMail];
    
    UINavigationItem* item = [[UINavigationItem alloc] initWithTitle:@""];
    
    item.leftBarButtonItem = [self backButtonInNavBar];

    if ([self.conversation hasAttachments]) {
        UIButton* attach = [WhiteBlurNavBar navBarButtonWithImage:@"attachment_off" andHighlighted:@"attachment_on"];
        [attach addTarget:self action:@selector(_attach) forControlEvents:UIControlEventTouchUpInside];
        item.rightBarButtonItem = [[UIBarButtonItem alloc] initWithCustomView:attach];
    }
    
    item.titleView = [WhiteBlurNavBar titleViewForItemTitle:mail.subject];
    
    [self _setup];
    
    //self.scrollView.panGestureRecognizer.delegate = self;
    
    [self.scrollView.panGestureRecognizer requireGestureRecognizerToFail:[ViewController mainVC].customPGR];

    [self setupNavBarWith:item overMainScrollView:self.scrollView];
}

- (void)viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    self.contentOffset = CGPointMake(0,0);

    [self refreshAttachments];
    //TODO:TODO? :)
    //[[CocoaButton sharedButton] enterLevel:2];
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
    if ([self.conversation hasAttachments]) {
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
    lbl.text = [self.conversation firstMail].subject;
    lbl.numberOfLines = 0;
    lbl.textColor = [UIColor whiteColor];
    lbl.lineBreakMode = NSLineBreakByWordWrapping;
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
        
        NSInteger i = [Mail isTodayOrYesterday:day];
        
        if (i == 0) {
            day = NSLocalizedString(@"mail-list-view.date-header.today", @"Today");
        }
        else if (i == -1) {
            day = NSLocalizedString(@"mail-list-view.date-header.yesterday", @"Yesterday");
        }
        
        NSString* hour = m.hour;
        //NSString* mail = m.content;
        
        if ((idx ==0) && !m.isRead) {
            [m toggleRead];
        }

        posY = [self _addHeaderDay:day hour:hour atYPos:posY inView:contentView];
        posY = [self _addMail:m withIndex:idx extended:(idx==0) atYPos:posY inView:contentView];
        
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

-(void) refreshAttachments
{
    for (UIView* m in self.contentView.subviews) {
        if ([m isKindOfClass:[SingleMailView class]]) {
            [(SingleMailView*)m refreshAtts];
        }
    }
}

-(Mail*) mailDisplayed:(SingleMailView*)mailView;
{
    return self.conversation.mails[mailView.idxInConversation];
}

- (BOOL)isConversation
{
    return self.conversation.mails.count > 1;
}

/*-(void) makeConversationFav:(BOOL)isFav
{
    //Account* ac = [[Accounts sharedInstance] currentAccount];
    //[ac manage:self.conversation isFav:isFav];
    
    //for (SingleMailView* smv in self.allMailViews) {
        [smv updateFavUI:isFav];
    //}
}*/

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
    
    [self.scrollView setContentOffset:self.contentOffset];
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

-(void) openWebURL:(NSURL*)url
{
    if ([self isEmailRegExp:url.absoluteString]) {
        NSString* email = [url.absoluteString stringByReplacingOccurrencesOfString:@"mailto:" withString:@""];
        
        Draft* draft = [Draft newDraftFormCurrentAccount];
        
        [[Persons sharedInstance] addPerson:[Person createWithName:nil email:email icon:nil codeName:nil]];
        
        draft.toPersons = [NSMutableArray arrayWithArray:@[email]];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:kPRESENT_EDITMAIL_NOTIFICATION object:nil userInfo:@{kPRESENT_MAIL_KEY:draft}];
        
        return;
    }
    
    SFSafariViewController* sv = [[SFSafariViewController alloc] initWithURL:url];
    sv.delegate = self;
    [self.view.window.rootViewController presentViewController:sv animated:YES completion:nil];
}

-(void) openLongURL:(NSURL*)url
{
    ARSafariActivity *safariActivity = [[ARSafariActivity alloc] init];
    UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:@[url] applicationActivities:@[safariActivity]];
    [self.view.window.rootViewController presentViewController:activityViewController
                                                      animated:YES
                                                    completion:nil];
}

-(void) openContentID:(NSString*)cid
{
    for (Mail* mail in self.conversation.mails) {
        for (Attachment* att in mail.attachments) {
            if (att.isInline && [att.contentID isEqualToString:cid]) {
                NSString* filePath = [StringUtil filePathInDocumentsDirectoryForAttachmentFileName:att.fileName];
                [att.data writeToFile:filePath atomically:YES];
                NSURL* URL = [NSURL fileURLWithPath:filePath];
                [self openURL:URL];
            }
        }
    }
}

-(void) openLongContentID:(NSString*)cid
{
    for (Mail* mail in self.conversation.mails) {
        for (Attachment* att in mail.attachments) {
            if (att.isInline && [att.contentID isEqualToString:cid]) {
                UIActivityViewController *activityViewController = [[UIActivityViewController alloc] initWithActivityItems:@[[UIImage imageWithData:att.data]] applicationActivities:nil];
                [self.view.window.rootViewController presentViewController:activityViewController
                                                                  animated:YES
                                                                completion:nil];
            }
        }
    }
}

- (void)safariViewControllerDidFinish:(SFSafariViewController *)controller
{
    [controller dismissViewControllerAnimated:YES completion:nil];
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

-(void) scrollTo:(CGPoint)offset
{
    self.contentOffset = offset;
    [self.scrollView setContentOffset:offset];
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    self.contentOffset = scrollView.contentOffset;
}

- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView
{
    [[ViewController mainVC] closeCocoaButtonIfNeeded];
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

-(CGFloat) _addMail:(Mail*)mail withIndex:(NSInteger)idx extended:(BOOL)extended atYPos:(CGFloat)posY inView:(UIView*)v
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
    
    if (self.folder.type==FolderTypeDeleted) {
        [b4 setImage:[UIImage imageNamed:@"button_folder_off"] forState:UIControlStateNormal];
        [b4 setImage:[UIImage imageNamed:@"button_folder_on"] forState:UIControlStateHighlighted];
    }
    else if (self.folder.type==FolderTypeAll) {
        [b2 setImage:[UIImage imageNamed:@"button_inbox_off"] forState:UIControlStateNormal];
        [b2 setImage:[UIImage imageNamed:@"button_inbox_on"] forState:UIControlStateHighlighted];
    }
    
    return @[b1, b2, b3, b4];
}

-(void) _editMail
{
    [[NSNotificationCenter defaultCenter] postNotificationName:kPRESENT_EDITMAIL_NOTIFICATION object:nil];
}

-(void) _executeMoveOnSelectedCellsTo:(CCMFolderType)toFolder
{
    
    NSString* fromFolderString;
    NSString* toFolderString;
    
    if (self.folder.type == FolderTypeUser) {
        fromFolderString = @"UserFolder";
    }
    else {
        fromFolderString = [self.conversation.user.linkedAccount systemFolderNames][self.folder.idx];
    }
    
    if (toFolder.type == FolderTypeUser) {
        toFolderString = @"UserFolder";
    }
    else {
        toFolderString = [self.conversation.user.linkedAccount systemFolderNames][toFolder.idx];
    }
    
    NSDictionary *articleParams = [NSDictionary dictionaryWithObjectsAndKeys:
                                   fromFolderString , @"from_Folder",
                                   toFolderString, @"to_Folder",
                                   @"conversation", @"action_Location"
                                   ,nil];
    
    [Flurry logEvent:@"Conversation Moved" withParameters:articleParams];
    
    [self.conversation.user.linkedAccount moveConversation:self.conversation from:self.folder to:toFolder updateUI:YES];
    
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
            toFolder.type = (self.folder.type == FolderTypeDeleted) ? FolderTypeInbox : FolderTypeDeleted;
            break;
        case 1:
            toFolder.type = (self.folder.type == FolderTypeAll) ? FolderTypeInbox : FolderTypeAll;
            break;
        case 2:
        {
            doNothing = YES;//Not right away at least! (Chris don't delete this...) :P
            
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
    return YES;
}

@end

@implementation SingleMailView

-(void) setupWithText:(Mail*)pMail extended:(BOOL)extended;
{
    [self.subviews.firstObject removeFromSuperview];
    
    Mail* mail = [self.delegate mailDisplayed:self];
    Person* person = [[Persons sharedInstance] getPersonWithID:mail.fromPersonID];
    
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
        
        NSArray* subarray = mail.toPersonIDs;
        
        if (mail.toPersonIDs.count>3) {
            NSRange r;
            r.length = 2;
            r.location = mail.toPersonIDs.count - 2;
            
            NSMutableArray* tmp = [[mail.toPersonIDs subarrayWithRange:r] mutableCopy];
            
            [tmp insertObject:@([Persons sharedInstance].idxMorePerson) atIndex:0];
            subarray = tmp;
        }
        
        for (NSNumber* userID in subarray) {
            
            Person* p = [[Persons sharedInstance] getPersonWithID:[userID integerValue]];
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

        CGSize size = CGSizeMake(WIDTH - 30,  ([UIScreen mainScreen].bounds.size.height / 2));

        size.width = ceilf(size.width);
        size.height = ceilf(size.height);
        
        const CGFloat topBorder = 14.f;

            if (!self.htmlView) {
                self.height = size.height;// = 100;
                MCOMessageView* view = [[MCOMessageView alloc]initWithFrame:CGRectMake(0/*8*/, 48.f + topBorder, size.width, size.height)];
                view.isConversation = [self.delegate isConversation];
                [view setMail:mail];
                view.delegate = self;
                self.htmlView = view;
            }
            else {
                size.height = self.height;
                [self.htmlView setFrame:CGRectMake(8, 48.f + topBorder, size.width, size.height)];
            }

            [inIV addSubview:self.htmlView];
        
        CGRect f = inIV.frame;
        f.size.height = 90 + size.height + topBorder * 2.f;
        inIV.frame = f;
        
        height = f.size.height;
        
        if (person.isGeneric) {
            n.text = mail.sender.displayName;;
        }
        else {
            n.text = person.name;
        }

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
            self.attchView = av;
        }
    }
    else {
        n.text = [pMail.body stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
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
        NSArray* xFix = @[@(0),@(1),@(2),@(2),@(5)];
        
        CGRect baseFrame = CGRectMake(5.5f, height - 33.f - 5.5f, 33.f, 33.f);
        
        CGFloat stepX = ((inIV.frame.size.width - 33.f - 5.5f) - baseFrame.origin.x ) / 4.f;
        
        NSInteger idxTag = 1;
        
        NSInteger idxFix = 0;
        
        for (NSString* name in btns) {
            
            UIButton* b = [[UIButton alloc] initWithFrame:baseFrame];
            UIImage* onImg = [UIImage imageNamed:[NSString stringWithFormat:@"%@n", name]];
            
            [b setImage:[UIImage imageNamed:[NSString stringWithFormat:@"%@ff", name]] forState:UIControlStateNormal];
            [b setImage:onImg forState:UIControlStateHighlighted];
            [b setImage:onImg forState:UIControlStateSelected];
            [b setImage:onImg forState:UIControlStateSelected | UIControlStateHighlighted];
            [inIV addSubview:b];
            
            baseFrame.origin.x = floorf(baseFrame.origin.x + stepX) + [xFix[idxFix] integerValue];
            
            idxFix++;
            
            //NSLog(@"Origin.x:%f", baseFrame.origin.x);
            
            if (name == [btns lastObject]) {
                [b addTarget:self action:@selector(_fav:) forControlEvents:UIControlEventTouchUpInside];
                if (mail.isFav) {
                    b.selected = YES;
                }
                self.favoriBtn = b;
            }
            else if (name == [btns firstObject]) {
                [b addTarget:self action:@selector(_masr:) forControlEvents:UIControlEventTouchUpInside];
                if (mail.isRead) {
                    b.selected = YES;
                }
                
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

-(void) refreshAtts
{
    Mail* mail = [self.delegate mailDisplayed:self];
    self.attchView = [self _createAttachments:mail.attachments];
}

-(UIView*) _createAttachments:(NSArray*)attachs
{
    NSInteger normalAttsCount = 0;

    for (Attachment* a in attachs) {
        if (!a.isInline) {
            normalAttsCount++;
        }
    }
    
    if (attachs.count == 0 || normalAttsCount == 0) {
        return nil;
    }
    
    CGFloat WIDTH = self.bounds.size.width;
    
    const CGFloat stepY = 73.f;
    
    UIView* v = [[UIView alloc] initWithFrame:CGRectMake(8, 0, WIDTH - 32, stepY * normalAttsCount)];
    v.backgroundColor = [UIColor whiteColor];
    CGFloat posY = 0.f;
    
    NSInteger idx = 0;
    
    for (Attachment* a in attachs) {
        
        if (a.isInline) {
            continue;
        }
        
        AttachmentView* av = [[AttachmentView alloc] initWithWidth:WIDTH-32 leftMarg:0];
        av.delegate = self;
        CGRect f = av.frame;
        f.origin.y = posY;
        av.frame = f;
        
        a.image = nil;
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

-(void) openURL:(NSURL*)url
{
    [self.delegate openURL:url];
}

-(void) _openEdit:(UIButton*)button
{
    Mail* m = [self.delegate mailDisplayed:self];
    
    Draft* repm = nil;
    
    if (button.tag==1) {
        repm = [m transfertDraft];
    }
    else if (button.tag==2) {
        repm = [m replyDraft:NO];
    }
    else {
        repm = [m replyDraft:YES];
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
    //[self updateFavUI:mail.isFav];
    [self setupWithText:mail extended:YES];

    //[self.delegate makeConversationFav:mail.isFav];
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
            Person* person = [[Persons sharedInstance] getPersonWithID:mail.fromPersonID];
            [[NSNotificationCenter defaultCenter] postNotificationName:kPRESENT_FOLDER_NOTIFICATION object:nil userInfo:@{kPRESENT_FOLDER_PERSON:person}];
            return;
        }
        
        if (pos.x > self.posXtoUsers) {
            
            if (self.bounds.size.height>50) {
                [[NSNotificationCenter defaultCenter] postNotificationName:kPRESENT_CONTACTS_NOTIFICATION object:nil userInfo:@{kPRESENT_MAIL_KEY:[self.delegate mailDisplayed:self]}];
            }
            else {
                Mail* mail = [self.delegate mailDisplayed:self];
                [mail toggleFav];
                [self setupWithText:mail extended:NO];
                //[self.delegate makeConversationFav:!mail.isFav];
            }
            return;
        }
        
        
        CGFloat nextHeight = 44.f;
        
        Mail* mail = [self.delegate mailDisplayed:self];

        if (mailView.bounds.size.height>50) {
            [self setupWithText:mail extended:NO];
            nextHeight = 44.f;
        }
        else {
            [self setupWithText:mail extended:YES];
            nextHeight = self.bounds.size.height;
        }
        
        CGFloat diff = nextHeight - mailView.frame.size.height;
        
        CGRect f = mailView.frame;
        f.size.height = nextHeight;
        mailView.frame = f;
        
        
        [self.delegate mailView:self changeHeight:diff];
        
    }
    
}

-(void) openWebURL:(NSURL*)url
{
    [self.delegate openWebURL:url];
}

-(void) openLongURL:(NSURL*)url
{
    [self.delegate openLongURL:url];
}

-(void) openContentID:(NSString*)cid
{
    [self.delegate openContentID:cid];
}

-(void) openLongContentID:(NSString*)cid
{
    [self.delegate openLongContentID:cid];
}

-(void) scrollTo:(CGPoint)offset
{
    [self.delegate scrollTo:offset];
}

-(void) webViewLoaded:(UIWebView*)webView
{
    self.height = webView.frame.size.height;
    
    CGFloat oldFrame = self.frame.size.height;
    
    [self setupWithText:[self.delegate mailDisplayed:self] extended:YES];
    
    CGFloat nextHeight = self.bounds.size.height;
    CGFloat diff = nextHeight - oldFrame;
    
    CGRect f = self.frame;
    f.size.height = nextHeight;
    self.frame = f;
    
    [self.delegate mailView:self changeHeight:diff];
}

-(void) shareAttachment:(Attachment*)att
{
    [self.delegate shareAttachment:att];
}

-(void) downloaded:(Attachment*)att
{
    [self refreshAtts];
    
    NSString* filePath = [StringUtil filePathInDocumentsDirectoryForAttachmentFileName:att.fileName];
    [att.data writeToFile:filePath atomically:YES];
    NSURL* URL = [NSURL fileURLWithPath:filePath];
    [self openURL:URL];
}

-(void) partForUniqueID:(NSString*)partID completed:(void (^)(NSData * data))completedBlock
{
    BOOL found = NO;
    
    Conversation* conv = ((ConversationViewController*)self.delegate).conversation;
    for (Mail* mail in conv.mails) {
        for (Attachment* att in mail.attachments) {

            if (att.isInline && [att.contentID isEqualToString:partID]) {
                found = YES;
                if(!att.data){
                    UidEntry* uidE = [mail.uids firstObject];
                    MCOIMAPFetchContentOperation*  op =
                    [[ImapSync sharedServices:conv.user].imapSession
                     fetchMessageAttachmentOperationWithFolder:[[conv user] folderServerName:uidE.folder]
                     uid:uidE.uid
                     partID:att.partID
                     encoding:MCOEncodingBase64];
                
                    op.progress = ^(unsigned int current, unsigned int maximum){
                        CCMLog(@"%u, %u", current,maximum);
                    };
                    dispatch_async([ImapSync sharedServices:conv.user].s_queue, ^{
                    [op start:^(NSError*  error, NSData*  partData) {
                        if(error){
                            CCMLog(@"%@",error);
                            return;
                        }
                        att.data = partData;
                        [Attachment updateData:att];

                        completedBlock(att.data);
                    }];
                        
                    });
                    
                    break;
                }
                else {

                    completedBlock(att.data);
                    
                    break;
                }
            }
        }
    }
    
    if (!found) {
        completedBlock(nil);
    }
}

@end

