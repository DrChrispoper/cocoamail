//
//  SpamListViewController.m
//  CocoaMail
//
//  Created by Christopher Hockley on 18/12/15.
//  Copyright © 2015 Christopher Hockley. All rights reserved.
//

#import "SpamListViewController.h"
#import "ConversationTableViewCell.h"
#import "Mail.h"
#import "Persons.h"
#import "AppSettings.h"
#import "Conversation.h"

@interface SpamListViewController () <UITableViewDataSource, UITableViewDelegate, ConversationCellDelegate>

@property (nonatomic, strong) NSMutableArray* convs;
@property (nonatomic, weak) UITableView* table;
@property (nonatomic, strong) NSDictionary* spamPics;

@end

@implementation SpamListViewController

-(void) _applyTrueTitleViewTo:(UINavigationItem*)item
{
    UILabel* l = [WhiteBlurNavBar titleViewForItemTitle:@"Spam Test"];
    item.titleView = l;
}

-(void) viewDidLoad
{
    [super viewDidLoad];
    
    self.view.backgroundColor = [UIGlobal standardLightGrey];

    NSString *path = [[[NSBundle mainBundle] URLForResource:@"pics" withExtension:@"json"] path];
    NSData* spamPicsData = [[NSFileManager defaultManager] contentsAtPath:path];
    self.spamPics = [NSJSONSerialization JSONObjectWithData:spamPicsData options:0 error:nil];
    self.convs = [[NSMutableArray alloc]initWithCapacity:self.spamPics.count];

    CGRect screenBounds = [UIScreen mainScreen].bounds;
    
    UINavigationItem* item = [[UINavigationItem alloc] initWithTitle:@""];
    
    item.leftBarButtonItem = [self backButtonInNavBar];
    
    [self _applyTrueTitleViewTo:item];
    
    
    UITableView* table = [[UITableView alloc] initWithFrame:CGRectMake(0,
                                                                       0,
                                                                       screenBounds.size.width,
                                                                       screenBounds.size.height - 20)
                                                      style:UITableViewStyleGrouped];
    
    
    CGFloat offsetToUse = 44.f;
    
    table.contentInset = UIEdgeInsetsMake(offsetToUse, 0, 60, 0);
    
    table.scrollIndicatorInsets = UIEdgeInsetsMake(44, 0, 0,0.5);
    table.allowsSelection = false;
    table.rowHeight = 90;
    table.separatorStyle = UITableViewCellSeparatorStyleNone;
    table.backgroundColor = [UIGlobal standardLightGrey];
    
    [self.view addSubview:table];
    
    [self setupNavBarWith:item overMainScrollView:table];
    
    table.dataSource = self;
    table.delegate = self;
    self.table = table;
    
    [self setupData];
}

-(void) cleanBeforeGoingBack
{
    self.table.delegate = nil;
    self.table.dataSource = nil;
}

-(void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
}

-(void) setupData
{
    for (NSString* key in self.spamPics) {
        Mail* mail = [Mail newMailFormCurrentAccount];
        
        mail.subject = key;
        mail.body = @"";
        
        for (NSString* kkey in self.spamPics[key]) {
            for (NSString* domain in self.spamPics[key][kkey]) {
                
                Persons* p = [Persons sharedInstance];
                
                NSString* email = [NSString stringWithFormat:@"test@%@",[[domain stringByReplacingOccurrencesOfString:@"\\" withString:@""] stringByReplacingOccurrencesOfString:@".*" withString:@"com"]];
                
                NSString *path = [[[NSBundle mainBundle] URLForResource:key withExtension:@"png"] path];
                NSData* spamPicData = [[NSFileManager defaultManager] contentsAtPath:path];
                
                NSInteger pIdx;
                
                Person* more = [Person createWithName:key email:email icon:[UIImage imageWithData:spamPicData] codeName:nil];
                pIdx = [p addPerson:more];
                
                
                mail.fromPersonID = pIdx;
                mail.toPersonID = @[@(pIdx)];

                break;
            }
            
            break;
        }
        
        Conversation* conv = [[Conversation alloc]init];
        [conv addMail:mail];
        [self.convs addObject:conv];
    }
}

-(BOOL) isPresentingDrafts
{
    return NO;
}

-(UIImageView*) imageViewForQuickSwipeAction
{
    
    UIImageView* arch = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"swipe_delete"]];
    
    return arch;
}

-(void) unselectAll
{

}

-(void) _commonRemoveCell:(NSIndexPath*)ip
{

}

-(void) _removeCell:(ConversationTableViewCell*)cell
{

}

-(void) leftActionDoneForCell:(ConversationTableViewCell*)cell
{

}

-(void) cell:(ConversationTableViewCell*)cell isChangingDuring:(double)timeInterval
{

}

-(void) _manageCocoaButton
{

}

-(void) cellIsSelected:(ConversationTableViewCell*)cell
{

}

-(void) cellIsUnselected:(ConversationTableViewCell*)cell
{

}

-(UIPanGestureRecognizer*) tableViewPanGesture
{
    return self.table.panGestureRecognizer;
}

#pragma mark - Table Datasource

-(NSInteger) numberOfSectionsInTableView:(UITableView*)tableView
{
    return 1;
}

-(NSInteger) tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.convs.count;
}

-(UITableViewCell*) tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath
{
    Conversation* conv  = self.convs[indexPath.row];

    NSString* idToUse = kMAIL_CELL_ID;
    
    ConversationTableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:idToUse];
    
    if (cell == nil) {
        cell = [[ConversationTableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:idToUse];
        [cell setupWithDelegate:self];
    }
    
    [cell fillWithConversation:conv isSelected:NO isDebugMode:NO];
    
    return cell;
}

#pragma mark Table Delegate


-(NSIndexPath*) tableView:(UITableView*)tableView willSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
    return nil;
}

-(void) tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

#pragma mark - CocoaButton

-(BOOL) haveCocoaButton
{
    return NO;
}


@end
