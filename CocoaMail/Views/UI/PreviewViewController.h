//
//  PreviewViewController.h
//  CocoaMail
//
//  Created by Christopher Hockley on 15/01/16.
//  Copyright © 2016 Christopher Hockley. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "ViewController.h"

@class Conversation;

@interface PreviewViewController : UIViewController

@property (nonatomic, strong) Conversation* conversation;
@property (nonatomic, strong) UITableView* table;
@property (nonatomic, strong) NSIndexPath* indexPath;

@end