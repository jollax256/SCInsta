#import "../../Utils.h"

%hook IGDirectThreadCallButtonsCoordinator
// Voice Call
- (void)_didTapAudioButton:(id)arg1 {
    if ([SCIUtils getBoolPref:@"call_confirm"]) {
        NSLog(@"[SCInsta] Call confirm triggered");

        [SCIUtils showConfirmation:^(void) L_BRACE %orig; R_BRACE];
    } else {
        %orig;
    }
}

// Video Call
- (void)_didTapVideoButton:(id)arg1 {
    if ([SCIUtils getBoolPref:@"call_confirm"]) {
        NSLog(@"[SCInsta] Call confirm triggered");
        
        [SCIUtils showConfirmation:^(void) L_BRACE %orig; R_BRACE];
    } else {
        %orig;
    }
}
%end