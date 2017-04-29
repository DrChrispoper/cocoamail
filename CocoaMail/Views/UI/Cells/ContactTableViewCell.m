//
//  ContactTableViewCell.m
//  CocoaMail
//
//  Created by Christopher Hockley on 08/02/16.
//  Copyright © 2016 Christopher Hockley. All rights reserved.
//

#import "ContactTableViewCell.h"
#import "Persons.h"
#import "ViewController.h"
#import "SearchViewController.h"

@interface ContactTableViewCell ()

@property (nonatomic, weak) UIView* baseView;

@property (nonatomic, weak) UILabel* name;

@property (nonatomic, weak) UIView* badge;
@property (nonatomic, weak) Person* person;

@end

@implementation ContactTableViewCell

-(void) setSelected:(BOOL)selected animated:(BOOL)animated
{
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
    
    UILabel* n = [[UILabel alloc] initWithFrame:CGRectMake(44, 0, inIV.bounds.size.width - 50, 45)];
    n.textColor = [UIColor colorWithWhite:0.47 alpha:1.0];
    n.font = [UIFont systemFontOfSize:16];
    n.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    [inIV addSubview:n];
    
    self.name = n;
    
    UIView* perso = [[UIView alloc] initWithFrame:CGRectMake(5.5, 5.5, 33, 33)];
    perso.backgroundColor = [UIColor clearColor];
    perso.autoresizingMask = UIViewAutoresizingFlexibleRightMargin;
    [inIV addSubview:perso];
    
    self.badge = perso;
    
    inIV.clipsToBounds = YES;

    self.baseView = back;
    
    [self.contentView addSubview:back];
    
    UITapGestureRecognizer* tgr = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(_tap:)];
    [self addGestureRecognizer:tgr];
    self.userInteractionEnabled = YES;
}

-(void) _tap:(UITapGestureRecognizer*)tgr
{
    if (tgr.state != UIGestureRecognizerStateEnded) {
        return;
    }
    
    [self.sDelegate selectedRow];
    [[NSNotificationCenter defaultCenter] postNotificationName:kPRESENT_FOLDER_NOTIFICATION object:nil userInfo:@{kPRESENT_FOLDER_PERSON:self.person}];
    return;
}

-(void) fillWithPerson:(Person*)person
{
    UIView *badge = self.badge;     // strong - will keep badge around while we use it
    
    if (self.baseView == nil) {
        [self setup];
    }
    
    self.name.text = [NSString stringWithFormat:@"%@ - %@", person.name, person.email];
    
    [badge.subviews.firstObject removeFromSuperview];
    [badge addSubview:[person badgeView]];
    
    self.person = person;
}

@end
