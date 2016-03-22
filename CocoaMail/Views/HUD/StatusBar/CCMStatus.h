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

+ (void)showStatus:(NSString *)status dismissAfter:(NSTimeInterval)interval code:(NSInteger)code;
+ (void)dismiss;

@end
