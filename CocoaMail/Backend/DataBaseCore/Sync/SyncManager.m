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

//@synthesize aNewEmailDelegate;      // is this used ANYWHERE?
@synthesize syncStates;
//@synthesize syncInProgress;         // is this used ANYWHERE?

// MARK: - Singleton

+(SyncManager*) getSingleton
{
	@synchronized(self) {
		if (singleton == nil) {
			singleton = [[self alloc] init];
		}
	}
    
	return singleton;
}

// MARK: - Initialization

-(id) init
{
	if (self = [super init]) {
        [self _loadSyncSettingsForAllUserAccounts];
	}
	
	return self;
}

-(void)_loadSyncSettingsForAllUserAccounts
{
    // Get the persistent state
    self.syncStates = [NSMutableArray arrayWithCapacity:2];
    
    // For each UserSettings referenced by the AppSettings singleton
    for (UserSettings* user in [AppSettings getSingleton].users) {
        
        if (user.isAll) {
            // This UserSettings is for the special All Accounts Mail view
            // Insert and empty "record" at the start of the Sync States mutable array
            [self.syncStates insertObject:[NSMutableDictionary dictionaryWithCapacity:1] atIndex:0];
        }
        else if (user.isDeleted) {
            // This UserSetting's Account has been deleted
            // Add and empty "record" for the Sync States mutable array
            [self.syncStates addObject:[NSMutableDictionary dictionaryWithCapacity:1]];
        }
        else {
            // This UserSettings is for a regular IMAP Account
            
            NSString* syncStateFullPathFilename
            = [self _syncStateFullPathFilenameForUser:user];
            
            // If this user's Sync Settings preferences file exists ...
            if ([[NSFileManager defaultManager] fileExistsAtPath:syncStateFullPathFilename]){
                DDLogDebug(@"File %@ does Exist",[self _syncStateFilenameForUser:user]);
                
                // Get the data contained in the file
                NSData* fileData = [[NSData alloc] initWithContentsOfFile:syncStateFullPathFilename];
                
                // Read the property dictionary from the file data
                NSMutableDictionary* syncSettingPropertiesFromFile = [NSPropertyListSerialization propertyListWithData:fileData options:NSPropertyListMutableContainersAndLeaves format:nil error:nil];
                
                // Add the properties read from the file into the syncStates array.
                [self.syncStates addObject:syncSettingPropertiesFromFile];
            }
            else {
                DDLogDebug(@"File \"%@\" does NOT Exist",[self _syncStateFilenameForUser:user]);
                
                // Create a NEW property dictionary
                NSMutableDictionary* newSyncSettingsProperties = [self _newSyncStateProperties];
                
                // Add the property dictionary to the syncStates array
                [self.syncStates addObject:newSyncSettingsProperties];
            }
        }
    }
}

- (NSMutableDictionary *)_newSyncStateProperties
{
    return [[NSMutableDictionary alloc] initWithObjectsAndKeys:
                @"2", @"__version",
                [NSMutableArray array], FOLDER_STATES_KEY,
                nil ];
}

-(NSString *)_syncStateFilenameForUser:(UserSettings *)user
{
    return [NSString stringWithFormat:SYNC_STATE_FILE_NAME_TEMPLATE,
       (long)user.accountNum];
}

-(NSString *)_syncStateFullPathFilenameForUser:(UserSettings *)user
{
    // This UserSettings is for a (non-All non-Deleted) Account
    NSString* syncStateFilename = [self _syncStateFilenameForUser:user];
    
    return [StringUtil filePathInDocumentsDirectoryForFileName:syncStateFilename];
}

#pragma mark - Folder Sync Requests

-(RACSignal*) syncActiveFolderFromStart:(BOOL)isFromStart user:(UserSettings*)user
{
    // Get the IMAP Sync Service for this user's account
    ImapSync *imapSyncService = [ImapSync sharedServices:user];
    
    NSInteger currentFolderIndex = [user.linkedAccount currentFolderIdx];  
    
    RACSignal *racSignal = [imapSyncService runFolder:currentFolderIndex
                                            fromStart:isFromStart
                                           gettingAll:NO];
    
    return [self emailForSignal:racSignal];
}

