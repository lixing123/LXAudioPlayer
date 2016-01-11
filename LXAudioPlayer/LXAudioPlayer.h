//
//  LXAudioPlayer.h
//  LXAudioPlayer
//
//  Created by 李 行 on 16/1/11.
//  Copyright © 2016年 lixing123.com. All rights reserved.
//

#import <Foundation/Foundation.h>

//TODO: the LXAudioPLayerDelegate
//notificaitons: player started, paused, ended, errored, buffering...

@interface LXAudioPlayer : NSObject

//the url of the audio data, for both local and remote audio
@property(readonly) NSURL *url;
//a boolean value that indicates whether the audio is playing
@property(readonly) BOOL isPlaying;
//duration of the audio
@property(readonly) float duration;
//the playback volume of the audio player, ranging from 0.0 to 1.0
@property(readonly) float volume;
//the number of channels
@property(readonly) NSUInteger numberOfChannels;
//the playback position, in seconds
@property(readonly) NSTimeInterval currentTime;

- (id)initWithURL:(NSURL *)url;

- (void)play;
- (void)pause;
- (void)stop;
- (void)seekToTime:(float)seekTime;

//if enable cache, the audio data will be saved to local file; Next time play the same file, player will first play the cached data
//-(void) enableCache:(BOOL)cacheEnabled;

//if set, the audio data will be saved to the local file url
- (void)setCacheURL:(NSURL *)cacheURL;

@end
