//
//  AttachmentsViewController.h
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 17/08/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "ViewController.h"

@class Conversation;

@interface AttachmentsViewController : InViewController

@property (nonatomic, strong) Conversation* conversation;

-(void)reloadWithConversation:(Conversation*)conversation;

@end
