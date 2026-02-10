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

/* * Feed * */

// Download feed images
%hook IGFeedPhotoView
- (void)didMoveToSuperview {
    %orig;

    if ([SCIUtils getBoolPref:@"dw_feed_posts"]) {
        [self addLongPressGestureRecognizer];
    }

    return;
}
%new - (void)addLongPressGestureRecognizer {
    NSLog(@"[SCInsta] Adding feed photo download long press gesture recognizer");

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = [SCIUtils getDoublePref:@"dw_finger_duration"];
    longPress.numberOfTouchesRequired = [SCIUtils getDoublePref:@"dw_finger_count"];

    [self addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    // Get photo instance
    IGPhoto *photo;

    if ([self.delegate isKindOfClass:%c(IGFeedItemPhotoCell)]) {
        IGFeedItemPhotoCellConfiguration *_configuration = MSHookIvar<IGFeedItemPhotoCellConfiguration *>(self.delegate, "_configuration");
        if (!_configuration) return;

        photo = MSHookIvar<IGPhoto *>(_configuration, "_photo");
    }
    else if ([self.delegate isKindOfClass:%c(IGFeedItemPagePhotoCell)]) {
        IGFeedItemPagePhotoCell *pagePhotoCell = self.delegate;

        photo = pagePhotoCell.pagePhotoPost.photo;
    }

    NSURL *photoUrl = [SCIUtils getPhotoUrl:photo];
    if (!photoUrl) {
        [SCIUtils showErrorHUDWithDescription:@"Could not extract photo url from post"];
        
        return;
    }

    // Download image & show in share menu
    initDownloaders();
    [imageDownloadDelegate downloadFileWithURL:photoUrl
                                 fileExtension:[[photoUrl lastPathComponent]pathExtension]
                                      hudLabel:nil];
}
%end

// Download feed videos
%hook IGModernFeedVideoCell.IGModernFeedVideoCell
- (void)didMoveToSuperview {
    %orig;

    if ([SCIUtils getBoolPref:@"dw_feed_posts"]) {
        [self addLongPressGestureRecognizer];
    }

    return;
}
%new - (void)addLongPressGestureRecognizer {
    NSLog(@"[SCInsta] Adding feed video download long press gesture recognizer");

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = [SCIUtils getDoublePref:@"dw_finger_duration"];
    longPress.numberOfTouchesRequired = [SCIUtils getDoublePref:@"dw_finger_count"];

    [self addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    @try {
        NSURL *videoUrl = nil;

        // 1. Try model-based extraction
        @try {
            videoUrl = [SCIUtils getVideoUrlForMedia:[self mediaCellFeedItem]];
        } @catch (NSException *e) {
            NSLog(@"[SCInsta] Feed video model extraction failed: %@", e);
        }

        // 2. Fallback: search own view hierarchy for AVPlayer
        if (!videoUrl) {
            NSLog(@"[SCInsta] Feed video: Model extraction returned nil, trying cache on self...");
            videoUrl = [SCIUtils getCachedVideoUrlForView:(UIView *)self];
        }

        // 3. Fallback: search parent controller's entire view hierarchy
        if (!videoUrl) {
            NSLog(@"[SCInsta] Feed video: Cache on self returned nil, trying parent controller...");
            UIViewController *parentVC = [SCIUtils nearestViewControllerForView:(UIView *)self];
            if (parentVC) {
                videoUrl = [SCIUtils getCachedVideoUrlForView:parentVC.view];
            }
        }

        if (!videoUrl) {
            [SCIUtils showErrorHUDWithDescription:@"Could not extract video url from post"];
            return;
        }

        // Download video & show in share menu
        initDownloaders();
        [videoDownloadDelegate downloadFileWithURL:videoUrl
                                     fileExtension:[[videoUrl lastPathComponent] pathExtension]
                                          hudLabel:nil];
    }
    @catch (NSException *exception) {
        NSLog(@"[SCInsta] Feed video download exception: %@", exception);
        [SCIUtils showErrorHUDWithDescription:@"An error occurred"];
    }
}
%end


/* * Reels * */

// Download reels (photos)
%hook IGSundialViewerPhotoView
- (void)didMoveToSuperview {
    %orig;

    if ([SCIUtils getBoolPref:@"dw_reels"]) {
        [self addLongPressGestureRecognizer];
    }

    return;
}
%new - (void)addLongPressGestureRecognizer {
    NSLog(@"[SCInsta] Adding reels photo download long press gesture recognizer");

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = [SCIUtils getDoublePref:@"dw_finger_duration"];
    longPress.numberOfTouchesRequired = [SCIUtils getDoublePref:@"dw_finger_count"];

    [self addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    IGPhoto *_photo = MSHookIvar<IGPhoto *>(self, "_photo");

    NSURL *photoUrl = [SCIUtils getPhotoUrl:_photo];
    if (!photoUrl) {
        [SCIUtils showErrorHUDWithDescription:@"Could not extract photo url from reel"];

        return;
    }

    // Download image & show in share menu
    initDownloaders();
    [imageDownloadDelegate downloadFileWithURL:photoUrl
                                 fileExtension:[[photoUrl lastPathComponent]pathExtension]
                                      hudLabel:nil];
}
%end

// Download reels (videos)
%hook IGSundialViewerVideoCell
- (void)didMoveToSuperview {
    %orig;

    if ([SCIUtils getBoolPref:@"dw_reels"]) {
        [self addLongPressGestureRecognizer];
    }

    return;
}
%new - (void)addLongPressGestureRecognizer {
    NSLog(@"[SCInsta] Adding reels video download long press gesture recognizer");

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = [SCIUtils getDoublePref:@"dw_finger_duration"];
    longPress.numberOfTouchesRequired = [SCIUtils getDoublePref:@"dw_finger_count"];

    [self addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    @try {
        NSURL *videoUrl = nil;

        // 1. Try model-based extraction
        @try {
            videoUrl = [SCIUtils getVideoUrlForMedia:self.video];
        } @catch (NSException *e) {
            NSLog(@"[SCInsta] Reel video model extraction failed: %@", e);
        }

        // 2. Fallback: search own view hierarchy for AVPlayer
        if (!videoUrl) {
            NSLog(@"[SCInsta] Reel video: Model extraction returned nil, trying cache on self...");
            videoUrl = [SCIUtils getCachedVideoUrlForView:(UIView *)self];
        }

        // 3. Fallback: search parent controller's entire view hierarchy
        if (!videoUrl) {
            NSLog(@"[SCInsta] Reel video: Cache on self returned nil, trying parent controller...");
            UIViewController *parentVC = [SCIUtils nearestViewControllerForView:(UIView *)self];
            if (parentVC) {
                videoUrl = [SCIUtils getCachedVideoUrlForView:parentVC.view];
            }
        }

        if (!videoUrl) {
            [SCIUtils showErrorHUDWithDescription:@"Could not extract video url from reel"];
            return;
        }

        // Download video & show in share menu
        initDownloaders();
        [videoDownloadDelegate downloadFileWithURL:videoUrl
                                     fileExtension:[[videoUrl lastPathComponent] pathExtension]
                                          hudLabel:nil];
    }
    @catch (NSException *exception) {
        NSLog(@"[SCInsta] Reel video download exception: %@", exception);
        [SCIUtils showErrorHUDWithDescription:@"An error occurred"];
    }
}
%end


/* * Stories * */

// Download story (images)
%hook IGStoryPhotoView
- (void)didMoveToSuperview {
    %orig;

    if ([SCIUtils getBoolPref:@"dw_story"]) {
        [self addLongPressGestureRecognizer];
    }

    return;
}
%new - (void)addLongPressGestureRecognizer {
    NSLog(@"[SCInsta] Adding story photo download long press gesture recognizer");

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = [SCIUtils getDoublePref:@"dw_finger_duration"];
    longPress.numberOfTouchesRequired = [SCIUtils getDoublePref:@"dw_finger_count"];

    [self addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    NSURL *photoUrl = [SCIUtils getPhotoUrlForMedia:[self item]];
    if (!photoUrl) {
        [SCIUtils showErrorHUDWithDescription:@"Could not extract photo url from story"];
        
        return;
    }

    // Download image & show in share menu
    initDownloaders();
    [imageDownloadDelegate downloadFileWithURL:photoUrl
                                 fileExtension:[[photoUrl lastPathComponent]pathExtension]
                                      hudLabel:nil];
}
%end

// Download story (videos)
%hook IGStoryModernVideoView
- (void)didMoveToSuperview {
    %orig;

    if ([SCIUtils getBoolPref:@"dw_story"]) {
        [self addLongPressGestureRecognizer];
    }

    return;
}
%new - (void)addLongPressGestureRecognizer {
    //NSLog(@"[SCInsta] Adding story video download long press gesture recognizer");

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = [SCIUtils getDoublePref:@"dw_finger_duration"];
    longPress.numberOfTouchesRequired = [SCIUtils getDoublePref:@"dw_finger_count"];

    [self addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    @try {
        NSURL *videoUrl = nil;

        // 1. Try model-based extraction
        @try {
            videoUrl = [SCIUtils getVideoUrlForMedia:self.item];
        } @catch (NSException *e) {
            NSLog(@"[SCInsta] Story modern video model extraction failed: %@", e);
        }

        // 2. Fallback: search own view hierarchy for AVPlayer
        if (!videoUrl) {
            NSLog(@"[SCInsta] Story modern video: Model extraction returned nil, trying cache on self...");
            videoUrl = [SCIUtils getCachedVideoUrlForView:(UIView *)self];
        }

        // 3. Fallback: search parent controller's entire view hierarchy
        if (!videoUrl) {
            NSLog(@"[SCInsta] Story modern video: Cache on self returned nil, trying parent controller...");
            UIViewController *parentVC = [SCIUtils nearestViewControllerForView:(UIView *)self];
            if (parentVC) {
                videoUrl = [SCIUtils getCachedVideoUrlForView:parentVC.view];
            }
        }

        if (!videoUrl) {
            [SCIUtils showErrorHUDWithDescription:@"Could not extract video url from story"];
            return;
        }

        // Download video & show in share menu
        initDownloaders();
        [videoDownloadDelegate downloadFileWithURL:videoUrl
                                     fileExtension:[[videoUrl lastPathComponent] pathExtension]
                                          hudLabel:nil];
    }
    @catch (NSException *exception) {
        NSLog(@"[SCInsta] Story modern video download exception: %@", exception);
        [SCIUtils showErrorHUDWithDescription:@"An error occurred"];
    }
}
%end

// Download story (videos, legacy)
%hook IGStoryVideoView
- (void)didMoveToSuperview {
    %orig;

    if ([SCIUtils getBoolPref:@"dw_story"]) {
        [self addLongPressGestureRecognizer];
    }

    return;
}
%new - (void)addLongPressGestureRecognizer {
    //NSLog(@"[SCInsta] Adding story video download long press gesture recognizer");

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = [SCIUtils getDoublePref:@"dw_finger_duration"];
    longPress.numberOfTouchesRequired = [SCIUtils getDoublePref:@"dw_finger_count"];

    [self addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    @try {
        NSURL *videoUrl = nil;

        // 1. Try model-based extraction (caption delegate or DM video)
        @try {
            IGStoryFullscreenSectionController *captionDelegate = self.captionDelegate;
            if (captionDelegate) {
                videoUrl = [SCIUtils getVideoUrlForMedia:captionDelegate.currentStoryItem];
            }
            else {
                // Direct messages video player
                id parentVC = [SCIUtils nearestViewControllerForView:self];
                if (parentVC && [parentVC isKindOfClass:%c(IGDirectVisualMessageViewerController)]) {
                    IGDirectVisualMessageViewerViewModeAwareDataSource *_dataSource = MSHookIvar<IGDirectVisualMessageViewerViewModeAwareDataSource *>(parentVC, "_dataSource");
                    if (_dataSource) {
                        IGDirectVisualMessage *_currentMessage = MSHookIvar<IGDirectVisualMessage *>(_dataSource, "_currentMessage");
                        if (_currentMessage) {
                            IGVideo *rawVideo = _currentMessage.rawVideo;
                            if (rawVideo) {
                                videoUrl = [SCIUtils getVideoUrl:rawVideo];
                            }
                        }
                    }
                }
            }
        } @catch (NSException *e) {
            NSLog(@"[SCInsta] Story legacy video model extraction failed: %@", e);
        }

        // 2. Fallback: search own view hierarchy for AVPlayer
        if (!videoUrl) {
            NSLog(@"[SCInsta] Story legacy video: Model extraction returned nil, trying cache on self...");
            videoUrl = [SCIUtils getCachedVideoUrlForView:self];
        }

        // 3. Fallback: search parent controller's entire view hierarchy
        if (!videoUrl) {
            NSLog(@"[SCInsta] Story legacy video: Cache on self returned nil, trying parent controller...");
            UIViewController *parentVC = [SCIUtils nearestViewControllerForView:self];
            if (parentVC) {
                videoUrl = [SCIUtils getCachedVideoUrlForView:parentVC.view];
            }
        }

        if (!videoUrl) {
            [SCIUtils showErrorHUDWithDescription:@"Could not extract video url from story"];
            return;
        }

        // Download video & show in share menu
        initDownloaders();
        [videoDownloadDelegate downloadFileWithURL:videoUrl
                                     fileExtension:[[videoUrl lastPathComponent] pathExtension]
                                          hudLabel:nil];
    }
    @catch (NSException *exception) {
        NSLog(@"[SCInsta] Story legacy video download exception: %@", exception);
        [SCIUtils showErrorHUDWithDescription:@"An error occurred"];
    }
}
%end


/* * Profile pictures * */

%hook IGProfilePictureImageView
- (void)didMoveToSuperview {
    %orig;

    if ([SCIUtils getBoolPref:@"save_profile"]) {
        [self addLongPressGestureRecognizer];
    }

    return;
}
%new - (void)addLongPressGestureRecognizer {
    NSLog(@"[SCInsta] Adding profile picture long press gesture recognizer");

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    [self addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    IGImageView *_imageView = MSHookIvar<IGImageView *>(self, "_imageView");
    if (!_imageView) return;
    
    IGImageSpecifier *imageSpecifier = _imageView.imageSpecifier;
    if (!imageSpecifier) return;

    NSURL *imageUrl = imageSpecifier.url;
    if (!imageUrl) return;

    // Download image & preview in quick look
    initDownloaders();
    [imageDownloadDelegate downloadFileWithURL:imageUrl
                                 fileExtension:[[imageUrl lastPathComponent] pathExtension]
                                      hudLabel:@"Loading"];
}
%end