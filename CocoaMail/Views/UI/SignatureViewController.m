//
//  SignatureViewController.m
//  CocoaMail
//
//  Created by Christopher Hockley on 28/10/15.
//  Copyright © 2015 Christopher Hockley. All rights reserved.
//

#import "SignatureViewController.h"
#import "AppSettings.h"
#import "Accounts.h"

@interface SignatureViewController () <UITableViewDataSource, UITableViewDelegate, UITextViewDelegate>

@property (nonatomic, weak) UITableView* table;
@property (nonatomic, strong) NSArray* settings;
@property (nonatomic, strong) UITextView* signature;

@property (nonatomic, strong) id keyboardNotificationId;

@end

@implementation SignatureViewController

-(void) viewDidLoad
{
    [super viewDidLoad];
    
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    
    UINavigationItem* item = [[UINavigationItem alloc] initWithTitle:@""];
    
    item.leftBarButtonItem = [self backButtonInNavBar];
    
    NSString* title = NSLocalizedString(@"signature-view.title", @"Signature");
    item.titleView = [WhiteBlurNavBar titleViewForItemTitle:title];
    
    UITableView* table = [[UITableView alloc] initWithFrame:CGRectMake(0,
                                                                       0,
                                                                       screenBounds.size.width,
                                                                       screenBounds.size.height - 20)
                                                      style:UITableViewStyleGrouped];
    table.contentInset = UIEdgeInsetsMake(44, 0, 60, 0);
    table.scrollIndicatorInsets = UIEdgeInsetsMake(44, 0, 0, 0);
    
    table.backgroundColor = [UIGlobal standardLightGrey];
    
    [self.view addSubview:table];
    
    [self setupNavBarWith:item overMainScrollView:table];
    
    [self _prepareTable];
    
    table.dataSource = self;
    table.delegate = self;
    self.table = table;
}

-(BOOL) haveCocoaButton
{
    return NO;
}

-(void) _hideKeyboard
{
    [self.table endEditing:YES];
}

-(void) _keyboardNotification:(BOOL)listen
{
    if (listen) {
        
        id id3 = [[NSNotificationCenter defaultCenter] addObserverForName:UIKeyboardWillChangeFrameNotification
                                                                   object:nil
                                                                    queue:[NSOperationQueue mainQueue]
                                                               usingBlock:^(NSNotification* notif){
                                                                   CGRect r = [notif.userInfo[UIKeyboardFrameEndUserInfoKey] CGRectValue];
                                                                   
                                                                   NSInteger animType = [notif.userInfo[UIKeyboardAnimationCurveUserInfoKey] integerValue];
                                                                   CGFloat duration = [notif.userInfo[UIKeyboardAnimationDurationUserInfoKey] floatValue];
                                                                   
                                                                   [UIView animateWithDuration:duration
                                                                                         delay:0.
                                                                                       options:animType
                                                                                    animations:^{
                                                                                        CGRect rsv = self.table.frame;
                                                                                        rsv.size.height = r.origin.y - 20;
                                                                                        self.table.frame = rsv;
                                                                                    }
                                                                                    completion:nil];
                                                               }];
        
        self.keyboardNotificationId = id3;
    }
    else {
        [[NSNotificationCenter defaultCenter] removeObserver:self.keyboardNotificationId];
    }
}

#define TITLE @"title"
#define CONTENT @"content"

#define TEXT @"t"
#define TEXT_2 @"dt"
#define ACTION @"a"
#define DACTION @"da"
#define OBJECT @"o"

-(void) _prepareTable
{
    NSArray* infos = @[
                       @{TEXT: @"", TEXT_2 : [AppSettings signature:self.account.idx], DACTION : @"EDIT_SIG"}
                       ];
    
    
    NSString* tAccount = NSLocalizedString(@"signature-view.header-section", @"EDIT SIGNATURE");
    NSDictionary* Paccounts = @{TITLE:tAccount, CONTENT:infos};
    
    if (![[AppSettings getSingleton] premiumPurchased]) {
        NSString* tDelete = NSLocalizedString(@"signature-view.unlock-button", @"Unlock CocoaMail");
        NSDictionary* PDelete = @{TITLE:@"", CONTENT:@[@{TEXT:tDelete, DACTION : @"UNLOCK"}]};
        
        self.settings = @[Paccounts, PDelete];
        
        return;
    }
    
    self.settings = @[Paccounts];
}

-(void) viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    [self _keyboardNotification:YES];
}

-(void) viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    [self _keyboardNotification:NO];
}

-(void) cleanBeforeGoingBack
{
    [self _keyboardNotification:NO];

    [AppSettings setSignature:self.signature.text accountIndex:self.account.idx];

    self.table.delegate = nil;
    self.table.dataSource = nil;
}

