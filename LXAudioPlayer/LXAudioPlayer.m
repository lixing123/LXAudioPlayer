//
//  LXAudioPlayer.m
//  LXAudioPlayer
//
//  Created by 李 行 on 16/1/11.
//  Copyright © 2016年 lixing123.com. All rights reserved.
//

#import "LXAudioPlayer.h"
#import "LXHeader.h"
#import <AudioToolbox/AudioToolbox.h>
#import "LXRingBuffer.h"
#import <pthread/pthread.h>

typedef void (^failOperation) ();

typedef struct AudioConverterStruct{
    AudioBuffer audioBuffer;
    UInt32 packetCount;
    AudioStreamPacketDescription *packetDescriptions;
    BOOL used;
}AudioConverterStruct;

typedef struct
{
    BOOL done;
    UInt32 numberOfPackets;
    AudioBuffer audioBuffer;
    AudioStreamPacketDescription* packetDescriptions;
}
AudioConvertInfo;

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
@public
    pthread_mutex_t playerMutex;
    pthread_mutex_t ringBufferMutex;
    pthread_cond_t ringBufferFilledCondition;
}

@property(nonatomic,readwrite)float duration;

@property(nonatomic)AUGraph graph;
@property(nonatomic)AudioUnit remoteIOUnit;
@property(nonatomic)NSURL *url;
@property(nonatomic)AudioFileStreamID audioFileStream;
@property(nonatomic)NSInputStream *inputStream;
@property(nonatomic)NSNumber *inputStreamOffset;
@property(nonatomic)AudioStreamBasicDescription canonicalFormat;
@property(nonatomic)AudioStreamBasicDescription converterInputFormat;
@property(nonatomic)AudioConverterRef audioConverter;
@property(nonatomic)LXRingBuffer *ringBuffer;
@property(nonatomic)NSThread *playbackThread;
@property(nonatomic)NSRunLoop *playbackRunLoop;
@property(nonatomic)NSConditionLock *playbackThreadRunningLock;

@property(nonatomic)BOOL waiting;

- (void)setupAudioConverterWithSourceFormat:(AudioStreamBasicDescription *)sourceFormat;

@end

static OSStatus RemoteIOUnitCallback(void *							inRefCon,
                                     AudioUnitRenderActionFlags *	ioActionFlags,
                                     const AudioTimeStamp *			inTimeStamp,
                                     UInt32							inBusNumber,
                                     UInt32							inNumberFrames,
                                     AudioBufferList * __nullable	ioData){
    LXAudioPlayer *player = (__bridge LXAudioPlayer*)inRefCon;
    
    //read from ring buffer
    UInt32 ioDataByteSize = inNumberFrames*player.canonicalFormat.mBytesPerFrame;
    if ([player.ringBuffer hasDataAvailableForDequeue:ioDataByteSize]) {
        [player.ringBuffer dequeueData:ioData->mBuffers[0].mData
                        dataByteLength:ioDataByteSize];
        ioData->mBuffers[0].mDataByteSize = ioDataByteSize;
        ioData->mBuffers[0].mNumberChannels = 1;
        ioData->mNumberBuffers = 1;
    }else{
        //TODO:when no enough data, tell the delegate or do other things
        ioData->mBuffers[0].mData = calloc(ioDataByteSize, 1);
        ioData->mBuffers[0].mDataByteSize = ioDataByteSize;
        ioData->mBuffers[0].mNumberChannels = 1;
        ioData->mNumberBuffers = 1;
    }
    
    if ([player.ringBuffer needToBeFilled]&&player.waiting) {
        //tell the NSInputStream delegate to continue read data
        pthread_mutex_lock(&player->ringBufferMutex);
        pthread_cond_signal(&player->ringBufferFilledCondition);
        pthread_mutex_unlock(&player->ringBufferMutex);
    }
    
    return noErr;
}

OSStatus MyAudioConverterComplexInputDataProc(AudioConverterRef               inAudioConverter,
                                              UInt32 *                        ioNumberDataPackets,
                                              AudioBufferList *               ioData,
                                              AudioStreamPacketDescription * __nullable * __nullable outDataPacketDescription,
                                              void * __nullable               inUserData){
    //supplies input data to AudioConverter and let the converter convert to PCM format
    AudioConvertInfo* convertInfo = (AudioConvertInfo*)inUserData;
    
    if (convertInfo->done)
    {
        ioNumberDataPackets = 0;
        
        return 100;
    }
    
    ioData->mNumberBuffers = 1;
    //将audioBuffer拷贝到converter的output中
    ioData->mBuffers[0] = convertInfo->audioBuffer;
    
    if (outDataPacketDescription)
    {
        *outDataPacketDescription = convertInfo->packetDescriptions;
    }
    
    *ioNumberDataPackets = convertInfo->numberOfPackets;
    convertInfo->done = YES;
    
    //if ring buffer has space for data, reschedule input stream to run loop
    
    return 0;
}

