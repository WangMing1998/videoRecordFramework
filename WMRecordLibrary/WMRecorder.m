//
//  WMRecorder.m
//  WMRecorder
//
//  Created by WangMing on 2016/10/12.
//  Copyright © 2016年 WangMing. All rights reserved.
//

#import <AVFoundation/AVFoundation.h>
#import "WMAssetWriter.h"
#import "WMRecorder.h"
#import <Photos/Photos.h>
#import "WMRecordConfiguration.h"
typedef void(^PropertyChangeBlock)(AVCaptureDevice *captureDevice);

@interface WMRecorder ()<AVCaptureVideoDataOutputSampleBufferDelegate,
                                AVCaptureAudioDataOutputSampleBufferDelegate,
                                UIApplicationDelegate>
{
    CMTime _timeOffset;//录制的偏移CMTime
    CMTime _lastVideo;//记录上一次视频数据文件的CMTime
    CMTime _lastAudio;//记录上一次音频数据文件的CMTime
    
    NSInteger _cx;//视频分辨的宽
    NSInteger _cy;//视频分辨的高
    int _channels;//音频通道
    Float64 _samplerate;//音频采样率
}

@property (strong, nonatomic) AVCaptureSession           *recordSession;//捕获视频的会话
@property (strong, nonatomic) AVCaptureVideoPreviewLayer *previewLayer;//捕获到的视频呈现的layer
@property (strong, nonatomic) AVCaptureDeviceInput       *backCameraInput;//后置摄像头输入
@property (strong, nonatomic) AVCaptureDeviceInput       *frontCameraInput;//前置摄像头输入
@property (strong, nonatomic) AVCaptureDeviceInput       *audioMicInput;//麦克风输入
@property (copy  , nonatomic) dispatch_queue_t           captureQueue;//录制的队列
@property (strong, nonatomic) AVCaptureConnection        *audioConnection;//音频录制连接
@property (strong, nonatomic) AVCaptureConnection        *videoConnection;//视频录制连接
@property (strong, nonatomic) AVCaptureVideoDataOutput   *videoOutput;//视频输出
@property (strong, nonatomic) AVCaptureAudioDataOutput   *audioOutput;//音频输出
@property (nonatomic, assign) NSInteger cx; //视频分辨的宽
@property (nonatomic, assign) NSInteger cy; //视频分辨的高
@property(nonatomic,strong)  WMRecordConfiguration *recordConfiguration;
@property(nonatomic,strong)  NSString *videoName;
@property(nonatomic, strong) NSString *videoSavePath;//视频路径
//录制写入
@property (nonatomic, strong) WMAssetWriter *assetWriter;


//录制状态
@property (atomic, assign) BOOL isCapturing;//正在录制
@property (atomic, assign) BOOL isPaused;//是否暂停
@property (atomic, assign) BOOL isDiscount;//是否中断
@property (nonatomic, assign) BOOL isFront;
@property (atomic, assign) CMTime startTime;//开始录制的时间
@property (atomic, assign) CGFloat currentRecordTime;//当前录制时间
@property (nonatomic,strong) NSString *videoImageName; // 图片保存名称
@property (nonatomic,assign) BOOL isAudioMute;
@property(nonatomic,assign) NSUInteger maxVideoDuration;

@end

@implementation WMRecorder



#pragma mark - Life Cycle

-(instancetype)initWithRecordConfiguration:(WMRecordConfiguration *)configuration
{
    if (self = [super init]) {
        self.recordConfiguration = configuration;

        // 设置录制时间
        if(configuration.videoRecordMaxTime == 0){
            self.maxVideoDuration = 7200;
        }else{
            self.maxVideoDuration = configuration.videoRecordMaxTime;
        }
        [self setupNotification];
    }
    return self;
}

#pragma mark 录制失败,清除缓存
-(void)clearVidepCach:(NSNotification *)notic
{
    if(self.delegate && [self.delegate respondsToSelector:@selector(recordVideo:withRecordError:)])
    {
        [self.delegate recordVideo:self withRecordError:notic.object];
    }
    [self cleanCache];
}

- (void)setupNotification {
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(clearVidepCach:) name:@"writeVideoDataError" object:nil];
}



- (void)setMute:(BOOL)bEnable
{
//    [_recordSession stopRunning];
    self.audioOutput = nil;
    self.audioMicInput = nil;// 必须要先清空。因为有懒加载
    [_recordSession beginConfiguration];
    if(bEnable)
    {
        [_recordSession removeInput:self.audioMicInput];
        [_recordSession removeOutput:self.audioOutput];
        self.isAudioMute = YES;
        
    }else
    {
        if([_recordSession canAddInput:self.audioMicInput])
        {
            [_recordSession addInput:self.audioMicInput];
            [_recordSession addOutput:self.audioOutput];
            self.isAudioMute = NO;
        }
    }
    [_recordSession commitConfiguration];
//    [_recordSession startRunning];
    
}




