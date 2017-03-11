//
//  WMAssetReader.h
//  WMRecorder
//
//  Created by WangMing on 2016/10/19.
//  Copyright © 2016年 WangMing. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>

@class WMAssetReader;

@protocol WMAssetReaderDelegate <NSObject>

- (void)ali_mMoveDecoder:(WMAssetReader *)reader buffer:(NSArray *)images;

- (void)mMovieDecoderOnDecodeFinished:(WMAssetReader *)reader;

- (void)mMovieDecoder:(WMAssetReader *)reader onNewVideoFrameReady:(CMSampleBufferRef)videoBuffer;
@end


@interface WMAssetReader : NSObject

@property (nonatomic, strong) NSString *videoPath;

@property (nonatomic, weak) id <WMAssetReaderDelegate> delegate;

- (void)startDecoderVideo;

- (void)test;

+ (CGImageRef)imageFromSampleBufferRef:(CMSampleBufferRef)sampleBufferRef;

@end
