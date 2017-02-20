//
//  CCMDDLogFormatter.m
//  CocoaMail
//
//  Created by Andrew Cerier on 2/15/17.
//  Copyright © 2017 Christopher Hockley. All rights reserved.
//

#import "CCMDDLogFormatter.h"

@implementation CCMDDLogFormatter

- (NSString *)formatLogMessage:(DDLogMessage *)logMessage {
    NSString *logLevel;
    switch (logMessage->_flag) {
        case DDLogFlagError    : logLevel = @"🆘"; break;
        case DDLogFlagWarning  : logLevel = @"⚠️"; break;
        case DDLogFlagInfo     : logLevel = @"I"; break;
        case DDLogFlagDebug    : logLevel = @"D"; break;
        default                : logLevel = @"V"; break;
    }
    
    return [NSString stringWithFormat:@"%@ %@ %@ | %@", logLevel, logMessage->_threadID, logMessage->_function, logMessage->_message];
}

@end