#pragma mark - Custom Method
//启动录制功能
- (void)startPreview{
    self.startTime = CMTimeMake(0, 0);
    self.isCapturing = NO;
    self.isPaused = NO;
    self.isDiscount = NO;
    self.isFront = NO;
    [self.recordSession startRunning];
}


//关闭预览
- (void)closePreview {
    _startTime = CMTimeMake(0, 0);
    if (_recordSession) {
        [_recordSession stopRunning];
    }
    [self.previewLayer removeFromSuperlayer];
    [self.assetWriter finishWithCompletionHandler:^{
        //        NSLog(@"录制完成");
    }];
}

//开始录制
- (void)startRecording {
    @synchronized(self) {
        if (!self.isCapturing) {
            self.assetWriter = nil;
            self.isPaused = NO;
            self.isDiscount = NO;
            _timeOffset = CMTimeMake(0, 0);
            self.isCapturing = YES;
        }
    }
}
//暂停录制
- (void)pauseRecording {
    @synchronized(self) {
        if (self.isCapturing) {
            self.isPaused = YES;
            self.isDiscount = YES;
        }
    }
}


//继续录制
- (void)resumeRecording {
    @synchronized(self) {
        if (self.isPaused) {
            self.isPaused = NO;
        }
    }
}

//停止录制
- (void)stopRecordingVideo:(void (^)(UIImage *movieImage,NSDictionary *videoInfo))handler{
    @synchronized(self) {
        if (self.isCapturing) {
            self.isCapturing = NO;
            NSString* path = self.assetWriter.path;
            NSURL* url = [NSURL fileURLWithPath:path];
            dispatch_async(_captureQueue, ^{
                [self.assetWriter finishWithCompletionHandler:^{
                self.isCapturing = NO;
                self.assetWriter = nil;;
                self.startTime = CMTimeMake(0, 0);
                self.currentRecordTime = 0;
                if(self.recordConfiguration.videoSaveType == systemPhotoAlbum){
                    [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                        [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:url];
                    } completionHandler:^(BOOL success, NSError * _Nullable error) {
                        if(success){
                            NSLog(@"视频已保存到系统相册");
                        }else{
                            NSLog(@"视频保存保存到系统相册失败");
                        }
                        [self cleanCache];
                    }];
                }
                [self movieToImageHandler:handler];
                }];
            });
            
        }
    }
}


//获取视频第一帧的图片
- (void)movieToImageHandler:(void (^)(UIImage *movieImage,NSDictionary *videoInfo))handler {

    NSURL *url = [NSURL fileURLWithPath:self.videoSavePath];
    AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:url options:nil];
    CMTime   time = [asset duration];
    int seconds = ceil(time.value/time.timescale);
    NSUInteger   fileSize = (NSUInteger)[[NSFileManager defaultManager] attributesOfItemAtPath:self.videoSavePath error:nil].fileSize;
    NSDictionary *videoInfo = @{@"size" : @(fileSize),
                                @"duration" : @(seconds),
                                @"videoSavePath":self.videoSavePath};

    
    
    
    AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    
    generator.appliesPreferredTrackTransform = TRUE;
    CMTime thumbTime = CMTimeMakeWithSeconds(0, 60);
    generator.apertureMode = AVAssetImageGeneratorApertureModeEncodedPixels;
    AVAssetImageGeneratorCompletionHandler generatorHandler =
    ^(CMTime requestedTime, CGImageRef im, CMTime actualTime, AVAssetImageGeneratorResult result, NSError *error){
        if (result == AVAssetImageGeneratorSucceeded) {
            UIImage *thumbImg = [UIImage imageWithCGImage:im];
            if (handler) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    handler(thumbImg,videoInfo);
                });
            }
        }
    };
    [generator generateCGImagesAsynchronouslyForTimes:
     [NSArray arrayWithObject:[NSValue valueWithCMTime:thumbTime]] completionHandler:generatorHandler];
}



-(NSString *)numberConvertToTime:(NSNumber *)number
{
    NSInteger totalSeconds = [number integerValue];
    NSInteger seconds = totalSeconds % 60;
    NSInteger minutes = (totalSeconds / 60) % 60;
    NSInteger hours = totalSeconds / 4800;
    return [NSString stringWithFormat:@"%02ld:%02ld:%02ld",(long)hours, (long)minutes, (long)seconds];
}

-(NSString *)numberConvertToVideoSize:(NSNumber *)number
{
    CGFloat totalSize = [number floatValue];
    CGFloat size = (totalSize / 1024)/1024;
    return [NSString stringWithFormat:@"%.2fM",size];
}


