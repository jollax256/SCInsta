#import <AVFoundation/AVFoundation.h>
#import "../../InstagramHeaders.h"
#import "../../Utils.h"
#import "../../Downloader/Download.h"

static SCIDownloadDelegate *imageDownloadDelegate;
static SCIDownloadDelegate *videoDownloadDelegate;

static void initDownloaders () {
    // Init downloaders only once
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        imageDownloadDelegate = [[SCIDownloadDelegate alloc] initWithAction:quickLook showProgress:NO];
        videoDownloadDelegate = [[SCIDownloadDelegate alloc] initWithAction:share showProgress:YES];
    });
}

// ─────────────────────────────────────────────
// Helper: safely extract a URL from an AVPlayer
// ─────────────────────────────────────────────
static NSURL *sciURLFromPlayer(AVPlayer *player) {
    if (!player) return nil;
    AVPlayerItem *item = player.currentItem;
    if (!item) return nil;
    AVAsset *asset = item.asset;
    if (![asset isKindOfClass:[AVURLAsset class]]) return nil;
    NSURL *url = ((AVURLAsset *)asset).URL;
    if (!url || url.absoluteString.length == 0) return nil;
    // Skip HLS manifests — NSURLSession can't download them as video files.
    // The structured API fallback will provide a direct .mp4 CDN link instead.
    NSString *pathExt = url.path.pathExtension.lowercaseString;
    if ([pathExt isEqualToString:@"m3u8"] || [pathExt isEqualToString:@"m3u"]) {
        NSLog(@"[SCInsta] sciURLFromPlayer: skipping HLS manifest URL");
        return nil;
    }
    return url;
}

// ─────────────────────────────────────────────
// Helper: recursively walk a CALayer tree to
// find any AVPlayerLayer with a downloadable URL.
// ─────────────────────────────────────────────
static NSURL *sciSearchLayerTree(CALayer *root, NSUInteger depth) {
    if (!root || depth > 20) return nil;
    @try {
        if ([root isKindOfClass:NSClassFromString(@"AVPlayerLayer")]) {
            AVPlayer *player = [root valueForKey:@"player"];
            NSURL *url = sciURLFromPlayer(player);
            if (url) return url;
        }
        NSArray *sublayers = [root.sublayers copy];
        for (CALayer *sub in sublayers) {
            NSURL *url = sciSearchLayerTree(sub, depth + 1);
            if (url) return url;
        }
    } @catch (NSException *e) {}
    return nil;
}

// ─────────────────────────────────────────────
// Helper: find downloadable URL from all windows
// ─────────────────────────────────────────────
static NSURL *sciGetPlayingVideoURLFromWindows(void) {
    @try {
        NSArray<UIWindow *> *windows = [UIApplication sharedApplication].windows;
        for (UIWindow *window in [windows copy]) {
            if (!window || window.isHidden) continue;
            NSURL *url = sciSearchLayerTree(window.layer, 0);
            if (url) return url;
        }
    } @catch (NSException *e) {
        NSLog(@"[SCInsta] sciGetPlayingVideoURLFromWindows exception: %@", e);
    }
    return nil;
}

// ─────────────────────────────────────────────
// Helper: find the AVPlayer itself (even if URL
// is HLS/m3u8 — needed for export fallback).
// ─────────────────────────────────────────────
static AVPlayer *sciFindPlayerInLayerTree(CALayer *root, NSUInteger depth) {
    if (!root || depth > 20) return nil;
    @try {
        if ([root isKindOfClass:NSClassFromString(@"AVPlayerLayer")]) {
            AVPlayer *player = [root valueForKey:@"player"];
            if (player && player.currentItem) return player;
        }
        NSArray *sublayers = [root.sublayers copy];
        for (CALayer *sub in sublayers) {
            AVPlayer *found = sciFindPlayerInLayerTree(sub, depth + 1);
            if (found) return found;
        }
    } @catch (NSException *e) {}
    return nil;
}

// Probe a single object's ivars for an AVPlayer instance
static AVPlayer *sciProbeObjForPlayer(id obj) {
    if (!obj) return nil;
    NSArray *names = @[@"_player", @"_avPlayer", @"_videoPlayer",
                       @"_statefulVideoPlayer", @"_mediaPlayer",
                       @"_avPlayerView", @"_videoPlayerView"];
    for (NSString *name in names) {
        @try {
            id val = [SCIUtils getIvarForObj:obj name:[name UTF8String]];
            if (!val) continue;
            if ([val isKindOfClass:[AVPlayer class]]) {
                AVPlayer *p = (AVPlayer *)val;
                if (p.currentItem) return p;
            }
            // The ivar might be a wrapper that has a .player or .avPlayer
            NSArray *subSels = @[@"player", @"avPlayer"];
            for (NSString *s in subSels) {
                if ([val respondsToSelector:NSSelectorFromString(s)]) {
                    id sub = [val valueForKey:s];
                    if ([sub isKindOfClass:[AVPlayer class]] && ((AVPlayer *)sub).currentItem)
                        return (AVPlayer *)sub;
                }
            }
        } @catch (...) {}
    }
    return nil;
}

