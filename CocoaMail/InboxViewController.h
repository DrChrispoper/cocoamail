//
//  InboxViewController.h
//  CocoaMail
//
//  Created by Christopher Hockley on 19/08/15.
//  Copyright (c) 2015 Christopher Hockley. All rights reserved.
//

#import <UIKit/UIKit.h>

typedef void (^CRefreshCompletionHandler) (BOOL didReceiveNewPosts) ;

@interface InboxViewController : UITableViewController

@property (nonatomic, retain) NSIndexPath* selectedIndexPath;
@property (nonatomic) BOOL folderChanged;

-(void)refreshWithCompletionHandler:(CRefreshCompletionHandler)completionHandler;

@end

