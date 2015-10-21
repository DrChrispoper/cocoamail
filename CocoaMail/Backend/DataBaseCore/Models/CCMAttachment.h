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
@property (nonatomic, readwrite, copy) NSString* msgId;
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
+(NSMutableArray*) getAttachmentsWithMsgId:(NSString*)msgId;
+(NSMutableArray*) getAttachmentsWithMsgId:(NSString*)msgId isInline:(BOOL)isInline;
//+(BOOL)searchAttachmentswithMsgId:(NSString*)msgId;
+(void) tableCheck;
-(BOOL) isEqual:(id)other;
-(NSUInteger) hash;
-(BOOL) isInline;


@end