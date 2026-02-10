#import "Utils.h"
#import <AVFoundation/AVFoundation.h>

@implementation SCIUtils

+ (BOOL)getBoolPref:(NSString *)key {
    if (![key length] || [[NSUserDefaults standardUserDefaults] objectForKey:key] == nil) return false;

    return [[NSUserDefaults standardUserDefaults] boolForKey:key];
}
+ (double)getDoublePref:(NSString *)key {
    if (![key length] || [[NSUserDefaults standardUserDefaults] objectForKey:key] == nil) return 0;

    return [[NSUserDefaults standardUserDefaults] doubleForKey:key];
}
+ (NSString *)getStringPref:(NSString *)key {
    if (![key length] || [[NSUserDefaults standardUserDefaults] objectForKey:key] == nil) return @"";

    return [[NSUserDefaults standardUserDefaults] stringForKey:key];
}

+ (void)cleanCache {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSMutableArray<NSError *> *deletionErrors = [NSMutableArray array];

    // Temp folder
    // * disabled bc app crashed trying to delete certain files inside it
    //NSError *tempFolderError;
    //[fileManager removeItemAtURL:[NSURL fileURLWithPath:NSTemporaryDirectory()] error:&tempFolderError];

    //if (tempFolderError) [deletionErrors addObject:tempFolderError];

    // Analytics folder
    NSError *analyticsFolderError;
    NSString *analyticsFolder = [[NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:@"Application Support/com.burbn.instagram/analytics"];
    [fileManager removeItemAtURL:[[NSURL alloc] initFileURLWithPath:analyticsFolder] error:&analyticsFolderError];

    if (analyticsFolderError) [deletionErrors addObject:analyticsFolderError];
    
    // Caches folder
    NSString *cachesFolder = [[NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:@"Caches"];
    NSArray *cachesFolderContents = [fileManager contentsOfDirectoryAtURL:[[NSURL alloc] initFileURLWithPath:cachesFolder] includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
    
    for (NSURL *fileURL in cachesFolderContents) {
        NSError *cacheItemDeletionError;
        [fileManager removeItemAtURL:fileURL error:&cacheItemDeletionError];

        if (cacheItemDeletionError) [deletionErrors addObject:cacheItemDeletionError];
    }

    // Log errors
    if (deletionErrors.count > 1) {

        for (NSError *error in deletionErrors) {
            NSLog(@"[SCInsta] File Deletion Error: %@", error);
        }

    }

}

// Displaying View Controllers
+ (void)showQuickLookVC:(NSArray<id> *)items {
    QLPreviewController *previewController = [[QLPreviewController alloc] init];
    QuickLookDelegate *quickLookDelegate = [[QuickLookDelegate alloc] initWithPreviewItemURLs:items];

    previewController.dataSource = quickLookDelegate;
    
    [topMostController() presentViewController:previewController animated:true completion:nil];
}
+ (void)showShareVC:(id)item {
    UIActivityViewController *acVC = [[UIActivityViewController alloc] initWithActivityItems:@[item] applicationActivities:nil];
    if (is_iPad()) {
        acVC.popoverPresentationController.sourceView = topMostController().view;
        acVC.popoverPresentationController.sourceRect = CGRectMake(topMostController().view.bounds.size.width / 2.0, topMostController().view.bounds.size.height / 2.0, 1.0, 1.0);
    }
    [topMostController() presentViewController:acVC animated:true completion:nil];
}

// Colours
+ (UIColor *)SCIColor_Primary {
    return [UIColor colorWithRed:0/255.0 green:152/255.0 blue:254/255.0 alpha:1];
};

// Errors
+ (NSError *)errorWithDescription:(NSString *)errorDesc {
    return [self errorWithDescription:errorDesc code:1];
}
+ (NSError *)errorWithDescription:(NSString *)errorDesc code:(NSInteger)errorCode {
    NSError *error = [ NSError errorWithDomain:@"com.socuul.scinsta" code:errorCode userInfo:@{ NSLocalizedDescriptionKey: errorDesc } ];
    return error;
}

+ (JGProgressHUD *)showErrorHUDWithDescription:(NSString *)errorDesc {
    return [self showErrorHUDWithDescription:errorDesc dismissAfterDelay:4.0];
}
+ (JGProgressHUD *)showErrorHUDWithDescription:(NSString *)errorDesc dismissAfterDelay:(CGFloat)dismissDelay {
    JGProgressHUD *hud = [[JGProgressHUD alloc] init];
    hud.textLabel.text = errorDesc;
    hud.indicatorView = [[JGProgressHUDErrorIndicatorView alloc] init];

    [hud showInView:topMostController().view];
    [hud dismissAfterDelay:4.0];

    return hud;
}

// Media
+ (NSURL *)getPhotoUrl:(IGPhoto *)photo {
    if (!photo) return nil;

    // Get highest quality photo link
    NSURL *photoUrl = [photo imageURLForWidth:100000.00];

    return photoUrl;
}
+ (NSURL *)getPhotoUrlForMedia:(IGMedia *)media {
    if (!media) return nil;

    IGPhoto *photo = media.photo;

    return [SCIUtils getPhotoUrl:photo];
}
+ (NSURL *)getVideoUrl:(IGVideo *)video {
    if (!video) return nil;

    // The past (pre v398)
    if ([video respondsToSelector:@selector(sortedVideoURLsBySize)]) {
        NSArray<NSDictionary *> *sorted = [video sortedVideoURLsBySize];
        NSString *urlString = sorted.firstObject[@"url"];
        return urlString.length ? [NSURL URLWithString:urlString] : nil;
    }

    // The present (post v398)
    if ([video respondsToSelector:@selector(allVideoURLs)]) {
        return [[video allVideoURLs] anyObject];
    }

    return nil;
}
+ (NSURL *)getVideoUrlForMedia:(IGMedia *)media {
    if (!media) return nil;

    IGVideo *video = media.video;
    if (!video) return nil;

    return [SCIUtils getVideoUrl:video];
}

// AVPlayer cache-based video URL extraction
+ (NSURL *)getCachedVideoUrlForView:(UIView *)view {
    @try {
        if (!view) return nil;
        
        AVPlayer *player = [self _findAVPlayerInView:view depth:0 maxDepth:15];
        if (!player) return nil;
        
        AVPlayerItem *currentItem = player.currentItem;
        if (!currentItem) return nil;
        
        AVAsset *asset = currentItem.asset;
        if (!asset) return nil;
        
        if ([asset isKindOfClass:[AVURLAsset class]]) {
            NSURL *url = ((AVURLAsset *)asset).URL;
            if (url) {
                NSLog(@"[SCInsta] getCachedVideoUrlForView: Found video URL from AVPlayer: %@", url);
                return url;
            }
        }
        
        return nil;
    }
    @catch (NSException *exception) {
        NSLog(@"[SCInsta] getCachedVideoUrlForView: Exception: %@", exception);
        return nil;
    }
}

+ (AVPlayer *)_findAVPlayerInView:(UIView *)view depth:(int)depth maxDepth:(int)maxDepth {
    @try {
        if (!view || depth > maxDepth) return nil;
        
        // Check this view's layer
        CALayer *layer = view.layer;
        if (layer) {
            AVPlayer *player = [self _findAVPlayerInLayer:layer depth:0 maxDepth:5];
            if (player) return player;
        }
        
        // Recurse into subviews
        for (UIView *subview in view.subviews) {
            AVPlayer *player = [self _findAVPlayerInView:subview depth:depth + 1 maxDepth:maxDepth];
            if (player) return player;
        }
        
        return nil;
    }
    @catch (NSException *exception) {
        NSLog(@"[SCInsta] _findAVPlayerInView: Exception: %@", exception);
        return nil;
    }
}

+ (AVPlayer *)_findAVPlayerInLayer:(CALayer *)layer depth:(int)depth maxDepth:(int)maxDepth {
    @try {
        if (!layer || depth > maxDepth) return nil;
        
        if ([layer isKindOfClass:[AVPlayerLayer class]]) {
            AVPlayer *player = ((AVPlayerLayer *)layer).player;
            if (player) return player;
        }
        
        // Check sublayers
        for (CALayer *sublayer in layer.sublayers) {
            AVPlayer *player = [self _findAVPlayerInLayer:sublayer depth:depth + 1 maxDepth:maxDepth];
            if (player) return player;
        }
        
        return nil;
    }
    @catch (NSException *exception) {
        NSLog(@"[SCInsta] _findAVPlayerInLayer: Exception: %@", exception);
        return nil;
    }
}

+ (void)exportCachedVideoFromView:(UIView *)view completion:(void(^)(NSURL *fileURL, NSError *error))completion {
    @try {
        if (!view || !completion) {
            if (completion) completion(nil, nil);
            return;
        }
        
        // 1. Try to find AVPlayer in this view
        AVPlayer *player = [self _findAVPlayerInView:view depth:0 maxDepth:15];
        
        // 2. If not found, try parent controller's view
        if (!player) {
            UIViewController *parentVC = [self nearestViewControllerForView:view];
            if (parentVC && parentVC.view) {
                player = [self _findAVPlayerInView:parentVC.view depth:0 maxDepth:15];
            }
        }
        
        if (!player || !player.currentItem || !player.currentItem.asset) {
            NSLog(@"[SCInsta] exportCachedVideo: No AVPlayer/asset found, trying cache files...");
            
            // 3. Last resort: find recently cached video file on disk
            NSURL *cachedFile = [self _findRecentCachedVideoFile];
            if (cachedFile) {
                NSLog(@"[SCInsta] exportCachedVideo: Found cached file: %@", cachedFile);
                // Copy to temp so it's safe to share
                NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"SCInsta_%@.mp4", NSUUID.UUID.UUIDString]];
                NSURL *tempURL = [NSURL fileURLWithPath:tempPath];
                NSError *copyErr;
                [[NSFileManager defaultManager] copyItemAtURL:cachedFile toURL:tempURL error:&copyErr];
                if (!copyErr) {
                    completion(tempURL, nil);
                    return;
                }
            }
            
            completion(nil, [self errorWithDescription:@"No video player found"]);
            return;
        }
        
        AVAsset *asset = player.currentItem.asset;
        NSLog(@"[SCInsta] exportCachedVideo: Found asset of type: %@", NSStringFromClass([asset class]));
        
        // Check if it's a simple AVURLAsset — if so, just use the URL directly
        if ([asset isKindOfClass:[AVURLAsset class]]) {
            NSURL *url = ((AVURLAsset *)asset).URL;
            if (url && [[NSFileManager defaultManager] fileExistsAtPath:url.path]) {
                // It's a local file, copy it
                NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                    [NSString stringWithFormat:@"SCInsta_%@.mp4", NSUUID.UUID.UUIDString]];
                NSURL *tempURL = [NSURL fileURLWithPath:tempPath];
                NSError *copyErr;
                [[NSFileManager defaultManager] copyItemAtURL:url toURL:tempURL error:&copyErr];
                if (!copyErr) {
                    NSLog(@"[SCInsta] exportCachedVideo: Copied local file: %@", tempURL);
                    completion(tempURL, nil);
                    return;
                }
            }
            // If it's a remote URL, still try export
        }
        
        // Export the asset using AVAssetExportSession
        NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
            [NSString stringWithFormat:@"SCInsta_%@.mp4", NSUUID.UUID.UUIDString]];
        NSURL *outputURL = [NSURL fileURLWithPath:tempPath];
        
        // Try passthrough first (fastest, no re-encoding)
        NSArray *presets = @[AVAssetExportPresetPassthrough, AVAssetExportPresetHighestQuality, AVAssetExportPresetMediumQuality];
        
        [self _tryExportAsset:asset withPresets:presets presetIndex:0 outputURL:outputURL completion:completion];
        
    }
    @catch (NSException *exception) {
        NSLog(@"[SCInsta] exportCachedVideo: Exception: %@", exception);
        if (completion) completion(nil, [self errorWithDescription:@"Export failed"]);
    }
}

