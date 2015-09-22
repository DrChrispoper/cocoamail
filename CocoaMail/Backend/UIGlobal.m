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
    return [UIColor colorWithWhite:0.8 alpha:1.0];
}

+(UIColor*) standardLightGrey
{
    return [UIColor colorWithWhite:0.92 alpha:1.0];
}

+(UIColor*) noImageBadgeColor
{
    return [UIColor colorWithWhite:120./255. alpha:1.0];
}

+(UIColor*) standardTableLineColor
{
    return [UIColor colorWithRed:200./255. green:199./255. blue:204./255. alpha:1.];
}

+(UIColor*) standardBlue
{
    return [UIColor colorWithRed:0. green:0.46 blue:1. alpha:1.];
}

@end