//
//  UIView+RenderViewToImage.m
//  CocoaMail
//
//  Created by Christopher Hockley on 26/01/16.
//  Copyright © 2016 Christopher Hockley. All rights reserved.
//

#import "UIView+RenderViewToImage.h"

@implementation UIView (RenderViewToImage)

- (UIImage *)imageByRenderingView
{
    UIGraphicsBeginImageContextWithOptions(self.bounds.size, NO, 0.0);
    [self drawViewHierarchyInRect:self.bounds afterScreenUpdates:YES];
    UIImage * snapshotImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return snapshotImage;
}

@end
