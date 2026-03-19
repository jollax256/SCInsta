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
// Helper: extract URL from any AVPlayer-backed
// view that may already have the media cached.
// ─────────────────────────────────────────────
static NSURL *sciGetCachedVideoURLFromView(UIView *view) {
    @try {
        // Inline helper: safely extract URL from an AVPlayer
        NSURL *(^urlFromPlayer)(AVPlayer *) = ^NSURL *(AVPlayer *player) {
            if (!player) return nil;
            AVPlayerItem *item = player.currentItem;
            if (!item) return nil;
            AVAsset *asset = item.asset;
            if (![asset isKindOfClass:[AVURLAsset class]]) return nil;
            return ((AVURLAsset *)asset).URL;
        };

        // 1. Walk sublayers for AVPlayerLayer
        for (CALayer *layer in view.layer.sublayers) {
            if (![layer isKindOfClass:NSClassFromString(@"AVPlayerLayer")]) continue;
            AVPlayer *player = [layer valueForKey:@"player"];
            NSURL *url = urlFromPlayer(player);
            if (url) return url;
        }

        // 2. Try common Instagram ivar names for AVPlayer / player wrappers
        for (NSString *ivarName in @[@"_player", @"_avPlayer", @"_videoPlayer", @"_statefulVideoPlayer"]) {
            id playerObj = [SCIUtils getIvarForObj:view name:[ivarName UTF8String]];
            if (!playerObj) continue;

            AVPlayer *player = nil;
            if ([playerObj isKindOfClass:[AVPlayer class]]) {
                player = (AVPlayer *)playerObj;
            } else if ([playerObj respondsToSelector:@selector(player)]) {
                id p = [playerObj performSelector:@selector(player)];
                if ([p isKindOfClass:[AVPlayer class]]) player = p;
            }

            NSURL *url = urlFromPlayer(player);
            if (url) return url;
        }
    } @catch (NSException *e) {
        NSLog(@"[SCInsta] sciGetCachedVideoURLFromView exception: %@", e);
    }
    return nil;
}

// ─────────────────────────────────────────────
// Helper: video URL — always use the cached
// AVPlayer URL (already loaded by Instagram).
// ─────────────────────────────────────────────
static NSURL *sciGetVideoURL(id media, UIView *hostView) {
    // Always prefer the cached AVPlayer URL — it's what's already playing,
    // guaranteed to work, and avoids any structured-API breakage.
    if (hostView) {
        NSURL *url = sciGetCachedVideoURLFromView(hostView);
        if (url) {
            NSLog(@"[SCInsta] sciGetVideoURL: using cached AVPlayer URL");
            return url;
        }
    }

    // Fallback to structured API only if cache miss (e.g. view not yet rendered)
    @try {
        if ([media respondsToSelector:@selector(video)]) {
            IGVideo *video = [media performSelector:@selector(video)];
            return [SCIUtils getVideoUrl:video];
        } else if ([media isKindOfClass:NSClassFromString(@"IGVideo")]) {
            return [SCIUtils getVideoUrl:(IGVideo *)media];
        }
    } @catch (NSException *e) {
        NSLog(@"[SCInsta] sciGetVideoURL API fallback exception: %@", e);
    }

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

        NSURL *videoUrl = sciGetVideoURL(media, self);
        if (!videoUrl) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [SCIUtils showErrorHUDWithDescription:@"Could not get video URL from feed post"];
            });
            return;
        }

        initDownloaders();
        NSString *ext = [[videoUrl lastPathComponent] pathExtension] ?: @"mp4";
        [videoDownloadDelegate downloadFileWithURL:videoUrl fileExtension:ext hudLabel:nil];
    } @catch (NSException *e) {
        NSLog(@"[SCInsta] Feed video download exception: %@", e);
        dispatch_async(dispatch_get_main_queue(), ^{
            [SCIUtils showErrorHUDWithDescription:@"Download failed, try again"];
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
        // self.video is IGMedia
        NSURL *videoUrl = sciGetVideoURL(self.video, self);
        if (!videoUrl) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [SCIUtils showErrorHUDWithDescription:@"Could not get video URL from reel"];
            });
            return;
        }

        initDownloaders();
        NSString *ext = [[videoUrl lastPathComponent] pathExtension] ?: @"mp4";
        [videoDownloadDelegate downloadFileWithURL:videoUrl fileExtension:ext hudLabel:nil];
    } @catch (NSException *e) {
        NSLog(@"[SCInsta] Reel video download exception: %@", e);
        dispatch_async(dispatch_get_main_queue(), ^{
            [SCIUtils showErrorHUDWithDescription:@"Download failed, try again"];
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
        NSURL *videoUrl = sciGetVideoURL(self.item, self);
        if (!videoUrl) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [SCIUtils showErrorHUDWithDescription:@"Could not get video URL from story"];
            });
            return;
        }

        initDownloaders();
        NSString *ext = [[videoUrl lastPathComponent] pathExtension] ?: @"mp4";
        [videoDownloadDelegate downloadFileWithURL:videoUrl fileExtension:ext hudLabel:nil];
    } @catch (NSException *e) {
        NSLog(@"[SCInsta] Story (modern) video download exception: %@", e);
        dispatch_async(dispatch_get_main_queue(), ^{
            [SCIUtils showErrorHUDWithDescription:@"Download failed, try again"];
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

        // Try structured API via caption delegate (story)
        IGStoryFullscreenSectionController *captionDelegate = self.captionDelegate;
        if (captionDelegate) {
            @try {
                videoUrl = sciGetVideoURL(captionDelegate.currentStoryItem, self);
            } @catch (...) {}
        }

        // Fallback: direct messages visual message
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

        // Last resort: cached AVPlayer URL
        if (!videoUrl) {
            videoUrl = sciGetCachedVideoURLFromView(self);
        }

        if (!videoUrl) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [SCIUtils showErrorHUDWithDescription:@"Could not get video URL from story"];
            });
            return;
        }

        initDownloaders();
        NSString *ext = [[videoUrl lastPathComponent] pathExtension] ?: @"mp4";
        [videoDownloadDelegate downloadFileWithURL:videoUrl fileExtension:ext hudLabel:nil];
    } @catch (NSException *e) {
        NSLog(@"[SCInsta] Story (legacy) video download exception: %@", e);
        dispatch_async(dispatch_get_main_queue(), ^{
            [SCIUtils showErrorHUDWithDescription:@"Download failed, try again"];
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