// Walk the subview tree (breadth-first, bounded) looking for an AVPlayer
static AVPlayer *sciFindPlayerInViewTree(UIView *root, int depth) {
    if (!root || depth > 10) return nil;
    AVPlayer *p = sciProbeObjForPlayer(root);
    if (p) return p;
    for (UIView *sub in [root.subviews copy]) {
        p = sciFindPlayerInViewTree(sub, depth + 1);
        if (p) return p;
    }
    return nil;
}

static AVPlayer *sciFindAnyPlayingPlayer(void) {
    @try {
        NSArray<UIWindow *> *windows = [UIApplication sharedApplication].windows;
        for (UIWindow *window in [windows copy]) {
            if (!window || window.isHidden) continue;
            // 1. Layer tree scan (AVPlayerLayer)
            AVPlayer *p = sciFindPlayerInLayerTree(window.layer, 0);
            if (p) return p;
            // 2. View ivar scan (stateful players, wrappers)
            p = sciFindPlayerInViewTree(window, 0);
            if (p) return p;
        }
    } @catch (NSException *e) {}
    return nil;
}

// ─────────────────────────────────────────────
// Helper: export the currently-playing video
// (works for HLS/m3u8, partially cached, etc.)
// Uses AVAssetExportSession → writes mp4 to disk.
// Calls the download delegate on completion.
// ─────────────────────────────────────────────
static void sciExportPlayerVideo(SCIDownloadDelegate *delegate) {
    AVPlayer *player = sciFindAnyPlayingPlayer();
    if (!player || !player.currentItem) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [SCIUtils showErrorHUDWithDescription:@"No active video player found"];
        });
        return;
    }

    AVAsset *asset = player.currentItem.asset;
    if (!asset) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [SCIUtils showErrorHUDWithDescription:@"Player has no asset to export"];
        });
        return;
    }

    // Determine best export preset
    NSArray *compatible = [AVAssetExportSession exportPresetsCompatibleWithAsset:asset];
    NSString *preset = [compatible containsObject:AVAssetExportPresetHighestQuality]
                       ? AVAssetExportPresetHighestQuality
                       : AVAssetExportPresetPassthrough;

    AVAssetExportSession *exporter = [AVAssetExportSession exportSessionWithAsset:asset presetName:preset];
    if (!exporter) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [SCIUtils showErrorHUDWithDescription:@"Could not create video exporter"];
        });
        return;
    }

    // Write to a temp file
    NSString *tmpPath = [NSTemporaryDirectory() stringByAppendingPathComponent:
                         [NSString stringWithFormat:@"%@.mp4", NSUUID.UUID.UUIDString]];
    exporter.outputURL = [NSURL fileURLWithPath:tmpPath];
    exporter.outputFileType = AVFileTypeMPEG4;
    exporter.shouldOptimizeForNetworkUse = YES;

    NSLog(@"[SCInsta] Exporting video via AVAssetExportSession (preset: %@)...", preset);

    // Show an "Exporting" HUD while the export runs
    dispatch_async(dispatch_get_main_queue(), ^{
        JGProgressHUD *exportHUD = [[JGProgressHUD alloc] init];
        exportHUD.textLabel.text = @"Exporting video...";
        exportHUD.interactionType = JGProgressHUDInteractionTypeBlockNoTouches;
        [exportHUD showInView:topMostController().view];

        [exporter exportAsynchronouslyWithCompletionHandler:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                [exportHUD dismiss];

                switch (exporter.status) {
                    case AVAssetExportSessionStatusCompleted: {
                        NSLog(@"[SCInsta] Export completed: %@", tmpPath);
                        // Hand the exported file to the standard download flow
                        // (this will show its own HUD, copy to cache, then share/preview)
                        [delegate downloadFileWithURL:[NSURL fileURLWithPath:tmpPath]
                                        fileExtension:@"mp4"
                                             hudLabel:@"Saving..."];
                        break;
                    }
                    case AVAssetExportSessionStatusFailed: {
                        NSString *errDesc = exporter.error.localizedDescription ?: @"unknown error";
                        NSLog(@"[SCInsta] Export failed: %@", errDesc);
                        [SCIUtils showErrorHUDWithDescription:
                         [NSString stringWithFormat:@"Export failed: %@", errDesc]];
                        break;
                    }
                    case AVAssetExportSessionStatusCancelled:
                        NSLog(@"[SCInsta] Export cancelled");
                        break;
                    default:
                        break;
                }
            });
        }];
    });
}

