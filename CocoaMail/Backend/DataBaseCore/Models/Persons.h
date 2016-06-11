//
//  Persons.h
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 13/08/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@class Person;
@class Account;


@interface Persons : NSObject

+(Persons*) sharedInstance;

-(Person*) getPersonWithID:(NSInteger)idx;

-(void) registerPersonWithNegativeID:(Person*)p;

-(NSInteger) addPerson:(Person*)person;
-(NSInteger) indexForEmail:(NSString*)email;

@property (nonatomic) NSInteger idxMorePerson;
@property (nonatomic) NSInteger idxCocoaPerson;

-(NSArray*) allPersons;
-(NSInteger) indexForPerson:(Person*)p;


@end


@interface Person : NSObject

@property (nonatomic, strong) NSString* name;
@property (nonatomic, strong) NSString* codeName;
@property (nonatomic, strong) NSString* email;
@property (nonatomic) BOOL isGeneric;
@property (nonatomic, strong) NSMutableData *imageData;

-(void) linkToAccount:(Account*)account;

-(UIView*) badgeView;
-(UIImageView*) badgeViewImage;
-(UIView*) doubleBadgeView;

+(Person*) createWithName:(NSString*)name email:(NSString*)mail icon:(UIImage*)icon codeName:(NSString*)codeName;

-(BOOL) hasGeneriEmail;

@end
