//
//  InViewController+UIViewControllerPreviewing.m
//  CocoaMail
//
//  Created by Christopher Hockley on 16/01/16.
//  Copyright © 2016 Christopher Hockley. All rights reserved.
//

#import "MailListViewController+UIViewControllerPreviewing.h"
#import "PreviewViewController.h"

@implementation MailListViewController (UIViewControllerPreviewingDelegate)

- (void)check3DTouch
{
    if ([self isForceTouchAvailable]) {
        self.previewingContext =
        [self registerForPreviewingWithDelegate:(id)self
                                     sourceView:self.view];
    }
}

- (UIViewController *)previewingContext:(id<UIViewControllerPreviewing>)previewingContext viewControllerForLocation:(CGPoint)location
{
    // check if we're not already displaying a preview controller (WebViewController is my preview controller)
    if ([self.presentedViewController isKindOfClass:[PreviewViewController class]]) {
        return nil;
    }
    
    CGFloat offset = self.table.contentInset.top;
    
    location.y = location.y - offset;
    
    NSIndexPath *path = [self.table indexPathForRowAtPoint:location];
    
    if (path) {
        
        UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Main" bundle:nil];
        PreviewViewController *previewController = [storyboard instantiateViewControllerWithIdentifier:@"PreviewView"];
        
        NSArray* list = self.convByDay[path.section][@"list"];
        Conversation* conv = [[Accounts sharedInstance] conversationForCI:[list objectAtIndex:path.row]];

        previewController.conversation = conv;
        previewController.table = self.table;
        previewController.indexPath = path;
        
        UITableViewCell* cell = [self.table cellForRowAtIndexPath:path];
        //CGRect rect = [self.table rectForRowAtIndexPath:path];
        CGRect frame = cell.frame;
        
        //frame.origin.y = frame.origin.y - offset;
        
        previewingContext.sourceRect = frame;
    
        return  previewController;
    }

    return nil;
}

- (void)previewingContext:(id )previewingContext commitViewController: (UIViewController *)viewControllerToCommit
{
    [[NSNotificationCenter defaultCenter] postNotificationName:kPRESENT_CONVERSATION_NOTIFICATION
                                                        object:nil
                                                      userInfo:@{kPRESENT_CONVERSATION_KEY:((PreviewViewController*)viewControllerToCommit).conversation}];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection
{
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self isForceTouchAvailable]) {
        if (!self.previewingContext) {
            self.previewingContext =
            [self registerForPreviewingWithDelegate:(id)self
                                         sourceView:self.view];
        }
    } else {
        if (self.previewingContext) {
            [self unregisterForPreviewingWithContext:self.previewingContext];
            self.previewingContext = nil;
        }
    }
}

- (BOOL)isForceTouchAvailable {
    BOOL isForceTouchAvailable = NO;
    if ([self.traitCollection respondsToSelector:
         @selector(forceTouchCapability)]) {
        isForceTouchAvailable = self.traitCollection
        .forceTouchCapability == UIForceTouchCapabilityAvailable;
    }
    return isForceTouchAvailable;
}

@end
