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
@synthesize importantFolderNumbers = _importantFolderNumbers;
@synthesize allFoldersDisplayNames = _allFoldersDisplayNames;
@synthesize accountNum = _accountNum;
@synthesize deleted = _deleted;
@synthesize all = _all;
@synthesize folderPathDelimiter = _folderPathDelimiter;
@synthesize folderPathPrefix = _folderPathPrefix;


-(NSString *) folderPathPrefix
{
    if ( !_folderPathPrefix ) {
        _folderPathPrefix = @"";
    }
    return _folderPathPrefix;
}

-(NSString *) folderPathDelimiter
{
    // This will usually be set except for those who upgrade the app
    // after the version with this change is first introduced.
    // Rather than forcing them to update the app, I am returning a
    // default value (which will work for Google accounts at least).
    if ( !_folderPathDelimiter ) {
        _folderPathDelimiter = @"/";
    }
    return _folderPathDelimiter;
}
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

-(NSArray<NSNumber*>*)importantFolderNumbers
{
    // Initialize the Important Folder Numbers if they do not already exist
    if ( _importantFolderNumbers == nil || _importantFolderNumbers.count < FolderTypeCount) {
        _importantFolderNumbers = [[NSMutableArray alloc] initWithCapacity:FolderTypeCount];
        for (int i = 0; i < FolderTypeCount; i++) {
            [_importantFolderNumbers addObject:[NSNumber numberWithInteger:-1]];
        }
    }
    return _importantFolderNumbers;
}

-(NSArray<NSString*>*)allFoldersDisplayNames
{
    return _allFoldersDisplayNames;
}

-(NSInteger)accountNum
{
    return _accountNum;
}

-(NSUInteger)accountIndex
{
    return (NSUInteger)[AppSettings indexForAccountNum:_accountNum];
}

-(BOOL)isDeleted
{
    return _deleted;
}

-(BOOL)isAll
{
    return _all;
}

-(void)setFolderPathPrefix:(NSString *)folderPathPrefix
{
    DDLogInfo(@"ENTERED");
    _folderPathPrefix = [folderPathPrefix copy];
    [NSKeyedArchiver archiveRootObject:self toFile:_localPath];
}

-(void)setFolderPathDelimiter:(NSString *)folderPathDelimiter
{
    DDLogInfo(@"ENTERED");
    _folderPathDelimiter = [folderPathDelimiter copy];
    [NSKeyedArchiver archiveRootObject:self toFile:_localPath];
}

-(void) setIdentifier:(NSString *)identifier
{
    DDLogInfo(@"ENTERED");
    _identifier = identifier;
    [NSKeyedArchiver archiveRootObject:self toFile:_localPath];
}

-(void) setUsername:(NSString *)username
{
    DDLogInfo(@"ENTERED");
    _username = username;
    [NSKeyedArchiver archiveRootObject:self toFile:_localPath];
}

-(void)setImapHostname:(NSString *)imapHostname
{
    DDLogInfo(@"ENTERED");
    _imapHostname = imapHostname;
    [NSKeyedArchiver archiveRootObject:self toFile:_localPath];
}

-(void)setImapPort:(NSUInteger)imapPort
{
    DDLogInfo(@"ENTERED");
    _imapPort = imapPort;
    [NSKeyedArchiver archiveRootObject:self toFile:_localPath];
}

-(void)setImapConnectionType:(NSUInteger)imapConnectionType
{
    DDLogInfo(@"ENTERED");
    _imapConnectionType = imapConnectionType;
    [NSKeyedArchiver archiveRootObject:self toFile:_localPath];
}

-(void)setSmtpHostname:(NSString *)smtpHostname
{
    DDLogInfo(@"ENTERED");
    _smtpHostname = smtpHostname;
    [NSKeyedArchiver archiveRootObject:self toFile:_localPath];
}

-(void)setSmtpPort:(NSUInteger)smtpPort
{
    DDLogInfo(@"ENTERED");
    _smtpPort = smtpPort;
    [NSKeyedArchiver archiveRootObject:self toFile:_localPath];
}

