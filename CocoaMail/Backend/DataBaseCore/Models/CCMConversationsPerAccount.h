//
//  CCMConversationsPerAccount.h
//  CocoaMail
//
//  Created by Andrew Cerier on 1/4/17.
//  Copyright © 2017 Christopher Hockley. All rights reserved.
//
// The CCMConversationsPerAccount class ontains:
//          a mutable Array of mutable IndexSets, one per account
//          where each IndexSet is a mutable set of conversation indecies for that account
//
#import <Foundation/Foundation.h>

@interface CCMConversationsPerAccount : NSObject

- (instancetype)initWithAccountCapacity:(NSUInteger)numberAccounts;
-(void) appendEmptyAccount;  // Append a new empty account mail index set for each non-All account
-(NSUInteger)accountCount;
-(NSUInteger)conversationsInAllAccounts;
-(void)addConversationIndex:(NSUInteger)conversationIndex forAccount:(NSUInteger)accountIndex;
-(void)removeConversationIndex:(NSUInteger)conversationIndex forAccount:(NSUInteger)accountIndex;
-(BOOL)containsConversationIndex:(NSUInteger)conversationIndex inAccount:(NSUInteger)accountIndex;
-(NSString*)description;

@end
