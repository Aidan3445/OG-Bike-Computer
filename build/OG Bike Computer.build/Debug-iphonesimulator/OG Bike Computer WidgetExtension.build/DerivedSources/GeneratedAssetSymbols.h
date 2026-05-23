#import <Foundation/Foundation.h>

#if __has_attribute(swift_private)
#define AC_SWIFT_PRIVATE __attribute__((swift_private))
#else
#define AC_SWIFT_PRIVATE
#endif

/// The resource bundle ID.
static NSString * const ACBundleID AC_SWIFT_PRIVATE = @"com.aidan3445.computa.widget";

/// The "AccentColor" asset catalog color resource.
static NSString * const ACColorNameAccentColor AC_SWIFT_PRIVATE = @"AccentColor";

/// The "WidgetBackground" asset catalog color resource.
static NSString * const ACColorNameWidgetBackground AC_SWIFT_PRIVATE = @"WidgetBackground";

#undef AC_SWIFT_PRIVATE
