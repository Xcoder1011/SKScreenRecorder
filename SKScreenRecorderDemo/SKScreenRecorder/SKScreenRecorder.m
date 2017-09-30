//
//  SKScreenRecorder.m
//  SKScreenRecorderDemo
//
//  Created by KUN on 2017/9/30.
//  Copyright © 2017年 lemon. All rights reserved.
//

#import "SKScreenRecorder.h"
#import <AVFoundation/AVFoundation.h>
#import <ReplayKit/ReplayKit.h>

@interface SKScreenRecorder () <RPScreenRecorderDelegate,RPPreviewViewControllerDelegate>
{
    BOOL _usingReplayKit;
    
    BOOL            _writing;
    float           _spaceDate;     // 秒   这个变量一直为0，
    NSDate          *startedAt;     // 录制的开始时间
    CGContextRef    context;        // 绘制layer的context
    NSTimer         *timer;
}

@property (nonatomic, getter=isRecording , readwrite)  BOOL recording;
@property (nonatomic , strong ) NSURL *videOutputUrl;
@property (nonatomic, assign ) NSUInteger frameRate;
@property (nonatomic, strong) dispatch_queue_t sessionQueue;

/**
 *  ReplayKit
 */
@property (nonatomic, strong) RPScreenRecorder *rpRecorder;

/**
 *  刻录机
 */
@property (nonatomic, strong) AVAssetWriter *videoWriter;
@property (nonatomic, strong) AVAssetWriterInput *videoAssetWriterInput;
@property (nonatomic, strong) AVAssetWriterInput *audioAssetWriterInput;
@property (nonatomic, strong) AVAssetWriterInputPixelBufferAdaptor *pixelBufferAdaptor;  //缓冲区

@end

@implementation SKScreenRecorder

+ (SKScreenRecorder *)sharedInstance {
    
    static SKScreenRecorder *recorder = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        recorder = [[SKScreenRecorder alloc] init];
        recorder.frameRate = 10;
    });
    return recorder;
}

/**
 * iOS9.0 使用ReplayKi
 */
- (void)sk_startRecordingWithReplayKit {
    
    _usingReplayKit = YES;
    self.rpRecorder = [RPScreenRecorder sharedRecorder];
    self.rpRecorder.delegate = self;
    [self.rpRecorder setMicrophoneEnabled:YES];
    [self.rpRecorder startRecordingWithHandler:^(NSError * _Nullable error) {
        if (error) {
            NSLog(@"错误信息 %@", error);
        } else {
            NSLog(@"录制开始");
        }
        NSLog(@"error = %@",error);
    }];
}


/**
 * 普通的刻录机方式( AssetWriter )
 */
