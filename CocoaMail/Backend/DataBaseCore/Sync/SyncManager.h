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

#import <MailCore/Mailcore.h>
#import <ReactiveCocoa/ReactiveCocoa.h>
#import "Email.h"


@interface SyncManager : NSObject {    
	// sync-related stuff
	NSMutableArray* syncStates;
	BOOL syncInProgress;
}

@property (nonatomic, weak) id aNewEmailDelegate;
@property (nonatomic, strong) NSMutableArray* syncStates;
@property (assign) BOOL syncInProgress;
@property (assign) BOOL isFromStart;

+(SyncManager*) getSingleton;

//-(RACSignal*) refreshActiveFolder;
-(RACSignal*) syncActiveFolderFromStart:(BOOL)isFromStart;
-(RACSignal*) refreshInbox;
-(RACSignal*) syncFolders;
-(RACSignal*) refreshImportantFolder:(NSInteger)folder;
-(RACSignal*) syncInboxFoldersBackground;

-(RACSignal*) searchThings:(NSArray*)things;
-(RACSignal*) searchText:(NSString*)text;

//Update recorded state
-(NSInteger) folderCount:(NSInteger)accountIndex;
-(void) addAccountState;
-(void) addFolderState:(NSDictionary*)data accountIndex:(NSInteger)accountIndex;
-(BOOL) isFolderDeleted:(NSInteger)folderNum accountIndex:(NSInteger)accountIndex;
-(void) markFolderDeleted:(NSInteger)folderNum accountIndex:(NSInteger)accountIndex;
-(void) persistState:(NSMutableDictionary*)data forFolderNum:(NSInteger)folderNum accountIndex:(NSInteger)accountIndex;
-(NSMutableDictionary*) retrieveState:(NSInteger)folderNum accountIndex:(NSInteger)accountIndex;


@end


