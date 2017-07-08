//
//  ConversationTableViewCell.m
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 16/07/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "ConversationTableViewCell.h"
#import "UserSettings.h"
#import "ViewController.h"
#import "Accounts.h"
#import "CocoaButton.h"
#import "Persons.h"
#import "Draft.h"
#import "NSDate+TimeAgo.h"


const CGFloat kCellTextRowHeight = 44.0;
const CGFloat kCellDividerHeight = 1.0;
const CGFloat kUnreadCircleDiameter = kCellTextRowHeight * 0.40; // 40% of row height
const CGFloat kUnreadCircleRadius = kUnreadCircleDiameter / 2.0;
const CGFloat kCellTextRowOffset = (kCellTextRowHeight - kUnreadCircleDiameter) / 2.0;
const CGFloat kCellEdgeInset = 5.5;

@interface ConversationTableViewCell () <UIGestureRecognizerDelegate>

@property (nonatomic, weak) UIView* baseView;

@property (nonatomic, weak) UILabel* name;
@property (nonatomic, weak) UILabel* title;
@property (nonatomic, weak) UILabel* time;

@property (nonatomic, weak) UIImageView* flaggedImageView;
@property (nonatomic, weak) UIImageView* leftAction;
@property (nonatomic, weak) UIImageView* backViewL;
@property (nonatomic, weak) UIImageView* backViewR;

@property (nonatomic, weak) UIView* badge;
@property (nonatomic, weak) UIView* unreadCircle;

@property (nonatomic, weak) UIImageView* attachment;

//@property (nonatomic, weak) UIView* readMask;


@property (nonatomic) BOOL dontGoBack;
@property (nonatomic) CGPoint panBasePos;
@property (nonatomic) CGSize panBaseSize;
@property (nonatomic, strong) NSDate* panStartDate;

@property (nonatomic) CGFloat currentSwipedPosition;

@property (nonatomic, weak) id<ConversationCellDelegate> delegate;

@property (nonatomic, weak) Conversation* conversation;

@end

@implementation ConversationTableViewCell

-(void) setupWithDelegate:(id<ConversationCellDelegate>)delegate
{
    
    self.backgroundColor = [UIColor clearColor];
    self.selectionStyle = UITableViewCellSelectionStyleNone;
    self.delegate = delegate;
    
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    
    UIView* cellBackgroundView = nil;
    CGFloat sepWidth =  0.0;
    
    UserSettings *user = [[Accounts sharedInstance] currentAccount].user;
    UIColor* accountColor = user.color;
    
    UIImage* rBack = [[UIImage imageNamed:@"cell_mail_unread"] imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    
    // Load Unread cell left half background view
    UIImageView* inLeftImageView = [[UIImageView alloc] initWithImage:rBack];
    inLeftImageView.frame = CGRectMake(8 , 0 , 150, 89);
    inLeftImageView.tintColor = accountColor;
    [self.contentView addSubview:inLeftImageView];
    inLeftImageView.contentMode = UIViewContentModeTopLeft;
    inLeftImageView.clipsToBounds = YES;
    self.backViewL = inLeftImageView;
    self.backViewL.alpha = 0.f;
    
    // Load Unread cell right have background view
    UIImageView* inRightImageView = [[UIImageView alloc] initWithImage:rBack];
    inRightImageView.frame = CGRectMake(screenBounds.size.width - 150 - 8 , 0 , 150, 89);
    inRightImageView.tintColor = accountColor;
    [self.contentView addSubview:inRightImageView];
    inRightImageView.contentMode = UIViewContentModeTopRight;
    inRightImageView.clipsToBounds = YES;
    self.backViewR = inRightImageView;
    self.backViewR.alpha = 0.f;
    
    // Set up Swipe Images
    UIImageView* arch = [self.delegate imageViewForQuickSwipeAction];
    CGRect fa = arch.frame;
    fa.origin.x = 8;
    fa.origin.y = 28;
    arch.frame = fa;
    arch.autoresizingMask = UIViewAutoresizingFlexibleRightMargin;
    [inLeftImageView addSubview:arch];
    self.leftAction = arch;
    
    // Set up Swipe Image Selected image
    UIImageView* sel = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"swipe_select"]];
    CGRect fs = sel.frame;
    fs.origin.x = inRightImageView.bounds.size.width - 8 - 30;
    fs.origin.y = 28;
    sel.frame = fs;
    sel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [inRightImageView addSubview:sel];
    
    
    CGFloat moreRightSpace = 0.f;
    
