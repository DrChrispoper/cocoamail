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

- (instancetype)initWithDayCapacity:(NSUInteger)capacity
{
    self = [super init];
    if (self) {
        _conversationsPerDay = [[NSMutableArray alloc] initWithCapacity:capacity];  // 100 days
    }
    return self;
}

-(NSDictionary*) _dayProperties:(NSUInteger)dayIndex
{
    @synchronized (self.conversationsPerDay) {
        NSUInteger dayCount = [self dayCount];
        
        DDAssert(dayIndex < dayCount, @"Day Index %@ must be less than Day Count %@",@(dayIndex),@(dayCount));
        
        NSDictionary *convsForDay = self.conversationsPerDay[dayIndex];
        
        DDAssert(convsForDay, @"Conversations for Day must exist for Day Index %@",@(dayIndex));
    
        return convsForDay;
    }
}


/**
 Get the conversations on the given day

 @param day day index ( 0 .. day count - 1)
 @return Returns nil on error
 */
-(NSMutableArray<ConversationIndex*>*) _conversationsForDay:(NSUInteger) dayIndex
{
    @synchronized (self.conversationsPerDay) {
        NSDictionary *dayDict = [self _dayProperties:dayIndex];

        NSMutableArray<ConversationIndex*>* dayConvList = dayDict[@"list"];
        
        DDAssert(dayConvList, @"Day Conversation List must exist for Day Index %@",@(dayIndex));
        
        return dayConvList;
    }
}
-(NSDate*)dateForDay:(NSUInteger)dayIndex
{
    @synchronized (self.conversationsPerDay) {
        NSDictionary *dayDict = [self _dayProperties:dayIndex];
        
        NSDate *dayDate = dayDict[@"day"];
        
        DDAssert(dayDate, @"Day Date must exist for Day Index %@",@(dayIndex));
        
        return dayDate;
    }
}
-(NSDate*)datetimeForConversation:(NSUInteger)convIndex onDay:(NSUInteger)dayIndex
{
    @synchronized (self.conversationsPerDay) {
        ConversationIndex *ci = [self conversation:convIndex onDay:dayIndex];
        
        NSDate *conversationDateTime = [ci date];
        
        DDAssert(conversationDateTime, @"Conversation Date Time must exist for Conversation Index %@ and Day Index %@",@(convIndex),@(dayIndex));
        
        return conversationDateTime;
    }
}

-(NSUInteger) dayCount
{
    @synchronized (self.conversationsPerDay) {
        NSUInteger numberOfDays = self.conversationsPerDay.count;
        
        return numberOfDays;
    }
}
-(NSUInteger) conversationCountOnDay:(NSUInteger)dayIndex
{
    @synchronized (self.conversationsPerDay) {
        NSArray *dayConvList = [self _conversationsForDay:dayIndex];
        
        return dayConvList.count;
    }
}
-(BOOL) isEmpty
{
    @synchronized (self.conversationsPerDay) {
        return ( [self dayCount] == 0 );
    }
}
-(NSUInteger) totalConversationCount        // total of all conversations on all days
{
    @synchronized (self.conversationsPerDay) {
        NSUInteger totalConversations = 0;
        
        for (NSUInteger day = 0; day < self.conversationsPerDay.count; day++ ) {
            totalConversations += [self conversationCountOnDay:day];
        }
        return totalConversations;
    }
}
-(ConversationIndex*) conversation:(NSUInteger)convIndex onDay:(NSUInteger)dayIndex
{
    @synchronized (self.conversationsPerDay) {
        NSMutableArray<ConversationIndex*>* convs = [self _conversationsForDay:dayIndex];
        
        ConversationIndex *ci = convs[convIndex];
        
        DDAssert(ci, @"ConversationIndex must exist for conversation index %@ and day index %@",@(convIndex),@(dayIndex));
        
        return ci;
    }
}
-(void)enumerateAllMailsUsingBlock:(void (^)(Mail *msg))block
{
    @synchronized (self.conversationsPerDay) {
        for (NSDictionary* d in self.conversationsPerDay) {
            
            NSArray<ConversationIndex*>* convs = d[@"list"];
            
            DDAssert(convs, @"Day Conversation List must exist for Day");
            
            for (ConversationIndex* cI in convs) {
                Conversation* con = [[Accounts sharedInstance] conversationForCI:cI];
                for (Mail* conversationMail in con.mails) {
                    block(conversationMail);
                }
            }
        }
    }
}

