//
//  Persons.m
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 13/08/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "Persons.h"
#import "UserSettings.h"
#import "UIGlobal.h"
#import "Accounts.h"
#import <AddressBook/AddressBook.h>
#import "MyLabel.h"
#import "UIView+RenderViewToImage.h"
#import <CommonCrypto/CommonDigest.h>
#import <AvailabilityMacros.h>

@interface Persons ()

@property (nonatomic, strong) NSMutableArray* alls;
@property (nonatomic, strong) NSMutableArray* allsNeg;
@property (nonatomic, strong) NSDictionary* spamPics;


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
    
    NSString *path = [[[NSBundle mainBundle] URLForResource:@"pics" withExtension:@"json"] path];
    NSData* spamPicsData = [[NSFileManager defaultManager] contentsAtPath:path];
    self.spamPics = [NSJSONSerialization JSONObjectWithData:spamPicsData options:0 error:nil];
    
    CNContactStore* store = [[CNContactStore alloc] init];

    if ([CNContactStore authorizationStatusForEntityType:CNEntityTypeContacts] == CNAuthorizationStatusAuthorized) {
        [self loadContacts:store];
    }
    else if ([CNContactStore authorizationStatusForEntityType:CNEntityTypeContacts] == CNAuthorizationStatusNotDetermined) {
        [store requestAccessForEntityType:CNEntityTypeContacts
                        completionHandler:^(BOOL granted, NSError* _Nullable error) {
                            if (granted) {
                                if (error) {
                                    CCMLog(@"Error reading Address Book: %@", error.description);
                                }
                                [self loadContacts:store];
                            }
                        }];
    }

    self.allsNeg = [NSMutableArray arrayWithCapacity:6];
    [self.allsNeg addObject:[[Person alloc] init]];
        
    return self;
}

-(void) checkSpam:(Person*)p
{
    for (id key in self.spamPics) {
        for (id kkey in self.spamPics[key]) {
            for (id domain in self.spamPics[key][kkey]) {
                NSRegularExpression* regex = [NSRegularExpression regularExpressionWithPattern:domain options:NSRegularExpressionCaseInsensitive error:nil];
                if ([regex matchesInString:p.email options:NSMatchingReportProgress range:NSMakeRange(0, p.email.length)].count) {
                    NSString *path = [[[NSBundle mainBundle] URLForResource:key withExtension:@"png"] path];
                    NSData* spamPicData = [[NSFileManager defaultManager] contentsAtPath:path];
                    p.image = [UIImage imageWithData:spamPicData];
                }
            }
        }
    }
}

