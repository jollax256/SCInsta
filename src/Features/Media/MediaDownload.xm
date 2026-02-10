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
    longPress.numberOfTouchesRequired = [SCIManager getDoublePref:@"dw_finger_count"];

    [self addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    @try {
        // 1. Try Primary Extraction (same as Reels)
        NSURL *videoUrl = [SCIUtils getVideoUrlForMedia:[self mediaCellFeedItem]];
        
        // 2. Try Cache Fallback if primary failed
        if (!videoUrl) {
            videoUrl = [SCIUtils getCachedVideoUrlForView:self];
        }

        if (!videoUrl) {
            [SCIUtils showErrorHUDWithDescription:@"Could not extract video URL from post"];
            return;
        }

        initDownloaders();
        [videoDownloadDelegate downloadFileWithURL:videoUrl
                                     fileExtension:@"mp4"
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
    longPress.numberOfTouchesRequired = [SCIManager getDoublePref:@"dw_finger_count"];

    [self addGestureRecognizer:longPress];
}
%new - (void)handleLongPress:(UILongPressGestureRecognizer *)sender {
    if (sender.state != UIGestureRecognizerStateBegan) return;

    @try {
        NSURL *videoUrl = nil;

        // 1. Try Primary Extraction via captionDelegate (same pattern as Reels self.video)
        if ([self respondsToSelector:@selector(captionDelegate)]) {
            IGStoryFullscreenSectionController *controller = self.captionDelegate;
            if (controller && [controller respondsToSelector:@selector(currentStoryItem)]) {
                IGMedia *media = controller.currentStoryItem;
                if (media) {
                    videoUrl = [SCIUtils getVideoUrlForMedia:media];
                }
            }
        }

        // 2. Try Cache Fallback if primary failed (same as Reels)
        if (!videoUrl) {
            videoUrl = [SCIUtils getCachedVideoUrlForView:self];
        }

        // 3. Search parent controller's view hierarchy
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

// Download button on story overlay
%hook IGStoryViewerContainerView
%property (nonatomic, retain) UIButton *sciDownloadButton;

- (void)didMoveToSuperview {
    %orig;

    if (![SCIManager getBoolPref:@"dw_story"]) return;
    if (self.sciDownloadButton) return; // Already added

    // Create download button with SF Symbol
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    
    // Use SF Symbol for a clean download icon
    UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightMedium];
    UIImage *downloadImage = [UIImage systemImageNamed:@"arrow.down.circle.fill" withConfiguration:config];
    [btn setImage:downloadImage forState:UIControlStateNormal];
    btn.tintColor = [UIColor whiteColor];
    
    // Add shadow for visibility over varied backgrounds
    btn.layer.shadowColor = [UIColor blackColor].CGColor;
    btn.layer.shadowOffset = CGSizeMake(0, 1);
    btn.layer.shadowOpacity = 0.6;
    btn.layer.shadowRadius = 3.0;
    
    // Position: bottom-right corner, respecting safe area
    CGFloat bottomPadding = 90.0;
    if ([SCIUtils isNotch]) {
        bottomPadding = 120.0;
    }
    btn.frame = CGRectMake(self.frame.size.width - 50, self.frame.size.height - bottomPadding, 40, 40);
    btn.autoresizingMask = UIViewAutoresizingFlexibleLeftMargin | UIViewAutoresizingFlexibleTopMargin;
    
    [btn addTarget:self action:@selector(sciDownloadButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    
    [self addSubview:btn];
    self.sciDownloadButton = btn;
}

%new - (void)sciDownloadButtonTapped:(UIButton *)sender {
    NSLog(@"[SCInsta] Story download button tapped");
    
    initDownloaders();
    
    @try {
        id mediaView = nil;
        
        // Try to get mediaView property
        if ([self respondsToSelector:@selector(mediaView)]) {
            mediaView = self.mediaView;
        }
        
        // Fallback: search subviews for known media view types
        if (!mediaView) {
            for (UIView *subview in self.subviews) {
                if ([subview isKindOfClass:%c(IGStoryPhotoView)] || [subview isKindOfClass:%c(IGStoryVideoView)]) {
                    mediaView = subview;
                    break;
                }
                // Also search one level deeper
                for (UIView *deepSubview in subview.subviews) {
                    if ([deepSubview isKindOfClass:%c(IGStoryPhotoView)] || [deepSubview isKindOfClass:%c(IGStoryVideoView)]) {
                        mediaView = deepSubview;
                        break;
                    }
                }
                if (mediaView) break;
            }
        }
        
        if (!mediaView) {
            NSLog(@"[SCInsta] Could not find media view in story container");
            [SCIUtils showErrorHUDWithDescription:@"Could not find story media"];
            return;
        }
        
        // ===== PHOTO STORY =====
        if ([mediaView isKindOfClass:%c(IGStoryPhotoView)]) {
            NSLog(@"[SCInsta] Downloading story photo");
            
            NSURL *photoUrl = nil;
            
            // Method 1: via item (IGMedia)
            if ([mediaView respondsToSelector:@selector(item)]) {
                photoUrl = [SCIUtils getPhotoUrlForMedia:[mediaView item]];
            }
            
            // Method 2: via photoView.imageSpecifier.url
            if (!photoUrl) {
                @try {
                    IGImageProgressView *photoView = [mediaView valueForKey:@"photoView"];
                    if (photoView && photoView.imageSpecifier) {
                        photoUrl = photoView.imageSpecifier.url;
                    }
                } @catch (NSException *e) {
                    NSLog(@"[SCInsta] photoView fallback failed: %@", e);
                }
            }
            
            if (!photoUrl) {
                [SCIUtils showErrorHUDWithDescription:@"Could not extract photo URL from story"];
                return;
            }
            
            [imageDownloadDelegate downloadFileWithURL:photoUrl
                                         fileExtension:[[photoUrl lastPathComponent] pathExtension]
                                              hudLabel:nil];
        }
        // ===== VIDEO STORY =====
        else if ([mediaView isKindOfClass:%c(IGStoryVideoView)]) {
            NSLog(@"[SCInsta] Downloading story video");
            
            NSURL *videoUrl = nil;
            
            // Method 1: videoPlayer._video.allVideoURLs (haoict method)
            @try {
                id videoPlayer = [mediaView valueForKey:@"videoPlayer"];
                if (videoPlayer) {
                    IGVideo *video = MSHookIvar<IGVideo *>(videoPlayer, "_video");
                    if (video) {
                        videoUrl = [SCIUtils getVideoUrl:video];
                    }
                }
            } @catch (NSException *e) {
                NSLog(@"[SCInsta] videoPlayer method failed: %@", e);
            }
            
            // Method 2: captionDelegate.currentStoryItem
            if (!videoUrl) {
                @try {
                    if ([mediaView respondsToSelector:@selector(captionDelegate)]) {
                        IGStoryFullscreenSectionController *controller = [(IGStoryVideoView *)mediaView captionDelegate];
                        if (controller && [controller respondsToSelector:@selector(currentStoryItem)]) {
                            IGMedia *media = controller.currentStoryItem;
                            if (media) {
                                videoUrl = [SCIUtils getVideoUrlForMedia:media];
                            }
                        }
                    }
                } @catch (NSException *e) {
                    NSLog(@"[SCInsta] captionDelegate method failed: %@", e);
                }
            }
            
            // Method 3: Cache-based AVPlayer search on media view
            if (!videoUrl) {
                videoUrl = [SCIUtils getCachedVideoUrlForView:(UIView *)mediaView];
            }
            
            // Method 4: Cache-based AVPlayer search on parent controller view
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
            
            [videoDownloadDelegate downloadFileWithURL:videoUrl
                                         fileExtension:@"mp4"
                                              hudLabel:nil];
        }
        else {
            NSLog(@"[SCInsta] Unknown media view type: %@", NSStringFromClass([mediaView class]));
            [SCIUtils showErrorHUDWithDescription:@"Unknown story media type"];
        }
    } @catch (NSException *exception) {
        NSLog(@"[SCInsta] Crash in Story button download: %@", exception);
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