//
//  CocoaButton.m
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 11/08/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "CocoaButton.h"

#import "Accounts.h"
#import "ViewController.h"


@interface CocoaButton()

@property (nonatomic) NSInteger openState;

@property (nonatomic, weak) UIView* backView;
@property (nonatomic, weak) UILabel* nameView;

@property (nonatomic, strong) NSArray* subviewsWide;
@property (nonatomic, strong) NSArray* subviewsHorizontal;

@property (nonatomic, weak) UIView* tempMainButton;

@property (nonatomic, strong) CADisplayLink* displayLink;
@property (nonatomic, weak) UIView* backViewAnim;
@property (nonatomic) double backViewAnimAngle;

@property (nonatomic) BOOL isSpinning;

@end


@interface AccountButton : UIView

-(instancetype) initForButton:(UIButton*)b;

@property (nonatomic, weak) UIButton* realButton;
@property (nonatomic, weak) CocoaButton* father;


@end

@implementation CocoaButton

+(instancetype) sharedButton
{
    static dispatch_once_t once;
    static CocoaButton * sharedInstance;
    
    dispatch_once(&once, ^{
        sharedInstance = [[self alloc] init];
    });
    
    return sharedInstance;
}

+(instancetype) fakeCocoaButtonForCredits
{
    CocoaButton* cb = [[CocoaButton alloc] init];
    
    cb.backView.backgroundColor = [UIColor colorWithRed:0.63 green:0.33 blue:0.18 alpha:0.9];
    
    cb.nameView.text = @"";
    
    UIImageView* iv = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"credits_cocoabutton"]];
    iv.contentMode = UIViewContentModeCenter;
    iv.frame = cb.nameView.bounds;
    [cb.nameView addSubview:iv];
    
    NSArray* alls = cb.gestureRecognizers;
    
    for (UIGestureRecognizer* gr in alls) {
        if ([gr isKindOfClass:[UILongPressGestureRecognizer class]]) {
            [cb removeGestureRecognizer:gr];
        }
    }
    
    return cb;
}

-(instancetype) init
{
    self = [super init];
    
    self.frame = CGRectMake(0, 0, 44, 44);
    
    Account* cac = [[Accounts sharedInstance] currentAccount];
    
    self.isSpinning = NO;
    
    self.backgroundColor = [UIColor clearColor];
    
    UIView* background = [[UIView alloc] initWithFrame:self.bounds];
    background.backgroundColor = cac.userColor;
    background.layer.cornerRadius = 22;
    background.layer.masksToBounds = YES;
    [self addSubview:background];
    self.backView = background;
    
    UITapGestureRecognizer* tgr = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_tap:)];
    [self addGestureRecognizer:tgr];
    self.userInteractionEnabled = YES;
    
    UILongPressGestureRecognizer* lpgr = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(_lgpress:)];
    lpgr.minimumPressDuration = .5;
    [self addGestureRecognizer:lpgr];
    
    
    UILabel* l = [[UILabel alloc] initWithFrame:self.bounds];
    l.backgroundColor = [UIColor clearColor];
    l.textColor = [UIColor whiteColor];
    l.textAlignment = NSTextAlignmentCenter;
    l.text = cac.codeName;
    l.font = [UIFont systemFontOfSize:13];
    [self addSubview:l];
    self.nameView = l;
    
    return self;
}

-(void) openWide
{
    if (self.openState == 0) {
        [self _openWide];
    }
}

-(void) updateColor
{
    Account* cac = [[Accounts sharedInstance] currentAccount];
    self.backView.backgroundColor = cac.userColor;
    self.nameView.text = cac.codeName;
    self.backViewAnim.backgroundColor = cac.userColor;
}

-(void) enterLevel:(NSInteger)level
{
    self.userInteractionEnabled = YES;
    self.nameView.text = @"";

    UIImage* imageLevel;

    switch (level) {
        case 1: //List
            imageLevel = [UIImage imageNamed:@"swipe_cocoabutton_folder"];
            
            break;
            
        case 2: //Conversation
            imageLevel = [UIImage imageNamed:@"swipe_cocoabutton_spam"];
            
            break;
            
        default:
            break;
    }
    
    UIImageView* iv = [[UIImageView alloc] initWithImage:imageLevel];
    iv.contentMode = UIViewContentModeCenter;
    iv.frame = self.nameView.bounds;
    [self.nameView addSubview:iv];
    
    Account* cac = [[Accounts sharedInstance] currentAccount];

    [UIView animateWithDuration:0.01
                          delay:0.12
                        options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
                         self.transform = CGAffineTransformMakeScale(0.84f, 1.f);
                     }
                     completion:^(BOOL fini){
                         [self _boingAnimationForView:self andThen:^{
                             self.userInteractionEnabled = YES;
                             self.openState = 0;
                             
                             for (UIView* iv in [self.nameView subviews]) {
                                 [iv removeFromSuperview];
                             }
                             
                             self.nameView.text = cac.codeName;
                         }];
                     }];

}

