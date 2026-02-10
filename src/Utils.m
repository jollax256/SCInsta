#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import "Utils.h"
#import "InstagramHeaders.h"

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

+ (UIColor *)SCIColour_Primary {
    return [self SCIColor_Primary];
}

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
    [hud dismissAfterDelay:dismissDelay]; // Used New delay of 4.0 via default param

    return hud;
}

// Media
// Legacy Robust Implementation for Media URL Extraction
+ (NSURL *)getPhotoUrl:(IGPhoto *)photo {
    if (!photo) return nil;

    @try {
        // BHInstagram's method: access _originalImageVersions ivar
        NSArray *originalImageVersions = [photo valueForKey:@"_originalImageVersions"];
        
        if (originalImageVersions && [originalImageVersions isKindOfClass:[NSArray class]] && originalImageVersions.count > 0) {
            id bestImageVersion = nil;
            CGFloat maxPixels = 0;

            for (id version in originalImageVersions) {
                if ([version respondsToSelector:@selector(width)] && [version respondsToSelector:@selector(height)]) {
                    CGFloat w = [[version valueForKey:@"width"] floatValue];
                    CGFloat h = [[version valueForKey:@"height"] floatValue];
                    CGFloat pixels = w * h;
                    
                    if (pixels >= maxPixels) {
                        maxPixels = pixels;
                        bestImageVersion = version;
                    }
                }
            }
            
            if (!bestImageVersion) {
                bestImageVersion = originalImageVersions[0];
            }

            if ([bestImageVersion respondsToSelector:@selector(url)]) {
                NSURL *url = [bestImageVersion valueForKey:@"url"];
                if (url && [url isKindOfClass:[NSURL class]]) {
                    return url;
                }
            }
        }
        
        if ([photo respondsToSelector:@selector(imageURLForWidth:)]) {
            NSURL *photoUrl = [photo imageURLForWidth:100000.00];
            if (photoUrl) {
                return photoUrl;
            }
        }
    } @catch (NSException *exception) {
        NSLog(@"[SCInsta] Exception in getPhotoUrl: %@", exception);
    }

    return nil;
}

+ (NSURL *)getPhotoUrlForMedia:(IGMedia *)media {
    if (!media) return nil;
    IGPhoto *photo = media.photo;
    return [SCIUtils getPhotoUrl:photo];
}

+ (NSURL *)getVideoUrl:(IGVideo *)video {
    if (!video) return nil;
    
    // 1. Try BHInstagram Method (Ivar Access)
    @try {
        NSArray *videoVersionDictionaries = [video valueForKey:@"_videoVersionDictionaries"];
        if (videoVersionDictionaries && [videoVersionDictionaries isKindOfClass:[NSArray class]] && videoVersionDictionaries.count > 0) {
            id firstVersion = videoVersionDictionaries[0];
            if ([firstVersion isKindOfClass:[NSDictionary class]]) {
                id urlValue = ((NSDictionary *)firstVersion)[@"url"];
                if (urlValue && [urlValue isKindOfClass:[NSString class]]) {
                     return [NSURL URLWithString:(NSString *)urlValue];
                }
            }
        }
    } @catch (NSException *e) { /* Ignore */ }
    
    // 2. Try _allVideoURLs Ivar
    @try {
        NSSet *allVideoURLs = [video valueForKey:@"_allVideoURLs"];
        if (allVideoURLs && [allVideoURLs isKindOfClass:[NSSet class]]) {
            NSURL *url = [allVideoURLs anyObject];
            if (url) return url;
        }
    } @catch (NSException *e) { /* Ignore */ }
    
    // 3. Try known method names
    NSArray *methods = @[@"sortedVideoURLsBySize", @"videoVersions", @"videoURLs", @"versions", @"playbackURL", @"allVideoURLs"];
    for (NSString *method in methods) {
        @try {
            SEL selector = NSSelectorFromString(method);
            if ([video respondsToSelector:selector]) {
                #pragma clang diagnostic push
                #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                id result = [video performSelector:selector];
                #pragma clang diagnostic pop
                
                NSURL *extracted = [self extractURLFromVideoResult:result];
                if (extracted) return extracted;
            }
        } @catch (NSException *e) { /* Ignore */ }
    }
    
    return nil;
}

+ (NSURL *)extractURLFromVideoResult:(id)result {
    if (!result) return nil;
    if ([result isKindOfClass:[NSURL class]]) return result;
    if ([result isKindOfClass:[NSString class]]) return [NSURL URLWithString:result];
    
    if ([result isKindOfClass:[NSArray class]]) {
        NSArray *array = (NSArray *)result;
        if (array.count < 1) return nil;
        id firstElement = array[0];
        
        if ([firstElement isKindOfClass:[NSDictionary class]]) {
            NSDictionary *dict = (NSDictionary *)firstElement;
            id urlValue = dict[@"url"];
            if ([urlValue isKindOfClass:[NSString class]]) return [NSURL URLWithString:urlValue];
            if ([urlValue isKindOfClass:[NSURL class]]) return urlValue;
        }
        
        if ([firstElement isKindOfClass:[NSURL class]]) return firstElement;
        if ([firstElement isKindOfClass:[NSString class]]) return [NSURL URLWithString:firstElement];
        
        if ([firstElement respondsToSelector:@selector(url)]) {
            #pragma clang diagnostic push
            #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
            id urlResult = [firstElement performSelector:@selector(url)];
            #pragma clang diagnostic pop
            return [self extractURLFromVideoResult:urlResult];
        }
    }
    
    if ([result isKindOfClass:[NSDictionary class]]) {
        NSDictionary *dict = (NSDictionary *)result;
        id urlValue = dict[@"url"] ?: dict[@"playbackUrl"] ?: dict[@"videoUrl"];
        if (urlValue) return [self extractURLFromVideoResult:urlValue];
    }
    
    if ([result respondsToSelector:@selector(url)]) {
        #pragma clang diagnostic push
        #pragma clang diagnostic ignored "-Warc-performSelector-leaks"
        id urlResult = [result performSelector:@selector(url)];
        #pragma clang diagnostic pop
        return [self extractURLFromVideoResult:urlResult];
    }
    
    if ([result isKindOfClass:[NSSet class]]) {
         return [self extractURLFromVideoResult:[result anyObject]];
    }
    
    return nil;
}


