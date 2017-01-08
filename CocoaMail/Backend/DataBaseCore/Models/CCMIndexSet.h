//
//  CCMIndexSet.h
//  CocoaMail
//
//  Created by Andrew Cerier on 1/4/17.
//  Copyright © 2017 Christopher Hockley. All rights reserved.
//
// CCMIndexSetArray contains a mutable Array of mutable IndexSets, one per account
//      where each IndexSet is a mutable set of mail/conversation indecies for that account
//
#import <Foundation/Foundation.h>

@class ConversationIndex;

@interface CCMIndexSetArray : NSObject

- (instancetype)initWithCapacity:(NSInteger)capacity;
-(void) appendEmptyIndexSet;  // Append a new empty account mail index set for each non-All account
-(NSInteger)indexSetCount;
-(NSInteger)totalIndexCount;
-(void)addConversationIndex:(ConversationIndex*)ci;
-(void)removeConversationIndex:(ConversationIndex*)ci;
-(BOOL)containsConversationIndex:(ConversationIndex*)ci;
-(NSString*)description;

@end
