//
//  GoogleDriveExplorerTableViewController.m
//  CocoaMail
//
//  Created by Christopher Hockley on 30/07/15.
//  Copyright (c) 2015 CocoaSoft. All rights reserved.
//

#import "GoogleDriveExplorer.h"

// View tags to differeniate alert views
static NSUInteger const kGDFileExistsAlertViewTag = 2;
static NSString *const kKeychainItemName = @"CocoaMail: Google Drive";
static NSString *const kClientId = @"489238945643-oqhsao0g40kf8qe7qkrao3ivmhoeuifl.apps.googleusercontent.com";
static NSString *const kClientSecret = @"LhDDzVoxcxbVT95lNPSDWkCg";

@interface GoogleDriveExplorer () {
    GTLDriveFile *selectedFile;
    GoogleDriveExplorer *newSubdirectoryController;
    UIBackgroundTaskIdentifier backgroundProcess;
    BOOL isLocalFileOverwritten;
}

@end

@implementation GoogleDriveExplorer
@synthesize service = _service;
//@synthesize refreshButton = _refreshButton;
@synthesize driveFiles = _driveFiles;
@synthesize isAuthorized = _isAuthorized;
@synthesize currentPath, rootViewDelegate,downloadProgressView,deliverDownloadNotifications;
static NSString * currentFileName = nil;

- (void)awakeFromNib
{
    [super awakeFromNib];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    if (self.currentPath == nil || [self.currentPath isEqualToString:@""]) self.currentPath = @"root";

    self.service = [[GTLServiceDrive alloc] init];
    self.service.authorizer =
    [GTMOAuth2ViewControllerTouch authForGoogleFromKeychainForName:kKeychainItemName
                                                          clientID:kClientId
                                                      clientSecret:kClientSecret];
}

- (void)viewDidUnload
{
    //[self setRefreshButton:nil];
    [super viewDidUnload];
    // Release any retained subviews of the main view.
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (!self.isAuthorized) {
        [self presentViewController:[self createAuthController] animated:YES completion:nil];
    } else {
        [self loadDriveFiles];

        // Sort Drive Files by modified date (descending order).
        [self.driveFiles sortUsingComparator:^NSComparisonResult(GTLDriveFile *lhs,
                                                                 GTLDriveFile *rhs) {
            return [rhs.modifiedDate.date compare:lhs.modifiedDate.date];
        }];
        [self.tableView reloadData];
    }
}

// Creates the auth controller for authorizing access to Drive API.
- (GTMOAuth2ViewControllerTouch *)createAuthController {
    GTMOAuth2ViewControllerTouch *authController;
    NSArray *scopes = [NSArray arrayWithObjects:kGTLAuthScopeDriveMetadataReadonly, nil];
    authController = [[GTMOAuth2ViewControllerTouch alloc]
                      initWithScope:[scopes componentsJoinedByString:@" "]
                      clientID:kClientId
                      clientSecret:kClientSecret
                      keychainItemName:kKeychainItemName
                      delegate:self
                      finishedSelector:@selector(viewController:finishedWithAuth:error:)];
    return authController;
}

// Handle completion of the authorization process, and update the Drive API
// with the new credentials.
- (void)viewController:(GTMOAuth2ViewControllerTouch *)viewController
      finishedWithAuth:(GTMOAuth2Authentication *)authResult
                 error:(NSError *)error {
    if (error != nil) {
        [self showAlert:@"Authentication Error" message:error.localizedDescription];
        self.service.authorizer = nil;
    }
    else {
        self.service.authorizer = authResult;
        self.isAuthorized = YES;
        [self dismissViewControllerAnimated:YES completion:nil];
    }
}

// Helper for showing an alert
- (void)showAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation
{
    return (interfaceOrientation != UIInterfaceOrientationPortraitUpsideDown);
}

