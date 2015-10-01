//
//  WKWebView+SynchronousEvaluateJavaScript.h
//  CocoaMail
//
//  Created by Christopher Hockley on 30/09/15.
//  Copyright © 2015 Christopher Hockley. All rights reserved.
//

#import <WebKit/WebKit.h>

@interface WKWebView (SynchronousEvaluateJavaScript)
- (NSString *)stringByEvaluatingJavaScriptFromString:(NSString *)script;
@end
