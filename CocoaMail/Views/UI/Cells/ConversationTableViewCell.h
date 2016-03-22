//
//  ConversationTableViewCell.h
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 16/07/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import <UIKit/UIKit.h>

@class Conversation;

#define kMAIL_CELL_ID @"kMAIL_CELL_ID"
#define kCONVERSATION_CELL_ID @"kCONVERSATION_CELL_ID"


@protocol ConversationCellDelegate;


@interface ConversationTableViewCell : UITableViewCell

-(void) setupWithDelegate:(id<ConversationCellDelegate>)delegate;
-(void) fillWithConversation:(Conversation*)conv isSelected:(BOOL)selected isDebugMode:(BOOL)debugMode;

-(NSString*) currentID;

-(void) animatedClose;

-(BOOL) isReplyAll;
-(void) setAlwaysSwiped;

@end

@protocol ConversationCellDelegate

-(void) leftActionDoneForCell:(ConversationTableViewCell*)cell;
-(void) cell:(ConversationTableViewCell*)cell isChangingDuring:(double)timeInterval;

-(void) cellIsSelected:(ConversationTableViewCell*)cell;
-(void) cellIsUnselected:(ConversationTableViewCell*)cell;

-(void) unselectAll;


// datasource
-(UIPanGestureRecognizer*) tableViewPanGesture;
-(UIImageView*) imageViewForQuickSwipeAction;
-(BOOL) isPresentingDrafts;


@end

