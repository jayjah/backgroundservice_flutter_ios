#import "ClientFlutterBackgroundServicePlugin.h"
#import <client_flutter_background_service/client_flutter_background_service-Swift.h>

@implementation ClientFlutterBackgroundServicePlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftClientFlutterBackgroundServicePlugin registerWithRegistrar:registrar];
}
@end
