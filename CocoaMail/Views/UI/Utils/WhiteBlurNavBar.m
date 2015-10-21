//
//  WhiteBlurNavBar.m
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 10/08/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "WhiteBlurNavBar.h"

#import "UIImage+ImageEffects.h"
#import "Accounts.h"
#import "UIGlobal.h"


@interface WhiteBlurNavBar ()

@property (nonatomic, weak) UIImageView* realBlurView;
@property (nonatomic, weak) UIView* underView;
@property (nonatomic, weak) UIView* whiteMask;

@property (nonatomic) CGFloat baseOffset;


@property (nonatomic, strong) UIImage* lastBlurredImage;
@property (nonatomic) CGFloat lastOffsetBlurred;
@property (nonatomic) CGFloat lastOffsetWanted;

@property (nonatomic, strong) CADisplayLink* displayLink;
@property (nonatomic, strong) NSDate* displayLinkEndDate;


@end

@implementation WhiteBlurNavBar

+(CGFloat) navBarHeight
{
    return 44.f;
}

+(UIButton*) navBarButtonWithImage:(NSString*)normal andHighlighted:(NSString*)high
{
    UIImage* imgOff = [[UIImage imageNamed:normal] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    UIImage* imgOn = [[UIImage imageNamed:high] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    
    UIButton* btn = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, 33, 33)];
    [btn setImage:imgOff forState:UIControlStateNormal];
    [btn setImage:imgOn forState:UIControlStateHighlighted];
    [btn setImage:imgOn forState:UIControlStateSelected];
    [btn setImage:imgOn forState:UIControlStateSelected|UIControlStateHighlighted];
    btn.tintColor = [UIColor blackColor];
    
    return btn;
}

+(UILabel*) titleViewForItemTitle:(NSString*)title
{
    UILabel* l = [[UILabel alloc] init];
    l.text = title;
    l.textColor = [UIColor blackColor];
    
    if ([Accounts sharedInstance].navBarBlurred) {
        l.backgroundColor = [UIColor clearColor];
    }
    else {
        l.backgroundColor = [UIColor whiteColor];
    }
    l.font = [UIFont boldSystemFontOfSize:16];
    l.textAlignment = NSTextAlignmentCenter;
    [l sizeToFit];
    
    return l;
}

-(instancetype) initWithWidth:(CGFloat)width
{
    self = [super initWithFrame:CGRectMake(0, 0, width, [WhiteBlurNavBar navBarHeight])];
    
    
    if ([Accounts sharedInstance].navBarBlurred) {
        self.opaque = false;
        [self setBackgroundImage:[UIImage imageNamed:@"emptyPixel"] forBarMetrics:UIBarMetricsDefault];
        [self setBackgroundImage:[UIImage imageNamed:@"emptyPixel"] forBarMetrics:UIBarMetricsCompact];
        self.shadowImage = [UIImage imageNamed:@"emptyPixel"];
        self.translucent = YES;
        self.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.6];
    }
    else {
        self.opaque = true;
        self.translucent = NO;
        self.backgroundColor = [UIColor whiteColor];
        
        UIView* border = [[UIView alloc] initWithFrame:CGRectMake(0, 43.5, width + 50, 0.5)];
        border.backgroundColor = [UIGlobal standardTableLineColor];
        [self addSubview:border];
    }
    
    self.tintColor = [UIColor blackColor];
    
    return self;
}

-(void) createWhiteMaskOverView:(UIView*)view withOffset:(CGFloat)offset
{
    if (![Accounts sharedInstance].navBarBlurred) {
        return;
    }
    
    self.baseOffset = -offset;
    self.underView = view;
    
    // create views needed for fast-blur
    
    UIView* support = [[UIView alloc] initWithFrame:CGRectMake(0, 0, self.frame.size.width, [WhiteBlurNavBar navBarHeight])];
    support.backgroundColor = [UIColor whiteColor];
    support.opaque = YES;
    support.clipsToBounds = YES;
    [self.underView.superview insertSubview:support aboveSubview:self.underView];
    
    UIImageView* blurredIV = [[UIImageView alloc] initWithFrame:CGRectMake(0, 0, self.frame.size.width, [WhiteBlurNavBar navBarHeight] * 3)];
    blurredIV.backgroundColor = [UIColor whiteColor];
    [support addSubview:blurredIV];
    self.realBlurView = blurredIV;
    
    UIView* mask = [[UIView alloc] initWithFrame:CGRectMake(-1, -1, support.bounds.size.width + 2, support.bounds.size.height + 1)];
    mask.backgroundColor = [UIColor whiteColor];
    [support addSubview:mask];
    mask.layer.borderWidth = 1.5f;
    mask.layer.borderColor = [UIColor colorWithWhite:0.95 alpha:1.0].CGColor;
    self.whiteMask = mask;
    mask.hidden = YES;
}

