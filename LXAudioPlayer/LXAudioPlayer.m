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
        //exit(1);
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

@property(nonatomic,readwrite)NSTimeInterval duration;
@property(nonatomic)BOOL durationIsAccurate;
@property(nonatomic,readwrite)NSTimeInterval progress;
@property(nonatomic,readwrite)LXAudioPlayerState state;
//when buffered data is less than the value, playing will be paused and state is buffering

@property(nonatomic)NSURL *url;
@property(nonatomic,readwrite)BOOL isPlaying;
@property(nonatomic,readwrite)float volume;
@property(nonatomic,readwrite)NSUInteger numberOfChannels;

@property(nonatomic)NSInputStream *inputStream;
@property(nonatomic)NSNumber *inputStreamOffset;//used for seeking
@property(nonatomic)AudioFileStreamID audioFileStream;
@property(nonatomic)AudioStreamBasicDescription canonicalFormat;
@property(nonatomic)AudioStreamBasicDescription inputFormat;
@property(nonatomic)AudioConverterRef audioConverter;

@property(nonatomic)AUGraph graph;
@property(nonatomic)AudioUnit remoteIOUnit;
@property(nonatomic)LXRingBuffer *ringBuffer;
//playback thread
@property(nonatomic)NSThread *playbackThread;
@property(nonatomic)NSRunLoop *playbackRunLoop;
@property(nonatomic)NSConditionLock *playbackThreadRunningLock;
@property(nonatomic)BOOL AudioFileStreamIsWaitingForSpace;//thread is waiting for data

//duration calculation
//duration = dataByteCount/bitRate, or
//duration = (fileSize-dataOffset)/bitRate
@property(nonatomic)float dataByteCount;
@property(nonatomic)float bitRate;//bits per second
@property(nonatomic)float fileSize;
@property(nonatomic)float dataOffset;
//used to calculate bit rate
@property(nonatomic)float packetDuration;//duration of per packet
@property(nonatomic)float processedPacketTotalSize;
@property(nonatomic)int processedPacketCount;

