#import "../../InstagramHeaders.h"
#import "../../Manager.h"
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

    if ([SCIManager getBoolPref:@"dw_feed_posts"]) {
        [self addLongPressGestureRecognizer];
    }

    return;
}
%new - (void)addLongPressGestureRecognizer {
    NSLog(@"[SCInsta] Adding feed photo download long press gesture recognizer");

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = [SCIManager getDoublePref:@"dw_finger_duration"];
    longPress.numberOfTouchesRequired = [SCIManager getDoublePref:@"dw_finger_count"];

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

    if ([SCIManager getBoolPref:@"dw_feed_posts"]) {
        [self addLongPressGestureRecognizer];
    }

    return;
}
%new - (void)addLongPressGestureRecognizer {
    NSLog(@"[SCInsta] Adding feed video download long press gesture recognizer");

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = [SCIManager getDoublePref:@"dw_finger_duration"];
    longPress.numberOfTouchesRequired = 2; // 2 fingers for feed videos

    [self addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    @try {
        // Use the same simple cache-based approach that works for Reels
        NSURL *videoUrl = [SCIUtils getCachedVideoUrlForView:self];
        
        // If not found in direct subviews, search parent controller's view hierarchy
        if (!videoUrl) {
            UIViewController *parentVC = [SCIUtils nearestViewControllerForView:self];
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
    } @catch (NSException *exception) {
        NSLog(@"[SCInsta] Crash in Feed video download: %@", exception);
        [SCIUtils showErrorHUDWithDescription:@"Download crashed - check logs"];
    }
}
%end


/* * Reels * */

// Download reels (photos)
%hook IGSundialViewerPhotoView
- (void)didMoveToSuperview {
    %orig;

    if ([SCIManager getBoolPref:@"dw_reels"]) {
        [self addLongPressGestureRecognizer];
    }

    return;
}
%new - (void)addLongPressGestureRecognizer {
    NSLog(@"[SCInsta] Adding reels photo download long press gesture recognizer");

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = [SCIManager getDoublePref:@"dw_finger_duration"];
    longPress.numberOfTouchesRequired = [SCIManager getDoublePref:@"dw_finger_count"];

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

    if ([SCIManager getBoolPref:@"dw_reels"]) {
        [self addLongPressGestureRecognizer];
    }

    return;
}
%new - (void)addLongPressGestureRecognizer {
    NSLog(@"[SCInsta] Adding reels video download long press gesture recognizer");

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = [SCIManager getDoublePref:@"dw_finger_duration"];
    longPress.numberOfTouchesRequired = [SCIManager getDoublePref:@"dw_finger_count"];

    [self addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;
    
    @try {
        if (![self respondsToSelector:@selector(video)]) {
            [SCIUtils showErrorHUDWithDescription:@"Error: Reel media not found"];
            return;
        }

        // 1. Try Primary Extraction (Ivar/Method)
        NSURL *videoUrl = [SCIUtils getVideoUrlForMedia:self.video];
        
        // 2. Try Cache Fallback if primary failed
        if (!videoUrl) {
            NSLog(@"[SCInsta] Primary extraction failed. Trying cache...");
            videoUrl = [SCIUtils getCachedVideoUrlForView:self];
        }

        if (!videoUrl) {
            [SCIUtils showErrorHUDWithDescription:@"Could not extract video URL"];
            return;
        }

        initDownloaders();
        [videoDownloadDelegate downloadFileWithURL:videoUrl
                                     fileExtension:@"mp4"
                                          hudLabel:nil];
    } @catch (NSException *exception) {
        NSLog(@"[SCInsta] Crash in Reel download: %@", exception);
        [SCIUtils showErrorHUDWithDescription:@"Download crashed - check logs"];
    }
}
%end


/* * Stories * */

// Download story (images)
%hook IGStoryPhotoView
- (void)didMoveToSuperview {
    %orig;

    if ([SCIManager getBoolPref:@"dw_story"]) {
        [self addLongPressGestureRecognizer];
    }

    return;
}
%new - (void)addLongPressGestureRecognizer {
    NSLog(@"[SCInsta] Adding story photo download long press gesture recognizer");

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = [SCIManager getDoublePref:@"dw_finger_duration"];
    longPress.numberOfTouchesRequired = [SCIManager getDoublePref:@"dw_finger_count"];

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
%hook IGStoryVideoView
- (void)didMoveToSuperview {
    %orig;

    if ([SCIManager getBoolPref:@"dw_story"]) {
        [self addLongPressGestureRecognizer];
    }

    return;
}
%new - (void)addLongPressGestureRecognizer {
    //NSLog(@"[SCInsta] Adding story video download long press gesture recognizer");

    UILongPressGestureRecognizer *longPress = [[UILongPressGestureRecognizer alloc] initWithTarget:self action:@selector(handleLongPress:)];
    longPress.minimumPressDuration = [SCIManager getDoublePref:@"dw_finger_duration"];
    longPress.numberOfTouchesRequired = 3; // 3 fingers for story videos (2 fingers pauses)

    [self addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    @try {
        // Use the same simple cache-based approach that works for Reels
        NSURL *videoUrl = [SCIUtils getCachedVideoUrlForView:self];
        
        // If not found in direct subviews, search parent controller's view hierarchy
        if (!videoUrl) {
            UIViewController *parentVC = [SCIUtils nearestViewControllerForView:self];
            if (parentVC) {
                videoUrl = [SCIUtils getCachedVideoUrlForView:parentVC.view];
            }
        }

        if (!videoUrl) {
            [SCIUtils showErrorHUDWithDescription:@"Could not extract video URL from story"];
            return;
        }

        initDownloaders();
        [videoDownloadDelegate downloadFileWithURL:videoUrl
                                     fileExtension:@"mp4"
                                          hudLabel:nil];
    } @catch (NSException *exception) {
        NSLog(@"[SCInsta] Crash in Story download: %@", exception);
        [SCIUtils showErrorHUDWithDescription:@"Download crashed - check logs"];
    }
}
%end


/* * Profile pictures * */

%hook IGProfilePictureImageView
- (void)didMoveToSuperview {
    %orig;

    if ([SCIManager getBoolPref:@"save_profile"]) {
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

    IGImageRequest *_imageRequest = MSHookIvar<IGImageRequest *>(self, "_imageRequest");
    if (!_imageRequest) return;
    
    NSURL *imageUrl = [_imageRequest url];
    if (!imageUrl) return;

    // Download image & preview in quick look
    initDownloaders();
    [imageDownloadDelegate downloadFileWithURL:imageUrl
                                 fileExtension:[[imageUrl lastPathComponent] pathExtension]
                                      hudLabel:@"Loading"];
}
%end