//
//  CreditViewController.m
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 06/09/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "CreditViewController.h"

#import "CocoaButton.h"
#import "Mail.h"
#import "Persons.h"


@interface CreditViewController () <UITableViewDataSource, UITableViewDelegate, CocoaButtonDatasource>

@property (nonatomic, weak) UITableView* table;
@property (nonatomic, strong) NSArray* tableContent;
@property (nonatomic, weak) CocoaButton* cocoaButton;

@end

@implementation CreditViewController

-(void) viewDidLoad
{
    [super viewDidLoad];
    
    
    self.view.backgroundColor = [UIGlobal standardLightGrey];
    
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    
    UINavigationItem* item = [[UINavigationItem alloc] initWithTitle:@""];
    item.leftBarButtonItem = [self backButtonInNavBar];
    item.titleView = [WhiteBlurNavBar titleViewForItemTitle: NSLocalizedString(@"credits-view.title", @"CocoaMail 1.0")];
    
    [self setupSimpleNavBarWith:item andWidth:screenBounds.size.width];
    
    UITableView* table = [[UITableView alloc] initWithFrame:CGRectMake(0,
                                                                       0,
                                                                       screenBounds.size.width,
                                                                       screenBounds.size.height - 20)
                                                      style:UITableViewStyleGrouped];
    table.contentInset = UIEdgeInsetsMake(44, 0, 60, 0);
    table.scrollIndicatorInsets = UIEdgeInsetsMake(44, 0, 0, 0);
    
    table.backgroundColor = [UIGlobal standardLightGrey];
    
    [self.view addSubview:table];
    self.view.backgroundColor = table.backgroundColor;
    
    [self setupNavBarWith:item overMainScrollView:table];
 
    [self _prepareTable];
    
    table.dataSource = self;
    table.delegate = self;
    self.table = table;
    
    CocoaButton* cb = [CocoaButton fakeCocoaButtonForCredits];
    cb.center = CGPointMake(self.view.frame.size.width - 30, self.view.frame.size.height - 30 - 20);
    [self.view addSubview:cb];
    cb.datasource = self;
    self.cocoaButton = cb;
}

-(BOOL) haveCocoaButton
{
    return NO;
}

-(void) cleanBeforeGoingBack
{
    self.table.delegate = nil;
    self.table.dataSource = nil;
}

#define kTITLE @"t"
#define kACTION @"a"
#define kSUB @"s"

-(void) viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.cocoaButton openWide];
    });
}

-(void) _prepareTable
{
    self.tableContent = @[
                          @[@{kTITLE : @"Reinald Freling", kSUB : @"Product Design", kACTION : @"open RF"},
                            @{kTITLE : @"Christopher Hockley", kSUB : @"Development", kACTION : @"open CH"},
                            @{kTITLE : @"Christophe Branche", kSUB : @"UI/UX Design", kACTION : @"open CB"},
                            @{kTITLE : @"Pascal Costa-Cunha", kSUB : @"Helping hand", kACTION : @"open PCC"}
                            ],
                          @[@{kTITLE : NSLocalizedString(@"credits-view.section.thanks", @"Thanks"), kACTION : @"open T"}],
                          @[@{kTITLE : NSLocalizedString(@"credits-view.section.review", @"Write a review in the iTunes Store"), kACTION : @"itunes"}]
                          ];
}

#pragma mark - Table Datasource

-(NSInteger) numberOfSectionsInTableView:(UITableView*)tableView
{
    return self.tableContent.count;
}

-(NSInteger) tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section
{
    return [((NSDictionary*)self.tableContent[section]) count];
}

-(UITableViewCell*) tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath
{
    
    NSDictionary* infos = self.tableContent[indexPath.section][indexPath.row];
    
    UITableViewCell* cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"noID"];
    
    cell.textLabel.text = infos[kTITLE];
    
    cell.textLabel.textAlignment = NSTextAlignmentNatural;
    cell.textLabel.textColor = [UIColor blackColor];
    
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    
    if (indexPath.row == [((NSDictionary*)self.tableContent[indexPath.section]) count]-1) {
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    
    NSString* sub = infos[kSUB];
    
    if (sub.length>0) {

        UILabel* lbl = [[UILabel alloc] initWithFrame:CGRectMake(150 , 0.5, tableView.frame.size.width - 150 - 30, 50)];
        lbl.text = sub;
        lbl.textColor = [UIColor lightGrayColor];
        lbl.textAlignment = NSTextAlignmentRight;
        [cell.contentView addSubview:lbl];
    }
    
    cell.selectionStyle = UITableViewCellSelectionStyleGray;
    
    return cell;
}

-(CGFloat) tableView:(UITableView*)tableView heightForRowAtIndexPath:(NSIndexPath*)indexPath
{
    return (indexPath.row==0) ? 52.5f : 52.0f;
}

#pragma mark - Table Delegate

