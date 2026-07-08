#import "../../Utils.h"

%hook IGDirectThreadViewController
- (void)swipeableScrollManagerDidEndDraggingAboveSwipeThreshold:(id)arg1 {
    if ([SCIUtils getBoolPref:@"shh_mode_confirm"]) {
        NSLog(@"[SCInsta] Confirm shh mode triggered");

        [SCIUtils showConfirmation:^{
            %orig;
        }];
    } else {
        %orig;
    }
}

- (void)shhModeTransitionButtonDidTap:(id)arg1 {
    if ([SCIUtils getBoolPref:@"shh_mode_confirm"]) {
        NSLog(@"[SCInsta] Confirm shh mode triggered");

        [SCIUtils showConfirmation:^{
            %orig;
        }];
    } else {
        %orig;
    }
}

- (void)messageListViewControllerDidToggleShhMode:(id)arg1 {
    if ([SCIUtils getBoolPref:@"shh_mode_confirm"]) {
        NSLog(@"[SCInsta] Confirm shh mode triggered");

        [SCIUtils showConfirmation:^{
            %orig;
        }];
    } else {
        %orig;
    }
}
%end