//
//  MCOMessageView.m
//
//  Created by DINH Viêt Hoà on 1/19/13.
//  Copyright (c) 2013 MailCore. All rights reserved.
//

#import "MCOMessageView.h"
#import "Mail.h"
#import "AppSettings.h"
#import "ImapSync.h"
#import "EmailProcessor.h"

@interface MCOMessageView () <MCOHTMLRendererIMAPDelegate, UIScrollViewDelegate>

@end

@implementation MCOMessageView {
    UIWebView*  _webView;
    NSString*  _html;
    __weak id <MCOMessageViewDelegate> _delegate;
    UIView* _loadingView;
    BOOL _hasResized;
}

@synthesize delegate = _delegate;

-(id) initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    
    if(self) {
        _hasResized = NO;
        _webView = [[UIWebView alloc] initWithFrame:[self bounds]];
        _webView.scalesPageToFit = NO;
        _webView.scrollView.bounces = false;
        _webView.dataDetectorTypes = UIDataDetectorTypeLink;

        _webView.scrollView.scrollsToTop = NO;
        _webView.scrollView.delegate = self;
        
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

-(void) setMail:(Mail *)mail
{
    if (!mail.email.htmlBody || [mail.email.htmlBody isEqualToString:@""]) {
        
        UidEntry* uidE = [mail.email getUids][0];
        MCOIndexSet* uidsIS = [[MCOIndexSet alloc]init];
        [uidsIS addIndex:uidE.uid];
        
        NSInteger accountIdx = [AppSettings indexForAccount:mail.email.accountNum];
        
        NSString* folderPath = [AppSettings folderServerName:uidE.folder forAccountIndex:accountIdx];
        
        [[[ImapSync sharedServices].imapSession fetchMessagesOperationWithFolder:folderPath requestKind:MCOIMAPMessagesRequestKindHeaders uids:uidsIS]
         start:^(NSError * _Nullable error, NSArray * _Nullable messages, MCOIndexSet * _Nullable vanishedMessages) {
             if (messages.count > 0) {
                 [[[ImapSync sharedServices:accountIdx].imapSession htmlBodyRenderingOperationWithMessage:messages[0] folder:folderPath] start:^(NSString* htmlString, NSError* error) {
                     mail.email.htmlBody = htmlString;
                     
                     NSInvocationOperation* nextOp = [[NSInvocationOperation alloc] initWithTarget:[EmailProcessor getSingleton] selector:@selector(updateEmailWrapper:) object:mail.email];
                     [[EmailProcessor getSingleton].operationQueue addOperation:nextOp];
                     
                    [self setHtml:mail.email.htmlBody];
                 }];
             }
         }];
    }
    else {
        [self setHtml:mail.email.htmlBody];
    }
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
}

-(NSString*) _jsonEscapedStringFromDictionary:(NSDictionary*)dictionary
{
	NSData*  json = [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:nil];
	NSString*  jsonString = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
	return jsonString;
}

-(MCOAttachment*)partForContentID:(NSString*)partUniqueID
{
    return [self.delegate partForUniqueID:partUniqueID];
}

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{    
    if (navigationType == UIWebViewNavigationTypeLinkClicked ) {
        [self.delegate openWebURL:[request URL]];
        //[[UIApplication sharedApplication] openURL:[request URL]];
        return NO;
    }
    else if (navigationType == UIWebViewNavigationTypeOther) {
        NSURL *url = [request URL];
        if ([[url scheme] isEqualToString:@"ready"]) {
            float contentHeight = [[[url host] componentsSeparatedByString:@","][0] integerValue];

            if (_webView.scrollView.maximumZoomScale == _webView.scrollView.minimumZoomScale) {
                //if (contentHeight < _webView.scrollView.contentSize.height) {
                    contentHeight = _webView.scrollView.contentSize.height;
                //}
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

            [_webView.scrollView scrollRectToVisible:CGRectMake(1,_webView.scrollView.contentSize.height - 1, 1, 1) animated:YES];

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

- (void) scrollViewDidEndDragging:(UIScrollView *)scrollView willDecelerate:(BOOL)decelerate
{
    //CGFloat docHeight = [[_webView stringByEvaluatingJavaScriptFromString:@"document.height"] floatValue];
    CGFloat scrollHeight = scrollView.contentSize.height;
    
    if (!_hasResized && scrollHeight > _webView.frame.size.height) {
        CGRect fr = _webView.frame;
        fr.size = CGSizeMake(_webView.frame.size.width, scrollHeight);
        _webView.frame = fr;
        
        [self.delegate webViewLoaded:_webView];
        _hasResized = YES;
    }
}

- (void)scrollViewDidEndZooming:(UIScrollView *)scrollView withView:(nullable UIView *)view atScale:(CGFloat)scale
{
    //CGFloat height = [[_webView stringByEvaluatingJavaScriptFromString:@"document.height"] floatValue];
    CGFloat scrollHeight = scrollView.contentSize.height;

    if (scale < 1) {
        //CCMLog(@"Content Height:%f",scrollView.contentSize.height);
        CGRect fr = _webView.frame;
        fr.size = CGSizeMake(_webView.frame.size.width, scrollHeight * scale);
        _webView.frame = fr;
        
        [self.delegate webViewLoaded:_webView];
    }
    if (scale > 1) {
        _hasResized = NO;
    }
}

@end
