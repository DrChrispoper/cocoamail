//
//  SignatureViewController.m
//  CocoaMail
//
//  Created by Christopher Hockley on 28/10/15.
//  Copyright © 2015 Christopher Hockley. All rights reserved.
//

#import "SignatureViewController.h"
#import "AppSettings.h"
#import "Accounts.h"

@interface SignatureViewController () <UITextViewDelegate>

@property (nonatomic, weak) UITextView* signature;

@end

@implementation SignatureViewController

-(void) viewDidLoad
{
    [super viewDidLoad];
    
    
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    
    UINavigationItem* item = [[UINavigationItem alloc] initWithTitle:@""];
    
    item.leftBarButtonItem = [self backButtonInNavBar];
    
    NSString* title = NSLocalizedString(@"signature-view.title", @"Signature");
    item.titleView = [WhiteBlurNavBar titleViewForItemTitle:title];
    
    UITextView* tf = [[UITextView alloc] initWithFrame:CGRectMake(0, 44.f, screenBounds.size.width, screenBounds.size.height-44)];
    tf.text = [AppSettings signature:self.account.idx];
    tf.delegate = self;
    tf.scrollEnabled = false;
    [tf setFont:[UIFont systemFontOfSize:16]];
    
    self.signature = tf;
    
    [self setupSimpleNavBarWith:item andWidth:screenBounds.size.width];
    
    [self.view addSubview:self.signature];
}

-(void) cleanBeforeGoingBack
{
    [AppSettings setSignature:self.signature.text accountIndex:self.account.idx];
}

-(BOOL) haveCocoaButton
{
    return NO;
}

#pragma mark TextView Delegate

/*-(void) textViewDidChange:(UITextView *)textView
{
    CGSize size = textView.frame.size;
    CGSize newSize = [textView sizeThatFits:CGSizeMake(size.width, CGFLOAT_MAX)];
    
    if (size.height != newSize.height) {
        self.signature.frame = textView.frame;
    }
}*/

@end
