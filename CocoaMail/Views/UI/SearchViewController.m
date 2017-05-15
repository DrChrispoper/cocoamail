//
//  SearchViewController.m
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 06/09/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "SearchViewController.h"
#import "UserSettings.h"
#import "SearchTableViewCell.h"
#import "Accounts.h"
#import "Mail.h"
#import "Attachments.h"
#import "SearchRunner.h"
#import <ReactiveCocoa/ReactiveCocoa.h>
#import "ContactTableViewCell.h"
#import "CCMSearchTableViewController.h"

@interface SearchViewController () <UITableViewDataSource, UITableViewDelegate, UISearchBarDelegate, MailListDelegate, UISearchControllerDelegate, UISearchResultsUpdating, SearchDelegate>

@property (nonatomic, strong) UITableView* table;
@property (nonatomic, strong) id keyboardNotificationId;
//@property (nonatomic, strong) UISearchBar* searchBar;
//@property (nonatomic, strong) UIView* searchBarSupport;

@property (nonatomic, strong) NSMutableArray* data;
@property (nonatomic, strong) NSArray<NSArray*>* filteredResults;
@property (nonatomic, strong) NSString *text;

//@property (nonatomic) NSInteger lastSearchLength;

//@property (nonatomic, retain) NSOperationQueue* searchQueue;

@property (nonatomic) BOOL localSearchDone;
@property (nonatomic) BOOL serverSearchDone;

@property (nonatomic) BOOL canReload;

//Fetch result controller
@property (nonatomic, strong) UISearchController *searchController;

//for the results to be shown with two table delegates
@property (nonatomic, strong) CCMSearchTableViewController *resultsTableController;

@property BOOL searchControllerWasActive;
@property BOOL searchControllerSearchFieldWasFirstResponder;

@end

@implementation SearchViewController

-(void) updateDays:(NSArray*)days
{
    DDLogWarn(@"Empty updateDays: called");
}
-(void) insertConversationIndex:(ConversationIndex*)ci
{
    DDLogWarn(@"Empty insertConversationIndex: called");
}

-(void) viewDidLoad
{
    [super viewDidLoad];
    // Do any additional setup after loading the view.
    
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    
    UINavigationItem* item = [[UINavigationItem alloc] initWithTitle:@""];
    item.leftBarButtonItem = [self backButtonInNavBar];
    
    
    UITableView* table = [[UITableView alloc] initWithFrame:CGRectMake(0,
                                                                       0,
                                                                       screenBounds.size.width,
                                                                       screenBounds.size.height - 20)
                                                      style:UITableViewStyleGrouped];
    table.contentInset = UIEdgeInsetsMake(44, 0, 60, 0);
    table.scrollIndicatorInsets = UIEdgeInsetsMake(44 + 46, 0, 0, 0);
    
    table.backgroundColor = [UIGlobal standardLightGrey];
    
    [self.view addSubview:table];

    self.view.backgroundColor = [UIGlobal standardLightGrey];
    
    
    [[Accounts sharedInstance] currentAccount].mailListDelegate = self;

    table.allowsSelection = false;
    //table.rowHeight = 90;
    table.separatorStyle = UITableViewCellSeparatorStyleNone;
    
    table.dataSource = self;
    table.delegate = self;
    self.table = table;
    
    /*UIView* headerView = [[UIView alloc] init];
    headerView.backgroundColor = self.table.backgroundColor;
    
    UIActivityIndicatorView* button = [[UIActivityIndicatorView alloc]initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
    button.frame = CGRectMake(0.0, 0.0, [UIScreen mainScreen].bounds.size.width , 40.0);
    [button startAnimating];
    
    [headerView addSubview:button];
    
    self.table.tableFooterView = headerView;*/
    
    //self.searchQueue = [NSOperationQueue new];
    //[self.searchQueue setMaxConcurrentOperationCount:1];
    
    _resultsTableController = [[CCMSearchTableViewController alloc] init];
    _searchController = [[UISearchController alloc] initWithSearchResultsController:self.resultsTableController];
    
    self.searchController.searchResultsUpdater = self;
    self.searchController.searchBar.placeholder = nil;
    self.searchController.obscuresBackgroundDuringPresentation = NO;
    self.searchController.hidesNavigationBarDuringPresentation = NO;
    [self.searchController.searchBar sizeToFit];
    //self.table.tableHeaderView = self.searchController.searchBar;
    
    item.titleView = self.searchController.searchBar;
    
    //item.titleView = [WhiteBlurNavBar titleViewForItemTitle:NSLocalizedString(@"search-view.title", @"Search")];

    [self setupNavBarWith:item overMainScrollView:table];

    // we want to be the delegate for our filtered table so didSelectRowAtIndexPath is called for both tables
    self.resultsTableController.tableView.delegate = self;
    self.searchController.delegate = self;
    self.searchController.dimsBackgroundDuringPresentation = NO; // default is YES
    self.searchController.searchBar.delegate = self; // so we can monitor text changes + others
   
    self.resultsTableController.sDelegate = self;
    
    // Search is now just presenting a view controller. As such, normal view controller
    // presentation semantics apply. Namely that presentation will walk up the view controller
    // hierarchy until it finds the root view controller or one that defines a presentation context.
    //
    self.definesPresentationContext = YES;  // know where you want UISearchController to be displayed
    
    self.canReload = YES;
    
    [self setupData];
}

