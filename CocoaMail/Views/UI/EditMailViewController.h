//
//  EditMailViewController.h
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 21/08/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "ViewController.h"
#import "InViewController.h"

@class Draft;

@interface EditMailViewController : InViewController

@property (nonatomic, strong) Draft* draft;


@end
