//
//  CCMDDLogFormatter.m
//  CocoaMail
//
//  Created by Andrew Cerier on 2/15/17.
//  Copyright © 2017 Christopher Hockley. All rights reserved.
//

#import "CCMDDLogFormatter.h"

// From DDLog.h:
//    @property (readonly, nonatomic) NSString *message;
//    @property (readonly, nonatomic) DDLogLevel level;
//    @property (readonly, nonatomic) DDLogFlag flag;
//    @property (readonly, nonatomic) NSInteger context;
//    @property (readonly, nonatomic) NSString *file;
//    @property (readonly, nonatomic) NSString *fileName;
//    @property (readonly, nonatomic) NSString *function;
//    @property (readonly, nonatomic) NSUInteger line;
//    @property (readonly, nonatomic) id tag;
//    @property (readonly, nonatomic) DDLogMessageOptions options;
//    @property (readonly, nonatomic) NSDate *timestamp;
//    @property (readonly, nonatomic) NSString *threadID; // ID as it appears in NSLog calculated from the machThreadID
//    @property (readonly, nonatomic) NSString *threadName;
//    @property (readonly, nonatomic) NSString *queueLabel;
//

@implementation CCMDDLogFormatter

- (NSString *)formatLogMessage:(DDLogMessage *)logMessage {
    NSString *logLevel;
    switch (logMessage.flag) {
        case DDLogFlagError    : logLevel = @"🆘"; break;
        case DDLogFlagWarning  : logLevel = @"⚠️"; break;
        case DDLogFlagInfo     : logLevel = @"I"; break;
        case DDLogFlagDebug    : logLevel = @"D"; break;
        default                : logLevel = @"V"; break;
    }
    
    return [NSString stringWithFormat:@"%@ T%@ %@ | %@", logLevel, logMessage.threadID, logMessage.function, logMessage.message];
}

@end
