#import "../../Utils.h"

#define CONFIRM_SHH_ACTION(orig) \
    if ([SCIUtils getBoolPref:@"shh_mode_confirm"]) { \
        NSLog(@"[SCInsta] Confirm shh mode triggered"); \
        [SCIUtils showConfirmation:^(void) { orig; }]; \
    } else { \
        orig; \
    }

%hook IGDirectThreadViewController
- (void)swipeableScrollManagerDidEndDraggingAboveSwipeThreshold:(id)arg1 {
    CONFIRM_SHH_ACTION(%orig);
}

- (void)shhModeTransitionButtonDidTap:(id)arg1 {
    CONFIRM_SHH_ACTION(%orig);
}

- (void)messageListViewControllerDidToggleShhMode:(id)arg1 {
    CONFIRM_SHH_ACTION(%orig);
}
%end