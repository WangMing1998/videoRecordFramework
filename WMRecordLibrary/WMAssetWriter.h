//
//  WMAssetWriter.h
//  WMRecorder
//
//  Created by WangMing on 2016/10/12.
//  Copyright © 2016年 WangMing. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

@interface WMAssetWriter : NSObject

@property (nonatomic, readonly) NSString *path;

/**
 *  WCLRecordEncoder遍历构造器的
 *
 *  @param path 媒体存发路径
 *  @param cy   视频分辨率的高
 *  @param cx   视频分辨率的宽
 *  @param ch   音频通道
 *  @param rate 音频的采样比率
 *  @videoBitRate 视频码率
 *  @audioBitRate 音频码率
 *  @return WMRecordEncoder的实体
 */
+ (WMAssetWriter*)encoderForPath:(NSString*) path Height:(NSInteger) cy width:(NSInteger) cx channels: (int) ch samples:(Float64) rate videoBitRate:(NSUInteger)videoBitRate audioBitRate:(NSUInteger)audioBitRate;

/**
 *  初始化方法
 *
 *  @param path 媒体存发路径
 *  @param cy   视频分辨率的高
 *  @param cx   视频分辨率的宽
 *  @param ch   音频通道
 *  @param rate 音频的采样率
 *  @videoBitRate 视频码率
 *  @audioBitRate 音频码率
 *  @return WMRecordEncoder的实体
 */
- (instancetype)initPath:(NSString*)path Height:(NSInteger)cy width:(NSInteger)cx channels:(int)ch samples:(Float64) rate videoBitRate:(NSUInteger)videoBitRate audioBitRate:(NSUInteger)audioBitRate;

/**
 *  完成视频录制时调用
 *
 *  @param handler 完成的回掉block
 */
- (void)finishWithCompletionHandler:(void (^)(void))handler;

/**
 *  通过这个方法写入数据
 *
 *  @param sampleBuffer 写入的数据
 *  @param isVideo      是否写入的是视频
 *
 *  @return 写入是否成功
 */
- (BOOL)encodeFrame:(CMSampleBufferRef)sampleBuffer isVideo:(BOOL)isVideo;
@end
