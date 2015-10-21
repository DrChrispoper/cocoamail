//
//  UidDBAccessor.h
//  CocoaMail
//
//  Created by Christopher Hockley on 20/01/2012.
//  Copyright (c) 2012 Christopher Hockley. All rights reserved.
//

#import "FMDB.h"


@interface UidDBAccessor : NSObject

@property (nonatomic, strong) FMDatabaseQueue* databaseQueue;

+(id) sharedManager;

-(NSString*) databaseFilepath;
-(void) deleteDatabase;


@end
