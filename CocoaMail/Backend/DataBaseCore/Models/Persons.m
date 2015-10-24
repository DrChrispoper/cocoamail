//
//  Persons.m
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 13/08/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "Persons.h"

#import "UIGlobal.h"
#import "Accounts.h"
#import <AddressBook/AddressBook.h>


@interface Persons ()

@property (nonatomic, strong) NSMutableArray* alls;
@property (nonatomic, strong) NSMutableArray* allsNeg;


@end


@interface Person ()

@property (nonatomic, strong) UIImage* image;
@property (nonatomic, weak) Account* userAccount;


@end

@import Contacts;

@implementation Persons

+(Persons*) sharedInstance
{
    static dispatch_once_t once;
    static Persons * sharedInstance;
    
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    
    return sharedInstance;
}

-(instancetype) init
{
    self = [super init];
    
    self.alls = [[NSMutableArray alloc]init];
    
    CNContactStore* store = [[CNContactStore alloc] init];

        if ([CNContactStore authorizationStatusForEntityType:CNEntityTypeContacts] == CNAuthorizationStatusNotDetermined) {
            
            [store requestAccessForEntityType:CNEntityTypeContacts completionHandler:^(BOOL granted, NSError* _Nullable error) {
                                                         if (granted) {
                                                             if (error) {
                                                                 CCMLog(@"Error reading Address Book: %@", error.description);
                                                             }
                                                             [self loadContacts:store];
                                                         }
                                                    }];
        } else if ([CNContactStore authorizationStatusForEntityType:CNEntityTypeContacts] == CNAuthorizationStatusAuthorized) {
            [self loadContacts:store];
        }
    

    self.allsNeg = [NSMutableArray arrayWithCapacity:6];
    [self.allsNeg addObject:[[Person alloc] init]];
        
    return self;
}

-(void) loadContacts:(CNContactStore*)store
{
    if (store != nil) {
        NSArray* allContacts = [store unifiedContactsMatchingPredicate:[CNContact predicateForContactsMatchingName:@""] keysToFetch:@[CNContactGivenNameKey, CNContactFamilyNameKey, CNContactEmailAddressesKey,CNContactImageDataKey] error:nil];
        
        NSMutableSet* allEmails = [[NSMutableSet alloc]initWithCapacity:[allContacts count]];
        self.alls = [[NSMutableArray alloc]initWithCapacity:[allContacts count]];
        
        for (NSUInteger i = 0; i < [allContacts count]; i++) {
            CNContact* contactPerson = allContacts[i];
            NSArray* emails = contactPerson.emailAddresses;
            
            for (NSUInteger j = 0; j < emails.count; j++) {
                CNLabeledValue* emailLV = emails[j];
                NSString* email = [emailLV value];
                
                if ([allEmails containsObject:email]) {
                    continue;
                }
                
                [allEmails addObject:email];
                
                Person* person = [[Person alloc] init];
                
                if (contactPerson.imageData) {
                    person.image = [UIImage imageWithData:contactPerson.imageData];
                }
                
                NSString* firstName = contactPerson.givenName;
                NSString* lastName =  contactPerson.familyName;
                
                NSString* fullName = [NSString stringWithFormat:@"%@ %@", firstName, lastName];
                
                if ([fullName isEqualToString:@" "]) {
                    fullName = email;
                }

                person.name = fullName;
                
                NSString* codeName = [fullName uppercaseString];
                codeName = [codeName stringByReplacingOccurrencesOfString:@" " withString:@""];
                codeName = [codeName substringToIndex:(codeName.length < 3)?codeName.length:3];
                
                person.codeName = codeName;
                person.email = email;
                
                [self.alls addObject:person];
            }
        }
    } else {
        CCMLog(@"Error reading Address Book");
    }
}

-(Person*) getPersonID:(NSInteger)idx
{
    
    if (idx < 0) {
        return  self.allsNeg[ - idx];
    }
    
    return self.alls[idx];
}