// ─────────────────────────────────────────────
// Helper: check a single view's ivar slots for
// an AVPlayer (used as secondary probe).
// ─────────────────────────────────────────────
static NSURL *sciProbeViewIvarsForPlayerURL(UIView *view) {
    if (!view) return nil;
    @try {
        NSArray *ivarNames = @[@"_player", @"_avPlayer", @"_videoPlayer",
                               @"_statefulVideoPlayer", @"_videoPlayerView",
                               @"_mediaPlayer", @"_avPlayerView"];
        for (NSString *ivarName in ivarNames) {
            id playerObj = [SCIUtils getIvarForObj:view name:[ivarName UTF8String]];
            if (!playerObj) continue;

            if ([playerObj isKindOfClass:[AVPlayer class]]) {
                NSURL *url = sciURLFromPlayer((AVPlayer *)playerObj);
                if (url) return url;
                continue;
            }
            if ([playerObj respondsToSelector:@selector(player)]) {
                id p = [playerObj performSelector:@selector(player)];
                if ([p isKindOfClass:[AVPlayer class]]) {
                    NSURL *url = sciURLFromPlayer((AVPlayer *)p);
                    if (url) return url;
                }
            }
            if ([playerObj respondsToSelector:@selector(avPlayer)]) {
                id p = [playerObj performSelector:@selector(avPlayer)];
                if ([p isKindOfClass:[AVPlayer class]]) {
                    NSURL *url = sciURLFromPlayer((AVPlayer *)p);
                    if (url) return url;
                }
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[SCInsta] sciProbeViewIvarsForPlayerURL exception: %@", e);
    }
    return nil;
}

// ─────────────────────────────────────────────
// Helper: video URL extractor with diagnostics.
// Populates *outDiag with a human-readable trace
// of what was tried and why each step failed.
// ─────────────────────────────────────────────
static NSURL *sciGetVideoURL(id media, UIView *hostView, NSString **outDiag) {
    NSMutableArray *diag = [NSMutableArray array];
    NSURL *url = nil;

    // ── Step 1: Structured IG API (most reliable — includes _videoVersionDictionaries) ──
    @try {
        // 1a. If media has a .video property, get the IGVideo and extract URLs
        if (media && [media respondsToSelector:@selector(video)]) {
            IGVideo *video = [media performSelector:@selector(video)];
            if (video) {
                url = [SCIUtils getVideoUrl:video];
                if (url) {
                    NSLog(@"[SCInsta] sciGetVideoURL: structured API (video selector)");
                    return url;
                }
                [diag addObject:@"API: .video exists but no URLs"];
            } else {
                [diag addObject:@"API: .video returned nil"];
            }
        }

        // 1b. If the media object IS an IGVideo, use it directly
        if (media && [media isKindOfClass:NSClassFromString(@"IGVideo")]) {
            url = [SCIUtils getVideoUrl:(IGVideo *)media];
            if (url) {
                NSLog(@"[SCInsta] sciGetVideoURL: structured API (IGVideo cast)");
                return url;
            }
            [diag addObject:@"API: IGVideo cast but no URLs"];
        }

        // 1c. Try getVideoUrlForMedia if it's IGMedia
        if (media && [media isKindOfClass:NSClassFromString(@"IGMedia")]) {
            url = [SCIUtils getVideoUrlForMedia:(IGMedia *)media];
            if (url) {
                NSLog(@"[SCInsta] sciGetVideoURL: structured API (getVideoUrlForMedia)");
                return url;
            }
        }

        // 1d. Media has no video selector
        if (media && ![media respondsToSelector:@selector(video)] && ![media isKindOfClass:NSClassFromString(@"IGVideo")]) {
            [diag addObject:[NSString stringWithFormat:@"API: media (%@) has no video selector",
                             NSStringFromClass([media class])]];
        }
        if (!media) {
            [diag addObject:@"API: media object is nil"];
        }
    } @catch (NSException *e) {
        [diag addObject:[NSString stringWithFormat:@"API crash: %@", e.reason ?: @"unknown"]];
    }

    // ── Step 2: Scan the full layer tree of all windows for AVPlayerLayer ──
    url = sciGetPlayingVideoURLFromWindows();
    if (url) {
        NSLog(@"[SCInsta] sciGetVideoURL: found via window layer scan");
        return url;
    }
    AVPlayer *activePlayer = sciFindAnyPlayingPlayer();
    if (activePlayer) {
        [diag addObject:@"Layer: player found but URL not downloadable (HLS?)"];
    } else {
        [diag addObject:@"Layer: no AVPlayerLayer in any window"];
    }

    // ── Step 3: Ivar probe on the gesture view + up to 8 ancestors ──
    if (hostView) {
        @try {
            UIView *candidate = hostView;
            for (int i = 0; i < 8 && candidate; i++) {
                url = sciProbeViewIvarsForPlayerURL(candidate);
                if (url) {
                    NSLog(@"[SCInsta] sciGetVideoURL: found via ivar probe (depth %d)", i);
                    return url;
                }
                candidate = candidate.superview;
            }
            [diag addObject:@"Ivar probe: no player ivars in 8 ancestors"];
        } @catch (NSException *e) {
            [diag addObject:[NSString stringWithFormat:@"Ivar probe crash: %@", e.reason ?: @"unknown"]];
        }
    } else {
        [diag addObject:@"Ivar probe: no host view"];
    }

    NSString *diagString = [diag componentsJoinedByString:@" → "];
    NSLog(@"[SCInsta] sciGetVideoURL FAILED: %@", diagString);
    if (outDiag) *outDiag = diagString;
    return nil;
}

// ─────────────────────────────────────────────
// Helper: highest-quality image URL from IGPhoto
// ─────────────────────────────────────────────
static NSURL *sciGetBestPhotoURL(IGPhoto *photo) {
    if (!photo) return nil;
    @try {
        // Request an impossibly large width so Instagram returns the largest available version
        return [photo imageURLForWidth:100000.0];
    } @catch (NSException *e) {
        NSLog(@"[SCInsta] sciGetBestPhotoURL exception: %@", e);
    }
    return nil;
}

// ─────────────────────────────────────────────
// Helper: safely extract file extension from any
// URL, stripping CDN query strings first.
// Falls back to defaultExt if nothing found.
// ─────────────────────────────────────────────
static NSString *sciFileExtension(NSURL *url, NSString *defaultExt) {
    if (!url) return defaultExt;
    // Use NSURL's path (no query, no fragment) to get a clean extension
    NSString *ext = url.path.pathExtension;
    // Validate: must be 2-4 alpha chars
    if (ext.length >= 2 && ext.length <= 4) {
        NSCharacterSet *nonAlpha = [[NSCharacterSet letterCharacterSet] invertedSet];
        if ([ext rangeOfCharacterFromSet:nonAlpha].location == NSNotFound) {
            return ext.lowercaseString;
        }
    }
    return defaultExt;
}

// ─────────────────────────────────────────────
// Helper: add long-press only once per view
// ─────────────────────────────────────────────
static void sciAddLongPress(UIView *view, id target, SEL action) {
    if ([SCIUtils existingLongPressGestureRecognizerForView:view]) return;

    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:target action:action];
    lp.minimumPressDuration = [SCIUtils getDoublePref:@"dw_finger_duration"];
    lp.numberOfTouchesRequired = (NSUInteger)[SCIUtils getDoublePref:@"dw_finger_count"];
    [view addGestureRecognizer:lp];
}


/* ══════════════════════════════════════════════
   FEED — Photos
   ══════════════════════════════════════════════ */

%hook IGFeedPhotoView
- (void)didMoveToSuperview {
    %orig;
    if ([SCIUtils getBoolPref:@"dw_feed_posts"]) {
        [self addLongPressGestureRecognizer];
    }
}
%new - (void)addLongPressGestureRecognizer {
    sciAddLongPress(self, self, @selector(sci_handleLongPress:));
}
%new - (void)sci_handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    @try {
        IGPhoto *photo = nil;

        if ([self.delegate isKindOfClass:%c(IGFeedItemPhotoCell)]) {
            IGFeedItemPhotoCellConfiguration *cfg = MSHookIvar<IGFeedItemPhotoCellConfiguration *>(self.delegate, "_configuration");
            if (cfg) photo = MSHookIvar<IGPhoto *>(cfg, "_photo");
        } else if ([self.delegate isKindOfClass:%c(IGFeedItemPagePhotoCell)]) {
            IGFeedItemPagePhotoCell *cell = (IGFeedItemPagePhotoCell *)self.delegate;
            photo = cell.pagePhotoPost.photo;
        }

        NSURL *photoUrl = sciGetBestPhotoURL(photo);
        if (!photoUrl) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [SCIUtils showErrorHUDWithDescription:@"Could not get photo URL"];
            });
            return;
        }

        initDownloaders();
        [imageDownloadDelegate downloadFileWithURL:photoUrl
                                    fileExtension:[[photoUrl lastPathComponent] pathExtension] ?: @"jpg"
                                         hudLabel:nil];
    } @catch (NSException *e) {
        NSLog(@"[SCInsta] Feed photo download exception: %@", e);
        dispatch_async(dispatch_get_main_queue(), ^{
            [SCIUtils showErrorHUDWithDescription:@"Download failed, try again"];
        });
    }
}
%end


