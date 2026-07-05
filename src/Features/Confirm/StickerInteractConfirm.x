#import "../../Utils.h"

#define CONFIRM_STICKER_ACTION(orig) \
    if ([SCIUtils getBoolPref:@"sticker_interact_confirm"]) { \
        NSLog(@"[SCInsta] Confirm sticker interact triggered"); \
        [SCIUtils showConfirmation:^(void) { orig; }]; \
    } else { \
        orig; \
    }

%hook IGStoryViewerTapTarget
- (void)_didTap:(id)arg1 forEvent:(id)arg2 {
    CONFIRM_STICKER_ACTION(%orig);
}
%end