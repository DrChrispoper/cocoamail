//
//  SearchViewController.m
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 06/09/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "SearchViewController.h"

#import "SearchTableViewCell.h"
#import "Accounts.h"
#import "Mail.h"
#import "Attachments.h"
#import "SearchRunner.h"
#import <ReactiveCocoa/ReactiveCocoa.h>


@interface SearchViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate>

@property (nonatomic, weak) UITableView* table;
@property (nonatomic, strong) id keyboardNotificationId;
@property (nonatomic, strong) UISearchBar* searchBar;
@property (nonatomic, strong) UIView* searchBarSupport;

@property (nonatomic, strong) NSArray* searchResult;
@property (nonatomic) NSInteger lastSearchLength;

@property (nonatomic, retain) NSOperationQueue* searchQueue;

@end

@implementation SearchViewController

-(void) viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    
    
    UINavigationItem* item = [[UINavigationItem alloc] initWithTitle:@""];
    item.leftBarButtonItem = [self backButtonInNavBar];
    
    item.titleView = [WhiteBlurNavBar titleViewForItemTitle:NSLocalizedString(@"Search", @"Search")];
    
    UITableView* table = [[UITableView alloc] initWithFrame:CGRectMake(0,
                                                                       0,
                                                                       screenBounds.size.width,
                                                                       screenBounds.size.height - 20)
                                                      style:UITableViewStyleGrouped];
    table.contentInset = UIEdgeInsetsMake(44, 0, 60, 0);
    table.scrollIndicatorInsets = UIEdgeInsetsMake(44 + 46, 0, 0, 0);
    
    table.backgroundColor = [UIGlobal standardLightGrey];
    
    [self.view addSubview:table];

    self.view.backgroundColor = table.backgroundColor;
    
    [self setupNavBarWith:item overMainScrollView:table];
    
    table.allowsSelection = false;
    table.rowHeight = 90;
    table.separatorStyle = UITableViewCellSeparatorStyleNone;
    
    table.dataSource = self;
    table.delegate = self;
    self.table = table;

    [self fetchAll];
}

-(void) _hideKeyboard
{
    [self.searchBar resignFirstResponder];
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

-(void) viewDidAppear:(BOOL)animated
{
    [super viewDidAppear:animated];
    
    [self _keyboardNotification:YES];
    
    [self.searchBar becomeFirstResponder];
}

-(void) viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    [self _keyboardNotification:NO];
}

-(void) cleanBeforeGoingBack
{
    [self _keyboardNotification:NO];
    
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

#define kCONTENT @"c"
#define kSUBTEXT @"st"

-(NSInteger) tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.searchResult.count;
}

-(UITableViewCell*) tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath
{
    NSString* reuseID = @"kSearchCellID";
    
    SearchTableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:reuseID];
    
    if (cell == nil) {
        cell = [[SearchTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseID];
    }
    
    NSDictionary* dic = self.searchResult[indexPath.row];
    
    Conversation* c = dic[kCONTENT];
    NSString* st = dic[kSUBTEXT];
    
    [cell fillWithConversation:c subText:st highlightWord:self.searchBar.text];
    
    return cell;
}

#pragma mark - Table Delegate

-(CGFloat) tableView:(UITableView*)tableView heightForFooterInSection:(NSInteger)section
{
    return CGFLOAT_MIN;
}

-(CGFloat) tableView:(UITableView*)tableView heightForHeaderInSection:(NSInteger)section
{
    return (section == 0) ? 46 : CGFLOAT_MIN;
}

-(UIView*) tableView:(UITableView*)tableView viewForHeaderInSection:(NSInteger)section
{
    if (section==0) {
        
        if (self.searchBar ==nil) {
            
            UISearchBar* bar = [[UISearchBar alloc] initWithFrame:CGRectMake(0, 0, tableView.frame.size.width, 44)];
            bar.delegate = self;
            bar.autoresizingMask = UIViewAutoresizingFlexibleBottomMargin;
            self.searchBar = bar;
            
            UIView* support = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.frame.size.width, 46)];
            [support addSubview:bar];
            support.autoresizingMask = UIViewAutoresizingNone;
            
            self.searchBarSupport = support;
        }
        
        return self.searchBarSupport;
    }
    
    return nil;
}