- (NSDictionary *)getVideoInfoWithSourcePath:(NSString *)path{
    AVURLAsset * asset = [AVURLAsset assetWithURL:[NSURL fileURLWithPath:path]];
    CMTime   time = [asset duration];
    int seconds = ceil(time.value/time.timescale);
    
    NSInteger   fileSize = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil].fileSize;
    
    return @{@"size" : @(fileSize),
             @"duration" : @(seconds)};
}

//切换前后置摄像头
- (void)switchCamera{
    if (self.isCapturing) {
        NSLog(@"视频录制期间不允许切换摄像头");
        return;
    }
    if (!self.isFront) {
        [self.recordSession stopRunning];
        [self.recordSession removeInput:self.backCameraInput];
        if ([self.recordSession canAddInput:self.frontCameraInput]) {
            [self changeCameraAnimation];
            [self.recordSession addInput:self.frontCameraInput];
        }
        self.isFront = YES;
    }else {
        [self.recordSession stopRunning];
        [self.recordSession removeInput:self.frontCameraInput];
        if ([self.recordSession canAddInput:self.backCameraInput]) {
            [self changeCameraAnimation];
            [self.recordSession addInput:self.backCameraInput];
        }
        self.isFront = NO;
    }
}

//开启闪光灯
- (void)switchFlashLight {
    AVCaptureDevice *backCamera = [self backCamera];
    if (backCamera.torchMode == AVCaptureTorchModeOff) {
        [backCamera lockForConfiguration:nil];
        backCamera.torchMode = AVCaptureTorchModeOn;
        backCamera.flashMode = AVCaptureFlashModeOn;
        [backCamera unlockForConfiguration];
    } else {
        [backCamera lockForConfiguration:nil];
        backCamera.torchMode = AVCaptureTorchModeOff;
        backCamera.flashMode = AVCaptureTorchModeOff;
        [backCamera unlockForConfiguration];
    }
}


//- (CGFloat)getVideoLength:(NSURL *)URL
//{
//    NSDictionary *opts = [NSDictionary dictionaryWithObject:[NSNumber numberWithBool:NO]
//                                                     forKey:AVURLAssetPreferPreciseDurationAndTimingKey];
//    AVURLAsset *urlAsset = [AVURLAsset URLAssetWithURL:URL options:opts];
//    float second = 0;
//    second = urlAsset.duration.value/urlAsset.duration.timescale;
//    return second;
//}

//- (CGFloat)getFileSize:(NSString *)path
//{
//    NSFileManager *fileManager = [[NSFileManager alloc] init];
//    float filesize = -1.0;
//    if ([fileManager fileExistsAtPath:path]) {
//        NSDictionary *fileDic = [fileManager attributesOfItemAtPath:path error:nil];//获取文件的属性
//        unsigned long long size = [[fileDic objectForKey:NSFileSize] longLongValue];
//        filesize = 1.0*size/1024;
//    }
//    return filesize;
//}

//- (void)unloadInputOrOutputDevice
//{
//    //改变会话的配置前一定要先开启配置，配置完成后提交配置改变
//    [self.recordSession beginConfiguration];
//    
//    [self.recordSession removeInput:self.backCameraInput];
//    [self.recordSession removeInput:self.audioMicInput];
//    
//    [self.recordSession removeOutput:self.videoOutput];
//    [self.recordSession removeOutput:self.audioOutput];
//    
//    //提交会话配置
//    [self.recordSession commitConfiguration];
//}

- (void)cleanCache
{
    if ([[NSFileManager defaultManager] fileExistsAtPath:self.videoSavePath]) {
        //删除
        NSError *error = nil;
        [[NSFileManager defaultManager] removeItemAtPath:self.videoSavePath error:&error];
        if (error) {
            NSLog(@"%@",error);
            return;
        }
        NSLog(@"录制意外结束，删除本地文件");
    }
    NSAssert([[NSThread mainThread] isMainThread], @"Not Main Thread");
    
}

- (void)adjustRecorderOrientation:(AVCaptureVideoOrientation)orientation
{
    self.videoConnection.videoOrientation = orientation;
}

#pragma mark - Private Method

//用来返回是前置摄像头还是后置摄像头
- (AVCaptureDevice *)cameraWithPosition:(AVCaptureDevicePosition) position {
    //返回和视频录制相关的所有默认设备
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    //遍历这些设备返回跟position相关的设备
    for (AVCaptureDevice *device in devices) {
        if ([device position] == position) {
            return device;
        }
    }
    return nil;
}

- (void)changeCameraAnimation {
    CATransition *changeAnimation = [CATransition animation];
    changeAnimation.delegate = self;
    changeAnimation.duration = 0.45;
    changeAnimation.type = @"oglFlip";
    changeAnimation.subtype = kCATransitionFromRight;
    changeAnimation.timingFunction = UIViewAnimationCurveEaseInOut;
    [self.previewLayer addAnimation:changeAnimation forKey:@"changeAnimation"];
}



