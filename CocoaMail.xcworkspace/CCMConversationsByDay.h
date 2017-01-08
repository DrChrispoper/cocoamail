//
//  CCMConversationsByDay.h
//  CocoaMail
//
//  Created by Andrew Cerier on 1/7/17.
//  Copyright © 2017 Christopher Hockley. All rights reserved.
//
//  conversationsByDay is a Dictionary (one per day) or Index Sets (
//

#import <Foundation/Foundation.h>

@class Mail, ConversationIndex;

typedef NSMutableArray<ConversationIndex *> CCMMutableConvIndexArray;


@interface CCMConversationsByDay : NSObject

- (instancetype)initWithDayCapacity:(NSInteger)capacity;
-(NSInteger) dayCount;
-(BOOL) isEmpty;        // dayCount == 0

-(void)enumerateAllMailsUsingBlock:(void (^)(Mail *msg))block;

// access elements of a day's conversations
-(CCMMutableConvIndexArray*) conversationsForDay:(NSInteger) day;
-(NSDate*)dateForDay:(NSInteger)day;

-(void)insertConservationIndex:(ConversationIndex*)conIndex andDate:(NSDate*)conDate atDayIndex:(NSInteger)dayIndex;
-(void)appendConversationIndex:(ConversationIndex*)conIndex andDate:(NSDate*)conDate;
-(void)removeConversationAtIndex:(NSInteger)dayIndex;


@end
