//
//  FolderViewController.h
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 14/07/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "ViewController.h"


@interface FolderViewController : InViewController

-(void) refreshWithCompletionHandler:(CRefreshCompletionHandler)completionHandler;


@end
