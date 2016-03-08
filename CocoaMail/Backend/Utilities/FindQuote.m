//
//  ObjectiveCCallingPython.m
//  CocoaMail
//
//  Created by Christopher Hockley on 02/02/16.
//  Copyright © 2016 Christopher Hockley. All rights reserved.
//

#import "FindQuote.h"
#import "RegExCategories.h"
#import "StringUtil.h"
#import "HTMLReader.h"

@interface FindQuote () {
    NSArray* _REPLY_PATTERNS;
    NSArray* _FORWARD_MESSAGES;
    NSArray* _FORWARD_PATTERNS;
    NSArray* _FORWARD_STYLES;
    NSDictionary* _HEADER_MAP;
}
@end

@implementation FindQuote

+(NSArray<NSString*>*) REPLY_PATTERNS
{
    static NSArray* _REPLY_PATTERNS;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _REPLY_PATTERNS = @[
                            @"^On .*wrote\\s*:\\s*$", // apple mail/gmail reply
                            @"^Am .*schrieb\\s*:\\s*$", // German
                            @"^Le .*écrit\\s*:\\s*$", //French
                            @"[0-9]{4}/[0-9]{1,2}/[0-9]{1,2} .* <.*@.*>$", // gmail (?) reply
                            @"[0-9]{4}-[0-9]{1,2}-[0-9]{1,2} .* <.*@.*>:$",
                            ];
    });
    return _REPLY_PATTERNS;
}

+(NSArray<NSString*>*) FORWARD_MESSAGES
{
    static NSArray* _FORWARD_MESSAGES;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _FORWARD_MESSAGES = @[
                              // apple mail forward
                              @"Begin forwarded message", @"Anfang der weitergeleiteten E-Mail",
                              @"Début du message réexpédié",
                              
                              // gmail/evolution forward
                              @"Forwarded [mM]essage", @"Mensaje reenviado",
                              
                              // outlook
                              @"Original [mM]essage", @"Ursprüngliche Nachricht", @"Mensaje reenviado", @"Mail [oO]riginal",
                              
                              // Thunderbird forward
                              @"Message transféré",
                              
                              @"Message d'origine",
                              ];
    });
    return _FORWARD_MESSAGES;
}

+(NSArray<NSString*>*) FORWARD_PATTERNS
{
    static NSArray* _FORWARD_PATTERNS;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableArray* fwd = [[NSMutableArray alloc] initWithCapacity:[FindQuote FORWARD_MESSAGES].count*2];
        
        [fwd addObject:@"^________________________________$"]; // yahoo?
        
        for (NSString* p in [FindQuote FORWARD_MESSAGES]) {
            [fwd addObject:[NSString stringWithFormat:@"^---+ ?%@ ?---+\\s*$", p]];
        }
        
        for (NSString* p in [FindQuote FORWARD_MESSAGES]) {
            [fwd addObject:[NSString stringWithFormat:@"^%@:$", p]];
        }
        
        _FORWARD_PATTERNS = fwd;
    });
    return _FORWARD_PATTERNS;
}

+(NSArray<NSString*>*) FORWARD_STYLES
{
    static NSArray* _FORWARD_STYLES;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _FORWARD_STYLES = @[
                            // Outlook
                            @"border:none;border-top:solid #B5C4DF 1.0pt;padding:3.0pt 0in 0in 0in",
                            ];
    });
    return _FORWARD_STYLES;
}

+(NSDictionary*) HEADER_MAP
{
    static NSDictionary* _HEADER_MAP;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _HEADER_MAP = @{
                        @"from": @"from",
                        @"von": @"from",
                        @"de": @"from",
                        
                        @"to": @"to",
                        @"an": @"to",
                        @"para": @"to",
                        @"à": @"to",
                        @"pour": @"to",
                        
                        @"cc": @"cc",
                        @"kopie": @"cc",
                        
                        @"bcc": @"bcc",
                        @"blindkopie": @"bcc",
                        
                        @"reply-to": @"reply-to",
                        @"répondre à": @"reply-to",
                        
                        @"date": @"date",
                        @"sent": @"date",
                        @"received": @"date",
                        @"datum": @"date",
                        @"gesendet": @"date",
                        @"enviado el": @"date",
                        @"enviados": @"date",
                        @"fecha": @"date",
                        
                        @"subject": @"subject",
                        @"betreff": @"subject",
                        @"asunto": @"subject",
                        @"objet": @"subject",
                        @"sujet": @"subject",
                        };
    });
    return _HEADER_MAP;
}

