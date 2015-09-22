//
//  WhiteBlurNavBar.h
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 10/08/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>


@interface WhiteBlurNavBar : UINavigationBar

+(UIButton*) navBarButtonWithImage:(NSString*)normal andHighlighted:(NSString*)high;
+(CGFloat) navBarHeight;

+(UILabel*) titleViewForItemTitle:(NSString*)title;

// always call this two methods, the second one after that view is on the view hierarchy
-(instancetype) initWithWidth:(CGFloat)width;
-(void) createWhiteMaskOverView:(UIView*)view withOffset:(CGFloat)offset;


-(void) computeBlur; // use cache
-(void) computeBlurForceNew; // don't use cache
-(void) computeBlurForceNewDuring:(double)timeInterval; // don't use cache and for every screen update during timeInterval seconds


@end
