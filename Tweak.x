#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreFoundation/CoreFoundation.h>
#import <objc/runtime.h>

#define VCamConfigPath "/var/mobile/Library/Preferences/VCam/config.plist"
#define VCamMediaDirectory "/var/mobile/Library/Preferences/VCam/input_media"
#define VCamNotificationName CFSTR("com.vcam.settingschanged")

static BOOL VCamEnabled = NO;
static NSString *VCamMediaType = nil;
static NSString *VCamMediaPath = nil;
static AVAssetReader *VCamAssetReader = nil;
static AVAssetReaderTrackOutput *VCamAssetTrackOutput = nil;
static dispatch_queue_t VCamMediaQueue = NULL;

static void VCamLoadSettings(void) {
    NSDictionary *config = [NSDictionary dictionaryWithContentsOfURL:[NSURL fileURLWithPath:VCamConfigPath]];
    if (!config) {
        VCamEnabled = NO;
        VCamMediaType = [@"image" copy];
        VCamMediaPath = nil;
        return;
    }

    id enabledValue = config[@"enabled"];
    VCamEnabled = enabledValue ? [enabledValue boolValue] : NO;

    id mediaType = config[@"media_type"];
    VCamMediaType = mediaType ? [mediaType copy] : @"image";

    id mediaPath = config[@"media_path"];
    VCamMediaPath = mediaPath ? [mediaPath copy] : nil;

    if ([VCamMediaType isEqualToString:@"video"] && VCamMediaPath.length > 0) {
        NSURL *url = [NSURL fileURLWithPath:VCamMediaPath];
        AVAsset *asset = [AVAsset assetWithURL:url];
        AVAssetTrack *track = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
        if (track) {
            AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:asset error:nil];
            NSDictionary *readerOutputSettings = @{
                (id)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
                (id)kCVPixelBufferIOSurfacePropertiesKey: @{}
            };
            AVAssetReaderTrackOutput *output = [[AVAssetReaderTrackOutput alloc] initWithTrack:track outputSettings:readerOutputSettings];
            output.alwaysCopiesSampleData = NO;
            if (reader && [reader canAddOutput:output]) {
                [reader addOutput:output];
                if ([reader startReading]) {
                    if (VCamAssetReader) {
                        [VCamAssetReader cancelReading];
                        VCamAssetReader = nil;
                    }
                    if (VCamAssetTrackOutput) {
                        VCamAssetTrackOutput = nil;
                    }
                    VCamAssetReader = reader;
                    VCamAssetTrackOutput = output;
                }
            }
        }
    }
}

static void VCamReleaseAssetReader(void) {
    if (VCamAssetTrackOutput) {
        VCamAssetTrackOutput = nil;
    }

    if (VCamAssetReader) {
        [VCamAssetReader cancelReading];
        VCamAssetReader = nil;
    }
}

static CVPixelBufferRef VCamCreatePixelBufferFromImagePath(NSString *imagePath) {
    if (imagePath.length == 0) {
        return NULL;
    }

    NSURL *imageURL = [NSURL fileURLWithPath:imagePath];
    UIImage *image = [UIImage imageWithContentsOfFile:imageURL.path];
    if (!image) {
        return NULL;
    }

    CGImageRef cgImage = image.CGImage;
    if (!cgImage) {
        return NULL;
    }

    size_t width = CGImageGetWidth(cgImage);
    size_t height = CGImageGetHeight(cgImage);
    size_t bytesPerRow = width * 4;

    CVPixelBufferRef pixelBuffer = NULL;
    NSDictionary *attributes = @{
        (NSString *)kCVPixelBufferCGImageCompatibilityKey: @YES,
        (NSString *)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES,
        (NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{}
    };

    CVReturn status = CVPixelBufferCreate(
        kCFAllocatorDefault,
        width,
        height,
        kCVPixelFormatType_32BGRA,
        (__bridge CFDictionaryRef)attributes,
        &pixelBuffer
    );

    if (status != kCVReturnSuccess || pixelBuffer == NULL) {
        return NULL;
    }

    CVPixelBufferLockBaseAddress(pixelBuffer, 0);
    void *baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer);
    if (!baseAddress) {
        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
        CFRelease(pixelBuffer);
        return NULL;
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef ctx = CGBitmapContextCreate(
        baseAddress,
        width,
        height,
        8,
        bytesPerRow,
        colorSpace,
        kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little
    );

    if (ctx) {
        CGContextDrawImage(ctx, CGRectMake(0, 0, width, height), cgImage);
        CGContextRelease(ctx);
    }

    CGColorSpaceRelease(colorSpace);
    CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);
    return pixelBuffer;
}

