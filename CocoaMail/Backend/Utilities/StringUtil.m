//
//  StringUtil.m
//  CocoaMail
//
//  Created by Christopher Hockley on 20/01/2012.
//  Copyright (c) 2012 Christopher Hockley. All rights reserved.
//

#import "StringUtil.h"

@implementation StringUtil

+(NSArray*) split:(NSString*)s atString:(NSString*)y
{
	return [s componentsSeparatedByString:y];
}

+(NSString*) trim:(NSString*)s
{
	NSCharacterSet* seperator = [NSCharacterSet characterSetWithCharactersInString:@" \t\r\n\f"];
	
	NSString* y = [s stringByTrimmingCharactersInSet:seperator];
	
	return y;
}

+(NSString*) filePathInDocumentsDirectoryForFileName:(NSString*)filename
{
	NSArray* paths = NSSearchPathForDirectoriesInDomains (NSDocumentDirectory, NSUserDomainMask, YES);
	NSString* documentsDirectory = paths[0];
	NSString* pathName = [documentsDirectory stringByAppendingPathComponent:filename];
    
	return pathName;
}

+(NSString*) filePathInDocumentsDirectoryForAttachmentFileName:(NSString*)filename
{
    NSArray* paths = NSSearchPathForDirectoriesInDomains (NSDocumentDirectory, NSUserDomainMask, YES);
    NSString* documentsDirectory = paths[0];
    documentsDirectory = [documentsDirectory stringByAppendingPathComponent:@"AttachmentsCache"];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:documentsDirectory]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:documentsDirectory withIntermediateDirectories:NO attributes:nil error:nil]; //Create folder
    }
    
    NSString* pathName = [documentsDirectory stringByAppendingPathComponent:filename];
    
    return pathName;
}

+(NSString*) initialStringForPersonString:(NSString*)personString
{
    personString = [personString uppercaseString];
    
    if ([[personString substringToIndex:1] isEqualToString:@" "]) {
        personString = [[personString substringWithRange:NSMakeRange(1, personString.length - 1)]capitalizedString];
    }
    
    if (personString.length == 0) {
        return @"@";
    }
    
    if (personString.length < 3) {
        return [personString substringToIndex:personString.length];
    }
    else {
        return [personString substringToIndex:3];
    }
    
    return @"🇫🇷";
}


@end
