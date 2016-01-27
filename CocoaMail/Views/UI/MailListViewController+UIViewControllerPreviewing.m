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
    // register for 3D Touch (if available)
    if (self.traitCollection.forceTouchCapability == UIForceTouchCapabilityAvailable) {
        self.previewingContext = [self registerForPreviewingWithDelegate:(id)self sourceView:self.table];
    }
}

- (void)Uncheck3DTouch
{
    [self unregisterForPreviewingWithContext:self.previewingContext];
}

- (UIViewController *)previewingContext:(id<UIViewControllerPreviewing>)previewingContext viewControllerForLocation:(CGPoint)location
{
    CCMLog(@"Preview");
    // check if we're not already displaying a preview controller (WebViewController is my preview controller)
    if ([self.presentedViewController isKindOfClass:[PreviewViewController class]]) {
        return nil;
    }
    
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
        
        previewingContext.sourceRect = cell.frame;
    
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
    [self check3DTouch];
}

@end