+(NSArray<NSString*>*) COMPILED_PATTERNS
{
    static NSArray* _COMPILED_PATTERNS;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSMutableArray* ptrns = [[NSMutableArray alloc] initWithCapacity:[FindQuote REPLY_PATTERNS].count+[FindQuote FORWARD_PATTERNS].count];
        
        for (NSString* regex in [FindQuote REPLY_PATTERNS]) {
            [ptrns addObject:regex];
        }
        
        for (NSString* regex in [FindQuote FORWARD_PATTERNS]) {
            [ptrns addObject:regex];
        }
        
        _COMPILED_PATTERNS = ptrns;
    });
    return _COMPILED_PATTERNS;
}

+(NSRegularExpression*) MULTIPLE_WHITESPACE_RE
{
    return [Rx rx:@"\\s+"];
}

+ (NSArray *) quote_html:(NSString*) html
{
    HTMLDocument* document = [HTMLDocument documentWithString:html];
    
    NSArray* parent_chain = [FindQuote _insert_quotequail_divider:document.rootElement];
    
    NSString* rendered_tree = [document.rootElement serializedFragment];
    
    NSArray* parts = [StringUtil split:rendered_tree atString:@"<div class=\"quotequail-divider\"></div>"];
    
    if ( parts.count  == 1) {
        return @[rendered_tree];
    }
    else {
        // Render open tags and attributes (but no content)
        NSMutableString* open_sequence = [NSMutableString string];
        
        for (HTMLElement* el in [parent_chain reverseObjectEnumerator]) {
            [open_sequence appendFormat:@"<%@%@%@>",el.tagName , el.attributes.count>0?@" ":@"" , [FindQuote _render_attrs:el]];
        }
        
        NSMutableString* close_sequence = [NSMutableString string];
        
        for (HTMLElement* el in parent_chain) {
            [close_sequence appendFormat:@"</%@>",el.tagName];
        }
        
        return @[[NSString stringWithFormat:@"%@%@",parts[0],close_sequence], [NSString stringWithFormat:@"%@%@", open_sequence, parts[1]]];
    }
}

+(NSString*) _render_attrs:(HTMLElement*)el
{
    NSMutableString* attributesString = [NSMutableString string];
    
    for (NSString* key in [el attributes]) {
        [attributesString appendFormat:@"%@=\"%@\" ", key, [el attributes][key]];
    }
    
    return attributesString;
}