#pragma mark - Table View

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
    return 1;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return self.driveFiles.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"Cell"];
    
    GTLDriveFile *file = [self.driveFiles objectAtIndex:indexPath.row];
    cell.textLabel.text = file.title;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath == nil)
        return;
    
    if ([self.driveFiles count] == 0) {
        // Do nothing, there are no items in the list. We don't want to download a file that doesn't exist (that'd cause a crash)
        [tableView deselectRowAtIndexPath:indexPath animated:YES];
    } else {
        selectedFile = [self.driveFiles objectAtIndex:indexPath.row];
        //CCMLog(@"File Type: %@ Name:%@ MIMEType:%@",file.kind,file.title,file.mimeType);
        
        if ([selectedFile.mimeType isEqualToString:@"application/vnd.google-apps.folder"]) {
            // Create new UITableViewController
            newSubdirectoryController = [[GoogleDriveExplorer alloc] init];
            newSubdirectoryController.rootViewDelegate = self.rootViewDelegate;
            NSString *subpath = [currentPath stringByAppendingPathComponent:selectedFile.title];
            newSubdirectoryController.currentPath = subpath;
            newSubdirectoryController.title = [subpath lastPathComponent];
            newSubdirectoryController.deliverDownloadNotifications = self.deliverDownloadNotifications;
            newSubdirectoryController.allowedFileTypes = self.allowedFileTypes;
            newSubdirectoryController.tableCellID = self.tableCellID;
            
            [tableView deselectRowAtIndexPath:indexPath animated:YES];
            
            [self.navigationController pushViewController:newSubdirectoryController animated:YES];
        } else {
            currentFileName = selectedFile.title;

            // Check if our delegate handles file selection
            if ([self.rootViewDelegate respondsToSelector:@selector(gdriveExplorer:didSelectFile:)]) {
                [self.rootViewDelegate gdriveExplorer:self didSelectFile:selectedFile];
            } else {
                // Download file
                [self downloadFile:selectedFile replaceLocalVersion:NO];
            }
         
        }
        
    }
}

