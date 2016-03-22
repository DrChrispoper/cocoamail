//
//  LoginTableViewCell.h
//  CocoaMail
//
//  Created by Christopher Hockley on 21/03/16.
//  Copyright © 2016 Christopher Hockley. All rights reserved.
//

#import <UIKit/UIKit.h>

@protocol OPDelegate;

@interface LoginTableViewCell : UITableViewCell

-(UITextField*) fillWithPlaceholder:(NSString *)placeholder oP:(id<OPDelegate>)delegate;
-(void) fillWithButton:(NSString *)placeholder;

@end

@protocol OPDelegate

-(void) findLoginFrom1Password:(id)sender;

@end