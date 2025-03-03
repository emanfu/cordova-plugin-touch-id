#import "TouchID.h"
#import <LocalAuthentication/LocalAuthentication.h>

static NSString *const FingerprintDatabaseStateKey = @"FingerprintDatabaseStateKey";

@implementation TouchID

// These two combined need to be unique, so one can be fixed
NSString *keychainItemIdentifier = @"TouchIDKey";
NSString *keychainItemServiceName;

- (void) isAvailable:(CDVInvokedUrlCommand*)command {

  if (NSClassFromString(@"LAContext") == NULL) {
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR] callbackId:command.callbackId];
    return;
  }

  [self.commandDelegate runInBackground:^{

    NSError *error = nil;
    LAContext *laContext = [[LAContext alloc] init];

    if ([laContext canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&error]) {
      NSString *biometryType = @"touch";
      if (@available(iOS 11.0, *)) {
        if (laContext.biometryType == LABiometryTypeFaceID) {
          biometryType = @"face";
        }
      }
      [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:biometryType]
                                  callbackId:command.callbackId];
    } else if ([laContext canEvaluatePolicy:LAPolicyDeviceOwnerAuthentication error:&error]) {
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsString:@"passcode"]
                                    callbackId:command.callbackId];
    } else {
      NSArray *errorKeys = @[@"code", @"localizedDescription"];
      [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsDictionary:[error dictionaryWithValuesForKeys:errorKeys]]
                                  callbackId:command.callbackId];
    }
  }];
}

- (void) didFingerprintDatabaseChange:(CDVInvokedUrlCommand*)command {
  // Get enrollment state
  [self.commandDelegate runInBackground:^{
    LAContext *laContext = [[LAContext alloc] init];
    NSError *error = nil;

    // we expect the dev to have checked 'isAvailable' already so this should not return an error,
    // we do however need to run canEvaluatePolicy here in order to get a non-nil evaluatedPolicyDomainState
    if (![laContext canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&error]) {
      [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error localizedDescription]] callbackId:command.callbackId];
      return;
    }

    // only supported on iOS9+, so check this.. if not supported just report back as false
    if (![laContext respondsToSelector:@selector(evaluatedPolicyDomainState)]) {
      [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:NO] callbackId:command.callbackId];
      return;
    }

    NSData * state = [laContext evaluatedPolicyDomainState];
    if (state != nil) {

      NSString * stateStr = [state base64EncodedStringWithOptions:0];

      NSString * storedState = [[NSUserDefaults standardUserDefaults] stringForKey:FingerprintDatabaseStateKey];

      // whenever a finger is added/changed/removed the value of the storedState changes,
      // so compare agains a value we previously stored in the context of this app
      BOOL changed = storedState != nil && ![stateStr isEqualToString:storedState];

      [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK messageAsBool:changed] callbackId:command.callbackId];

      // Store enrollment
      [[NSUserDefaults standardUserDefaults] setObject:stateStr forKey:FingerprintDatabaseStateKey];
      [[NSUserDefaults standardUserDefaults] synchronize];
    }
  }];
}

// this 'default' method uses keychain instead of localauth so the passcode fallback can be used
- (void) verifyFingerprint:(CDVInvokedUrlCommand*)command {

  NSString *message = [command.arguments objectAtIndex:0];
  NSString *callbackId = command.callbackId;

  [self.commandDelegate runInBackground:^{
      NSError *error = nil;
      LAContext *laContext = [[LAContext alloc] init];
      
      if (![laContext canEvaluatePolicy:LAPolicyDeviceOwnerAuthentication error:&error]) {
          [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error localizedDescription]]
                                      callbackId:callbackId];
          return;
      }
      
      // if we add a 'verifyFingerprintWithOptions' method we can add stuff like this:
      // the nr of seconds you allow to reuse the last touchid device unlock (default 0, so never reuse)
      //    laContext.touchIDAuthenticationAllowableReuseDuration = 30;
      
      [laContext evaluatePolicy:LAPolicyDeviceOwnerAuthentication localizedReason:message reply:^(BOOL authOK, NSError *error) {
          if (authOK) {
              [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
                                          callbackId:callbackId];
          } else {
              NSLog(@"Fingerprint or device passcode could not be validated.");
              // invoked when the scan failed 3 times in a row, the cancel button was pressed, or the 'enter password' button was pressed
              NSArray *errorKeys = @[@"code", @"localizedDescription"];
              [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                                   messageAsDictionary:[error dictionaryWithValuesForKeys:errorKeys]]
                                          callbackId:callbackId];
          }
      }];
  }];
}

// This implementation uses LocalAuthentication and has no built-in passcode fallback
- (void) verifyFingerprintWithCustomPasswordFallback:(CDVInvokedUrlCommand*)command {
  NSString *message = [command.arguments objectAtIndex:0];
  [self verifyFingerprintWithCustomPasswordFallback:command.callbackId withMessage:message andEnterPasswordLabel:nil];
}

- (void) verifyFingerprintWithCustomPasswordFallbackAndEnterPasswordLabel:(CDVInvokedUrlCommand*)command {
  NSString *message = [command.arguments objectAtIndex:0];
  NSString *enterPasswordLabel = [command.arguments objectAtIndex:1];
  [self verifyFingerprintWithCustomPasswordFallback:command.callbackId withMessage:message andEnterPasswordLabel:enterPasswordLabel];
}

- (void) verifyFingerprintWithCustomPasswordFallback:(NSString*)callbackId withMessage:(NSString*)message andEnterPasswordLabel:(NSString*)enterPasswordLabel {

  if (NSClassFromString(@"LAContext") == NULL) {
    [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR]
                                callbackId:callbackId];
    return;
  }

  [self.commandDelegate runInBackground:^{
    NSError *error = nil;
    LAContext *laContext = [[LAContext alloc] init];

    if (![laContext canEvaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics error:&error]) {
      [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR messageAsString:[error localizedDescription]]
                                  callbackId:callbackId];
      return;
    }

    // if we add a 'verifyFingerprintWithOptions' method we can add stuff like this:
    // the nr of seconds you allow to reuse the last touchid device unlock (default 0, so never reuse)
//    laContext.touchIDAuthenticationAllowableReuseDuration = 30;

    // this replaces the default 'Enter password' button label
    if (enterPasswordLabel != nil) {
      laContext.localizedFallbackTitle = enterPasswordLabel;
    }

    [laContext evaluatePolicy:LAPolicyDeviceOwnerAuthenticationWithBiometrics localizedReason:message reply:^(BOOL authOK, NSError *error) {
      if (authOK) {
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_OK]
                                    callbackId:callbackId];
      } else {
        // invoked when the scan failed 3 times in a row, the cancel button was pressed, or the 'enter password' button was pressed
        NSArray *errorKeys = @[@"code", @"localizedDescription"];
        [self.commandDelegate sendPluginResult:[CDVPluginResult resultWithStatus:CDVCommandStatus_ERROR
                                                           messageAsDictionary:[error dictionaryWithValuesForKeys:errorKeys]]
                                    callbackId:callbackId];
      }
    }];
  }];
}

@end
