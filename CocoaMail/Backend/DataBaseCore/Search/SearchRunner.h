//
//  SearchRunner.h
//  CocoaMail
//
//  Created by Christopher Hockley on 20/01/2012.
//  Copyright (c) 2012 Christopher Hockley. All rights reserved.
//

#import <ReactiveCocoa/ReactiveCocoa.h>
#import "sqlite3.h"
#import "Email.h"


@interface SearchRunner : NSObject {
	NSOperationQueue* operationQueue;
	volatile BOOL cancelled;
}

-(RACSignal*) search:(NSString*)searchText;
-(RACSignal*) senderSearch:(NSArray*)addressess;

-(RACSignal*) activeFolderSearch:(Email*)email;
-(RACSignal*) threadSearch:(NSString*)thread;
-(RACSignal*) allEmailsSearch;

@property (assign) volatile BOOL cancelled; // flag for when we cancel a search op
@property (nonatomic, readwrite,strong) NSOperationQueue* operationQueue;

+(id) getSingleton;
-(void) cancel;

+(NSArray*) dbNumsInAccount:(NSInteger)accountIndex;

@end