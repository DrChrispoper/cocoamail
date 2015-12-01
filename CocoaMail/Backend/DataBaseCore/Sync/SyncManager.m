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
		for (NSInteger i = 0; i < [AppSettings numAccounts]+1; i++) {
			if ([AppSettings isAccountNumDeleted:i]) {
				[self.syncStates addObject:[NSMutableDictionary dictionaryWithCapacity:1]];
			}
            else {
				NSString* filePath = [StringUtil filePathInDocumentsDirectoryForFileName:[NSString stringWithFormat:SYNC_STATE_FILE_NAME_TEMPLATE, (long)i]];
				
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

-(RACSignal*) syncActiveFolderFromStart:(BOOL)isFromStart
{
    if (kisActiveAccountAll) {
        NSMutableArray* newEmailsSignalArray = [[NSMutableArray alloc]init];
        
        for (NSInteger accountIndex = 0 ; accountIndex < [AppSettings numActiveAccounts];accountIndex++) {
            //NSInteger accountIndex = [AppSettings numAccountForIndex:i];
            [newEmailsSignalArray addObject:[self emailForSignal:[[ImapSync sharedServices:accountIndex] runFolder:[[[Accounts sharedInstance] getAccount:accountIndex] currentFolderIdx] fromStart:isFromStart fromAccount:NO]]];
        }
        
        return [RACSignal merge:newEmailsSignalArray];
    }
    else {
        return [self emailForSignal:[[ImapSync sharedServices] runFolder:[[Accounts sharedInstance].currentAccount currentFolderIdx] fromStart:isFromStart fromAccount:NO]];
    }
}

-(RACSignal*) refreshImportantFolder:(NSInteger)pfolder
{
    if (kisActiveAccountAll) {
        NSMutableArray* newEmailsSignalArray = [[NSMutableArray alloc]init];
        
        for (NSInteger accountIndex = 0 ; accountIndex < [AppSettings numActiveAccounts];accountIndex++) {
            //NSInteger accountIndex = [AppSettings numAccountForIndex:i];
            NSInteger folder = [AppSettings importantFolderNumforAccountIndex:accountIndex forBaseFolder:pfolder];
            [newEmailsSignalArray addObject:[self emailForSignal:[[ImapSync sharedServices:accountIndex] runFolder:folder fromStart:YES fromAccount:NO]]];
        }
        
        return [RACSignal merge:newEmailsSignalArray];
    }
    else {
        return [self emailForSignal:[[ImapSync sharedServices] runFolder:[AppSettings importantFolderNumforAccountIndex:kActiveAccountIndex forBaseFolder:pfolder] fromStart:YES fromAccount:NO]];
    }
}

-(RACSignal*) refreshInbox
{
    if (kisActiveAccountAll) {
        NSMutableArray* newEmailsSignalArray = [[NSMutableArray alloc]init];
        
        for (NSInteger accountIndex = 0 ; accountIndex < [AppSettings numActiveAccounts];accountIndex++) {
            //NSInteger accountIndex = [AppSettings numAccountForIndex:i];
            [newEmailsSignalArray addObject:[self emailForSignal:[[ImapSync sharedServices:accountIndex] runFolder:[AppSettings numFolderWithFolder:FolderTypeWith(FolderTypeInbox, 0) forAccountIndex:accountIndex] fromStart:YES fromAccount:YES]]];
        }
        
        return [RACSignal merge:newEmailsSignalArray];
    }
    else {
        return [self emailForSignal:[[ImapSync sharedServices] runFolder:[AppSettings numFolderWithFolder:FolderTypeWith(FolderTypeInbox, 0) forAccountIndex:kActiveAccountIndex] fromStart:YES fromAccount:YES]];
    }
}

-(RACSignal*) syncFolders
{
    if (kisActiveAccountAll) {
        NSMutableArray* newEmailsSignalArray = [[NSMutableArray alloc]init];
        
        for (NSInteger accountIndex = 0 ; accountIndex < [AppSettings numActiveAccounts];accountIndex++) {
            //NSInteger accountIndex = [AppSettings numAccountForIndex:i];
            [newEmailsSignalArray addObject:[self emailForSignal:[[ImapSync sharedServices:accountIndex] runFolder:-1 fromStart:NO fromAccount:YES]]];
        }
        
        return [RACSignal merge:newEmailsSignalArray];
    }
    else {
        return [self emailForSignal:[[ImapSync sharedServices] runFolder:-1 fromStart:NO fromAccount:YES]];
    }
}

-(RACSignal*) syncInboxFoldersBackground
{
    NSMutableArray* newEmailsSignalArray = [[NSMutableArray alloc]init];

    for (NSInteger accountIndex = 0 ; accountIndex < [AppSettings numActiveAccounts];accountIndex++) {
        //NSInteger accountIndex = [AppSettings numAccountForIndex:i];
            NSInteger folder = [AppSettings importantFolderNumforAccountIndex:accountIndex forBaseFolder:FolderTypeInbox];
            [newEmailsSignalArray addObject:[self emailForSignal:[[ImapSync sharedServices:accountIndex] runFolder:folder fromStart:YES fromAccount:NO]]];
            /*[newEmailsSignal subscribeNext:^(Email* email) {
                CCMLog(@"Background fetched: %@",email.subject);
            }
                                     error:^(NSError* error) {}
                                 completed:^{
                                     CCMLog(@"Done with bg fetch account");
                                 }];*/
    }
    
    return [RACSignal merge:newEmailsSignalArray];
}

-(RACSignal*) searchText:(NSString*)text
{
    if (kisActiveAccountAll) {
        NSMutableArray* newEmailsSignalArray = [[NSMutableArray alloc]init];
        
        for (NSInteger accountIndex = 0 ; accountIndex < [AppSettings numActiveAccounts];accountIndex++) {
            //NSInteger accountIndex = [AppSettings numAccountForIndex:i];
            [newEmailsSignalArray addObject:[self emailForSignal:[[ImapSync sharedServices:accountIndex] runSearchText:text]]];
        }
        
        return [RACSignal merge:newEmailsSignalArray];
    }
    else {
        return [self emailForSignal:[[ImapSync sharedServices] runSearchText:text]];
    }
}

-(RACSignal*) searchPerson:(Person*)person
{
    if (kisActiveAccountAll) {
        NSMutableArray* newEmailsSignalArray = [[NSMutableArray alloc]init];
        
        for (NSInteger accountIndex = 0 ; accountIndex < [AppSettings numActiveAccounts];accountIndex++) {
            //NSInteger accountIndex = [AppSettings numAccountForIndex:i];
            [newEmailsSignalArray addObject:[self emailForSignal:[[ImapSync sharedServices:accountIndex] runSearchPerson:person]]];
        }
        
        return [RACSignal merge:newEmailsSignalArray];
    }
    else {
        return [self emailForSignal:[[ImapSync sharedServices] runSearchPerson:person]];
    }
}

-(RACSignal*) emailForSignal:(RACSignal*)signal
{
    return  [signal map:^(Email* email) {
        return email;
    }];
}

#pragma	mark Update and retrieve syncState

-(NSInteger) folderCount:(NSInteger)accountIndex
{
    NSArray* folderStates = self.syncStates[[AppSettings numForData:accountIndex]][FOLDER_STATES_KEY];
	
    return [folderStates count];
}

-(NSMutableDictionary*) retrieveState:(NSInteger)folderNum accountIndex:(NSInteger)accountIndex
{
    NSArray* folderStates = self.syncStates[[AppSettings numForData:accountIndex]][FOLDER_STATES_KEY];
	
	if (folderNum >= [folderStates count]) {
		return nil;
	}
	
	return [folderStates[folderNum] mutableCopy];
}

-(void) addAccountState
{
	NSInteger numAccounts = [AppSettings numAccounts] + 1;
	
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
	
	[AppSettings addAccount];
}

-(void) addFolderState:(NSDictionary*)data accountIndex:(NSInteger)accountIndex
{
	[self.syncStates[[AppSettings numForData:accountIndex]][FOLDER_STATES_KEY] addObject:data];
	
	NSString* filePath = [StringUtil filePathInDocumentsDirectoryForFileName:[NSString stringWithFormat:SYNC_STATE_FILE_NAME_TEMPLATE, (long)[AppSettings numForData:accountIndex]]];
	
    if (![self.syncStates[[AppSettings numForData:accountIndex]] writeToFile:filePath atomically:YES]) {
		CCMLog(@"Unsuccessful in persisting state to file %@", filePath);
	}
}

-(BOOL) isFolderDeleted:(NSInteger)folderNum accountIndex:(NSInteger)accountIndex
{
	NSArray* folderStates = self.syncStates[[AppSettings numForData:accountIndex]][FOLDER_STATES_KEY];
	
	if (folderNum >= [folderStates count]) {
		return YES;
	}
	
	NSNumber* y =  folderStates[folderNum][@"deleted"];
	
	return (y == nil) || [y boolValue];
}

-(void) markFolderDeleted:(NSInteger)folderNum accountIndex:(NSInteger)accountIndex
{
	NSMutableArray* folderStates = self.syncStates[[AppSettings numForData:accountIndex]][FOLDER_STATES_KEY];
	
	NSMutableDictionary* y = folderStates[folderNum];
	y[@"deleted"] = @YES;
	
	NSString* filePath = [StringUtil filePathInDocumentsDirectoryForFileName:[NSString stringWithFormat:SYNC_STATE_FILE_NAME_TEMPLATE, (long)[AppSettings numForData:accountIndex]]];
	
    if (![self.syncStates[[AppSettings numForData:accountIndex]] writeToFile:filePath atomically:YES]) {
		CCMLog(@"Unsuccessful in persisting state to file %@", filePath);
	}
}

-(void) persistState:(NSMutableDictionary*)data forFolderNum:(NSInteger)folderNum accountIndex:(NSInteger)accountIndex
{
	NSMutableArray* folderStates = self.syncStates[[AppSettings numForData:accountIndex]][FOLDER_STATES_KEY];
	
	folderStates[folderNum] = data;
	
	NSString* filePath = [StringUtil filePathInDocumentsDirectoryForFileName:[NSString stringWithFormat:SYNC_STATE_FILE_NAME_TEMPLATE, (long)[AppSettings numForData:accountIndex]]];
    
    if (![self.syncStates[[AppSettings numForData:accountIndex]] writeToFile:filePath atomically:YES]) {
		CCMLog(@"Unsuccessful in persisting state to file %@", filePath);
	}
}


@end