- (void)sk_startRecordingWithCapture {
    
    @synchronized (self) {
        _usingReplayKit = NO;
        _sessionQueue = dispatch_queue_create("com.skcamera.sessionQueue", nil);
        dispatch_queue_set_specific(_sessionQueue, "SKCameraRecordSessionQueue", "true", nil);
        dispatch_set_target_queue(_sessionQueue, dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_HIGH, 0));
        
        if (!self.isRecording) {
            self.recording = YES;
            NSLog(@"开始录制。。。");
            
            NSLog(@"start record");
            
            startedAt   = [NSDate date];
            _writing    = NO;
            _spaceDate  = 0;
            
            timer = [NSTimer scheduledTimerWithTimeInterval:1.0/self.frameRate target:self selector:@selector(drawFrame) userInfo:nil repeats:YES];
            // 加入主循环池中
            [[NSRunLoop mainRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
        }
    }
}

- (void)drawFrame
{
    if (!_writing) {
        [self performSelector:@selector(getFrame) withObject:nil];
    }
}

- (void)getFrame
{
    if (!_writing) {
        
        _writing = YES;
        
        
        /*
         *
         *
         size_t width = CGBitmapContextGetWidth(context);
         size_t height = CGBitmapContextGetHeight(context);
         
         CGContextClearRect(context, CGRectMake(0, 0, width, height));//将显示区域填充为透明背景
         [[[UIApplication sharedApplication].delegate window] drawViewHierarchyInRect:[[UIApplication sharedApplication].delegate window].bounds afterScreenUpdates:NO];
         UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
         CGImageRef cgImage = image.CGImage;
         
         */
        
        CGImageRef cgImage = [self getDeviceScreenImageRef];
        
        
        if (self.isRecording) {
            float millisElapsed = [[NSDate date] timeIntervalSinceDate:startedAt] * 1000.0-_spaceDate*1000.0;
            [self writeVideoFrameAtTime:CMTimeMake((int)millisElapsed, 1000) addImage:cgImage];
        }
        // CGImageRelease(cgImage);
        _writing = NO;
    }
}

- (CGImageRef)getDeviceScreenImageRef {
    
    size_t width = CGBitmapContextGetWidth(context);
    size_t height = CGBitmapContextGetHeight(context);
    
    if ([[UIScreen mainScreen] respondsToSelector:@selector(scale)]){
        UIGraphicsBeginImageContextWithOptions(CGSizeMake(width, height), NO, [UIScreen mainScreen].scale);
    } else {
        UIGraphicsBeginImageContext(CGSizeMake(width, height));
    }
    [[[UIApplication sharedApplication].delegate window].layer renderInContext:UIGraphicsGetCurrentContext()];
    UIImage *screenImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    CGRect rect = CGRectMake(0, 0, width, height);
    CGImageRef newImageRef = CGImageCreateWithImageInRect(screenImage.CGImage, rect);
    UIImage *newImage = [UIImage imageWithCGImage:newImageRef];
    CGImageRelease(newImageRef);
    return newImage.CGImage;
}


-(void) writeVideoFrameAtTime:(CMTime)time addImage:(CGImageRef )newImage
{
    //视频输入是否准备接受更多的媒体数据
    if (![self.videoAssetWriterInput isReadyForMoreMediaData]) {
        NSLog(@"Not ready for video data");
        if (timer) {
            [timer invalidate];
            timer = nil;
        }
    } else {
        
        @synchronized (self) {
            
            CVPixelBufferRef buffer = [self pixelBufferFromCGImage:newImage]; // cpu 15
            if (buffer) {
                if(![self.pixelBufferAdaptor appendPixelBuffer:buffer withPresentationTime:time]) {
                    NSLog(@"Warning:  Unable to write buffer to video");
                } else {
                    CFRelease(buffer);
                }
            }
            
            /*
             
             CVPixelBufferRef pixelBuffer = NULL;
             CGImageRef cgImage = CGImageCreateCopy(newImage);
             CFDataRef image = CGDataProviderCopyData(CGImageGetDataProvider(cgImage));
             
             int status = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, self.pixelBufferAdaptor.pixelBufferPool, &pixelBuffer);
             if(status != 0){
             NSLog(@"Error creating pixel buffer:  status=%d", status);
             }
             CVPixelBufferLockBaseAddress( pixelBuffer, 0 );
             uint8_t* destPixels = CVPixelBufferGetBaseAddress(pixelBuffer);
             CFDataGetBytes(image, CFRangeMake(0, CFDataGetLength(image)), destPixels);
             
             if(status == 0) {
             BOOL success = [self.pixelBufferAdaptor appendPixelBuffer:pixelBuffer withPresentationTime:time];
             if (!success)
             NSLog(@"Warning:  Unable to write buffer to video");
             }
             //clean up
             CVPixelBufferUnlockBaseAddress( pixelBuffer, 0 );
             CVPixelBufferRelease( pixelBuffer );
             CFRelease(image);
             CGImageRelease(cgImage);
             
             */
        }
        
    }
}


- (CVPixelBufferRef)pixelBufferFromCGImage:(CGImageRef)image{
    
    NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys:
                             [NSNumber numberWithBool:YES], kCVPixelBufferCGImageCompatibilityKey,
                             [NSNumber numberWithBool:YES], kCVPixelBufferCGBitmapContextCompatibilityKey,
                             nil];
    
    CVPixelBufferRef pxbuffer = NULL;
    // 获取图片的大小
    CGFloat frameWidth = CGImageGetWidth(image);
    CGFloat frameHeight = CGImageGetHeight(image);
    // 转流设置
    CVReturn status = CVPixelBufferCreate(kCFAllocatorDefault,
                                          frameWidth,
                                          frameHeight,
                                          kCVPixelFormatType_32ARGB,
                                          (__bridge CFDictionaryRef) options,
                                          &pxbuffer);
    
    NSParameterAssert(status == kCVReturnSuccess && pxbuffer != NULL);
    
    CVPixelBufferLockBaseAddress(pxbuffer, 0);
    void *pxdata = CVPixelBufferGetBaseAddress(pxbuffer);
    NSParameterAssert(pxdata != NULL);
    
    CGColorSpaceRef rgbColorSpace = CGColorSpaceCreateDeviceRGB();
    
    CGContextRef context = CGBitmapContextCreate(pxdata,
                                                 frameWidth,
                                                 frameHeight,
                                                 8,
                                                 CVPixelBufferGetBytesPerRow(pxbuffer),
                                                 rgbColorSpace,
                                                 (CGBitmapInfo)kCGImageAlphaNoneSkipFirst);
    NSParameterAssert(context);
    CGContextConcatCTM(context, CGAffineTransformIdentity);
    CGContextDrawImage(context, CGRectMake(0,
                                           0,
                                           frameWidth,
                                           frameHeight),
                       image);
    CGColorSpaceRelease(rgbColorSpace);
    CGContextRelease(context);
    
    CVPixelBufferUnlockBaseAddress(pxbuffer, 0);
    
    return pxbuffer;
}