-(void)sortConversationsByDateForDay:(NSUInteger)dayIndex
{
    NSSortDescriptor *sortByDate = [NSSortDescriptor sortDescriptorWithKey:NSStringFromSelector(@selector(date)) ascending:NO];
    
    @synchronized (self.conversationsPerDay) {
        NSDictionary *dayDict = [self _dayProperties:dayIndex];
        
        NSMutableArray<ConversationIndex*>* daysConversationList = dayDict[@"list"];
        
        DDAssert(daysConversationList, @"Day Conversation List must exist for Day");
        
        [daysConversationList sortUsingDescriptors:@[sortByDate]];
    }
}
-(NSDictionary*) _createNewConversationsList:(ConversationIndex*)conIndex forDate:(NSDate*)conDate
{
    NSMutableArray *conversationList = [NSMutableArray arrayWithObject:conIndex];
    
    NSDictionary* conversationIndex =
    @{@"list": conversationList,
      @"day" : conDate };
    
    return conversationIndex;
}

-(void)insertNewDayWithConservationIndex:(ConversationIndex*)conIndex andDate:(NSDate*)conDate atDayIndex:(NSUInteger)dayIndex
{
    NSDictionary* daysConversations = [self _createNewConversationsList:conIndex forDate:conDate];
    
    DDAssert(daysConversations, @"daysConversations must not be nil.");
    
    @synchronized (self.conversationsPerDay) {
        [self.conversationsPerDay insertObject:daysConversations atIndex:dayIndex];
    }
}
-(void)appendNewDayWithConversationIndex:(ConversationIndex*)conIndex andDate:(NSDate*)conDate
{
    NSDictionary* daysConversations = [self _createNewConversationsList:conIndex forDate:conDate];
    
    @synchronized (self.conversationsPerDay) {
        [self.conversationsPerDay addObject:daysConversations];
    }
}
-(void)removeDayAtIndex:(NSUInteger)dayIndex
{
    @synchronized (self.conversationsPerDay) {
        NSUInteger dayCount = [self dayCount];
        
        DDAssert(dayIndex >= 0 && dayIndex < dayCount,
                 @"removeDayAtIndex: day index (%@) out of range (0 - %@)",
                 @(dayIndex),@(dayCount-1));
    
        [self.conversationsPerDay removeObjectAtIndex:dayIndex];
    }

}
-(void)appendConversation:(ConversationIndex*)conIndex onDay:(NSUInteger)dayIndex
{
    @synchronized (self.conversationsPerDay) {
        NSMutableArray<ConversationIndex*>* conversationsForDay = [self _conversationsForDay:dayIndex];
        [conversationsForDay addObject:conIndex];
    }
}
-(void)insertConversation:(ConversationIndex*)ciToInsert atConversationArrayIndex:(NSUInteger)convArrayIndex onDay:(NSUInteger)dayIndex
{
    @synchronized (self.conversationsPerDay) {
        NSMutableArray<ConversationIndex*>* conversationsForDay = [self _conversationsForDay:dayIndex];
        [conversationsForDay insertObject:ciToInsert atIndex:convArrayIndex];
    }
}
-(void)removeConversation:(NSUInteger)conIndex onDay:(NSUInteger)dayIndex
{
    @synchronized (self.conversationsPerDay) {
        NSMutableArray<ConversationIndex*>* conversationsForDay = [self _conversationsForDay:dayIndex];
        [conversationsForDay removeObjectAtIndex:conIndex];
    }
}
-(void)exchangeConversationsAtIndex:(NSUInteger)convIndexOne withConversationAtIndex:(NSUInteger)convIndexTwo onDay:(NSUInteger)dayIndex
{
    @synchronized (self.conversationsPerDay) {
        NSMutableArray<ConversationIndex*>* conversationsForDay = [self _conversationsForDay:dayIndex];
        [conversationsForDay exchangeObjectAtIndex:convIndexOne withObjectAtIndex:convIndexTwo];
    }
}

