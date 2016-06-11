//
//  CCMSearchTableViewController.h
//  CocoaMail
//
//  Created by Christopher Hockley on 04/04/16.
//  Copyright © 2016 Christopher Hockley. All rights reserved.
//

#import <UIKit/UIKit.h>

@protocol SearchDelegate;

@interface CCMSearchTableViewController : UITableViewController

@property (nonatomic, strong) NSArray<NSArray*>* filteredResults;
@property (nonatomic, strong) NSString *text;
@property (nonatomic, weak) id<SearchDelegate> sDelegate;

@end