+(NSArray*) _get_inline_texts:(HTMLElement*)elParent
{
    NSArray* INLINE_TAGS = @[@"a", @"b", @"em", @"i", @"strong", @"span", @"font", @"q", @"object", @"bdo", @"sub", @"sup", @"center"];
    
    NSMutableArray* texts = [[NSMutableArray alloc] init];
    
    for (NSInteger index = 0; index < elParent.children.count; index++) {
        //for (id child in elParent.children) {
        
        id child = elParent.children[index];
        
        if ([child isKindOfClass:[HTMLTextNode class]]) {
            HTMLTextNode* tn = (HTMLTextNode*)child;
            if (![tn.data isEqualToString:@""]) {
                [texts addObject:[[NSMutableArray alloc] initWithObjects:@(texts.count), tn.data, nil]];
            }
        }
        else if ([child isKindOfClass:[HTMLElement class]]) {
            HTMLElement* el = (HTMLElement*)child;
            
            // Text at the beginning of the element which preceeds any other text
            // e.g. '<div>A<a>B</a></div>' will return 'AB'
            // e.g. '<div>A<a>B</a>C</div>' will return 'ABC'
            // e.g. '<div>A<a>B</a><a>C</a></div>' will return 'ABC'
            // e.g. '<div>A<a>B</a>C<a>D</a></div>' will return 'ABCD'
            
            if ([INLINE_TAGS containsObject:el.tagName]) {
                NSInteger inlineIndex = [elParent.children indexOfObject:el];
                
                NSMutableString* all = [NSMutableString string];
                
                //If text before inline tag use it (A)
                if (inlineIndex != 0 && texts.count > 0) {
                    [all appendString:[texts lastObject][1]];
                }
                else {
                    [texts addObject:[[NSMutableArray alloc] initWithObjects:@(texts.count), all, nil]];
                }
                
                [all appendString:el.textContent];
                
                index++;
                
                //Loop while INLINE_TAGS if HTMLTextNode added and break else just break
                for (; index < elParent.children.count; index++) {
                    id nextChild = elParent.children[index];
                    
                    if ([nextChild isKindOfClass:[HTMLTextNode class]]) {
                        HTMLTextNode* tnNext = (HTMLTextNode*)nextChild;
                        
                        if (![tnNext.data isEqualToString:@""]) {
                            [all appendString:tnNext.data];
                        }
                        
                        [texts lastObject][1] = all;
                        break;
                    }
                    else if ([nextChild isKindOfClass:[HTMLElement class]]) {
                        
                        HTMLElement* elInline = (HTMLElement*)nextChild;
                        
                        if ([INLINE_TAGS containsObject:el.tagName]) {
                            [all appendString:elInline.textContent];
                        }
                        else {
                            [texts lastObject][1] = all;
                            break;
                        }
                    }
                }
            }
        }
    }
    
    return texts;
}

+(NSArray*) _recursive:(HTMLElement*)elParent quail:(HTMLElement*)quail_el
{
    for (HTMLElement* el in elParent.childElementNodes) {
        NSString* style = [el attributes][@"style"];
        
        if ([[FindQuote FORWARD_STYLES] containsObject:style]) {
            NSMutableOrderedSet *children = [el mutableChildren];
            [children insertObject:quail_el atIndex:0];
            quail_el.parentNode = el;
            
            //TODO Check
            return [FindQuote _get_parent_chain:quail_el];
        }
        else {
            
            for (NSArray* txts in [FindQuote _get_inline_texts:el]) {
                
                NSInteger text_idx = [txts[0] integerValue];
                NSString* text = txts[1];
                
                NSArray* ptrns = [FindQuote COMPILED_PATTERNS];
                
                for (NSString* regex in ptrns) {
                    
                    if([[text replace:[FindQuote MULTIPLE_WHITESPACE_RE] with:@" "] isMatch:RX(regex)]) {
                        // Insert quotequail divider *after* the text.
                        
                        //NOT SURE
                        NSMutableOrderedSet *children = [el mutableChildren];
                        
                        [children insertObject:quail_el atIndex:text_idx];
                        
                        return [FindQuote _get_parent_chain:quail_el];
                    }
                }
            }
        }
        
        NSArray* p = [FindQuote _recursive:el quail:quail_el];
        if (p) {
            return p;
        }
    }
    
    return nil;
}

+(NSArray*) _insert_quotequail_divider:(HTMLElement*)elParent {
    /*
     Inserts a quotequail divider div if a pattern is found and returns the
     parent element chain. Returns None if no pattern was found.
     */
    
    HTMLElement* quail_el =  [[HTMLElement alloc] initWithTagName:@"div" attributes:@{@"class": @"quotequail-divider"}];
    
    NSArray* parent = [FindQuote _recursive:elParent quail:quail_el];
    
    if (parent) {
        return parent;
    }
    
    return [FindQuote _get_parent_chain:quail_el];
}

+(NSArray*) _get_parent_chain:(HTMLElement*)quail_el
{
    NSMutableArray* parent_chain = [[NSMutableArray alloc] init];
    
    HTMLElement* parent_el = [quail_el parentElement];
    
    while (parent_el) {
        [parent_chain addObject:parent_el];
        
        parent_el = [parent_el parentElement];
    }
    
    return parent_chain;
}

@end
