#import "../../Utils.h"

// Demangled name: IGQuickSnapExperimentation.IGQuickSnapExperimentationHelper
%hook _TtC26IGQuickSnapExperimentation32IGQuickSnapExperimentationHelper
+ (_Bool)isQuicksnapEnabled:(id)enabled {
    _Bool orig_val = %orig;
    return [SCIUtils getBoolPref:@"disable_instants_creation"] ? false : orig_val;
}
+ (_Bool)isQuicksnapEnabledInFeed:(id)feed {
    _Bool orig_val = %orig;
    return [SCIUtils getBoolPref:@"disable_instants_creation"] ? false : orig_val;
}
+ (_Bool)isQuicksnapEnabledInInbox:(id)inbox {
    _Bool orig_val = %orig;
    return [SCIUtils getBoolPref:@"disable_instants_creation"] ? false : orig_val;
}
+ (_Bool)isQuicksnapEnabledInStories:(id)stories {
    _Bool orig_val = %orig;
    return [SCIUtils getBoolPref:@"disable_instants_creation"] ? false : orig_val;
}
+ (_Bool)isQuicksnapEnabledInNotesTray:(id)tray {
    _Bool orig_val = %orig;
    return [SCIUtils getBoolPref:@"disable_instants_creation"] ? false : orig_val;
}
+ (_Bool)isQuicksnapEnabledInNotesTrayWithPeek:(id)peek {
    _Bool orig_val = %orig;
    return [SCIUtils getBoolPref:@"disable_instants_creation"] ? false : orig_val;
}
+ (_Bool)isQuicksnapEnabledInNotesTrayWithPog:(id)pog {
    _Bool orig_val = %orig;
    return [SCIUtils getBoolPref:@"disable_instants_creation"] ? false : orig_val;
}
+ (_Bool)isQuicksnapNotesTrayEmptyPogEnabled:(id)enabled {
    _Bool orig_val = %orig;
    return [SCIUtils getBoolPref:@"disable_instants_creation"] ? false : orig_val;
}
// + (_Bool)isStoriesSpringEnabled:(id)enabled {
//     return true;
// }
// + (_Bool)shouldEnableScreenshotBlocking:(id)blocking {
//     return false;
// }
// + (_Bool)areFiltersEnabled:(id)enabled {
//     return true;
// }
// + (_Bool)isBottomsheetCustomAudienceEnabled:(id)enabled {
//     return true;
// }
// + (_Bool)isVideoCaptureEnabled:(id)enabled {
//     return true;
// }
%end

// %hook IGDirectNotesTrayRowCell
// - (_Bool)isQuicksnapPeekVisible {
//     return true;
// }
// %end

// %hook IGDirectNotesTrayRowSectionController
// - (_Bool)isQuicksnapPeekVisible {
//     return true;
// }
// %end