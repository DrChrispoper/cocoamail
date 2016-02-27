//
//  UserSettings.m
//  CocoaMail
//
//  Created by Christopher Hockley on 24/02/16.
//  Copyright © 2016 Christopher Hockley. All rights reserved.
//

#import "UserSettings.h"
#import "PDKeychainBindings.h"
#import "SyncManager.h"
#import "Accounts.h"

@implementation UserSettings {
    NSString* _localPath;
}

@synthesize identifier = _identifier;
@synthesize username = _username;
@synthesize imapHostname = _imapHostname;
@synthesize imapPort = _imapPort;
@synthesize imapConnectionType = _imapConnectionType;
@synthesize smtpHostname = _smtpHostname;
@synthesize smtpPort = _smtpPort;
@synthesize smtpConnectionType = _smtpConnectionType;
@synthesize signature = _signature;
@synthesize name = _name;
@synthesize initials = _initials;
@synthesize color = _color;
@synthesize importantFolders = _importantFolders;
@synthesize allFolders = _allFolders;
@synthesize accountNum = _accountNum;
@synthesize accountIndex = _accountIndex;
@synthesize deleted = _deleted;
@synthesize all = _all;

-(NSString *) identifier
{
    return _identifier;
}

-(NSString *)username
{
    return _username;
}

-(NSString *) imapHostname
{
    return _imapHostname;
}

-(NSUInteger)imapPort
{
    return _imapPort;
}

-(NSUInteger)imapConnectionType
{
    return _imapConnectionType;
}

-(NSString *)smtpHostname
{
    return _smtpHostname;
}

-(NSUInteger)smtpPort
{
    return _smtpPort;
}

-(NSUInteger)smtpConnectionType
{
    return _smtpConnectionType;
}

-(NSString *)signature
{
    return _signature;
}

-(NSString *)name
{
    return _name;
}

-(NSString *)initials
{
    return _initials;
}

-(UIColor *)color
{
    return _color;
}

-(NSArray *)importantFolders
{
    return _importantFolders;
}

-(NSArray *)allFolders
{
    return _allFolders;
}

-(NSUInteger)accountNum
{
    return _accountNum;
}

-(NSUInteger)accountIndex
{
    return _accountIndex;
}

-(BOOL)isDeleted
{
    return _deleted;
}

-(BOOL)isAll
{
    return _all;
}

-(void) setIdentifier:(NSString *)identifier
{
    _identifier = identifier;
    [NSKeyedArchiver archiveRootObject:self toFile:_localPath];
}

-(void) setUsername:(NSString *)username
{
    _username = username;
    [NSKeyedArchiver archiveRootObject:self toFile:_localPath];
}

-(void)setImapHostname:(NSString *)imapHostname
{
    _imapHostname = imapHostname;
    [NSKeyedArchiver archiveRootObject:self toFile:_localPath];
}

-(void)setImapPort:(NSUInteger)imapPort
{
    _imapPort = imapPort;
    [NSKeyedArchiver archiveRootObject:self toFile:_localPath];
}

-(void)setImapConnectionType:(NSUInteger)imapConnectionType
{
    _imapConnectionType = imapConnectionType;
    [NSKeyedArchiver archiveRootObject:self toFile:_localPath];
}

-(void)setSmtpHostname:(NSString *)smtpHostname
{
    _smtpHostname = smtpHostname;
    [NSKeyedArchiver archiveRootObject:self toFile:_localPath];
}

-(void)setSmtpPort:(NSUInteger)smtpPort
{
    _smtpPort = smtpPort;
    [NSKeyedArchiver archiveRootObject:self toFile:_localPath];
}

-(void)setSmtpConnectionType:(NSUInteger)smtpConnectionType
{
    _smtpConnectionType = smtpConnectionType;
    [NSKeyedArchiver archiveRootObject:self toFile:_localPath];
}

-(void)setSignature:(NSString *)signature
{
    _signature = signature;
    [NSKeyedArchiver archiveRootObject:self toFile:_localPath];
}

-(void)setName:(NSString *)name
{
    _name = name;
    [NSKeyedArchiver archiveRootObject:self toFile:_localPath];
}

-(void)setInitials:(NSString *)initials
{
    _initials = initials;
    [NSKeyedArchiver archiveRootObject:self toFile:_localPath];
}

-(void)setColor:(UIColor *)color
{
    _color = color;
    [NSKeyedArchiver archiveRootObject:self toFile:_localPath];
}

-(void)setImportantFolders:(NSMutableArray *)importantFolders
{
    _importantFolders = importantFolders;
    [NSKeyedArchiver archiveRootObject:self toFile:_localPath];
}

