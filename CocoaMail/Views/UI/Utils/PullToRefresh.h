//
//  PullToRefresh.h
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 19/08/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>


// TODO add a delegate to do the async action

@interface PullToRefresh : NSObject

-(void) scrollViewDidEndDragging:(UIScrollView *)scrollView;
-(void) scrollViewDidScroll:(UIScrollView *)scrollView;

@property (nonatomic) CGFloat delta;

@end
