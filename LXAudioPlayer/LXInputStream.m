//
//  LXInputStream.m
//  LXAudioPlayer
//
//  Created by 李 行 on 16/1/22.
//  Copyright © 2016年 lixing123.com. All rights reserved.
//

#import "LXInputStream.h"
#import <AudioToolbox/AudioToolbox.h>
#import "LXHeader.h"

@interface LXInputStream ()<NSStreamDelegate>

@property(nonatomic)NSInputStream *inputStream;
@property(nonatomic)id<LXInputStreamDelegate>delegate;

@end

@implementation LXInputStream

- (id)initWithURL:(NSURL *)url delegate:(id<LXInputStreamDelegate>)aDelegate {
    if (self=[super init]) {
        self.inputStream = [[NSInputStream alloc] initWithURL:url];
        [self.inputStream setDelegate:self];
        [self.inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop]
                                    forMode:NSDefaultRunLoopMode];
        [self.inputStream open];
        self.delegate = aDelegate;
    }
    
    return self;
}

- (void)pause {
    
}

- (void)resume {
    
}

#pragma mark - NSStreamDelegate

- (void)stream:(NSStream *)aStream handleEvent:(NSStreamEvent)eventCode {
    NSInputStream *aInputStream = (NSInputStream *)aStream;
    NSLog(@"event code:%d",(int)eventCode);
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
            //TODO:compare this method with blocking thread
            //if ([self.ringBuffer needToBeFilled]) {
            if (self.inputStream.hasBytesAvailable) {
                //TODO:figure out buffer size
                UInt32 bufferSize = 1024;
                UInt8 *inputBuffer = calloc(sizeof(UInt8)*bufferSize, 1);
                NSInteger readLength;
                
                readLength = [aInputStream read:inputBuffer
                                      maxLength:bufferSize];
                
//                AudioFileStreamParseBytes(self.audioFileStream,
//                                          (UInt32)readLength,
//                                          inputBuffer,
//                                          0);
            }
            break;
        }
        case NSStreamEventErrorOccurred:{
            LXLog(@"stream event error");
            break;
        }
        case NSStreamEventEndEncountered:{
            LXLog(@"stream event end");
            break;
        }
        default:
            break;
    }
}

@end
