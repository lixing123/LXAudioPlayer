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

- (BOOL)hasSpaceAvailableForDequeue:(UInt32)spaceSize;

- (BOOL)hasDataAvailableForEnqueue:(UInt32)dataSize;

- (BOOL)euqueueData:(void *)data dataByteLength:(UInt32)dataByteSize;

- (BOOL)dequeueData:(void *)data dataByteLength:(UInt32)dataByteSize;

@end