////获取视频第一帧的图片
//- (void)movieToImageHandler{
//    NSURL *url = [NSURL fileURLWithPath:self.videoSavePath];
//    AVURLAsset *asset = [[AVURLAsset alloc] initWithURL:url options:nil];
//    AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
//    generator.appliesPreferredTrackTransform = TRUE;
//    CMTime thumbTime = CMTimeMakeWithSeconds(0, 60);
//    generator.apertureMode = AVAssetImageGeneratorApertureModeEncodedPixels;
//    AVAssetImageGeneratorCompletionHandler generatorHandler =
//    ^(CMTime requestedTime, CGImageRef im, CMTime actualTime, AVAssetImageGeneratorResult result, NSError *error){
//        if (result == AVAssetImageGeneratorSucceeded) {
//            UIImage *thumbImg = [UIImage imageWithCGImage:im];
////            thumbImg = [self scaleImage:thumbImg toScale:0.2];
////            NSLog(@"\n生成图片的宽%.f\n生成图片的高%.f\n",thumbImg.size.width,thumbImg.size.height);
//            //生成你想要尺寸的图
//            dispatch_async(dispatch_get_main_queue(), ^{
////            [WMFileManager writeDataToFile:self.videoImageName data:UIImagePNGRepresentation(thumbImg)];
//            });
//        }
//    };
//    [generator generateCGImagesAsynchronouslyForTimes:
//     [NSArray arrayWithObject:[NSValue valueWithCMTime:thumbTime]] completionHandler:generatorHandler];
//}
//
//- (UIImage *)scaleImage:(UIImage *)image toScale:(float)scaleSize{
//    
//    UIGraphicsBeginImageContext(CGSizeMake((image.size.width * scaleSize),(image.size.height *scaleSize)));
//    [image drawInRect:CGRectMake(0, 0, image.size.width * scaleSize, image.size.height * scaleSize)];
//    UIImage *scaledImage = UIGraphicsGetImageFromCurrentImageContext();
//    UIGraphicsEndImageContext();
//    return scaledImage;
//}

//获得视频存放地址
- (NSString *)getVideoDocumentPath {
    NSString *videoCache = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject] ;
    BOOL isDir = NO;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL existed = [fileManager fileExistsAtPath:videoCache isDirectory:&isDir];
    if ( !(isDir == YES && existed == YES) ) {
        [fileManager createDirectoryAtPath:videoCache withIntermediateDirectories:YES attributes:nil error:nil];
    };
    return videoCache;
}

//获得视频cahhe存放地址
- (NSString *)getVideoCachePath {
    NSString *videoCache = [NSTemporaryDirectory() stringByAppendingPathComponent:@"videos"] ;
    BOOL isDir = NO;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL existed = [fileManager fileExistsAtPath:videoCache isDirectory:&isDir];
    if ( !(isDir == YES && existed == YES) ) {
        [fileManager createDirectoryAtPath:videoCache withIntermediateDirectories:YES attributes:nil error:nil];
    };
    return videoCache;
}


- (NSString *)getUploadFile_type:(NSString *)type fileType:(NSString *)fileType {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSDateFormatter * formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyyMMddHHmmss"];
    NSDate * NowDate = [NSDate dateWithTimeIntervalSince1970:now];
    ;
    NSString * timeStr = [formatter stringFromDate:NowDate];
    NSString *fileName = [NSString stringWithFormat:@"%@_%@.%@",type,timeStr,fileType];
    self.videoImageName = [NSString stringWithFormat:@"%@_%@",type,timeStr];
    return fileName;
}

//设置音频格式
- (void)setAudioFormat:(CMFormatDescriptionRef)fmt {
    const AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmt);
    _samplerate = asbd->mSampleRate;
    _channels = asbd->mChannelsPerFrame;
    
}

//调整媒体数据的时间
- (CMSampleBufferRef)adjustTime:(CMSampleBufferRef)sample by:(CMTime)offset {
    CMItemCount count;
    CMSampleBufferGetSampleTimingInfoArray(sample, 0, nil, &count);
    CMSampleTimingInfo* pInfo = malloc(sizeof(CMSampleTimingInfo) * count);
    CMSampleBufferGetSampleTimingInfoArray(sample, count, pInfo, &count);
    for (CMItemCount i = 0; i < count; i++) {
        pInfo[i].decodeTimeStamp = CMTimeSubtract(pInfo[i].decodeTimeStamp, offset);
        pInfo[i].presentationTimeStamp = CMTimeSubtract(pInfo[i].presentationTimeStamp, offset);
    }
    CMSampleBufferRef sout;
    CMSampleBufferCreateCopyWithNewTiming(nil, sample, count, pInfo, &sout);
    free(pInfo);
    return sout;
}