/* ══════════════════════════════════════════════
   FEED — Videos
   ══════════════════════════════════════════════ */

%hook IGModernFeedVideoCell.IGModernFeedVideoCell
- (void)didMoveToSuperview {
    %orig;
    if ([SCIUtils getBoolPref:@"dw_feed_posts"]) {
        [self addLongPressGestureRecognizer];
    }
}
%new - (void)addLongPressGestureRecognizer {
    sciAddLongPress(self, self, @selector(sci_handleLongPress:));
}
%new - (void)sci_handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    @try {
        id media = nil;
        @try { media = [self mediaCellFeedItem]; } @catch (...) {}

        NSString *diag = nil;
        NSURL *videoUrl = sciGetVideoURL(media, self, &diag);
        if (!videoUrl) {
            // Ultimate fallback: export from the active player (handles HLS/streaming)
            NSLog(@"[SCInsta] Feed video: no direct URL, trying export. Diag: %@", diag ?: @"none");
            initDownloaders();
            sciExportPlayerVideo(videoDownloadDelegate);
            return;
        }

        initDownloaders();
        NSString *ext = sciFileExtension(videoUrl, @"mp4");
        [videoDownloadDelegate downloadFileWithURL:videoUrl fileExtension:ext hudLabel:nil];
    } @catch (NSException *e) {
        NSLog(@"[SCInsta] Feed video download exception: %@", e);
        NSString *msg = [NSString stringWithFormat:@"Feed crash: %@", e.reason ?: @"unknown"];
        dispatch_async(dispatch_get_main_queue(), ^{
            [SCIUtils showErrorHUDWithDescription:msg];
        });
    }
}
%end