-(RACSignal*) refreshImportantFolder:(NSInteger)baseFolder user:(UserSettings*)user
{
    // Get the IMAP Sync Service for this user's account
    ImapSync *imapSyncService = [ImapSync sharedServices:user];
    
    NSUInteger folderIndex = [user numFolderWithFolder:FolderTypeWith(baseFolder, 0)];
    
    RACSignal *racSignal = [imapSyncService runFolder:folderIndex
                                            fromStart:YES
                                           gettingAll:NO];
    
    return [self emailForSignal:racSignal];
}

-(RACSignal*) syncFoldersUser:(UserSettings*)user;
{
    // Get the IMAP Sync Service for this user's account
    ImapSync *imapSyncService = [ImapSync sharedServices:user];
    
    RACSignal *racSignal = [imapSyncService runFolder:-1
                                            fromStart:NO
                                           gettingAll:YES];
    
    return [self emailForSignal:racSignal];
}

-(RACSignal*) syncInboxFoldersBackground
{
    NSMutableArray* newEmailsSignalsArray = [[NSMutableArray alloc]init];

    for (UserSettings* user in [AppSettings getSingleton].users) {
        
        if (user.isDeleted) {
            continue;  // Don't do anything with a User that is deleted
        }
    //for (NSInteger accountIndex = 0 ; accountIndex < [AppSettings numActiveAccounts];accountIndex++) {
        
        [ImapSync runInboxUnread:user];
        
        NSInteger inboxFolderIndex = [user inboxFolderNumber];
        
        // Get the IMAP Sync Service for this user's account
        ImapSync *imapSyncService = [ImapSync sharedServices:user];
        
        RACSignal *racSignal = [imapSyncService runFolder:inboxFolderIndex
                                                fromStart:YES
                                               gettingAll:NO];
        
        RACSignal *emailRacSignal = [self emailForSignal:racSignal];
        
        [newEmailsSignalsArray addObject:emailRacSignal];
    }
    
    return [RACSignal merge:newEmailsSignalsArray];
}

#pragma mark - Search for Text and Person via the IMAP Sync Service

-(RACSignal*) searchText:(NSString*)text user:(UserSettings*)user
{
    // Get the IMAP Sync Service for this user's account
    ImapSync *imapSyncService = [ImapSync sharedServices:user];
    
    RACSignal *racSignal = [imapSyncService runSearchText:text];

    return [self emailForSignal:racSignal];
}

-(RACSignal*) searchPerson:(Person*)person user:(UserSettings*)user
{
    // Get the IMAP Sync Service for this user's account
    ImapSync *imapSyncService = [ImapSync sharedServices:user];
    
    RACSignal *racSignal = [imapSyncService runSearchPerson:person];
    
    return [self emailForSignal:racSignal];
}

#warning need to understand what this is doing ...
-(RACSignal*) emailForSignal:(RACSignal*)signal
{
    return  [signal map:^(Mail* email) {
        return email;
    }];
}

// MARK: - Update and Retrieve Sync State
-(NSInteger)_getAccountCount
{
    // The "All messages" UserSettings does not have an associated
    // Account record, so we subtract one from the user count
    return [AppSettings getSingleton].users.count - 1;
}


-(NSMutableArray *)_folderStatesForAccountNumber:(NSInteger)accountNum
{
    NSInteger accountCount = [self _getAccountCount];
    
    // Account index is 0 based
    DDAssert(accountNum<=accountCount,@"Account Number must be <= %ld",(long)accountCount);
    
    return self.syncStates[accountNum][FOLDER_STATES_KEY];
}

// Return the number of folders in the account from the local local Sync State
-(NSInteger) folderCount:(NSInteger)accountNum
{
    
    NSMutableArray* folderStates = [self _folderStatesForAccountNumber:accountNum];
	
    return [folderStates count];
}

// Given an account and a folder in that account,
// return a mutable COPY of its Folder State dictionary from the local Sync States
-(NSMutableDictionary*) retrieveState:(NSInteger)folderNum accountNum:(NSInteger)accountNum
{
    NSMutableArray* folderStates = [self _folderStatesForAccountNumber:accountNum];
	
	if (folderNum >= [folderStates count]) {
		return nil;
	}
	
	return [folderStates[folderNum] mutableCopy];
}