+ (void)_tryExportAsset:(AVAsset *)asset withPresets:(NSArray *)presets presetIndex:(NSUInteger)index outputURL:(NSURL *)outputURL completion:(void(^)(NSURL *, NSError *))completion {
    if (index >= presets.count) {
        NSLog(@"[SCInsta] exportCachedVideo: All presets failed");
        completion(nil, [self errorWithDescription:@"Could not export video"]);
        return;
    }
    
    NSString *preset = presets[index];
    
    if (![AVAssetExportSession exportPresetsCompatibleWithAsset:asset].count) {
        NSLog(@"[SCInsta] exportCachedVideo: No compatible presets for asset");
        completion(nil, [self errorWithDescription:@"No compatible export presets"]);
        return;
    }
    
    AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:asset presetName:preset];
    if (!exportSession) {
        // Try next preset
        [self _tryExportAsset:asset withPresets:presets presetIndex:index + 1 outputURL:outputURL completion:completion];
        return;
    }
    
    // Use a unique path for each attempt
    NSString *attemptPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
        [NSString stringWithFormat:@"SCInsta_%@.mp4", NSUUID.UUID.UUIDString]];
    NSURL *attemptURL = [NSURL fileURLWithPath:attemptPath];
    
    exportSession.outputURL = attemptURL;
    exportSession.outputFileType = AVFileTypeMPEG4;
    exportSession.shouldOptimizeForNetworkUse = NO;
    
    NSLog(@"[SCInsta] exportCachedVideo: Trying preset: %@", preset);
    
    [exportSession exportAsynchronouslyWithCompletionHandler:^{
        switch (exportSession.status) {
            case AVAssetExportSessionStatusCompleted:
                NSLog(@"[SCInsta] exportCachedVideo: Export completed with preset: %@", preset);
                completion(attemptURL, nil);
                break;
            case AVAssetExportSessionStatusFailed:
                NSLog(@"[SCInsta] exportCachedVideo: Preset %@ failed: %@", preset, exportSession.error);
                // Try next preset
                [self _tryExportAsset:asset withPresets:presets presetIndex:index + 1 outputURL:outputURL completion:completion];
                break;
            case AVAssetExportSessionStatusCancelled:
                NSLog(@"[SCInsta] exportCachedVideo: Export cancelled");
                completion(nil, [self errorWithDescription:@"Export cancelled"]);
                break;
            default:
                [self _tryExportAsset:asset withPresets:presets presetIndex:index + 1 outputURL:outputURL completion:completion];
                break;
        }
    }];
}

