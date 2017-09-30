//
//  SKScreenRecorder.h
//  SKScreenRecorderDemo
//
//  Created by KUN on 2017/9/30.
//  Copyright © 2017年 lemon. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

@interface SKScreenRecorder : NSObject

+ (SKScreenRecorder *)sharedInstance;

@property (nonatomic, getter=isRecording , readonly)  BOOL recording; // 是否正在录制

/**
 * 录视频完成回调
 */
@property (nonatomic, copy) void (^didRecordCompletionBlock)(SKScreenRecorder *recorder, NSURL *outputFileUrl, NSError *error);


/**
 * ReplayKit录视频完成回调
 */
@property (nonatomic, copy) void (^replayKitDidRecordCompletionBlock)(UIViewController *previewViewController, NSError *error);


/**
 * 各种错误回调
 */
@property (nonatomic, copy) void (^onError)(SKScreenRecorder *recorder, NSError *error);


/**
 *  1.  iOS9.0 使用ReplayKit ,videOutputUrl不可设置
 */
- (void)sk_startRecordingWithReplayKit;


/**
 * 2.  普通的刻录机方式( AssetWriter )
 */
- (void)sk_startRecordingWithCapture;

/*
 * 设置录制视频 相关信息
 *
 * @param url   视频输出的url
 * @param url   一秒钟录制几帧图像 , default 10
 */
- (void)setupRecordingConfigWithOutputUrl:(NSURL *)url  frameRate:(NSUInteger)frameRate;


/**
 * 暂停录制视频
 */
- (void)sk_pauseRecording;

/**
 * 继续录制视频
 */
- (void)sk_resumeRecording;

/**
 * 停止录制视频
 */
- (void)sk_stopRecording;

@end
