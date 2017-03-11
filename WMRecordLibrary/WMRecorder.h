//
//  WMRecorder.h
//  WMRecorder
//
//  Created by WangMing on 2016/10/12.
//  Copyright © 2016年 WangMing. All rights reserved.
//

#import <AVFoundation/AVCaptureVideoPreviewLayer.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
@class WMRecordConfiguration;
#define videoDuration  @"duration"
#define videoSize @"size"  AVCaptureVideoOrientationLandscapeRight
//AVCaptureVideoOrientationPortrait           = 1,
//AVCaptureVideoOrientationPortraitUpsideDown = 2,
//AVCaptureVideoOrientationLandscapeRight     = 3,
//AVCaptureVideoOrientationLandscapeLeft      = 4,

@class WMRecorder;
@protocol WMVideoRecordDelegate <NSObject>

@optional
-(void)recordVideo:(WMRecorder *)record withProgress:(CGFloat)progress;
-(void)recordVideo:(WMRecorder *)record withBeyondMaxRecordTime:(NSUInteger)recordTime;
-(void)recordVideo:(WMRecorder *)record withRecordError:(NSString *)error;
@end

@interface WMRecorder : NSObject

@property(atomic, assign, readonly) BOOL isCapturing;//正在录制
@property(atomic, assign, readonly) BOOL isPaused;//是否暂停
@property(nonatomic, weak) id <WMVideoRecordDelegate> delegate;
@property(nonatomic, strong) AVCaptureDevice *captureDevice;
-(instancetype)initWithRecordConfiguration:(WMRecordConfiguration *)configuration;

//捕获到的视频呈现的layer
- (AVCaptureVideoPreviewLayer *)previewLayer;
//调整录制的方向
- (void)adjustRecorderOrientation:(AVCaptureVideoOrientation)orientation;
//启动录制功能
- (void)startPreview;
//关闭录制功能
- (void)closePreview;
//开始录制
- (void)startRecording;
//暂停录制
- (void)pauseRecording;
//停止录制
- (void)stopRecordingVideo:(void (^)(UIImage *movieImage,NSDictionary *videoInfo))handler;
//继续录制
- (void)resumeRecording;
//开启闪光灯
- (void)switchFlashLight;
//设置聚焦点  手动聚焦
- (void)setFocusCursorWithPoint:(CGPoint)tapPoint;
//切换前后置摄像头
- (void)switchCamera;
#pragma mark 设置静音
- (void)setMute:(BOOL)bEnable;


@end
