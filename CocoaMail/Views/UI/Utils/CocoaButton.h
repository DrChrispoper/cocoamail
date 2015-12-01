//
//  CocoaButton.h
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 11/08/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import <UIKit/UIKit.h>

@class CocoaButton;
@class Account;

@protocol CocoaButtonDatasource

-(NSArray*) buttonsWideFor:(CocoaButton*)cocoabutton;
-(NSArray*) buttonsHorizontalFor:(CocoaButton*)cocoabutton;
-(BOOL) automaticCloseFor:(CocoaButton*)cocoabutton;
-(BOOL) cocoabuttonLongPress:(CocoaButton*)cocoabutton;


@end


@interface CocoaButton : UIView

+(instancetype) sharedButton;

+(instancetype) fakeCocoaButtonForCredits;

@property (nonatomic, weak) id<CocoaButtonDatasource> datasource;

-(void) forceCloseButton;
-(void) updateColor;
-(void) openHorizontal;

-(void) forceCloseHorizontal;
-(void) forceOpenHorizontal;

-(void) replaceMainButton:(UIButton*)button;

-(void) closeHorizontalButton:(UIButton*)button refreshCocoaButtonAndDo:(void (^)())action;

+(void) animateHorizontalButtonCancelTouch:(UIButton*)button;

-(void) refreshAnimation:(BOOL)anim;

-(void) openWide;

-(void) enterLevel:(NSInteger)level;

@end