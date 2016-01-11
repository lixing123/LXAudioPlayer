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
    // see if it appears to be a 4-char-code
    *(UInt32 *)(errorString + 1) = CFSwapInt32HostToBig(result);
    if (isprint(errorString[1]) && isprint(errorString[2]) && isprint(errorString[3]) && isprint(errorString[4])) {
        errorString[0] = errorString[5] = '\'';
        errorString[6] = '\0';
    } else
        // no, format it as an integer
        sprintf(errorString, "%d", (int)result);
    
    fprintf(stderr, "Error: %s (%s)\n", operation, errorString);
    
    exit(1);
}

@interface LXAudioPlayer (){
    MyGraphPlayer player;
}

@end

@implementation LXAudioPlayer

#pragma mark -

- (id)initWithURL:(NSURL *)url {
    if (self=[super init]) {
        NSInputStream *inputStream = [[NSInputStream alloc] initWithURL:url];
        
        //set up graph
        [self setupGraph];
    }
    
    return self;
}

- (void)play {
    
}

- (void)pause {
    
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
    handleError(AUGraphNodeInfo(player.graph,
                                remoteIONode,
                                NULL,
                                &player.remoteIOUnit),
                "AUGraphNodeInfo failed");
}

@end















