//
//  LXAudioPlayer.m
//  LXAudioPlayer
//
//  Created by 李 行 on 16/1/11.
//  Copyright © 2016年 lixing123.com. All rights reserved.
//

#import "LXAudioPlayer.h"
#import <AudioToolbox/AudioToolbox.h>

typedef void (^failOperation) ();

#define DEBUG_MODE

#ifdef DEBUG_MODE
#define LXLog(fmt, ...) NSLog((@"%s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)
#else
#define LXLog(...)
#endif

typedef struct AudioConverterStruct{
    UInt16 *inData;
    UInt32 dataFrameCount;
}AudioConverterStruct;

static void handleError(OSStatus result, const char *failReason, failOperation operation)
{
    if (result == noErr) return;
    
    char errorString[20];
    *(UInt32 *)(errorString + 1) = CFSwapInt32HostToBig(result);
    if (isprint(errorString[1]) && isprint(errorString[2]) && isprint(errorString[3]) && isprint(errorString[4])) {
        errorString[0] = errorString[5] = '\'';
        errorString[6] = '\0';
    } else
        sprintf(errorString, "%d", (int)result);
    
    fprintf(stderr, "Error: %s (%s)\n", failReason, errorString);
    if (!operation) {
        exit(1);
    }else{
        operation();
    }
}

@interface LXAudioPlayer ()<NSStreamDelegate>{
}

@property(nonatomic)AUGraph graph;
@property(nonatomic)AudioUnit remoteIOUnit;
@property(nonatomic)NSURL *url;
@property(nonatomic)AudioFileStreamID stream;
@property(nonatomic)NSInputStream *inputStream;
@property(nonatomic)AudioStreamBasicDescription canonicalFormat;
@property(nonatomic)AudioConverterRef audioConverter;

- (void)setupAudioConverterWithSourceFormat:(AudioStreamBasicDescription *)sourceFormat;

@end

static OSStatus RemoteIOUnitCallback(void *							inRefCon,
                                     AudioUnitRenderActionFlags *	ioActionFlags,
                                     const AudioTimeStamp *			inTimeStamp,
                                     UInt32							inBusNumber,
                                     UInt32							inNumberFrames,
                                     AudioBufferList * __nullable	ioData){
    
    //read from input file
//    UInt8 inputBuffer[inNumberFrames];
//    if (player.inputStream.hasBytesAvailable) {
//        NSInteger readLength = [player.inputStream read:inputBuffer
//                                              maxLength:inNumberFrames];
//        NSLog(@"read length:%ld",(long)readLength);
//    }else{
//        NSLog(@"input stream has no data available");
//    }
    
    //copy buffer to ioData
//    for (int i=0; i<inNumberFrames; i++) {
//        AudioBuffer buffer = ioData->mBuffers[i];
//        buffer.mDataByteSize = inNumberFrames;
//        buffer.mNumberChannels = 1;
//        buffer.mData = malloc(inNumberFrames*sizeof(UInt8));
//        memcpy(&buffer, inputBuffer, inNumberFrames*sizeof(UInt8));
//    }
    
    return noErr;
}

OSStatus MyAudioConverterComplexInputDataProc(AudioConverterRef               inAudioConverter,
                                              UInt32 *                        ioNumberDataPackets,
                                              AudioBufferList *               ioData,
                                              AudioStreamPacketDescription * __nullable * __nullable outDataPacketDescription,
                                              void * __nullable               inUserData){
    //supplies input data to AudioConverter and let the converter convert to PCM format
    LXLog(@"");
    AudioConverterStruct *converterStruct = (AudioConverterStruct*)inUserData;
    
    ioData->mNumberBuffers = 1;
    ioData->mBuffers[0].mDataByteSize = converterStruct->dataFrameCount;
    ioData->mBuffers[0].mNumberChannels = 1;
    ioData->mBuffers[0].mData = malloc(sizeof(UInt16)*converterStruct->dataFrameCount);
    memcpy(ioData->mBuffers[0].mData, converterStruct->inData, sizeof(UInt16)*converterStruct->dataFrameCount);
    
    return noErr;
}