/* ══════════════════════════════════════════════
   REELS — Photos
   ══════════════════════════════════════════════ */

%hook IGSundialViewerPhotoView
- (void)didMoveToSuperview {
    %orig;
    if ([SCIUtils getBoolPref:@"dw_reels"]) {
        [self addLongPressGestureRecognizer];
    }
}
%new - (void)addLongPressGestureRecognizer {
    sciAddLongPress(self, self, @selector(sci_handleLongPress:));
}
%new - (void)sci_handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    @try {
        IGPhoto *photo = nil;
        @try { photo = MSHookIvar<IGPhoto *>(self, "_photo"); } @catch (...) {}

        NSURL *photoUrl = sciGetBestPhotoURL(photo);
        if (!photoUrl) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [SCIUtils showErrorHUDWithDescription:@"Could not get photo URL from reel"];
            });
            return;
        }

        initDownloaders();
        [imageDownloadDelegate downloadFileWithURL:photoUrl
                                    fileExtension:[[photoUrl lastPathComponent] pathExtension] ?: @"jpg"
                                         hudLabel:nil];
    } @catch (NSException *e) {
        NSLog(@"[SCInsta] Reel photo download exception: %@", e);
        dispatch_async(dispatch_get_main_queue(), ^{
            [SCIUtils showErrorHUDWithDescription:@"Download failed, try again"];
        });
    }
}
%end


/* ══════════════════════════════════════════════
   REELS — Videos
   ══════════════════════════════════════════════ */

