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

@interface ViewController ()

@property(nonatomic,strong)LXAudioPlayer *lxPlayer;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    [self setupSession];
    
    UIButton *playButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [playButton setFrame:CGRectMake(100, 10, 100, 25)];
    [playButton setTitle:@"Play"
                forState:UIControlStateNormal];
    [playButton addTarget:self
                   action:@selector(play)
         forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:playButton];
    
    UIButton *pauseButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [pauseButton setFrame:CGRectMake(100, 110, 100, 25)];
    [pauseButton setTitle:@"Pause"
                forState:UIControlStateNormal];
    [pauseButton addTarget:self
                    action:@selector(pause:)
         forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:pauseButton];
    
    UIButton *stopButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
    [stopButton setFrame:CGRectMake(100, 210, 100, 25)];
    [stopButton setTitle:@"Stop"
                forState:UIControlStateNormal];
    [stopButton addTarget:self
                   action:@selector(stop)
         forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:stopButton];
}

- (void)play {
    NSString *fileString = [[NSBundle mainBundle] pathForResource:@"test" ofType:@"mp3"];
    NSURL *url = [[NSURL alloc] initFileURLWithPath:fileString];
    //the lxPlayer must be of a global variable, or it'll be released before playing.
    self.lxPlayer = [[LXAudioPlayer alloc] initWithURL:url];
    [self.lxPlayer play];
}

- (void)pause:(UIButton *)button {
    if ([button.titleLabel.text isEqualToString:@"Pause"]) {
        //[self.lxPlayer pause];
        [button setTitle:@"Resume" forState:UIControlStateNormal];
    }else {
        //[self.lxPlayer resume];
        [button setTitle:@"Pause" forState:UIControlStateNormal];
    }
    
}

- (void)stop {
    [self.lxPlayer stop];
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

@end
