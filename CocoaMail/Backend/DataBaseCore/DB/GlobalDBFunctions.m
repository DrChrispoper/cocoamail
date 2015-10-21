//
//  GlobalDBFunctions.m
//  CocoaMail
//
//  Created by Christopher Hockley on 20/01/2012.
//  Copyright (c) 2012 Christopher Hockley. All rights reserved.
//

#import "GlobalDBFunctions.h"
#import "StringUtil.h"
#import "Email.h"
#import "CCMAttachment.h"
#import "UidEntry.h"
#import "CachedAction.h"
#import "AppSettings.h"

@implementation GlobalDBFunctions

#pragma	mark Add DB management

+(void) deleteAll
{
	NSArray* paths = NSSearchPathForDirectoriesInDomains (NSDocumentDirectory, NSUserDomainMask, YES); 
	NSString* documentsDirectory = paths[0];
	
	NSString* fileName;
	NSDirectoryEnumerator* dirEnum = [[NSFileManager defaultManager] enumeratorAtPath:documentsDirectory];
    
	while (fileName = [dirEnum nextObject]) {
		NSString* filePath = [StringUtil filePathInDocumentsDirectoryForFileName:fileName];
		[[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
	}
}

+(NSString*) dbFileNameForNum:(NSInteger)dbNum
{
	return [NSString stringWithFormat:@"email-%lu.edb", (long)dbNum];
}

+(void) tableCheck
{
    // NOTE: need to change dbGlobalTableVersion every time we change the schema
    if ([AppSettings globalDBVersion] < 1) {
        [UidEntry tableCheck];
        [CCMAttachment tableCheck];
        [CachedAction tableCheck];
        [AppSettings setGlobalDBVersion:1];
    }	
}


@end
