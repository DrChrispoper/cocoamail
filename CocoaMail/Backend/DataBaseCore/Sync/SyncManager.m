//
//  SyncManager.m
//  CocoaMail
//
//  Created by Christopher Hockley on 20/01/2012.
//  Copyright (c) 2012 Christopher Hockley. All rights reserved.
//

#import <CommonCrypto/CommonDigest.h>
#import "SyncManager.h"
#import "StringUtil.h"
#import "Reachability.h"
#import "UidDBAccessor.h"
#import "AppSettings.h"
#import "ImapSync.h"
#import "UserSettings.h"

#define SYNC_STATE_FILE_NAME_TEMPLATE    @"sync_state_%lu.plist"
#define FOLDER_STATES_KEY		@"folderStates"

static SyncManager * singleton = nil;

@implementation SyncManager

@synthesize aNewEmailDelegate;
@synthesize syncStates;
@synthesize syncInProgress;

+(SyncManager*) getSingleton
{
	@synchronized(self) {
		if (singleton == nil) {
			singleton = [[self alloc] init];
		}
	}
    
	return singleton;
}

-(id) init
{
	if (self = [super init]) {
		//Get the persistent state
		self.syncStates = [NSMutableArray arrayWithCapacity:2];
        for (UserSettings* user in [AppSettings getSingleton].users) {
            if (user.isAll) {
                [self.syncStates insertObject:[NSMutableDictionary dictionaryWithCapacity:1] atIndex:0];
            }
            else if (user.isDeleted) {
				[self.syncStates addObject:[NSMutableDictionary dictionaryWithCapacity:1]];
			}
            else {
				NSString* filePath = [StringUtil filePathInDocumentsDirectoryForFileName:[NSString stringWithFormat:SYNC_STATE_FILE_NAME_TEMPLATE, (long)user.accountNum]];
				
				if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
					NSData* fileData = [[NSData alloc] initWithContentsOfFile:filePath];
					NSMutableDictionary* props = [NSPropertyListSerialization propertyListWithData:fileData options:NSPropertyListMutableContainersAndLeaves format:nil error:nil];
					
					[self.syncStates addObject:props];
				}
                else {
					NSMutableDictionary* props = [[NSMutableDictionary alloc] initWithObjectsAndKeys:@"2", @"__version", [NSMutableArray array], FOLDER_STATES_KEY, nil];
					[self.syncStates addObject:props];
				}
			}
		}
	}
	
	return self;
}

#pragma mark Request sync

-(RACSignal*) syncActiveFolderFromStart:(BOOL)isFromStart accountIndex:(NSInteger)accountIndex;
{
    return [self emailForSignal:[[ImapSync sharedServices:accountIndex] runFolder:[[Accounts sharedInstance].currentAccount currentFolderIdx] fromStart:isFromStart fromAccount:NO]];
}

-(RACSignal*) refreshImportantFolder:(NSInteger)pfolder accountIndex:(NSInteger)accountIndex;
{
    return [self emailForSignal:[[ImapSync sharedServices:accountIndex] runFolder:[[AppSettings userWithIndex:accountIndex] importantFolderNumforBaseFolder:pfolder] fromStart:YES fromAccount:NO]];
}

-(RACSignal*) syncFoldersAccountIndex:(NSInteger)accountIndex;
{
    return [self emailForSignal:[[ImapSync sharedServices:accountIndex] runFolder:-1 fromStart:NO fromAccount:YES]];
}

-(RACSignal*) syncInboxFoldersBackground
{
    NSMutableArray* newEmailsSignalArray = [[NSMutableArray alloc]init];

    for (NSInteger accountIndex = 0 ; accountIndex < [AppSettings numActiveAccounts];accountIndex++) {
        
        [ImapSync runInboxUnread:accountIndex];
        
        NSInteger folder = [[AppSettings userWithIndex:accountIndex] importantFolderNumforBaseFolder:FolderTypeInbox];
        [newEmailsSignalArray addObject:[self emailForSignal:[[ImapSync sharedServices:accountIndex] runFolder:folder fromStart:YES fromAccount:NO]]];
    }
    
    return [RACSignal merge:newEmailsSignalArray];
}

-(RACSignal*) searchText:(NSString*)text accountIndex:(NSInteger)accountIndex
{
    return [self emailForSignal:[[ImapSync sharedServices:accountIndex] runSearchText:text]];
}

-(RACSignal*) searchPerson:(Person*)person accountIndex:(NSInteger)accountIndex
{
    return [self emailForSignal:[[ImapSync sharedServices:accountIndex] runSearchPerson:person]];
}

