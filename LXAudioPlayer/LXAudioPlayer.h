//
//  LXAudioPlayer.h
//  LXAudioPlayer
//
//  Created by 李 行 on 16/1/11.
//  Copyright © 2016年 lixing123.com. All rights reserved.
//

#import <Foundation/Foundation.h>

//playing state
typedef UInt32 LXAudioPlayerState;

CF_ENUM(LXAudioPlayerState) {
    kLXAudioPlayerStateReady       = 1,
    kLXAudioPlayerStatePlaying     = 2,
    kLXAudioPlayerStateBuffering   = 3,
    kLXAudioPlayerStatePaused      = 4,
    kLXAudioPlayerStateStopped     = 5,
    kLXAudioPlayerStateError       = 6,
};

//TODO:set error type

@protocol LXAudioPlayerDelegate <NSObject>

//the duration is updated
//note:duration may change at runtime
- (void)didUpdateDuration:(float)newDuration;
//player did update playing state
- (void)didUpdateState:(LXAudioPlayerState)state;

//TODO:when getting stream format, notify the delegate; for example, number of channels

@end

@interface LXAudioPlayer : NSObject

//the url of the audio data, for both local and remote audio
@property(readonly)NSURL *url;
//a boolean value that indicates whether the audio is playing
@property(readonly)BOOL isPlaying;
//duration of the audio
//TODO:update this property at proper time
@property(readonly)NSTimeInterval duration;
//the playback volume of the audio player, ranging from 0.0 to 1.0
//TODO:calculate volume
@property(readonly)float volume;
//number of channels
@property(readonly)NSUInteger numberOfChannels;
//playback position, in seconds
@property(readonly)NSTimeInterval progress;
//playing state
@property(nonatomic,readonly)LXAudioPlayerState state;
@property(nonatomic,weak)id<LXAudioPlayerDelegate>delegate;

- (id)initWithURL:(NSURL *)url delegate:(id<LXAudioPlayerDelegate>)delegate;

- (void)play;
- (void)pause;
- (void)stop;
- (NSTimeInterval)seekToTime:(NSTimeInterval)seekTime;

//if enable cache, the audio data will be saved to local file; Next time play the same file, player will first play the cached data
//-(void) enableCache:(BOOL)cacheEnabled;

//if set, the audio data will be saved to the local file url
- (void)setCacheURL:(NSURL *)cacheURL;

@end
