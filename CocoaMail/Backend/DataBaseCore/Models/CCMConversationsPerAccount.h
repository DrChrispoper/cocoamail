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

- (instancetype)initWithAccountCapacity:(NSInteger)numberAccounts;
-(void) appendEmptyAccount;  // Append a new empty account mail index set for each non-All account
-(NSInteger)accountCount;
-(NSInteger)conversationsInAllAccounts;
-(void)addConversationIndex:(NSInteger)conversationIndex forAccount:(NSInteger)accountIndex;
-(void)removeConversationIndex:(NSInteger)conversationIndex forAccount:(NSInteger)accountIndex;
-(BOOL)containsConversationIndex:(NSInteger)conversationIndex inAccount:(NSInteger)accountIndex;
-(NSString*)description;

@end
