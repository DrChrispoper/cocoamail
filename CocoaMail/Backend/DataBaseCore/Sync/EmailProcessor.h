//
//  EmailProcessor.h
//  CocoaMail
//
//  Created by Christopher Hockley on 20/01/2012.
//  Copyright (c) 2012 Christopher Hockley. All rights reserved.
//

#import <MailCore/MailCore.h>
#import "Email.h"
#import "UidEntry.h"

@interface EmailProcessor : NSObject {
	NSOperationQueue *operationQueue;
	NSDateFormatter *dbDateFormatter;
	NSInteger currentDBNum;
	NSInteger addsSinceTransaction;
	volatile BOOL shuttingDown; // this avoids doing db access while the app is shutting down. It's triggered in ReMailAppDelegate.applicationWillTerminate
	
	id updateSubscriber;	
}

@property (nonatomic, strong) NSOperationQueue *operationQueue;
@property (nonatomic, strong) NSDateFormatter *dbDateFormatter;
@property (nonatomic, strong) id updateSubscriber;
@property (assign) volatile BOOL shuttingDown;

+ (EmailProcessor *)getSingleton;

+ (NSInteger)dbNumForDate:(NSDate *)date;
- (void)switchToDBNum:(NSInteger)dbNum;
- (void)updateFlag:(NSMutableArray *)datas;
- (void)addToFolderWrapper:(UidEntry *)data;
- (void)removeFromFolderWrapper:(NSArray *)datas;
- (void)addEmailWrapper:(Email *)email;
- (void)addEmail:(Email *)email;

@end