-(void) refreshAnimation:(BOOL)anim
{
    if (anim && !self.isSpinning) {
        self.isSpinning = YES;
        if (self.backViewAnim==nil) {
            UIView* background = [[UIView alloc] initWithFrame:self.bounds];
            background.backgroundColor = self.backView.backgroundColor;
            background.layer.cornerRadius = 22;
            background.layer.masksToBounds = YES;
            [self insertSubview:background belowSubview:self.backView];
            self.backViewAnim = background;
        }
        
        if (self.displayLink==nil) {
            
            
            [UIView animateWithDuration:0.1
                             animations:^{
                                 [self _displayLink:nil];
                             }
                             completion:^(BOOL fini){
                                 CADisplayLink* dl = [CADisplayLink displayLinkWithTarget:self selector:@selector(_displayLink:)];
                                 [dl addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
                                 self.displayLink = dl;
                             }];
        }
        
    }
    else if (!anim) {
        self.isSpinning = NO;
        [UIView animateWithDuration:0.1
                         animations:^{
                             CGPoint center = self.backView.center;
                             self.backViewAnim.center = center;
                             
                         }
                         completion:^(BOOL fini){
                             [self.backViewAnim removeFromSuperview];
                             self.backViewAnim = nil;
                         }];
        
        [self.displayLink invalidate];
        self.displayLink = nil;
    }
    
}

-(void) _displayLink:(CADisplayLink*)dl
{
    //    double value = [dl timestamp] * M_PI * 4;
    const double step = M_PI / 10.;
    
    self.backViewAnimAngle += step;
    double value = self.backViewAnimAngle;
    
    const CGFloat deltamax = 1.5f;
    const CGFloat deltaX = deltamax * cos(value);
    const CGFloat deltaY = deltamax * sin(value);
    
    CGPoint center = self.backView.center;
    center.x += deltaX;
    center.y += deltaY;
    self.backViewAnim.center = center;
}

-(void) _forceCloseButtonSkipDatasource
{
    [self replaceMainButton:nil];
    
    if (self.openState == 0) {
    }
    else if (self.openState == 2) {
        [self _closeHorizontal];
    }
    else {
        [self _closeWide];
    }
    
    self.openState = 0;
}

-(void) forceCloseButton
{
    if ([self.datasource automaticCloseFor:self]==NO) {
        return;
    }
    
    [self _forceCloseButtonSkipDatasource];
}

-(void) forceCloseHorizontal
{
    if (self.openState == 2) {
        [self replaceMainButton:nil];
        [self _closeHorizontal];
        self.openState = 0;
    }
}

-(void) closeHorizontalButton:(UIButton*)button refreshCocoaButtonAndDo:(void (^)())action
{
    self.userInteractionEnabled = NO;
    
    AccountButton* supportV = (AccountButton*)[button superview];
    [supportV.superview bringSubviewToFront:supportV];
    
    [UIView animateWithDuration:0.15
                          delay:0.
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
                         for (UIView* v in self.subviewsHorizontal) {
                             if (v != supportV) {
                                 v.alpha = 0;
                                 v.transform = CGAffineTransformIdentity;
                             }
                             else {
                                 v.transform = CGAffineTransformMakeScale(0.84f, 1.f);
                             }
                         }
                     }
                     completion:^(BOOL fini){
                         self.openState = 0;
                         
                         for (UIView* v in self.subviewsHorizontal) {
                             if (v != supportV) {
                                 [v removeFromSuperview];
                             }
                         }
                         self.subviewsHorizontal = nil;
                         
                         if (action != nil) {
                             action();
                         }
                     }];
    
    [UIView animateWithDuration:0.01
                          delay:0.12
                        options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
                         self.backView.alpha = 0;
                     }
                     completion:^(BOOL fini){
                         [self _makeAppearNewCocoaButtonFromView:supportV];
                     }];
}

