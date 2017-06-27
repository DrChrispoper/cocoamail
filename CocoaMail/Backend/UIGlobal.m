//
//  UIGlobal.m
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 24/07/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "UIGlobal.h"

@implementation UIGlobal

+(UIColor*) bubbleFolderGrey
{
    return [UIColor colorWithWhite:0.8f alpha:1.0f];
}

+(UIColor*) standardLightGrey
{
    return [UIColor colorWithWhite:0.92f alpha:1.0f];
}

+(UIColor*) noImageBadgeColor //Weird Crash if not.
{
    return [UIColor colorWithCIColor:[CIColor colorWithCGColor:[UIColor colorWithWhite:120.0f / 255.0f alpha:1.0f].CGColor]];
}

+(UIColor*) standardTableLineColor
{
    return [UIColor colorWithRed:200.0f / 255.0f green:199.0f / 255.0f blue:204.0f / 255.0f alpha:1.0f];
}

+(UIColor*) standardBlue
{
    return [UIColor colorWithRed:0.0f green:0.46f blue:1.0f alpha:1.0f];
}


@end
