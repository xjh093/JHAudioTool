//
//  JHAudioTool.m
//  JHKit
//
//  Created by HaoCold on 2018/12/18.
//  Copyright © 2018 HaoCold. All rights reserved.
//

#import "JHAudioTool.h"
#import <AVFoundation/AVFoundation.h>
#import "lame.h"

@interface JHAudioTool()
@property (nonatomic,  assign) BOOL  stop;
@end

@implementation JHAudioTool

+ (instancetype)shareTool
{
    static JHAudioTool *tool;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        tool = [[JHAudioTool alloc] init];
    });
    return tool;
}

+ (void)mergeAudios:(NSArray *)paths destnation:(NSString *)outputPath finish:(JHAudioToolFinishBlock)finish
{
    if (paths.count == 0 || outputPath == nil) {
        return;
    }
    
    AVMutableComposition *composition = [AVMutableComposition composition];
    // 设置音频合并音轨
    AVMutableCompositionTrack *compositionTrack = [composition addMutableTrackWithMediaType:AVMediaTypeAudio preferredTrackID:kCMPersistentTrackID_Invalid];
    // 开始时间
    CMTime beginTime = kCMTimeZero;
    NSError *error = nil;
    for (NSString *path in paths) {
        
        NSURL *url;
        if ([path isKindOfClass:[NSURL class]]) {
            url = (NSURL *)path;
        }else{
            url = [NSURL fileURLWithPath:path];
        }
        
        // 音频文件资源
        AVURLAsset *asset = [AVURLAsset assetWithURL:url];
        // 需要合并的音频文件的区间
        CMTimeRange timeRange = CMTimeRangeMake(kCMTimeZero, asset.duration);
        // ofTrack 音频文件内容
        AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeAudio].firstObject;
        //
        [compositionTrack insertTimeRange:timeRange ofTrack:track atTime:beginTime error:&error];
        if (error) {
            NSLog(@"error:%@",error);
        }
        
        beginTime = CMTimeAdd(beginTime, asset.duration);
    }
    
    [[NSFileManager defaultManager] removeItemAtPath:outputPath error:nil];
    
    // 导出合并的音频
    // presetName 与 outputFileType 要对应
    AVAssetExportSession *export = [[AVAssetExportSession alloc] initWithAsset:composition presetName:AVAssetExportPresetAppleM4A];
    export.outputURL = [NSURL fileURLWithPath:outputPath];
    export.outputFileType = AVFileTypeAppleM4A;
    export.shouldOptimizeForNetworkUse = YES;
    [export exportAsynchronouslyWithCompletionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            if (finish) {
                if(export.status == AVAssetExportSessionStatusCompleted) {
                    AVURLAsset *asset = [AVURLAsset assetWithURL:[NSURL fileURLWithPath:outputPath]];
                    int64_t seconds = asset.duration.value / asset.duration.timescale;
                    
                    finish(YES, seconds);
                }else if(export.status == AVAssetExportSessionStatusFailed){
                    NSLog(@"export failed:%@",error);
                    finish(NO, 0);
                }
            }
        });
    }];
}

