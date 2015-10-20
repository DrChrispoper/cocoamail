//
//  PDKeychainBindingsController.m
//  PDKeychainBindingsController
//
//  Created by Carl Brown on 7/10/11.
//  Copyright 2011 PDAgent, LLC. Released under MIT License.
//

#import "PDKeychainBindingsController.h"
#import <Security/Security.h>

static PDKeychainBindingsController * sharedInstance = nil;

@implementation PDKeychainBindingsController

#pragma mark -
#pragma mark Keychain Access

- (NSString *)serviceName {
    return [[NSBundle mainBundle] bundleIdentifier];
}

- (NSString *)stringForKey:(NSString *)key {
    OSStatus status;
    NSDictionary *query = @{(__bridge id)kSecReturnData:(NSNumber *)kCFBooleanTrue,
                            (__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
                            (__bridge id)kSecAttrAccount:key,
                            (__bridge id)kSecAttrService:[self serviceName]};
    
    CFDataRef stringData = NULL;
    status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&stringData);

    if (status) {
        return nil;
    }
    
    NSString *string = [[NSString alloc] initWithData:(__bridge id)stringData encoding:NSUTF8StringEncoding];
    CFRelease(stringData);

    return string;
}

- (BOOL)storeString:(NSString *)string forKey:(NSString *)key {
    return [self storeString:string forKey:key accessibleAttribute:kSecAttrAccessibleWhenUnlocked];
}

- (BOOL)storeString:(NSString *)string forKey:(NSString *)key accessibleAttribute:(CFTypeRef)accessibleAttribute {
    if (!string)  {
        //Need to delete the Key
        NSDictionary *spec = @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
                               (__bridge id)kSecAttrAccount:key,
                               (__bridge id)kSecAttrService:[self serviceName]};
        
        OSStatus result = SecItemDelete((__bridge CFDictionaryRef)spec);
        
        if (result != 0) {
            CCMLog(@"Could not store(Delete) string. Error was:%i", (int)result);
        }
        
        return !result;
    } else {
        NSData *stringData = [string dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *spec = @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
                               (__bridge id)kSecAttrAccount:key,
                               (__bridge id)kSecAttrService:[self serviceName]};
        
        if (!string) {
            OSStatus result = SecItemDelete((__bridge CFDictionaryRef)spec);
            
            if (result!=0) {
                CCMLog(@"Could not store(Delete) string. Error was:%i", (int)result);
            }
            
            return !result;
        }
        else if ([self stringForKey:key]) {
            NSDictionary *update = @{
                                     (__bridge id)kSecAttrAccessible:(__bridge id)accessibleAttribute,
                                     (__bridge id)kSecValueData:stringData
                                     };
            
            OSStatus result = SecItemUpdate((__bridge CFDictionaryRef)spec, (__bridge CFDictionaryRef)update);
            
            if (result!=0) {
                CCMLog(@"Could not store(Update) string. Error was:%i", (int)result);
            }
            
            return !result;
        } else {
            NSMutableDictionary *data = [NSMutableDictionary dictionaryWithDictionary:spec];
            data[(__bridge id)kSecValueData] = stringData;
            data[(__bridge id)kSecAttrAccessible] = (__bridge id)accessibleAttribute;
            OSStatus result = SecItemAdd((__bridge CFDictionaryRef)data, NULL);
            
            if (result!=0) {
                CCMLog(@"Could not store(Add) string. Error was:%i", ( int)result);
            }
            
            return !result;
        }
    }
}

#pragma mark -
#pragma mark Singleton Stuff

+ (PDKeychainBindingsController *)sharedKeychainBindingsController {
    static dispatch_once_t onceQueue;
    
    dispatch_once(&onceQueue, ^{
        sharedInstance = [[self alloc] init];
    });
    
    return sharedInstance;
}

#pragma mark -
#pragma mark Business Logic

- (PDKeychainBindings *)keychainBindings {
    if (_keychainBindings == nil) {
        _keychainBindings = [[PDKeychainBindings alloc] init];
    }
    
    if (_valueBuffer==nil) {
        _valueBuffer = [[NSMutableDictionary alloc] init];
    }
    
    return _keychainBindings;
}

- (id)values {
    if (_valueBuffer==nil) {
        _valueBuffer = [[NSMutableDictionary alloc] init];
    }
    
    return _valueBuffer;
}

- (id)valueForKeyPath:(NSString *)keyPath {
    NSRange firstSeven = NSMakeRange(0, 7);
    
    if (NSEqualRanges([keyPath rangeOfString:@"values."], firstSeven)) {
        //This is a values keyPath, so we need to check the keychain
        NSString *subKeyPath = [keyPath stringByReplacingCharactersInRange:firstSeven withString:@""];
        NSString *retrievedString = [self stringForKey:subKeyPath];
        
        if (retrievedString) {
            if (!_valueBuffer[subKeyPath] || ![_valueBuffer[subKeyPath] isEqualToString:retrievedString]) {
                //buffer has wrong value, need to update it
                [_valueBuffer setValue:retrievedString forKey:subKeyPath];
            }
        }
    }
    
    return [super valueForKeyPath:keyPath];
}

- (void)setValue:(id)value forKeyPath:(NSString *)keyPath {
    [self setValue:value forKeyPath:keyPath accessibleAttribute:kSecAttrAccessibleWhenUnlocked];
}

- (void)setValue:(id)value forKeyPath:(NSString *)keyPath accessibleAttribute:(CFTypeRef)accessibleAttribute {
    NSRange firstSeven = NSMakeRange(0, 7);
    
    if (NSEqualRanges([keyPath rangeOfString:@"values."], firstSeven)) {
        //This is a values keyPath, so we need to check the keychain
        NSString *subKeyPath = [keyPath stringByReplacingCharactersInRange:firstSeven withString:@""];
        NSString *retrievedString = [self stringForKey:subKeyPath];
        
        if (retrievedString) {
            if (![value isEqualToString:retrievedString]) {
                [self storeString:value forKey:subKeyPath accessibleAttribute:accessibleAttribute];
            }
            
            if (!_valueBuffer[subKeyPath] || ![_valueBuffer[subKeyPath] isEqualToString:value]) {
                //buffer has wrong value, need to update it
                [_valueBuffer setValue:value forKey:subKeyPath ];
            }
        } else {
            //First time to set it
            [self storeString:value forKey:subKeyPath accessibleAttribute:accessibleAttribute];
            [_valueBuffer setValue:value forKey:subKeyPath];
        }
    } 
    [super setValue:value forKeyPath:keyPath];
}

@end