-(void) setupData
{
    NSMutableArray* alls = [[NSMutableArray alloc] init];
    
    BOOL isActiveAccountAll = [[Accounts sharedInstance] currentAccount].user.isAll;
    if (isActiveAccountAll) {
        for (NSUInteger idx = 0; idx < [AppSettings numActiveAccounts]; idx++) {
            Account* a = [[Accounts sharedInstance] account:idx];
            NSMutableArray<ConversationIndex*>* ci = [a getConversationsForFolder:CCMFolderTypeAll];
            [alls addObjectsFromArray:ci];
            
        }
    }
    else {
        Account* a = [[Accounts sharedInstance] currentAccount];
        NSMutableArray<ConversationIndex*>* ci = [a getConversationsForFolder:CCMFolderTypeAll];
        [alls addObjectsFromArray:ci];
    }
    
    self.data = [alls mutableCopy];
}

#pragma mark - UISearchBarDelegate

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
}

-(void) _hideKeyboard
{
    [self.searchController.searchBar resignFirstResponder];
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
    
    [[Accounts sharedInstance] currentAccount].mailListDelegate = self;
    
    // restore the searchController's active state
    
    if (self.searchControllerWasActive) {
        //[self.searchController setActive:NO];
        [self.table reloadData];
        //[self.view :self.resultsTableController.tableView];
        //self.searchController.searchBar.hidden = NO;
        
        //_searchControllerWasActive = NO;
        
        if (self.searchControllerSearchFieldWasFirstResponder) {
            _searchControllerSearchFieldWasFirstResponder = NO;
        }
    }
    else {
    //[self _keyboardNotification:YES];
    [self.searchController.searchBar becomeFirstResponder];
    }
    /*if (![self.searchBar.text isEqualToString:@""]) {
        [self reFetch:NO];
    }
    
    [self _keyboardNotification:YES];
    
    [self.searchBar becomeFirstResponder];*/
}

-(void) viewWillDisappear:(BOOL)animated
{
    [super viewWillDisappear:animated];
    
    self.canReload = YES;

    [self _keyboardNotification:NO];
}

