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

-(RACSignal*) search:(NSString*)searchText inAccountNum:(NSInteger)accountNum;
-(RACSignal*) senderSearch:(Person*)person inAccountNum:(NSInteger)accountNum;

-(RACSignal*) deleteEmailsInAccountNum:(NSInteger)accountNum;
-(RACSignal*) activeFolderSearch:(Mail*)email inAccountNum:(NSInteger)accountNum;
//-(RACSignal*) threadSearch:(NSString*)thread inAccountNum:(NSInteger)accountNum;
-(RACSignal*) allEmailsDBSearch;

@property (assign) volatile BOOL cancelled; // flag for when we cancel a search op
@property (nonatomic, readwrite,strong) NSOperationQueue* operationQueue;

+(id) getSingleton;
-(void) cancel;

+(NSArray*) dbNumsInAccountNum:(NSInteger)accountNum;

@end