#pragma mark - Folder State Keyed Value "Accessors"

-(id)_folderStateValueForKey:(NSString *)key account:(NSInteger)accountNum folder:(NSInteger)folderNum
{
    DDAssert(key, @"Key argument must exist");
    
    NSMutableDictionary* folderState = [self retrieveState:folderNum accountNum:accountNum];
    if ( folderState == nil ) {
        DDLogError(@"Cannot Retrieve State for folder=%ld account=%ld",(long)folderNum,(long)accountNum);
        return nil;
    }
    
    id folderStateValue = folderState[kFolderStateFolderPathKey];
    if ( folderStateValue == nil ) {
        DDLogError(@"Key \"%@\" not found in Folder State for folder %ld in account %ld",
                   kFolderStateFolderPathKey,(long)folderNum,(long)accountNum);
        return nil;
    }
    
    return folderStateValue;
}

-(NSInteger)retrieveLastEndedFromFolderState:(NSInteger)folderNum accountNum:(NSInteger)accountNum
{
    id valForKey = [self _folderStateValueForKey:kFolderStateLastEndedKey
                                        account:accountNum
                                         folder:folderNum];
    if ( valForKey == nil )
    {
        return -1;
    }
    
    NSInteger lastEnded = (NSInteger)valForKey;
    
    DDLogDebug(@"FolderState[%@] returning \"%ld\"",kFolderStateLastEndedKey,(long)lastEnded);
                           
    return lastEnded;
   
}
-(NSString *)retrieveFolderPathFromFolderState:(NSInteger)folderNum accountNum:(NSInteger)accountNum
{
    id valForKey = [self _folderStateValueForKey:kFolderStateFolderPathKey
                                        account:accountNum
                                         folder:folderNum];
    if ( valForKey == nil )
    {
        return nil;
    }

    NSString *folderPath = (NSString*)valForKey;
    
    DDLogDebug(@"FolderState[\"%@\"] returns \"%@\"",kFolderStateFolderPathKey,folderPath);
    
    return folderPath;
}

#pragma mark - Add account state

// Add a New account Sync State entry
-(void) addAccountState
{
    NSInteger numAccounts = [self _getAccountCount];
	
    NSMutableDictionary* props = [self _newSyncStateProperties];
    
    if (numAccounts == 1) {
        self.syncStates [0] = props;

        [self _writeSyncStateToFileForAccount:0L];
    }
    
	[self.syncStates addObject:props];
    
    [self _writeSyncStateToFileForAccount:numAccounts];
}


-(void) addNewStateForFolder:(MCOIMAPFolder*)folder named:(NSString*)folderName forAccount:(NSUInteger)accountNum
{
    NSDictionary* folderState = @{ kFolderStateAccountNumberKey : @(accountNum),
                                   kFolderStateFolderDisplayNameKey: folderName,
                                   kFolderStateFolderPathKey:folder.path,
                                   kFolderStateDeletedKey:@false,
                                   kFolderStateFullSyncKey:@false,
                                   kFolderStateLastEndedKey:@0,
                                   kFolderStateFolderFlagsKey:@(folder.flags),
                                   kFolderStateEmailCountKey:@(0)
                                   };
    
    NSMutableDictionary *accountStates = self.syncStates[accountNum];
    NSMutableArray *accountFolderStates = accountStates[FOLDER_STATES_KEY];
    
    NSMutableDictionary *folderStates = [NSMutableDictionary dictionaryWithDictionary:folderState];
    [accountFolderStates addObject:folderStates];
    
    [self _writeSyncStateToFileForAccount:accountNum];
}

-(BOOL) isFolderDeletedLocally:(NSInteger)folderNum accountNum:(NSInteger)accountNum
{
    NSMutableDictionary *accountStates = self.syncStates[accountNum];
    NSMutableArray *accountFolderStates = accountStates[FOLDER_STATES_KEY];
    NSMutableDictionary *folderStates = accountFolderStates[folderNum];
	
	NSNumber* y =  folderStates[kFolderStateDeletedKey];
	
	return (y == nil) || [y boolValue];
}


