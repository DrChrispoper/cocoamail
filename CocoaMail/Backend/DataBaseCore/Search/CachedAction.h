//
//  CachedAction.h
//  CocoaMail
//
//  Created by Christopher Hockley on 16/07/15.
//  Copyright (c) 2015 CocoaSoft. All rights reserved.
//

#import "UidEntry.h"


@interface CachedAction : NSObject

@property (assign) NSInteger pk;
@property (nonatomic, readwrite) UidEntry* uid;
/// Indexes are: 0 - Move  1 - Delete 2 - Star 3 - Unstar
@property (nonatomic, readwrite) NSInteger actionIndex;
@property (nonatomic, readwrite) NSInteger toFolder;

+(void) tableCheck;
+(BOOL) addAction:(CachedAction*)action;
+(BOOL) addActionWithUid:(UidEntry*)uidEntry actionIndex:(NSInteger)actionIndex toFolder:(NSInteger)folder;
+(BOOL) removeAction:(CachedAction*)action;
+(NSMutableArray*) getActions;
+(NSMutableArray*) getActionsForAccount:(NSInteger)account;

-(void) doAction;


@end