static CMSampleBufferRef VCamCreateSampleBufferFromPixelBuffer(CVPixelBufferRef pixelBuffer) {
    if (pixelBuffer == NULL) {
        return NULL;
    }

    CMVideoFormatDescriptionRef formatDescription = NULL;
    OSStatus formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
        kCFAllocatorDefault,
        pixelBuffer,
        &formatDescription
    );
    if (formatStatus != noErr || formatDescription == NULL) {
        return NULL;
    }

    CMSampleBufferRef sampleBuffer = NULL;
    OSStatus sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(
        kCFAllocatorDefault,
        pixelBuffer,
        formatDescription,
        NULL,
        &sampleBuffer
    );

    if (formatDescription) {
        CFRelease(formatDescription);
    }

    if (sampleStatus != noErr) {
        return NULL;
    }

    return sampleBuffer;
}

static CMSampleBufferRef VCamReadVideoSample(void) {
    if (!VCamAssetReader || !VCamAssetTrackOutput) {
        return NULL;
    }

    CMSampleBufferRef sampleBuffer = [VCamAssetTrackOutput copyNextSampleBuffer];
    if (sampleBuffer == NULL) {
        VCamReleaseAssetReader();
        VCamLoadSettings();
        if (VCamAssetReader && VCamAssetTrackOutput) {
            sampleBuffer = [VCamAssetTrackOutput copyNextSampleBuffer];
        }
    }

    return sampleBuffer;
}

static CMSampleBufferRef VCamBuildReplacementSampleBuffer(void) {
    if (!VCamEnabled || VCamMediaPath.length == 0) {
        return NULL;
    }

    if ([VCamMediaType isEqualToString:@"video"]) {
        return VCamReadVideoSample();
    }

    CVPixelBufferRef imagePixelBuffer = VCamCreatePixelBufferFromImagePath(VCamMediaPath);
    if (!imagePixelBuffer) {
        return NULL;
    }

    CMSampleBufferRef sampleBuffer = VCamCreateSampleBufferFromPixelBuffer(imagePixelBuffer);
    if (sampleBuffer) {
        CFRelease(imagePixelBuffer);
        return sampleBuffer;
    }

    CFRelease(imagePixelBuffer);
    return NULL;
}

static void VCamSettingsChangedCallback(CFNotificationCenterRef center, void *observer, CFStringRef name, const void *object, CFDictionaryRef userInfo) {
    (void)center;
    (void)observer;
    (void)name;
    (void)object;
    (void)userInfo;

    VCamLoadSettings();
}

%hook AVCaptureVideoDataOutput

- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (!VCamEnabled || VCamMediaPath.length == 0) {
        %orig;
        return;
    }

    CMSampleBufferRef replacement = VCamBuildReplacementSampleBuffer();
    if (replacement) {
        %orig(output, replacement, connection);
        CFRelease(replacement);
        return;
    }

    %orig;
}

%end

__attribute__((constructor)) static void VCamInitializer(void) {
    VCamMediaQueue = dispatch_queue_create("com.vcam.media.queue", DISPATCH_QUEUE_SERIAL);
    CFNotificationCenterAddObserver(
        CFNotificationCenterGetDarwinNotifyCenter(),
        NULL,
        VCamSettingsChangedCallback,
        VCamNotificationName,
        NULL,
        CFNotificationSuspensionBehaviorCoalesce
    );

    VCamLoadSettings();
}