-(void)setSmtpConnectionType:(NSUInteger)smtpConnectionType
{
    DDLogInfo(@"ENTERED");
    _smtpConnectionType = smtpConnectionType;
    [NSKeyedArchiver archiveRootObject:self toFile:_localPath];
}

-(void)setSignature:(NSString *)signature
{
    DDLogInfo(@"ENTERED");
    _signature = signature;
    [NSKeyedArchiver archiveRootObject:self toFile:_localPath];
}

-(void)setName:(NSString *)name
{
    DDLogInfo(@"ENTERED");

    if (!self.isAll) {
        self.linkedAccount.person.name = name;
    }
    
    _name = name;
    [NSKeyedArchiver archiveRootObject:self toFile:_localPath];
}

-(void)setInitials:(NSString *)initials
{
    DDLogInfo(@"ENTERED");

    if (!self.isAll) {
        self.linkedAccount.person.codeName = initials;
    }
    
    _initials = initials;
    [NSKeyedArchiver archiveRootObject:self toFile:_localPath];
}

-(void)setColor:(UIColor *)color
{
    DDLogInfo(@"ENTERED");

    _color = color;
    [NSKeyedArchiver archiveRootObject:self toFile:_localPath];
}

-(void)setimportantFolderNumbers:(NSMutableArray<NSNumber*>*)importantFolderNumbers
{
    DDLogInfo(@"ENTERED");

    _importantFolderNumbers = importantFolderNumbers;
    [NSKeyedArchiver archiveRootObject:self toFile:_localPath];
}

-(void) setAllFoldersDisplayNames:(NSMutableArray *)allFolders
{
    DDLogInfo(@"ENTERED");

    _allFoldersDisplayNames = allFolders;   // does this copy or assign?
    
    [NSKeyedArchiver archiveRootObject:self toFile:_localPath];
}

-(void)setAccountNum:(NSInteger)accountNum
{
    DDLogInfo(@"ENTERED");

    _accountNum = accountNum;
    
    NSString *documentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString* folderPath = [documentsDirectory stringByAppendingPathComponent:FOLDER_USER_SETTINGS_KEY];
    _localPath = [folderPath stringByAppendingPathComponent:[NSString stringWithFormat:USER_SETTINGS_FILE_NAME_TEMPLATE,(unsigned long)_accountNum]];
    
    [NSKeyedArchiver archiveRootObject:self toFile:_localPath];
}

-(void)setDeleted:(BOOL)deleted
{
    DDLogInfo(@"ENTERED");

    _deleted = deleted;
    [NSKeyedArchiver archiveRootObject:self toFile:_localPath];
}

