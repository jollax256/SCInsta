#import "Utils.h"
#import <AVFoundation/AVFoundation.h>
#import <objc/runtime.h>

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

+ (_Bool)liquidGlassEnabledBool:(_Bool)fallback {
    BOOL setting = [SCIUtils getBoolPref:@"liquid_glass_surfaces"];
    return setting ? true : fallback;
}

+ (void)cleanCache {
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSMutableArray<NSError *> *deletionErrors = [NSMutableArray array];

    // * disabled bc app crashed trying to delete certain files inside it
    // todo: remove the above disclaimer if this new code doesn't cause crashing
    // Temp folder
    NSArray *tempFolderContents = [fileManager contentsOfDirectoryAtURL:[NSURL fileURLWithPath:NSTemporaryDirectory()] includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];

    for (NSURL *fileURL in tempFolderContents) {
        NSError *cacheItemDeletionError;
        [fileManager removeItemAtURL:fileURL error:&cacheItemDeletionError];

        if (cacheItemDeletionError) [deletionErrors addObject:cacheItemDeletionError];
    }

    // Analytics folder
    NSString *analyticsFolder = [[NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES) objectAtIndex:0] stringByAppendingPathComponent:@"Application Support/com.burbn.instagram/analytics"];
    NSArray *analyticsFolderContents = [fileManager contentsOfDirectoryAtURL:[[NSURL alloc] initFileURLWithPath:analyticsFolder] includingPropertiesForKeys:nil options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];

    for (NSURL *fileURL in analyticsFolderContents) {
        NSError *cacheItemDeletionError;
        [fileManager removeItemAtURL:fileURL error:&cacheItemDeletionError];

        if (cacheItemDeletionError) [deletionErrors addObject:cacheItemDeletionError];
    }
    
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
+ (void)showSettingsVC:(UIWindow *)window {
    UIViewController *rootController = [window rootViewController];
    SCISettingsViewController *settingsViewController = [SCISettingsViewController new];
    UINavigationController *navigationController = [[UINavigationController alloc] initWithRootViewController:settingsViewController];
    
    [rootController presentViewController:navigationController animated:YES completion:nil];
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

    // 1. Post v398: allVideoURLs (most common modern path)
    @try {
        if ([video respondsToSelector:@selector(allVideoURLs)]) {
            NSSet *urls = [video allVideoURLs];
            if (urls.count) {
                NSLog(@"[SCInsta] getVideoUrl: Found URL via allVideoURLs");
                return [urls anyObject];
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[SCInsta] getVideoUrl: allVideoURLs threw: %@", e);
    }

    // 2. Pre v398: sortedVideoURLsBySize
    @try {
        if ([video respondsToSelector:@selector(sortedVideoURLsBySize)]) {
            NSArray<NSDictionary *> *sorted = [video sortedVideoURLsBySize];
            NSString *urlString = sorted.firstObject[@"url"];
            if (urlString.length) {
                NSLog(@"[SCInsta] getVideoUrl: Found URL via sortedVideoURLsBySize");
                return [NSURL URLWithString:urlString];
            }
        }
    } @catch (NSException *e) {
        NSLog(@"[SCInsta] getVideoUrl: sortedVideoURLsBySize threw: %@", e);
    }

    // 3. Direct url property (some IG versions)
    @try {
        if ([video respondsToSelector:@selector(url)]) {
            NSURL *url = [video performSelector:@selector(url)];
            if (url && [url isKindOfClass:[NSURL class]]) {
                NSLog(@"[SCInsta] getVideoUrl: Found URL via url property");
                return url;
            }
        }
    } @catch (NSException *e) {}

    // 4. videoURL property
    @try {
        if ([video respondsToSelector:@selector(videoURL)]) {
            NSURL *url = [video performSelector:@selector(videoURL)];
            if (url && [url isKindOfClass:[NSURL class]]) {
                NSLog(@"[SCInsta] getVideoUrl: Found URL via videoURL property");
                return url;
            }
        }
    } @catch (NSException *e) {}

    // 5. Runtime introspection: scan all properties for NSURL values
    @try {
        NSURL *url = [self _extractVideoURLByIntrospection:video];
        if (url) {
            NSLog(@"[SCInsta] getVideoUrl: Found URL via runtime introspection");
            return url;
        }
    } @catch (NSException *e) {
        NSLog(@"[SCInsta] getVideoUrl: introspection threw: %@", e);
    }

    NSLog(@"[SCInsta] getVideoUrl: All extraction methods failed for %@", NSStringFromClass([video class]));
    return nil;
}

+ (NSURL *)_extractVideoURLByIntrospection:(id)obj {
    if (!obj) return nil;

    unsigned int count = 0;
    objc_property_t *properties = class_copyPropertyList([obj class], &count);
    if (!properties) return nil;

    NSURL *bestURL = nil;

    for (unsigned int i = 0; i < count; i++) {
        const char *name = property_getName(properties[i]);
        if (!name) continue;

        NSString *propName = [NSString stringWithUTF8String:name];

        @try {
            id value = [obj valueForKey:propName];

            // Direct NSURL property
            if ([value isKindOfClass:[NSURL class]]) {
                NSURL *url = (NSURL *)value;
                NSString *abs = url.absoluteString;
                // Only accept URLs that look like video URLs (http/https with video-like paths)
                if ([abs hasPrefix:@"http"] && ([abs containsString:@".mp4"] ||
                    [abs containsString:@"video"] || [abs containsString:@".m3u8"])) {
                    NSLog(@"[SCInsta] introspection: Found video URL in property '%@'", propName);
                    bestURL = url;
                    break;
                }
                // Accept any http URL if we don't find a better one
                if (!bestURL && [abs hasPrefix:@"http"]) {
                    bestURL = url;
                }
            }
            // NSString that could be a URL
            else if ([value isKindOfClass:[NSString class]]) {
                NSString *str = (NSString *)value;
                if ([str hasPrefix:@"http"] && ([str containsString:@".mp4"] ||
                    [str containsString:@"video"])) {
                    NSURL *url = [NSURL URLWithString:str];
                    if (url) {
                        NSLog(@"[SCInsta] introspection: Found video URL string in property '%@'", propName);
                        bestURL = url;
                        break;
                    }
                }
            }
            // NSSet or NSArray of URLs
            else if ([value isKindOfClass:[NSSet class]] || [value isKindOfClass:[NSArray class]]) {
                for (id item in value) {
                    if ([item isKindOfClass:[NSURL class]]) {
                        bestURL = (NSURL *)item;
                        NSLog(@"[SCInsta] introspection: Found video URL in collection property '%@'", propName);
                        break;
                    }
                }
                if (bestURL) break;
            }
        } @catch (NSException *e) {
            // Skip inaccessible properties
        }
    }

    free(properties);
    return bestURL;
}
+ (NSURL *)getVideoUrlForMedia:(IGMedia *)media {
    if (!media) return nil;

    IGVideo *video = media.video;
    if (!video) return nil;

    return [SCIUtils getVideoUrl:video];
}

// === OUR CUSTOM VIDEO DOWNLOAD HELPERS (preserved from our fork) ===

+ (NSURL *)getVideoUrlForPostItem:(IGPostItem *)postItem {
    @try {
        if (!postItem) return nil;
        
        IGVideo *video = postItem.video;
        if (!video) return nil;
        
        return [SCIUtils getVideoUrl:video];
    }
    @catch (NSException *exception) {
        NSLog(@"[SCInsta] getVideoUrlForPostItem: Exception: %@", exception);
        return nil;
    }
}

+ (NSURL *)getCarouselVideoUrlFromView:(UIView *)view {
    @try {
        if (!view) return nil;
        
        // Search for IGPageMediaView in the view hierarchy (up and down)
        // First, search upward through superviews
        UIView *current = view;
        while (current) {
            if ([current isKindOfClass:NSClassFromString(@"IGPageMediaView")]) {
                IGPageMediaView *pageView = (IGPageMediaView *)current;
                IGPostItem *currentItem = [pageView currentMediaItem];
                if (currentItem) {
                    NSURL *url = [SCIUtils getVideoUrlForPostItem:currentItem];
                    if (url) {
                        NSLog(@"[SCInsta] getCarouselVideoUrl: Found video URL from carousel current item (upward search)");
                        return url;
                    }
                }
            }
            current = current.superview;
        }
        
        // Then search downward in the view's subviews
        IGPageMediaView *pageView = (IGPageMediaView *)[self _findViewOfClass:NSClassFromString(@"IGPageMediaView") inView:view depth:0 maxDepth:10];
        if (pageView) {
            IGPostItem *currentItem = [pageView currentMediaItem];
            if (currentItem) {
                NSURL *url = [SCIUtils getVideoUrlForPostItem:currentItem];
                if (url) {
                    NSLog(@"[SCInsta] getCarouselVideoUrl: Found video URL from carousel current item (downward search)");
                    return url;
                }
            }
        }
        
        // Also try searching from parent controller's view
        UIViewController *parentVC = [self nearestViewControllerForView:view];
        if (parentVC && parentVC.view != view) {
            IGPageMediaView *pageView2 = (IGPageMediaView *)[self _findViewOfClass:NSClassFromString(@"IGPageMediaView") inView:parentVC.view depth:0 maxDepth:10];
            if (pageView2) {
                IGPostItem *currentItem = [pageView2 currentMediaItem];
                if (currentItem) {
                    NSURL *url = [SCIUtils getVideoUrlForPostItem:currentItem];
                    if (url) {
                        NSLog(@"[SCInsta] getCarouselVideoUrl: Found video URL from carousel current item (controller search)");
                        return url;
                    }
                }
            }
        }
        
        return nil;
    }
    @catch (NSException *exception) {
        NSLog(@"[SCInsta] getCarouselVideoUrlFromView: Exception: %@", exception);
        return nil;
    }
}

+ (UIView *)_findViewOfClass:(Class)cls inView:(UIView *)view depth:(int)depth maxDepth:(int)maxDepth {
    @try {
        if (!view || !cls || depth > maxDepth) return nil;
        
        if ([view isKindOfClass:cls]) return view;
        
        for (UIView *subview in view.subviews) {
            UIView *found = [self _findViewOfClass:cls inView:subview depth:depth + 1 maxDepth:maxDepth];
            if (found) return found;
        }
        
        return nil;
    }
    @catch (NSException *exception) {
        return nil;
    }
}

// AVPlayer cache-based video URL extraction fallback
// Used when Instagram changes how they serve/secure video and model extraction fails.
// Finds the URL the currently-playing AVPlayer is streaming from so we can download it.
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

        CALayer *layer = view.layer;
        if (layer) {
            AVPlayer *player = [self _findAVPlayerInLayer:layer depth:0 maxDepth:5];
            if (player) return player;
        }

        for (UIView *subview in view.subviews) {
            AVPlayer *player = [self _findAVPlayerInView:subview depth:depth + 1 maxDepth:maxDepth];
            if (player) return player;
        }

        return nil;
    }
    @catch (NSException *exception) {
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

        for (CALayer *sublayer in layer.sublayers) {
            AVPlayer *player = [self _findAVPlayerInLayer:sublayer depth:depth + 1 maxDepth:maxDepth];
            if (player) return player;
        }

        return nil;
    }
    @catch (NSException *exception) {
        return nil;
    }
}