-(void) loadContacts:(CNContactStore*)store
{
    if (store != nil) {
        self.alls = [[NSMutableArray alloc]init];
        NSMutableSet* allEmails = [[NSMutableSet alloc]init];

        [store enumerateContactsWithFetchRequest:[[CNContactFetchRequest alloc] initWithKeysToFetch:@[CNContactGivenNameKey, CNContactFamilyNameKey, CNContactEmailAddressesKey,CNContactImageDataKey]] error:nil usingBlock:^(CNContact * _Nonnull contact, BOOL * _Nonnull stop) {
            
            NSArray* emails = contact.emailAddresses;
            
            for (NSUInteger j = 0; j < emails.count; j++) {
                CNLabeledValue* emailLV = emails[j];
                NSString* email = [emailLV value];
                
                if ([allEmails containsObject:email]) {
                    continue;
                }
                
                [allEmails addObject:email];
                
                Person* person = [[Person alloc] init];
                
                if (contact.imageData) {
                    person.image = [UIImage imageWithData:contact.imageData];
                }
                
                NSString* firstName = contact.givenName;
                NSString* lastName =  contact.familyName;
                
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

        }];
    } else {
        CCMLog(@"Error reading Address Book");
    }
}

-(Person*) getPersonWithID:(NSInteger)idx
{
    
    if (idx < 0) {
        return  self.allsNeg[ - idx];
    }
    
    return self.alls[idx];
}

-(NSInteger) indexForEmail:(NSString*)email
{
    Person* p = [Person createWithName:@"" email:email icon:nil codeName:@""];
    
    return [self addPerson:p];
}

-(NSInteger) addPerson:(Person*)person
{
    NSInteger idx = [self indexForPerson:person];
    
    if (idx == NSNotFound || idx == -NSNotFound) {
        
        if (person.email && !person.image) {
            [[Persons sharedInstance] checkSpam:person];
        }
        
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
    
    
    for (int i = 0; i < self.alls.count; i++) {
    //for (Person* p in tmp) {
        Person* p = self.alls[i];
        if (p.email.length > 0 && [p.email rangeOfString:@"@"].location != NSNotFound) {
            [res addObject:p];
        }
    }

    /*for (Person* p in self.allsNeg) {
        if (p.email.length > 0 && [p.email rangeOfString:@"@"].location != NSNotFound) {
            [res addObject:p];
        }
    }*/
    
    return res;
}

-(NSInteger) indexForPerson:(Person*)p
{
    NSInteger idx = [self.allsNeg indexOfObject:p];
    
    if (idx == NSNotFound) {
        return [[self.alls copy] indexOfObject:p];
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
    
    if (!name) {
        p.name = mail;
    }
    
    if (!codeName) {
        p.codeName = [[mail substringToIndex:3] uppercaseString];
    }
    
    
    p.isGeneric = [p hasGeneriEmail];

    if (p.isGeneric) {
        NSString* partOne = [p.email componentsSeparatedByString:@"@"][1];

        NSString* cN = [partOne uppercaseString];
        cN = [cN stringByReplacingOccurrencesOfString:@" " withString:@""];
        cN = [cN substringToIndex:(cN.length < 3)?cN.length:3];
        
        p.codeName = cN;
    }
    
    if (UIApplicationStateBackground != [UIApplication sharedApplication].applicationState && mail) {
    NSURL* url = [p gravatarURL:mail];
    
    NSURLRequest *request = [NSURLRequest
                             requestWithURL:url
                             cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData
                             timeoutInterval:0.f];
    
    NSURLSession *session = [NSURLSession sharedSession];
    
    NSURLSessionDownloadTask *downloadTask = [session downloadTaskWithRequest:request
                                                            completionHandler:
                                              ^(NSURL *location, NSURLResponse *response, NSError *error) {
                                                  NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *) response;

                                                  if (!error && httpResponse.statusCode != 404) {
                                                      NSString *documentsPath = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
                                                      NSURL *documentsDirectoryURL = [NSURL fileURLWithPath:documentsPath];
                                                      NSURL *documentURL = [documentsDirectoryURL URLByAppendingPathComponent:[response
                                                                                                                           suggestedFilename]];
                                                      [[NSFileManager defaultManager] moveItemAtURL:location
                                                                                          toURL:documentURL
                                                                                          error:nil];
                                                      
                                                      NSString* fP = [NSString stringWithFormat:@"%@/%@",documentsPath,[response suggestedFilename]];
                                                    if ([[NSFileManager defaultManager] fileExistsAtPath:fP]) {
                                                          p.image = [UIImage imageWithContentsOfFile:fP];
                                                    }
                                                  }
                                              }];
    
            [downloadTask resume];
    }
    
    [[Persons sharedInstance] addPerson:p];
    
    return p;
}

- (NSURL *)gravatarURL:(NSString *)email {
    NSMutableString *gravatarPath = [NSMutableString stringWithFormat:@"http://gravatar.com/avatar/%@?s=%d&r=pg&d=404", [self createMD5:email], 66];
    
    return [NSURL URLWithString:gravatarPath];
}

-(void) linkToAccount:(Account*)account
{
    self.userAccount = account;
}

-(UIImageView*) badgeViewImage
{
    UIImageView* iv = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 33, 33)];

    if (self.userAccount || self.image == nil) {
        
        MyLabel* perso = [[MyLabel alloc] initWithFrame:CGRectMake(0, 0, 33, 33)];
        perso.backgroundColor = [UIGlobal noImageBadgeColor];
        
        if (self.userAccount != nil) {
            perso.backgroundColor = self.userAccount.user.color;
        }
        
        perso.isColorLocked = YES;
        
        perso.text = self.codeName;
        perso.textAlignment = NSTextAlignmentCenter;
        perso.textColor = [UIColor whiteColor];
        perso.layer.cornerRadius = 16.5;
        perso.layer.masksToBounds = YES;
        perso.font = [UIFont systemFontOfSize:12];
        
        UIImage *imageFromLabel;
        CGSize size = perso.frame.size;
        UIGraphicsBeginImageContextWithOptions(size, NO, 0);
        [perso.layer renderInContext:UIGraphicsGetCurrentContext()];
        imageFromLabel = UIGraphicsGetImageFromCurrentImageContext();
        UIGraphicsEndImageContext();
        
        iv.image = imageFromLabel;
    }
    else {
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
            iv.contentMode = UIViewContentModeScaleAspectFit;
        }
    }

    iv.layer.cornerRadius = 16.5;
    iv.layer.masksToBounds = YES;
    
    return iv;
}