//    if ([self.reuseIdentifier isEqualToString:kCONVERSATION_CELL_ID]) {
//        
//        UIImage* rBack2 = [[UIImage imageNamed:@"cell_conversation_unread"] resizableImageWithCapInsets:UIEdgeInsetsMake(44, 44,44, 44)];
//        //rBack = [rBack imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
//        UIImageView* iv = [[UIImageView alloc] initWithImage:rBack2];
//        iv.frame = CGRectMake(8., 0, screenBounds.size.width - 9, 89);
//        cellBackgroundView = iv;
//        sepWidth = iv.bounds.size.width - 7.f;
//        moreRightSpace = 7.f;
//        
//    }
//    else {
        UIImage* rBack3 = [[UIImage imageNamed:@"cell_mail_unread"] resizableImageWithCapInsets:UIEdgeInsetsMake(44, 44, 44, 44)];
        //rBack = [rBack imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        UIImageView* iv = [[UIImageView alloc] initWithImage:rBack3];
        iv.frame = CGRectMake(8, 0, screenBounds.size.width - 16, 89);
        cellBackgroundView = iv;
        sepWidth = iv.bounds.size.width;
//    }
    self.baseView = cellBackgroundView;
    
    //UILongPressGestureRecognizer* lpgr = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(_press:)];
    //lpgr.minimumPressDuration = 0.01;
    //[self.contentView addGestureRecognizer:lpgr];
    //lpgr.delegate = self;
    
    
    UITapGestureRecognizer* tap = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_press:)];
    [self.contentView addGestureRecognizer:tap];
    
    tap.delegate = self;
    
    UIPanGestureRecognizer* lpgr = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(_pan:)];
    //lpgr.minimumPressDuration = 0.01;
    [self.contentView addGestureRecognizer:lpgr];
    
    lpgr.delegate = self;
    
    [self.contentView addSubview:cellBackgroundView];
    
    // Set up cell row seperator line
    UIView* cellRowsSeperator = [[UIView alloc] initWithFrame:CGRectMake(0, 44, sepWidth, kCellDividerHeight)];
    cellRowsSeperator.backgroundColor = [UIColor colorWithWhite:0.96 alpha:1.0];
    cellRowsSeperator.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [cellBackgroundView addSubview:cellRowsSeperator];
    
    UILabel* nameLabel = [[UILabel alloc] initWithFrame:CGRectMake(44, 0, cellBackgroundView.bounds.size.width - 135 - moreRightSpace, 45)];
    nameLabel.textColor = [UIColor colorWithWhite:0.47 alpha:1.0];
    nameLabel.font = [UIFont systemFontOfSize:16];
    nameLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [cellBackgroundView addSubview:nameLabel];
    self.name = nameLabel;
    
    UILabel* titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(44, 44, cellBackgroundView.bounds.size.width - 88 - moreRightSpace, 45)];
    titleLabel.textColor = [UIColor colorWithWhite:0.02 alpha:1.0];
    titleLabel.font = [UIFont systemFontOfSize:16];
    titleLabel.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [cellBackgroundView addSubview:titleLabel];
    self.title = titleLabel;
    
    UILabel* timeLabel = [[UILabel alloc] initWithFrame:CGRectMake(cellBackgroundView.bounds.size.width - 108 - moreRightSpace, 0, 100, 45)];
    timeLabel.textAlignment = NSTextAlignmentRight;
    timeLabel.textColor = [UIColor colorWithWhite:0.47 alpha:1.0];
    timeLabel.font = [UIFont systemFontOfSize:13];
    timeLabel.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [cellBackgroundView addSubview:timeLabel];
    self.time = timeLabel;
    
    // Create and position the Flagged Image View
    
    UIImageView* flaggedImage = [[UIImageView alloc]
                        initWithImage:[UIImage imageNamed:@"cell_favoris_off"]
                        highlightedImage:[UIImage imageNamed:@"cell_favoris_off"]]; // should be on, made it off as I am working towards replacing this code
    CGRect f = flaggedImage.frame;
    f.origin.x = cellBackgroundView.bounds.size.width - 38.5 - moreRightSpace;
    f.origin.y = 50.5;
    flaggedImage.frame = f;
    flaggedImage.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [cellBackgroundView addSubview:flaggedImage];
    self.flaggedImageView = flaggedImage;
    
    // Create and position the Attachment "Paper Clip" view.
    UIImageView* attachmentImage = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"mail_attachment_off"] highlightedImage:[UIImage imageNamed:@"mail_attachment_on"]];
    CGFloat att_view_x = cellBackgroundView.bounds.size.width - 38.5 - moreRightSpace;
    CGFloat att_view_y = 50.5;
    attachmentImage.frame = CGRectMake(att_view_x, att_view_y, 33, 33);
    attachmentImage.autoresizingMask = UIViewAutoresizingFlexibleRightMargin;
    [cellBackgroundView addSubview:attachmentImage];
    self.attachment = attachmentImage;
    
    UIView* personView = [[UIView alloc] initWithFrame:CGRectMake(kCellEdgeInset, kCellEdgeInset, 33, 33)];
    personView.backgroundColor = [UIColor clearColor];
    [cellBackgroundView addSubview:personView];
    self.badge = personView;
    
    // View that will contain Unread Conversation Messenger UILabel
    // Center Point relative to parent window
    CGFloat view_x = kCellTextRowOffset;
    CGFloat view_y = kCellTextRowHeight + kCellDividerHeight + kCellTextRowOffset;
    // View width and height
    CGFloat view_w = kUnreadCircleDiameter;
    CGFloat view_h = kUnreadCircleDiameter;
    
    UIView* unreadView = [[UIView alloc] initWithFrame:CGRectMake(view_x, view_y, view_w, view_h)];
    unreadView.backgroundColor = [UIColor clearColor];
    [cellBackgroundView addSubview:unreadView];
    self.unreadCircle = unreadView;
    
    self.currentSwipedPosition = 0.0;
    self.panBaseSize = self.baseView.frame.size;
    
    
    if ([self.delegate isPresentingDrafts]) {
        self.flaggedImageView.hidden = YES;
    }
    
}

