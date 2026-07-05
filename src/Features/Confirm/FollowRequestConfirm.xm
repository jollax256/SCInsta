#import "../../Utils.h"

#define CONFIRM_REQUEST_ACTION(orig) \
    if ([SCIUtils getBoolPref:@"follow_request_confirm"]) { \
        NSLog(@"[SCInsta] Confirm follow request triggered"); \
        [SCIUtils showConfirmation:^(void) { orig; }]; \
    } else { \
        orig; \
    }

%hook IGPendingRequestView
- (void)_onApproveButtonTapped {
    CONFIRM_REQUEST_ACTION(%orig);
}
- (void)_onIgnoreButtonTapped {
    CONFIRM_REQUEST_ACTION(%orig);
}
%end