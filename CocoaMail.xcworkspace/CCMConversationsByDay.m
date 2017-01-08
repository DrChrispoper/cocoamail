//
//  CCMConversationsByDay.m
//  CocoaMail
//
//  Created by Andrew Cerier on 1/7/17.
//  Copyright © 2017 Christopher Hockley. All rights reserved.
//

#import "CCMConversationsByDay.h"
#import "Mail.h"
#import "Conversation.h"
#import "Accounts.h"
#import "DateUtil.h"

@interface CCMConversationsByDay ()

// conversationsPerDay is a mutable array (one per day) of dictionaries
//
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *conversationsPerDay;

@end

@implementation CCMConversationsByDay

- (instancetype)initWithDayCapacity:(NSInteger)capacity
{
    self = [super init];
    if (self) {
        _conversationsPerDay = [[NSMutableArray alloc] initWithCapacity:capacity];  // 100 days
    }
    return self;
}

-(NSDictionary*) _dayProperties:(NSInteger)day
{
    NSInteger dayCount = [self dayCount];
    
    DDAssert(day >= 0 && day < dayCount,
             @"day (%@) out of bounds (0-%@",
             @(day),(@(dayCount-1)));
    
    return self.conversationsPerDay[day];
}

-(CCMMutableConvIndexArray*) conversationsForDay:(NSInteger) day
{
    NSDictionary *dayDict = [self _dayProperties:day];
    
    NSArray *dayConvList = dayDict[@"list"];
    
    return [dayConvList mutableCopy];
}
-(NSDate*)dateForDay:(NSInteger)day
{
    NSDictionary *dayDict = [self _dayProperties:day];
    
    return dayDict[@"day"];}

-(NSInteger) dayCount
{
    NSInteger numberOfDays = self.conversationsPerDay.count;
    
    return numberOfDays;
}
-(BOOL) isEmpty
{
    return ( [self dayCount] == 0);
}

-(void)enumerateAllMailsUsingBlock:(void (^)(Mail *msg))block
{
    for (NSDictionary* d in self.conversationsPerDay) {
        
        NSArray* convs = d[@"list"];
        
        for (ConversationIndex* cI in convs) {
            Conversation* con = [[Accounts sharedInstance] conversationForCI:cI];
            for (Mail* m in con.mails) {
                block(m);
            }
        }
    }
}

-(NSDictionary*) _conversationIndexEntryWithIndex:(ConversationIndex*)conIndex andDate:(NSDate*)conDate
{
    NSMutableArray *conversationList = [NSMutableArray arrayWithObject:conIndex];
    
    NSDictionary* conversationIndex =
    @{@"list": conversationList,
      @"day" : conDate };
    
    return conversationIndex;
}
-(void)insertConservationIndex:(ConversationIndex*)conIndex andDate:(NSDate*)conDate atDayIndex:(NSInteger)dayIndex
{
    NSDictionary* conIndexEntry = [self _conversationIndexEntryWithIndex:conIndex andDate:conDate];
    
    [self.conversationsPerDay insertObject:conIndexEntry atIndex:dayIndex];
}
-(void)appendConversationIndex:(ConversationIndex*)conIndex andDate:(NSDate*)conDate
{
    NSDictionary* conIndexEntry = [self _conversationIndexEntryWithIndex:conIndex andDate:conDate];
    
    [self.conversationsPerDay addObject:conIndexEntry];
}
-(void)removeConversationAtIndex:(NSInteger)dayIndex
{
    NSInteger dayCount = [self dayCount];
    
    DDAssert(dayIndex >= 0 && dayIndex < dayCount,
             @"day index (%@) out of range (0 - %@)",
             @(dayIndex),@(dayCount-1));
    
    [self.conversationsPerDay removeObjectAtIndex:dayIndex];

}

-(NSString*)description
{
    NSMutableString *text = [NSMutableString string];
    
    NSInteger dayCount = [self dayCount];
    [text appendFormat:@"\n\nCCMConversationsByDay has %@ days:\n",@(dayCount)];
    
    for (NSInteger day = 0; day < dayCount; day++ ) {
        
        NSDate *convDate = [self dateForDay:day];
        NSString* humanDate = [[DateUtil getSingleton] humanDate:convDate];

        [text appendFormat:@"\tday [%@] = \"%@\":\n",@(day),humanDate];
        
        CCMMutableConvIndexArray *dayConvs = [self conversationsForDay:day];
        
        for ( NSInteger convNum = 0; convNum < dayConvs.count; convNum++ ) {
            
            [text appendFormat:@"\t\tconversation %@:\n",@(convNum)];
            
            ConversationIndex *ci = dayConvs[convNum];
            Conversation* conv = [[Accounts sharedInstance] conversationForCI:ci];
            
            [text appendFormat:@"\t\t\tIsDraft: %@\n",(conv.isDraft?@"YES":@"NO")];
            
            for (NSInteger mailNum = 0; mailNum < conv.mails.count; mailNum++ ) {
                Mail *msg = conv.mails[mailNum];
                NSString *subj  = msg.subject;
                NSString *msgid = [msg.msgID substringToIndex:8];
                
                [text appendFormat:@"\t\t\tMail %@: Subj: \"%@\" ID prefix = \"%@\"\n",@(mailNum),subj,msgid];
            }
        }
    }

    return text;
}

@end