// === END OF OUR CUSTOM VIDEO DOWNLOAD HELPERS ===

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

// Alerts
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
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:title message:@"Are you sure?" preferredStyle:UIAlertControllerStyleAlert];
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

// Toasts
+ (void)showToastForDuration:(double)duration title:(NSString *)title {
    [SCIUtils showToastForDuration:duration title:title subtitle:nil];
}
+ (void)showToastForDuration:(double)duration title:(NSString *)title subtitle:(NSString *)subtitle {
    // Root VC
    Class rootVCClass = NSClassFromString(@"IGRootViewController");

    UIViewController *topMostVC = topMostController();
    if (![topMostVC isKindOfClass:rootVCClass]) return;

    IGRootViewController *rootVC = (IGRootViewController *)topMostVC;

    // Presenter
    IGActionableConfirmationToastPresenter *toastPresenter = [rootVC toastPresenter];
    if (toastPresenter == nil) return;

    // View Model
    Class modelClass = NSClassFromString(@"IGActionableConfirmationToastViewModel");
    IGActionableConfirmationToastViewModel *model = [modelClass new];
    
    [model setValue:title forKey:@"text_annotatedTitleText"];
    [model setValue:subtitle forKey:@"text_annotatedSubtitleText"];

    // Show new toast, after clearing existing one
    [toastPresenter hideAlert];
    [toastPresenter showAlertWithViewModel:model isAnimated:true animationDuration:duration presentationPriority:0 tapActionBlock:nil presentedHandler:nil dismissedHandler:nil];
}

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

// Ivars
+ (id)getIvarForObj:(id)obj name:(const char *)name {
    Ivar ivar = class_getInstanceVariable(object_getClass(obj), name);
    if (!ivar) return nil;

    return object_getIvar(obj, ivar);
}
+ (void)setIvarForObj:(id)obj name:(const char *)name value:(id)value {
    Ivar ivar = class_getInstanceVariable(object_getClass(obj), name);
    if (!ivar) return;
    
    object_setIvarWithStrongDefault(obj, ivar, value);
}


@end