+ (NSURL *)_findRecentCachedVideoFile {
    @try {
        NSFileManager *fm = [NSFileManager defaultManager];
        NSArray *searchDirs = @[
            NSTemporaryDirectory(),
            [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) firstObject]
        ];
        
        NSDate *mostRecentDate = nil;
        NSURL *mostRecentFile = nil;
        NSSet *videoExts = [NSSet setWithArray:@[@"mp4", @"mov", @"m4v"]];
        
        for (NSString *searchDir in searchDirs) {
            if (!searchDir) continue;
            
            NSDirectoryEnumerator *enumerator = [fm enumeratorAtURL:[NSURL fileURLWithPath:searchDir]
                includingPropertiesForKeys:@[NSURLContentModificationDateKey, NSURLFileSizeKey]
                options:0
                errorHandler:nil];
            
            for (NSURL *fileURL in enumerator) {
                NSString *ext = [[fileURL pathExtension] lowercaseString];
                if (![videoExts containsObject:ext]) continue;
                
                NSDate *modDate = nil;
                NSNumber *fileSize = nil;
                [fileURL getResourceValue:&modDate forKey:NSURLContentModificationDateKey error:nil];
                [fileURL getResourceValue:&fileSize forKey:NSURLFileSizeKey error:nil];
                
                // Only consider files modified in the last 30 seconds and > 100KB
                if (!modDate || !fileSize || fileSize.longLongValue < 100000) continue;
                NSTimeInterval age = [[NSDate date] timeIntervalSinceDate:modDate];
                if (age > 30) continue;
                
                if (!mostRecentDate || [modDate compare:mostRecentDate] == NSOrderedDescending) {
                    mostRecentDate = modDate;
                    mostRecentFile = fileURL;
                }
            }
        }
        
        return mostRecentFile;
    }
    @catch (NSException *exception) {
        NSLog(@"[SCInsta] _findRecentCachedVideoFile: Exception: %@", exception);
        return nil;
    }
}

