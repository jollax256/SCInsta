#import "../../Utils.h"

%hook IGPendingRequestView
- (void)_onApproveButtonTapped {
    if ([SCIUtils getBoolPref:@"follow_request_confirm"]) {
        NSLog(@"[SCInsta] Confirm follow request triggered");

        [SCIUtils showConfirmation:^(void) L_BRACE %orig; R_BRACE];
    } else {
        %orig;
    }
}
- (void)_onIgnoreButtonTapped {
    if ([SCIUtils getBoolPref:@"follow_request_confirm"]) {
        NSLog(@"[SCInsta] Confirm follow request triggered");

        [SCIUtils showConfirmation:^(void) L_BRACE %orig; R_BRACE];
    } else {
        %orig;
    }
}
%end