- (void)setupAudioConverterWithSourceFormat:(AudioStreamBasicDescription *)sourceFormat;
- (void)calculateDuration;

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
    if ([player.ringBuffer hasDataForLenghthInSeconds:player.minBufferLengthInSeconds]) {
        if ([player.ringBuffer hasDataAvailableForDequeue:ioDataByteSize]) {
            player.state = kLXAudioPlayerStatePlaying;
            [player.ringBuffer dequeueData:ioData->mBuffers[0].mData
                            dataByteLength:ioDataByteSize];
            ioData->mBuffers[0].mDataByteSize = ioDataByteSize;
            ioData->mBuffers[0].mNumberChannels = 1;
            ioData->mNumberBuffers = 1;
            
            //update progress
            player.progress += inNumberFrames/player.canonicalFormat.mSampleRate;
            //the following code is wrong
            //player.progress = inTimeStamp->mSampleTime/player.canonicalFormat.mSampleRate;
            //the following code is wrong too
            //        AudioTimeStamp timeStamp = {0};
            //        UInt32 propSize = sizeof(timeStamp);
            //        handleError(AudioUnitGetProperty(player.remoteIOUnit,
            //                                         kAudioUnitProperty_CurrentPlayTime,
            //                                         kAudioUnitScope_Global,
            //                                         0,
            //                                         &timeStamp,
            //                                         &propSize),
            //                    "AudioUnitGetProperty kAudioUnitProperty_CurrentPlayTime", ^{
            //                        
            //                    });
            
            //TODO:calculate volume, in format of dB
        }
    }else{
        player.state = kLXAudioPlayerStateBuffering;
        //TODO:when no enough data, tell the delegate or do other things
        ioData->mBuffers[0].mData = calloc(ioDataByteSize, 1);
        ioData->mBuffers[0].mDataByteSize = ioDataByteSize;
        ioData->mBuffers[0].mNumberChannels = 1;
        ioData->mNumberBuffers = 1;
        player.volume = 0.0;
    }
    
    if ([player.ringBuffer needToBeFilled]&&player.AudioFileStreamIsWaitingForSpace) {
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
            player.packetDuration = inputFormat.mFramesPerPacket/inputFormat.mSampleRate;
            player.numberOfChannels = inputFormat.mChannelsPerFrame;
            [player calculateDuration];
            break;
        }
        case kAudioFileStreamProperty_AudioDataByteCount:{
            UInt64 audioDataByteCount;
            UInt32 propSize = sizeof(audioDataByteCount);
            handleError(AudioFileStreamGetProperty(inAudioFileStream,
                                                   kAudioFileStreamProperty_AudioDataByteCount,
                                                   &propSize,
                                                   &audioDataByteCount),
                        "kAudioFileStreamProperty_AudioDataByteCount failed",
                        ^{
                            
                        });
            player.dataByteCount = audioDataByteCount;
            [player calculateDuration];
        }
        case kAudioFileStreamProperty_BitRate:{
            //TODO:bit rate sometimes wrong
//            UInt32 bitRate;
//            UInt32 propSize = sizeof(bitRate);
//            handleError(AudioFileStreamGetProperty(inAudioFileStream,
//                                                   kAudioFileStreamProperty_BitRate,
//                                                   &propSize,
//                                                   &bitRate),
//                        "AudioFileStreamGetProperty kAudioFileStreamProperty_BitRate",
//                        ^{
//                            LXLog(@"AudioFileStreamGetProperty kAudioFileStreamProperty_BitRate");
//                        });
//            player.bitRate = bitRate;
//            LXLog(@"bit rate:%d",bitRate);
            [player calculateDuration];
            break;
        }
        case kAudioFileStreamProperty_DataOffset:{
            SInt64 dataOffset;
            UInt32 propSize = sizeof(dataOffset);
            handleError(AudioFileStreamGetProperty(inAudioFileStream,
                                                   kAudioFileStreamProperty_DataOffset,
                                                   &propSize,
                                                   &dataOffset),
                        "AudioFileStreamGetProperty kAudioFileStreamProperty_DataOffset",
                        ^{
                            
                        });
            player.dataOffset = dataOffset;
            [player calculateDuration];
            break;
        }
        case kAudioFileStreamProperty_InfoDictionary:{
            CFDictionaryRef infoDictionary;
            UInt32 propSize;
            handleError(AudioFileStreamGetPropertyInfo(inAudioFileStream,
                                                       kAudioFileStreamProperty_InfoDictionary,
                                                       &propSize,
                                                       NULL),
                        "AudioFileStreamGetPropertyInfo kAudioFileStreamProperty_InfoDictionary",
                        ^{
                            
                        });
            handleError(AudioFileStreamGetProperty(inAudioFileStream,
                                                   kAudioFileStreamProperty_InfoDictionary,
                                                   &propSize,
                                                   &infoDictionary),
                        "AudioFileStreamGetProperty kAudioFileStreamProperty_InfoDictionary",
                        ^{
                            
                        });
            int *duration;
            duration = (int*)CFDictionaryGetValue(infoDictionary, kAFInfoDictionary_ApproximateDurationInSeconds);
            if (&duration>0) {
                player.duration = *duration;
                player.durationIsAccurate = YES;
            }
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
    LXAudioPlayer *player = (__bridge LXAudioPlayer*)inClientData;
    
    //update packet count and total size
    if (inPacketDescriptions) {
        //TODO:make this global #define variable
        int maxPacketCount = 128;
        if (player.processedPacketCount<maxPacketCount) {
            int count = MIN(maxPacketCount-player.processedPacketCount, inNumberPackets);
            for (int i=0; i<count; i++) {
                UInt32 packetSize = inPacketDescriptions[i].mDataByteSize;
                player.processedPacketTotalSize += packetSize;
                player.processedPacketCount++;
                if (player.processedPacketCount==maxPacketCount) {
                    [player calculateDuration];
                }
            }
        }
    }
    
    //define input data of audio converter
    AudioConvertInfo convertInfo;
    
    convertInfo.done = NO;
    convertInfo.numberOfPackets = inNumberPackets;
    convertInfo.packetDescriptions = inPacketDescriptions;
    convertInfo.audioBuffer.mData = (void *)inInputData;
    convertInfo.audioBuffer.mDataByteSize = inNumberBytes;
    convertInfo.audioBuffer.mNumberChannels = player.inputFormat.mChannelsPerFrame;
    
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

- (id)initWithURL:(NSURL *)url delegate:(id<LXAudioPlayerDelegate>)delegate{
    if (self=[super init]) {
        self.url = url;
        self.delegate = delegate;
        
        [self setupProperties];
        
        [self getFileSize];
        
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
    BOOL isRunning = [self graphRunningState];
    if (!isRunning) {
        self.state = kLXAudioPlayerStatePlaying;
        pthread_mutex_lock(&playerMutex);
        handleError(AUGraphStart(_graph),
                    "AUGraphStart failed",
                    ^{
                        self.state = kLXAudioPlayerStateError;
                    });
        pthread_mutex_unlock(&playerMutex);
    }
}

//TODD:fulfill this method
- (void)reset {
    [self.ringBuffer reset];
    
}

//TODO:change return value to a real "state"
- (BOOL)graphRunningState {
    Boolean isRunning;
    pthread_mutex_lock(&playerMutex);
    OSStatus status = AUGraphIsRunning(_graph,
                                       &isRunning);
    pthread_mutex_unlock(&playerMutex);
    if (status) {
        return NO;
    }
    return isRunning;
}

- (void)pause {
    BOOL isRunning = [self graphRunningState];
    self.state = kLXAudioPlayerStatePaused;
    if (isRunning) {
        handleError(AUGraphStop(_graph),
                    "pause AUGraph failed",
                    ^{
                        self.state = kLXAudioPlayerStateError;
                    });
    }
}

- (void)stop {
    //clear AUGraph
    self.state = kLXAudioPlayerStateStopped;
    handleError(AUGraphStop(_graph),
                "stop AUGraph failed", ^{
                    self.state = kLXAudioPlayerStateError;
                });
}

- (NSTimeInterval)seekToTime:(NSTimeInterval)seekTime {
    //AudioFileStream seek
    //TODO:check this applies to PCM, CBR and VBR
    //TODO: can packet duration calculated based on kAudioFileStreamProperty_AverageBytesPerPacket?
    //TODO:fix bugs when seeking network resources;
    pthread_mutex_lock(&playerMutex);
    float packetDuration = self.inputFormat.mFramesPerPacket/self.inputFormat.mSampleRate;
    SInt64 packetOffset = floor(seekTime/packetDuration);
    SInt64 actualByteOffset;
    AudioFileStreamSeekFlags flags;
    AudioFileStreamSeek(self.audioFileStream,
                        packetOffset,
                        &actualByteOffset,
                        &flags);
    //get data offset
    SInt64 dataOffset;
    UInt32 propSize = sizeof(dataOffset);
    AudioFileStreamGetProperty(self.audioFileStream,
                               kAudioFileStreamProperty_DataOffset,
                               &propSize,
                               &dataOffset);
    SInt64 fileOffset = actualByteOffset + dataOffset;
    
    //NSInputStream seek
    //TODO:sometimes file offset is much more than file size
    LXLog(@"file offset:%lld",fileOffset);
    BOOL result = [self.inputStream setProperty:@(fileOffset) forKey:NSStreamFileCurrentOffsetKey];
    LXLog(@"set file offset result:%d",result);
    LXLog(@"after offset:%d",[[self.inputStream propertyForKey:NSStreamFileCurrentOffsetKey] intValue]);
    
    //reset ringBuffer
    [self.ringBuffer reset];
    
    //signal playback thread
    pthread_mutex_lock(&ringBufferMutex);
    pthread_cond_signal(&ringBufferFilledCondition);
    pthread_mutex_unlock(&ringBufferMutex);
    
    //reset converter
    //without this line, seeking will cause "hissing"
    AudioConverterReset(self.audioConverter);
    
    self.progress = seekTime;
    pthread_mutex_unlock(&playerMutex);
    return actualByteOffset/self.canonicalFormat.mSampleRate;
}

//- (void)enableCache:(BOOL)cacheEnabled{}

//TODO:fulfill this method
- (void)setCacheURL:(NSURL *)cacheURL {
    
}

#pragma mark -

- (BOOL)isLocalFile {
    NSRange range;
    range.location = 0;
    range.length = 4;
    NSString *headerString = [self.url.absoluteString substringWithRange:range];
    return [headerString isEqualToString:@"file"];
}

- (void)setupProperties {
    self.dataByteCount = self.bitRate = self.fileSize = self.dataOffset = self.packetDuration = self.processedPacketTotalSize = self.processedPacketCount = self.progress = 0;
    self.durationIsAccurate = NO;
    self.isPlaying = NO;
    self.minBufferLengthInSeconds = 2.0;
}

- (void)setupInputStream {
    CFReadStreamRef inputStreamRef;
    if ([self isLocalFile]) {
        inputStreamRef = CFReadStreamCreateWithFile(kCFAllocatorDefault,
                                                    (__bridge CFURLRef)self.url);
    }else {
        //TODO:does this suit for every senerio?
//        CFStreamCreatePairWithSocketToHost(NULL,
//                                           (__bridge CFStringRef)self.url.absoluteString,
//                                           80,
//                                           &inputStreamRef,
//                                           NULL);
        
        CFHTTPMessageRef message = CFHTTPMessageCreateRequest(NULL,
                                                              (CFStringRef)@"GET",
                                                              (__bridge CFURLRef)self.url,
                                                              kCFHTTPVersion1_1);
        
        CFHTTPMessageSetHeaderFieldValue(message, CFSTR("Accept"), CFSTR("*/*"));
        CFHTTPMessageSetHeaderFieldValue(message, CFSTR("Ice-MetaData"), CFSTR("0"));
        
        //TODO:replace CFReadStreamCreateForHTTPRequest with NSURLSession
        inputStreamRef = CFReadStreamCreateForHTTPRequest(NULL,
                                                          message);
    }
    self.inputStream = (__bridge_transfer NSInputStream *)inputStreamRef;
    
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
                    self.state = kLXAudioPlayerStateError;
                });
}