-(void) cleanBeforeGoingBack
{
    [self _keyboardNotification:NO];
    [[SearchRunner getSingleton] cancel];
    //[self.searchQueue cancelAllOperations];
    [self.searchController setActive:NO];

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


-(UIView*) tableView:(UITableView*)tableView viewForHeaderInSection:(NSInteger)section
{
    /*if (section==0) {
        
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
    }*/
    
    return nil;
}

#pragma mark - UISearchControllerDelegate

// Called after the search controller's search bar has agreed to begin editing or when
// 'active' is set to YES.
// If you choose not to present the controller yourself or do not implement this method,
// a default presentation is performed on your behalf.
//
// Implement this method if the default presentation is not adequate for your purposes.
//

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar
{
    self.navBar.hidden = FALSE;
}

- (void)willPresentSearchController:(UISearchController *)searchController {
    // do something before the search controller is presented
    //self.table.contentInset = UIEdgeInsetsMake(0, 0, 60, 0);
}

- (void)didPresentSearchController:(UISearchController *)searchController {
    // do something after the search controller is presented
}

- (void)willDismissSearchController:(UISearchController *)searchController {
    // do something before the search controller is dismissed
    //self.table.contentInset = UIEdgeInsetsMake(44, 0, 60, 0);
}

- (void)didDismissSearchController:(UISearchController *)searchController {
    // do something after the search controller is dismissed
}

#define kCONTENT @"c"
#define kSUBTEXT @"st"

-(NSInteger) numberOfSectionsInTableView:(UITableView*)tableView
{
    return 2;
}

-(NSInteger) tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section
{
    return _searchControllerWasActive?[self.filteredResults[section] count]:0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{

        if (indexPath.section == 0) {
            return 45;
        }
        else {
            return 90;
        }
    
}

-(UITableViewCell*) tableView:(UITableView*)tableView cellForRowAtIndexPath:(NSIndexPath*)indexPath
{
    if (indexPath.section == 0) {
        Person* p = self.filteredResults[indexPath.section][indexPath.row];
        
        NSString* reuseID = @"kPersonCellID";
        
        ContactTableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:reuseID];
        
        if (cell==nil) {
            cell = [[ContactTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseID];
        }
        
        cell.sDelegate = self;
        
        [cell fillWithPerson:p];
        
        return cell;
    }
    else {
        NSString* reuseID = @"kSearchCellID";
        
        SearchTableViewCell* cell = [tableView dequeueReusableCellWithIdentifier:reuseID];
        
        if (cell == nil) {
            cell = [[SearchTableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:reuseID];
        }
        
        cell.sDelegate = self;
        
        NSDictionary* dic = self.filteredResults[indexPath.section][indexPath.row];
        
        Conversation* c = [[Accounts sharedInstance] conversationForCI:dic[kCONTENT]];
        NSString* st = dic[kSUBTEXT];
        
        [cell fillWithConversation:c subText:st highlightWord:self.text];
        
        return cell;
    }

}

-(NSIndexPath*) tableView:(UITableView*)tableView willSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
    self.canReload = NO;
    return nil;
}

-(void) tableView:(UITableView*)tableView didSelectRowAtIndexPath:(NSIndexPath*)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

#pragma mark - SearchBar Delegate

- (void)updateSearchResultsForSearchController:(UISearchController *)searchController {
    [self _updateSearchResultWith:searchController.searchBar.text];
}

-(void) _updateSearchResultWith:(NSString*)word
{
    if (!word) {
        word = @"";
    }
    /*if (word.length == 0) {
        //self.searchResult = nil;
        return ;
    }*/
    
    self.resultsTableController.text = word;
    self.text = word;
    
    NSMutableArray* current = [self.data mutableCopy];
    
    //self.lastSearchLength = word.length;
    
    NSMutableSet* peopleIn = [[NSMutableSet alloc] init];
    
    NSSortDescriptor* sortByDate = [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(date)) ascending:NO];
    [current sortUsingDescriptors:@[sortByDate]];
    
    NSMutableArray* next = [NSMutableArray arrayWithCapacity:current.count];
    
    for (ConversationIndex* c in current) {
        
        Mail* mail = [[[Accounts sharedInstance] conversationForCI:c] firstMail];
        
        Person* p = [[Persons sharedInstance] getPersonWithID:mail.fromPersonID];
        
        NSString* fromName = p.name;
        NSString* title = mail.subject;
        NSString* content = mail.body;
        
        if (!content){
            content = @"";
        }
        
        content = [content stringByReplacingOccurrencesOfString:@"\n" withString:@""];
        
        NSMutableArray* attachs = [NSMutableArray arrayWithCapacity:mail.attachments.count];
        
        for (Attachment* a in mail.attachments) {
            if (a.fileName) {
                [attachs addObject:a.fileName];
            }
        }
        

        if (![peopleIn containsObject:@(mail.fromPersonID)] && [fromName rangeOfString:word options:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch].location != NSNotFound) {
            [next addObject:@{kCONTENT:c, kSUBTEXT: @""}];
            [peopleIn addObject:@(mail.fromPersonID)];
            
        }
        else if ([title rangeOfString:word options:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch].location != NSNotFound) {
            [next addObject:@{kCONTENT:c, kSUBTEXT: @""}];
        }
        else {
            
            BOOL found = NO;
            
            for (NSString* att in attachs) {
                if ([att rangeOfString:word options:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch].location != NSNotFound) {
                    [next addObject:@{kCONTENT:c, kSUBTEXT: att}];
                    found = YES;
                    break;
                }
            }

            if (found) {
                continue;
            }
            
            NSRange r = [content rangeOfString:word options:NSCaseInsensitiveSearch|NSDiacriticInsensitiveSearch];
            
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
    
    NSMutableArray* ppl = [[NSMutableArray alloc] init];
    
    if (word.length>0) {
        
        word = [word lowercaseString];
        
        for (Person* p in [[Persons sharedInstance] allPersons]) {
            
            if ([p.name rangeOfString:word options:NSCaseInsensitiveSearch].location != NSNotFound) {
                [ppl addObject:p];
            }
            else if ([p.email rangeOfString:word options:NSCaseInsensitiveSearch].location != NSNotFound) {
                [ppl addObject:p];
            }
        }
    }
    
    CCMSearchTableViewController *tableController = (CCMSearchTableViewController *)self.searchController.searchResultsController;
    tableController.filteredResults = @[ppl, next];
    self.filteredResults = @[ppl, next];
    [self.table reloadData];
    [tableController.tableView reloadData];
    
    /*dispatch_async(dispatch_get_main_queue(), ^{
        self.searchResult = [NSArray arrayWithObjects:ppl, next, nil];
        [self.searchBar resignFirstResponder];
        [UIView animateWithDuration:0 animations:^{
            [self.table reloadData];
        } completion:^(BOOL finished) {
            DDLogInfo(@"Finished");
            [self.searchBar becomeFirstResponder];
        }];
    });*/
}

/*-(void) searchBar:(UISearchBar*)searchBar textDidChange:(NSString*)searchText
{
    [self.searchQueue addOperationWithBlock:^{
        [self _updateSearchResultWith:searchBar.text];
    }];
    
    [self.searchBar becomeFirstResponder];
}

-(void) searchBarSearchButtonClicked:(UISearchBar*)searchBar
{
    if (searchBar.text.length > 1) {
        [[NSOperationQueue mainQueue] addOperationWithBlock:^{
            [[[Accounts sharedInstance] currentAccount] doTextSearch:searchBar.text];
        }];
    }
    
    [searchBar resignFirstResponder];
}*/

-(void) removeConversationList:(NSArray *)convs { }

-(BOOL) isPresentingDrafts
{
    return false;
}

- (void)reFetch:(BOOL)force
{
    if (self.canReload) {
    [self setupData];
    //[self.searchQueue addOperationWithBlock:^{
        //self.lastSearchLength = self.searchBar.text.length;
    [self _updateSearchResultWith:self.searchController.searchBar.text];
    //}];
    }
}

-(void) localSearchDone:(BOOL)done
{
    self.localSearchDone = done;
    
    if (self.localSearchDone && self.serverSearchDone) {
        [self.table.tableFooterView setHidden:YES];
    }
}

-(void) serverSearchDone:(BOOL)done
{
    self.serverSearchDone = done;
    
    if (self.localSearchDone && self.serverSearchDone) {
        [self.table.tableFooterView setHidden:YES];
    }
}

- (void)selectedRow
{
    self.canReload = NO;

    [self _hideKeyboard];
    //self.searchController.active = NO;
    self.searchControllerWasActive = YES;
}

@end
