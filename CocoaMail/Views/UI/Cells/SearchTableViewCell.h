//
//  SearchTableViewCell.h
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 06/09/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import <UIKit/UIKit.h>

@class Conversation;

@interface SearchTableViewCell : UITableViewCell

- (void)fillWithConversation:(Conversation*)conv subText:(NSString*)subtext highlightWord:(NSString*)word;

@end
