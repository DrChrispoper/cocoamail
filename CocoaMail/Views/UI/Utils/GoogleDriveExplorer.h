//
//  GoogleDriveExplorerTableViewController.h
//  CocoaMail
//
//  Created by Christopher Hockley on 30/07/15.
//  Copyright (c) 2015 CocoaSoft. All rights reserved.
//

#import "GTLDrive.h"
#import "GTMOAuth2ViewControllerTouch.h"

typedef enum kGDFileConflictError : NSInteger {
    kGDriveFileNewerError = 1,
    kGDriveFileOlderError = 2,
    kGDriveFileSameAsLocalFileError = 3
} kGDFileConflictError;


@protocol GDriveExplorerDelegate;


@interface GoogleDriveExplorer : UITableViewController  <UISearchBarDelegate, UISearchDisplayDelegate> {

}

//@property (weak, nonatomic) IBOutlet UIBarButtonItem* refreshButton;

@property (nonatomic, strong) GTLServiceDrive* service;
@property (retain) NSMutableArray* driveFiles;
@property BOOL isAuthorized;

@property (nonatomic, copy) NSString* currentPath;
@property (nonatomic, weak) id <GDriveExplorerDelegate> rootViewDelegate;

/// Set allowed file types (like a filter). Just create an array of allowed file extensions. Do not set to allow all files
@property (nonatomic, copy) NSArray* allowedFileTypes;

/// Set the tableview cell ID for dequeueing
@property (nonatomic, copy) NSString* tableCellID;

/// Download indicator in UINavigationBar to indicate progress of file download
@property (strong, nonatomic) UIProgressView* downloadProgressView;

/// Set whether or not DBBrowser should deliver notifications to the user about file downloads
@property BOOL deliverDownloadNotifications;

-(void) loadDriveFiles;


@end

/// The GDriveExplorer Delegate can be used to recieve download notifications, failures, successes, errors, file conflicts, and even handle the download yourself.
@protocol GDriveExplorerDelegate <NSObject>

@optional

//----------------------------------------------------------------------------------------//
// Available Methods - Use these delegate methods for a variety of operations and events  //
//----------------------------------------------------------------------------------------//

/// Sent to the delegate when there is a successful file download
-(void) gdriveExplorer:(GoogleDriveExplorer*)explorer didDownloadFile:(NSString*)fileName didOverwriteFile:(BOOL)isLocalFileOverwritten;

/// Sent to the delegate if DropboxBrowser failed to download file from Dropbox
-(void) gdriveExplorer:(GoogleDriveExplorer*)explorer didFailToDownloadFile:(NSString*)fileName;

/// Sent to the delegate if the selected file already exists locally
-(void) gdriveExplorer:(GoogleDriveExplorer*)explorer fileConflictWithLocalFile:(NSURL*)localFileURL withGDriveFile:(GTLDriveFile*)gdriveFile withError:(NSError*)error;

/// Sent to the delegate when the user selects a file. Implementing this method will require you to download or manage the selection on your own. Otherwise, automatically downloads file if not implemented.
-(void) gdriveExplorer:(GoogleDriveExplorer*)explorer didSelectFile:(GTLDriveFile*)file;

/// Sent to the delegate if the share link is successfully loaded
-(void) gdriveExplorer:(GoogleDriveExplorer*)explorer didLoadShareLink:(NSString*)link;

/// Sent to the delegate if there was an error creating or loading share link
-(void) gdriveExplorer:(GoogleDriveExplorer*)explorer didFailToLoadShareLinkWithError:(NSError*)error;

/// Sent to the delegate when a file download notification is delivered to the user. You can use this method to record the notification ID so you can clear the notification if ncessary.
-(void) gdriveExplorer:(GoogleDriveExplorer*)explorer deliveredFileDownloadNotification:(UILocalNotification*)notification;

/// Sent to the delegate after the DropboxBrowserViewController is dismissed by the user - Do \b NOT use this method to dismiss the DropboxBrowser
-(void) gdriveExplorerDismissed:(GoogleDriveExplorer*)explorer;


@end