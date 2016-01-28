//
//  ContactsTableViewCell.m
//  CocoaMail
//
//  Created by Christopher Hockley on 28/01/16.
//  Copyright © 2016 Christopher Hockley. All rights reserved.
//

#import "ContactsTableViewCell.h"

@implementation ContactsTableViewCell

- (void)layoutSubviews {
    [super layoutSubviews];
    self.imageView.bounds = CGRectMake(10,(self.frame.size.height-33)/2,33,33);
    self.imageView.frame = CGRectMake(10,(self.frame.size.height-33)/2,33,33);
    self.imageView.contentMode = UIViewContentModeScaleAspectFill;
    self.imageView.layer.cornerRadius = 16.5;
    self.imageView.layer.masksToBounds = YES;
    
    CGRect tmpFrame = self.textLabel.frame;
    tmpFrame.origin.x = 53;
    self.textLabel.frame = tmpFrame;
    
    tmpFrame = self.detailTextLabel.frame;
    tmpFrame.origin.x = 53;
    self.detailTextLabel.frame = tmpFrame;
    
    self.separatorInset = UIEdgeInsetsMake(0, 53, 0, 0);
    self.layoutMargins = UIEdgeInsetsMake(0, 53, 0, 0);
}

@end
