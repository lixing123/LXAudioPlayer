//
//  ViewController.m
//  LXAudioPlayer
//
//  Created by 李 行 on 16/1/11.
//  Copyright © 2016年 lixing123.com. All rights reserved.
//

#import "ViewController.h"
#import "LXAudioPlayer.h"
#import <AVFoundation/AVFoundation.h>

#define Test_LXAudioPlayer

@interface ViewController ()<LXAudioPlayerDelegate>

@property(nonatomic)LXAudioPlayer *lxPlayer;
@property(nonatomic)AVAudioPlayer *player;
@property(nonatomic)UISlider *slider;
@property(nonatomic)UILabel *durationLabel;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    [self setupSession];
    
    NSString *fileString = [[NSBundle mainBundle] pathForResource:@"test" ofType:@"mp3"];
    NSURL *url = [[NSURL alloc] initFileURLWithPath:fileString];
    //TODO:when comes up with this url, duration seems to be wrong; need to be fixed;
//    NSURL *url = [NSURL URLWithString:@"http://www.abstractpath.com/files/audiosamples/sample.mp3"];
    //the lxPlayer must be of a global variable, or it'll be released before playing.
    self.lxPlayer = [[LXAudioPlayer alloc] initWithURL:url delegate:self];
    self.player = [[AVAudioPlayer alloc] initWithContentsOfURL:url
                                                         error:nil];
    
    UIButton *playButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [playButton setFrame:CGRectMake(10, 100, 100, 25)];
    [playButton setTitle:@"Play"
                forState:UIControlStateNormal];
    [playButton addTarget:self
                   action:@selector(play)
         forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:playButton];
    
    UIButton *pauseButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [pauseButton setFrame:CGRectMake(110, 100, 100, 25)];
    [pauseButton setTitle:@"Pause"
                forState:UIControlStateNormal];
    [pauseButton addTarget:self
                    action:@selector(pause:)
         forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:pauseButton];
    
    UIButton *stopButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [stopButton setFrame:CGRectMake(210, 100, 100, 25)];
    [stopButton setTitle:@"Stop"
                forState:UIControlStateNormal];
    [stopButton addTarget:self
                   action:@selector(stop)
         forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:stopButton];
    
    self.slider = [[UISlider alloc] initWithFrame:CGRectMake(10, 150, 300, 20)];
    [self.view addSubview:self.slider];
    self.slider.minimumValue = 0.0;
    self.slider.maximumValue = self.lxPlayer.duration;
    [self.slider addTarget:self
                    action:@selector(slide:) forControlEvents:UIControlEventTouchUpInside];
    
    self.durationLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 180, 320, 30)];
    self.durationLabel.text = @"duration:";
    [self.view addSubview:self.durationLabel];
    
    [NSTimer scheduledTimerWithTimeInterval:1.0
                                     target:self
                                   selector:@selector(updateViews)
                                   userInfo:nil
                                    repeats:YES];
}

- (void)updateViews {
    NSLog(@"progress:%f",self.lxPlayer.progress);
    self.slider.value = self.lxPlayer.progress;
}

- (void)slide:(UISlider *)aSlider {
    [self.lxPlayer seekToTime:aSlider.value];
}

- (void)play {
#ifdef Test_LXAudioPlayer
    [self.lxPlayer play];
#else
    [self.player play];
#endif
}

- (void)pause:(UIButton *)button {
    if ([button.titleLabel.text isEqualToString:@"Pause"]) {
        [button setTitle:@"Resume" forState:UIControlStateNormal];
#ifdef Test_LXAudioPlayer
        [self.lxPlayer pause];
#else
        [self.player pause];
#endif
    }else {
        [button setTitle:@"Pause" forState:UIControlStateNormal];
#ifdef Test_LXAudioPlayer
        [self.lxPlayer play];
#else
        [self.player play];
#endif
    }
    
}

- (void)stop {
#ifdef Test_LXAudioPlayer
    [self.lxPlayer stop];
#else
    [self.player stop];
#endif
}

- (void)setupSession {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayAndRecord
                   error:nil];
    [session requestRecordPermission:^(BOOL granted) {
    }];
    [session overrideOutputAudioPort:AVAudioSessionPortOverrideSpeaker
                               error:nil];
    [session setActive:YES
                 error:nil];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    
}

#pragma mark - LXAudioPlayerDelegate

- (void)didUpdateDuration:(float)newDuration {
    //TODO:sometimes self.property are all nil, fix it
    self.slider.maximumValue = newDuration;
    NSLog(@"duration:%f",newDuration);
    self.durationLabel.text = [NSString stringWithFormat:@"duration:%d:%d",(int)newDuration/60,(int)newDuration%60];
}

- (void)didUpdateState:(LXAudioPlayerState)state {
    switch (state) {
        case kLXAudioPlayerStatePlaying:{
            NSLog(@"kLXAudioPlayerStatePlaying");
            break;
        }
        case kLXAudioPlayerStateReady:{
            NSLog(@"kLXAudioPlayerStateReady");
            break;
        }
        case kLXAudioPlayerStateBuffering:{
            NSLog(@"kLXAudioPlayerStateBuffering");
            break;
        }
        case kLXAudioPlayerStatePaused:{
            NSLog(@"kLXAudioPlayerStatePaused");
            break;
        }
        case kLXAudioPlayerStateStopped:{
            NSLog(@"kLXAudioPlayerStateStopped");
            break;
        }
        case kLXAudioPlayerStateError:{
            NSLog(@"error occured");
            break;
        }
        default:
            break;
    }
}

@end
