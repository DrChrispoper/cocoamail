//
//  CCMStatus.h
//  CocoaMail
//
//  Created by Christopher Hockley on 01/08/14.
//  Copyright (c) 2014 Christopher Hockley. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface CCMStatus : NSObject

@property (copy, nonatomic) NSString *status;

+ (void)showStatus:(NSString *)status;
+ (void)dismiss;
+ (void)dismissAfter:(NSTimeInterval)interval;
+ (void)dismissAfter:(NSTimeInterval)interval thenStatus:(NSString *)status;

@end