-(RACSignal*) emailForSignal:(RACSignal*)signal
{
    return  [signal map:^(Mail* email) {
        return email;
    }];
}

#pragma	mark Update and retrieve syncState

-(NSInteger) folderCount:(NSInteger)accountIndex
{
    NSArray* folderStates = self.syncStates[[AppSettings numAccountForIndex:accountIndex]][FOLDER_STATES_KEY];
	
    return [folderStates count];
}

-(NSMutableDictionary*) retrieveState:(NSInteger)folderNum accountNum:(NSInteger)accountNum
{
    NSArray* folderStates = self.syncStates[accountNum][FOLDER_STATES_KEY];
	
	if (folderNum >= [folderStates count]) {
		return nil;
	}
	
	return [folderStates[folderNum] mutableCopy];
}

-(void) addAccountState
{
    NSInteger numAccounts = [AppSettings getSingleton].users.count - 1;
	
    NSMutableDictionary* props = [[NSMutableDictionary alloc] initWithObjectsAndKeys:@"2", @"__version", [NSMutableArray array], FOLDER_STATES_KEY, nil];
    
    if (numAccounts == 1) {
        self.syncStates [0] = props;
        NSInteger z = 0;
        NSString* filePath = [StringUtil filePathInDocumentsDirectoryForFileName:[NSString stringWithFormat:SYNC_STATE_FILE_NAME_TEMPLATE, (long)z]];
        
        if (![self.syncStates[0] writeToFile:filePath atomically:YES]) {
            CCMLog(@"Unsuccessful in persisting state to file %@", filePath);
        }
    }
    
	[self.syncStates addObject:props];
	
	NSString* filePath = [StringUtil filePathInDocumentsDirectoryForFileName:[NSString stringWithFormat:SYNC_STATE_FILE_NAME_TEMPLATE, (long)numAccounts]];
    
	if (![self.syncStates[numAccounts] writeToFile:filePath atomically:YES]) {
		CCMLog(@"Unsuccessful in persisting state to file %@", filePath);
	}
}

-(void) addFolderState:(NSDictionary*)data accountNum:(NSInteger)accountNum
{
	[self.syncStates[accountNum][FOLDER_STATES_KEY] addObject:data];
	
	NSString* filePath = [StringUtil filePathInDocumentsDirectoryForFileName:[NSString stringWithFormat:SYNC_STATE_FILE_NAME_TEMPLATE, (long)accountNum]];
	
    if (![self.syncStates[accountNum] writeToFile:filePath atomically:YES]) {
		CCMLog(@"Unsuccessful in persisting state to file %@", filePath);
	}
}

-(BOOL) isFolderDeleted:(NSInteger)folderNum accountNum:(NSInteger)accountNum
{
	NSArray* folderStates = self.syncStates[accountNum][FOLDER_STATES_KEY];
	
	if (folderNum >= [folderStates count]) {
		return YES;
	}
	
	NSNumber* y =  folderStates[folderNum][@"deleted"];
	
	return (y == nil) || [y boolValue];
}

-(void) markFolderDeleted:(NSInteger)folderNum accountNum:(NSInteger)accountNum
{
	NSMutableArray* folderStates = self.syncStates[accountNum][FOLDER_STATES_KEY];
	
	NSMutableDictionary* y = folderStates[folderNum];
	y[@"deleted"] = @YES;
	
	NSString* filePath = [StringUtil filePathInDocumentsDirectoryForFileName:[NSString stringWithFormat:SYNC_STATE_FILE_NAME_TEMPLATE, (long)accountNum]];
	
    if (![self.syncStates[accountNum] writeToFile:filePath atomically:YES]) {
		CCMLog(@"Unsuccessful in persisting state to file %@", filePath);
	}
}

-(void) persistState:(NSMutableDictionary*)data forFolderNum:(NSInteger)folderNum accountNum:(NSInteger)accountNum
{
	NSMutableArray* folderStates = self.syncStates[accountNum][FOLDER_STATES_KEY];
	
	folderStates[folderNum] = data;
	
	NSString* filePath = [StringUtil filePathInDocumentsDirectoryForFileName:[NSString stringWithFormat:SYNC_STATE_FILE_NAME_TEMPLATE, (long)accountNum]];
    
    if (![self.syncStates[accountNum] writeToFile:filePath atomically:YES]) {
		CCMLog(@"Unsuccessful in persisting state to file %@", filePath);
	}
}


@end