//
//  DateUtil.h
//  CocoaMail
//
//  Created by Christopher Hockley on 20/01/2012.
//  Copyright (c) 2012 Christopher Hockley. All rights reserved.
//

@interface DateUtil : NSObject {
	NSDate* today;
	NSDate* yesterday;
	NSDate* lastWeek;
	
	NSDateFormatter* dateFormatter;
	NSDateComponents* todayComponents;
	NSDateComponents* yesterdayComponents;
}

@property (nonatomic, strong) NSDate* today;
@property (nonatomic, strong) NSDate* yesterday;
@property (nonatomic, strong) NSDate* lastWeek;
@property (nonatomic, strong) NSDateFormatter* dateFormatter;
@property (nonatomic, strong) NSDateComponents* todayComponents;
@property (nonatomic, strong) NSDateComponents* yesterdayComponents;

+(id) getSingleton;
-(NSString*) humanDate:(NSDate*)date;
-(NSString*) time:(NSDate*)date;
+(NSDate*) datetimeInLocal:(NSDate*)utcDate;


@end