-(NSIndexPath*) tableView:(UITableView*)tableView willSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
    return nil;
}

-(void) tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

-(void) insertRows:(Email*)email
{
    Conversation* conv = [[Conversation alloc] init];
    [conv addMail:[Mail mail:email]];
    [[[Accounts sharedInstance] currentAccount] addConversation:conv];
}

-(void) fetchAll
{
    [self.searchQueue addOperationWithBlock:^{
        [[[SearchRunner getSingleton] activeFolderSearch:0]
         subscribeNext:^(Email* email) {
             [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                 [self insertRows:email];
             }];
         }
         completed:^{
             [[NSOperationQueue mainQueue] addOperationWithBlock:^{}];
         }];
    }];
}

#pragma mark - SearchBar Delegate

-(void) _updateSearchResultWith:(NSString*)word
{
    if (word.length < 2) {
        self.searchResult = nil;
        return;
    }
    
    NSMutableArray* current;
    
    if (word.length <= 2 || self.lastSearchLength >= word.length) {
        NSArray* alls = [[[Accounts sharedInstance] currentAccount] getConversationsForFolder:FolderTypeWith(FolderTypeAll, 0)];
        current = [alls mutableCopy];
    }
    else {
        NSMutableArray* currentContent = [NSMutableArray arrayWithCapacity:self.searchResult.count];
        
        for (NSDictionary* d in self.searchResult) {
            [currentContent addObject:d[kCONTENT]];
        }
        
        current = currentContent;
    }
    
    self.lastSearchLength = word.length;
    
    NSMutableIndexSet* peopleIn = [[NSMutableIndexSet alloc] init];
    
    NSMutableArray* next = [NSMutableArray arrayWithCapacity:current.count];
    
    for (Conversation* c in current) {
        
        Mail* mail = [c firstMail];
        
        Person* p = [[Persons sharedInstance] getPersonID:mail.fromPersonID];
        
        NSString* fromName = p.name;
        NSString* title = mail.title;
        NSString* content = mail.content;
        
        NSMutableArray* attachs = [NSMutableArray arrayWithCapacity:mail.attachments.count];
        
        for (Attachment* a in mail.attachments) {
            [attachs addObject:a.fileName];
        }
        

        if (![peopleIn containsIndex:mail.fromPersonID] && [fromName rangeOfString:word options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [next addObject:@{kCONTENT:c, kSUBTEXT: @""}];
            [peopleIn addIndex:mail.fromPersonID];
            
        }
        else if ([title rangeOfString:word options:NSCaseInsensitiveSearch].location != NSNotFound) {
            [next addObject:@{kCONTENT:c, kSUBTEXT: @""}];
        }
        else {
            
            BOOL found = NO;
            
            for (NSString* att in attachs) {
                if ([att rangeOfString:word options:NSCaseInsensitiveSearch].location != NSNotFound) {
                    [next addObject:@{kCONTENT:c, kSUBTEXT: att}];
                    found = YES;
                    break;
                }
            }

            if (found) {
                continue;
            }
            
            NSRange r = [content rangeOfString:word options:NSCaseInsensitiveSearch];
            
            if (r.location != NSNotFound) {

                if (r.location>8) {
                    r.location -= 8;
                }
                else {
                    r.location -= 0;
                }
                
                if (content.length<r.location + 100) {
                    r.length = content.length - r.location;
                }
                else {
                    r.length = 100;
                }

                NSString* sub = [content substringWithRange:r];
                
                if (r.location!=0) {
                    sub = [NSString stringWithFormat:@"…%@", sub];
                }
                
                [next addObject:@{kCONTENT:c, kSUBTEXT: sub}];
            }
        }
    }
    
    
    self.searchResult = next;
}

-(void) searchBar:(UISearchBar*)searchBar textDidChange:(NSString*)searchText
{
    [self _updateSearchResultWith:searchBar.text];

    [self.table reloadData];
    
    [self.searchBar becomeFirstResponder];
    
}

-(void) searchBarSearchButtonClicked:(UISearchBar*)searchBar
{
    [searchBar resignFirstResponder];
}

@end
