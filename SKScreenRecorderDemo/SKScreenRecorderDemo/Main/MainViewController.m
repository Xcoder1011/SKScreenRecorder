//
//  MainViewController.m
//  SKScreenRecorderDemo
//
//  Created by KUN on 2017/9/30.
//  Copyright © 2017年 lemon. All rights reserved.
//

#import "MainViewController.h"
#import "SKScreenRecorder.h"
@import Photos;

@interface MainViewController ()

// 计时器
@property (weak, nonatomic) IBOutlet UILabel *countingLabel;

@end

@implementation MainViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self.navigationController setNavigationBarHidden:YES];
    NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:1.0 target:self selector:@selector(timerRun) userInfo:nil repeats:YES];
    [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSRunLoopCommonModes];
    [timer fire];
}

- (void)timerRun {
    
    static NSInteger index = 1;
    
    [self.countingLabel setText:[NSString stringWithFormat:@"%ld",index]];
    
    index ++;
}


// 开始录制
- (IBAction)startRecordAct:(UIButton *)sender {
    
    [self startRecordScreen];
}

// 停止录制
- (IBAction)stopRecordAct:(UIButton *)sender {
    
    [self stopRecordScreen];
}

#pragma mark -- 录制屏幕

- (void)startRecordScreen {
    
    [[SKScreenRecorder sharedInstance] setupRecordingConfigWithOutputUrl:OutputUrl() frameRate:35];
    
    [SKScreenRecorder sharedInstance].didRecordCompletionBlock = ^(SKScreenRecorder *recorder, NSURL *outputFileUrl, NSError *error) {
        
        [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
            
            [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:outputFileUrl];
            
        } completionHandler:^(BOOL success, NSError * _Nullable error) {
            
            dispatch_async(dispatch_get_main_queue(), ^{
                if (success) {
                    NSLog(@"保存成功");
                    
                } else {
                    NSLog(@"保存失败");
                }
            });
        }];
    };
    
    [[SKScreenRecorder sharedInstance] sk_startRecordingWithCapture];
}

- (void)stopRecordScreen {
    
    [[SKScreenRecorder sharedInstance] sk_stopRecording];
}

static inline NSURL * OutputUrl() {
    
    NSString *tempDocuments = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) objectAtIndex:0];
    NSString *tempVideoPath= [NSString stringWithFormat:@"%@/SKScreenRecorder", tempDocuments];
    if (![[NSFileManager defaultManager] fileExistsAtPath:tempVideoPath]) {
        [[NSFileManager defaultManager] createDirectoryAtPath:tempVideoPath withIntermediateDirectories:YES attributes:nil error:nil];
    }
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"YYYY-MM-DD-HH:mm:ss"];
    NSString *dateTime = [formatter stringFromDate:[NSDate date]];
    
    NSString *fileName = [NSString stringWithFormat:@"Documents/SKScreenRecorder/%@test.mp4",dateTime];
    NSString *pathFirstToMovie = [NSHomeDirectory() stringByAppendingPathComponent:fileName];
    
    return [NSURL fileURLWithPath:pathFirstToMovie];
}

@end