/**
 *  开始录制视频
 *  推荐, 自动判断系统版本
 */
- (void)sk_startRecording {
    
    if (NSClassFromString(@"RPScreenRecorder") != nil)
    {
        if ([[RPScreenRecorder sharedRecorder] isAvailable]) {
            NSLog(@"支持ReplayKit录制! ");
            [self sk_startRecordingWithReplayKit];
        } else {
            NSLog(@"不支持ReplayKit录制! ");
            [self sk_startRecordingWithCapture];
        }
    }
    else
    {
        [self sk_startRecordingWithCapture];
    }
}

/**
 * 暂停录制视频
 */
- (void)sk_pauseRecording {
    
    
}

/**
 * 继续录制视频
 */
- (void)sk_resumeRecording {
    
}

/**
 * 停止录制视频
 */
- (void)sk_stopRecording {
    
    if (_usingReplayKit) {
        
        [self.rpRecorder stopRecordingWithHandler:^(RPPreviewViewController * _Nullable previewViewController, NSError * _Nullable error) {
            //
            if (error) {
                NSLog(@"错误信息 %@", error);
            } else {
                NSLog(@"停止成功");
                previewViewController.previewControllerDelegate = self;
            }
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if (self.replayKitDidRecordCompletionBlock ) {
                    self.replayKitDidRecordCompletionBlock(previewViewController, error);
                }
            });
        }];
        
    } else { // 原始截图
        
        @synchronized (self) {
            if (self.isRecording) {
                self.recording = NO;
                NSLog(@"停止录制。。。");
                dispatch_async(_sessionQueue, ^{
                    
                    if (self.videoWriter) {
                        
                        [self.videoAssetWriterInput markAsFinished];
                        // wait for the video
                        int status = self.videoWriter.status;
                        while (status == AVAssetWriterStatusUnknown)
                        {
                            NSLog(@"Waiting...");
                            [NSThread sleepForTimeInterval:0.5f];
                            status = self.videoWriter.status;
                        }
                        
                        [self.videoWriter finishWritingWithCompletionHandler:^{
                            
                            dispatch_async(dispatch_get_main_queue(), ^{
                                
                                if (timer) {
                                    [timer invalidate];
                                    timer = nil;
                                }
                                NSLog(@"stop record");
                                if(self.didRecordCompletionBlock) {
                                    self.didRecordCompletionBlock(self, self.videoWriter.outputURL, nil);
                                    
                                    self.videoWriter = nil;
                                    self.pixelBufferAdaptor = nil;
                                    self.videoAssetWriterInput = nil;
                                    self.audioAssetWriterInput = nil;
                                    startedAt = nil;
                                }
                            });
                        }];
                    }
                });
                
            }
        }
        
    }
}


