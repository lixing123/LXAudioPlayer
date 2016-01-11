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

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    [self setupSession];
    
    NSString *fileString = [[NSBundle mainBundle] pathForResource:@"test" ofType:@"mp3"];
    LXAudioPlayer *lxPlayer = [[LXAudioPlayer alloc] initWithURL:[NSURL URLWithString:fileString]];
    [lxPlayer play];
}

- (void)setupSession {
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setCategory:AVAudioSessionCategoryPlayAndRecord
                   error:nil];
    [session requestRecordPermission:^(BOOL granted) {
    }];
    [session setActive:YES
                 error:nil];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end