// Safely extract the media/video object from an IGSundialViewerVideoCell.
// Instagram frequently renames or removes the .video property, so we probe
// multiple methods:
//   1. BHInstagram-style: walk view hierarchy for controls overlay → .media
//   2. Selector probing on the cell itself
//   3. Ivar probing on the cell itself
static id sciGetReelMedia(id cell) {
    if (!cell) return nil;

    // ── Method 1: BHInstagram delegate chain approach ──
    // Find the controls overlay view (or its Swift-mangled variants) in the
    // view's subview tree. These overlays reliably hold an IGMedia reference.
    @try {
        NSArray *overlayClassNames = @[
            @"IGSundialViewerControlsOverlayView",
            @"_TtC30IGSundialViewerControlsOverlay34IGSundialViewerControlsOverlayView",
            @"_TtC30IGSundialViewerControlsOverlay40IGSundialViewerModernControlsOverlayView"
        ];
        // Search subviews of the cell for controls overlay
        NSMutableArray *queue = [NSMutableArray arrayWithObject:cell];
        int visited = 0;
        while (queue.count > 0 && visited < 200) {
            UIView *current = queue.firstObject;
            [queue removeObjectAtIndex:0];
            visited++;
            for (NSString *className in overlayClassNames) {
                Class cls = NSClassFromString(className);
                if (cls && [current isKindOfClass:cls]) {
                    // Try .media property
                    if ([current respondsToSelector:@selector(media)]) {
                        id media = [(id)current performSelector:@selector(media)];
                        if (media) {
                            NSLog(@"[SCInsta] sciGetReelMedia: found via overlay %@.media", className);
                            return media;
                        }
                    }
                    // Try _media ivar
                    id media = [SCIUtils getIvarForObj:current name:"_media"];
                    if (media) {
                        NSLog(@"[SCInsta] sciGetReelMedia: found via overlay %@._media", className);
                        return media;
                    }
                }
            }
            // Also check delegate property for overlay controller with _media ivar
            if ([current respondsToSelector:@selector(delegate)]) {
                id delegate = [(id)current performSelector:@selector(delegate)];
                if (delegate) {
                    id media = [SCIUtils getIvarForObj:delegate name:"_media"];
                    if (media) {
                        NSLog(@"[SCInsta] sciGetReelMedia: found via delegate._media on %@",
                              NSStringFromClass([delegate class]));
                        return media;
                    }
                }
            }
            if ([current isKindOfClass:[UIView class]]) {
                [queue addObjectsFromArray:[(UIView *)current subviews]];
            }
        }
    } @catch (...) {}

    // ── Method 2: Selector probing on the cell itself ──
    NSArray *selectorNames = @[@"video", @"media", @"post", @"mediaItem",
                                @"currentMedia", @"feedItem", @"item",
                                @"videoMedia", @"reelMedia"];
    for (NSString *selName in selectorNames) {
        @try {
            SEL sel = NSSelectorFromString(selName);
            if ([cell respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                id result = [cell performSelector:sel];
#pragma clang diagnostic pop
                if (result) {
                    NSLog(@"[SCInsta] sciGetReelMedia: found via -%@", selName);
                    return result;
                }
            }
        } @catch (...) {}
    }

    // ── Method 3: Ivar probing on the cell ──
    NSArray *ivarNames = @[@"_video", @"_media", @"_post", @"_mediaItem",
                           @"_currentMedia", @"_feedItem", @"_item",
                           @"_videoMedia", @"_reelMedia"];
    for (NSString *ivarName in ivarNames) {
        @try {
            id val = [SCIUtils getIvarForObj:cell name:[ivarName UTF8String]];
            if (val) {
                NSLog(@"[SCInsta] sciGetReelMedia: found via ivar %@", ivarName);
                return val;
            }
        } @catch (...) {}
    }
    NSLog(@"[SCInsta] sciGetReelMedia: could not find media on %@", NSStringFromClass([cell class]));
    return nil;
}

%hook IGSundialViewerVideoCell
- (void)didMoveToSuperview {
    %orig;
    if ([SCIUtils getBoolPref:@"dw_reels"]) {
        [self addLongPressGestureRecognizer];
    }
}
%new - (void)addLongPressGestureRecognizer {
    sciAddLongPress(self, self, @selector(sci_handleLongPress:));
}
%new - (void)sci_handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    @try {
        id media = sciGetReelMedia(self);
        NSString *diag = nil;
        NSURL *videoUrl = sciGetVideoURL(media, self, &diag);
        if (!videoUrl) {
            NSLog(@"[SCInsta] Reel: no direct URL, trying export. Diag: %@", diag ?: @"none");
            initDownloaders();
            sciExportPlayerVideo(videoDownloadDelegate);
            return;
        }

        initDownloaders();
        NSString *ext = sciFileExtension(videoUrl, @"mp4");
        [videoDownloadDelegate downloadFileWithURL:videoUrl fileExtension:ext hudLabel:nil];
    } @catch (NSException *e) {
        NSLog(@"[SCInsta] Reel video download exception: %@", e);
        NSString *msg = [NSString stringWithFormat:@"Reel crash: %@", e.reason ?: @"unknown"];
        dispatch_async(dispatch_get_main_queue(), ^{
            [SCIUtils showErrorHUDWithDescription:msg];
        });
    }
}
%end