void MyAudioFileStream_PropertyListenerProc(void *							inClientData,
                                            AudioFileStreamID				inAudioFileStream,
                                            AudioFileStreamPropertyID		inPropertyID,
                                          AudioFileStreamPropertyFlags *	ioFlags){
    LXAudioPlayer *player = (__bridge LXAudioPlayer*)inClientData;
    LXLog(@"audio file stream get property:%d",inPropertyID);
    switch (inPropertyID) {
        case kAudioFileStreamProperty_DataFormat:{
            AudioStreamBasicDescription inputFormat;
            UInt32 size = sizeof(inputFormat);
            handleError(AudioFileStreamGetProperty(inAudioFileStream,
                                                   kAudioFileStreamProperty_DataFormat,
                                                   &size,
                                                   &inputFormat),
                        "failed to get input stream's data format",
                        ^{
                            
                        });
            [player setupAudioConverterWithSourceFormat:&inputFormat];
            break;
        }
        default:
            break;
    }
}

void MyAudioFileStream_PacketsProc (void *							inClientData,
                                    UInt32							inNumberBytes,
                                    UInt32							inNumberPackets,
                                    const void *					inInputData,
                                    AudioStreamPacketDescription	*inPacketDescriptions){
    LXLog(@"");
    LXAudioPlayer *player = (__bridge LXAudioPlayer*)inClientData;
    
    //get maximum buffer size
    UInt32 maxBufferSize;
    UInt32 size = sizeof(maxBufferSize);
    AudioConverterGetProperty(player.audioConverter,
                              kAudioConverterPropertyMinimumOutputBufferSize,
                              &size,
                              &maxBufferSize);
    
    //define input data of audio converter
    AudioConverterStruct converterStruct = {0};
    converterStruct.inData = (UInt16*)inInputData;
    converterStruct.dataFrameCount = inNumberBytes;
    
    //define output data of audio converter
    AudioBufferList bufferList;
    bufferList.mNumberBuffers = 1;
    bufferList.mBuffers[0].mNumberChannels = player.canonicalFormat.mChannelsPerFrame;
    bufferList.mBuffers[0].mDataByteSize = maxBufferSize;
    bufferList.mBuffers[0].mData = malloc(maxBufferSize*sizeof(UInt16));
    handleError(AudioConverterFillComplexBuffer(player.audioConverter,
                                                MyAudioConverterComplexInputDataProc,
                                                &converterStruct,
                                                &inNumberPackets,
                                                &bufferList,
                                                NULL),
                "AudioConverterFillComplexBuffer failed",
                ^{
                    
                });
    
    //store bufferList
}

@implementation LXAudioPlayer

#pragma mark -

- (id)initWithURL:(NSURL *)url {
    if (self=[super init]) {
        self.url = url;
        [self setupInputStream];
        
        [self setupAudioFileStreamService];
        
        //set up graph
        [self setupGraph];
    }
    
    return self;
}

- (void)play {
    handleError(AUGraphStart(_graph),
                "AUGraphStart failed",
                ^{
                    
                });
    LXLog(@"play");
}

- (void)pause {
    handleError(AUGraphStop(_graph),
                "AUGraphStop failed",
                ^{
                    
                });
}

- (void)stop {
    
}

- (void)seekToTime:(float)seekTime {
    
}

//- (void)enableCache:(BOOL)cacheEnabled{}

- (void)setCacheURL:(NSURL *)cacheURL {
    
}

#pragma mark -

- (void)setupInputStream{
    self.inputStream = [[NSInputStream alloc] initWithURL:self.url];
    self.inputStream.delegate = self;
    [self.inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop]
                                forMode:NSDefaultRunLoopMode];
    [self.inputStream open];
}

- (void)setupAudioFileStreamService{
    AudioFileStreamID localStream;
    handleError(AudioFileStreamOpen((__bridge void*)self,
                                    MyAudioFileStream_PropertyListenerProc,
                                    MyAudioFileStream_PacketsProc,
                                    0,//TODO:define file type hint based on file extension
                                    &localStream),
                "failed to open audio file stream",
                ^{
                    
                });
    self.stream = localStream;
}

- (void)setupAudioConverterWithSourceFormat:(AudioStreamBasicDescription *)sourceFormat{
    LXLog(@"setting audio converter source format");
    AudioStreamBasicDescription streamFormat = self.canonicalFormat;
    AudioConverterRef audioConverter;
    AudioConverterNew(sourceFormat,
                      &streamFormat,
                      &audioConverter);
    self.audioConverter = audioConverter;
}

