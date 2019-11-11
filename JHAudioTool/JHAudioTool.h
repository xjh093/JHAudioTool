//
//  JHAudioTool.h
//  JHKit
//
//  Created by HaoCold on 2018/12/18.
//  Copyright © 2018 HaoCold. All rights reserved.
//

#import <Foundation/Foundation.h>

typedef void(^JHAudioToolFinishBlock)(BOOL success, int64_t seconds);
typedef void(^JHAudioToolTranscodeBlock)(BOOL success);

@interface JHAudioTool : NSObject

+ (instancetype)shareTool;

/**
 Merge audios.(from .caf or .wav to .m4a)
 
 @param paths source audio path.
 @param outputPath output path of audio.
 
 */
+ (void)mergeAudios:(NSArray *)paths destnation:(NSString *)outputPath finish:(JHAudioToolFinishBlock)finish;

/**
 transcode audio.(from .m4a to .caf or .wav)
 
 @param path source audio path.
 @param outputPath output path of audio.
 
 */
+ (void)transcodeAudio:(NSString*)path destnation:(NSString *)outputPath sampleRate:(int)sampleRate finish:(JHAudioToolFinishBlock)finish;

/**
 Transcode PCM to MP3.
 
 @param sourcePath source path.
 @param desPath destination path.
 @param sampleRate sampleRate.
 
 @return BOOL YES,Transcode success, otherwese NO.
 */
+ (BOOL)audioTranscodePCMtoMp3:(NSString *)sourcePath destination:(NSString *)desPath sampleRate:(int)sampleRate;

/**
 Fetch audio duration.
 
 @param url audio path.
 
 @return duration.
 */
+ (NSTimeInterval)audioDurationFromURL:(NSString *)url;

/**
 Transcode PCM to MP3 while recording.
 
 @param sourcePath source path.
 @param desPath destination path.
 @param sampleRate sampleRate.
 @param callback callback.
 */
- (void)audioTranscodePCMtoMp3:(NSString *)sourcePath destination:(NSString *)desPath sampleRate:(int)sampleRate callback:(JHAudioToolTranscodeBlock)callback;

/**
 stop transcode.
 */
- (void)transcodeStop;

@end
