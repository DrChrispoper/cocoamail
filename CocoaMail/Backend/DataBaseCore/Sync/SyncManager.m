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
		// Get the persistent state
		self.syncStates = [NSMutableArray arrayWithCapacity:2];
        
        // For each UserSettings referenced by the AppSettings singleton
        for (UserSettings* user in [AppSettings getSingleton].users) {
            
            if (user.isAll) {
                // This UserSettings is for the special All Accounts Mail view
                [self.syncStates insertObject:[NSMutableDictionary dictionaryWithCapacity:1] atIndex:0];
            }
            else if (user.isDeleted) {
                // This UserSetting's Account has been deleted
				[self.syncStates addObject:[NSMutableDictionary dictionaryWithCapacity:1]];
			}
            else {
                // This UserSettings is for a (non-All non-Deleted) Account
                NSString* fileName = [NSString stringWithFormat:SYNC_STATE_FILE_NAME_TEMPLATE, (long)user.accountNum];
				NSString* filePath = [StringUtil filePathInDocumentsDirectoryForFileName:fileName];
				
				if ([[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
                    DDLogDebug(@"File %@ does Exist",fileName);
                    
                    // Get the data contained in the file
					NSData* fileData = [[NSData alloc] initWithContentsOfFile:filePath];
                    
                    // Read the property dictionary from the file data
					NSDictionary* props = [NSPropertyListSerialization propertyListWithData:fileData options:NSPropertyListMutableContainersAndLeaves format:nil error:nil];
					
                    // Add the property dictionary to the syncStates array.
					[self.syncStates addObject:props];
				}
                else {
                    DDLogDebug(@"File %@ does NOT Exist",fileName);

                    // Create a new property dictionary
					NSMutableDictionary* props = [[NSMutableDictionary alloc] initWithObjectsAndKeys:@"2", @"__version", [NSMutableArray array], FOLDER_STATES_KEY, nil];
                    
                    // Add the property dictionary to the syncStates array
					[self.syncStates addObject:props];
				}
			}
		}
	}
	
	return self;
}

#pragma mark Request sync

-(RACSignal*) syncActiveFolderFromStart:(BOOL)isFromStart user:(UserSettings*)user
{
    ImapSync *imapSyncService = [ImapSync sharedServices:user];
    
    NSInteger currentFolderIndex = [user.linkedAccount currentFolderIdx];
    
    return [self emailForSignal:[imapSyncService runFolder:currentFolderIndex
                                                 fromStart:isFromStart
                                               fromAccount:NO]];
}

-(RACSignal*) refreshImportantFolder:(NSInteger)baseFolder user:(UserSettings*)user
{
    return [self emailForSignal:[[ImapSync sharedServices:user] runFolder:[user numFolderWithFolder:FolderTypeWith(baseFolder, 0)] fromStart:YES fromAccount:NO]];
}

-(RACSignal*) syncFoldersUser:(UserSettings*)user;
{
    return [self emailForSignal:[[ImapSync sharedServices:user] runFolder:-1 fromStart:NO fromAccount:YES]];
}

-(RACSignal*) syncInboxFoldersBackground
{
    NSMutableArray* newEmailsSignalArray = [[NSMutableArray alloc]init];

    for (UserSettings* user in [AppSettings getSingleton].users) {
        if (user.isDeleted) {
            continue;
        }
    //for (NSInteger accountIndex = 0 ; accountIndex < [AppSettings numActiveAccounts];accountIndex++) {
        
        [ImapSync runInboxUnread:user];
        
        NSInteger folder = [user numFolderWithFolder:FolderTypeWith(FolderTypeInbox, 0)];
        [newEmailsSignalArray addObject:[self emailForSignal:[[ImapSync sharedServices:user] runFolder:folder fromStart:YES fromAccount:NO]]];
    }
    
    return [RACSignal merge:newEmailsSignalArray];
}

-(RACSignal*) searchText:(NSString*)text user:(UserSettings*)user
{
    return [self emailForSignal:[[ImapSync sharedServices:user] runSearchText:text]];
}

-(RACSignal*) searchPerson:(Person*)person user:(UserSettings*)user
{
    return [self emailForSignal:[[ImapSync sharedServices:user] runSearchPerson:person]];
}

-(RACSignal*) emailForSignal:(RACSignal*)signal
{
    return  [signal map:^(Mail* email) {
        return email;
    }];
}

#pragma	mark Update and retrieve syncState

-(NSInteger) folderCount:(NSInteger)accountNum
{
    NSArray* folderStates = self.syncStates[accountNum][FOLDER_STATES_KEY];
	
    return [folderStates count];
}

-(NSDictionary*) retrieveState:(NSInteger)folderNum accountNum:(NSInteger)accountNum
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
    self.syncStates[accountNum][FOLDER_STATES_KEY][folderNum][@"deleted"] = @YES;
	
	NSString* filePath = [StringUtil filePathInDocumentsDirectoryForFileName:[NSString stringWithFormat:SYNC_STATE_FILE_NAME_TEMPLATE, (long)accountNum]];
	
    if (![self.syncStates[accountNum] writeToFile:filePath atomically:YES]) {
		CCMLog(@"Unsuccessful in persisting state to file %@", filePath);
	}
}

-(void) persistState:(NSMutableDictionary*)data forFolderNum:(NSInteger)folderNum accountNum:(NSInteger)accountNum
{
	self.syncStates[accountNum][FOLDER_STATES_KEY][folderNum] = data;
		
	NSString* filePath = [StringUtil filePathInDocumentsDirectoryForFileName:[NSString stringWithFormat:SYNC_STATE_FILE_NAME_TEMPLATE, (long)accountNum]];
    
    if (![self.syncStates[accountNum] writeToFile:filePath atomically:YES]) {
		CCMLog(@"Unsuccessful in persisting state to file %@", filePath);
	}
}


@end