-(void) _makeAppearNewCocoaButtonFromView:(AccountButton*)button
{
    [self _boingAnimationForView:button andThen:^{
        [ViewController refreshCocoaButton];
        self.backView.alpha = 1.0;
        [button removeFromSuperview];
        
        self.userInteractionEnabled = YES;
    }];
}

-(void) _boingAnimationForView:(UIView*)boing andThen:(void(^)())endAction
{
    
    double longtime = 0.4;
    NSArray* steps = @[ @(1.11f), @(0.89f), @(1.05f), @(0.95f), @(1.02f), @(0.98f), @(1.f)];
    double smallTime =  1.0 / [steps count];
    
    [UIView animateKeyframesWithDuration:longtime
                                   delay:0.0
                                 options:UIViewKeyframeAnimationOptionCalculationModeCubic
                              animations:^{
                                  
                                  NSInteger idx = 0;
                                  
                                  for (NSNumber* n in steps) {
                                      [UIView addKeyframeWithRelativeStartTime:smallTime * idx
                                                              relativeDuration:smallTime
                                                                    animations:^{
                                                                        boing.transform = CGAffineTransformMakeScale([n floatValue], 1.f);
                                                                    }];
                                      idx++;
                                  }
                              }
                              completion:^(BOOL fini){
                                  
                                  if (endAction) {
                                      endAction();
                                  }
                              }];
}

-(void) _openHorizontal
{
    NSArray* realButtons = [self.datasource buttonsHorizontalFor:self];
    NSMutableArray* buttons = [NSMutableArray arrayWithCapacity:realButtons.count];
    
    for (UIButton* b in realButtons) {
        AccountButton* ab = [[AccountButton alloc] initForButton:b];
        [buttons addObject:ab];
        
        [self insertSubview:ab belowSubview:self.backView];
        ab.userInteractionEnabled = YES;
        ab.center = CGPointMake(22, 22);
        ab.alpha = 0;
    }
    self.subviewsHorizontal = buttons;
    
    self.userInteractionEnabled = NO;
    
    [UIView animateWithDuration:0.3
                          delay:0.
         usingSpringWithDamping:0.7
          initialSpringVelocity:0.3
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{
                         
                         const CGFloat stepX = -(52.f + ([UIScreen mainScreen].bounds.size.width - 320.f) / 5.f);
                         
                         CGFloat nextPosX = 0.f;
                         
                         for (UIButton* b in buttons) {
                             nextPosX += stepX;
                             b.alpha = 1;
                             b.transform = CGAffineTransformMakeTranslation(nextPosX, 0);
                         }
                         
                     }
                     completion:^(BOOL fini){
                         self.userInteractionEnabled = YES;
                         self.openState = 2;
                     }];
    
}

-(void) _closeHorizontal
{
    self.userInteractionEnabled = NO;
    
    [UIView animateWithDuration:0.15
                          delay:0.
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
                         for (UIView* v in self.subviewsHorizontal) {
                             v.alpha = 0;
                             v.transform = CGAffineTransformIdentity;
                         }
                         
                     }
                     completion:^(BOOL fini){
                         for (UIView* v in self.subviewsHorizontal) {
                             [v removeFromSuperview];
                         }
                         self.subviewsHorizontal = nil;
                     }];
    
    [UIView animateWithDuration:0.01
                          delay:0.12
                        options:UIViewAnimationOptionBeginFromCurrentState
                     animations:^{
                         self.transform = CGAffineTransformMakeScale(0.84f, 1.f);
                     }
                     completion:^(BOOL fini){
                         [self _boingAnimationForView:self andThen:^{
                             self.userInteractionEnabled = YES;
                             self.openState = 0;
                         }];
                     }];
    
}

-(void) openHorizontal
{
    if (self.openState==0) {
        [self _openHorizontal];
    }
}

-(void) forceOpenHorizontal
{
    if (self.openState==0) {
        [self _openHorizontal];
    }
    else if (self.openState == 1) {
        [UIView animateWithDuration:0.2
                         animations:^{
                             [self _forceCloseButtonSkipDatasource];
                         }
                         completion:^(BOOL fini){
                             [self _openHorizontal];
                         }];
    }
    else if (self.openState == 2) {
        
        for (UIView* v in self.subviewsHorizontal) {
            [v removeFromSuperview];
        }
        self.subviewsHorizontal = nil;
        
        NSArray* realButtons = [self.datasource buttonsHorizontalFor:self];
        NSMutableArray* buttons = [NSMutableArray arrayWithCapacity:realButtons.count];
        
        const CGFloat stepX = -(52.f + ([UIScreen mainScreen].bounds.size.width - 320.f) / 5.f);
        CGFloat nextPosX = 0.f;
        
        for (UIButton* b in realButtons) {
            AccountButton* ab = [[AccountButton alloc] initForButton:b];
            [buttons addObject:ab];
            
            [self insertSubview:ab belowSubview:self.backView];
            ab.userInteractionEnabled = YES;
            ab.center = CGPointMake(22, 22);
            ab.alpha = 1;
            
            nextPosX += stepX;
            ab.transform = CGAffineTransformMakeTranslation(nextPosX, 0);
        }
        self.subviewsHorizontal = buttons;
    }
}

