//
//  AttachmentsViewController.m
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 17/08/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "AttachmentsViewController.h"

#import "Persons.h"
#import "Reachability.h"
#import "Accounts.h"
#import "AppSettings.h"
#import "ImapSync.h"
#import "StringUtil.h"
#import <QuickLook/QuickLook.h>

@interface AttachmentsViewController () <UITableViewDataSource, UITableViewDelegate, QLPreviewControllerDataSource, QLPreviewControllerDelegate, CCMAttachmentViewDelegate, UIDocumentInteractionControllerDelegate>{
    NSArray *_activityItems;
}

@property (nonatomic, weak) UITableView* table;
@property (nonatomic, strong) NSArray* mailsWithAttachment;

@end



@interface AttachmentsCell : UITableViewCell

@property (nonatomic, weak) AttachmentView* attachView;

@end



@implementation AttachmentsViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    
    UINavigationItem* item = [[UINavigationItem alloc] initWithTitle:@""];
    
    item.leftBarButtonItem = [self backButtonInNavBar];
    
    UILabel* l = [WhiteBlurNavBar titleViewForItemTitle:[self.conversation firstMail].title];
    item.titleView = l;
    /*
    UIImageView* iv = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"attachment_off"]];
    
    UIView* support = [[UIView alloc] initWithFrame:CGRectMake(0, 0, l.frame.size.width + iv.frame.size.width + 2.f, 33.f)];
    support.backgroundColor = [UIColor clearColor];
    [support addSubview:iv];
    iv.autoresizingMask = UIViewAutoresizingFlexibleRightMargin;
    
    CGRect r = l.frame;
    r.origin.x = iv.frame.size.width + 2.f;
    r.origin.y = floorf((33.f - r.size.height) / 2.f);
    l.frame = r;
    [support addSubview:l];
    l.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    
    if (support.frame.size.width > screenBounds.size.width - 55.f) {
        r = support.frame;
        r.size.width = screenBounds.size.width - 55.f;
        support.frame = r;
    }
    
    item.titleView = support;
    */
    
    
    UITableView* table = [[UITableView alloc] initWithFrame:CGRectMake(0,
                                                                       0,
                                                                       screenBounds.size.width,
                                                                       screenBounds.size.height-20)
                                                      style:UITableViewStyleGrouped];
    table.contentInset = UIEdgeInsetsMake(44, 0, 60, 0);
    table.scrollIndicatorInsets = UIEdgeInsetsMake(44, 0, 0, 0);
    
    table.backgroundColor = [UIColor whiteColor];
    
    [self.view addSubview:table];
    
    [self setupNavBarWith:item overMainScrollView:table];
    
    [self _setupData];
    
    table.dataSource = self;
    table.delegate = self;    
    self.table = table;    
}


-(void) _setupData
{
    NSMutableArray* res = [NSMutableArray arrayWithCapacity:self.conversation.mails.count];
    
    for (Mail* m in self.conversation.mails) {
        if ([m haveAttachment]) {
            [m.email fetchAllAttachments];
            [res addObject:m];
        }
    }
    
    self.mailsWithAttachment = res;
    
}


-(void) cleanBeforeGoingBack
{
    self.table.delegate = nil;
    self.table.dataSource = nil;    
}


#pragma mark - Table Datasource


-(NSInteger) numberOfSectionsInTableView:(UITableView *)tableView
{
    return self.mailsWithAttachment.count;
}

-(NSInteger) tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    
    Mail* m = self.mailsWithAttachment[section];
    return m.attachments.count;
}


-(UITableViewCell*) tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    
    Mail* m = self.mailsWithAttachment[indexPath.section];
    Attachment* at = m.attachments[indexPath.row];
    
    
    NSString* reuseID = @"kAttchCellID";
    
    AttachmentsCell* cell = [tableView dequeueReusableCellWithIdentifier:reuseID];
    
    if (cell == nil) {
        cell = [[AttachmentsCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseID];
    }
    
    [cell.attachView fillWith:at];
    cell.attachView.delegate = self;
    
    return cell;
}

-(CGFloat) tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return (indexPath.row==0) ? 73.f : 72.5f;
}


#pragma mark Table Delegate


-(CGFloat) tableView:(UITableView *)tableView heightForFooterInSection:(NSInteger)section
{
    return CGFLOAT_MIN;
}

-(CGFloat) tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section
{
    return 44.f;
}

