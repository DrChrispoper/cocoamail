//
//  UserSettings.h
//  CocoaMail
//
//  Created by Christopher Hockley on 24/02/16.
//  Copyright © 2016 Christopher Hockley. All rights reserved.
//

#import "CCMConstants.h"
#import "Accounts.h"
#import <MailCore/Mailcore.h>

#define USER_SETTINGS_FILE_NAME_TEMPLATE    @"user_settings_%lu"
#define FOLDER_USER_SETTINGS_KEY		@"userSettings"

@interface UserSettings : NSObject <NSCoding>

@property NSString *identifier;
@property NSString *username;

@property NSString *imapHostname;
@property NSUInteger imapPort;
@property NSUInteger imapConnectionType;

@property NSString *smtpHostname;
@property NSUInteger smtpPort;
@property NSUInteger smtpConnectionType;

@property NSString *signature;
@property NSString *name;
@property NSString *initials;
@property UIColor* color;

@property NSMutableArray* importantFolders;
@property NSMutableArray* allFoldersDisplayNames;

@property (getter = isDeleted) BOOL deleted;
@property (getter = isAll) BOOL all;

@property NSUInteger accountNum;
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
-(NSInteger) numFolderWithFolder:(CCMFolderType)folder;
-(NSInteger)inboxFolderNumber;

-(NSString*) folderDisplayNameForIndex:(NSInteger)folder;
-(NSString*) folderDisplayNameForType:(CCMFolderType)folder;

-(NSString*) folderServerName:(NSInteger)folder;
-(NSArray*) allNonImportantFoldersName;

-(Account*) linkedAccount;

-(MCOIMAPMessagesRequestKind) requestKind;

-(NSString *)description;

@end