/* ══════════════════════════════════════════════
   STORIES — Photos
   ══════════════════════════════════════════════ */

%hook IGStoryPhotoView
- (void)didMoveToSuperview {
    %orig;
    if ([SCIUtils getBoolPref:@"dw_story"]) {
        [self addLongPressGestureRecognizer];
    }
}
%new - (void)addLongPressGestureRecognizer {
    sciAddLongPress(self, self, @selector(sci_handleLongPress:));
}
%new - (void)sci_handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    @try {
        id item = nil;
        @try { item = [self item]; } @catch (...) {}

        NSURL *photoUrl = nil;
        if (item) {
            photoUrl = [SCIUtils getPhotoUrlForMedia:(IGMedia *)item];
        }

        // Fallback: try IGImageSpecifier from any IGImageView sub-view
        if (!photoUrl) {
            for (UIView *sub in self.subviews) {
                if ([sub isKindOfClass:%c(IGImageView)]) {
                    IGImageSpecifier *spec = ((IGImageView *)sub).imageSpecifier;
                    if (spec.url) { photoUrl = spec.url; break; }
                }
            }
        }

        if (!photoUrl) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [SCIUtils showErrorHUDWithDescription:@"Could not get photo URL from story"];
            });
            return;
        }

        initDownloaders();
        [imageDownloadDelegate downloadFileWithURL:photoUrl
                                    fileExtension:[[photoUrl lastPathComponent] pathExtension] ?: @"jpg"
                                         hudLabel:nil];
    } @catch (NSException *e) {
        NSLog(@"[SCInsta] Story photo download exception: %@", e);
        dispatch_async(dispatch_get_main_queue(), ^{
            [SCIUtils showErrorHUDWithDescription:@"Download failed, try again"];
        });
    }
}
%end


/* ══════════════════════════════════════════════
   STORIES — Videos (modern)
   ══════════════════════════════════════════════ */

// Safely extract a media/item object from a story view using multiple selectors/ivars.
static id sciGetStoryMedia(id view) {
    if (!view) return nil;
    NSArray *selectorNames = @[@"item", @"media", @"currentStoryItem",
                                @"storyItem", @"mediaItem", @"video"];
    for (NSString *selName in selectorNames) {
        @try {
            SEL sel = NSSelectorFromString(selName);
            if ([view respondsToSelector:sel]) {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                id result = [view performSelector:sel];
#pragma clang diagnostic pop
                if (result) return result;
            }
        } @catch (...) {}
    }
    NSArray *ivarNames = @[@"_item", @"_media", @"_currentStoryItem",
                           @"_storyItem", @"_mediaItem", @"_video"];
    for (NSString *ivarName in ivarNames) {
        @try {
            id val = [SCIUtils getIvarForObj:view name:[ivarName UTF8String]];
            if (val) return val;
        } @catch (...) {}
    }
    return nil;
}

%hook IGStoryModernVideoView
- (void)didMoveToSuperview {
    %orig;
    if ([SCIUtils getBoolPref:@"dw_story"]) {
        [self addLongPressGestureRecognizer];
    }
}
%new - (void)addLongPressGestureRecognizer {
    sciAddLongPress(self, self, @selector(sci_handleLongPress:));
}
%new - (void)sci_handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    @try {
        id media = sciGetStoryMedia(self);
        NSString *diag = nil;
        NSURL *videoUrl = sciGetVideoURL(media, self, &diag);
        if (!videoUrl) {
            NSLog(@"[SCInsta] Story (modern): no direct URL, trying export. Diag: %@", diag ?: @"none");
            initDownloaders();
            sciExportPlayerVideo(videoDownloadDelegate);
            return;
        }

        initDownloaders();
        NSString *ext = sciFileExtension(videoUrl, @"mp4");
        [videoDownloadDelegate downloadFileWithURL:videoUrl fileExtension:ext hudLabel:nil];
    } @catch (NSException *e) {
        NSLog(@"[SCInsta] Story (modern) video download exception: %@", e);
        NSString *msg = [NSString stringWithFormat:@"Story crash: %@", e.reason ?: @"unknown"];
        dispatch_async(dispatch_get_main_queue(), ^{
            [SCIUtils showErrorHUDWithDescription:msg];
        });
    }
}
%end


/* ══════════════════════════════════════════════
   STORIES — Videos (legacy)
   ══════════════════════════════════════════════ */