-(void)setAll:(BOOL)all
{
    DDLogInfo(@"ENTERED");

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
    BOOL u = ![[self oAuth] isEqualToString:@""];
    return  u;
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

-(NSString*) refreshT
{
    return [[PDKeychainBindings sharedKeychainBindings] stringForKey:[NSString stringWithFormat: @"RT%li", (long)_accountNum]];
}

-(void) setRefreshT:(NSString*)token
{
    PDKeychainBindings* bindings = [PDKeychainBindings sharedKeychainBindings];
    [bindings setString:token forKey:[NSString stringWithFormat: @"RT%li", (long)_accountNum] accessibleAttribute:kSecAttrAccessibleAfterFirstUnlock];
}

// This returns the index into importantFolderNumbers of the requested folder type
-(NSInteger) importantFolderNumforBaseFolder:(BaseFolderType)baseFolder
{
    NSUInteger maxIndex = self.importantFolderNumbers.count - 1;
    
    if ( baseFolder < 0 || baseFolder > maxIndex) {
        // error
        DDLogError(@"Important Folder Number index %@ is not between 0 and %@.",@(baseFolder),@(maxIndex));
        return -1;
    }
    
    NSNumber *importantNumber = self.importantFolderNumbers[baseFolder];
    if ( importantNumber == nil ) {
        // error
        DDLogError(@"No valid NSNumber at ImportantFolderNumber[%@]",@(baseFolder));
        return -1;
    }
    
    return [importantNumber integerValue];
}


-(void) setImportantFolderNum:(NSInteger)folder forBaseFolder:(BaseFolderType)baseFolder
{
    NSUInteger maxIndex = self.importantFolderNumbers.count - 1;
    
    if ( baseFolder < 0 || baseFolder > maxIndex) {
        // error
        DDLogError(@"Important Folder Number index %@ is not between 0 and %@.",@(baseFolder),@(maxIndex));
        return;
    }

    self.importantFolderNumbers[baseFolder] = [NSNumber numberWithInteger:folder];
    
    [NSKeyedArchiver archiveRootObject:self toFile:_localPath];
}

-(CCMFolderType) typeOfFolder:(NSInteger)folder
{
    // If we are the all user, return this as a system folder type
    if (_all) {
        return FolderTypeWith(folder, 0);
    }
    
    // If the folder is a system folder, return this
    NSInteger folderNumberIndex = 0;
    for (NSNumber *folderNumber in self.importantFolderNumbers) {
        NSInteger folderNameIndex = [folderNumber integerValue];
        if ( folder == folderNameIndex ) {
            return FolderTypeWith(folderNumberIndex, 0);
        }
        folderNumberIndex++;
    }

    NSArray* nonImportantFolderNames = [self allNonImportantFoldersName];
    NSString* folderName = [self folderDisplayNameForIndex:(NSUInteger)folder];
    
    // If the folder name for this index can be found in the User Folders,
    // turn return that folder type.
    for (NSUInteger idx = 0; idx < nonImportantFolderNames.count;idx++) {
        if ([folderName isEqualToString:nonImportantFolderNames[idx]]) {
            NSInteger folderIndex = (NSInteger)idx;
            return FolderTypeWith(FolderTypeUser, folderIndex);
        }
    }
    
    // Otherwise return Folder Type ALL
    return CCMFolderTypeAll;
}

-(NSString*) folderDisplayNameForIndex:(NSUInteger)folder
{
    DDAssert(_allFoldersDisplayNames,@"_addFoldersDisplayNames must be initialized.");
//    DDAssert(folder>=0, @"folder index must not be negative.");
    
    return _allFoldersDisplayNames[folder];
}

-(NSString*) folderDisplayNameForType:(CCMFolderType)folder
{
    return [self folderDisplayNameForIndex:(NSUInteger)[self numFolderWithFolder:folder]];
}

-(NSString*) folderServerName:(NSInteger)folder
{
    NSString* folderPath = [[SyncManager getSingleton] retrieveFolderPathFromFolderState:folder
                                                       accountNum:(NSInteger)_accountNum];
    return folderPath;
}

-(NSInteger)inboxFolderNumber
{
    return [self numFolderWithFolder:inboxFolderType()];
}
-(NSInteger) numFolderWithFolder:(CCMFolderType)folder      // Can return -1
{
    NSInteger folderIndex = -1;     // not found
    
    if (folder.type == FolderTypeUser) {
        NSString *folderName = [[Accounts sharedInstance] currentAccount].userFolders[(NSUInteger)folder.idx][0];
        for (NSUInteger index = 0; index < [_allFoldersDisplayNames count]; index++) {
            
            NSString *indexedFolderDisplayName = [self folderDisplayNameForIndex:index];
            if ([folderName isEqualToString:indexedFolderDisplayName]) {
                folderIndex = (NSInteger)index;
                break;
            }
        } // end of loop
        
    } else {
        folderIndex = [self importantFolderNumforBaseFolder:folder.type];
    }
    
//    DDLogError(@"Folder for Type=%@ and Index=%@ COULD NOT BE FOUND",@(folder.type),@(folder.idx));
    
//    DDAssert(folderIndex != -1, @"Folder Index must not be -1!");
    
    return folderIndex;      // NB: CAN RETURN -1
}

-(NSArray<NSString*>*) allNonImportantFoldersName
{
    if ( !_allFoldersDisplayNames ){
        _allFoldersDisplayNames = [NSMutableArray arrayWithObject:@"nothing here"];
    }
    
    // Create an All Folders Names Set
    NSMutableSet* foldersSet = [NSMutableSet setWithArray:_allFoldersDisplayNames];
    
    // Remove the Important Folder Names from the All Folders Name Set
    for (NSNumber* folderNumber in self.importantFolderNumbers) {
        if ([folderNumber intValue] >= 0) {
            NSUInteger folderNameIndex = [folderNumber unsignedIntegerValue];
            
            NSString *fldNameToRemove = _allFoldersDisplayNames[folderNameIndex];
            
            // if we got a string and its more than 0 characters in length ...
            if ( fldNameToRemove && fldNameToRemove.length) {
                
                // then remove it from the folder set
                [foldersSet removeObject:fldNameToRemove];
            }
            
        }
    }
    
    NSArray <NSString*>* folderNames = [foldersSet allObjects];
    
    // Return an array of all Non Important (ie. User) Folders in sorted order
    return [folderNames sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
}

-(Account*) linkedAccount   // Returns the Account object for self.accountNum
{
    NSUInteger appSettingsIndexForAccount = [self accountIndex];
    
    DDAssert(appSettingsIndexForAccount >= 0, @"AppSettings Account Index must be found");
    
    return [[Accounts sharedInstance] account:appSettingsIndexForAccount];
}

- (MCOIMAPMessagesRequestKind)requestKind
{
    MCOIMAPMessagesRequestKind rq =
    MCOIMAPMessagesRequestKindHeaders |
    MCOIMAPMessagesRequestKindStructure |
    MCOIMAPMessagesRequestKindInternalDate |
    MCOIMAPMessagesRequestKindHeaderSubject |
    MCOIMAPMessagesRequestKindFlags;
    
    if ([self.identifier isEqualToString:@"gmail"]) {
        rq |= MCOIMAPMessagesRequestKindGmailThreadID;
    }
    
    return rq;
}

#pragma mark - NSCoding

- (id)initWithCoder:(NSCoder *)decoder {
    self = [super init];
    if (!self) {
        return nil;
    }
    
    _folderPathDelimiter = [decoder decodeObjectForKey:@"folderPathDelimiter"];
    _folderPathPrefix = [decoder decodeObjectForKey:@"folderPathPrefix"];
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

    _importantFolderNumbers = [decoder decodeObjectForKey:@"importantFolders"];
    _allFoldersDisplayNames = [decoder decodeObjectForKey:@"allFolders"];
    
//    DDAssert(_allFoldersDisplayNames,@"_allFoldersDisplayNames should not be nil");
    
    _deleted = [decoder decodeBoolForKey:@"deleted"];
    _all = [decoder decodeBoolForKey:@"all"];

    _accountNum = [decoder decodeIntegerForKey:@"accountNum"];
    //_accountIndex = [decoder decodeIntegerForKey:@"accountIndex"];
    
    NSString *documentsDirectory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString* folderPath = [documentsDirectory stringByAppendingPathComponent:FOLDER_USER_SETTINGS_KEY];
    _localPath = [folderPath stringByAppendingPathComponent:[NSString stringWithFormat:USER_SETTINGS_FILE_NAME_TEMPLATE,(unsigned long)_accountNum]];
    
    DDLogVerbose(@"DECODED UserSettings: %@",[self description]);

    return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder
{
    [encoder encodeObject:_folderPathDelimiter forKey:@"folderPathDelimiter"];
    [encoder encodeObject:_folderPathPrefix forKey:@"folderPathPrefix"];
    
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
        
    [encoder encodeObject:_importantFolderNumbers forKey:@"importantFolders"];
    [encoder encodeObject:_allFoldersDisplayNames forKey:@"allFolders"];
    
    if ( _allFoldersDisplayNames == nil ) {
        DDLogDebug(@"Archiving NIL _allFolderDisplayNames for account %@",@(_accountNum));
    } else {
        DDLogDebug(@"Archiving %@ _allFolderDisplayNames for account %@",@(_allFoldersDisplayNames.count),@(_accountNum));
    }
    [encoder encodeBool:_deleted forKey:@"deleted"];
    [encoder encodeBool:_all forKey:@"all"];

    [encoder encodeInteger:_accountNum forKey:@"accountNum"];
    //[encoder encodeInteger:_accountIndex forKey:@"accountIndex"];
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

#pragma mark - NSObject description

-(NSString *)description
{
    NSMutableString *desc = [NSMutableString string];
    
    [desc appendString:@"\n--- UserSettings: ---\n"];
    
    [desc appendFormat:@"\taccount number = %@\n",@(self.accountNum)];
    [desc appendString:@"\n"];

    [desc appendFormat:@"\tdelimiter = \"%@\"\n",self.folderPathDelimiter];
    [desc appendFormat:@"\tprefix    = \"%@\"\n",self.folderPathPrefix];
    [desc appendString:@"\n"];

    [desc appendFormat:@"\tidentifier = \"%@\"\n",self.identifier];
    [desc appendFormat:@"\tusername   = \"%@\"\n",self.username];
    [desc appendString:@"\n"];
    
    // IMAP
    [desc appendFormat:@"\tIMAP hostname        = \"%@\"\n",self.imapHostname];
    [desc appendFormat:@"\tIMAP port            = %ld\n",(long)self.imapPort];
    [desc appendFormat:@"\tIMAP connection type = \"%@\"\n",
        [self connTypeDescription:self.imapConnectionType]];
    [desc appendString:@"\n"];
    
    // SMTP
    [desc appendFormat:@"\tSMTP hostname        = \"%@\"\n",self.smtpHostname];
    [desc appendFormat:@"\tSMTP port            = %ld\n",(long)self.smtpPort];
    [desc appendFormat:@"\tSMTP connection type = \"%@\"\n",
        [self connTypeDescription:self.smtpConnectionType]];
    [desc appendString:@"\n"];
    
    [desc appendFormat:@"\tSignature = \"%@\"\n",self.signature];
    [desc appendFormat:@"\tName      = \"%@\"\n",self.name];
    [desc appendFormat:@"\tInitials  = \"%@\"\n",self.initials];
    [desc appendFormat:@"\tcolor     = \"%@\"\n",[self.color description]];
    [desc appendString:@"\n"];

    if (self.importantFolderNumbers == nil) {
        [desc appendFormat:@"\tImportant Folders array is nil!\n"];
    } else {
        [desc appendFormat:@"\tImportant Folders count = %ld\n",
         (unsigned long)[self.importantFolderNumbers count]];
        for (NSNumber *importantFolderNumber in self.importantFolderNumbers) {
            [desc appendFormat:@"\t\tNumber = \"%@\"\n",[importantFolderNumber stringValue]];
        }
    }
    
    if ( self.allFoldersDisplayNames == nil ) {
        [desc appendFormat:@"\tFolder Display Names array is nil!\n"];
    } else {
        [desc appendFormat:@"\tFolder Display Names count = %ld\n",
         (unsigned long)[self.allFoldersDisplayNames count]];
        for (NSString *folderName in self.allFoldersDisplayNames) {
            [desc appendFormat:@"\t\tName = \"%@\"\n",folderName];
        }
    
    }
    [desc appendString:@"\n"];

    [desc appendFormat:@"\tIs Deleted = %@\n",([self isDeleted]?@"TRUE":@"FALSE")];
    [desc appendFormat:@"\tIs All     = %@\n",([self isAll]?@"TRUE":@"FALSE")];
   
    [desc appendString:@"--- End of UserSettings ---"];
    
    return desc;
}

-(NSString *) connTypeDescription:(NSInteger)connType
{
    NSString *desc = @"";
    
    switch ( connType ) {
        case MCOConnectionTypeClear:
            desc = @"Clear-text";
            break;
        case MCOConnectionTypeStartTLS:
            desc = @"Start TLS - Start with Clear-text, then switch to encrypted connection using TLS/SSL";
            break;
        case MCOConnectionTypeTLS:
            desc = @"TLS - encrypted connection using TLS/SSL.";
            break;
        default:
            desc = [NSString stringWithFormat:@"Unknown MOConnectionType %ld",(long)connType];
            break;
    }
    return desc;
}


@end