-(void) markFolderDeleted:(NSInteger)folderNum accountNum:(NSInteger)accountNum
{
    NSMutableDictionary *accountStates = self.syncStates[accountNum];
    NSMutableArray *accountFolderStates = accountStates[FOLDER_STATES_KEY];
    NSMutableDictionary *folderStates = accountFolderStates[folderNum];
    
    NSNumber *folderDeleted = @(YES);
    
    [folderStates setValue:folderDeleted forKey:kFolderStateDeletedKey];

    [self _writeSyncStateToFileForAccount:accountNum];
}

-(void) persistState:(NSMutableDictionary*)data forFolderNum:(NSInteger)folderNum accountNum:(NSInteger)accountNum
{
    NSMutableDictionary *accountStates = self.syncStates[accountNum];
    NSMutableArray *accountFolderStates = accountStates[FOLDER_STATES_KEY];
    
    accountFolderStates[folderNum] = data;
    
    [self _writeSyncStateToFileForAccount:accountNum];
}

// MARK: - local function to write out Sync State

-(void)_writeSyncStateToFileForAccount:(NSInteger)accountNum
{
    NSString *fileName = [NSString stringWithFormat:SYNC_STATE_FILE_NAME_TEMPLATE, (long)accountNum];
    
    NSString *filePath = [StringUtil filePathInDocumentsDirectoryForFileName:fileName];
    
    if ( ![self.syncStates[accountNum] writeToFile:filePath atomically:YES] ) {
        
        DDLogError(@"Error: Could not save account %ld Sync State to \"%@\"",
                   (long)accountNum,filePath);
        return;
    }
    
    DDLogInfo(@"Saved account %ld Sync State to \"%@\"",(long)accountNum,fileName);
}


// syncStates ISA mutable array, indexed by account number,
//      returning accountStates
// accountStates ISA mutable dictionary,
//      in which the key "folderStates" returns accountFolderStates
// accountFolderStates ISA mutable array, indexed by folder number,
//      returning folderStates
// folderStates is a mutable dictionary,
//      in which the key "deleted" returns a BOOL folderDeleted
//
-(NSString *)description
{
    NSInteger acntCount = self.syncStates.count;
    
    NSMutableString *desc = [NSMutableString stringWithFormat:@"SyncStates has %ld accounts:\n",(long)acntCount];
    
    for (NSInteger acntNum = 0; acntNum < acntCount; acntNum++ ) {
        
        NSMutableDictionary *acntStates = self.syncStates[acntNum];
        
        DDAssert(acntStates,@"acntStates must exist");
        
        NSMutableArray *acntFolderStates = acntStates[FOLDER_STATES_KEY];
        
        DDAssert(acntFolderStates,@"acntStates must exist");
        
        NSInteger fldrCount = acntFolderStates.count;
        
        [desc appendFormat:@"\taccount[%ld] has %ld folders:\n",
                                        (long)acntNum,(long)fldrCount];
        
        for (NSInteger fldrNum = 0; fldrNum < fldrCount; fldrNum++ ) {
            
            NSMutableDictionary *folderStates = acntFolderStates[fldrNum];

//#define kFolderStateAccountNumberKey        @"accountNum"
//#define kFolderStateFolderDisplayNameKey    @"folderDisplayName"    // used anywhere??
//#define kFolderStateFolderPathKey           @"folderPath"
//#define kFolderStateDeletedKey              @"deleted"
//#define kFolderStateFullSyncKey             @"fullsynced"
//#define kFolderStateLastEndedKey            @"lastended"            // Last Folder Synced
//#define kFolderStateFolderFlagsKey          @"flags"                // where used?
//#define kFolderStateEmailCountKey           @"emailCount"
            
            NSString *folderName = folderStates[kFolderStateFolderDisplayNameKey];
            
            NSInteger folderMsgCount = [folderStates[kFolderStateEmailCountKey] integerValue];
        
            NSNumber* y = folderStates[kFolderStateDeletedKey];
            
            BOOL folderDeleted = (y == nil) || [y boolValue];
            
            [desc appendFormat:@"\t\tfolder[%ld] \"%@\" has %ld messages",
             (long)fldrNum,folderName,(long)folderMsgCount];
            
            if ( folderDeleted ) {
                [desc appendString:@" (DELETED)"];
            }
            [desc appendString:@"\n"];
        }
    }
    return desc;
}


@end
