//
//  Attachment.h
//  CocoaMail
//
//  Created by Christopher Hockley on 20/01/2014.
//  Copyright (c) 2014 Christopher Hockley. All rights reserved.
//

#import <Foundation/Foundation.h>


@interface CCMAttachment : NSObject

@property (assign) NSInteger pk;

@property (nonatomic, readwrite, copy) NSString* contentID;
@property (nonatomic, readwrite, copy) NSString* msgID;
@property (nonatomic, readwrite, copy) NSString* fileName;
@property (nonatomic, readwrite, copy) NSString* mimeType;
@property (nonatomic, readwrite, copy) NSData* data;
@property (nonatomic, readwrite, copy) NSString* partID;
@property (nonatomic) NSUInteger size;

+(NSMutableArray*) getAttachments;
+(NSMutableArray*) getAttachments:(BOOL)andInline;
+(void) addAttachments:(NSArray*)atts;
+(void) addAttachmentsUnsafe:(NSMutableArray*)atts;
+(void) updateData:(CCMAttachment*)attachment;
+(NSMutableArray*) getAttachmentsWithMsgID:(NSString*)msgID;
+(NSMutableArray*) getAttachmentsWithMsgID:(NSString*)msgID isInline:(BOOL)isInline;
+(void) tableCheck;

-(BOOL) isEqual:(id)other;
-(NSUInteger) hash;
-(BOOL) isInline;

+(void) clearAttachments;

@end