-(void)changeDeviceProperty:(PropertyChangeBlock)propertyChange{
    AVCaptureDevice *captureDevice= [self.backCameraInput device];
    NSError *error;
    //注意改变设备属性前一定要首先调用lockForConfiguration:调用完之后使用unlockForConfiguration方法解锁
    if ([captureDevice lockForConfiguration:&error]) {
        propertyChange(captureDevice);
        [captureDevice unlockForConfiguration];
    }else{
        NSLog(@"设置设备属性过程发生错误，错误信息：%@",error.localizedDescription);
    }
}

-(void)setFocusMode:(AVCaptureFocusMode )focusMode{
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        if ([captureDevice isFocusModeSupported:focusMode]) {
            [captureDevice setFocusMode:focusMode];
        }
    }];
}

-(void)setExposureMode:(AVCaptureExposureMode)exposureMode{
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        if ([captureDevice isExposureModeSupported:exposureMode]) {
            [captureDevice setExposureMode:exposureMode];
        }
    }];
}


-(void)focusWithMode:(AVCaptureFocusMode)focusMode exposureMode:(AVCaptureExposureMode)exposureMode atPoint:(CGPoint)point{
    [self changeDeviceProperty:^(AVCaptureDevice *captureDevice) {
        if ([captureDevice isFocusModeSupported:focusMode]) {
            [captureDevice setFocusMode:AVCaptureFocusModeAutoFocus];
        }
        if ([captureDevice isFocusPointOfInterestSupported]) {
            [captureDevice setFocusPointOfInterest:point];
        }
        if ([captureDevice isExposureModeSupported:exposureMode]) {
            [captureDevice setExposureMode:AVCaptureExposureModeAutoExpose];
        }
        if ([captureDevice isExposurePointOfInterestSupported]) {
            [captureDevice setExposurePointOfInterest:point];
        }
    }];
}

//设置 聚焦点
- (void)setFocusCursorWithPoint:(CGPoint)tapPoint
{
    CGPoint cameraPoint= [self.previewLayer captureDevicePointOfInterestForPoint:tapPoint];
    [self focusWithMode:AVCaptureFocusModeAutoFocus exposureMode:AVCaptureExposureModeAutoExpose atPoint:cameraPoint];
}

#pragma mark - AVCaptureVideoDataOutputSampleBufferDelegate,AVCaptureAudioDataOutputSampleBufferDelegate

