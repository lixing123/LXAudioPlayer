//
//  LXRingBuffer.h
//  LXAudioPlayer
//
//  Created by 李 行 on 16/1/13.
//  Copyright © 2016年 lixing123.com. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AudioToolbox/AudioToolbox.h>

@interface LXRingBuffer : NSObject

- (id)initWithDataPCMFormat:(AudioStreamBasicDescription)pcmFormat seconds:(float)seconds;

- (BOOL)euqueueData:(void *)data dataByteLength:(UInt32)dataByteLength;

- (BOOL)dequeueData:(void *)data dataByteLength:(UInt32)dataByteLength;

@end
