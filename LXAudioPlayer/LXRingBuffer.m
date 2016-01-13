//
//  LXRingBuffer.m
//  LXAudioPlayer
//
//  Created by 李 行 on 16/1/13.
//  Copyright © 2016年 lixing123.com. All rights reserved.
//

#import "LXRingBuffer.h"

@interface LXRingBuffer (){
    AudioBufferList audioBufferList;
    //TODO: it seems that using multiple AudioBuffer is also possible
    AudioBuffer *audioBuffer;
    
    UInt32 totalFrameCount;
    UInt32 currentFrameIndex;
    UInt32 currentUsedFrameCount;
    UInt32 bytesPerFrame;
}

@end

@implementation LXRingBuffer

- (id)initWithDataPCMFormat:(AudioStreamBasicDescription)pcmFormat seconds:(float)seconds{
    if (self=[super init]) {
        //init audioBuffer
        UInt32 bufferSize = pcmFormat.mSampleRate * seconds * pcmFormat.mBytesPerFrame;
        audioBuffer = &audioBufferList.mBuffers[0];
        audioBufferList.mBuffers[0].mDataByteSize = bufferSize;
        audioBufferList.mBuffers[0].mNumberChannels = pcmFormat.mChannelsPerFrame;
        audioBufferList.mBuffers[0].mData = (void*)calloc(bufferSize, 0);
        
        bytesPerFrame = pcmFormat.mBytesPerFrame;
        totalFrameCount = audioBuffer->mDataByteSize / bytesPerFrame;
        currentFrameIndex = 0;
        currentUsedFrameCount = 0;
    }
    return self;
}

- (BOOL)euqueueData:(void *)data dataByteLength:(UInt32)dataByteLength {
    //if available bytes space is smaller than size of inserted data, return NO
    UInt32 bytesAvailable = (totalFrameCount - currentUsedFrameCount) * bytesPerFrame;
    if (bytesAvailable<dataByteLength) {
        return NO;
    }
    
    //does buffer has a continuous space to save audio?
    BOOL hasContinuousSpace = NO;
    if (currentFrameIndex+currentUsedFrameCount>totalFrameCount) {
        hasContinuousSpace = YES;
    }else if ((totalFrameCount-currentFrameIndex-currentUsedFrameCount)*bytesPerFrame>dataByteLength){
        hasContinuousSpace = YES;
    }
    
    UInt32 end = (currentFrameIndex+currentUsedFrameCount)%totalFrameCount;
    
    //if buffer has a continuous space to save data, just save data
    if (hasContinuousSpace) {
        memcpy(audioBuffer->mData+end*bytesPerFrame, data, dataByteLength);
    }else{
        //first, copy part of data to the end of buffer
        memcpy(audioBuffer->mData+end*bytesPerFrame, data, (totalFrameCount-end)*bytesPerFrame);
        //second, copy remaining of data to the start of buffer
        UInt32 remainingSize = dataByteLength-(totalFrameCount-end)*bytesPerFrame;
        memcpy(audioBuffer->mData, data+(totalFrameCount-end)*bytesPerFrame, remainingSize);
    }
    
    currentUsedFrameCount += dataByteLength/bytesPerFrame;
    
    return YES;
}

- (BOOL)dequeueData:(void *)data dataByteLength:(UInt32)dataByteLength {
    return NO;
}

@end
