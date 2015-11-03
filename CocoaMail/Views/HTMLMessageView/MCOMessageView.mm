//
//  MCOMessageView.m
//
//  Created by DINH Viêt Hoà on 1/19/13.
//  Copyright (c) 2013 MailCore. All rights reserved.
//

#import "MCOMessageView.h"

@interface MCOMessageView () <MCOHTMLRendererIMAPDelegate>

@end

@implementation MCOMessageView {
    UIWebView*  _webView;
    NSString*  _html;
    __weak id <MCOMessageViewDelegate> _delegate;
    UIView* _loadingView;
}

@synthesize delegate = _delegate;

-(id) initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    
    if(self) {
        _webView = [[UIWebView alloc] initWithFrame:[self bounds]];
        //[_webView setAutoresizingMask:(UIViewAutoresizingFlexibleHeight)];
        _webView.scalesPageToFit = NO;
        _webView.scrollView.bounces = false;
        _webView.dataDetectorTypes = UIDataDetectorTypeLink;

        _webView.scrollView.scrollsToTop = NO;
        
        [_webView setDelegate:self];
    
        _loadingView = [[UIView alloc]initWithFrame:[self bounds]];
        _loadingView.backgroundColor = [UIColor colorWithWhite:1. alpha:1.];
        
        UIActivityIndicatorView* activityView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        activityView.center = CGPointMake(_loadingView.frame.size.width / 2.0, _loadingView.frame.size.height / 2.0);
        [activityView startAnimating];
        activityView.tag = 100;
        
        [_loadingView addSubview:activityView];
        
        [self addSubview:_webView];
        [self addSubview:_loadingView];
    }
    
    return self;
}

-(void) dealloc
{
    _webView = nil;
}

-(void) setHtml:(NSString*)html
{
    _html = html;
    
    [_webView stopLoading];
    [self _refresh];
}

-(void) _refresh
{
    NSString * content = _html;
    
    content = [content stringByReplacingOccurrencesOfString:@" height=\"100%\"" withString:@"?"];
    content = [content stringByReplacingOccurrencesOfString:@" height: 100%" withString:@"?"];
    content = [content stringByReplacingOccurrencesOfString:@" min-height:100%" withString:@"?"];
    content = [content stringByReplacingOccurrencesOfString:@"\nheight=\"100%\"" withString:@"?"];
    content = [content stringByReplacingOccurrencesOfString:@"\nheight: 100%" withString:@"?"];
    content = [content stringByReplacingOccurrencesOfString:@"\nmin-height:100%" withString:@"?"];
    
    if (content == nil) {
        [_webView loadHTMLString:@"" baseURL:nil];
        return;
    }
    NSMutableString * html = [NSMutableString string];
    NSURL * jsURL = [[NSBundle mainBundle] URLForResource:@"MCOMessageViewScript" withExtension:@"js"];
    
    
    NSString* quoteStyle = @"<style> blockquote { margin:0 } body { font-family: HelveticaNeue, Verdana; )</style>";
    
    CCMLog(@"Proccess");
    
    BOOL haveStyle = ([content rangeOfString:@"<style"].location != NSNotFound);
    BOOL haveQuote = ([content rangeOfString:@"<blockquote"].location != NSNotFound);
    BOOL haveMeta = ([content rangeOfString:@"<meta"].location != NSNotFound);
    BOOL haveTable = ([content rangeOfString:@"<table"].location != NSNotFound);

    if (haveQuote) {
        _webView.scalesPageToFit = NO;
    }
    else {
        _webView.scalesPageToFit = (haveMeta || haveStyle || haveTable);
    }
    
    CCMLog(@"Proccessed");

    [html appendFormat:@"<html><head><meta name='viewport' content='width=device-width, initial-scale=1.0'><script src=\"%@\"></script>%@</head><body>%@</body><iframe src='x-mailcore-msgviewloaded:' style='width: 0px; height: 0px; border: none;'></iframe></html>", [jsURL absoluteString],quoteStyle, content];
    
    NSData *data = [html dataUsingEncoding:NSUTF8StringEncoding];
    [_webView loadData:data MIMEType:@"text/html" textEncodingName:@"utf-8" baseURL:[NSURL URLWithString:@""]];
    
    //[_webView loadHTMLString:html baseURL:nil];
}

