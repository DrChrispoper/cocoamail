//
//  ConversationViewController.h
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 03/08/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "ViewController.h"
#import "CocoaButton.h"
#import "InViewController.h"

@class Conversation;

@interface ConversationViewController : InViewController <CocoaButtonDatasource>

@property (nonatomic, strong) Conversation* conversation;


@end