%hook IGStoryVideoView
- (void)didMoveToSuperview {
    %orig;
    if ([SCIUtils getBoolPref:@"dw_story"]) {
        [self addLongPressGestureRecognizer];
    }
}
%new - (void)addLongPressGestureRecognizer {
    sciAddLongPress(self, self, @selector(sci_handleLongPress:));
}
%new - (void)sci_handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    @try {
        NSURL *videoUrl = nil;
        NSString *diag = nil;

        // 1. Try sciGetVideoURL with safe media extraction
        id media = nil;
        @try {
            IGStoryFullscreenSectionController *captionDelegate = self.captionDelegate;
            if (captionDelegate) {
                media = captionDelegate.currentStoryItem;
            }
        } @catch (...) {}
        // Also try extracting from self using the safe helper
        if (!media) media = sciGetStoryMedia(self);

        if (media) {
            @try {
                videoUrl = sciGetVideoURL(media, self, &diag);
            } @catch (...) {}
        }

        // 2. If still nil, try window-level scan again with no media
        if (!videoUrl) {
            videoUrl = sciGetPlayingVideoURLFromWindows();
        }

        // 3. Fallback: direct messages visual message
        if (!videoUrl) {
            @try {
                id parentVC = [SCIUtils nearestViewControllerForView:self];
                if (parentVC && [parentVC isKindOfClass:%c(IGDirectVisualMessageViewerController)]) {
                    IGDirectVisualMessageViewerViewModeAwareDataSource *ds =
                        MSHookIvar<IGDirectVisualMessageViewerViewModeAwareDataSource *>(parentVC, "_dataSource");
                    if (ds) {
                        IGDirectVisualMessage *msg =
                            MSHookIvar<IGDirectVisualMessage *>(ds, "_currentMessage");
                        if (msg) {
                            IGVideo *rawVideo = (IGVideo *)[msg rawVideo];
                            videoUrl = [SCIUtils getVideoUrl:rawVideo];
                        }
                    }
                }
            } @catch (...) {}
        }

        if (!videoUrl) {
            NSLog(@"[SCInsta] Story (legacy): no direct URL, trying export. Diag: %@", diag ?: @"none");
            initDownloaders();
            sciExportPlayerVideo(videoDownloadDelegate);
            return;
        }

        initDownloaders();
        NSString *ext = sciFileExtension(videoUrl, @"mp4");
        [videoDownloadDelegate downloadFileWithURL:videoUrl fileExtension:ext hudLabel:nil];
    } @catch (NSException *e) {
        NSLog(@"[SCInsta] Story (legacy) video download exception: %@", e);
        NSString *msg = [NSString stringWithFormat:@"Story crash: %@", e.reason ?: @"unknown"];
        dispatch_async(dispatch_get_main_queue(), ^{
            [SCIUtils showErrorHUDWithDescription:msg];
        });
    }
}
%end


/* ══════════════════════════════════════════════
   PROFILE PICTURES
   ══════════════════════════════════════════════ */

%hook IGProfilePictureImageView
- (void)didMoveToSuperview {
    %orig;
    if ([SCIUtils getBoolPref:@"save_profile"]) {
        [self addLongPressGestureRecognizer];
    }
}
%new - (void)addLongPressGestureRecognizer {
    // Profile picture uses a 1-finger, default-duration long press
    if ([SCIUtils existingLongPressGestureRecognizerForView:self]) return;
    UILongPressGestureRecognizer *lp = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(sci_handleLongPress:)];
    [self addGestureRecognizer:lp];
}
%new - (void)sci_handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    @try {
        IGImageView *imgView = nil;
        @try { imgView = MSHookIvar<IGImageView *>(self, "_imageView"); } @catch (...) {}
        if (!imgView) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [SCIUtils showErrorHUDWithDescription:@"Could not get profile picture"];
            });
            return;
        }

        IGImageSpecifier *spec = imgView.imageSpecifier;
        NSURL *imageUrl = spec.url;
        if (!imageUrl) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [SCIUtils showErrorHUDWithDescription:@"Could not get profile picture URL"];
            });
            return;
        }

        initDownloaders();
        [imageDownloadDelegate downloadFileWithURL:imageUrl
                                    fileExtension:[[imageUrl lastPathComponent] pathExtension] ?: @"jpg"
                                         hudLabel:@"Loading"];
    } @catch (NSException *e) {
        NSLog(@"[SCInsta] Profile picture download exception: %@", e);
        dispatch_async(dispatch_get_main_queue(), ^{
            [SCIUtils showErrorHUDWithDescription:@"Download failed, try again"];
        });
    }
}
%end