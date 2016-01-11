//
//  LXAudioPlayer.m
//  LXAudioPlayer
//
//  Created by 李 行 on 16/1/11.
//  Copyright © 2016年 lixing123.com. All rights reserved.
//

#import "LXAudioPlayer.h"
#import <AudioToolbox/AudioToolbox.h>

typedef struct MyGraphPlayer{
    AUGraph graph;
    AudioUnit remoteIOUnit;
}MyGraphPlayer;

//TODO:change char* to error type
static void handleError(OSStatus result, const char *operation)
{
    if (result == noErr) return;
    
    char errorString[20];
    *(UInt32 *)(errorString + 1) = CFSwapInt32HostToBig(result);
    if (isprint(errorString[1]) && isprint(errorString[2]) && isprint(errorString[3]) && isprint(errorString[4])) {
        errorString[0] = errorString[5] = '\'';
        errorString[6] = '\0';
    } else
        sprintf(errorString, "%d", (int)result);
    
    fprintf(stderr, "Error: %s (%s)\n", operation, errorString);
    
    exit(1);
}

OSStatus RemoteIOUnitCallback(void *							inRefCon,
                              AudioUnitRenderActionFlags *	    ioActionFlags,
                              const AudioTimeStamp *			inTimeStamp,
                              UInt32							inBusNumber,
                              UInt32							inNumberFrames,
                              AudioBufferList * __nullable	    ioData){
    //TODO:implement this function
    
    return noErr;
}

@interface LXAudioPlayer (){
    MyGraphPlayer player;
}

@end

@implementation LXAudioPlayer

#pragma mark -

- (id)initWithURL:(NSURL *)url {
    if (self=[super init]) {
        //TODO:set up input stream
        NSInputStream *inputStream = [[NSInputStream alloc] initWithURL:url];
        
        //set up graph
        [self setupGraph];
    }
    
    return self;
}

- (void)play {
    handleError(AUGraphStart(player.graph),
                "AUGraphStart failed");
}

- (void)pause {
    handleError(AUGraphStop(player.graph),
                "AUGraphStop failed");
}

- (void)stop {
    
}

- (void)seekToTime:(float)seekTime {
    
}

//- (void)enableCache:(BOOL)cacheEnabled{}

- (void)setCacheURL:(NSURL *)cacheURL {
    
}

#pragma mark -

- (void)setupGraph{
    handleError(NewAUGraph(&player.graph),
                "NewAUGraph failed");
    
    //create RemoteIO audio unit
    AudioComponentDescription remoteIODescription = {0};
    remoteIODescription.componentType = kAudioUnitType_Output;
    remoteIODescription.componentSubType = kAudioUnitSubType_RemoteIO;
    remoteIODescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    AUNode remoteIONode;
    handleError(AUGraphAddNode(player.graph,
                               &remoteIODescription,
                               &remoteIONode),
                "add RemoteIO node to graph failed");
    handleError(AUGraphOpen(player.graph),
                "open graph failed");
    handleError(AUGraphNodeInfo(player.graph,
                                remoteIONode,
                                NULL,
                                &player.remoteIOUnit),
                "AUGraphNodeInfo failed");
    
    //open output hardware(speaker) of remoteIO unit
    UInt32 enableIO = 1;
    UInt32 size = sizeof(enableIO);
    
    handleError(AudioUnitSetProperty(player.remoteIOUnit,
                                     kAudioOutputUnitProperty_EnableIO,
                                     kAudioUnitScope_Output,
                                     0,
                                     &enableIO,
                                     size),
                "enable speaker of remoteIO failed");
    
    //set input stream format of remoteIO unit
    AudioStreamBasicDescription streamFormat = {0};
    streamFormat.mFormatID = kAudioFormatLinearPCM;
    streamFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    streamFormat.mSampleRate = 44100.0;
    streamFormat.mFramesPerPacket = 1;
    streamFormat.mBytesPerPacket = 4;
    streamFormat.mBytesPerFrame = 4;
    streamFormat.mChannelsPerFrame = 2;
    streamFormat.mBitsPerChannel = 16;
    handleError(AudioUnitSetProperty(player.remoteIOUnit,
                                     kAudioUnitProperty_StreamFormat,
                                     kAudioUnitScope_Input,
                                     0,
                                     &streamFormat,
                                     sizeof(streamFormat)),
                "unable to set stream format of remoteIO unit");
    
    //set render callback of remoteIO unit
    AURenderCallbackStruct callbackStruct;
    callbackStruct.inputProc = RemoteIOUnitCallback;
    callbackStruct.inputProcRefCon = &player;
    handleError(AudioUnitSetProperty(player.remoteIOUnit,
                                     kAudioUnitProperty_SetRenderCallback,
                                     kAudioUnitScope_Input,
                                     0,
                                     &callbackStruct,
                                     sizeof(callbackStruct)),
                "unable to set render callback of remoteIO unit");
    
    handleError(AUGraphInitialize(player.graph),
                "initialize graph failed");
}

@end