-(void)setAllFolders:(NSMutableArray *)allFolders
{
    _allFolders = allFolders;
    [NSKeyedArchiver archiveRootObject:self toFile:_localPath];
}

-(void)setAccountNum:(NSUInteger)accountNum
{
    _accountNum = accountNum;
    
    NSString *documentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString* folderPath = [documentsDirectory stringByAppendingPathComponent:FOLDER_USER_SETTINGS_KEY];
    _localPath = [folderPath stringByAppendingPathComponent:[NSString stringWithFormat:USER_SETTINGS_FILE_NAME_TEMPLATE,(unsigned long)_accountNum]];
    
    [NSKeyedArchiver archiveRootObject:self toFile:_localPath];
}

-(void)setAccountIndex:(NSUInteger)accountIndex
{
    _accountIndex = accountIndex;
    [NSKeyedArchiver archiveRootObject:self toFile:_localPath];
}

-(void)setDeleted:(BOOL)deleted
{
    _deleted = deleted;
    [NSKeyedArchiver archiveRootObject:self toFile:_localPath];
}

-(void)setAll:(BOOL)all
{
    _all = all;
    [NSKeyedArchiver archiveRootObject:self toFile:_localPath];
}

-(NSString*) password
{
    NSString* str =  [[PDKeychainBindings sharedKeychainBindings] objectForKey:[NSString stringWithFormat: @"P%li", (long)_accountNum]];
    
    return str;
}

-(void) setPassword:(NSString*)password
{
    PDKeychainBindings* bindings = [PDKeychainBindings sharedKeychainBindings];
    [bindings setObject:password forKey:[NSString stringWithFormat: @"P%li", (long)_accountNum] accessibleAttribute:kSecAttrAccessibleAfterFirstUnlock];
}

-(BOOL) isUsingOAuth
{
    return  ![[self oAuth] isEqualToString:@""];
}

-(NSString*) oAuth
{
    return [[PDKeychainBindings sharedKeychainBindings] stringForKey:[NSString stringWithFormat: @"T%li", (long)_accountNum]];
}

-(void) setOAuth:(NSString*)token
{
    PDKeychainBindings* bindings = [PDKeychainBindings sharedKeychainBindings];
    [bindings setString:token forKey:[NSString stringWithFormat: @"T%li", (long)_accountNum] accessibleAttribute:kSecAttrAccessibleAfterFirstUnlock];
}

-(NSInteger) importantFolderNumforBaseFolder:(BaseFolderType)baseFolder
{
    return [_importantFolders[baseFolder] integerValue];
}

-(void) setImportantFolderNum:(NSInteger)folder forBaseFolder:(BaseFolderType)baseFolder
{
    if (_importantFolders.count == 0) {
        _importantFolders = [[NSMutableArray alloc] initWithObjects:@"", @"", @"", @"", @"", @"", nil];
    }
    
    _importantFolders[baseFolder] = @(folder);
    
    [NSKeyedArchiver archiveRootObject:self toFile:_localPath];
}

-(CCMFolderType) typeOfFolder:(NSInteger)folder
{
    if (_all) {
        return FolderTypeWith(folder, 0);
    }
    
    for (int idx = (int)_importantFolders.count-1 ; idx >= 0 ; idx--) {
        if (folder == [_importantFolders[idx] integerValue]) {
            return FolderTypeWith(idx, 0);
        }
    }
    
    NSArray* nonImportantFolders = [self allNonImportantFoldersName];
    NSString* folderName = [self folderDisplayNameForIndex:folder];
    
    for (int idx = 0; idx < nonImportantFolders.count;idx++) {
        if ([folderName isEqualToString:nonImportantFolders[idx]]) {
            return FolderTypeWith(FolderTypeUser, idx);
        }
    }
    
    return FolderTypeWith(FolderTypeAll, 0);
}

-(NSString*) folderDisplayNameForIndex:(NSInteger)folder
{
    return _allFolders[folder];
}

-(NSString*) folderDisplayNameForType:(CCMFolderType)folder
{
    return [self folderDisplayNameForIndex:[self numFolderWithFolder:folder]];
}

-(NSString*) folderServerName:(NSInteger)folder
{
    NSMutableDictionary* folderState = [[SyncManager getSingleton] retrieveState:folder accountNum:_accountNum];
    NSString* name = folderState[@"folderPath"];
    if (!name) {
        NSLog(@"NO NAME!");
    }
    return name;
}

