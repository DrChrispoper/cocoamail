//
//  DateUtil.m
//  CocoaMail
//
//  Created by Christopher Hockley on 20/01/2012.
//  Copyright (c) 2012 Christopher Hockley. All rights reserved.
//

#import "DateUtil.h"
#define DATE_UTIL_SECS_PER_DAY 86400

static DateUtil *singleton = nil;

@implementation DateUtil

@synthesize today;
@synthesize yesterday;
@synthesize lastWeek;
@synthesize todayComponents;
@synthesize yesterdayComponents;
@synthesize dateFormatter;

- (void)refreshData
{
	NSCalendar *gregorian = [NSCalendar currentCalendar];
	self.today = [NSDate date];
	self.yesterday = [today dateByAddingTimeInterval:-DATE_UTIL_SECS_PER_DAY];
	self.lastWeek = [today dateByAddingTimeInterval:-6*DATE_UTIL_SECS_PER_DAY];
	self.todayComponents = [gregorian components:(NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay) fromDate:today];
	self.yesterdayComponents = [gregorian components:(NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay) fromDate:yesterday];
	self.dateFormatter = [[NSDateFormatter alloc] init];
}

- (id)init
{
	if (self = [super init]) {	
		[self refreshData];
	}
	return self;
}

+ (id)getSingleton
{
	@synchronized(self) {
		if (singleton == nil) {
			singleton = [[self alloc] init];
		}
	}
	return singleton;
}

- (NSString *)humanDate:(NSDate *)date
{
	/*NSCalendar *gregorian = [NSCalendar currentCalendar];
	
	NSDateComponents *dateComponents = [gregorian components:(NSCalendarUnitYear|NSCalendarUnitMonth|NSCalendarUnitDay) fromDate:date];
	
	if([dateComponents day] == [todayComponents day] &&
	   [dateComponents month] == [todayComponents month] && 
	   [dateComponents year] == [todayComponents year]) {
		[dateFormatter setDateStyle:NSDateFormatterNoStyle];
		[dateFormatter setTimeStyle:NSDateFormatterShortStyle];
		
        return NSLocalizedString(@"today", @"Email received today");
	}
	if([dateComponents day] == [yesterdayComponents day] && 
	   [dateComponents month] == [yesterdayComponents month] && 
	   [dateComponents year] == [yesterdayComponents year]) {
		return NSLocalizedString(@"yesterday", @"Email sent yesterday");
	}
	if([date laterDate:lastWeek] == date) {
        
		[dateFormatter setDateFormat:@"EEEE"];
		return [[dateFormatter stringFromDate:date] capitalizedString];
	}*/
    
    [dateFormatter setDateFormat:@"d MMM yy"];
	
	return [dateFormatter stringFromDate:date];
}

- (NSString *)time:(NSDate *)date
{
    [dateFormatter setDateFormat:@"HH:mm"];
    
    return [dateFormatter stringFromDate:date];
}

+ (NSDate *)datetimeInLocal:(NSDate *)utcDate
{
	NSTimeZone *utc = [NSTimeZone timeZoneWithName:@"UTC"];
	
	NSTimeZone *local = [NSTimeZone localTimeZone];
	
	NSInteger sourceSeconds = [utc secondsFromGMTForDate:utcDate];
	NSInteger destinationSeconds = [local secondsFromGMTForDate:utcDate];
	
	NSTimeInterval interval =  destinationSeconds - sourceSeconds;
	NSDate *res = [[NSDate alloc] initWithTimeInterval:interval sinceDate:utcDate];
	return res;
}

@end
