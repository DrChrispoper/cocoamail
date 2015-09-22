//
//  EditCocoaButtonView.m
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 05/09/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "EditCocoaButtonView.h"

#import "Accounts.h"
#import "AppSettings.h"

@interface ChooseColorView : UIView

-(instancetype) initWithFrame:(CGRect)frame forAccountColor:(UIColor*)color;

@property (nonatomic, copy) void (^tapColor)(UIColor*);

-(void) updateForAccount:(Account*)account;

@end


@interface EditCocoaButtonView () <UITextFieldDelegate>

@property (nonatomic, weak) ChooseColorView* color;
@property (nonatomic, weak) UITextField* codename;

@end



@implementation EditCocoaButtonView

+(instancetype) editCocoaButtonViewForAccount:(Account*)account
{
    CGSize bounds = [UIScreen mainScreen].bounds.size;
    EditCocoaButtonView* v = [[EditCocoaButtonView alloc] initWithFrame:CGRectMake(0, 0, bounds.width, 131)];
    v.account = account;
    [v setup];
    return v;
}


-(void) setup
{
    self.backgroundColor = [UIColor whiteColor];
    
    ChooseColorView* ccv = [[ChooseColorView alloc] initWithFrame:CGRectMake(0, 11.f, self.bounds.size.width, 52.f)
                                                  forAccountColor:self.account.userColor];
    
    [ccv updateForAccount:self.account];
    ccv.tapColor = ^(UIColor* color) {
        self.account.userColor = color;
        [AppSettings setColor:color accountNum:self.account.accountNum];

        if (self.cocobuttonUpdated != nil) {
            self.cocobuttonUpdated();
        }
        
    };
    
    [self addSubview:ccv];
    self.color = ccv;
    
    UITextField* tf = [[UITextField alloc] initWithFrame:CGRectMake(50, 52 + 22, self.bounds.size.width - 100, 57)];
    tf.textAlignment = NSTextAlignmentCenter;
    tf.autocapitalizationType = UITextAutocapitalizationTypeAllCharacters;
    tf.autocorrectionType = UITextAutocorrectionTypeNo;
    tf.text = self.account.codeName;
    tf.delegate = self;
    [self addSubview:tf];
    self.codename = tf;
}


-(void) becomeFirstResponder
{
    [self.codename becomeFirstResponder];
}


-(BOOL) textFieldShouldReturn:(UITextField *)textField
{
    [textField resignFirstResponder];
    return YES;
}

-(BOOL) textField:(UITextField *)textField shouldChangeCharactersInRange:(NSRange)range replacementString:(NSString *)string
{
    NSString* newText = [textField.text stringByReplacingCharactersInRange:range withString:string];
    
    if (newText.length<4) {
        textField.text = [newText uppercaseString];
        self.account.codeName = textField.text;
        [self.color updateForAccount:self.account];
        
        if (self.cocobuttonUpdated != nil) {
            self.cocobuttonUpdated();
        }
        
    }
    
    return NO;
}


@end






@interface ChooseColorView ()

@property (nonatomic, strong) NSArray* colors;
@property (nonatomic, weak) UILabel* codenameLbl;

@end





@implementation ChooseColorView

-(instancetype) initWithFrame:(CGRect)frame forAccountColor:(UIColor*)accColor
{
    self = [super initWithFrame:frame];
    
    self.backgroundColor = [UIColor whiteColor];
    
    const CGFloat BIG = 44.f;
    const CGFloat halfBIG = BIG / 2.f;
    
    
    CGFloat posX = 8.f + halfBIG;
    const CGFloat step = (frame.size.width - (2.f*posX))/6.f;
    
    NSArray* allColors = [Accounts sharedInstance].accountColors;
    
    NSMutableArray* c = [NSMutableArray arrayWithCapacity:allColors.count];
    
    NSInteger wantedIdx = 0;
    
    for (UIColor* color in allColors) {
        
        if (color == accColor) {
            wantedIdx = [allColors indexOfObject:color];
        }
        
        UIView* v = [[UIView alloc] initWithFrame:CGRectMake(posX-halfBIG, 4, BIG, BIG)];
        v.layer.cornerRadius = halfBIG;
        v.layer.masksToBounds = YES;
        v.backgroundColor = color;
        [self addSubview:v];
        
        [c addObject:v];
        
        posX = floorf(posX + step);
        
    }

    
    UILabel* l = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, BIG, BIG)];
    l.textAlignment = NSTextAlignmentCenter;
    l.textColor = [UIColor whiteColor];
    l.backgroundColor = [UIColor clearColor];
    l.alpha = 0.f;
    l.font = [UIFont systemFontOfSize:13];
    
    [self addSubview:l];
    self.codenameLbl = l;
    
    self.colors = c;
    
    [UIView setAnimationsEnabled:NO];
    [self selectColorIdx:wantedIdx];
    [UIView setAnimationsEnabled:YES];
    
    UITapGestureRecognizer* tgr = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_tap:)];
    [self addGestureRecognizer:tgr];
    
    self.userInteractionEnabled = YES;
    
    return self;
}

-(void) selectColorIdx:(NSInteger)idx
{
    CGFloat scale = 26.f / 44.f;
    
    UIView* selected = self.colors[idx];
    
    self.codenameLbl.alpha = 0.f;
    [UIView animateWithDuration:0.3
                     animations:^{
                         
                         for (UIView* v in self.colors) {
                             if (v==selected) {
                                 v.transform = CGAffineTransformIdentity;
                                 [v addSubview:self.codenameLbl];
                                 self.codenameLbl.alpha = 1.f;
                             }
                             else {
                                 v.transform = CGAffineTransformMakeScale(scale, scale);
                             }
                         }
                     }];
}

-(void)_tap:(UITapGestureRecognizer*)tgr
{
    if (tgr.state != UIGestureRecognizerStateEnded || !tgr.enabled) {
        return;
    }
    
    CGPoint pos = [tgr locationInView:tgr.view];
    
    CGFloat step = self.bounds.size.width / 7.f;
    
    NSInteger posX = (NSInteger)(pos.x / step);
    
    if (posX<0) {
        posX = 0;
    }
    else if (posX>6) {
        posX = 6;
    }
    [self selectColorIdx:posX];
    
    UIColor* c = [Accounts sharedInstance].accountColors[posX];
    self.tapColor(c);
    
}

-(void) updateForAccount:(Account*)account
{
    self.codenameLbl.text = account.codeName;
}


@end