-(NSInteger) numFolderWithFolder:(CCMFolderType)folder
{
    NSString* folderName;
    
    if (folder.type == FolderTypeUser) {
        folderName = [[Accounts sharedInstance] currentAccount].userFolders[folder.idx][0];
        for (int index = 0; index < [_allFolders count]; index++) {
            if ([folderName isEqualToString:_allFolders[index]]) {
                return index;
            }
        }
    } else {
        return [self importantFolderNumforBaseFolder:folder.type];
    }
    
    return -1;
}

-(NSArray*) allNonImportantFoldersName
{
    NSMutableSet* foldersSet = [NSMutableSet setWithArray:_allFolders];
    
    for (NSNumber* index in _importantFolders) {
        if ([index intValue] >= 0) {
            [foldersSet removeObject:_allFolders[[index intValue]]];
        }
    }
    
    return [[foldersSet allObjects] sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

-(Account*) linkedAccount
{
    return [[Accounts sharedInstance] account:_accountIndex];
}

#pragma mark - NSCoding

- (id)initWithCoder:(NSCoder *)decoder {
    self = [super init];
    if (!self) {
        return nil;
    }
    
    _identifier = [decoder decodeObjectForKey:@"identifier"];
    _username = [decoder decodeObjectForKey:@"username"];
    
    _imapHostname = [decoder decodeObjectForKey:@"imapHostname"];
    _imapPort = [decoder decodeIntegerForKey:@"imapPort"];
    _imapConnectionType = [decoder decodeIntegerForKey:@"imapConnectionType"];
    
    _smtpHostname = [decoder decodeObjectForKey:@"smtpHostname"];
    _smtpPort = [decoder decodeIntegerForKey:@"smtpPort"];
    _smtpConnectionType = [decoder decodeIntegerForKey:@"smtpConnectionType"];
    
    _signature = [decoder decodeObjectForKey:@"signature"];
    _name = [decoder decodeObjectForKey:@"name"];
    _initials = [decoder decodeObjectForKey:@"initials"];
    _color = [UserSettings _colorForString:[decoder decodeObjectForKey:@"color"]];

    _importantFolders = [decoder decodeObjectForKey:@"importantFolders"];
    _allFolders = [decoder decodeObjectForKey:@"allFolders"];

    _deleted = [decoder decodeBoolForKey:@"deleted"];
    _all = [decoder decodeBoolForKey:@"all"];

    _accountNum = [decoder decodeIntegerForKey:@"accountNum"];
    _accountIndex = [decoder decodeIntegerForKey:@"accountIndex"];
    
    NSString *documentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString* folderPath = [documentsDirectory stringByAppendingPathComponent:FOLDER_USER_SETTINGS_KEY];
    _localPath = [folderPath stringByAppendingPathComponent:[NSString stringWithFormat:USER_SETTINGS_FILE_NAME_TEMPLATE,(unsigned long)_accountNum]];
    
    return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder
{
    [encoder encodeObject:_identifier forKey:@"identifier"];
    [encoder encodeObject:_username forKey:@"username"];
    
    [encoder encodeObject:_imapHostname forKey:@"imapHostname"];
    [encoder encodeInteger:_imapPort forKey:@"imapPort"];
    [encoder encodeInteger:_imapConnectionType forKey:@"imapConnectionType"];

    [encoder encodeObject:_smtpHostname forKey:@"smtpHostname"];
    [encoder encodeInteger:_smtpPort forKey:@"smtpPort"];
    [encoder encodeInteger:_smtpConnectionType forKey:@"smtpConnectionType"];
    
    [encoder encodeObject:_signature forKey:@"signature"];
    [encoder encodeObject:_name forKey:@"name"];
    [encoder encodeObject:_initials forKey:@"initials"];
    [encoder encodeObject:[UserSettings _stringForColor:_color] forKey:@"color"];
    
    [encoder encodeObject:_importantFolders forKey:@"importantFolders"];
    [encoder encodeObject:_allFolders forKey:@"allFolders"];
    
    [encoder encodeBool:_deleted forKey:@"deleted"];
    [encoder encodeBool:_all forKey:@"all"];

    [encoder encodeInteger:_accountNum forKey:@"accountNum"];
    [encoder encodeInteger:_accountIndex forKey:@"accountIndex"];
}

+(UIColor*) _colorForString:(NSString*)colorString
{
    UIColor* color = [UIColor colorWithCIColor:[CIColor colorWithString:colorString]];
    
    CGFloat red = 0.0, green = 0.0, blue = 0.0, alpha =0.0;
    
    [color getRed:&red green:&green blue:&blue alpha:&alpha];
    
    return [UIColor colorWithRed:(float)red
                           green:(float)green
                            blue:(float)blue
                           alpha:1];
}

+(NSString*) _stringForColor:(UIColor*)color
{
    return [CIColor colorWithCGColor:color.CGColor].stringRepresentation;
}

@end
