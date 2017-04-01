//
//  SyncManager.h
//  CocoaMail
//
//  Created by Christopher Hockley on 20/01/2012.
//  Copyright (c) 2012 Christopher Hockley. All rights reserved.
//
//  Singleton. SyncManager is the central place for coordinating syncs:
//  - starting syncs if not in progress
//  - registering for sync-related events
//  - persists sync state of sync processes
//
//  However, SyncManager itself has none of the syncing logic.

#import <MailCore/MailCore.h>
#import <ReactiveCocoa/ReactiveCocoa.h>

#define kFolderStateAccountNumberKey        @"accountNum"
#define kFolderStateFolderDisplayNameKey    @"folderDisplayName"    // used anywhere??
#define kFolderStateFolderPathKey           @"folderPath"
#define kFolderStateDeletedKey              @"deleted"
#define kFolderStateFullSyncKey             @"fullsynced"
#define kFolderStateLastEndedKey            @"lastended"            // Last Folder Synced
#define kFolderStateFolderFlagsKey          @"flags"                // where used?
#define kFolderStateEmailCountKey           @"emailCount"

@class UserSettings;
@class Person;

@interface SyncManager : NSObject {    
	// sync-related stuff
//	NSMutableArray <NSMutableDictionary*>* syncStates;
//	BOOL syncInProgress;
}

//@property (nonatomic, weak) id aNewEmailDelegate;

// syncStates ISA mutable array, indexed by account number,
//      returning accountStates
// accountStates ISA mutable dictionary,
//      in which the key "folderStates" returns accountFolderStates
// accountFolderStates ISA mutable array, indexed by folder number,
//      returning folderStates
// folderStates is a mutable dictionary,
//      in which the key "deleted" returns a BOOL folderDeleted
//

// TODO: - Someday make syncStates private to this class, and make all changes via accessors
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary*>* syncStates;
//@property (assign) BOOL syncInProgress;
//@property (assign) BOOL isFromStart;

+(SyncManager*) getSingleton;

//-(RACSignal*) refreshActiveFolder;
-(RACSignal*) syncActiveFolderFromStart:(BOOL)isFromStart user:(UserSettings*)user;
-(RACSignal*) syncFoldersUser:(UserSettings*)user;
-(RACSignal*) refreshImportantFolder:(NSInteger)folder user:(UserSettings*)user;
-(RACSignal*) syncInboxFoldersBackground;

-(RACSignal*) searchPerson:(Person*)person user:(UserSettings*)user;
-(RACSignal*) searchText:(NSString*)text user:(UserSettings*)user;

-(void) addAccountState;
-(NSInteger) addNewStateForFolder:(MCOIMAPFolder*)folder named:(NSString*)folderName forAccount:(NSUInteger)accountNum;

-(NSInteger) folderCount:(NSInteger)accountNum;

// MARK: - getters
-(BOOL) isFolderDeletedLocally:(NSInteger)folderNum accountNum:(NSInteger)accountNum;
-(NSString *)retrieveFolderPathFromFolderState:(NSInteger)folderNum accountNum:(NSInteger)accountNum;
-(NSInteger)retrieveLastEndedFromFolderState:(NSInteger)folderNum accountNum:(NSInteger)accountNum;

-(NSDictionary*) retrieveState:(NSInteger)folderNum accountNum:(NSInteger)accountNum;  // for external getters

// MARK: - setters
-(void)markFolderDeleted:(NSInteger)folderNum accountNum:(NSInteger)accountNum;
-(void)updateMessageCount:(NSInteger)messageCount forFolderNumber:(NSInteger)folderNum andAccountNum:(NSUInteger)accountNum;
-(void)updateLastEndedIndex:(NSInteger)lastEIndex forFolderNumber:(NSInteger)folderNum andAccountNum:(NSUInteger)accountNum;




@end


