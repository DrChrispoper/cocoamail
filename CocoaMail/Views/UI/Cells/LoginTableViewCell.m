//
//  LoginTableViewCell.m
//  CocoaMail
//
//  Created by Christopher Hockley on 21/03/16.
//  Copyright © 2016 Christopher Hockley. All rights reserved.
//

#import "LoginTableViewCell.h"
#import "OnePasswordExtension.h"

@interface LoginTableViewCell ()

@property (nonatomic, weak) UIView* baseView;
@property (nonatomic, weak) UITextField* name;
@property (nonatomic, weak) UIButton* onePassword;

@end

@implementation LoginTableViewCell

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];
}

-(void) setup
{
    self.backgroundColor = [UIColor clearColor];
    self.selectionStyle = UITableViewCellSelectionStyleGray;
    
    UIView* back = nil;
    
    CGRect screenBounds = [UIScreen mainScreen].bounds;

    CGFloat WIDTH = screenBounds.size.width;
    CGFloat height = 44;
    
    UIImage* rBack = [[UIImage imageNamed:@"cell_mail_unread"] resizableImageWithCapInsets:UIEdgeInsetsMake(22, 30, 22, 30)];
    UIImageView* inIV = [[UIImageView alloc] initWithImage:rBack];
    inIV.frame = CGRectMake(8 , 0 , WIDTH - 16, height);
    back = inIV;
    
    UITextField* tf = [[UITextField alloc] initWithFrame:CGRectMake(20, 0, inIV.bounds.size.width - 20, 45)];
    tf.autocorrectionType = UITextAutocorrectionTypeNo;
    tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    
    [inIV addSubview:tf];
    
    self.name = tf;
    
    UIButton* fav = [[UIButton alloc] initWithFrame:CGRectMake(inIV.bounds.size.width - 33.f - 5.5, 5.5, 33.F, 33.F)];
    [fav setImage:[UIImage imageNamed:@"onepassword-toolbar"] forState:UIControlStateNormal];
    [fav setImage:[UIImage imageNamed:@"onepassword-toolbar-light"] forState:UIControlStateHighlighted];

    fav.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [inIV addSubview:fav];
    
    self.onePassword = fav;
    
    inIV.clipsToBounds = YES;
    
    self.baseView = back;
    
    [self.contentView addSubview:back];
}

-(UITextField*) fillWithPlaceholder:(NSString *)placeholder oP:(id<OPDelegate>)delegate
{
    if (self.baseView == nil) {
        [self setup];
    }
    
    self.baseView.alpha = 1.f;
    self.onePassword.hidden = YES;

    self.name.placeholder = placeholder;
    
    if ([placeholder isEqualToString:@"Password"]) {
        if ([[OnePasswordExtension sharedExtension] isAppExtensionAvailable]) {
            self.onePassword.hidden = NO;
            [self.onePassword addTarget:delegate action:@selector(findLoginFrom1Password:) forControlEvents:UIControlEventTouchUpInside];
        }
        self.name.secureTextEntry = YES;
        self.name.returnKeyType = UIReturnKeyDone;
    }
    else if ([placeholder isEqualToString:@"Email"]) {
        self.name.keyboardType = UIKeyboardTypeEmailAddress;
        self.name.returnKeyType = UIReturnKeyNext;
    }

    return self.name;
}

-(void) fillWithButton:(NSString *)placeholder
{
    if (self.baseView == nil) {
        [self setup];
    }

    self.baseView.alpha = .5f;
    self.onePassword.hidden = YES;

    self.name.text = placeholder;
    self.name.textAlignment = NSTextAlignmentCenter;
}

@end
