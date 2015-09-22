//
//  SearchTableViewCell.m
//  Cocoamail
//
//  Created by Pascal Costa-Cunha on 06/09/2015.
//  Copyright (c) 2015 cocoasoft. All rights reserved.
//

#import "SearchTableViewCell.h"

#import "Mail.h"
#import "Persons.h"
#import "ViewController.h"

@interface SearchTableViewCell ()

@property (nonatomic, weak) UIView* baseView;

@property (nonatomic, weak) UILabel* name;
@property (nonatomic, weak) UILabel* title;
@property (nonatomic, weak) UILabel* time;

@property (nonatomic, weak) UIView* badge;

@property (nonatomic, weak) UIImageView* attachment;

@property (nonatomic, weak) Conversation* conversation;

@end


@implementation SearchTableViewCell


static NSDateFormatter* s_df_date = nil;

+(void) initialize
{
    s_df_date = [[NSDateFormatter alloc] init];
    s_df_date.dateStyle = NSDateFormatterShortStyle;
    s_df_date.timeStyle = NSDateFormatterNoStyle;
}


- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}


- (void) setup
{
    
    self.backgroundColor = [UIColor clearColor];
    self.selectionStyle = UITableViewCellSelectionStyleGray;
    
    CGRect screenBounds = [UIScreen mainScreen].bounds;
    
    UIView* back = nil;
    CGFloat sepWidth =  0.0;
    
    CGFloat moreRightSpace = 0.f;
    
    UIImage* rBack = [[UIImage imageNamed:@"cell_mail_unread"] resizableImageWithCapInsets:UIEdgeInsetsMake(44, 44, 44, 44)];
    UIImageView* iv = [[UIImageView alloc] initWithImage:rBack];
    iv.frame = CGRectMake(8, 0, screenBounds.size.width - 16, 89);
    back = iv;
    sepWidth = iv.bounds.size.width;
    
    self.baseView = back;
    
    [self.contentView addSubview:back];
    
    
    UIView* sep = [[UIView alloc] initWithFrame:CGRectMake(0, 44, sepWidth, 1)];
    sep.backgroundColor = [UIColor colorWithWhite:0.96 alpha:1.0];
    sep.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [back addSubview:sep];
    
    UILabel* n = [[UILabel alloc] initWithFrame:CGRectMake(44, 0, back.bounds.size.width - 115 - moreRightSpace, 45)];
    n.textColor = [UIColor colorWithWhite:0.47 alpha:1.0];
    n.font = [UIFont systemFontOfSize:16];
    n.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [back addSubview:n];
    self.name = n;
    
    UILabel* t = [[UILabel alloc] initWithFrame:CGRectMake(44, 44, back.bounds.size.width - 108 - moreRightSpace, 45)];
    t.textColor = [UIColor colorWithWhite:0.02 alpha:1.0];
    t.font = [UIFont systemFontOfSize:16];
    t.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [back addSubview:t];
    self.title = t;
    
    
    UILabel* h = [[UILabel alloc] initWithFrame:CGRectMake(back.bounds.size.width - 88 - moreRightSpace, 0, 80, 45)];
    h.textAlignment = NSTextAlignmentRight;
    h.textColor = [UIColor colorWithWhite:0.47 alpha:1.0];
    h.font = [UIFont systemFontOfSize:13];
    h.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin;
    [back addSubview:h];
    self.time = h;
    
    
    UIImageView* atc = [[UIImageView alloc] initWithImage:[UIImage imageNamed:@"mail_attachment_off"] highlightedImage:[UIImage imageNamed:@"mail_attachment_on"]];
    atc.frame = CGRectMake(5.5, 50.5, 33, 33);
    atc.autoresizingMask = UIViewAutoresizingFlexibleRightMargin;
    [back addSubview:atc];
    self.attachment = atc;
    
    UIView* perso = [[UIView alloc] initWithFrame:CGRectMake(5.5, 5.5, 33, 33)];
    perso.backgroundColor = [UIColor clearColor];
    [back addSubview:perso];
    self.badge = perso;
    
    UITapGestureRecognizer* tgr = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_tap:)];
    [self addGestureRecognizer:tgr];
    self.userInteractionEnabled = YES;
    
}