-(CGFloat) tableView:(UITableView*)tableView heightForFooterInSection:(NSInteger)section
{
    return CGFLOAT_MIN;
}

-(CGFloat) tableView:(UITableView*)tableView heightForHeaderInSection:(NSInteger)section
{
    return (section==0) ? 160 : 10;
}

-(UIView*) tableView:(UITableView*)tableView viewForHeaderInSection:(NSInteger)section
{
    if (section==0) {
        
        CGFloat WIDTH = tableView.frame.size.width;
        
        UIView* bigOne = [[UIView alloc] initWithFrame:CGRectMake(0, 0, WIDTH, 160)];
        
        bigOne.backgroundColor = [UIColor clearColor];
        
        UIImageView* iv = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"cocoamail"]];
        
        CGPoint c = bigOne.center;
        c.y -= 20;
        iv.center = c;
        [bigOne addSubview:iv];
        
        CGFloat WIDTH_LBL = 240;
        
        UILabel* lbl = [[UILabel alloc] initWithFrame:CGRectMake((WIDTH - WIDTH_LBL) / 2. , 105, WIDTH_LBL, 50)];
        lbl.backgroundColor = bigOne.backgroundColor;
        lbl.text = @"CocoaMail was made with love sitting at a french café.";
        lbl.numberOfLines = 0;
        [bigOne addSubview:lbl];
        lbl.textAlignment = NSTextAlignmentCenter;
        
        return bigOne;
    }
    
    return nil;
}

-(NSIndexPath*) tableView:(UITableView*)tableView willSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
    NSDictionary* infos = self.tableContent[indexPath.section][indexPath.row];

    NSString* action = infos[kACTION];
    
    if ([action isEqualToString:@"itunes"]) {
        [ViewController presentAlertWIP:@"itunes review…"];
    }
    else {
        NSArray* ele = [action componentsSeparatedByString:@" "];
        
        [self.cocoaButton forceCloseButton];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:kSETTINGS_CREDIT2_NOTIFICATION object:nil
                                                          userInfo:@{kSETTINGS_KEY:ele[1]}];
    }
    
    
    return nil;
}

-(void) tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

#pragma mark - CocoaButton

-(void) scrollViewDidScroll:(UIScrollView*)scrollView
{
    [super scrollViewDidScroll:scrollView];
    
    if (scrollView.isDragging) {
        [self.cocoaButton forceCloseButton];
    }
}

-(NSArray*) buttonsWideFor:(CocoaButton*)cocoabutton;
{
    UIButton* b1 = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 33, 33)];
    [b1 setImage:[UIImage imageNamed:@"edit_off"] forState:UIControlStateNormal];
    [b1 setImage:[UIImage imageNamed:@"edit_on"] forState:UIControlStateHighlighted];
    [b1 addTarget:self action:@selector(_tapButton:) forControlEvents:UIControlEventTouchUpInside];
    b1.tag = 1;
    
    UIButton* b2 = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 33, 33)];
    [b2 setImage:[UIImage imageNamed:@"credits_facebook_off"] forState:UIControlStateNormal];
    [b2 setImage:[UIImage imageNamed:@"credits_facebook_on"] forState:UIControlStateHighlighted];
    [b2 addTarget:self action:@selector(_tapButton:) forControlEvents:UIControlEventTouchUpInside];
    b2.tag = 2;
    
    UIButton* b3 = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 33, 33)];
    [b3 setImage:[UIImage imageNamed:@"credits_twitter_off"] forState:UIControlStateNormal];
    [b3 setImage:[UIImage imageNamed:@"credits_twitter_on"] forState:UIControlStateHighlighted];
    [b3 addTarget:self action:@selector(_tapButton:) forControlEvents:UIControlEventTouchUpInside];
    b3.tag = 3;
    
    return @[b1, b2, b3];
}

-(void) _tapButton:(UIButton*)button
{
    switch (button.tag) {
        case 1:
        {
            Mail* mail = [Mail newMailFormCurrentAccount];
            
            Persons* p = [Persons sharedInstance];
            
            if (p.idxCocoaPerson == 0) {
                Person* more = [Person createWithName:nil email:@"support@cocoamail.com" icon:[UIImage imageNamed:@"cocoamail"] codeName:nil];
                p.idxCocoaPerson = [p addPerson:more];
            }
            
            mail.toPersonID = @[@(p.idxCocoaPerson)];
            
            [[NSNotificationCenter defaultCenter] postNotificationName:kPRESENT_EDITMAIL_NOTIFICATION object:nil userInfo:@{kPRESENT_MAIL_KEY:mail}];
            break;
        }
        case 2:
            [ViewController presentAlertWIP:@"Go to Cocoamail facebook page"];
            break;
        case 3:
            [ViewController presentAlertWIP:@"Go to Cocoamail twitter page"];
            break;
            
        default:
            break;
    }
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
