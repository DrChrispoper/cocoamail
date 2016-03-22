//
//  Draft.h
//  CocoaMail
//
//  Created by Christopher Hockley on 01/03/16.
//  Copyright © 2016 Christopher Hockley. All rights reserved.
//

#import <Foundation/Foundation.h>

@class Mail;

@interface Draft : NSObject

@property NSInteger accountNum;
@property NSMutableArray<NSString*>* toPersons;
@property BOOL isBcc;

@property NSString* transferContent;
@property NSString* fromMailMsgID;

@property NSString* subject;
@property NSString* body;

//ToFetch
@property NSString* msgID;
@property NSDate* datetime;

+(Draft*) newDraftFormCurrentAccount;

-(NSArray*)attachments;

-(void) save;
-(void) deleteDraft;
-(void) appendToSent:(NSString*)rfc822DataFilename;

-(NSString*) rfc822DataTo:(NSArray*)toPersonIDs;
-(Mail*) fromMail;
//-(Mail*) mail;

@end