- (void)destroyAudioFileStreamService {
    handleError(AudioFileStreamClose(_audioFileStream),
                "AudioFileStreamClose failed",
                ^{
                    self.state = kLXAudioPlayerStateError;
                });
}

- (void)setupAudioConverterWithSourceFormat:(AudioStreamBasicDescription *)sourceFormat {
    AudioStreamBasicDescription streamFormat = self.canonicalFormat;
    AudioConverterRef audioConverter;
    AudioConverterNew(sourceFormat,
                      &streamFormat,
                      &audioConverter);
    self.audioConverter = audioConverter;
    self.inputFormat = *sourceFormat;
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
                                                          seconds:10.0];
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
                    self.state = kLXAudioPlayerStateError;
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
                    self.state = kLXAudioPlayerStateError;
                });
    handleError(AUGraphOpen(_graph),
                "open graph failed",
                ^{
                    self.state = kLXAudioPlayerStateError;
                });
    handleError(AUGraphNodeInfo(_graph,
                                remoteIONode,
                                NULL,
                                &_remoteIOUnit),
                "AUGraphNodeInfo failed",
                ^{
                    self.state = kLXAudioPlayerStateError;
                });
    
    handleError(AudioUnitSetProperty(_remoteIOUnit,
                                     kAudioUnitProperty_StreamFormat,
                                     kAudioUnitScope_Input,
                                     0,
                                     &_canonicalFormat,
                                     sizeof(_canonicalFormat)),
                "unable to set stream format of remoteIO unit",
                ^{
                    self.state = kLXAudioPlayerStateError;
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
                    self.state = kLXAudioPlayerStateError;
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
                    self.state = kLXAudioPlayerStateError;
                });
    
    handleError(AUGraphInitialize(_graph),
                "initialize graph failed",
                ^{
                    self.state = kLXAudioPlayerStateError;
                });
    self.state = kLXAudioPlayerStateReady;
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

