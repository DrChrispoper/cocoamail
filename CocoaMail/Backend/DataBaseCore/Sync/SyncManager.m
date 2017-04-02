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

// MARK: - Load each SyncSettings from "sync_state_<index>.plist", one per UserSetting.

-(void)_loadSyncSettingsForAllUserAccounts
{
    NSArray<UserSettings*>* allUserSettings = [AppSettings getSingleton].users;
    
    // Get the persistent state
    self.syncStates = [NSMutableArray arrayWithCapacity:allUserSettings.count];
    
    // For each UserSettings referenced by the AppSettings singleton
    for (UserSettings* user in allUserSettings) {
        
        if (user.isAll) {

            // This UserSettings is for the special All Accounts Mail view
            // Insert and empty "record" at the start of the Sync States mutable array
            [self.syncStates insertObject:[NSMutableDictionary dictionaryWithCapacity:1] atIndex:0];
            
            // TODO: this assumes only one isAll UserSettings
            
            continue; // next UserSettings
        }
        
        if (user.isDeleted) {
            // This UserSetting's Account has been deleted
            // Add and empty "record" for the Sync States mutable array
            [self.syncStates addObject:[NSMutableDictionary dictionaryWithCapacity:1]];
            
            // TODO: this assumes only one isDeleted UserSettings
            
            continue; // next UserSettings
        }
        
        // TODO: Does this loop assume that the isAll and isDeleted UserSettings occur before all the other UserSettings?
        
        // This UserSettings is for a regular IMAP Account
        NSString* syncStateFullPathFilename = [self _syncStateFullPathFilenameForUser:user];
        
        // If this user's Sync Settings preferences file exists ...
        if ([[NSFileManager defaultManager] fileExistsAtPath:syncStateFullPathFilename]){
            DDLogDebug(@"Loading Sync data file \"%@\" for account num %@",[self _syncStateFilenameForUser:user],@(user.accountNum));
            
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

- (NSMutableDictionary *)_newSyncStateProperties
{
    return [[NSMutableDictionary alloc] initWithObjectsAndKeys:
                @"2",                   @"__version",
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

#pragma mark - Folder IMAP Sync Requests

-(RACSignal*) syncActiveFolderFromStart:(BOOL)isFromStart user:(UserSettings*)user
{
    DDLogInfo(@"ENTERED, Sync ACTIVE Folder with IMAP Server. fromStart=%@ forUser=%@",
              (isFromStart?@"YES":@"NO"),user.username);
    
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
    DDLogInfo(@"ENTERED, Sync IMPORTANT Folder with IMAP Server. folder=%@ forUser=%@",
              [user.linkedAccount baseFolderType:baseFolder],user.username);
    
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
    DDLogInfo(@"ENTERED, Sync ALL Folders with IMAP Server. forUser=%@",
              user.username);
    
    // Get the IMAP Sync Service for this user's account
    ImapSync *imapSyncService = [ImapSync sharedServices:user];
    
    RACSignal *racSignal = [imapSyncService runFolder:-1
                                            fromStart:NO
                                           gettingAll:YES];
    
    return [self emailForSignal:racSignal];
}

-(RACSignal*) syncInboxFoldersBackground
{
    DDLogInfo(@"ENTERED, Sync ALL Folders for ALL Users IN BACKGROUND with IMAP Server.");

    NSMutableArray* newEmailsSignalsArray = [[NSMutableArray alloc]init];

    for (UserSettings* user in [AppSettings getSingleton].users) {
        
        if (user.isDeleted) {
            continue;  // Don't do anything with a User that is deleted
        }
    //for (NSInteger accountIndex = 0 ; accountIndex < [AppSettings numActiveAccounts];accountIndex++) {
        
        [ImapSync runInboxUnread:user completed:^{}];     // Why call this, as it has no completion block
        
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

#pragma mark - Search for Messaage Text / Person Name via the IMAP Sync Service

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

-(RACSignal*) emailForSignal:(RACSignal*)signal
{
    return  [signal map:^(Mail* email) {
        return email;
    }];
}

// MARK: - Get number of UserSettings / Accounts / Sync Settings (internal function)

-(NSInteger)_getAccountCount
{
    // The "All messages" UserSettings does not have an associated
    // Account record, so we subtract one from the user count
    return [AppSettings getSingleton].users.count - 1;
}


// MARK: - Return Sync States for an Account

-(NSMutableArray *)_folderStatesForAccountNumber:(NSInteger)accountNum
{
    NSInteger accountCount = [self _getAccountCount];
    
    // Account index is 0 based (or 999)
    DDAssert(accountNum<=accountCount || accountNum==999 ,@"Account Number must be <= %ld OR equal to 999",(long)accountCount);
    
    NSDictionary *accountStates = self.syncStates[accountNum];
    
    DDAssert(accountStates,@"Account States must exist.");
    
    NSMutableArray *accountFolderStates = accountStates[FOLDER_STATES_KEY];
    
    DDAssert(accountFolderStates, @"Account Folder States must exist.");
    
    return accountFolderStates;
}

// MARK: - Return Sync States for an Account and Folder

-(NSMutableDictionary*) _folderStatesForAccountNumber:(NSInteger)accountNum folderNumber:(NSInteger)folderNum
{
    NSArray *accountFolderStates = [self _folderStatesForAccountNumber:accountNum];
    
    if ( folderNum < 0 || folderNum >= accountFolderStates.count ) {
        return nil;
    }
    
    NSMutableDictionary *folderStates = accountFolderStates[folderNum];
    
    return folderStates;
    
}

// MARK: - Return number of folders in an account

// Return the number of folders in the account from the local local Sync State
-(NSInteger) folderCount:(NSInteger)accountNum
{
    
    NSMutableArray* folderStates = [self _folderStatesForAccountNumber:accountNum];
	
    return [folderStates count];
}

// MARK: - Return a copy of the folderStates for an Account Folder

// Given an account and a folder in that account,
// return a mutable COPY of its Folder State dictionary from the local Sync States
-(NSDictionary*) retrieveState:(NSInteger)folderNum accountNum:(NSInteger)accountNum
{
    NSMutableDictionary* folderStates = [self _folderStatesForAccountNumber:accountNum folderNumber:folderNum];

	return folderStates;
}

// MARK: - SETTERS

-(void)updateMessageCount:(NSInteger)messageCount forFolderNumber:(NSInteger)folderNum andAccountNum:(NSUInteger)accountNum
{
    NSMutableDictionary* syncState = [self _folderStatesForAccountNumber:accountNum folderNumber:folderNum];
    
    @synchronized (syncState) {
        syncState[kFolderStateEmailCountKey] = @(messageCount);
    }
    
    [self _persistState:syncState forFolderNum:folderNum accountNum:accountNum];
}
-(void)updateLastEndedIndex:(NSInteger)lastEIndex forFolderNumber:(NSInteger)folderNum andAccountNum:(NSUInteger)accountNum
{
    NSMutableDictionary* syncState = [self _folderStatesForAccountNumber:accountNum folderNumber:folderNum];
    
    @synchronized (syncState) {
        syncState[kFolderStateLastEndedKey] = @(lastEIndex);
        syncState[kFolderStateFullSyncKey]  = @(lastEIndex == 1);
    }
    
    [self _persistState:syncState forFolderNum:folderNum accountNum:accountNum];
}


// MARK: - Get state for Key for Account Folder

-(id)_folderStateValueForKey:(NSString *)key account:(NSInteger)accountNum folder:(NSInteger)folderNum
{
    DDAssert(key, @"Key argument must exist");
    
    NSDictionary* folderState = [self retrieveState:folderNum accountNum:accountNum];
    if ( folderState == nil ) {
        DDLogError(@"Cannot Retrieve State for folder=%ld account=%ld",(long)folderNum,(long)accountNum);
        return nil;
    }
    
    id folderStateValue = folderState[key];
    if ( folderStateValue == nil ) {
        DDLogError(@"Key \"%@\" not found in Folder State for folder %ld in account %ld",
                   key,(long)folderNum,(long)accountNum);
        return nil;
    }
    
    return folderStateValue;
}

// MARK: - Get "Last Ended" state for Account Folder

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
    
    DDLogVerbose(@"FolderState[%@] returning \"%ld\"",kFolderStateLastEndedKey,(long)lastEnded);
                           
    return lastEnded;
   
}

// MARK: - Get "Folder Path" state for Account Folder

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
    
    DDLogVerbose(@"FolderState[\"%@\"] returns \"%@\"",kFolderStateFolderPathKey,folderPath);
    
    return folderPath;
}

// MARK: - Add an Account Sync State and write all Sync States to file store.

// Add a New account Sync State entry
-(void) addAccountState
{
    NSInteger numAccounts = [self _getAccountCount];
	
    NSMutableDictionary* props = [self _newSyncStateProperties];
    
    if (numAccounts == 1) {
        
        @synchronized (self.syncStates) {
            self.syncStates[0] = props;
        }

        [self _writeSyncStateToFileForAccount:0L];
    }
    
    @synchronized (self.syncStates) {
        [self.syncStates addObject:props];
    }
    
    [self _writeSyncStateToFileForAccount:numAccounts];
}

// MARK: - Add an Account Folder Sync State and write all Sync States to file store.

-(NSInteger) addNewStateForFolder:(MCOIMAPFolder*)folder named:(NSString*)folderName forAccount:(NSUInteger)accountNum
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
    
    NSMutableArray *accountFolderStates = [self _folderStatesForAccountNumber:accountNum];
    
    NSMutableDictionary *folderStates = [NSMutableDictionary dictionaryWithDictionary:folderState];
    
    @synchronized (self.syncStates) {
        [accountFolderStates addObject:folderStates];
    }
    DDLogDebug(@"ADDED Sync State num %ld for new IMAP folder \"%@\"",(long)accountFolderStates.count,folder.path);
    
    [self _writeSyncStateToFileForAccount:accountNum];
    
    NSInteger newFolderStatesIndex = accountFolderStates.count - 1;
    
    return newFolderStatesIndex;   // index of last (new) record
}

// MARK: - Is Folder locally deleted?

-(BOOL) isFolderDeletedLocally:(NSInteger)folderNum accountNum:(NSInteger)accountNum
{
    NSMutableDictionary *folderStates = [self _folderStatesForAccountNumber:accountNum folderNumber:folderNum];
	
	NSNumber* y =  folderStates[kFolderStateDeletedKey];
    
    if ( y == nil ) {
        DDLogWarn(@"isFolderDeletedLocally: fNum=%@ aNum=%@, PROPERTY NOT FOUND.",@(folderNum),@(accountNum));
        return TRUE;
    }
	
    return [y boolValue];  // deleted if deleted property doesn't exist, or is FALSE
}

// MARK: - Mark local folder as deleted

-(void) markFolderDeleted:(NSInteger)folderNum accountNum:(NSInteger)accountNum
{
    NSMutableDictionary *folderStates = [self _folderStatesForAccountNumber:accountNum folderNumber:folderNum];
    
    NSNumber *folderDeleted = @(YES);
    
    @synchronized (self.syncStates) {
        [folderStates setValue:folderDeleted forKey:kFolderStateDeletedKey];
    }

    [self _writeSyncStateToFileForAccount:accountNum];
}

// MARK: - Update the Account Folder sync state and write to file store

-(void) _persistState:(NSMutableDictionary*)data forFolderNum:(NSInteger)folderNum accountNum:(NSInteger)accountNum
{
    NSMutableDictionary *accountStates = self.syncStates[accountNum];
    NSMutableArray *accountFolderStates = accountStates[FOLDER_STATES_KEY];
    
    accountFolderStates[folderNum] = data;
    
    [self _writeSyncStateToFileForAccount:accountNum];
}

// MARK: - local function to write out Sync State

// #warning ERROR RECIEVED: "NSArray was mutated while being enumerated". (enumerated during this file write).

-(void)_writeSyncStateToFileForAccount:(NSInteger)accountNum
{
    NSString *fileName = [NSString stringWithFormat:SYNC_STATE_FILE_NAME_TEMPLATE, (long)accountNum];
    
    NSString *filePath = [StringUtil filePathInDocumentsDirectoryForFileName:fileName];
    
    NSMutableDictionary *accountStates = self.syncStates[accountNum];
    
    DDAssert(accountStates, @"accountStates cannot be nil.");
    
    @synchronized (self.syncStates) {
        
        // TODO: might want to time writing these files
        
        if ( ![accountStates writeToFile:filePath atomically:YES] ) {
            
            DDLogError(@"Error: Could not save account %ld Sync State to \"%@\"",
                       (long)accountNum,filePath);
        }
        else {
            DDLogDebug(@"Saved account %ld Sync State to \"%@\"",(long)accountNum,fileName);
        }
    }

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