-(UIView*) badgeView
{
    if (self.userAccount || self.image == nil) {
        
        MyLabel* perso = [[MyLabel alloc] initWithFrame:CGRectMake(0, 0, 33, 33)];
        perso.backgroundColor = [UIGlobal noImageBadgeColor];
        
        if (self.userAccount != nil) {
            perso.backgroundColor = self.userAccount.user.color;
        }
       
        perso.isColorLocked = YES;
        
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

-(UIView*) doubleBadgeView
{
    if (self.userAccount || self.image == nil) {
        
        MyLabel* perso = [[MyLabel alloc] initWithFrame:CGRectMake(0, 0, 66, 66)];
        perso.backgroundColor = [UIGlobal noImageBadgeColor];
        
        if (self.userAccount != nil) {
            perso.backgroundColor = self.userAccount.user.color;
        }
        
        perso.isColorLocked = YES;
        
        perso.text = self.codeName;
        perso.textAlignment = NSTextAlignmentCenter;
        perso.textColor = [UIColor whiteColor];
        perso.layer.cornerRadius = 33;
        perso.layer.masksToBounds = YES;
        perso.font = [UIFont systemFontOfSize:24];
        
        return perso;
    }
    else {
        UIImageView* iv = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, 66, 66)];
        
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
                iv.layer.cornerRadius = 33;
                iv.layer.masksToBounds = YES;
                
                return iv;
            }
        }
        else {
            iv.image = self.image;
        }
        
        
        iv.contentMode = UIViewContentModeScaleAspectFill;
        iv.layer.cornerRadius = 33;
        iv.layer.masksToBounds = YES;
        
        return iv;
    }
}

-(BOOL) hasGeneriEmail
{
    NSString* partOne = [self.email componentsSeparatedByString:@"@"][0];
    
    if ([partOne containsString:@"notify"]) {
        return YES;
    }
    if ([partOne containsString:@"notifications"]) {
        return YES;
    }
    if ([partOne containsString:@"member"]) {
        return YES;
    }
    if ([partOne containsString:@"no-reply"]) {
        return YES;
    }
    if ([partOne containsString:@"noreply"]) {
        return YES;
    }
    
    if ([self.name containsString:@" via "] || [self.name containsString:@" (via "]) {
        return YES;
    }
    
    return NO;
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

- (NSString *)createMD5:(NSString *)email {
    const char *cStr = [_email UTF8String];
    unsigned char digest[16];
    
    CC_MD5(cStr, (int)strlen(cStr), digest);
    
    NSMutableString *emailMD5 = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    
    for(int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
        [emailMD5 appendFormat:@"%02x", digest[i]];
    }
    
    return  emailMD5;
}

#pragma mark - object description
- (NSString *)description
{
    NSMutableString *desc = [NSMutableString string];
    
    [desc appendString:@"\n --- Person --- \n"];
    
    [desc appendFormat:@"\tName       = \"%@\"\n",self.name];
    [desc appendFormat:@"\tCodename   = \"%@\"\n",self.codeName];
    [desc appendFormat:@"\tEmail      = \"%@\"\n",self.email];
    [desc appendFormat:@"\tIs Generic = %@\n",(self.isGeneric?@"TRUE":@"FALSE")];
    [desc appendFormat:@"\tImage Data:\n%@",[self.imageData description]];
    
    [desc appendString:@" --- End Person ---\n"];
    
    return desc;
}

@end
