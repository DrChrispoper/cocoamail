//
//  SearchRunner.h
//  CocoaMail
//
//  Created by Christopher Hockley on 20/01/2012.
//  Copyright (c) 2012 Christopher Hockley. All rights reserved.
//

#import <ReactiveCocoa/ReactiveCocoa.h>
#import "sqlite3.h"

@class Person;
@class Mail;

@interface SearchRunner : NSObject {
	NSOperationQueue* operationQueue;
	volatile BOOL cancelled;
}

-(RACSignal*) search:(NSString*)searchText inAccount:(NSInteger)accountIndex;
-(RACSignal*) senderSearch:(Person*)person inAccount:(NSInteger)accountIndex;

-(RACSignal*) deleteEmailsInAccount:(NSInteger)accountIndex;
-(RACSignal*) activeFolderSearch:(Mail*)email inAccount:(NSInteger)accountIndex;
-(RACSignal*) threadSearch:(NSString*)thread inAccount:(NSInteger)accountIndex;
-(RACSignal*) allEmailsSearch;

@property (assign) volatile BOOL cancelled; // flag for when we cancel a search op
@property (nonatomic, readwrite,strong) NSOperationQueue* operationQueue;

+(id) getSingleton;
-(void) cancel;

+(NSArray*) dbNumsInAccount:(NSInteger)accountIndex;

@end