- (void) captureOutput:(AVCaptureOutput *)captureOutput didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    BOOL isVideo = YES;
    @synchronized(self) {
        if (!self.isCapturing  || self.isPaused) {
            return;
        }
        if (captureOutput != self.videoOutput) {
            isVideo = NO;
        }
        //初始化编码器，当有音频和视频参数时创建编码器
        if ((self.assetWriter == nil) && !isVideo) {
            CMFormatDescriptionRef fmt = CMSampleBufferGetFormatDescription(sampleBuffer);
            if(self.isAudioMute == NO)// 非静音状态下添加音轨
            {
                [self setAudioFormat:fmt];
            }
            
        
            NSLog(@"当前编码器的音频采样速率和视频采样速率分别是：%ld---%ld",self.recordConfiguration.audioBitRate,self.recordConfiguration.videoRecordBitRate);
            NSUInteger audioBitRate = 0;
            NSUInteger videoBitRate = 0;
            NSUInteger videoWidth = 0;
            NSUInteger videoHeigth = 0;
            
            if(self.recordConfiguration.audioBitRate <= 0){
                audioBitRate = 64000;
            }else{
                audioBitRate = self.recordConfiguration.audioBitRate;
            }
            
            if(self.videoConnection.videoOrientation ==  AVCaptureVideoOrientationPortrait ||
               self.videoConnection.videoOrientation == AVCaptureVideoOrientationPortraitUpsideDown)
            {
                if(self.recordConfiguration.videoRecordSize.width == 0){
                    videoWidth = 480;
                }else{
                    videoWidth = self.recordConfiguration.videoRecordSize.width;
                }
                
                if(self.recordConfiguration.videoRecordSize.height == 0){
                    videoHeigth = 640;
                }else{
                    videoHeigth = self.recordConfiguration.videoRecordSize.height;
                }
            }else{
                if(self.recordConfiguration.videoRecordSize.width == 0){
                    videoWidth = 640;
                }else{
                    videoWidth = self.recordConfiguration.videoRecordSize.height;
                }
                
                if(self.recordConfiguration.videoRecordSize.height == 0){
                    videoHeigth = 480;
                }else{
                    videoHeigth = self.recordConfiguration.videoRecordSize.width;
                }
            }
            // create saveVideoPath
            self.videoName = [self getCurrentTime];
            switch (self.recordConfiguration.videoSaveType) {
            case systemPhotoAlbum:
                 self.videoSavePath = [[self getVideoCachePath] stringByAppendingPathComponent:self.videoName];
                 NSLog(@"录制的视频保存到相册");
                 break;
            case customSavePath:
                 self.videoSavePath = [[self getVideoDocumentPath] stringByAppendingPathComponent:self.videoName];
                 NSLog(@"录制的视频保存到沙盒");
                 break;
            default:
                 self.videoSavePath = [[self getVideoCachePath] stringByAppendingPathComponent:self.videoName];
                 NSLog(@"录制的视频保存到相册");
                 break;
                }
           
            NSLog(@"\n视频码率:%ld\n音频码率:%ld\n输出视频分辨率为:%ld X %ld\n",videoBitRate,audioBitRate,videoWidth,videoHeigth);
            NSLog(@"\n视频保存路径:%@\n",self.videoSavePath);
            
            self.assetWriter = [WMAssetWriter encoderForPath:self.videoSavePath Height:videoHeigth width:videoWidth channels:_channels samples:_samplerate videoBitRate:videoBitRate audioBitRate:audioBitRate];
        }
        //判断是否中断录制过
        if (self.isDiscount) {
            if (isVideo) {
                return;
            }
            self.isDiscount = NO;
            // 计算暂停的时间
            CMTime pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
            CMTime last = isVideo ? _lastVideo : _lastAudio;
            if (last.flags & kCMTimeFlags_Valid) {
                if (_timeOffset.flags & kCMTimeFlags_Valid) {
                    pts = CMTimeSubtract(pts, _timeOffset);
                }
                CMTime offset = CMTimeSubtract(pts, last);
                if (_timeOffset.value == 0) {
                    _timeOffset = offset;
                }else {
                    _timeOffset = CMTimeAdd(_timeOffset, offset);
                }
            }
            _lastVideo.flags = 0;
            _lastAudio.flags = 0;
        }
        // 增加sampleBuffer的引用计时,这样我们可以释放这个或修改这个数据，防止在修改时被释放
        CFRetain(sampleBuffer);
        if (_timeOffset.value > 0) {
            CFRelease(sampleBuffer);
            //根据得到的timeOffset调整
            sampleBuffer = [self adjustTime:sampleBuffer by:_timeOffset];
        }
        // 记录暂停上一次录制的时间
        CMTime pts = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
        CMTime dur = CMSampleBufferGetDuration(sampleBuffer);
        if (dur.value > 0) {
            pts = CMTimeAdd(pts, dur);
        }
        if (isVideo) {
            _lastVideo = pts;
        }else {
            _lastAudio = pts;
        }
    }
    CMTime dur = CMSampleBufferGetPresentationTimeStamp(sampleBuffer);
    if (self.startTime.value == 0) {
        self.startTime = dur;
    }
    CMTime sub = CMTimeSubtract(dur, self.startTime);
    self.currentRecordTime = CMTimeGetSeconds(sub);
    if (self.currentRecordTime > self.maxVideoDuration) {
//        if (self.currentRecordTime - self.maxVideoDuration < 0.1) {
//            if ([self.delegate respondsToSelector:@selector(recordProgress:)]) {
//                dispatch_async(dispatch_get_main_queue(), ^{
//                    [self.delegate recordProgress:self.currentRecordTime/self.maxVideoDuration];
//                });
//            }
//        }
        if(self.delegate && [self.delegate respondsToSelector:@selector(recordVideo:withBeyondMaxRecordTime:)]){
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.delegate recordVideo:self withBeyondMaxRecordTime:self.maxVideoDuration];
            });
        }
        return;
    }
    if ([self.delegate respondsToSelector:@selector(recordVideo:withProgress:)]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.delegate recordVideo:self withProgress:self.currentRecordTime/self.maxVideoDuration];
        });
    }
    // 进行数据编码
    [self.assetWriter encodeFrame:sampleBuffer isVideo:isVideo];
    CFRelease(sampleBuffer);
}


#pragma mark - Lazy Load

- (AVCaptureVideoPreviewLayer *)previewLayer
{
    if (_previewLayer == nil) {
        //通过AVCaptureSession初始化
        AVCaptureVideoPreviewLayer *preview = [[AVCaptureVideoPreviewLayer alloc] initWithSession:self.recordSession];
        preview.videoGravity = AVLayerVideoGravityResizeAspect;
        //设置视频预览的方向
        preview.connection.videoOrientation = self.videoConnection.videoOrientation;
        _previewLayer = preview;
    }
    return _previewLayer;

}