- (BOOL)downloadFile:(GTLDriveFile *)file replaceLocalVersion:(BOOL)replaceLocalVersion {
    // Begin Background Process
    backgroundProcess = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{
        [[UIApplication sharedApplication] endBackgroundTask:backgroundProcess];
        backgroundProcess = UIBackgroundTaskInvalid;
    }];
    
    // Check if the file is a directory
    if ([file.mimeType isEqualToString:@"application/vnd.google-apps.folder"]) return NO;
    
    // Set download success
    BOOL downloadSuccess = NO;
    
    // Setup the File Manager
    NSFileManager *fileManager = [NSFileManager defaultManager];
    
    // Create the local file path
    //NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
    NSString *localPath = [NSTemporaryDirectory() stringByAppendingPathComponent:file.title];
    
    // Check if the local version should be overwritten
    if (replaceLocalVersion) {
        isLocalFileOverwritten = YES;
        [fileManager removeItemAtPath:localPath error:nil];
    } else {
        isLocalFileOverwritten = NO;
    }
    
    // Check if a file with the same name already exists locally
    if ([fileManager fileExistsAtPath:localPath] == NO) {
        // Prevent the user from downloading any more files while this donwload is in progress
        self.tableView.userInteractionEnabled = NO;
        [UIView animateWithDuration:0.75 animations:^{
            self.tableView.alpha = 0.8;
        }];
        
        // Start the file download
        [self startDownloadFile];
        
        //[[self restClient] loadFile:file.path intoPath:localPath];

        GTMHTTPFetcher *fetcher = [self.driveService.fetcherService fetcherWithURLString:file.downloadUrl];
        
        fetcher.downloadPath = localPath;
        
        [fetcher beginFetchWithCompletionHandler:^(NSData *data, NSError *error) {
            if (error == nil) {
                NSLog(@"Retrieved file content");
                // Do something with data
                [self downloadedFile];
            } else {
                NSLog(@"An error occurred: %@", error);    
            }
        }];
        
        // The download was a success
        downloadSuccess = YES;
        
    } else {
        // Create the local URL and get the modification date
        NSURL *fileUrl = [NSURL fileURLWithPath:localPath];
        NSDate *fileDate;
        NSError *error;
        [fileUrl getResourceValue:&fileDate forKey:NSURLContentModificationDateKey error:&error];
        
        if (!error) {
            NSComparisonResult result;
            result = [file.modifiedDate.date compare:fileDate]; // Compare the Dates
            
            UIAlertController *alertView = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"File Conflict", @"Dropbox alert view title")
                                                                               message:[NSString stringWithFormat:@"%@ is not linked to your Dropbox. Would you like to login now and allow access?", [[[NSBundle mainBundle] infoDictionary] objectForKey:(NSString *)kCFBundleNameKey]]
                                                                        preferredStyle:UIAlertControllerStyleAlert];
            
            [alertView addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel",@"Cancel button") style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
                
            }]];
            
            [alertView addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Overwrite",@"Dropbox alert view confirm button") style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
                 [self downloadFile:selectedFile replaceLocalVersion:YES];
            }]];
            
            if (result == NSOrderedAscending) {
                // Dropbox file is older than local file
                alertView.message = [NSString stringWithFormat:@"%@ has already been downloaded from Dropbox. You can overwrite the local version with the Dropbox one. The file in local files is newer than the Dropbox file.", file.title];
                
                NSDictionary *infoDictionary = @{@"file": file, @"message": @"File already exists in Dropbox and locally. The local file is newer."};
                NSError *error = [NSError errorWithDomain:@"[DropboxBrowser] File Conflict Error: File already exists in Dropbox and locally. The local file is newer." code:kGDriveFileOlderError userInfo:infoDictionary];
                
                if ([self.rootViewDelegate respondsToSelector:@selector(gdriveExplorer:fileConflictWithLocalFile:withGDriveFile:withError:)]) {
                    [self.rootViewDelegate gdriveExplorer:self fileConflictWithLocalFile:fileUrl withGDriveFile:file withError:error];
                }
                
            } else if (result == NSOrderedDescending) {
                // Dropbox file is newer than local file
                alertView.message = [NSString stringWithFormat:@"%@ has already been downloaded from Dropbox. You can overwrite the local version with the Dropbox file. The file in Dropbox is newer than the local file.", file.title];
                
                NSDictionary *infoDictionary = @{@"file": file, @"message": @"File already exists in Dropbox and locally. The Dropbox file is newer."};
                NSError *error = [NSError errorWithDomain:@"[DropboxBrowser] File Conflict Error: File already exists in Dropbox and locally. The Dropbox file is newer." code:kGDriveFileNewerError userInfo:infoDictionary];
                
                if ([self.rootViewDelegate respondsToSelector:@selector(gdriveExplorer:fileConflictWithLocalFile:withGDriveFile:withError:)]) {
                    [self.rootViewDelegate gdriveExplorer:self fileConflictWithLocalFile:fileUrl withGDriveFile:file withError:error];
                }
            } else if (result == NSOrderedSame) {
                // Dropbox File and local file were both modified at the same time
                alertView.message = [NSString stringWithFormat:@"%@ has already been downloaded from Dropbox. You can overwrite the local version with the Dropbox file. Both the local file and the Dropbox file were modified at the same time.", file.title];
                
                NSDictionary *infoDictionary = @{@"file": file, @"message": @"File already exists in Dropbox and locally. Both files were modified at the same time."};
                NSError *error = [NSError errorWithDomain:@"[DropboxBrowser] File Conflict Error: File already exists in Dropbox and locally. Both files were modified at the same time." code:kGDriveFileSameAsLocalFileError userInfo:infoDictionary];
                
                if ([self.rootViewDelegate respondsToSelector:@selector(gdriveExplorer:fileConflictWithLocalFile:withGDriveFile:withError:)]) {
                    [self.rootViewDelegate gdriveExplorer:self fileConflictWithLocalFile:fileUrl withGDriveFile:file withError:error];
                }
            }
            
            [self presentViewController:alertView animated:YES completion:nil];
            
            [self updateTableData];
        } else {
            downloadSuccess = NO;
        }
    }
    
    return downloadSuccess;
}

