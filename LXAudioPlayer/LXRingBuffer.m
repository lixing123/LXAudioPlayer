//
//  LXRingBuffer.m
//  LXAudioPlayer
//
//  Created by 李 行 on 16/1/13.
//  Copyright © 2016年 lixing123.com. All rights reserved.
//

#import "LXRingBuffer.h"
#import "LXHeader.h"
#import "libkern/OSAtomic.h"

//TODO define a OSSpinLock block

@interface LXRingBuffer (){
    AudioBufferList audioBufferList;
    //TODO: it seems that using multiple AudioBuffer is also possible
    AudioBuffer *audioBuffer;
    
    UInt32 totalFrameCount;
    UInt32 currentFrameIndex;
    UInt32 currentUsedFrameCount;
    UInt32 bytesPerFrame;
    
    //TODO:add support for multithread
    OSSpinLock spinLock;
}

@end

@implementation LXRingBuffer

- (id)initWithDataPCMFormat:(AudioStreamBasicDescription)pcmFormat seconds:(float)seconds{
    if (self=[super init]) {
        //init audioBuffer
        UInt32 bufferSize = pcmFormat.mSampleRate * seconds * pcmFormat.mBytesPerFrame;
        audioBuffer = &audioBufferList.mBuffers[0];
        audioBufferList.mNumberBuffers = 1;
        audioBufferList.mBuffers[0].mDataByteSize = bufferSize;
        //audioBufferList.mBuffers[0].mNumberChannels = pcmFormat.mChannelsPerFrame;
        //TODO:AudioBufferList.mNumberChannels should always 1???
        audioBufferList.mBuffers[0].mNumberChannels = 1;
        audioBufferList.mBuffers[0].mData = (void*)calloc(audioBuffer->mDataByteSize, 1);
        
        bytesPerFrame = pcmFormat.mBytesPerFrame;
        totalFrameCount = audioBuffer->mDataByteSize / bytesPerFrame;
        currentFrameIndex = 0;
        currentUsedFrameCount = 0;
        
        LXLog(@"total fram count of ring buffer:%d",totalFrameCount);
    }
    return self;
}

- (BOOL)needToBeFilled {
    OSSpinLockLock(&spinLock);
    BOOL result = (currentUsedFrameCount/totalFrameCount>0.7);
    OSSpinLockUnlock(&spinLock);
    return result;
}

- (BOOL)hasSpaceAvailableForEnqueue:(UInt32)spaceSize {
    OSSpinLockLock(&spinLock);
    BOOL result = (totalFrameCount-currentUsedFrameCount) * bytesPerFrame >= spaceSize;
    //LXLog(@"hasSpaceAvailableForEnqueue:%@",result?@"YES":@"NO");
    OSSpinLockUnlock(&spinLock);
    return result;
}

- (BOOL)hasDataAvailableForDequeue:(UInt32)dataSize {
    OSSpinLockLock(&spinLock);
    BOOL result = currentUsedFrameCount * bytesPerFrame >= dataSize;
    OSSpinLockUnlock(&spinLock);
    return result;
}

- (BOOL)euqueueData:(void *)data dataByteLength:(UInt32)dataByteSize {
    //if available bytes space is smaller than size of inserted data, return NO
    if (![self hasSpaceAvailableForEnqueue:dataByteSize]) {
        return NO;
    }
    
    OSSpinLockLock(&spinLock);
    UInt32 start = currentFrameIndex;
    UInt32 used  = currentUsedFrameCount;
    OSSpinLockUnlock(&spinLock);
    
    //LXLog(@"ring buffer status before enqueue:startIndex:%d     framesUsed:%d     data size:%d",start,used,dataByteSize);
    
    //does buffer has a continuous space to save audio?
    BOOL hasContinuousSpace = NO;
    if (start+used>totalFrameCount) {
        hasContinuousSpace = YES;
    }else if ((totalFrameCount-start-used)*bytesPerFrame>dataByteSize){
        hasContinuousSpace = YES;
    }
    UInt32 end = (start+used)%totalFrameCount;

    //if buffer has a continuous space to save data, just save data
    //TODO:add pthread lock
    if (hasContinuousSpace) {
        memcpy(audioBuffer->mData+end*bytesPerFrame, data, dataByteSize);
    }
    else{
        //first, copy part of data to the end of buffer
        memcpy(audioBuffer->mData+end*bytesPerFrame, data, (totalFrameCount-end)*bytesPerFrame);
        //second, copy remaining of data to the start of buffer
        //LXLog(@"bytes used 3:%d",used);
        UInt32 remainingSize = dataByteSize-(totalFrameCount-end)*bytesPerFrame;
        memcpy(audioBuffer->mData, data+(totalFrameCount-end)*bytesPerFrame, remainingSize);
        //LXLog(@"bytes used 4:%d",used);
    }
    
    OSSpinLockLock(&spinLock);
    currentUsedFrameCount = currentUsedFrameCount + dataByteSize/bytesPerFrame;
    used = currentUsedFrameCount;
    LXLog(@"ring buffer status after enqueue:startIndex:%d     framesUsed:%d",start,used);
    OSSpinLockUnlock(&spinLock);
    return YES;
}

- (BOOL)dequeueData:(void *)data dataByteLength:(UInt32)dataByteSize {
    if (![self hasDataAvailableForDequeue:dataByteSize]) {
        return NO;
    }
    
    //does the buffer has a continuous data?
    BOOL hasContinuousData = NO;
    //OSSpinLockLock(&spinLock);
    if ((totalFrameCount-currentFrameIndex)*bytesPerFrame>=dataByteSize) {
        hasContinuousData = YES;
    }
    //OSSpinLockLock(&spinLock);
    
    //if has continuous data, just copy it
    if (hasContinuousData) {
        //OSSpinLockLock(&spinLock);
        memcpy(data, audioBuffer->mData+currentFrameIndex*bytesPerFrame, dataByteSize);
        //OSSpinLockLock(&spinLock);
    }else{
        //OSSpinLockLock(&spinLock);
        UInt32 firstPartDataSize = (totalFrameCount-currentFrameIndex)*bytesPerFrame;
        //first copy part of data from currentFrameIndex to end of buffer
        memcpy(data, audioBuffer->mData+currentFrameIndex*bytesPerFrame, firstPartDataSize);
        //second copy remaining data from start of buffer
        memcpy(data+firstPartDataSize, audioBuffer->mData, dataByteSize-firstPartDataSize);
        //OSSpinLockLock(&spinLock);
    }
    
    //OSSpinLockLock(&spinLock);
    currentFrameIndex = (currentFrameIndex+dataByteSize/bytesPerFrame)%totalFrameCount;
    currentUsedFrameCount -= dataByteSize/bytesPerFrame;
    //OSSpinLockLock(&spinLock);
    
    return NO;
}

@end