//录制的队列
- (dispatch_queue_t)captureQueue {
    if (_captureQueue == nil) {
        _captureQueue = dispatch_queue_create("cn.qiuyouqun.im.wclrecordengine.capture", DISPATCH_QUEUE_SERIAL);
    }
    return _captureQueue;
}

//捕获视频的会话
- (AVCaptureSession *)recordSession {
    if (_recordSession == nil) {
        _recordSession = [[AVCaptureSession alloc] init];
        
        if(self.recordConfiguration != nil)
        {
            //添加摄像头的输出
            if(self.recordConfiguration.cameraPosition == cameraPositionBack){
                if ([_recordSession canAddInput:self.backCameraInput]) {
                    [_recordSession addInput:self.backCameraInput];
                    self.captureDevice = [self backCamera];
                }
            }else{
                if ([_recordSession canAddInput:self.frontCameraInput]) {
                    [_recordSession addInput:self.frontCameraInput];
                    self.captureDevice = [self frontCamera];
                }
            }
            // 预览清晰度设置---- 默认标清录制
            switch (self.recordConfiguration.videoRecordType) {
                case videoRecordType_480P:
                    if([_recordSession canSetSessionPreset:AVCaptureSessionPreset640x480]){
                        self.recordConfiguration.videoRecordSize = CGSizeMake(480,720);
                        _recordSession.sessionPreset = AVCaptureSessionPreset640x480;
                    }else{
                        _recordSession.sessionPreset = AVCaptureSessionPreset352x288;
                        self.recordConfiguration.videoRecordSize = CGSizeMake(288, 352);
                        NSLog(@"机型不支持480P录制,已切换为更低清晰度录制");
                    }
                    break;
                case videoRecordType_720P:
                    if([_recordSession canSetSessionPreset:AVCaptureSessionPreset1280x720]){
                        self.recordConfiguration.videoRecordSize = CGSizeMake(720,1280);
                        _recordSession.sessionPreset = AVCaptureSessionPreset1280x720;
                    }else{
                        _recordSession.sessionPreset = AVCaptureSessionPreset640x480;
                        self.recordConfiguration.videoRecordSize = CGSizeMake(480, 640);
                        NSLog(@"机型不支持720P录制,已切换为480P录制");
                    }
                    break;
                case videoRecordType_1080P:
                    if([_recordSession canSetSessionPreset:AVCaptureSessionPreset1920x1080]){
                        _recordSession.sessionPreset = AVCaptureSessionPreset1920x1080;
                        self.recordConfiguration.videoRecordSize = CGSizeMake(1080,1920);
                    }else{
                        _recordSession.sessionPreset = AVCaptureSessionPreset640x480;
                        self.recordConfiguration.videoRecordSize = CGSizeMake(480, 640);
                        NSLog(@"机型不支持1080P录制,已切换为480P录制");
                    }
                    break;
                    
                default:
                    if([_recordSession canSetSessionPreset:AVCaptureSessionPreset640x480]){
                        self.recordConfiguration.videoRecordSize = CGSizeMake(480,720);
                        _recordSession.sessionPreset = AVCaptureSessionPreset640x480;
                    }else{
                        _recordSession.sessionPreset = AVCaptureSessionPreset352x288;
                        self.recordConfiguration.videoRecordSize = CGSizeMake(288, 352);
                        NSLog(@"机型不支持480P录制,已切换为更低清晰度录制");
                    }
                    break;
            }
            
            // 设置预览及录制方向---默认横向录制
            switch (self.recordConfiguration.recordOrientation) {
                case videoRecordOrientationPortrait:
                     self.videoConnection.videoOrientation = AVCaptureVideoOrientationPortrait;
                    break;
                case videoRecordOrientationPortraitUpsideDown:
                    self.videoConnection.videoOrientation = AVCaptureVideoOrientationPortraitUpsideDown;
                    break;
                case videoRecordOrientationLandscapeRight:
                    self.videoConnection.videoOrientation = AVCaptureVideoOrientationLandscapeRight;
                    break;
                case videoRecordOrientationLandscapeLeft:
                    self.videoConnection.videoOrientation = AVCaptureVideoOrientationLandscapeLeft;
                    break;
                default:
                    self.videoConnection.videoOrientation = AVCaptureVideoOrientationLandscapeRight;
                    break;
            }
    
        }else{// 默认开启后置摄像头
            if ([_recordSession canAddInput:self.backCameraInput]) {
                [_recordSession addInput:self.backCameraInput];
                self.captureDevice = [self backCamera];
            }
        }
        
        //添加后置麦克风的输入
        if ([_recordSession canAddInput:self.audioMicInput]) {
            [_recordSession addInput:self.audioMicInput];
        }
        
        //添加音频输出
        if ([_recordSession canAddOutput:self.audioOutput]) {
            [_recordSession addOutput:self.audioOutput];
        }
        //添加视频输出
        if ([_recordSession canAddOutput:self.videoOutput]) {
            [_recordSession addOutput:self.videoOutput];
        }
        
        // 设置录制fps
        if(0 < self.recordConfiguration.videoRecordFps)
        {
            [self setFps:30];
        }else{
            [self setFps:self.recordConfiguration.videoRecordFps];
        }
    }
    return _recordSession;
}