+ (void)transcodeAudio:(NSString *)path destnation:(NSString *)outputPath sampleRate:(int)sampleRate finish:(JHAudioToolFinishBlock)finish
{
    NSURL *originalUrl = [NSURL fileURLWithPath:path];
    NSURL *outPutUrl = [NSURL fileURLWithPath:outputPath];
    
    AVURLAsset *songAsset = [AVURLAsset URLAssetWithURL:originalUrl options:nil];
    NSError *error =nil;
    AVAssetReader *assetReader = [AVAssetReader assetReaderWithAsset:songAsset error:&error];
    if(error) {
        NSLog(@"assetReader error: %@", error);
        if (finish) {
            finish(NO,0);
        }
        return;
    }
    
    AVAssetReaderOutput *assetReaderOutput = [AVAssetReaderAudioMixOutput assetReaderAudioMixOutputWithAudioTracks:songAsset.tracks audioSettings:nil];
    if([assetReader canAddOutput:assetReaderOutput]){
        [assetReader addOutput:assetReaderOutput];
    }else{
        NSLog(@"can't add reader output... die!");
        if (finish) {
            finish(NO,0);
        }
        return;
    }
    
    AVAssetWriter *assetWriter = [AVAssetWriter assetWriterWithURL:outPutUrl fileType:AVFileTypeCoreAudioFormat error:&error];
    if(error) {
        NSLog(@"assetWriter error: %@", error);
        if (finish) {
            finish(NO,0);
        }
        return;
    }
    
    AudioChannelLayout channelLayout;
    memset(&channelLayout,0,sizeof(AudioChannelLayout));
    channelLayout.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo;
    
    NSDictionary *outputSettings = @{
                                     AVFormatIDKey:@(kAudioFormatLinearPCM),
                                     AVSampleRateKey:@(sampleRate), // 8000/11025/22050/44100/96000
                                     AVNumberOfChannelsKey:@(2),
                                     AVChannelLayoutKey:[NSData dataWithBytes:&channelLayout length:sizeof(channelLayout)],
                                     AVLinearPCMBitDepthKey:@(16),
                                     AVLinearPCMIsNonInterleaved:@(NO),
                                     AVLinearPCMIsFloatKey:@(NO),
                                     AVLinearPCMIsBigEndianKey:@(NO)
                                     };
    
    AVAssetWriterInput *assetWriterInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeAudio outputSettings:outputSettings];
    assetWriterInput.expectsMediaDataInRealTime = NO;
    if([assetWriter canAddInput:assetWriterInput]) {
        [assetWriter addInput:assetWriterInput];
    }else{
        NSLog(@"can't add asset writer input... die!");
        if (finish) {
            finish(NO,0);
        }
        return;
    }
    
    [assetReader startReading];
    [assetWriter startWriting];
    
    AVAssetTrack *soundTrack = [songAsset.tracks objectAtIndex:0];
    CMTime startTime = CMTimeMake(0, soundTrack.naturalTimeScale);
    [assetWriter startSessionAtSourceTime:startTime];
    
    dispatch_queue_t mediaInputQueue = dispatch_queue_create("mediaInputQueue",NULL);
    [assetWriterInput requestMediaDataWhenReadyOnQueue:mediaInputQueue usingBlock: ^{
        while([assetWriterInput isReadyForMoreMediaData]) {
            CMSampleBufferRef nextBuffer = [assetReaderOutput copyNextSampleBuffer];
            if(nextBuffer) {
                [assetWriterInput appendSampleBuffer:nextBuffer];
            }else{
                [assetWriterInput markAsFinished];
                [assetWriter finishWritingWithCompletionHandler:^{
                }];
                
                [assetReader cancelReading];
                NSDictionary *outputFileAttributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[outPutUrl path] error:nil];
                NSLog(@"fileSize: %lld",[outputFileAttributes fileSize]);
                dispatch_async(dispatch_get_main_queue(), ^{
                    if (finish) {
                        AVURLAsset *asset = [AVURLAsset assetWithURL:outPutUrl];
                        int64_t seconds = asset.duration.value / asset.duration.timescale;
                        finish(YES,seconds);
                    }
                });
                break;
            }
        }
    }];
}

+ (BOOL)audioTranscodePCMtoMp3:(NSString *)sourcePath destination:(NSString *)desPath sampleRate:(int)sampleRate;
{
    BOOL success = NO;
    @try {
        int read, write;
        
        FILE *pcm = fopen([sourcePath cStringUsingEncoding:1], "rb");
        fseek(pcm, 4*1024, SEEK_CUR); // skip file header, 跳过文件头
        FILE *mp3 = fopen([desPath cStringUsingEncoding:1], "wb+");
        
        const int PCM_SIZE = 8192;
        const int MP3_SIZE = 8192;
        short int pcm_buffer[PCM_SIZE*2];
        unsigned char mp3_buffer[MP3_SIZE];
        
        lame_t lame = lame_init();
        lame_set_in_samplerate(lame, sampleRate); // 采样率要和录制的一样  8000/11025/22050/44100/96000
        lame_set_VBR(lame, vbr_default);
        lame_init_params(lame);
        
        do {
            read = fread(pcm_buffer, 2*sizeof(short int), PCM_SIZE, pcm);
            if (read == 0)
                write = lame_encode_flush(lame, mp3_buffer, MP3_SIZE);
            else
                write = lame_encode_buffer_interleaved(lame, pcm_buffer, read, mp3_buffer, MP3_SIZE);
            
            fwrite(mp3_buffer, write, 1, mp3);
            
        } while (read != 0);
        
        lame_mp3_tags_fid(lame, mp3);
        lame_close(lame);
        fclose(mp3);
        fclose(pcm);
        success = YES;
    }
    @catch (NSException *exception) {
        NSLog(@"audioTranscodePCMtoMp3:%@",[exception description]);
        success = NO;
    }
    @finally {
        return success;
    }
}