-(void) setAlwaysSwiped
{
    self.currentSwipedPosition = [self _limiteRightSwipe];
    
    CGRect frame = self.baseView.frame;
    frame.size = self.panBaseSize;
    frame.origin.x = 8 + self.currentSwipedPosition;
    frame.size.width -= self.currentSwipedPosition;
    self.baseView.frame = frame;
    
    //self.backViewR.alpha = (self.currentSwipedPosition == 0.0f) ? 0.f : 1.f;
    self.backViewL.alpha = 1.f;
    
    for (UIGestureRecognizer* gr in [self.contentView gestureRecognizers]) {
        [self.contentView removeGestureRecognizer:gr];
    }
}

-(BOOL) gestureRecognizer:(UIGestureRecognizer*)gestureRecognizer shouldRecognizeSimultaneouslyWithGestureRecognizer:(UIGestureRecognizer*)otherGestureRecognizer
{
    if ([self.delegate tableViewPanGesture] == otherGestureRecognizer) {
        return YES;
    }
    
    return NO;
}

-(NSString*) currentID
{
    return [self.conversation firstMail].msgID;
}

-(Mail*) mail
{
    return [self.conversation firstMail];
}

-(CGFloat) _limiteRightSwipe
{
    return ([self.reuseIdentifier isEqualToString:kCONVERSATION_CELL_ID] ? 51.f  : 44.f);
    
}

-(void) _cellIsSelected
{
    [self.delegate cellIsSelected:self];
}

-(void) _cellIsUnselected
{
    [self.delegate cellIsUnselected:self];
}

