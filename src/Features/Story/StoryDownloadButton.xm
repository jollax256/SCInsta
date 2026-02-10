#import "../../InstagramHeaders.h"
#import "../../Manager.h"
#import "../../Utils.h"
#import "../../Downloader/Download.h"

static SCIDownloadDelegate *videoDownloadDelegate;

static void initDownloader() {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        videoDownloadDelegate = [[SCIDownloadDelegate alloc] initWithAction:share showProgress:YES];
    });
}

// Add download button to story overlay
%hook IGStoryFullscreenOverlayView
%new
- (void)addStoryDownloadButton {
    // Check if button already exists
    UIButton *existingButton = (UIButton *)[self viewWithTag:99999];
    if (existingButton) return;
    
    // Create download button
    UIButton *downloadButton = [UIButton buttonWithType:UIButtonTypeSystem];
    downloadButton.tag = 99999;
    [downloadButton setTitle:@"⬇️ Download" forState:UIControlStateNormal];
    downloadButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [downloadButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    downloadButton.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.6];
    downloadButton.layer.cornerRadius = 8;
    downloadButton.layer.masksToBounds = YES;
    
    // Position button in top-right area
    downloadButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:downloadButton];
    
    [NSLayoutConstraint activateConstraints:@[
        [downloadButton.topAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.topAnchor constant:10],
        [downloadButton.trailingAnchor constraintEqualToAnchor:self.safeAreaLayoutGuide.trailingAnchor constant:-10],
        [downloadButton.widthAnchor constraintEqualToConstant:110],
        [downloadButton.heightAnchor constraintEqualToConstant:36]
    ]];
    
    [downloadButton addTarget:self action:@selector(handleStoryDownload) forControlEvents:UIControlEventTouchUpInside];
}

%new
- (void)handleStoryDownload {
    @try {
        // Use the same cache-based approach that works for Reels
        NSURL *videoUrl = [SCIUtils getCachedVideoUrlForView:self];
        
        if (!videoUrl) {
            // Search parent controller's view hierarchy
            UIViewController *parentVC = [SCIUtils nearestViewControllerForView:self];
            if (parentVC) {
                videoUrl = [SCIUtils getCachedVideoUrlForView:parentVC.view];
            }
        }
        
        if (!videoUrl) {
            [SCIUtils showErrorHUDWithDescription:@"Could not find video to download"];
            return;
        }
        
        initDownloader();
        [videoDownloadDelegate downloadFileWithURL:videoUrl
                                     fileExtension:@"mp4"
                                          hudLabel:nil];
    } @catch (NSException *exception) {
        NSLog(@"[SCInsta] Story download error: %@", exception);
        [SCIUtils showErrorHUDWithDescription:@"Download failed"];
    }
}

- (void)didMoveToSuperview {
    %orig;
    
    if ([SCIManager getBoolPref:@"dw_story"]) {
        // Add download button when view appears
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self addStoryDownloadButton];
        });
    }
}
%end