- (void)setupGraph{
    handleError(NewAUGraph(&_graph),
                "NewAUGraph failed",
                ^{
                    
                });
    
    //create RemoteIO audio unit
    AudioComponentDescription remoteIODescription = {0};
    remoteIODescription.componentType = kAudioUnitType_Output;
    remoteIODescription.componentSubType = kAudioUnitSubType_RemoteIO;
    remoteIODescription.componentManufacturer = kAudioUnitManufacturer_Apple;
    
    AUNode remoteIONode;
    handleError(AUGraphAddNode(_graph,
                               &remoteIODescription,
                               &remoteIONode),
                "add RemoteIO node to graph failed",
                ^{
                    
                });
    handleError(AUGraphOpen(_graph),
                "open graph failed",
                ^{
                    
                });
    handleError(AUGraphNodeInfo(_graph,
                                remoteIONode,
                                NULL,
                                &_remoteIOUnit),
                "AUGraphNodeInfo failed",
                ^{
                    
                });
    
    //open output hardware(speaker) of remoteIO unit
    UInt32 enableIO = 1;
    UInt32 size = sizeof(enableIO);
    
    handleError(AudioUnitSetProperty(_remoteIOUnit,
                                     kAudioOutputUnitProperty_EnableIO,
                                     kAudioUnitScope_Output,
                                     0,
                                     &enableIO,
                                     size),
                "enable speaker of remoteIO failed",
                ^{
                    
                });
    
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
    handleError(AudioUnitSetProperty(_remoteIOUnit,
                                     kAudioUnitProperty_StreamFormat,
                                     kAudioUnitScope_Input,
                                     0,
                                     &streamFormat,
                                     sizeof(streamFormat)),
                "unable to set stream format of remoteIO unit",
                ^{
                    
                });
    self.canonicalFormat = streamFormat;
    
    //set render callback of remoteIO unit
    AURenderCallbackStruct callbackStruct;
    callbackStruct.inputProc = RemoteIOUnitCallback;
    //why need __bridge void*???
    callbackStruct.inputProcRefCon = (__bridge void*)self;
    handleError(AudioUnitSetProperty(_remoteIOUnit,
                                     kAudioUnitProperty_SetRenderCallback,
                                     kAudioUnitScope_Input,
                                     0,
                                     &callbackStruct,
                                     sizeof(callbackStruct)),
                "unable to set render callback of remoteIO unit",
                ^{
                    
                });
    
    handleError(AUGraphInitialize(_graph),
                "initialize graph failed",
                ^{
                    
                });
    LXLog(@"ready to set up graph");
}

#pragma mark - NSStreamDelegate

//TODO:implement this function
- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode {
    switch (eventCode) {
        case NSStreamEventNone:
            
            break;
        case NSStreamEventOpenCompleted:
            
            break;
        
        case NSStreamEventHasBytesAvailable:{
            //LXLog(@"read from NSInputStream");
            //read from input file
            //TODO:figure out buffer size
            UInt32 bufferSize = 1024;
            UInt8 inputBuffer[bufferSize];
            NSInteger readLength;
            if (self.inputStream.hasBytesAvailable) {
                readLength = [self.inputStream read:inputBuffer
                                          maxLength:bufferSize];
                NSLog(@"read length:%ld",(long)readLength);
            }else{
                NSLog(@"input stream has no data available");
            }
            
            //copy buffer to ioData
//            for (int i=0; i<bufferSize; i++) {
//                AudioBuffer buffer = ioData->mBuffers[i];
//                buffer.mDataByteSize = inNumberFrames;
//                buffer.mNumberChannels = 1;
//                buffer.mData = malloc(inNumberFrames*sizeof(UInt8));
//                memcpy(&buffer, inputBuffer, inNumberFrames*sizeof(UInt8));
//            }
            
            AudioFileStreamParseBytes(self.stream,
                                      (UInt32)readLength,
                                      inputBuffer,
                                      0);
            
            break;
        }
        case NSStreamEventErrorOccurred:
            
            break;
        case NSStreamEventEndEncountered:
            
            break;
        default:
            break;
    }
}

@end















