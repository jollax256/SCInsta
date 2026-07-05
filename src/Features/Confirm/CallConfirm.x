#import "../../Utils.h"

#define CONFIRM_CALL_ACTION(orig) \
    if ([SCIUtils getBoolPref:@"call_confirm"]) { \
        NSLog(@"[SCInsta] Call confirm triggered"); \
        [SCIUtils showConfirmation:^(void) { orig; }]; \
    } else { \
        orig; \
    }

%hook IGDirectThreadCallButtonsCoordinator
// Voice Call
- (void)_didTapAudioButton:(id)arg1 {
    CONFIRM_CALL_ACTION(%orig);
}

// Video Call
- (void)_didTapVideoButton:(id)arg1 {
    CONFIRM_CALL_ACTION(%orig);
}
%end