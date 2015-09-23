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
	NSMutableArray *syncStates;
	BOOL syncInProgress;
}

@property (nonatomic,weak) id aNewEmailDelegate;
@property (nonatomic,strong) NSMutableArray *syncStates;
@property (assign) BOOL syncInProgress;
@property (assign) BOOL isFromStart;

+(SyncManager*)getSingleton;

//-(RACSignal *) refreshActiveFolder;
-(RACSignal *) syncActiveFolderFromStart:(BOOL)isFromStart;
-(RACSignal *) syncFolders;
-(RACSignal *) refreshImportantFolder:(NSInteger)folder;
-(RACSignal *) syncInboxFoldersBackground;

-(RACSignal *) searchThings:(NSArray*)things;

//Update recorded state
-(NSInteger)folderCount:(NSInteger)accountNum;
-(void)addAccountState;
-(void)addFolderState:(NSDictionary *)data accountNum:(NSInteger)accountNum;
-(BOOL)isFolderDeleted:(NSInteger)folderNum accountNum:(NSInteger)accountNum;
-(void)markFolderDeleted:(NSInteger)folderNum accountNum:(NSInteger)accountNum;
-(void)persistState:(NSMutableDictionary *)data forFolderNum:(NSInteger)folderNum accountNum:(NSInteger)accountNum;
-(NSMutableDictionary*)retrieveState:(NSInteger)folderNum accountNum:(NSInteger)accountNum;
-(NSSet*)retrieveAllDBNumsAccountNum:(NSInteger)accountNum;

@end


