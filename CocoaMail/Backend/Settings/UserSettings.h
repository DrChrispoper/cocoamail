//
//  UserSettings.h
//  CocoaMail
//
//  Created by Christopher Hockley on 24/02/16.
//  Copyright © 2016 Christopher Hockley. All rights reserved.
//

#import "CCMConstants.h"
#import "Accounts.h"
#import <MailCore/MailCore.h>

#define USER_SETTINGS_FILE_NAME_TEMPLATE    @"user_settings_%lu"
#define FOLDER_USER_SETTINGS_KEY		@"userSettings"

@interface UserSettings : NSObject <NSCoding>

@property (nonatomic) NSString *identifier;
@property (nonatomic) NSString *username;

@property (nonatomic) NSString *imapHostname;
@property (nonatomic) NSUInteger imapPort;
@property (nonatomic) NSUInteger imapConnectionType;

@property (nonatomic) NSString *smtpHostname;
@property (nonatomic) NSUInteger smtpPort;
@property (nonatomic) NSUInteger smtpConnectionType;

@property (nonatomic) NSString *signature;
@property (nonatomic) NSString *name;
@property (nonatomic) NSString *initials;
@property (nonatomic) UIColor* color;

@property (nonatomic) NSMutableArray<NSNumber*>* importantFolderNumbers;
@property (nonatomic) NSMutableArray<NSString*>* allFoldersDisplayNames;

@property (nonatomic) NSString* folderPathDelimiter;      // folder path delimiter is actually a char
@property (nonatomic) NSString* folderPathPrefix;

@property (nonatomic, getter = isDeleted) BOOL deleted;
@property (nonatomic, getter = isAll) BOOL all;

@property (nonatomic) NSInteger accountNum;

-(NSUInteger) accountIndex;

-(NSString*) password;
-(void) setPassword:(NSString*)password;

-(void) setOAuth:(NSString*)token;
-(NSString*) oAuth;
-(BOOL) isUsingOAuth;
-(NSString*) refreshT;
-(void) setRefreshT:(NSString*)token;

/// Indexes are: 0-INBOX 1-Starred 2-Sent Mail 3-Draft 4-All Mail 5-Trash  6-Spam
//-(NSInteger) importantFolderNumforBaseFolder:(BaseFolderType)baseFolder;
-(void) setImportantFolderNum:(NSInteger)folder forBaseFolder:(BaseFolderType)baseFolder;
-(CCMFolderType) typeOfFolder:(NSInteger)folder;
-(NSInteger) numFolderWithFolder:(CCMFolderType)folder;     // Can return -1!
-(NSInteger) inboxFolderNumber;

-(NSString*) folderDisplayNameForIndex:(NSUInteger)folder;
-(NSString*) folderDisplayNameForType:(CCMFolderType)folder;

-(NSString*) folderServerName:(NSInteger)folder;
-(NSArray<NSString*>*) allNonImportantFoldersName;

-(Account*) linkedAccount;

-(MCOIMAPMessagesRequestKind) requestKind;

-(NSString *)description;

@end
