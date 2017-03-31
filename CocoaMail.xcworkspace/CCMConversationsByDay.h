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
-(NSInteger) conversationCountOnDay:(NSInteger)dayIndex;

-(BOOL) isEmpty;        // dayCount == 0
-(NSInteger) totalConversationCount;        // total of all conversations on all days

-(void)enumerateAllMailsUsingBlock:(void (^)(Mail *msg))block;

// access elements of a day's conversations
-(NSDate*)dateForDay:(NSInteger)day;
-(ConversationIndex*) conversation:(NSInteger)convIndex onDay:(NSInteger)dayIndex;
-(NSDate*)datetimeForConversation:(NSInteger)convIndex onDay:(NSInteger)dayIndex;


-(void)sortConversationsByDateForDay:(NSInteger)dayIndex;

-(void)insertNewDayWithConservationIndex:(ConversationIndex*)conIndex andDate:(NSDate*)conDate atDayIndex:(NSInteger)dayIndex;
-(void)appendNewDayWithConversationIndex:(ConversationIndex*)conIndex andDate:(NSDate*)conDate;
-(void)removeDayAtIndex:(NSInteger)dayIndex;

-(void)appendConversation:(ConversationIndex*)conIndex onDay:(NSInteger)dayIndex;
-(void)insertConversation:(ConversationIndex*)ciToInsert atConversationArrayIndex:(NSInteger)convArrayIndex onDay:(NSInteger)dayIndex;
-(void)removeConversation:(NSInteger)conIndex onDay:(NSInteger)dayIndex;
-(void)exchangeConversationsAtIndex:(NSInteger)convIndexOne withConversationAtIndex:(NSInteger)convIndexTwo onDay:(NSInteger)dayIndex;

- (void)InsertConversation:(ConversationIndex *)ciToInsert;

-(NSString*)description;

@end
