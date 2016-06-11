//
//  CCMSearchTableViewController.m
//  CocoaMail
//
//  Created by Christopher Hockley on 04/04/16.
//  Copyright © 2016 Christopher Hockley. All rights reserved.
//

#import "CCMSearchTableViewController.h"
#import "ContactTableViewCell.h"
#import "SearchTableViewCell.h"
#import "Accounts.h"
#import "SearchViewController.h"

@interface CCMSearchTableViewController () <UITableViewDataSource, UITableViewDelegate, SearchDelegate>

@end

@implementation CCMSearchTableViewController 

- (void)viewDidLoad {
    [super viewDidLoad];

    self.tableView.backgroundColor = [UIColor clearColor];
    
    self.view.backgroundColor = self.tableView.backgroundColor;
    
    self.tableView.allowsSelection = false;
    //self.tableView.rowHeight = 90;
    self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
}

- (void)viewWillAppear:(BOOL)animated
{
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    
    self.view.frame = CGRectMake(0, 44, screenBounds.size.width, screenBounds.size.height-44);
    
    
    [super viewWillAppear:animated];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

#pragma mark - Table Datasource

-(NSInteger) numberOfSectionsInTableView:(UITableView*)tableView
{
    return 2;
}

-(NSInteger) tableView:(UITableView*)tableView numberOfRowsInSection:(NSInteger)section
{
    return [self.filteredResults[section] count];
}

-(UIView*) tableView:(UITableView*)tableView viewForHeaderInSection:(NSInteger)section
{
    return nil;
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

#define kCONTENT @"c"
#define kSUBTEXT @"st"

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


-(void)selectedRow
{
    [self.sDelegate selectedRow];
}

@end
