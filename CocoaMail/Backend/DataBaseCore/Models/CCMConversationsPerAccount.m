//
//  CCMConversationsPerAccount.m
//  CocoaMail
//
//  Created by Andrew Cerier on 1/4/17.
//  Copyright © 2017 Christopher Hockley. All rights reserved.
//
//  conversationsByAccount is muttable array of index sets, one for each account
//      indexSet[account] -> mutable index set
//

#import "Conversation.h"
#import "UserSettings.h"
#import "CocoaLumberjack.h"
#import "CCMConversationsPerAccount.h"

@interface CCMConversationsPerAccount ()
@property (nonatomic, strong) NSMutableArray<NSMutableIndexSet*>* conversationsByAccount;
@end

@implementation CCMConversationsPerAccount

- (instancetype)initWithAccountCapacity:(NSInteger)capacity
{
    self = [super init];
    if (self) {
        // conversationsByAccount is an array of index sets, one for each account
        //      conversationsByAccount[account] -> mutable index set
        self.conversationsByAccount = [[NSMutableArray alloc]initWithCapacity:capacity];
    }
    return self;
}

-(void) appendEmptyAccount
{
    [self.conversationsByAccount addObject:[[NSMutableIndexSet alloc]init]];
}

-(NSInteger)accountCount;
{
    return self.conversationsByAccount.count;
}

-(NSInteger)conversationsInAllAccounts
{
    NSInteger totalConversationCount = 0;
    
    for (NSMutableIndexSet* accountConversations in self.conversationsByAccount) {
        totalConversationCount += accountConversations.count;
    }
    return totalConversationCount;
}

// MARK: - local safety methods

-(NSMutableIndexSet*)_conversationsForAccount:(NSInteger)accountIndex
{
    DDAssert(accountIndex>=0 && accountIndex<self.conversationsByAccount.count,
             @"Array Index (%@) out of range. Valid: (0 to %@)",
             @(accountIndex),@(self.conversationsByAccount.count-1));
    
    return self.conversationsByAccount[accountIndex];
}

//-(NSMutableIndexSet *)_indexSetForConversationIndex:(ConversationIndex *)ci inAccount:(Account*)account
//{
//    
//    return [self _conversationsForAccount:account];
//}

// MARK: - Conversation: add, remove, contains?


-(void)addConversationIndex:(NSInteger)conversationIndex forAccount:(NSInteger)accountIndex
{
    NSMutableIndexSet *conversations = [self _conversationsForAccount:accountIndex];
    
    [conversations addIndex:conversationIndex];
}
-(void)removeConversationIndex:(NSInteger)conversationIndex forAccount:(NSInteger)accountIndex
{
    NSMutableIndexSet *conversations = [self _conversationsForAccount:accountIndex];
    
    [conversations removeIndex:conversationIndex];
}

-(BOOL)containsConversationIndex:(NSInteger)conversationIndex inAccount:(NSInteger)accountIndex
{
    NSMutableIndexSet *conversations = [self _conversationsForAccount:accountIndex];
    
    return [conversations containsIndex:conversationIndex];
}

// MARK: - Conversations Index Sets description

-(NSString*)description
{
    NSMutableString *text = [NSMutableString string];
    
    NSInteger acntCount = self.conversationsByAccount.count;
    
    [text appendFormat:@"\n\nConversations Per Account has %@ accounts:",@(acntCount)];
    
    for (NSInteger acntIndex = 0; acntIndex < acntCount; acntIndex++) {
        
        NSMutableIndexSet *conversations = [self _conversationsForAccount:acntIndex];
        
        [text appendFormat:@"\n\tAccount[%@] has %@ Conversations.",@(acntIndex),@([conversations count])];
        
        [conversations enumerateIndexesUsingBlock:^(NSUInteger idx, BOOL * _Nonnull stop) {
            
            // NB: Need an actual user/account to get -[account getConservationByIndex:]
            
            [text appendFormat:@"\n\t\thas (conversation Index) %@",
             @(idx)];
            
        }];
    }
    [text appendString:@"\n\n"];
    
    return text;
}



@end