-(void) _press:(UITapGestureRecognizer*)lpgr
{
    const CGPoint pos = [lpgr locationInView:lpgr.view];
    const NSInteger tagFavSelected = 972;
    
    switch (lpgr.state) {
        case UIGestureRecognizerStatePossible:
        {
            // tap fav
            CGRect bigger = CGRectInset(self.flaggedImageView.frame, -10, -10);
            
            if (CGRectContainsPoint(bigger, pos)) {
                self.flaggedImageView.tag = tagFavSelected;
                self.flaggedImageView.highlighted = !self.flaggedImageView.highlighted;
            }
            
            // tap attachment
            if (self.attachment.hidden == NO) {
                
                if (![self.delegate isPresentingDrafts]) {
                    bigger = CGRectInset(self.attachment.frame, -10, -10);
                    
                    if (CGRectContainsPoint(bigger, pos)) {
                        self.attachment.highlighted = true;
                    }
                }
            }
            break;
        }
        case UIGestureRecognizerStateEnded:
        {
            CGRect bigger = CGRectInset(self.flaggedImageView.frame, -10, -10);
            
            if (CGRectContainsPoint(bigger, pos)) {
                self.flaggedImageView.tag = tagFavSelected;
                self.flaggedImageView.highlighted = !self.flaggedImageView.highlighted;
            }
            
            // tap attachment
            if (self.attachment.hidden == NO) {
                
                if (![self.delegate isPresentingDrafts]) {
                    bigger = CGRectInset(self.attachment.frame, -10, -10);
                    
                    if (CGRectContainsPoint(bigger, pos)) {
                        self.attachment.highlighted = true;
                    }
                }
            }

            // tav fav
            if (self.flaggedImageView.tag == tagFavSelected) {
                
                if (![[self.conversation firstMail].body isEqualToString:@"COCOAMAILSECRECTWEAPON"]) {
                    [self.conversation toggleFav];
                }
                
                self.flaggedImageView.tag = 0;
            } // tap attachment
            else if (self.attachment.highlighted) {
                [[NSNotificationCenter defaultCenter] postNotificationName:kPRESENT_CONVERSATION_ATTACHMENTS_NOTIFICATION object:nil
                                                                  userInfo:@{kPRESENT_CONVERSATION_KEY:self.conversation}];
                
                self.attachment.highlighted = false;
            }
            else {
                // tap user badge
                CGRect bigger = CGRectInset(self.badge.frame, -10, -10);
                
                if (CGRectContainsPoint(bigger, pos)) {
                    
                    Person* person;
                    
                    if ([[Accounts sharedInstance] getPersonID:[self conversation].user.accountIndex] == [self mail].fromPersonID && [self mail].toPersonIDs && [self mail].toPersonIDs.count != 0){
                        person = [[Persons sharedInstance] getPersonWithID:[[[self mail].toPersonIDs firstObject] integerValue]];
                    }
                    else {
                        person = [[Persons sharedInstance] getPersonWithID:[self mail].fromPersonID];
                    }
                    
                    [[NSNotificationCenter defaultCenter] postNotificationName:kPRESENT_FOLDER_NOTIFICATION object:nil userInfo:@{kPRESENT_FOLDER_PERSON:person}];
                    return;
                }
                
                // tap cell
                
                UIView* overView = [[UIView alloc] initWithFrame:self.baseView.bounds];
                overView.backgroundColor = [UIColor lightGrayColor];
                overView.alpha = 0.f;
                overView.layer.cornerRadius = 20.f;
                overView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
                
                [self.baseView addSubview:overView];
                
                [UIView animateWithDuration:0.1
                                 animations:^{
                                     overView.alpha = 0.8f;
                                 }
                                 completion:^(BOOL fini){
                                     [UIView animateWithDuration:0.1
                                                      animations:^{
                                                          overView.alpha = 0.0f;
                                                      }
                                                      completion:^(BOOL fini){
                                                          [overView removeFromSuperview];
                                                          [self.delegate unselectAll];
                                                          
                                                          if (![[self.conversation firstMail].body isEqualToString:@"COCOAMAILSECRECTWEAPON"]) {
                                                            if ([self.delegate isPresentingDrafts]) {
                                                              [[NSNotificationCenter defaultCenter] postNotificationName:kPRESENT_EDITMAIL_NOTIFICATION
                                                                                                                  object:nil
                                                                                                                userInfo:@{kPRESENT_MAIL_KEY:[[self.conversation firstMail] toDraft]}];
                                                            }
                                                            else {
                                                              [[NSNotificationCenter defaultCenter] postNotificationName:kPRESENT_CONVERSATION_NOTIFICATION
                                                                                                                  object:nil
                                                                                                                userInfo:@{kPRESENT_CONVERSATION_KEY:self.conversation}];
                                                            }
                                                          }
                                                          
                                                      }];
                                 }];
            }
            
        }
        default:
            break;
    }
}