- (void)getFileSize {
    //if url begin with "file:",then it's a local file
    if ([self isLocalFile]) {
        NSString *filePath = [self.url path];
        NSFileManager *manager = [NSFileManager defaultManager];
        NSError *error;
        NSDictionary *attributes = [manager attributesOfItemAtPath:filePath
                                                             error:&error];
        if (!error) {
            NSNumber* size = [attributes objectForKey:@"NSFileSize"];
            if (size) {
                self.fileSize = size.floatValue;
                [self calculateDuration];
            }
        }
    }
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
                                                  selector:@selector(startPlaybackThread)
                                                    object:nil];
    [self.playbackThread start];
}

- (void)startPlaybackThread {
    self.playbackRunLoop = [NSRunLoop currentRunLoop];
    
    [self.playbackThreadRunningLock lockWhenCondition:0];
    [self.playbackThreadRunningLock unlockWithCondition:1];
    
    [self.playbackRunLoop addPort:[NSPort port] forMode:NSDefaultRunLoopMode];
    //TODO:stop run loop at a proper time
    [self.playbackRunLoop run];
}

- (void)calculateDuration {
    //TODO:check for PCM, CBR and VBR
    if (self.duration>0&&self.durationIsAccurate) {
        return;
    }
    
    if (self.bitRate==0&&self.packetDuration>0&&self.processedPacketCount>0) {
        self.bitRate = (self.processedPacketTotalSize/self.processedPacketCount)/self.packetDuration*8.0;
    }
    float dataByteCount = 0;
    if (self.dataByteCount>0) {
        dataByteCount = self.dataByteCount;
    }
    
    if (self.fileSize>0&&self.dataOffset>0) {
        dataByteCount = self.fileSize - self.dataOffset;
    }
    
    if (dataByteCount==0 || self.bitRate==0) {
        return;
    }
    
    NSTimeInterval newDuration = dataByteCount/(self.bitRate/8.0);
    if (self.duration!=newDuration) {
        self.duration = newDuration;
        if ([self.delegate respondsToSelector:@selector(didUpdateDuration:)]) {
            [self.delegate didUpdateDuration:self.duration];
        }
    }
}

- (void)setState:(LXAudioPlayerState)state {
    if (_state != state) {
        _state = state;
        if ([self.delegate respondsToSelector:@selector(didUpdateState:)]) {
            self.isPlaying = (state==kLXAudioPlayerStatePlaying);
            [self.delegate didUpdateState:state];
        }
        
        if (state==kLXAudioPlayerStateError) {
            [self cleanup];
        }
    }
}

- (void) cleanup {
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
                        
                        self.AudioFileStreamIsWaitingForSpace = YES;
                        pthread_cond_wait(&ringBufferFilledCondition, &ringBufferMutex);
                        self.AudioFileStreamIsWaitingForSpace = NO;
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
            LXLog(@"stream event error:%@",self.inputStream.streamError);
            self.state = kLXAudioPlayerStateError;
            break;
        }
        case NSStreamEventEndEncountered:{
            LXLog(@"stream event end");
            //TODO:tell self that stream end encountered.
            break;
        }
        default:
            break;
    }
}

@end