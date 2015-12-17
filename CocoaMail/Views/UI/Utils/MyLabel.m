//
//  MyLabel.m
//  CocoaMail
//
//  Created by Christopher Hockley on 14/12/15.
//  Copyright © 2015 Christopher Hockley. All rights reserved.
//

#import "MyLabel.h"

@implementation MyLabel

@synthesize isColorLocked;

- (void)setBackgroundColor:(UIColor *)backgroundColor {
    if (!isColorLocked) {
        super.backgroundColor = backgroundColor;
    }
}
@end