-(void) _pan:(UIPanGestureRecognizer*)lpgr
{
    const CGPoint pos = [lpgr locationInView:lpgr.view];
    const NSInteger tagFavSelected = 972;
    
    BOOL back = false;
    
    switch (lpgr.state) {
        case UIGestureRecognizerStateBegan:
            self.panBasePos = pos;
            self.leftAction.hidden = true;
            self.panStartDate = [NSDate date];

            break;
            
        case UIGestureRecognizerStateChanged:
        {
            
            UIPanGestureRecognizer* tpgr = [self.delegate tableViewPanGesture];
            CGPoint p = [tpgr  translationInView:tpgr.view];
            CGFloat pyabs = fabs(p.y);
            
            if (pyabs >= fabs(p.x) && pyabs > 10) {
                self.dontGoBack = YES;
                lpgr.enabled = NO;
                lpgr.enabled = YES;
                self.dontGoBack = NO;
                return;
            }
            
            CGFloat delta = pos.x - self.panBasePos.x;
            
            
            delta += self.currentSwipedPosition;
            
            const CGFloat limite = -[self _limiteRightSwipe];
            
            if (delta<limite) {
                delta = limite;
            }
            else if (delta>44.f) {
                delta = 44.0f;
                
            }
            
            if (fabs(delta - self.currentSwipedPosition) > 12.f) {
                tpgr.enabled = NO;
                tpgr.enabled = YES;
            }
            
            
            CGRect frame = self.baseView.frame;
            frame.size = self.panBaseSize;
            
            if (delta>0) {
                frame.origin.x = 8 + delta;
                frame.size.width -= delta;
                
                CGFloat pourc = delta / 44.f;
                
                if (pourc > 1.f) {
                    pourc = 1.f;
                }
                
                if (pourc < 0.f) {
                    pourc = 0.f;
                }
                
                if (self.currentSwipedPosition == 0.f) {
                    
                    self.leftAction.hidden = pourc<1.f;
                    
                    if (pourc>0.85) {
                        self.leftAction.hidden = NO;
                        self.leftAction.alpha = (pourc - 0.85) / 0.15 /* pourc*pourc*/;
                    }
                }
                else {
                    self.leftAction.hidden = YES;
                }
                
                self.backViewL.alpha = pourc;
                self.backViewR.alpha = 0.f;
                
            }
            else {
                frame.origin.x = 8;
                frame.size.width += delta;
                
                CGFloat pourc = -(delta / 40.f);
                
                if (pourc > 1.f) {
                    pourc = 1.f;
                }
                
                if (pourc < 0.f) {
                    pourc = 0.f;
                }
                
                self.backViewR.alpha = pourc;
                self.backViewL.alpha = 0.f;
                
            }
            self.baseView.frame = frame;
            
            [self.delegate cell:self isChangingDuring:0.05];
            
            if (self.attachment.highlighted || self.flaggedImageView.tag == tagFavSelected) {
                
                BOOL noMore = YES;
                
                if ([self.panStartDate timeIntervalSinceNow]>-0.8) {
                    if (fabs(pos.x - self.panBasePos.x)<8) {
                        if (fabs(pos.y - self.panBasePos.y)<8) {
                            noMore = false;
                        }
                    }
                }
                
                if (noMore) {
                    if (self.attachment.highlighted) {
                        self.attachment.highlighted = NO;
                    }
                    
                    if (self.flaggedImageView.tag == tagFavSelected) {
                        self.flaggedImageView.tag = 0;
                        self.flaggedImageView.highlighted = !self.flaggedImageView.highlighted;
                    }
                }
            }
            break;
        }
        case UIGestureRecognizerStateEnded:
        {
            UIPanGestureRecognizer* tpgr = [self.delegate tableViewPanGesture];
            
            //BOOL otherIsStopped = (tpgr.state == UIGestureRecognizerStatePossible || tpgr.state == UIGestureRecognizerStateFailed);
            
            tpgr.enabled = YES;
        }
        case UIGestureRecognizerStateCancelled:
        case UIGestureRecognizerStateFailed:
            back = true;
            break;
        default:
            break;
    }
    
    if (back) {
        
        CGFloat delta = pos.x - self.panBasePos.x + self.currentSwipedPosition;
        BOOL userEndAction = lpgr.state == UIGestureRecognizerStateEnded;
        BOOL doAction = (self.leftAction.hidden == false && self.leftAction.alpha == 1.0);
        
        [self.delegate cell:self isChangingDuring:0.25];
        
        [UIView animateWithDuration:0.2
                              delay:0.0
             usingSpringWithDamping:0.8
              initialSpringVelocity:0.1
                            options:UIViewAnimationOptionBeginFromCurrentState
                         animations:^{
                             
                             if (self.dontGoBack == NO) {
                                 const CGFloat limite = -[self _limiteRightSwipe];
                                 self.currentSwipedPosition = ((delta<limite)) ? limite : 0.f;
                             }
                             [self _applyStableFrame];
                             
                         }
                         completion:nil];
        
        if (doAction) {
            
            if (userEndAction) {
                
                QuickSwipeType idxQuickSwipe = [self quickSwipeType];
                
                if (idxQuickSwipe == QuickSwipeMark) {
                    Mail* m = [self mail];
                    [m toggleRead];
                    [self fillWithConversation:self.conversation isSelected:false isDebugMode:NO];
                }
                
                [self.delegate leftActionDoneForCell:self];
            }
        }
        else {
            if (self.currentSwipedPosition<0) {
                [self _cellIsSelected];
            }
            else {
                [self _cellIsUnselected];
            }
        }
        
    }
    
}

