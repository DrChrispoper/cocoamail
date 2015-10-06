//
//  CacheDBAccessor.h
//  CocoaMail
//
//  Created by Christopher Hockley on 16/07/15.
//  Copyright (c) 2015 CocoaSoft. All rights reserved.
//

#import "FMDB.h"

@interface CacheDBAccessor : NSObject

@property (nonatomic, strong) FMDatabaseQueue *databaseQueue;

+ (id)sharedManager;

- (NSString *)databaseFilepath;
- (void)deleteDatabase;

@end