+ (NSTimeInterval)audioDurationFromURL:(NSString *)url{
    if (![url isKindOfClass:[NSString class]]) {
        return 0;
    }
    if (url.length == 0) {
        return 0;
    }
    
    AVURLAsset *audioAsset = nil;
    NSDictionary *dic = @{AVURLAssetPreferPreciseDurationAndTimingKey:@(YES)};
    if ([url hasPrefix:@"http://"]) {
        audioAsset = [AVURLAsset URLAssetWithURL:[NSURL URLWithString:url] options:dic];
    }else {
        audioAsset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:url] options:dic];
    }
    CMTime audioDuration = audioAsset.duration;
    float audioDurationSeconds = CMTimeGetSeconds(audioDuration);
    return audioDurationSeconds;
}

- (void)audioTranscodePCMtoMp3:(NSString *)sourcePath destination:(NSString *)desPath sampleRate:(int)sampleRate callback:(JHAudioToolTranscodeBlock)callback
{
    _stop = NO;
    
    @try {
        int read, write;
        
        FILE *pcm = fopen([sourcePath cStringUsingEncoding:1], "rb");
        FILE *mp3 = fopen([desPath cStringUsingEncoding:1], "wb");
        
        const int PCM_SIZE = 8192;
        const int MP3_SIZE = 8192;
        short int pcm_buffer[PCM_SIZE*2];
        unsigned char mp3_buffer[MP3_SIZE];
        
        lame_t lame = lame_init();
        lame_set_in_samplerate(lame, sampleRate); // 采样率要和录制的一样  8000/11025/22050/44100/96000
        lame_set_VBR(lame, vbr_default);
        lame_init_params(lame);
        
        long curpos;
        BOOL skipPCMHeader = NO;
        
        do {
            curpos = ftell(pcm);
            long startPos = ftell(pcm);
            fseek(pcm, 0, SEEK_END);
            long endPos   = ftell(pcm);
            long length   = endPos - startPos;
            fseek(pcm, curpos, SEEK_SET);
            
            if (length > PCM_SIZE * 2 * sizeof(short int)) {
                
                if (!skipPCMHeader) {
                    //Uump audio file header, If you do not skip file header
                    //you will heard some noise at the beginning!!!
                    fseek(pcm, 4 * 1024, SEEK_CUR);
                    skipPCMHeader = YES;
                    NSLog(@"skip pcm file header !!!!!!!!!!");
                }
                
                read = (int)fread(pcm_buffer, 2 * sizeof(short int), PCM_SIZE, pcm);
                write = lame_encode_buffer_interleaved(lame, pcm_buffer, read, mp3_buffer, MP3_SIZE);
                fwrite(mp3_buffer, write, 1, mp3);
                NSLog(@"read %d bytes", write);
            } else {
                [NSThread sleepForTimeInterval:0.05];
                NSLog(@"sleep");
            }
        } while (!_stop);
        
        read = (int)fread(pcm_buffer, 2 * sizeof(short int), PCM_SIZE, pcm);
        write = lame_encode_flush(lame, mp3_buffer, MP3_SIZE);
        
        NSLog(@"read %d bytes and flush to mp3 file", write);
        lame_mp3_tags_fid(lame, mp3);
        lame_close(lame);
        fclose(mp3);
        fclose(pcm);
        
    } @catch (NSException *exception) {
        NSLog(@"audioTranscodePCMtoMp3:%@",[exception description]);
        if (callback) {
            callback(NO);
        }
    } @finally {
        NSLog(@"audioTranscodePCMtoMp3 finish!");
        if (callback) {
            callback(YES);
        }
    }
}

- (void)transcodeStop
{
    _stop = YES;
}

@end
