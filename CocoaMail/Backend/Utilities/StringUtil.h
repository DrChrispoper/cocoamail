//
//  StringUtil.h
//  CocoaMail
//
//  Created by Christopher Hockley on 20/01/2012.
//  Copyright (c) 2012 Christopher Hockley. All rights reserved.
//

@interface StringUtil : NSObject

+(NSArray*) split:(NSString*)s atString:(NSString*)y;
+(NSString*) trim:(NSString*)s;
+(NSString*) filePathInDocumentsDirectoryForFileName:(NSString*)filename;
+(NSString*) filePathInDocumentsDirectoryForAttachmentFileName:(NSString*)filename;
+(NSString*) initialStringForPersonString:(NSString*)personString;


@end
