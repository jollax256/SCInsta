#import "../../Utils.h"

#define QUICKSNAPENABLED(orig) return [SCIUtils getBoolPref:@"disable_instants_creation"] ? false : orig;

// Demangled name: IGQuickSnapExperimentation.IGQuickSnapExperimentationHelper
%hook _TtC26IGQuickSnapExperimentation32IGQuickSnapExperimentationHelper
+ (_Bool)isQuicksnapEnabled:(id)enabled {
    QUICKSNAPENABLED(%orig);
}
+ (_Bool)isQuicksnapEnabledInFeed:(id)feed {
    QUICKSNAPENABLED(%orig);
}
+ (_Bool)isQuicksnapEnabledInInbox:(id)inbox {
    QUICKSNAPENABLED(%orig);
}
+ (_Bool)isQuicksnapEnabledInStories:(id)stories {
    QUICKSNAPENABLED(%orig);
}
+ (_Bool)isQuicksnapEnabledInNotesTray:(id)tray {
    QUICKSNAPENABLED(%orig);
}
+ (_Bool)isQuicksnapEnabledInNotesTrayWithPeek:(id)peek {
    QUICKSNAPENABLED(%orig);
}
+ (_Bool)isQuicksnapEnabledInNotesTrayWithPog:(id)pog {
    QUICKSNAPENABLED(%orig);
}
+ (_Bool)isQuicksnapNotesTrayEmptyPogEnabled:(id)enabled {
    QUICKSNAPENABLED(%orig);
}
%end