-(Mail*) mail
{
    return [self.conversation firstMail];
}

-(void) _tap:(UITapGestureRecognizer*)tgr
{
    if (tgr.state != UIGestureRecognizerStateEnded) {
        return;
    }
    
    
    const CGPoint pos = [tgr locationInView:tgr.view];
    
    CGRect bigger;
    
    // tap attachment
    if (self.attachment.hidden == NO) {
        bigger = CGRectInset(self.attachment.frame, -10, -10);
        if (CGRectContainsPoint(bigger, pos)) {
            
            [[NSNotificationCenter defaultCenter] postNotificationName:kPRESENT_CONVERSATION_ATTACHMENTS_NOTIFICATION object:nil
                                                              userInfo:@{kPRESENT_CONVERSATION_KEY:self.conversation}];
            return;
        }
    }
            
    
    bigger = CGRectInset(self.badge.frame, -10, -10);
    if (CGRectContainsPoint(bigger, pos)) {
        Person* person = [[Persons sharedInstance] getPersonID:[self mail].fromPersonID];
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
                                              
                                              [[NSNotificationCenter defaultCenter] postNotificationName:kPRESENT_CONVERSATION_NOTIFICATION
                                                                                                  object:nil
                                                                                                userInfo:@{kPRESENT_CONVERSATION_KEY:self.conversation}];
                                          }];
                     }];

}


- (void)fillWithConversation:(Conversation*)conv subText:(NSString*)subtext highlightWord:(NSString*)word
{
    
    if (self.baseView == nil) {
        [self setup];
    }
    
    self.conversation = conv;
    
    Mail* mail = [self mail];
    
    self.time.text = [s_df_date stringFromDate:mail.date];
    self.attachment.hidden = ![conv haveAttachment];
    
    Person* p = [[Persons sharedInstance] getPersonID:mail.fromPersonID];
    
    NSString* mailFromName = p.name;

    NSRange r = [mailFromName rangeOfString:word options:NSCaseInsensitiveSearch];
    
    if (r.location != NSNotFound) {
        
        NSMutableAttributedString* res = [[NSMutableAttributedString alloc] initWithString:mailFromName
                                                                                attributes:@{ NSFontAttributeName : self.name.font,
                                                                                              NSForegroundColorAttributeName : self.name.textColor,
                                                                                              NSBackgroundColorAttributeName : [UIColor whiteColor]
                                                                                              }];
        
        [res addAttributes:@{ NSFontAttributeName : self.name.font,
                              NSForegroundColorAttributeName : [UIColor whiteColor],
                              NSBackgroundColorAttributeName : [UIGlobal standardBlue]}
                     range:r];
        
        self.name.attributedText = res;
    }
    else {
        self.name.text = mailFromName;
    }
    

    NSString* subtextToDisplay = (subtext.length==0) ? mail.title : subtext;
    

    NSRange rST = [subtextToDisplay rangeOfString:word options:NSCaseInsensitiveSearch];
    
    if (rST.location != NSNotFound) {
        
        NSMutableAttributedString* res = [[NSMutableAttributedString alloc] initWithString:subtextToDisplay
                                                                                attributes:@{ NSFontAttributeName : self.title.font,
                                                                                              NSForegroundColorAttributeName : self.title.textColor,
                                                                                              NSBackgroundColorAttributeName : [UIColor whiteColor]
                                                                                              }];
        
        [res addAttributes:@{ NSFontAttributeName : self.name.font,
                              NSForegroundColorAttributeName : [UIColor whiteColor],
                              NSBackgroundColorAttributeName : [UIGlobal standardBlue]}
                     range:rST];
        
        self.title.attributedText = res;
    }
    else {
        self.title.text = subtextToDisplay;
    }
    
    
    
    [self.badge.subviews.firstObject removeFromSuperview];
    [self.badge addSubview:[p badgeView]];
    
}




@end
