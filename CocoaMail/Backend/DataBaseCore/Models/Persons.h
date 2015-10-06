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

+ (Persons *)sharedInstance;

- (Person *)getPersonID:(NSInteger)idx;

- (void)registerPersonWithNegativeID:(Person *)p;

- (NSInteger)addPerson:(Person *)person;

@property (nonatomic) NSInteger idxMorePerson;
@property (nonatomic) NSInteger idxCocoaPerson;

- (NSArray *)allPersons;
- (NSInteger)indexForPerson:(Person *)p;

@end

@interface Person : NSObject

@property (nonatomic, strong) NSString *name;
@property (nonatomic, strong) NSString *codeName;
@property (nonatomic, strong) NSString *email;

- (void)linkToAccount:(Account *)account;

- (UIView *)badgeView;

+ (Person *)createWithName:(NSString *)name email:(NSString *)mail icon:(UIImage *)icon codeName:(NSString *)codeName;

@end
