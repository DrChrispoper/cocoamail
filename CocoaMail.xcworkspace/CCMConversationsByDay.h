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

@interface CCMConversationsByDay : NSObject

- (instancetype)initWithDayCapacity:(NSUInteger)capacity;

-(NSUInteger) dayCount;
-(BOOL) isEmpty;        // dayCount == 0

-(NSUInteger) conversationCountOnDay:(NSUInteger)dayIndex;
-(NSUInteger) totalConversationCount;        // total of all conversations on all days


-(void)enumerateAllMailsUsingBlock:(void (^)(Mail *msg))block;

// access elements of a day's conversations
-(NSDate*)dateForDay:(NSUInteger)day;
-(ConversationIndex*) conversation:(NSUInteger)convIndex onDay:(NSUInteger)dayIndex;
-(NSDate*)datetimeForConversation:(NSUInteger)convIndex onDay:(NSUInteger)dayIndex;


-(void)sortConversationsByDateForDay:(NSUInteger)dayIndex;

-(void)insertNewDayWithConservationIndex:(ConversationIndex*)conIndex andDate:(NSDate*)conDate atDayIndex:(NSUInteger)dayIndex;
-(void)appendNewDayWithConversationIndex:(ConversationIndex*)conIndex andDate:(NSDate*)conDate;
-(void)removeDayAtIndex:(NSUInteger)dayIndex;

-(void)appendConversation:(ConversationIndex*)conIndex onDay:(NSUInteger)dayIndex;
-(void)insertConversation:(ConversationIndex*)ciToInsert atConversationArrayIndex:(NSUInteger)convArrayIndex onDay:(NSUInteger)dayIndex;
-(void)removeConversation:(NSUInteger)conIndex onDay:(NSUInteger)dayIndex;
-(void)exchangeConversationsAtIndex:(NSUInteger)convIndexOne withConversationAtIndex:(NSUInteger)convIndexTwo onDay:(NSUInteger)dayIndex;

- (void)InsertConversation:(ConversationIndex *)ciToInsert;

-(NSString*)description;

@end