/*
 * 设置录制视频 相关信息
 *
 * @param url   视频输出的url
 * @param url   一秒钟录制几帧图像 , default 10
 */
- (void)setupRecordingConfigWithOutputUrl:(NSURL *)url  frameRate:(NSUInteger)frameRate {
    
    _videOutputUrl = url;
    _frameRate = frameRate;
    
    unlink([[_videOutputUrl path] UTF8String]);
    
    CGSize tmpsize = [UIScreen mainScreen].bounds.size;
    float scaleFactor = [[UIScreen mainScreen] scale];
    CGSize size = CGSizeMake(tmpsize.width*scaleFactor, tmpsize.height*scaleFactor);
    NSError *error = nil;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if ([fileManager fileExistsAtPath:[_videOutputUrl path]]) {
        
        if ([fileManager removeItemAtPath:[_videOutputUrl path] error:&error] == NO) {
            NSLog(@"Could not delete old recording file at path:  %@", [_videOutputUrl path]);
            return ;
        }
    }
    [self createWriter:_videOutputUrl cropSize:size];
}


- (void)createWriter:(NSURL *)assetUrl  cropSize:(CGSize)cropSize {
    
#if defined(__LP64__) && __LP64__
    
    NSLog(@"设备是64位");
#else
    NSLog(@"设备是32位");
#endif
    
    
    NSError *error = nil;
    self.videoWriter = [AVAssetWriter assetWriterWithURL:assetUrl fileType:AVFileTypeMPEG4 error:&error];
    NSParameterAssert(self.videoWriter);
    //使其更适合在网络上播放
    self.videoWriter.shouldOptimizeForNetworkUse = YES;
    
    int videoWidth = cropSize.width;
    int videoHeight =cropSize.height;
    
    NSDictionary* videoCompressionProps = [NSDictionary dictionaryWithObjectsAndKeys:
                                           [NSNumber numberWithDouble:videoWidth * videoHeight], AVVideoAverageBitRateKey,//视频尺寸*比率，相当于AVCaptureSessionPresetHigh，数值越大，显示越精细
                                           nil ];
    
    NSDictionary *outputSettings = @{
                                     AVVideoCodecKey : AVVideoCodecH264,
                                     AVVideoWidthKey : @(videoWidth),
                                     AVVideoHeightKey : @(videoHeight),
                                     AVVideoCompressionPropertiesKey:videoCompressionProps
                                     }; //  AVVideoScalingModeKey:AVVideoScalingModeResizeAspectFill,
    
    self.videoAssetWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:outputSettings];
    NSParameterAssert(self.videoAssetWriterInput);
    
    // 表明输入是否应该调整其处理为实时数据源的数据
    self.videoAssetWriterInput.expectsMediaDataInRealTime = YES;
    
    /**
     * 如果使用 CGAffineTransformMakeRotation(M_PI / 2.0) ， 则对应的 videoWidth = 720，videoHeight = 1280
     */
    //    self.videoAssetWriterInput.transform = CGAffineTransformMakeRotation(M_PI / 2.0);  //
    
    
    //    NSDictionary *audioOutputSettings = @{
    //                                          AVFormatIDKey:@(kAudioFormatMPEG4AAC),
    //                                          AVEncoderBitRateKey:@(64000),
    //                                          AVSampleRateKey:@(44100),
    //                                          AVNumberOfChannelsKey:@(1),
    //                                          };
    //
    //    self.audioAssetWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:audioOutputSettings];
    //    self.audioAssetWriterInput.expectsMediaDataInRealTime = YES;
    
    
    NSDictionary *SPBADictionary = @{
                                     (__bridge NSString *)kCVPixelBufferPixelFormatTypeKey : @(kCVPixelFormatType_32BGRA),
                                     (__bridge NSString *)kCVPixelBufferWidthKey : @(videoWidth),
                                     (__bridge NSString *)kCVPixelBufferHeightKey  : @(videoHeight),
                                     (__bridge NSString *)kCVPixelFormatOpenGLESCompatibility : ((__bridge NSNumber *)kCFBooleanTrue)
                                     };
    
    
    self.pixelBufferAdaptor = [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:self.videoAssetWriterInput sourcePixelBufferAttributes:SPBADictionary];
    
    if ([self.videoWriter canAddInput:self.videoAssetWriterInput]) {
        [self.videoWriter addInput:self.videoAssetWriterInput];
    }else {
        if (error == nil) {
            //            error = [SKScreenRecorder createError:@"Cannot add videoAssetWriterInput inside videoWriter" code:SKCameraErrorCodeVideoNotEnabled];
            //            [self passError:error];
        }
    }
    //    if ([self.videoWriter canAddInput:self.audioAssetWriterInput]) {
    //        [self.videoWriter addInput:self.audioAssetWriterInput];
    //    }else {
    //        if (error == nil) {
    ////            error = [SKScreenRecorder createError:@"Cannot add audioAssetWriterInput inside videoWriter" code:SKCameraErrorCodeVideoNotEnabled];
    ////            [self passError:error];
    //        }
    //    }
    
    [self.videoWriter startWriting];
    [self.videoWriter startSessionAtSourceTime:CMTimeMake(0, 1000)];
    
    //create context
    if (context== NULL)
    {
        UIGraphicsBeginImageContextWithOptions([[UIApplication sharedApplication].delegate window].bounds.size, YES, 0);
        context = UIGraphicsGetCurrentContext();
    }
    if (context== NULL)
    {
        fprintf (stderr, "Context not created!");
        //        error = [SKScreenRecorder createError:@"Cannot add audioAssetWriterInput inside videoWriter" code:SKCameraErrorCodeVideoNotEnabled];
        //        [self passError:error];
    }
}


#pragma mark -- RPPreviewViewControllerDelegate

- (void)previewController:(RPPreviewViewController *)previewController didFinishWithActivityTypes:(NSSet <NSString *> *)activityTypes {
    if ([activityTypes containsObject:@"com.apple.UIKit.activity.SaveToCameraRoll"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"保存成功");
        });
    }
    if ([activityTypes containsObject:@"com.apple.UIKit.activity.CopyToPasteboard"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            NSLog(@"复制成功");
        });
    }
}

- (void)previewControllerDidFinish:(RPPreviewViewController *)previewController {
    
    NSLog(@"previewControllerDidFinish");
    [previewController dismissViewControllerAnimated:YES completion:^{
    }];
}

#pragma mark -- RPScreenRecorderDelegate

- (void)screenRecorder:(RPScreenRecorder *)screenRecorder didStopRecordingWithError:(NSError *)error previewViewController:(nullable RPPreviewViewController *)previewViewController {
    
    NSLog(@"didStopRecordingWithError error = %@",error);
}

- (void)screenRecorderDidChangeAvailability:(RPScreenRecorder *)screenRecorder {
    
    NSLog(@"screenRecorderDidChangeAvailability = %d",screenRecorder.available);
    
}

@end
