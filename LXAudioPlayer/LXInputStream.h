//
//  LXInputStream.h
//  LXAudioPlayer
//
//  Created by 李 行 on 16/1/22.
//  Copyright © 2016年 lixing123.com. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol LXInputStreamDelegate <NSObject>

@optional

- (void)stream:(id)aStream handleEvent:(NSStreamEvent)eventCode;

@end

@interface LXInputStream : NSObject

- (id)initWithURL:(NSURL *)url delegate:(id<LXInputStreamDelegate>)delegate;

- (void)pause;

- (void)resume;

@end