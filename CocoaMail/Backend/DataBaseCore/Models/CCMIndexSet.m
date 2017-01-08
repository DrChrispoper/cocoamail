//
//  CCMIndexSet.m
//  CocoaMail
//
//  Created by Andrew Cerier on 1/4/17.
//  Copyright © 2017 Christopher Hockley. All rights reserved.
//
//  indexSet is an array of index sets, one for each account
//      indexSet[account] -> mutable index set
//

#import "CCMIndexSet.h"
#import "Conversation.h"
#import "UserSettings.h"
#import "CocoaLumberjack.h"

@interface CCMIndexSetArray ()
@property (nonatomic, strong) NSMutableArray<NSMutableIndexSet*>* indexSetArray;
@end

@implementation CCMIndexSetArray

- (instancetype)initWithCapacity:(NSInteger)capacity
{
    self = [super init];
    if (self) {
        // indexSet is an array of index sets, one for each account
        //      indexSet[account] -> mutable index set
        self.indexSetArray = [[NSMutableArray alloc]initWithCapacity:capacity];
    }
    return self;
}

-(void) appendEmptyIndexSet
{
    [self.indexSetArray addObject:[[NSMutableIndexSet alloc]init]];
}

-(NSInteger)indexSetCount;
{
    return self.indexSetArray.count;
}
-(NSInteger)totalIndexCount
{
    NSInteger totalIndexCount = 0;
    
    for (NSMutableIndexSet* indexSet in self.indexSetArray) {
        totalIndexCount += indexSet.count;
    }
    return totalIndexCount;
}

-(NSMutableIndexSet*)indexSetAtIndex:(NSInteger)arrayIndex
{
    DDAssert(arrayIndex>=0,@"Array Index must be greater than or equal to zero");
    DDAssert(arrayIndex>self.indexSetArray.count, @"Array Index (%@) must not exceed element count (%@)",@(arrayIndex),@(self.indexSetArray.count));
    
    return self.indexSetArray[arrayIndex];
}


// MARK: - ConversationIndex

-(void)addConversationIndex:(ConversationIndex*)ci
{
    [self.indexSetArray[ci.user.accountIndex] addIndex:ci.index];
}
-(void)removeConversationIndex:(ConversationIndex*)ci
{
    [self.indexSetArray[ci.user.accountIndex] removeIndex:ci.index];
}

-(BOOL)containsConversationIndex:(ConversationIndex*)ci
{
    return [self.indexSetArray[ci.user.accountIndex] containsIndex:ci.index];
}

-(NSString*)description
{
    NSMutableString *text = [NSMutableString string];
    
    NSInteger count = self.indexSetArray.count;
    
    [text appendFormat:@"Index Set Array has %@ elements.",@(count)];
    
    for (NSInteger arrayIndex = 0; arrayIndex < count; arrayIndex++) {
        NSMutableIndexSet *indexSet = [self indexSetAtIndex:arrayIndex];
        [text appendString:[indexSet description]];
    }
    
    return text;
}



@end
