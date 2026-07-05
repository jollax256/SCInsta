#import "../../Utils.h"

#define CONFIRM_COMMENT_ACTION(orig) \
    if ([SCIUtils getBoolPref:@"post_comment_confirm"]) { \
        NSLog(@"[SCInsta] Confirm post comment triggered"); \
        [SCIUtils showConfirmation:^(void) { orig; }]; \
    } else { \
        orig; \
    }

%hook IGCommentComposer.IGCommentComposerController
- (void)onSendButtonTap {
    CONFIRM_COMMENT_ACTION(%orig);
}
%end