-(BOOL) _isCID:(NSURL*)url
{
	NSString* theScheme = [url scheme];
	if ([theScheme caseInsensitiveCompare:@"cid"] == NSOrderedSame)
        return YES;
    return NO;
}

-(void) _loadImages
{
    CCMLog(@"Load images");
	NSString* result = [_webView stringByEvaluatingJavaScriptFromString:@"findCIDImageURL()"];
	NSData* data = [result dataUsingEncoding:NSUTF8StringEncoding];

    NSArray* imagesURLStrings = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
	
	for(NSString* urlString in imagesURLStrings) {
		MCOAttachment*  part = nil;
		NSURL*  url;
		
		url = [NSURL URLWithString:urlString];
        
		if ([self _isCID:url]) {
            CCMLog(@"url is cidurl:%@", url);
			part = [self partForContentID:[url resourceSpecifier]];
		}
		
		if (part == nil)
			continue;
        
        NSString* inlineData = [NSString stringWithFormat:@"data:image/jpg;base64,%@",[part.data base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength]];
        
        NSDictionary*  args = @{@"URLKey": urlString, @"InlineDataKey": inlineData };
        
        NSString*  jsonString = [self _jsonEscapedStringFromDictionary:args];
        
        NSString*  replaceScript = [NSString stringWithFormat:@"replaceImageSrc(%@)", jsonString];
        [_webView stringByEvaluatingJavaScriptFromString:replaceScript];
	}
    CCMLog(@"Loaded images");

}

-(NSString*) _jsonEscapedStringFromDictionary:(NSDictionary*)dictionary
{
	NSData*  json = [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:nil];
	NSString*  jsonString = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
	return jsonString;
}

-(MCOAttachment*)partForContentID:(NSString*)partUniqueID{
    return [self.delegate partForUniqueID:partUniqueID];
}

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType {
    
    if (navigationType == UIWebViewNavigationTypeLinkClicked ) {
        [[UIApplication sharedApplication] openURL:[request URL]];
        return NO;
    }
    else if (navigationType == UIWebViewNavigationTypeOther) {
        NSURL *url = [request URL];
        if ([[url scheme] isEqualToString:@"ready"]) {
            float contentHeight = [[[url host] componentsSeparatedByString:@","][0] integerValue];
            
            if (_webView.scrollView.maximumZoomScale == _webView.scrollView.minimumZoomScale) {
                if (contentHeight < _webView.scrollView.contentSize.height) {
                    contentHeight = _webView.scrollView.contentSize.height;
                }
            }
            else {
                if (contentHeight > _webView.scrollView.contentSize.height) {
                    contentHeight = _webView.scrollView.contentSize.height;
                }
            }
            
            CGRect fr = _webView.frame;
            fr.size = CGSizeMake(_webView.frame.size.width, contentHeight);
            _webView.frame = fr;
            
            [_loadingView setHidden:YES];
            [self.delegate webViewLoaded:_webView];
            return NO;
        }
    }
    
    NSURLRequest *responseRequest = [self webView:webView resource:nil willSendRequest:request redirectResponse:nil fromDataSource:nil];
    if(responseRequest == request) {
        return YES;
    } else {
        [webView loadRequest:responseRequest];
        return NO;
    }
    return YES;
}

-(NSURLRequest*)webView:(UIWebView*)sender resource:(id)identifier willSendRequest:(NSURLRequest*)request redirectResponse:(NSURLResponse*)redirectResponse fromDataSource:(id)dataSource
{
    if ([[[request URL] scheme] isEqualToString:@"x-mailcore-msgviewloaded"]) {
        [self _loadImages];
    }
	
	return request;
}


/*-(void)webViewDidFinishLoad:(UIWebView*)webView {
    CGSize contentSize = webView.scrollView.contentSize;
    CGSize viewSize = webView.bounds.size;
    
    float rw = viewSize.width / contentSize.width;
    
    webView.scrollView.minimumZoomScale = rw;
    webView.scrollView.maximumZoomScale = rw;
    webView.scrollView.zoomScale = rw;
    
    //_webView.frame = CGRectMake(0, 0, webView.frame.size.width, webView.scrollView.contentSize.height);
}*/

@end
