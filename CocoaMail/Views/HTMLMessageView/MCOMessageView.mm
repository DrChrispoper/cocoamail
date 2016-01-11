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

static NSString * mainJavascript = @"\
var imageElements = function() {\
var imageNodes = document.getElementsByTagName('img');\
return [].slice.call(imageNodes);\
};\
\
var findCIDImageURL = function() {\
var images = imageElements();\
\
var imgLinks = [];\
for (var i = 0; i < images.length; i++) {\
var url = images[i].getAttribute('src');\
if (url.indexOf('cid:') == 0 || url.indexOf('x-mailcore-image:') == 0)\
imgLinks.push(url);\
}\
return JSON.stringify(imgLinks);\
};\
\
var replaceImageSrc = function(info) {\
var images = imageElements();\
\
for (var i = 0; i < images.length; i++) {\
var url = images[i].getAttribute('src');\
if (url.indexOf(info.URLKey) == 0) {\
images[i].setAttribute('src', info.InlineDataKey);\
break;\
}\
}\
};\
\
$(document).ready(function() {\
window.location.href = \"ready://\" + document.documentElement.clientHeight + \",\" + document.body.offsetWidth;\
});\
\
$.mobile.loading().hide();\
\
function longClickHandler(e){\
e.preventDefault();\
window.location.href = \"long://\" + e.target.href;\
}\
\
$(\"a\").bind( 'taphold', longClickHandler);\
$(document).on( 'taphold', \"div\", longClickHandler );\
";

static NSString * mainStyle = @"\
body {\
font-family: HelveticaNeue, Verdana;\
font-size: 14px;\
word-wrap: break-word;\
-webkit-text-size-adjust:none;\
-webkit-nbsp-mode: space;\
}\
\
pre {\
white-space: pre-wrap;\
}\
";

@interface MCOMessageView () <UIScrollViewDelegate>

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
        [_loadingView setHidden:YES];

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
        
        CCMLog(@"No html");
        [_loadingView setHidden:NO];

        UidEntry* uidE = [mail.email getUids][0];
        MCOIndexSet* uidsIS = [[MCOIndexSet alloc]init];
        [uidsIS addIndex:uidE.uid];
        
        NSInteger accountIdx = [AppSettings indexForAccount:mail.email.accountNum];
        
        NSString* folderPath = [AppSettings folderServerName:uidE.folder forAccountIndex:accountIdx];
        
        [[[ImapSync sharedServices:accountIdx].imapSession fetchMessagesOperationWithFolder:folderPath requestKind:MCOIMAPMessagesRequestKindHeaders | MCOIMAPMessagesRequestKindStructure  uids:uidsIS]
         start:^(NSError * _Nullable error, NSArray * _Nullable messages, MCOIndexSet * _Nullable vanishedMessages) {
             if (messages.count > 0) {
                 [[[ImapSync sharedServices:accountIdx].imapSession htmlBodyRenderingOperationWithMessage:messages[0] folder:folderPath] start:^(NSString* htmlString, NSError* error) {
                     mail.email.htmlBody = htmlString;
                     
                     NSInvocationOperation* nextOp = [[NSInvocationOperation alloc] initWithTarget:[EmailProcessor getSingleton] selector:@selector(updateEmailWrapper:) object:mail.email];
                     [[EmailProcessor getSingleton].operationQueue addOperation:nextOp];
                     [_loadingView setHidden:YES];
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
    
    NSURL * jsURL = [[NSBundle mainBundle] URLForResource:@"jquery" withExtension:@"js"];
    NSURL * jsMobileURL = [[NSBundle mainBundle] URLForResource:@"jquerymobile" withExtension:@"js"];
    NSURL * jsLongURL = [[NSBundle mainBundle] URLForResource:@"jquerylong" withExtension:@"js"];

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
    
    [html appendFormat:@"<html><head><meta name='viewport' content='width=device-width, initial-scale=1.0'><script src=\"%@\"></script><script src=\"%@\"></script><script src=\"%@\"></script><script>%@</script><style>%@</style></head>"
     @"<body>%@</body><iframe src='x-mailcore-msgviewloaded:' style='width: 0px; height: 0px; border: none;'>"
     @"</iframe></html>", [jsURL absoluteString], [jsMobileURL absoluteString], [jsLongURL absoluteString], mainJavascript, mainStyle, content];
    [_webView loadHTMLString:html baseURL:nil];
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
        NSURL*  url;
        
        url = [NSURL URLWithString:urlString];
        
        if ([self _isCID:url]) {
            CCMLog(@"url is cidurl:%@", url);
            [self partForContentID:[url resourceSpecifier] completed:^(NSData * data) {
                if (!data) {
                    return;
                }
                NSString* inlineData = [NSString stringWithFormat:@"data:image/jpg;base64,%@",[data base64EncodedStringWithOptions:NSDataBase64Encoding64CharacterLineLength]];
                
                NSDictionary*  args = @{@"URLKey": urlString, @"InlineDataKey": inlineData };
                
                NSString*  jsonString = [self _jsonEscapedStringFromDictionary:args];
                
                NSString*  replaceScript = [NSString stringWithFormat:@"replaceImageSrc(%@)", jsonString];
                NSString* res = [_webView stringByEvaluatingJavaScriptFromString:replaceScript];
                CCMLog(@"Javascript res:%@", res);
            }];
        }
    }
}

-(NSString*) _jsonEscapedStringFromDictionary:(NSDictionary*)dictionary
{
    NSData*  json = [NSJSONSerialization dataWithJSONObject:dictionary options:0 error:nil];
    NSString*  jsonString = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
    return jsonString;
}

-(void)partForContentID:(NSString*)partUniqueID completed:(void (^)(NSData * data))completedBlock
{
    [self.delegate partForUniqueID:partUniqueID completed:completedBlock];
}

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    NSURL *url = [request URL];

    if ([[url scheme] isEqualToString:@"long"]) {
    
        NSArray* comps = [[url absoluteString] componentsSeparatedByString:@":"];
        
        NSString* urlString = comps[1];
        
        urlString = [urlString substringFromIndex:2];
        
        [self.delegate openLongURL:[NSURL URLWithString:urlString]];
        
        return false;
    }
    
    if (navigationType == UIWebViewNavigationTypeLinkClicked ) {
        [self.delegate openWebURL:url];
        return NO;
    }
    else if (navigationType == UIWebViewNavigationTypeOther) {
        if ([[url scheme] isEqualToString:@"ready"]) {
            float contentHeight = [[[url host] componentsSeparatedByString:@","][0] integerValue];
            
            if (_webView.scrollView.contentSize.height > 0) {
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
            }
            
            CGRect fr = _webView.frame;
            fr.size = CGSizeMake(_webView.frame.size.width, contentHeight);
            _webView.frame = fr;
            
            [self.delegate webViewLoaded:_webView];
            
            [_webView stringByEvaluatingJavaScriptFromString:@"document.body.style.webkitTouchCallout='none';"];

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
    CGFloat scrollHeight = scrollView.contentSize.height;
    
    if (scale < 1) {
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