// View Controllers
+ (UIViewController *)viewControllerForView:(UIView *)view {
    NSString *viewDelegate = @"viewDelegate";
    if ([view respondsToSelector:NSSelectorFromString(viewDelegate)]) {
        return [view valueForKey:viewDelegate];
    }

    return nil;
}

+ (UIViewController *)viewControllerForAncestralView:(UIView *)view {
    NSString *_viewControllerForAncestor = @"_viewControllerForAncestor";
    if ([view respondsToSelector:NSSelectorFromString(_viewControllerForAncestor)]) {
        return [view valueForKey:_viewControllerForAncestor];
    }

    return nil;
}

+ (UIViewController *)nearestViewControllerForView:(UIView *)view {
    return [self viewControllerForView:view] ?: [self viewControllerForAncestralView:view];
}

// Functions
+ (NSString *)IGVersionString {
    return [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleShortVersionString"];
};
+ (BOOL)isNotch {
    return [[[UIApplication sharedApplication] keyWindow] safeAreaInsets].bottom > 0;
};

+ (BOOL)existingLongPressGestureRecognizerForView:(UIView *)view {
    NSArray *allRecognizers = view.gestureRecognizers;

    for (UIGestureRecognizer *recognizer in allRecognizers) {
        if ([[recognizer class] isSubclassOfClass:[UILongPressGestureRecognizer class]]) {
            return YES;
        }
    }

    return NO;
}
+ (BOOL)showConfirmation:(void(^)(void))okHandler title:(NSString *)title {
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:title message:@"Are you sure?" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Yes" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        okHandler();
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"No!" style:UIAlertActionStyleCancel handler:nil]];

    [topMostController() presentViewController:alert animated:YES completion:nil];

    return nil;
};
+ (BOOL)showConfirmation:(void(^)(void))okHandler cancelHandler:(void(^)(void))cancelHandler title:(NSString *)title {
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:nil message:@"Are you sure?" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Yes" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        okHandler();
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"No!" style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        if (cancelHandler != nil) {
            cancelHandler();
        }
    }]];

    [topMostController() presentViewController:alert animated:YES completion:nil];

    return nil;
};
+ (BOOL)showConfirmation:(void(^)(void))okHandler {
    return [self showConfirmation:okHandler title:nil];
};
+ (BOOL)showConfirmation:(void(^)(void))okHandler cancelHandler:(void(^)(void))cancelHandler {
    return [self showConfirmation:okHandler cancelHandler:cancelHandler title:nil];
}
+ (void)showRestartConfirmation {
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Restart required" message:@"You must restart the app to apply this change" preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"Restart" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        exit(0);
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"Later" style:UIAlertActionStyleCancel handler:nil]];

    [topMostController() presentViewController:alert animated:YES completion:nil];
};
+ (void)prepareAlertPopoverIfNeeded:(UIAlertController*)alert inView:(UIView*)view {
    if (alert.popoverPresentationController) {
        // UIAlertController is a popover on iPad. Display it in the center of a view.
        alert.popoverPresentationController.sourceView = view;
        alert.popoverPresentationController.sourceRect = CGRectMake(view.bounds.size.width / 2.0, view.bounds.size.height / 2.0, 1.0, 1.0);
        alert.popoverPresentationController.permittedArrowDirections = 0;
    }
};

// Math
+ (NSUInteger)decimalPlacesInDouble:(double)value {
    NSNumberFormatter *formatter = [[NSNumberFormatter alloc] init];
    [formatter setNumberStyle:NSNumberFormatterDecimalStyle];
    [formatter setMaximumFractionDigits:15]; // Allow enough digits for double precision
    [formatter setMinimumFractionDigits:0];
    [formatter setDecimalSeparator:@"."]; // Force dot for internal logic, then respect locale for final display if needed

    NSString *stringValue = [formatter stringFromNumber:@(value)];

    // Find decimal separator
    NSRange decimalRange = [stringValue rangeOfString:formatter.decimalSeparator];

    if (decimalRange.location == NSNotFound) {
        return 0;
    } else {
        return stringValue.length - (decimalRange.location + decimalRange.length);
    }
}

@end