-(void) _displayLink:(CADisplayLink*)dl
{
    if ([self.displayLinkEndDate timeIntervalSinceNow]<=0) {
        [dl invalidate];
        self.displayLink = nil;
    }
    
    [self computeBlurForceNew];
}

-(void) computeBlurForceNewDuring:(double)timeInterval
{
    if (![Accounts sharedInstance].navBarBlurred) {
        return;
    }
    
    
    if (self.displayLink==nil) {
        CADisplayLink* dl = [CADisplayLink displayLinkWithTarget:self selector:@selector(_displayLink:)];
        [dl addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
        self.displayLink = dl;
    }
    
    self.displayLinkEndDate = [NSDate dateWithTimeIntervalSinceNow:timeInterval];
}

-(void) computeBlurForceNew
{
    if (![Accounts sharedInstance].navBarBlurred) {
        return;
    }
    
    CGFloat currentOffset = [(UIScrollView*)self.underView contentOffset].y;
    self.lastOffsetWanted = currentOffset;
    self.lastOffsetBlurred = currentOffset;
    
    [self _reallyComputeBlur];
    
    if (self.realBlurView.frame.origin.y != 0) {
        CGRect f = self.realBlurView.frame;
        f.origin.y = 0;
        self.realBlurView.frame = f;
    }

    self.realBlurView.image = self.lastBlurredImage;
}

-(void) _reallyComputeBlur
{
    
    UIGraphicsBeginImageContextWithOptions(CGSizeMake(self.frame.size.width, [WhiteBlurNavBar navBarHeight]*3), true, [UIScreen mainScreen].scale);
    
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    CGContextSetFillColorWithColor(ctx, [UIColor whiteColor].CGColor);
    CGContextFillRect(ctx, CGRectMake(0, 0, self.frame.size.width, [WhiteBlurNavBar navBarHeight]));
    [self.underView drawViewHierarchyInRect:CGRectMake(0, 0, self.underView.frame.size.width, self.underView.frame.size.height) afterScreenUpdates:NO];
    UIImage* img = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    UIImage* blurred = [img applyBlurWithRadius:3 tintColor:nil saturationDeltaFactor:0.8 maskImage:nil];
    
    self.lastBlurredImage = blurred;
}

-(void) computeBlur
{
    if (![Accounts sharedInstance].navBarBlurred) {
        return;
    }
    
    const CGFloat currentOffset = [(UIScrollView*)self.underView contentOffset].y;

    // to make the white navbar smoothly dissappear
    if (currentOffset>self.baseOffset && currentOffset<self.baseOffset + [WhiteBlurNavBar navBarHeight]) {
        self.whiteMask.transform = CGAffineTransformMakeTranslation(0, (self.baseOffset - currentOffset));
        self.whiteMask.hidden = NO;
    }
    else {
        self.whiteMask.hidden = YES;
    }

    // compute new or use cached one
    
    if (currentOffset <= self.baseOffset) {
        //NSLog(@"SKIP TO HIGH");
        self.realBlurView.image = nil;
        return;
    }

    const CGFloat deltaLast = self.lastOffsetWanted - currentOffset;
    self.lastOffsetWanted = currentOffset;
    
    if (deltaLast>[WhiteBlurNavBar navBarHeight] - 2.f) {
        // going to fast to the top (no cell in table views to display)
        self.realBlurView.image = nil;
        return;
    }

    if (self.realBlurView.image == nil) {
        [self computeBlurForceNew];
        return;
    }
    
    const CGFloat limiteBottom = [WhiteBlurNavBar navBarHeight] * 2.f;
    const CGFloat limiteTop = MIN(deltaLast * 3.f , [WhiteBlurNavBar navBarHeight] / 2.f);
    
    CGFloat delta = currentOffset - self.lastOffsetBlurred;
    
    BOOL justeMove = NO;
    
    if (delta>0 && delta < limiteBottom) {
        //NSLog(@"REUSE BOTTOM : %f", delta);
        justeMove = YES;
    }
    else if (delta<0 && delta > -limiteTop) {
        //NSLog(@"REUSE ON TOP : %f  ||  %f", delta, deltaLast);
        justeMove = YES;
    }
    else {
        //NSLog(@"NEW FOR %f : %f", currentOffset, delta);
        
        self.lastOffsetBlurred = currentOffset;
        [self _reallyComputeBlur];
        self.realBlurView.image = self.lastBlurredImage;
        
        if (self.realBlurView.frame.origin.y != 0) {
            CGRect f = self.realBlurView.frame;
            f.origin.y = 0;
            self.realBlurView.frame = f;
        }
    }
    
    if (justeMove) {
        CGRect f = self.realBlurView.frame;
        f.origin.y = -delta;
        self.realBlurView.frame = f;
    }
}


@end