void MyAudioFileStream_PropertyListenerProc(void *							inClientData,
                                            AudioFileStreamID				inAudioFileStream,
                                            AudioFileStreamPropertyID		inPropertyID,
                                            AudioFileStreamPropertyFlags *	ioFlags){
    LXAudioPlayer *player = (__bridge LXAudioPlayer*)inClientData;
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
        case kAudioFileStreamProperty_AudioDataByteCount:{
            //create a ring buffer that don't need to read circle
            //TODO:fix bugs when ring buffer size is less than size of audio
            //init ring buffer
//            UInt64 fileSize;
//            UInt32 propSize = sizeof(fileSize);
//            handleError(AudioFileStreamGetProperty(inAudioFileStream,
//                                                   kAudioFileStreamProperty_AudioDataByteCount,
//                                                   &propSize,
//                                                   &fileSize),
//                        "kAudioFileStreamProperty_AudioDataByteCount failed",
//                        ^{
//                            
//                        });
//            player.duration = fileSize;
//            player.ringBuffer = [[LXRingBuffer alloc] initWithDataPCMFormat:player.canonicalFormat
//                                                                    seconds:player.duration];
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
    LXAudioPlayer *player = (__bridge LXAudioPlayer*)inClientData;
    
    //define input data of audio converter
    AudioConvertInfo convertInfo;
    
    convertInfo.done = NO;
    convertInfo.numberOfPackets = inNumberPackets;
    convertInfo.packetDescriptions = inPacketDescriptions;
    convertInfo.audioBuffer.mData = (void *)inInputData;
    convertInfo.audioBuffer.mDataByteSize = inNumberBytes;
    convertInfo.audioBuffer.mNumberChannels = player.converterInputFormat.mChannelsPerFrame;
    
    //define output data of audio converter
    while (1) {
        UInt32 maxBufferSize = 1024 * 16;
        AudioBufferList bufferList;
        bufferList.mNumberBuffers = 1;
        AudioBuffer *buffer = &bufferList.mBuffers[0];
        buffer->mNumberChannels = player.canonicalFormat.mChannelsPerFrame;
        buffer->mDataByteSize = maxBufferSize;
        buffer->mData = malloc(maxBufferSize);
        OSStatus result = AudioConverterFillComplexBuffer(player.audioConverter,
                                                          MyAudioConverterComplexInputDataProc,
                                                          &convertInfo,
                                                          &maxBufferSize,
                                                          &bufferList,
                                                          NULL);
        if (result==0) {
            //store bufferList
            if ([player.ringBuffer hasSpaceAvailableForEnqueue:buffer->mDataByteSize]) {
                BOOL enqueueResult = [player.ringBuffer enqueueData:buffer->mData
                                                     dataByteLength:buffer->mDataByteSize];
                if (!enqueueResult) {
                    LXLog(@"enqueue failed");
                }
                free(buffer->mData);
                buffer->mData = NULL;
            }else{
                NSLog(@"no enough space for data");
            }
            continue;
        }else if (result==100){//need data from AudioFileStream
            if ([player.ringBuffer hasSpaceAvailableForEnqueue:buffer->mDataByteSize]) {
                BOOL enqueueResult = [player.ringBuffer enqueueData:buffer->mData
                                                     dataByteLength:buffer->mDataByteSize];
                if (!enqueueResult) {
                    LXLog(@"enqueue failed");
                }
                free(buffer->mData);
                buffer->mData = NULL;
            }else{
                LXLog(@"no enough space for data");
                free(buffer->mData);
                buffer->mData = NULL;
            }
            return;
        }else{//error
            LXLog(@"audio converter error");
            free(buffer->mData);
            buffer->mData = NULL;
            return;
        }
    }
}

@implementation LXAudioPlayer

#pragma mark -

- (id)initWithURL:(NSURL *)url {
    if (self=[super init]) {
        self.url = url;
        
        [self setupLocks];
        
        [self setupPlaybackThread];
        
        [self setupInputStream];
        
        [self setupAudioFileStreamService];
        
        //set up graph
        [self setupCanonicalFormat];
        
        //set up ring buffer based on canonical stream format
        [self setupRingBuffer];
        
        [self setupGraph];
    }
    
    return self;
}

- (void)play {
    //pthread_mutex_lock(&playerMutex);
    BOOL isRunning = [self graphRunningState];
    if (!isRunning) {
        pthread_mutex_lock(&playerMutex);
        handleError(AUGraphStart(_graph),
                    "AUGraphStart failed",
                    ^{
                        
                    });
        pthread_mutex_unlock(&playerMutex);
    }
}

- (BOOL)graphRunningState {
    Boolean isRunning;
    OSStatus status = AUGraphIsRunning(_graph,
                                       &isRunning);
    if (status) {
        return NO;
    }
    return isRunning;
}

- (void)pause {
    BOOL isRunning = [self graphRunningState];
    LXLog(@"AUGraph is running:%d",isRunning);
    handleError(AUGraphStop(_graph),
                "pause AUGraph failed",
                ^{
                    
                });
}

- (void)resume {
    BOOL isRunning = [self graphRunningState];
    LXLog(@"AUGraph is running:%d",isRunning);
    handleError(AUGraphStart(_graph),
                "resume AUGraph failed",
                ^{
                    
                });
}

- (void)stop {
    BOOL isRunning = [self graphRunningState];
    LXLog(@"AUGraph is running:%d",isRunning);
    //clear AUGraph
    handleError(AUGraphStop(_graph),
                "stop AUGraph failed", ^{
                    
                });
    [self destroyGraph];
    //clear pthread locks
    [self destroyLocks];
    
    //clear audio player
    [self destroyRingBuffer];
    [self destroyAudioConverter];
    [self destroyInputStream];
    [self destroyAudioFileStreamService];
}

- (void)seekToTime:(float)seekTime {
    
}

//- (void)enableCache:(BOOL)cacheEnabled{}

- (void)setCacheURL:(NSURL *)cacheURL {
    
}

#pragma mark -

- (void)setupInputStream {
    self.inputStream = [[NSInputStream alloc] initWithURL:self.url];
    self.inputStream.delegate = self;
    //make sure the playback thread is already running
    [self.playbackThreadRunningLock lockWhenCondition:1];
    [self.playbackThreadRunningLock unlockWithCondition:0];
    [self.inputStream scheduleInRunLoop:self.playbackRunLoop
                                forMode:NSDefaultRunLoopMode];
    [self.inputStream open];
}

- (void)destroyInputStream {
    [self.inputStream close];
    [self.inputStream removeFromRunLoop:[NSRunLoop currentRunLoop]
                                forMode:NSDefaultRunLoopMode];
    self.inputStream.delegate = nil;
}

- (void)setupAudioFileStreamService {
    handleError(AudioFileStreamOpen((__bridge void*)self,
                                    MyAudioFileStream_PropertyListenerProc,
                                    MyAudioFileStream_PacketsProc,
                                    0,//TODO:define file type hint based on file extension
                                    &_audioFileStream),
                "failed to open audio file stream",
                ^{
                    
                });
}

- (void)destroyAudioFileStreamService {
    handleError(AudioFileStreamClose(_audioFileStream),
                "AudioFileStreamClose failed",
                ^{
                    
                });
}

- (void)setupAudioConverterWithSourceFormat:(AudioStreamBasicDescription *)sourceFormat {
    AudioStreamBasicDescription streamFormat = self.canonicalFormat;
    AudioConverterRef audioConverter;
    AudioConverterNew(sourceFormat,
                      &streamFormat,
                      &audioConverter);
    self.audioConverter = audioConverter;
    self.converterInputFormat = *sourceFormat;
}

- (void)destroyAudioConverter {
    handleError(AudioConverterDispose(self.audioConverter),
                "AudioConverterDispose failed",
                ^{
                    
                });
}

- (void)setupCanonicalFormat {
    //set input stream format of remoteIO unit
    //TODO:is it needed to destroy ASBD when dealloc?
    AudioStreamBasicDescription streamFormat = {0};
    streamFormat.mFormatID = kAudioFormatLinearPCM;
    streamFormat.mFormatFlags = kAudioFormatFlagIsSignedInteger | kAudioFormatFlagIsPacked;
    streamFormat.mSampleRate = 44100.0;
    streamFormat.mFramesPerPacket = 1;
    streamFormat.mBytesPerPacket = 4;
    streamFormat.mBytesPerFrame = 4;
    streamFormat.mChannelsPerFrame = 2;
    streamFormat.mBitsPerChannel = 16;
    self.canonicalFormat = streamFormat;
}

- (void)setupRingBuffer {
    self.ringBuffer = [[LXRingBuffer alloc] initWithDataPCMFormat:self.canonicalFormat
                                                          seconds:5.0];
}

- (void)destroyRingBuffer {
    if (self.ringBuffer) {
        [self.ringBuffer destroy];
    }
    self.ringBuffer = nil;
}

- (void)setupGraph {
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
    
    handleError(AudioUnitSetProperty(_remoteIOUnit,
                                     kAudioUnitProperty_StreamFormat,
                                     kAudioUnitScope_Input,
                                     0,
                                     &_canonicalFormat,
                                     sizeof(_canonicalFormat)),
                "unable to set stream format of remoteIO unit",
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
}

- (void)destroyGraph {
    handleError(AUGraphStop(_graph),
                "AUGraphStop failed",
                ^{
                    LXLog(@"AUGraphStop failed");
                });
    handleError(AUGraphUninitialize(_graph),
                "AUGraphUninitialize failed",
                ^{
                    LXLog(@"AUGraphUninitialize failed");
                });
    handleError(AUGraphClose(_graph),
                "AUGraphClose failed",
                ^{
                    LXLog(@"AUGraphClose failed");
                });
    handleError(DisposeAUGraph(_graph),
                "DisposeAUGraph failed",
                ^{
                    LXLog(@"DisposeAUGraph failed");
                });
}

- (void)setupLocks {
    pthread_mutex_init(&playerMutex, NULL);
    pthread_mutex_init(&ringBufferMutex, NULL);
    pthread_cond_init(&ringBufferFilledCondition, NULL);
    self.playbackThreadRunningLock = [[NSConditionLock alloc] initWithCondition:0];
}

- (void)destroyLocks {
    pthread_mutex_destroy(&ringBufferMutex);
    pthread_mutex_destroy(&playerMutex);
    pthread_cond_destroy(&ringBufferFilledCondition);
}

- (void)setupPlaybackThread {
    self.playbackThread = [[NSThread alloc] initWithTarget:self
                                                  selector:@selector(playback)
                                                    object:nil];
    [self.playbackThread start];
}

- (void)playback {
    self.playbackRunLoop = [NSRunLoop currentRunLoop];
    
    [self.playbackThreadRunningLock lockWhenCondition:0];
    [self.playbackThreadRunningLock unlockWithCondition:1];
    
    [self.playbackRunLoop addPort:[NSPort port] forMode:NSDefaultRunLoopMode];
    //TODO:stop run loop at a proper time
    [self.playbackRunLoop run];
}

#pragma mark - NSStreamDelegate

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode {
    NSInputStream *aInputStream = (NSInputStream *)aStream;
    switch (eventCode) {
        case NSStreamEventNone:{
            LXLog(@"stream event none");
            break;
        }
        case NSStreamEventOpenCompleted:{
            LXLog(@"stream event open complete");
            break;
        }
        case NSStreamEventHasBytesAvailable:{
            //read from input file
            //if ring buffer doesn't need data, block here
            if ([self.ringBuffer filled]) {
                    pthread_mutex_lock(&ringBufferMutex);
                    while (true) {
                        if ([self.ringBuffer needToBeFilled]) {
                            break;
                        }
                        
                        self.waiting = YES;
                        pthread_cond_wait(&ringBufferFilledCondition, &ringBufferMutex);
                        self.waiting = NO;
                    }
                    pthread_mutex_unlock(&ringBufferMutex);
            }
            
            if (![self.ringBuffer filled]) {
                if (self.inputStream.hasBytesAvailable) {
                    //TODO:figure out buffer size
                    UInt32 bufferSize = 1024;
                    UInt8 *inputBuffer = calloc(sizeof(UInt8)*bufferSize, 1);
                    NSInteger readLength;
                    
                    readLength = [aInputStream read:inputBuffer
                                          maxLength:bufferSize];
                    
                    AudioFileStreamParseBytes(self.audioFileStream,
                                              (UInt32)readLength,
                                              inputBuffer,
                                              0);
                    free(inputBuffer);
                    inputBuffer = NULL;
                }
            }
            
            break;
        }
        case NSStreamEventErrorOccurred:{
            LXLog(@"stream event error");
            break;
        }
        case NSStreamEventEndEncountered:{
            LXLog(@"stream event end");
            //[self stop];
            break;
        }
        default:
            break;
    }
}

@end















