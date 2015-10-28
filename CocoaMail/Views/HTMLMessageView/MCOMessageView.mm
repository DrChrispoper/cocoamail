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
    NSString*  _folder;
    MCOAbstractMessage*  _message;
    NSString*  _html;
    __weak id <MCOMessageViewDelegate> _delegate;
    BOOL _prefetchIMAPImagesEnabled;
    BOOL _prefetchIMAPAttachmentsEnabled;
    UIView* _loadingView;
}

@synthesize folder = _folder;
@synthesize delegate = _delegate;
@synthesize prefetchIMAPImagesEnabled = _prefetchIMAPImagesEnabled;
@synthesize prefetchIMAPAttachmentsEnabled = _prefetchIMAPAttachmentsEnabled;

-(id) initWithFrame:(CGRect)frame
{
    self = [super initWithFrame:frame];
    
    if(self) {
        _webView = [[UIWebView alloc] initWithFrame:[self bounds]];
        //[_webView setAutoresizingMask:(UIViewAutoresizingFlexibleHeight)];
        _webView.scalesPageToFit = NO;
        _webView.scrollView.bounces = false;
        _webView.dataDetectorTypes = UIDataDetectorTypeLink;

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

-(id) initWithCoder:(NSCoder*)aDecoder
{
    self = [super initWithCoder:aDecoder];
    _webView = [[UIWebView alloc] initWithFrame:[self bounds]];
    //[_webView setAutoresizingMask:(UIViewAutoresizingFlexibleHeight)];
    _webView.scalesPageToFit = true;
    _webView.clipsToBounds = YES;
    _webView.scrollView.scrollEnabled = true;
    _webView.scrollView.bounces = false;
    [_webView setDelegate:self];
    [self addSubview:_webView];
    
    return self;
}


-(void) dealloc
{
    _message = nil;
    _folder = nil;
    _webView = nil;
}

-(void) setMessage:(MCOAbstractMessage*)message
{
    _message = message;
    
    [_webView stopLoading];
    [self _refresh];
}

-(void) setHtml:(NSString*)html
{
    _html = html;
    
    [_webView stopLoading];
    [self _refresh];
}

-(MCOAbstractMessage*) message
{
    return _message;
}

-(void) _refresh
{
    NSString*  content;
    
    /*if (_message == nil) {
        content = nil;
    }
    else {
        
        if ([_message isKindOfClass:[MCOIMAPMessage class]]) {
            content = [(MCOIMAPMessage* ) _message htmlRenderingWithFolder:_folder delegate:self];
        }
        else if ([_message isKindOfClass:[MCOMessageBuilder class]]) {
            content = [(MCOMessageBuilder* ) _message htmlRenderingWithDelegate:self];
        }
        else if ([_message isKindOfClass:[MCOMessageParser class]]) {
            content = [(MCOMessageParser* ) _message htmlRenderingWithDelegate:self];
        }
        else {
            content = nil;
            MCAssert(0);
        }*/
        content = _html;
   // }
	if (content == nil) {
		[_webView loadHTMLString:@"" baseURL:nil];
		return;
	}
	
	NSMutableString*  html = [NSMutableString string];
	NSURL*  jsURL = [[NSBundle mainBundle] URLForResource:@"MCOMessageViewScript" withExtension:@"js"];
    [html appendFormat:@"<html><head><meta name='viewport' content='width=device-width, initial-scale=1.0, user-scalable=yes'><script src=\"%@\"></script></head><body>%@</body><iframe src='x-mailcore-msgviewloaded:' style='width: 0px; height: 0px; border: none;'></iframe></html>",
     [jsURL absoluteString], content];
    
	[_webView loadHTMLString:html baseURL:nil];
}

-(BOOL) _isCID:(NSURL*)url
{
	NSString* theScheme = [url scheme];
	if ([theScheme caseInsensitiveCompare:@"cid"] == NSOrderedSame)
        return YES;
    return NO;
}

-(BOOL) _isXMailcoreImage:(NSURL*)url
{
	NSString* theScheme = [url scheme];
	if ([theScheme caseInsensitiveCompare:@"x-mailcore-image"] == NSOrderedSame)
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
		/*else if ([self _isXMailcoreImage:url]) {
            CCMLog(@"url is x-mailcore-img:%@", url);
			NSString*  specifier = [url resourceSpecifier];
			NSString*  partUniqueID = specifier;
			//part = [self _partForUniqueID:partUniqueID];
		}*/
		
		if (part == nil)
			continue;
		
        //NSString*  partUniqueID = [part uniqueID];
        
       // NSData*  previewData = [self dataPartForUniqueID:partUniqueID];
        
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

-(NSURL*) _cacheJPEGImageData:(NSData*)imageData withFilename:(NSString*)filename
{
	NSString*  path = [[NSTemporaryDirectory() stringByAppendingPathComponent:filename] stringByAppendingPathExtension:@"jpg"];
	[imageData writeToFile:path atomically:YES];
	return [NSURL fileURLWithPath:path];
}

-(MCOAttachment*)partForContentID:(NSString*)partUniqueID{
    return [self.delegate partForUniqueID:partUniqueID];
}

-(MCOAbstractPart*) _partForCIDURL:(NSURL*)url
{
    return [_message partForContentID:[url resourceSpecifier]];
}

-(MCOAbstractPart*) _partForUniqueID:(NSString*)partUniqueID
{
    return [_message partForUniqueID:partUniqueID];
}

-(NSData*) _dataForIMAPPart:(MCOIMAPPart*)part folder:(NSString*)folder
{
    NSData*  data;
    NSString*  partUniqueID = [part uniqueID];
    data = [[self delegate] MCOMessageView:self dataForPartWithUniqueID:partUniqueID];
    if (data == NULL) {
        [[self delegate] MCOMessageView:self fetchDataForPartWithUniqueID:partUniqueID downloadedFinished:^(NSError*  error) {
            [self _refresh];
        }];
    }
    return data;
}

-(BOOL)webView:(UIWebView*)webView shouldStartLoadWithRequest:(NSURLRequest*)request navigationType:(UIWebViewNavigationType)navigationType {
    
   
    if (navigationType == UIWebViewNavigationTypeLinkClicked ) {
        //NSURL* url = [request URL];
        //if ([[url absoluteString] rangeOfString:@"gmail"].location == NSNotFound) {
            //[self.delegate openWebURL:url];
            [[UIApplication sharedApplication] openURL:[request URL]];
            return NO;
        //}
    }
    else if (navigationType == UIWebViewNavigationTypeOther) {
        NSURL* url = [request URL];
        if ([[url scheme] isEqualToString:@"ready"]) {
            float contentHeight = [[[url host] componentsSeparatedByString:@","][0] integerValue];

            if (contentHeight < _webView.scrollView.contentSize.height) {
                contentHeight = _webView.scrollView.contentSize.height;
            }
            
            CGRect fr = _webView.frame;
            fr.size = CGSizeMake(_webView.frame.size.width, contentHeight);
            _webView.frame = fr;
            
            [_loadingView setHidden:YES];
            [self.delegate webViewLoaded:_webView];
            return NO;
        }
    }
    
    NSURLRequest* responseRequest = [self webView:webView resource:nil willSendRequest:request redirectResponse:nil fromDataSource:nil];
    
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

-(BOOL) MCOAbstractMessage:(MCOAbstractMessage*)msg canPreviewPart:(MCOAbstractPart*)part
{
    static NSMutableSet * supportedImageMimeTypes = NULL;
    if (supportedImageMimeTypes == NULL) {
        supportedImageMimeTypes = [[NSMutableSet alloc] init];
        [supportedImageMimeTypes addObject:@"image/png"];
        [supportedImageMimeTypes addObject:@"image/gif"];
        [supportedImageMimeTypes addObject:@"image/jpg"];
        [supportedImageMimeTypes addObject:@"image/jpeg"];
    }
    static NSMutableSet * supportedImageExtension = NULL;
    if (supportedImageExtension == NULL) {
        supportedImageExtension = [[NSMutableSet alloc] init];
        [supportedImageExtension addObject:@"png"];
        [supportedImageExtension addObject:@"gif"];
        [supportedImageExtension addObject:@"jpg"];
        [supportedImageExtension addObject:@"jpeg"];
    }
    
    if ([supportedImageMimeTypes containsObject:[[part mimeType] lowercaseString]]) {
        return YES;
    }
    
    NSString*  ext = nil;
    if ([part filename] != nil) {
        if ([[part filename] pathExtension] != nil) {
            ext = [[[part filename] pathExtension] lowercaseString];
        }
    }
    if (ext != nil) {
        if ([supportedImageExtension containsObject:ext])
            return YES;
    }
    
    if (![[self delegate] respondsToSelector:@selector(MCOMessageView:canPreviewPart:)]) {
        return false;
    }
    return [[self delegate] MCOMessageView:self canPreviewPart:part];
}

-(NSDictionary*) MCOAbstractMessage:(MCOAbstractMessage*)msg templateValuesForHeader:(MCOMessageHeader*)header
{
    if (![[self delegate] respondsToSelector:@selector(MCOMessageView:templateValuesForHeader:)]) {
        return nil;
    }
    return [[self delegate] MCOMessageView:self templateValuesForHeader:header];
}

-(NSDictionary*) MCOAbstractMessage:(MCOAbstractMessage*)msg templateValuesForPart:(MCOAbstractPart*)part
{
    if (![[self delegate] respondsToSelector:@selector(MCOMessageView:templateValuesForPartWithUniqueID:)]) {
        return nil;
    }
    return [[self delegate] MCOMessageView:self templateValuesForPartWithUniqueID:[part uniqueID]];
}

-(NSString*) MCOAbstractMessage:(MCOAbstractMessage*)msg templateForMainHeader:(MCOMessageHeader*)header
{
    if (![[self delegate] respondsToSelector:@selector(MCOMessageView_templateForMainHeader:)]) {
        return nil;
    }
    return [[self delegate] MCOMessageView_templateForMainHeader:self];
}

-(NSString*) MCOAbstractMessage:(MCOAbstractMessage*)msg templateForImage:(MCOAbstractPart*)header
{
    NSString*  templateString;
    if ([[self delegate] respondsToSelector:@selector(MCOMessageView_templateForImage:)]) {
        templateString = [[self delegate] MCOMessageView_templateForImage:self];
    }
    else {
        templateString = @"<img src=\"{{URL}}\"/>";
    }
    templateString = [NSString stringWithFormat:@"<div id=\"{{CONTENTID}}\">%@</div>", templateString];
    return templateString;
}

-(NSString*) MCOAbstractMessage:(MCOAbstractMessage*)msg templateForAttachment:(MCOAbstractPart*)part
{
    if (![[self delegate] respondsToSelector:@selector(MCOMessageView_templateForAttachment:)]) {
        return NULL;
    }
    NSString*  templateString = [[self delegate] MCOMessageView_templateForAttachment:self];
    templateString = [NSString stringWithFormat:@"<div id=\"{{CONTENTID}}\">%@</div>", templateString];
    return templateString;
}

-(NSString*) MCOAbstractMessage_templateForMessage:(MCOAbstractMessage*)msg
{
    if (![[self delegate] respondsToSelector:@selector(MCOMessageView_templateForMessage:)]) {
        return NULL;
    }
    return [[self delegate] MCOMessageView_templateForMessage:self];
}

-(NSString*) MCOAbstractMessage:(MCOAbstractMessage*)msg templateForEmbeddedMessage:(MCOAbstractMessagePart*)part
{
    if (![[self delegate] respondsToSelector:@selector(MCOMessageView_templateForEmbeddedMessage:)]) {
        return NULL;
    }
    return [[self delegate] MCOMessageView_templateForEmbeddedMessage:self];
}

-(NSString*) MCOAbstractMessage:(MCOAbstractMessage*)msg templateForEmbeddedMessageHeader:(MCOMessageHeader*)header
{
    if (![[self delegate] respondsToSelector:@selector(MCOMessageView_templateForEmbeddedMessageHeader:)]) {
        return NULL;
    }
    return [[self delegate] MCOMessageView_templateForEmbeddedMessageHeader:self];
}

-(NSString*) MCOAbstractMessage_templateForAttachmentSeparator:(MCOAbstractMessage*)msg
{
    if (![[self delegate] respondsToSelector:@selector(MCOMessageView_templateForAttachmentSeparator:)]) {
        return NULL;
    }
    return [[self delegate] MCOMessageView_templateForAttachmentSeparator:self];
}

-(NSString*) MCOAbstractMessage:(MCOAbstractMessage*)msg filterHTMLForPart:(NSString*)html
{
    if (![[self delegate] respondsToSelector:@selector(MCOMessageView:filteredHTMLForPart:)]) {
        return html;
    }
    return [[self delegate] MCOMessageView:self filteredHTMLForPart:html];
}

-(NSString*) MCOAbstractMessage:(MCOAbstractMessage*)msg filterHTMLForMessage:(NSString*)html
{
    if (![[self delegate] respondsToSelector:@selector(MCOMessageView:filteredHTMLForMessage:)]) {
        return html;
    }
    return [[self delegate] MCOMessageView:self filteredHTMLForMessage:html];
}

-(NSData*) MCOAbstractMessage:(MCOAbstractMessage*)msg dataForIMAPPart:(MCOIMAPPart*)part folder:(NSString*)folder
{
    return [self _dataForIMAPPart:part folder:folder];
}

-(void) MCOAbstractMessage:(MCOAbstractMessage*)msg prefetchAttachmentIMAPPart:(MCOIMAPPart*)part folder:(NSString*)folder
{
    if (!_prefetchIMAPAttachmentsEnabled)
        return;
    
    NSString*  partUniqueID = [part uniqueID];
    [[self delegate] MCOMessageView:self fetchDataForPartWithUniqueID:partUniqueID downloadedFinished:^(NSError*  error) {
        // do nothing
    }];
}

-(void) MCOAbstractMessage:(MCOAbstractMessage*)msg prefetchImageIMAPPart:(MCOIMAPPart*)part folder:(NSString*)folder
{
    if (!_prefetchIMAPImagesEnabled)
        return;
    
    NSString*  partUniqueID = [part uniqueID];
    [[self delegate] MCOMessageView:self fetchDataForPartWithUniqueID:partUniqueID downloadedFinished:^(NSError*  error) {
        // do nothing
    }];
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
