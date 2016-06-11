//
//  ContactTableViewCell.h
//  CocoaMail
//
//  Created by Christopher Hockley on 08/02/16.
//  Copyright © 2016 Christopher Hockley. All rights reserved.
//

#import <UIKit/UIKit.h>

@class Person;

@protocol SearchDelegate;

@interface ContactTableViewCell : UITableViewCell

-(void) fillWithPerson:(Person*)p;

@property (nonatomic, weak) id<SearchDelegate> sDelegate;

@end