-(QuickSwipeType) quickSwipeType
{
    QuickSwipeType idxQuickSwipe = [Accounts sharedInstance].quickSwipeType;
    
    if ([self.delegate isPresentingDrafts]) {
        return QuickSwipeDelete;
    }
    
    return idxQuickSwipe;
}

-(void) fillWithConversation:(Conversation*)conv isSelected:(BOOL)selected isDebugMode:(BOOL)debugMode
{
    self.conversation = conv;
    Mail* mail = [self mail];
    
    if (![mail.subject isEqualToString:@""]) {
        self.title.text = mail.subject;
    }
    else {
        self.title.text = [mail.body stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
    }
    
    Person* p = nil;
    
    //If it is a reply show the first receipient
    NSInteger meID = [[Accounts sharedInstance] getPersonID:conv.user.accountIndex];
    if (meID == mail.fromPersonID) {
        if (!mail.toPersonIDs || mail.toPersonIDs.count == 0) {
            p = [[Persons sharedInstance] getPersonWithID:mail.fromPersonID];
            self.name.text = @"Draft";
        }
        else {
            NSInteger toID = -999;
            
            for (Mail* mail in conv.mails) {
                if (mail.fromPersonID != meID) {
                    toID = mail.fromPersonID;
                    break;
                }
            }
            
            if (toID == -999) {
                toID = [[mail.toPersonIDs firstObject] integerValue];
            }
            
            p = [[Persons sharedInstance] getPersonWithID:toID];
            self.name.text = [NSString stringWithFormat:@"↩︎%@",p.name];
        }
    }
    else {
        p = [[Persons sharedInstance] getPersonWithID:mail.fromPersonID];
        NSString* name;
        
        if (p.isGeneric) {
            name = mail.sender.displayName;;
        }
        else {
            name = p.name;
        }
        
        self.name.text = name;
    }
    
    [self.badge.subviews.firstObject removeFromSuperview];
    [self.badge addSubview:[p badgeView]];
    
    NSDate* twelveHours = [[NSDate date] dateByAddingTimeInterval:- 60 * 60 * 12];

    if ([Mail isTodayOrYesterday:mail.day] == 0 && [mail.datetime compare:twelveHours] == NSOrderedDescending) {
        self.time.text = [mail.datetime timeAgo];
    }
    else {
        self.time.text = mail.hour;
    }
    self.attachment.hidden = ![conv hasAttachments];
    
    self.flaggedImageView.highlighted = conv.isFav;
    
    
    QuickSwipeType idxQuickSwipe = [self quickSwipeType];
    
    if (idxQuickSwipe == QuickSwipeReply) {
        BOOL toMany = mail.toPersonIDs.count>1;
        self.leftAction.highlighted = toMany;
    }
    
    if (idxQuickSwipe == QuickSwipeArchive) {
        self.leftAction.highlighted = ![conv isInInbox];
    }
    
    
    
    // Remove the circleLabel if it exists
    [self.unreadCircle.subviews.firstObject removeFromSuperview];
    
    if (idxQuickSwipe == QuickSwipeMark) {
        self.leftAction.highlighted = NO;
    }

    UILabel *circleLabel = nil;
    
    // Get account color
    UIColor* accountColor = [[Accounts sharedInstance] currentAccount].user.color;
    DDAssert(accountColor, @"account color must be set");
    
    NSUInteger numberMailsInConversation = [conv mailCount];
    if ( numberMailsInConversation == 1 )  {
        // This cell contains a single mail, not a conversation
        
        // Single message, unread: <account color> circle with no number label
        circleLabel = [self _createCircleLabelWithNumber:0 andColor:accountColor];
    } else {
        // This cell contains a conversation
        
        NSUInteger numberUnreadMailsInConversation = [conv unreadCount];
        if ( numberUnreadMailsInConversation == 0 ) {
            // This is a conversation but all are read
            
            // Conversation, all read: Gray circle with label number = number of messages in thread
            circleLabel = [self _createCircleLabelWithNumber:numberMailsInConversation andColor:[UIColor grayColor]];
        } else {
            // The conversation has unread conversations
            
            // Conversation, with 1 or more unread messages: <account color> cirle with label number = number of messages in thread
            circleLabel = [self _createCircleLabelWithNumber:numberMailsInConversation andColor:accountColor];
        }
    }
    DDAssert(circleLabel, @"Circle Label must exist.");
    
    // Replace the old circle label with the new one
    [self.unreadCircle.subviews.firstObject removeFromSuperview];
    [self.unreadCircle addSubview:circleLabel];
    
    
    //        [self.readMask removeFromSuperview];
    //        self.readMask = nil;
    
    if (idxQuickSwipe == QuickSwipeMark) {
        self.leftAction.highlighted = YES;
    }
    
    // selection
    self.currentSwipedPosition = (selected) ? -[self _limiteRightSwipe] : 0.f;
    [self _applyStableFrame];
}

-(UILabel *) _createCircleLabelWithNumber:(NSUInteger)labelNumber andColor:(UIColor*)circleColor
{
    // The UILabel is positioned at x,y = 0.0 relative to its parent view
    // The UILabel has a heigh and width equal to the diameter for the circle
    UILabel* circleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, kUnreadCircleDiameter, kUnreadCircleDiameter)];
    
    circleLabel.backgroundColor = circleColor;
    
    if ( labelNumber == 0 ) {
        // Zero means NO LABEL
        
        // Create circle with NO label
        circleLabel.text = @"";
    }
    else if ( labelNumber > 9 ) {
        // Label number has 2 or more digits
        
        // Display a special label
        circleLabel.text = @"9+";
    }
    else { // Label number is 1 to 9
        
        // Display "1" to "9"
        circleLabel.text = [[NSNumber numberWithUnsignedInteger:labelNumber] stringValue];
    }
    
    circleLabel.textAlignment = NSTextAlignmentCenter;
    circleLabel.textColor = [UIColor whiteColor];
    circleLabel.layer.cornerRadius = kUnreadCircleRadius;
    circleLabel.layer.masksToBounds = YES;
    circleLabel.font = [UIFont systemFontOfSize:12];
    
    return circleLabel;
}

-(void) _applyStableFrame
{
    CGRect frame = self.baseView.frame;
    frame.size = self.panBaseSize;
    frame.origin.x = 8;
    frame.size.width += self.currentSwipedPosition;
    self.baseView.frame = frame;
    
    self.backViewR.alpha = (self.currentSwipedPosition == 0.0f) ? 0.f : 1.f;
    self.backViewL.alpha = 0.f;
}

-(void) animatedClose
{
    self.currentSwipedPosition = 0.f;
    [self.delegate cell:self isChangingDuring:0.25];
    [UIView animateWithDuration:0.2
                     animations:^{
                         [self _applyStableFrame];
                     }
                     completion:nil];
}

-(BOOL) isReplyAll
{
    return self.leftAction.highlighted;
}

@end