-(UIView*) tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section
{
    
    UIView* support = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, 44)];
    support.backgroundColor = tableView.backgroundColor;
    
    support.clipsToBounds = NO;
    
    UIView* lineT = [[UIView alloc] initWithFrame:CGRectMake(0, -0.5, support.frame.size.width, 0.5)];
    lineT.backgroundColor = [UIColor colorWithWhite:0.69 alpha:1.0];
    [support addSubview:lineT];
    
    UIView* lineB = [[UIView alloc] initWithFrame:CGRectMake(0, 44, support.frame.size.width, 0.5)];
    lineB.backgroundColor = lineT.backgroundColor;
    [support addSubview:lineB];
    
    
    Mail* m = self.mailsWithAttachment[section];
    
    Person* p = [[Persons sharedInstance] getPersonID:m.fromPersonID];

    UIView* badge = [p badgeView];
    
    CGRect f = badge.frame;
    f.origin.x = 5.5;
    f.origin.y = 5.5;
    badge.frame = f;
    [support addSubview:badge];
    badge.autoresizingMask = UIViewAutoresizingFlexibleRightMargin;
    
    UILabel* t = [[UILabel alloc] initWithFrame:CGRectMake(44, 0, 300, 44)];
    t.backgroundColor = support.backgroundColor;
    t.textColor = [UIColor colorWithWhite:0.47 alpha:1.0];
    t.font = [UIFont systemFontOfSize:12];
    t.text = m.day;
    [t sizeToFit];
    
    f = t.frame;
    f.origin.x = support.frame.size.width - f.size.width - 10.f;
    f.size.height = 44.f;
    t.frame = f;
    
    [support addSubview:t];
    t.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    
    
    UILabel* h = [[UILabel alloc] initWithFrame:CGRectMake(44, 0, t.frame.origin.x - 44, 44)];
    h.backgroundColor = support.backgroundColor;
    h.textColor = [UIColor colorWithWhite:0.47 alpha:1.0];
    h.font = [UIFont systemFontOfSize:16];
    h.text = p.name;
    [support addSubview:h];
    h.autoresizingMask = UIViewAutoresizingFlexibleWidth;

    
    return support;
}



-(NSIndexPath*) tableView:(UITableView *)tableView willSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    AttachmentsCell * cell = (AttachmentsCell*)[tableView cellForRowAtIndexPath:indexPath];
    
    Mail* m = self.mailsWithAttachment[indexPath.section];
    Attachment* att = m.attachments[indexPath.row];
    
    if(!att.data) {
        [cell.attachView beginActionDownload:att];
    }
    else {
        NSString *filePath = [StringUtil filePathInDocumentsDirectoryForAttachmentFileName:att.fileName];
        [att.data writeToFile:filePath atomically:YES];
        NSURL *URL = [NSURL fileURLWithPath:filePath];
        [self openURL:URL];
    }
    
    return nil;
}

- (void)openURL:(NSURL *)url
{
    QLPreviewController *previewController = [[QLPreviewController alloc]init];
    previewController.delegate = self;
    previewController.dataSource = self;
    previewController.currentPreviewItemIndex = 0;
    
    _activityItems = @[url];
    
    [self.view.window.rootViewController presentViewController:previewController animated:YES completion:nil];
}

#pragma mark - QLPreviewControllerDataSource
- (NSInteger)numberOfPreviewItemsInPreviewController:(QLPreviewController *)previewController
{
    return _activityItems.count;
}

- (id)previewController:(QLPreviewController *)previewController previewItemAtIndex:(NSInteger)index
{
    return _activityItems[index];
}

- (void)previewControllerWillDismiss:(QLPreviewController *)controller
{
    //    [[UIApplication sharedApplication] setStatusBarHidden:YES];
    //    [self setNeedsStatusBarAppearanceUpdate];
}

- (void)shareAttachment:(Attachment*)att
{
    NSString *filePath = [StringUtil filePathInDocumentsDirectoryForAttachmentFileName:att.fileName];
    [att.data writeToFile:filePath atomically:YES];
    NSURL *URL = [NSURL fileURLWithPath:filePath];
    
    UIDocumentInteractionController *documentInteractionController = [UIDocumentInteractionController interactionControllerWithURL:URL];
    documentInteractionController.delegate = self;
    [documentInteractionController presentOpenInMenuFromRect:CGRectMake(0 ,0 , 0, 0) inView:self.view animated:YES];
}

@end




@implementation AttachmentsCell

-(instancetype) initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    
    self.contentView.backgroundColor = [UIColor whiteColor];
    
    AttachmentView* av = [[AttachmentView alloc] initWithWidth:self.contentView.frame.size.width leftMarg:25];
    [self.contentView addSubview:av];
    av.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [av buttonActionType:AttachmentViewActionDonwload];
    self.attachView = av;
    
    self.separatorInset = UIEdgeInsetsMake(0, 91, 0, 0);
    
    return self;
}


@end