- (void)downloadedFile {
    self.tableView.userInteractionEnabled = YES;
    
    [UIView animateWithDuration:0.75 animations:^{
        self.tableView.alpha = 1.0;
        downloadProgressView.alpha = 0.0;
    }];
    
    [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:YES];
    
    UIAlertController *alertView = [UIAlertController alertControllerWithTitle:NSLocalizedString(@"File Downloaded", @"Dropbox confirmation view title")
                                                                       message:[NSString stringWithFormat:@"%@ was downloaded from Dropbox.", currentFileName]
                                                                preferredStyle:UIAlertControllerStyleAlert];
    
    [alertView addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Ok", @"Dismiss the message alert view") style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {}]];
    
    [self presentViewController:alertView animated:YES completion:nil];
    
    // Deliver File Download Notification
    if (deliverDownloadNotifications == YES) {
        UILocalNotification *localNotification = [[UILocalNotification alloc] init];
        localNotification.alertBody = [NSString stringWithFormat:@"Downloaded %@ from Google Drive", currentFileName];
        localNotification.soundName = UILocalNotificationDefaultSoundName;
        [[UIApplication sharedApplication] presentLocalNotificationNow:localNotification];
        
        if ([[self rootViewDelegate] respondsToSelector:@selector(gdriveExplorer:deliveredFileDownloadNotification:)])
            [[self rootViewDelegate] gdriveExplorer:self deliveredFileDownloadNotification:localNotification];
    }
    
    if ([self.rootViewDelegate respondsToSelector:@selector(dropboxBrowser:didDownloadFile:didOverwriteFile:)])
        [self.rootViewDelegate gdriveExplorer:self didDownloadFile:currentFileName didOverwriteFile:isLocalFileOverwritten];
    
    // End the background task
    [[UIApplication sharedApplication] endBackgroundTask:backgroundProcess];
    
    [self removeDropboxBrowser];
}


- (void)updateTableData {
    [self.tableView deselectRowAtIndexPath:[self.tableView indexPathForSelectedRow] animated:YES];
    
    [self.tableView reloadData];
    [self.refreshControl endRefreshing];
}

- (void)startDownloadFile {
    [self.downloadProgressView setProgress:0.0];
    [UIView animateWithDuration:0.75 animations:^{
        downloadProgressView.alpha = 1.0;
    }];
}

- (void)removeDropboxBrowser {
    [self dismissViewControllerAnimated:YES completion:^{
        if ([[self rootViewDelegate] respondsToSelector:@selector(gdriveExplorerDismissed:)])
            [[self rootViewDelegate] gdriveExplorerDismissed:self];
    }];
}

- (GTLServiceDrive *)driveService {
    static GTLServiceDrive *service = nil;
    
    if (!service) {
        service = [[GTLServiceDrive alloc] init];
        
        // Have the service object set tickets to fetch consecutive pages
        // of the feed so we do not need to manually fetch them.
        service.shouldFetchNextPages = YES;
        
        // Have the service object set tickets to retry temporary error conditions
        // automatically.
        service.retryEnabled = YES;
    }
    return service;
}

- (IBAction)refreshButtonClicked:(id)sender {
    [self loadDriveFiles];
}

- (void)loadDriveFiles {
    GTLQueryDrive *query = [GTLQueryDrive queryForFilesList];
    query.q = [NSString stringWithFormat:@"'%@' in parents", currentPath];
    
    [self.driveService executeQuery:query completionHandler:^(GTLServiceTicket *ticket,
                                                              GTLDriveFileList *files,
                                                              NSError *error) {
        if (error == nil) {
            if (self.driveFiles == nil) {
                self.driveFiles = [[NSMutableArray alloc] init];
            }
            [self.driveFiles removeAllObjects];
            [self.driveFiles addObjectsFromArray:files.items];
            [self.tableView reloadData];
        } else {
            NSLog(@"An error occurred: %@", error);
        }
    }];
}

@end