-(NSInteger) addPerson:(Person*)person
{
    NSInteger idx = [self indexForPerson:person];
    
    if (idx == NSNotFound || idx == -NSNotFound) {
        [self.alls addObject:person];
        
        return (self.alls.count - 1);
    }

    return idx;
}

-(void) registerPersonWithNegativeID:(Person*)p
{
    [self.allsNeg addObject:p];
}

-(NSArray*) allPersons
{
    NSMutableArray* res = [[NSMutableArray alloc] initWithCapacity:self.alls.count + self.allsNeg.count];
    
    for (Person* p in self.alls) {
        if (p.email.length > 0 && [p.email rangeOfString:@"@"].location != NSNotFound) {
            [res addObject:p];
        }
    }

    for (Person* p in self.allsNeg) {
        if (p.email.length > 0 && [p.email rangeOfString:@"@"].location != NSNotFound) {
            [res addObject:p];
        }
    }
    
    return res;
}

-(NSInteger) indexForPerson:(Person*)p
{
    NSInteger idx = [self.allsNeg indexOfObject:p];
    
    if (idx == NSNotFound) {
        return [self.alls indexOfObject:p];
    }
    
    return -idx;
}


@end

@implementation Person

+(Person*) createWithName:(NSString*)name email:(NSString*)mail icon:(UIImage*)icon codeName:(NSString*)codeName
{
    Person* p = [[Person alloc] init];
    
    p.name = name;
    p.image = icon;
    p.codeName = codeName;
    p.email = mail;
    
    [[Persons sharedInstance] addPerson:p];
    
    return p;
}

-(void) linkToAccount:(Account*)account
{
    self.userAccount = account;
}

-(UIView*) badgeView
{
    if (self.image == nil) {
        
        UILabel* perso = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 33, 33)];
        perso.backgroundColor = [UIGlobal noImageBadgeColor];
        
        if (self.userAccount != nil) {
            perso.backgroundColor = self.userAccount.userColor;
        }
        
        perso.text = self.codeName;
        perso.textAlignment = NSTextAlignmentCenter;
        perso.textColor = [UIColor whiteColor];
        perso.layer.cornerRadius = 16.5;
        perso.layer.masksToBounds = YES;
        perso.font = [UIFont systemFontOfSize:12];
        
        return perso;
    }
    else {
        UIImageView* iv = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 33, 33)];
        
        if ([self isFakePerson]) {
            if (self.email == nil) {
                // fake dot person
                iv.image = [self.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
                iv.tintColor = [UIGlobal noImageBadgeColor];
            }
            else {
                // cocoamail person
                iv.image = self.image;
                iv.contentMode = UIViewContentModeScaleAspectFit;
                
                iv.backgroundColor = [UIColor colorWithRed:1. green:.69 blue:.0 alpha:1.];
                iv.layer.cornerRadius = 16.5;
                iv.layer.masksToBounds = YES;
                
                return iv;
            }
        }
        else {
            iv.image = self.image;
        }
        
        
        iv.contentMode = UIViewContentModeScaleAspectFill;
        iv.layer.cornerRadius = 16.5;
        iv.layer.masksToBounds = YES;
        
        return iv;
    }
}

-(BOOL) isFakePerson
{
    return (self.codeName==nil /*&& self.email==nil*/ && self.name==nil);
}

-(BOOL) isEqual:(id)object
{
    if (object == self) {
        return YES;
    }
    
    if (!object || ![object isKindOfClass:[self class]]) {
        return NO;
    }
    
    return [self isEqualToPerson:object];
}

-(BOOL) isEqualToPerson:(Person*)aPerson
{
    if (self == aPerson) {
        return YES;
    }
    
    if (![(id)[self email] isEqualToString:[aPerson email]]) {
        return NO;
    }
    
    return YES;
}


@end