+ (NSURL *)getVideoUrlForMedia:(IGMedia *)media {
    if (!media) return nil;
    IGVideo *video = media.video;
    if (!video) return nil;
    return [SCIUtils getVideoUrl:video];
}

// Search recursively for a player in subviews (Legacy Wrapper)
+ (NSURL *)getCachedVideoUrlForView:(UIView *)view {
    return [self getCachedVideoUrlForView:view depth:0];
}

// Recursive implementation with depth limit
+ (NSURL *)getCachedVideoUrlForView:(UIView *)view depth:(NSInteger)depth {
    if (!view || depth > 15) return nil;
    
    // 1. Check for AVPlayerLayer directly
    if ([view.layer isKindOfClass:[AVPlayerLayer class]]) {
        AVPlayerLayer *playerLayer = (AVPlayerLayer *)view.layer;
        AVPlayer *player = playerLayer.player;
        if (player) {
            NSURL *url = [self getUrlFromPlayer:player];
            if (url) return url;
        }
    }
    
    // 2. Check common property names for players or wrappers
    NSArray *playerKeys = @[@"player", @"videoPlayer", @"avPlayer"];
    
    for (NSString *key in playerKeys) {
        if ([view respondsToSelector:NSSelectorFromString(key)]) {
            id playerObj = [view valueForKey:key];
            if (playerObj && [playerObj isKindOfClass:[AVPlayer class]]) {
                NSURL *url = [self getUrlFromPlayer:(AVPlayer *)playerObj];
                if (url) return url;
            }
            if (playerObj && [playerObj respondsToSelector:@selector(avPlayer)]) {
                id innerPlayer = [playerObj valueForKey:@"avPlayer"];
                if (innerPlayer && [innerPlayer isKindOfClass:[AVPlayer class]]) {
                    NSURL *url = [self getUrlFromPlayer:(AVPlayer *)innerPlayer];
                    if (url) return url;
                }
            }
        }
    }
    
    // 3. Recursively check subviews
    for (UIView *subview in view.subviews) {
        NSURL *url = [self getCachedVideoUrlForView:subview depth:depth + 1];
        if (url) return url;
    }
    
    return nil;
}

+ (NSURL *)getUrlFromPlayer:(AVPlayer *)player {
    AVPlayerItem *currentItem = player.currentItem;
    if (!currentItem) return nil;
    
    AVAsset *asset = currentItem.asset;
    if ([asset isKindOfClass:[AVURLAsset class]]) {
        return [(AVURLAsset *)asset URL];
    }
    return nil;
}

+ (void)requestWebVideoUrlForMedia:(IGMedia *)media completion:(void(^)(NSURL *url))completion {
    if (!media) {
        if (completion) completion(nil);
        return;
    }

    NSString *shortcode = nil;
    if ([media respondsToSelector:@selector(code)]) {
        shortcode = [media valueForKey:@"code"]; 
    }
    
    if (!shortcode || ![shortcode isKindOfClass:[NSString class]] || shortcode.length == 0) {
        if (completion) completion(nil);
        return;
    }
    
    NSURL *webUrl = [NSURL URLWithString:[NSString stringWithFormat:@"https://www.instagram.com/p/%@/", shortcode]];
    
    NSURLSession *session = [NSURLSession sharedSession];
    [[session dataTaskWithURL:webUrl completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        if (error || !data) {
            if (completion) completion(nil);
            return;
        }
        
        NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        if (!html) {
             if (completion) completion(nil);
             return;
        }
        
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"property=\"og:video\" content=\"([^\"]+)\"" options:0 error:nil];
        NSTextCheckingResult *match = [regex firstMatchInString:html options:0 range:NSMakeRange(0, html.length)];
        
        if (match && match.range.location != NSNotFound) {
            NSString *videoUrlString = [html substringWithRange:[match rangeAtIndex:1]];
            if (completion) completion([NSURL URLWithString:videoUrlString]);
        } else {
            NSRegularExpression *jsonRegex = [NSRegularExpression regularExpressionWithPattern:@"\"video_url\":\"([^\"]+)\"" options:0 error:nil];
            NSTextCheckingResult *jsonMatch = [jsonRegex firstMatchInString:html options:0 range:NSMakeRange(0, html.length)];
            
            if (jsonMatch && jsonMatch.range.location != NSNotFound) {
                 NSString *jsonUrlString = [html substringWithRange:[jsonMatch rangeAtIndex:1]];
                 jsonUrlString = [jsonUrlString stringByReplacingOccurrencesOfString:@"\\u0026" withString:@"&"];
                 if (completion) completion([NSURL URLWithString:jsonUrlString]);
            } else {
                 if (completion) completion(nil);
            }
        }
    }] resume];
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