//后置摄像头输入
- (AVCaptureDeviceInput *)backCameraInput {
    if (_backCameraInput == nil) {
        NSError *error;
        
        _backCameraInput = [[AVCaptureDeviceInput alloc] initWithDevice:[self backCamera] error:&error];
        if (error) {
            NSLog(@"获取后置摄像头失败~");
        }
    }
    return _backCameraInput;
}

//前置摄像头输入
- (AVCaptureDeviceInput *)frontCameraInput {
    if (_frontCameraInput == nil) {
        NSError *error;
        _frontCameraInput = [[AVCaptureDeviceInput alloc] initWithDevice:[self frontCamera] error:&error];
        if (error) {
            NSLog(@"获取前置摄像头失败~");
        }
    }
    return _frontCameraInput;
}

//麦克风输入
- (AVCaptureDeviceInput *)audioMicInput {
    if (_audioMicInput == nil) {
        AVCaptureDevice *mic = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
        NSError *error;
        _audioMicInput = [AVCaptureDeviceInput deviceInputWithDevice:mic error:&error];
        if (error) {
            NSLog(@"获取麦克风失败~");
        }
    }
    return _audioMicInput;
}

//视频输出
- (AVCaptureVideoDataOutput *)videoOutput {
    if (_videoOutput == nil) {
        _videoOutput = [[AVCaptureVideoDataOutput alloc] init];
        [_videoOutput setSampleBufferDelegate:self queue:self.captureQueue];
        NSDictionary* setcapSettings = [NSDictionary dictionaryWithObjectsAndKeys:
                                        [NSNumber numberWithInt:kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange], kCVPixelBufferPixelFormatTypeKey,
                                        nil];
        _videoOutput.videoSettings = setcapSettings;
    }
    return _videoOutput;
}

//音频输出
- (AVCaptureAudioDataOutput *)audioOutput {
    if (_audioOutput == nil) {
        _audioOutput = [[AVCaptureAudioDataOutput alloc] init];
        [_audioOutput setSampleBufferDelegate:self queue:self.captureQueue];
    }
    return _audioOutput;
}

//视频连接
- (AVCaptureConnection *)videoConnection {
//    _videoConnection.videoOrientation = VideoOutPutOrientation;
    _videoConnection = [self.videoOutput connectionWithMediaType:AVMediaTypeVideo];
    return _videoConnection;
}

//音频连接
- (AVCaptureConnection *)audioConnection {
    if (_audioConnection == nil) {
        if(self.isAudioMute == NO)
        {
            _audioConnection = [self.audioOutput connectionWithMediaType:AVMediaTypeAudio];
        }
    }
    return _audioConnection;
}

//返回前置摄像头
- (AVCaptureDevice *)frontCamera {
    return [self cameraWithPosition:AVCaptureDevicePositionFront];
}

//返回后置摄像头
- (AVCaptureDevice *)backCamera {
    return [self cameraWithPosition:AVCaptureDevicePositionBack];
}

-(void)dealloc
{
    NSLog(@"录制管理类被销毁");
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

/**
 *  设置录制fps
 *
 *  @param fps 录制fps
 */
-(void)setFps:(CGFloat)fps
{
    [self.captureDevice lockForConfiguration:nil];
    [self.captureDevice setActiveVideoMinFrameDuration:CMTimeMake(1, fps)];
    [self.captureDevice setActiveVideoMaxFrameDuration:CMTimeMake(1, fps)];
    [self.captureDevice unlockForConfiguration];
}



-(NSString *)getCurrentTime
{
    // 获得当前时间
    NSDate*date = [NSDate date];
    NSCalendar*calendar = [NSCalendar currentCalendar];
    NSDateComponents*comps;
    
    comps =[calendar components:(NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay |
                                 NSCalendarUnitHour | NSCalendarUnitMinute | NSCalendarUnitSecond)
                       fromDate:date];
    NSInteger year = [comps year];
    NSInteger month = [comps month];
    NSInteger day = [comps day];
    NSInteger hour = [comps hour];
    NSInteger minute = [comps minute];
    NSInteger second = [comps second];
    
    NSString *currentTIme = [NSString stringWithFormat:@"%ld-%02ld-%02ld %02ld:%02ld:%02ld",(long)year,month,day,hour,minute,second];
    return currentTIme;
}

@end
