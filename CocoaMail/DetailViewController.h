//
//  DetailViewController.h
//  CocoaMail
//
//  Created by Christopher Hockley on 19/08/15.
//  Copyright (c) 2015 Christopher Hockley. All rights reserved.
//

#import <UIKit/UIKit.h>

@interface DetailViewController : UIViewController

@property (strong, nonatomic) id detailItem;
@property (weak, nonatomic) IBOutlet UILabel *detailDescriptionLabel;

@end