-(void) _openWide
{
    NSArray* buttons = [self.datasource buttonsWideFor:self];
    
    self.subviewsWide = buttons;
    
    for (UIButton* b in buttons) {
        [self addSubview:b];
        b.userInteractionEnabled = YES;
        
        b.center = CGPointMake(22, 22);
        b.alpha = 0;
    }
    
    NSArray* steps = nil;
    
    const CGFloat base = 110.f;
    
    if (buttons.count == 3) {
        
        CGFloat mid = floorf(base * cosf(M_PI_4));
        steps = @[[NSValue valueWithCGAffineTransform:CGAffineTransformMakeTranslation(0, -base)],
                  [NSValue valueWithCGAffineTransform:CGAffineTransformMakeTranslation(-mid, -mid)],
                  [NSValue valueWithCGAffineTransform:CGAffineTransformMakeTranslation(-base, 0)]
                  ];
    }
    else if (buttons.count==4) {
        
        CGFloat mid1 = floorf(base * cosf(M_PI / 3.));
        CGFloat mid2 = floorf(base * cosf(M_PI / 6.));
        steps = @[[NSValue valueWithCGAffineTransform:CGAffineTransformMakeTranslation(0, -base)],
                  [NSValue valueWithCGAffineTransform:CGAffineTransformMakeTranslation(-mid1, -mid2)],
                  [NSValue valueWithCGAffineTransform:CGAffineTransformMakeTranslation(-mid2, -mid1)],
                  [NSValue valueWithCGAffineTransform:CGAffineTransformMakeTranslation(-base, 0)]
                  ];
    }
    else {
        NSLog(@"COCOABUTTON : 3 ou 4 buttons only !!!");
        return;
    }
    
    [UIView animateWithDuration:0.3
                          delay:0.
         usingSpringWithDamping:0.7
          initialSpringVelocity:0.3
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{
                         CGFloat scale = 290.f / 44.f;
                         self.backView.transform = CGAffineTransformMakeScale(scale, scale);
                         
                         NSInteger idx = 0;
                         
                         for (UIButton* b in buttons) {
                             b.alpha = 1;
                             b.transform = [steps[idx] CGAffineTransformValue];
                             idx++;
                         }
                     }
                     completion:^(BOOL fini){
                         self.openState = 1;
                     }];
}

-(void) _closeWide
{
    self.userInteractionEnabled = NO;
    
    [UIView animateWithDuration:0.3
                          delay:0.
         usingSpringWithDamping:0.7
          initialSpringVelocity:0.3
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{
                         self.backView.transform = CGAffineTransformIdentity;
                         
                         for (UIView* v in self.subviewsWide) {
                             v.alpha = 0;
                             v.transform = CGAffineTransformIdentity;
                         }
                         
                     }
                     completion:^(BOOL fini){
                         self.userInteractionEnabled = YES;
                         self.openState = 0;
                         
                         for (UIView* v in self.subviewsWide) {
                             [v removeFromSuperview];
                         }
                         self.subviewsWide = nil;
                     }];
}

-(void) _lgpress:(UILongPressGestureRecognizer*)lpgr
{
    if (lpgr.enabled==NO || self.openState != 0) {
        return;
    }
    
    if (lpgr.state == UIGestureRecognizerStateBegan) {
        
        lpgr.enabled = NO;
        lpgr.enabled = YES;
        
        if ([self.datasource cocoabuttonLongPress:self]) {
            [self _openHorizontal];
        }
    }
}