-(void) scrollViewDidScroll:(UIScrollView*)scrollView
{
    [super scrollViewDidScroll:scrollView];
    
    if (scrollView.isDragging) {
        [self _hideKeyboard];
    }
}

#pragma mark - Table Datasource

-(NSInteger) numberOfSectionsInTableView:(UITableView*)tableView
{
    return self.settings.count;
}

-(NSInteger) tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section
{
    NSDictionary* sectionInfos = self.settings[section];
    NSArray* content = sectionInfos[CONTENT];
    
    return content.count;
}

-(CGFloat) tableView:(UITableView*)tableView heightForRowAtIndexPath:(NSIndexPath*)indexPath
{
    
    CGFloat base = 52.f;
    
    if (indexPath.row==0) {
        base += .5;
        
        if (indexPath.section == 0) {
            base = base*3;
        }
    }
    
    return base;
}

-(UITableViewCell*) tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath
{
    NSDictionary* sectionInfos = self.settings[indexPath.section];
    NSArray* content = sectionInfos[CONTENT];
    NSDictionary* infoCell = content[indexPath.row];
    
    
    UITableViewCell* cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"noID"];
    
    
    cell.textLabel.text = infoCell[TEXT];
    
    cell.textLabel.textAlignment = NSTextAlignmentNatural;
    cell.textLabel.textColor = [UIColor blackColor];
    
    [cell.textLabel sizeToFit];
    
    cell.accessoryType = UITableViewCellAccessoryNone;
    
    
    CGSize bounds = tableView.bounds.size;
    bounds.height = 52;
    
    if (infoCell[TEXT_2] != nil) {
        
        bounds.height = 52 * 3;

        UITextView* tf = [[UITextView alloc] initWithFrame:CGRectMake(10, 0, bounds.width - 20, bounds.height)];
        tf.text = infoCell[TEXT_2];
        tf.font = [UIFont systemFontOfSize:16];
        tf.delegate = self;
        
        if (![[AppSettings getSingleton] premiumPurchased]) {
            [tf setEditable:NO];
            [tf setAlpha:0.5];
        }
        
        [cell addSubview:tf];
    
        NSString* action = infoCell[DACTION];
        
        if ([action isEqualToString:@"EDIT_SIG"]) {
            tf.tag = 0;
            self.signature = tf;
        }
        
    }
    
    if (infoCell[DACTION]!=nil) {
        
        NSString* action = infoCell[DACTION];
        
        if ([action isEqualToString:@"NAV_BAR_SOLID"]) {
        }
        else if ([action isEqualToString:@"UNLOCK"]) {
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.textLabel.textAlignment = NSTextAlignmentCenter;
            cell.textLabel.textColor = [UIColor colorWithRed:0.0 green:122.0/255.0 blue:1.0 alpha:1.0];
        }
    }
    
    cell.selectionStyle = UITableViewCellSelectionStyleGray;
    
    return cell;
}

-(NSString*) tableView:(UITableView*)tableView titleForHeaderInSection:(NSInteger)section
{
    NSDictionary* sectionInfos = self.settings[section];
    
    return sectionInfos[TITLE];
}

#pragma mark Table Delegate

-(CGFloat) tableView:(UITableView*)tableView heightForFooterInSection:(NSInteger)section
{
    return CGFLOAT_MIN;
}

-(CGFloat) tableView:(UITableView*)tableView heightForHeaderInSection:(NSInteger)section
{
    return 52;
}

-(NSIndexPath*) tableView:(UITableView*)tableView willSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
    NSDictionary* sectionInfos = self.settings[indexPath.section];
    NSArray* content = sectionInfos[CONTENT];
    NSDictionary* infoCell = content[indexPath.row];
    
    NSString* directAction = infoCell[DACTION];
    
    if (directAction.length > 0) {
        
        NSArray* reload = nil;
        
        if ([directAction isEqualToString:@"UNLOCK"]) {
            [[AppSettings getSingleton] setPremiumPurchased:YES];
            [self _prepareTable];
            [self.table reloadData];
        }
        
        if (reload.count > 0) {
            [tableView reloadRowsAtIndexPaths:reload withRowAnimation:UITableViewRowAnimationNone];
        }
        
        return nil;
    }
    
    return nil;
}

-(void) tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

#pragma mark - TextField delegate

-(void) textFieldDidEndEditing:(UITextField*)textField
{
    if (textField.tag == 0) {
        [AppSettings setSignature:textField.text accountIndex:self.account.idx];
    }
}

-(BOOL) textFieldShouldReturn:(UITextField*)textField
{
    [textField resignFirstResponder];
    
    return YES;
}


@end