- (void)InsertConversation:(ConversationIndex *)ciToInsert
{
    @synchronized (self.conversationsPerDay) {
        BOOL conversationAddedToConvByDate = NO;
        
        // To find where to insert this conversation, we look through the convByDate array
        NSUInteger dayCount = [self dayCount];
        for (NSUInteger dayIndex = 0 ; dayIndex < dayCount ; dayIndex++) {
            
            NSDate* indexedDayDate = [self dateForDay:dayIndex];
            
            if ( indexedDayDate ) {
                
                NSComparisonResult result = [[ciToInsert day] compare:indexedDayDate];
                
                if (result == NSOrderedDescending) {
                    //Email Before //Insert section before date //+ email
                    
                    [self insertNewDayWithConservationIndex:ciToInsert andDate:[ciToInsert day] atDayIndex:dayIndex];
                    
                    conversationAddedToConvByDate = YES;
                    break;
                }
                else if (result == NSOrderedSame) { // same day, so search through the coversations on that date
                                                    //Add email to section of date
                    
                    [self sortConversationsByDateForDay:dayIndex];
                    
                    NSUInteger conCount = [self conversationCountOnDay:dayIndex];
                    
                    for (NSUInteger convArrayIndex = 0 ; convArrayIndex < conCount ; convArrayIndex++) {
                        
                        ConversationIndex* indexedConversationIndex = [self conversation:convArrayIndex onDay:dayIndex];
                        
                        NSComparisonResult compareResult = [[ciToInsert date] compare:[indexedConversationIndex date]];
                        
                        if (compareResult == NSOrderedDescending) {
                            
                            [self insertConversation:ciToInsert atConversationArrayIndex:convArrayIndex onDay:dayIndex];
                            
                            conversationAddedToConvByDate = YES;
                            break;
                        }
                    }
                    
                    if (!conversationAddedToConvByDate) {
                        // Add at end
                        [self appendConversation:ciToInsert onDay:dayIndex];
                        conversationAddedToConvByDate = YES;
                    }
                    
                    break;
                }
            }
        }
        
        if (!conversationAddedToConvByDate) {
            //Date section not existing //Add new date //Add email to new date
            [self appendNewDayWithConversationIndex:ciToInsert andDate:[ciToInsert day]];
        }
    } // end @syncronized
}


-(NSString*)description
{
    NSMutableString *text = [NSMutableString string];
    
    @synchronized (self.conversationsPerDay) {
        NSUInteger dayCount = [self dayCount];
        [text appendFormat:@"\n\nCCMConversationsByDay has %@ days:\n",@(dayCount)];
        
        for (NSUInteger dayIndex = 0; dayIndex < dayCount; dayIndex++ ) {
            
            NSDate *convDate = [self dateForDay:dayIndex];
            if ( convDate == nil ) {
                DDLogError(@"No NSDate for day index %@",@(dayIndex));
                continue;   // skip to next day index
            }
            NSString* humanDate = [[DateUtil getSingleton] humanDate:convDate];
            
            NSMutableArray<ConversationIndex*> *dayConvs = [self _conversationsForDay:dayIndex];
            NSUInteger convsCount = dayConvs.count;
            
            [text appendFormat:@"DAY [%@], \"%@\" has %@ conversations.\n",@(dayIndex),humanDate,@(convsCount)];
            
            for ( NSUInteger convNum = 0; convNum < convsCount; convNum++ ) {
                
                ConversationIndex *ci = dayConvs[convNum];
                Conversation* conv = [[Accounts sharedInstance] conversationForCI:ci];
                NSUInteger msgCount = conv.mails.count;
                
                [text appendFormat:@"\tCONVERSATION %@ has %@ mail messages (draft = %@):\n",
                 @(convNum),@(msgCount),(conv.isDraft?@"YES":@"NO")];
                
                for (NSUInteger mailNum = 0; mailNum < msgCount; mailNum++ ) {
                    Mail *msg = conv.mails[mailNum];
                    NSString *subj  = msg.subject;
                    NSString *msgid = [msg.msgID substringToIndex:8];
                    
                    [text appendFormat:@"\t\tMAIL %@: Subj: \"%@\" ID prefix = \"%@\"\n",@(mailNum),subj,msgid];
                }
            }
        }
    }
    return text;
}

@end