-(void) _tap:(UITapGestureRecognizer*)tgr
{
    if (tgr.enabled==NO || tgr.state!=UIGestureRecognizerStateEnded) {
        return;
    }
    
    if (self.openState == 0) {
        
        if (self.subviewsWide.count>0) {
            [[NSNotificationCenter defaultCenter] postNotificationName:kPRESENT_EDITMAIL_NOTIFICATION object:nil];
            [self _closeWide];
            return;
        }
        else {
            [self _openWide];
        }
    }
    else if (self.openState == 1) {
        
        CGRect bigger = CGRectInset(self.bounds, -15, -15);
        CGPoint pos = [tgr locationInView:tgr.view];
        
        if (!CGRectContainsPoint(bigger, pos)) {
            return;
        }
        
        [self _closeWide];
        
    }
    else if (self.openState == 2) {
        CGRect bigger = CGRectInset(self.bounds, -15, -15);
        CGPoint pos = [tgr locationInView:tgr.view];
        
        if (!CGRectContainsPoint(bigger, pos)) {
            return;
        }
        
        [self _closeHorizontal];
    }
    
}

-(void) replaceMainButton:(UIButton*)button
{
    [self.tempMainButton removeFromSuperview];
    [self addSubview:button];
    self.tempMainButton = button;
}

-(UIView*) hitTest:(CGPoint)point withEvent:(UIEvent*)event
{
    
    for (UIView* v in self.subviewsWide) {
        CGRect bigger = CGRectInset(v.frame, -10, -10);
        
        if (CGRectContainsPoint(bigger, point)) {
            return v;
        }
    }
    
    for (AccountButton* v in self.subviewsHorizontal) {
        CGRect bigger = CGRectInset(v.frame, -10, -10);
        
        if (CGRectContainsPoint(bigger, point)) {
            return v.realButton;
        }
    }
    
    
    CGFloat radius = self.backView.frame.size.height / 2.f;
    
    CGFloat posInRadiusX = point.x - 22.f;
    CGFloat posInRadiusY = point.y - 22.f;
    
    CGFloat distSqrt = posInRadiusX * posInRadiusX + posInRadiusY * posInRadiusY;
    CGFloat radiusSqrt = (radius + 15) * (radius + 15);
    
    if (distSqrt < radiusSqrt) {
        
        if (self.tempMainButton!=nil) {
            return self.tempMainButton;
        }
        
        return self;
    }
    
    return nil;
}

+(void) animateHorizontalButtonCancelTouch:(UIButton*)button
{
    [UIView animateWithDuration:0.15
                          delay:0.
         usingSpringWithDamping:0.5
          initialSpringVelocity:0.3
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{
                         CGFloat scale = 33.f / 44.f;
                         button.transform = CGAffineTransformScale(button.transform, scale, scale);
                     }
                     completion:^(BOOL fini){
                     }];
}


@end

@implementation AccountButton

-(instancetype) initForButton:(UIButton*)b
{
    self = [super init];
    
    self.backgroundColor = [UIColor clearColor];
    self.frame = CGRectMake(0, 0, 44, 44);
    
    [b addTarget:self action:@selector(_touchButton:) forControlEvents:UIControlEventTouchDown];
    [b addTarget:self action:@selector(_touchButton:) forControlEvents:UIControlEventTouchDragEnter];
    [b addTarget:self action:@selector(_cancelTouchButton:) forControlEvents:UIControlEventTouchDragExit];
    [b addTarget:self action:@selector(_cancelTouchButton:) forControlEvents:UIControlEventTouchCancel];
    
    [self addSubview:b];
    self.realButton = b;
    
    CGFloat scale = 33.f / 44.f;
    b.transform = CGAffineTransformMakeScale(scale, scale);
    
    self.userInteractionEnabled = YES;
    b.userInteractionEnabled = YES;
    
    return self;
}

-(void) _touchButton:(UIButton*)button
{
    [UIView animateWithDuration:0.15
                          delay:0.
         usingSpringWithDamping:0.5
          initialSpringVelocity:0.3
                        options:UIViewAnimationOptionCurveEaseInOut
                     animations:^{
                         button.transform = CGAffineTransformIdentity;
                     }
                     completion:^(BOOL fini){
                     }];
}

-(void) _cancelTouchButton:(UIButton*)button
{
    [CocoaButton animateHorizontalButtonCancelTouch:button];
    /*
     [UIView animateWithDuration:0.15
     delay:0.
     usingSpringWithDamping:0.5
     initialSpringVelocity:0.3
     options:UIViewAnimationOptionCurveEaseInOut
     animations:^{
     CGFloat scale = 33.f/44.f;
     button.transform = CGAffineTransformScale(button.transform, scale, scale);
     }
     completion:^(BOOL fini){
     }];
     */
}


@end