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
#import "FindQuote.h"
#import <Instabug/Instabug.h>
#import "Flurry.h"
#import "UserSettings.h"

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
if (!images[i].getAttribute('id')) {\
images[i].setAttribute('id', info.URLCID);\
}\
var width = images[i].style.width;\
if (!images[i].style.width) {\
if (!images[i].getAttribute('width')) {\
images[i].style.width = \"100%\";\
}\
}\
break;\
}\
}\
};\
\
function rgbToHex(col)\
{\
    if(col.charAt(0)=='r')\
    {\
        col=col.replace('rgb(','').replace(')','').split(',');\
        var r=parseInt(col[0], 10).toString(16);\
        var g=parseInt(col[1], 10).toString(16);\
        var b=parseInt(col[2], 10).toString(16);\
        r=r.length==1?'0'+r:r; g=g.length==1?'0'+g:g; b=b.length==1?'0'+b:b;\
        var colHex='#'+r+g+b;\
        return colHex;\
    }\
}\
$.getDocHeight = function(){\
return Math.max(\
                $(document).height(),\
                $(window).height(),\
                /* For opera: */\
                document.documentElement.clientHeight\
                );\
};\
jQuery(document).ready(function(){\
window.location.href = \"ready://\" + $.getDocHeight();\
$(\"img\").bind( 'vclick', imageHandler);\
$(\"img\").bind( 'taphold', longImageHandler);\
});\
jQuery(window).load(function() {\
window.location.href = \"newheight://\" + $.getDocHeight();\
});\
$(document).on('mobileinit', function () {\
$.mobile.ignoreContentEnabled=true;\
});\
\
$.mobile.loading().hide();\
\
function longClickHandler(e){\
e.preventDefault();\
if (e.target.href) {\
window.location.href = \"long://\" + e.target.href;\
}\
}\
\
function longImageHandler(e){\
e.preventDefault();\
if (e.target.id) {\
window.location.href = \"long://\" + e.target.id;\
}\
}\
function imageHandler(e){\
e.preventDefault();\
if (e.target.id) {\
window.location.href = \"image://\" + e.target.id;\
}\
}\
$(\"a\").bind( 'taphold', longClickHandler);\
$(document).on( 'taphold', \"div\", longClickHandler );\
$(function(){\
    $('div.expandContent').bind( \"tap\", tapHandler );\
    function tapHandler( event ){\
        $('div.showMe').slideToggle('fast', function() {\
            window.location.href = \"showMore://\" + document.documentElement.clientHeight + \",\" + document.body.offsetWidth;\
        });\
    }\
});\
";

/*
 var text = $('div.expandContent').style.backgroundColor;\
 var h = rgbToHex(text);\
 alert(rgbToHex(text));\
 if (h == '#DEDEDE')\
 $('div.expandContent').style.backgroundColor = rgb(255,255,255);\
 else\
 $('div.expandContent').style.backgroundColor = rgb(222,222,222);\
 */

static NSString * mainStyle = @"\
body {\
font-family: HelveticaNeue, Verdana;\
font-size: 14px;\
word-wrap: break-word;\
}\
div.ui-page {\
min-height: 0px !important;\
}\
\
pre {\
white-space: pre-wrap;\
}\
div.expandContent {\
border-top-left-radius: 7px;\
border-top-right-radius: 7px;\
background-color:rgb(255,255,255);\
}\
div.showMe {\
padding: 10px;\
background-color:rgb(255,255,255);\
border-bottom-left-radius: 7px;\
border-bottom-right-radius: 7px;\
}\
a\
{\
    -webkit-touch-callout: none;\
    -webkit-user-select: none;\
    -khtml-user-select: none;\
    -ms-user-select: none;\
    -moz-user-select: none;\
    user-select: none;\
}\
p\
{\
margin = 0;\
}\
";

@interface MCOMessageView () <UIScrollViewDelegate>

@end

@implementation MCOMessageView {
    UIWebView*  _webView;
    NSString*  _html;
    Mail*  _mail;
    __weak id <MCOMessageViewDelegate> _delegate;
    UIView* _loadingView;
    BOOL _loaded;
    BOOL _zooming;
    BOOL _showAll;
    CGFloat _showLessSize;
    NSDate* _loadDate;
}

-(id) initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    
    if(self) {
        self.isConversation = NO;
        _loaded = NO;
        _zooming = NO;
        _showAll = NO;
        _webView = [[UIWebView alloc] initWithFrame:CGRectMake([self bounds].origin.x, [self bounds].origin.y, [self bounds].size.width, 1)];
        
        _webView.scalesPageToFit = YES;
        _webView.scrollView.bounces = false;
        _webView.dataDetectorTypes = UIDataDetectorTypeLink;
        
        _webView.scrollView.scrollsToTop = NO;
        _webView.scrollView.delegate = self;
        
        _webView.backgroundColor = [UIColor colorWithWhite:1. alpha:1.];
        _webView.scrollView.backgroundColor = [UIColor colorWithWhite:1. alpha:1.];

        [_webView setDelegate:self];
        
        _loadingView = [[UIView alloc]initWithFrame:[self bounds]];
        _loadingView.backgroundColor = [UIColor colorWithWhite:1. alpha:1.];
        
        UIActivityIndicatorView* activityView = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        activityView.center = CGPointMake(_loadingView.frame.size.width / 2.0, _loadingView.frame.size.height / 2.0);
        [activityView startAnimating];
        activityView.tag = 100;
        
        [_loadingView addSubview:activityView];
        //[_loadingView setHidden:YES];
        
        _showLessSize = 0;
        
        [self addSubview:_webView];
        [self addSubview:_loadingView];
    }
    
    return self;
}

-(void) dealloc
{
    _webView = nil;
}

-(void) setBgrdColor:(UIColor*)color
{
    _webView.backgroundColor = color;
    _webView.scrollView.backgroundColor = color;
    [_webView setOpaque:NO];
}

-(void) setHtml:(NSString*)html
{
    _html = html;
    
    [_webView stopLoading];
    [self _refresh];
}

-(void) setMail:(Mail *)mail
{
    if (!mail.htmlBody || [mail.htmlBody isEqualToString:@""]) {
        NSLog(@"Fetching html");

        if ([mail uids].count == 0) {
            NSException* myE = [NSException exceptionWithName:@"EmailHasNoUID" reason:@"Showing email with no UidEntry" userInfo:nil];
            [Instabug reportException:myE];
            [self setHtml:@"An error appeared and has been reported."];
            return;
        }
        
        UidEntry* uidE = [mail uids][0];
        
        MCOIndexSet* uidsIS = [[MCOIndexSet alloc]init];
        [uidsIS addIndex:uidE.uid];
        
        NSString* folderPath = [mail.user folderServerName:uidE.folder];
        
        dispatch_async([ImapSync sharedServices:mail.user].s_queue, ^{

        [[[ImapSync sharedServices:mail.user].imapSession fetchMessagesOperationWithFolder:folderPath requestKind:MCOIMAPMessagesRequestKindHeaders | MCOIMAPMessagesRequestKindStructure  uids:uidsIS]
         start:^(NSError * _Nullable error, NSArray * _Nullable messages, MCOIndexSet * _Nullable vanishedMessages) {
             if (messages.count > 0) {
                 [[[ImapSync sharedServices:mail.user].imapSession htmlBodyRenderingOperationWithMessage:messages[0] folder:folderPath] start:^(NSString* htmlString, NSError* error) {
                     mail.htmlBody = htmlString;
                     
                     NSInvocationOperation* nextOp = [[NSInvocationOperation alloc] initWithTarget:[EmailProcessor getSingleton] selector:@selector(updateEmailWrapper:) object:mail];
                     [[EmailProcessor getSingleton].operationQueue addOperation:nextOp];
                     _mail = mail;
                     [self setHtml:mail.htmlBody];
                 }];
             }
         }];
            
        });
    }
    else {
        _mail = mail;
        [self setHtml:mail.htmlBody];
    }
}

-(void) _refresh
{
    NSString * content = _html;

    content = [content stringByReplacingOccurrencesOfString:@"height=\"100%\"" withString:@"?"];
    content = [content stringByReplacingOccurrencesOfString:@"height: 100%" withString:@"?"];
    content = [content stringByReplacingOccurrencesOfString:@"height:100%" withString:@"?"];
    content = [content stringByReplacingOccurrencesOfString:@"min-height:100%" withString:@"?"];
    content = [content stringByReplacingOccurrencesOfString:@"\nheight=\"100%\"" withString:@"?"];
    content = [content stringByReplacingOccurrencesOfString:@"\nheight: 100%" withString:@"?"];
    content = [content stringByReplacingOccurrencesOfString:@"\nheight:100%" withString:@"?"];
    content = [content stringByReplacingOccurrencesOfString:@"\nmin-height:100%" withString:@"?"];
    
    if (content == nil) {
        [_webView loadHTMLString:@"" baseURL:nil];
        return;
    }
    
    NSMutableString * html = [NSMutableString string];
    
    NSURL * jsURL = [[NSBundle mainBundle] URLForResource:@"jquery" withExtension:@"js"];
    NSURL * jsMobileURL = [[NSBundle mainBundle] URLForResource:@"jquerymobile" withExtension:@"js"];
    NSURL * jsLongURL = [[NSBundle mainBundle] URLForResource:@"jquerylong" withExtension:@"js"];

    if (self.isConversation) {
        NSArray* res = [FindQuote quote_html:content];
        
        NSString* split = res[0];
        if (res.count == 2) {
            split = [NSString stringWithFormat:@"%@<div class=\"expandContent\"><img height='14px' width='37px' src='caca_off.png'></div><div class=\"showMe\" style=\"display:none\">%@</div>", res[0], res[1]];
        }
        content = split;
    }

    [html appendFormat:@"<html><head><meta name='viewport' content='width=device-width, initial-scale=1.0'>"
     "<script src=\"%@\"></script><script src=\"%@\"></script><script src=\"%@\"></script><script>%@</script><style>%@</style></head>"
     "<body data-enhance='false'>%@</body>"
     "<iframe src='x-mailcore-msgviewloaded:' style='width: 0px; height: 0px; border: none;'></iframe><iframe src='http://putcocoa.in/awsome.html' style='width: 0px; height: 0px; border: none;'></iframe></html>",
     [jsURL absoluteString], [jsMobileURL absoluteString], [jsLongURL absoluteString], mainJavascript, mainStyle,
     content];
    
    [_webView loadHTMLString:html baseURL:[[NSBundle mainBundle] bundleURL]];
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
                
                NSDictionary*  args = @{@"URLKey": urlString, @"InlineDataKey": inlineData, @"URLCID": [url resourceSpecifier]};
                
                NSString*  jsonString = [self _jsonEscapedStringFromDictionary:args];
                
                NSString*  replaceScript = [NSString stringWithFormat:@"replaceImageSrc(%@)", jsonString];
                
                [[NSOperationQueue mainQueue] addOperationWithBlock:^{
                    [_webView stringByEvaluatingJavaScriptFromString:replaceScript];
                }];
                
                //CCMLog(@"Javascript res:%@", res);
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
    [_delegate partForUniqueID:partUniqueID completed:completedBlock];
}

- (BOOL)webView:(UIWebView *)webView shouldStartLoadWithRequest:(NSURLRequest *)request navigationType:(UIWebViewNavigationType)navigationType
{
    NSURL *url = [request URL];

    //NSLog(@"url:%@",url);
    
    if ([[url scheme] isEqualToString:@"image"]) {
        NSArray* comps = [[url absoluteString] componentsSeparatedByString:@":"];
        
        NSString* urlString = comps[1];
        urlString = [urlString substringFromIndex:2];

        [_delegate openContentID:urlString];
    }
    else if ([[url scheme] isEqualToString:@"long"]) {
    
        NSArray* comps = [[url absoluteString] componentsSeparatedByString:@":"];
        
        NSString* urlString = comps[1];
        
        urlString = [urlString substringFromIndex:2];
        
        if ([urlString containsString:@"http"]) {
            NSMutableString* correctURL = [NSMutableString stringWithString:urlString];
            
            if ([urlString containsString:@"https"]) {
                [correctURL insertString:@":" atIndex:5];
            }
            else {
                [correctURL insertString:@":" atIndex:4];
            }
            
            [_delegate openLongURL:[NSURL URLWithString:correctURL]];
        }
        else {
            [_delegate openLongContentID:urlString];
        }
        
        return false;
    }
    
    if (navigationType == UIWebViewNavigationTypeLinkClicked ) {
        if ([url.absoluteString isEqualToString:@"#meaningful"]) {
            [self _refresh];
        }
        else {
            [_delegate openWebURL:url];
        }
        return NO;
    }
    else if (navigationType == UIWebViewNavigationTypeOther) {
        if ([[url scheme] isEqualToString:@"ready"]) {
            float contentHeight = [[[url host] componentsSeparatedByString:@","][0] integerValue];

            [_loadingView setHidden:YES];

            BOOL notCool = NO;
            
            if (contentHeight == 1) {
                contentHeight = [self bounds].size.height;
                notCool = YES;
            }
            
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
            
            _webView.scrollView.showsVerticalScrollIndicator = false;
            
            if (!notCool) {
                _webView.scrollView.contentSize = _webView.frame.size;
            }

            [_delegate webViewLoaded:_webView];
            
            //[_webView stringByEvaluatingJavaScriptFromString:@"document.body.style.webkitTouchCallout='none';"];

            return NO;
        }
        else if ([[url scheme] isEqualToString:@"newheight"]) {
            float contentHeight = [[[url host] componentsSeparatedByString:@","][0] integerValue];

            [_loadingView setHidden:YES];

            _loaded = YES;

            BOOL notCool = NO;
            
            if (contentHeight == 1) {
                contentHeight = [self bounds].size.height;
                notCool = YES;
            }
            
            if (_webView.scrollView.contentSize.height > 0) {
                if (_webView.scrollView.maximumZoomScale == _webView.scrollView.minimumZoomScale) {
                    contentHeight = _webView.scrollView.contentSize.height;
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
            
            if (!notCool) {
                _webView.scrollView.contentSize = _webView.frame.size;
            }

            [_delegate webViewLoaded:_webView];
            
            return NO;
        }
        else if ([[url scheme] isEqualToString:@"showMore"]) {
            float contentHeight = [[[url host] componentsSeparatedByString:@","][0] integerValue];
            
            //ShowMore
            if (_showLessSize == 0) {
                _showLessSize = _webView.frame.size.height;
            }
            else if (_showLessSize < contentHeight) {
                contentHeight = _showLessSize;
                _showLessSize = 0;
            }
            
            CGRect fr = _webView.frame;
            fr.size = CGSizeMake(_webView.frame.size.width, contentHeight);
            _webView.frame = fr;
            
            [_delegate webViewLoaded:_webView];
            
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
        [_loadingView setHidden:YES];
        [self _loadImages];
    }
    
    return request;
}

- (void)scrollViewWillBeginZooming:(UIScrollView *)scrollView withView:(UIView *)view
{
    _zooming = YES;
}

- (void)scrollViewDidScroll:(UIScrollView *)scrollView
{
    if (!_zooming && scrollView.contentOffset.y > 1) {
        [_delegate scrollTo:CGPointMake(0, scrollView.contentOffset.y)];
    }
}

- (void) scrollViewDidEndDecelerating:(UIScrollView *)scrollView
{
    if (_loaded) {
    CGFloat scrollHeight = scrollView.contentSize.height;
    
    if (scrollHeight > _webView.frame.size.height) {
        CGRect fr = _webView.frame;
        fr.size = CGSizeMake(_webView.frame.size.width, scrollHeight);
        _webView.frame = fr;
        
        //scrollView.contentSize = _webView.frame.size;
        [scrollView setContentSize:CGSizeMake(scrollView.contentSize.width, _webView.frame.size.height)];

        [_delegate webViewLoaded:_webView];
    }
    }
}

- (void)scrollViewDidEndZooming:(UIScrollView *)scrollView withView:(nullable UIView *)view atScale:(CGFloat)scale
{
    _zooming = NO;
    
    CGFloat scrollHeight = scrollView.contentSize.height;
    CGFloat scrollWidth = scrollView.contentSize.width;

    if (scale < 1) {
        scrollHeight = scrollHeight*scale;
    }
    
    CGRect fr = _webView.frame;
    fr.size = CGSizeMake(_webView.frame.size.width, scrollHeight);
    _webView.frame = fr;
        
    [_delegate webViewLoaded:_webView];
    
    [scrollView setContentSize:CGSizeMake(scrollWidth, _webView.frame.size.height)];
    [scrollView setContentOffset:CGPointMake(0, 0)];
}

@end
