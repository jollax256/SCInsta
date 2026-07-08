#import "../../Utils.h"

%hook IGStoryViewerTapTarget
- (void)_didTap:(id)arg1 forEvent:(id)arg2 {
    if ([SCIUtils getBoolPref:@"sticker_interact_confirm"]) {
        NSLog(@"[SCInsta] Confirm sticker interact triggered");

        [SCIUtils showConfirmation:^{
            %orig;
        }];
    } else {
        %orig;
    }
}
%end