//
//  GlobalDBFunctions.h
//  CocoaMail
//
//  Created by Christopher Hockley on 20/01/2012.
//  Copyright (c) 2012 Christopher Hockley. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface GlobalDBFunctions : NSObject

+(NSString*) dbFileNameForNum:(NSInteger)dbNum;
+(void) deleteAll;
+(void) tableCheck;


@end
