//
//  LXHeader.h
//  LXAudioPlayer
//
//  Created by 李 行 on 16/1/14.
//  Copyright © 2016年 lixing123.com. All rights reserved.
//

#ifndef LXHeader_h
#define LXHeader_h

#define DEBUG_MODE

#ifdef DEBUG_MODE
#define LXLog(fmt, ...) NSLog((fmt), ##__VA_ARGS__)
//#define LXLog(fmt, ...) NSLog((@"%s [Line %d] " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__)
#else
#define LXLog(...)
#endif

#endif /* LXHeader_h */
