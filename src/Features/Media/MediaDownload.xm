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
    return ((AVURLAsset *)asset).URL;
}

// ─────────────────────────────────────────────
// Helper: check a single view's layer + ivars
// for an AVPlayer URL (non-recursive).
// ─────────────────────────────────────────────
static NSURL *sciProbeViewForPlayerURL(UIView *view) {
    if (!view) return nil;
    @try {
        // 1. Walk sublayers for AVPlayerLayer
        for (CALayer *layer in view.layer.sublayers) {
            if (![layer isKindOfClass:NSClassFromString(@"AVPlayerLayer")]) continue;
            AVPlayer *player = [layer valueForKey:@"player"];
            NSURL *url = sciURLFromPlayer(player);
            if (url) return url;
        }

        // 2. Try common Instagram ivar names for AVPlayer / player wrappers
        NSArray *ivarNames = @[@"_player", @"_avPlayer", @"_videoPlayer",
                               @"_statefulVideoPlayer", @"_videoPlayerView",
                               @"_mediaPlayer", @"_avPlayerView"];
        for (NSString *ivarName in ivarNames) {
            id playerObj = [SCIUtils getIvarForObj:view name:[ivarName UTF8String]];
            if (!playerObj) continue;

            // Direct AVPlayer
            if ([playerObj isKindOfClass:[AVPlayer class]]) {
                NSURL *url = sciURLFromPlayer((AVPlayer *)playerObj);
                if (url) return url;
                continue;
            }

            // Wrapper that exposes .player
            if ([playerObj respondsToSelector:@selector(player)]) {
                id p = [playerObj performSelector:@selector(player)];
                if ([p isKindOfClass:[AVPlayer class]]) {
                    NSURL *url = sciURLFromPlayer((AVPlayer *)p);
                    if (url) return url;
                }
            }

            // Wrapper that exposes .avPlayer
            if ([playerObj respondsToSelector:@selector(avPlayer)]) {
                id p = [playerObj performSelector:@selector(avPlayer)];
                if ([p isKindOfClass:[AVPlayer class]]) {
                    NSURL *url = sciURLFromPlayer((AVPlayer *)p);
                    if (url) return url;
                }
            }

            // If the wrapper itself is a UIView, probe its layers too
            if ([playerObj isKindOfClass:[UIView class]]) {
                for (CALayer *layer in ((UIView *)playerObj).layer.sublayers) {
                    if (![layer isKindOfClass:NSClassFromString(@"AVPlayerLayer")]) continue;
                    AVPlayer *player = [layer valueForKey:@"player"];
                    NSURL *url = sciURLFromPlayer(player);
                    if (url) return url;
                }
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[SCInsta] sciProbeViewForPlayerURL exception: %@", e);
    }
    return nil;
}

// ─────────────────────────────────────────────
// Helper: recursively walk ALL subviews to find
// any cached AVPlayer URL (BFS, max 8 levels).
// ─────────────────────────────────────────────
static NSURL *sciGetCachedVideoURLFromView(UIView *view) {
    if (!view) return nil;
    @try {
        // BFS through the view tree
        NSMutableArray<UIView *> *queue = [NSMutableArray arrayWithObject:view];
        NSUInteger head = 0;
        NSUInteger maxNodes = 150; // safety cap — Instagram views are deep but bounded

        while (head < queue.count && head < maxNodes) {
            UIView *current = queue[head++];
            if (!current) continue;

            NSURL *url = sciProbeViewForPlayerURL(current);
            if (url) return url;

            // Snapshot subviews to avoid mutation-during-enumeration
            NSArray<UIView *> *subs = [current.subviews copy];
            for (UIView *sub in subs) {
                if (sub) [queue addObject:sub];
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[SCInsta] sciGetCachedVideoURLFromView exception: %@", e);
    }
    return nil;
}

// ─────────────────────────────────────────────
// Helper: walk UP the view hierarchy to find
// a cached URL in parent/sibling views.
// ─────────────────────────────────────────────
static NSURL *sciGetCachedVideoURLFromViewAndParents(UIView *view) {
    if (!view) return nil;
    @try {
        // First try the view itself + all its children (deep BFS)
        NSURL *url = sciGetCachedVideoURLFromView(view);
        if (url) return url;

        // Walk up to 5 ancestors, probing each ancestor directly +
        // all siblings of the child we just came from (shallow probe only).
        UIView *lastChild = view;
        UIView *ancestor = view.superview;
        for (int i = 0; i < 5 && ancestor; i++) {
            // Direct probe on the ancestor itself
            url = sciProbeViewForPlayerURL(ancestor);
            if (url) return url;

            // Shallow-probe siblings of lastChild
            for (UIView *sibling in ancestor.subviews) {
                if (sibling == lastChild) continue; // skip the one we came from
                url = sciProbeViewForPlayerURL(sibling);
                if (url) return url;
            }

            lastChild = ancestor;
            ancestor = ancestor.superview;
        }
    } @catch (NSException *e) {
        NSLog(@"[SCInsta] sciGetCachedVideoURLFromViewAndParents exception: %@", e);
    }
    return nil;
}

// ─────────────────────────────────────────────
// Helper: video URL — always prefer the cached
// AVPlayer URL (already loaded by Instagram).
// ─────────────────────────────────────────────
static NSURL *sciGetVideoURL(id media, UIView *hostView) {
    // ALWAYS try cached AVPlayer URL first — it's the actual video playing,
    // guaranteed to work, and immune to Instagram API changes.
    if (hostView) {
        NSURL *url = sciGetCachedVideoURLFromViewAndParents(hostView);
        if (url) {
            NSLog(@"[SCInsta] sciGetVideoURL: using cached AVPlayer URL");
            return url;
        }
    }

    // Fallback to structured API only if cache miss (e.g. view not yet rendered)
    @try {
        if ([media respondsToSelector:@selector(video)]) {
            IGVideo *video = [media performSelector:@selector(video)];
            NSURL *url = [SCIUtils getVideoUrl:video];
            if (url) {
                NSLog(@"[SCInsta] sciGetVideoURL: using structured API fallback");
                return url;
            }
        }
        if ([media isKindOfClass:NSClassFromString(@"IGVideo")]) {
            NSURL *url = [SCIUtils getVideoUrl:(IGVideo *)media];
            if (url) {
                NSLog(@"[SCInsta] sciGetVideoURL: using IGVideo direct fallback");
                return url;
            }
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

        NSURL *videoUrl = sciGetVideoURL(media, self);
        if (!videoUrl) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [SCIUtils showErrorHUDWithDescription:@"Could not get video URL from feed post"];
            });
            return;
        }

        initDownloaders();
        NSString *ext = sciFileExtension(videoUrl, @"mp4");
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
        NSString *ext = sciFileExtension(videoUrl, @"mp4");
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
        NSString *ext = sciFileExtension(videoUrl, @"mp4");
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

        // 1. Cached URL via sciGetVideoURL (deep walk + parent walk + API fallback)
        IGStoryFullscreenSectionController *captionDelegate = self.captionDelegate;
        if (captionDelegate) {
            @try {
                videoUrl = sciGetVideoURL(captionDelegate.currentStoryItem, self);
            } @catch (...) {}
        }

        // 2. If still nil, try with self directly (no media object)
        if (!videoUrl) {
            videoUrl = sciGetCachedVideoURLFromViewAndParents(self);
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
            dispatch_async(dispatch_get_main_queue(), ^{
                [SCIUtils showErrorHUDWithDescription:@"Could not get video URL from story"];
            });
            return;
        }

        initDownloaders();
        NSString *ext = sciFileExtension(videoUrl, @"mp4");
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