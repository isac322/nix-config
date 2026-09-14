#import <ApplicationServices/ApplicationServices.h>
#import <Foundation/Foundation.h>

#include <errno.h>
#include <fcntl.h>
#include <signal.h>
#include <spawn.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <sysexits.h>
#include <unistd.h>

static NSString *const ConfigPath = @"/etc/camofox-vnc-host.plist";
static volatile sig_atomic_t ChildPID = 0;

static void LogError(NSString *format, ...) NS_FORMAT_FUNCTION(1, 2);

static void LogError(NSString *format, ...) {
  va_list arguments;
  va_start(arguments, format);
  NSString *message = [[NSString alloc] initWithFormat:format arguments:arguments];
  va_end(arguments);
  fprintf(stderr, "camofox-vnc-host: %s\n", message.UTF8String ?: "unknown error");
}

static BOOL IsCStringSafe(NSString *value) {
  if (![value canBeConvertedToEncoding:NSUTF8StringEncoding]) {
    return NO;
  }

  unichar nul = 0;
  NSString *nulString = [NSString stringWithCharacters:&nul length:1];
  return [value rangeOfString:nulString].location == NSNotFound;
}

static BOOL IsBoolean(id value) {
  return value != nil && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID();
}

static NSData *ReadConfigData(void) {
  int descriptor = open(ConfigPath.fileSystemRepresentation, O_RDONLY | O_CLOEXEC);
  if (descriptor < 0) {
    LogError(@"cannot open %@: %s", ConfigPath, strerror(errno));
    return nil;
  }

  struct stat metadata;
  if (fstat(descriptor, &metadata) != 0) {
    LogError(@"cannot inspect %@: %s", ConfigPath, strerror(errno));
    close(descriptor);
    return nil;
  }

  if (!S_ISREG(metadata.st_mode)) {
    LogError(@"%@ must resolve to a regular file", ConfigPath);
    close(descriptor);
    return nil;
  }
  if (metadata.st_uid != 0) {
    LogError(@"%@ must be owned by root", ConfigPath);
    close(descriptor);
    return nil;
  }
  if ((metadata.st_mode & (S_IWGRP | S_IWOTH)) != 0) {
    LogError(@"%@ must not be writable by group or others", ConfigPath);
    close(descriptor);
    return nil;
  }

  NSMutableData *data = [NSMutableData data];
  uint8_t buffer[16384];
  for (;;) {
    ssize_t count = read(descriptor, buffer, sizeof(buffer));
    if (count > 0) {
      [data appendBytes:buffer length:(NSUInteger)count];
      continue;
    }
    if (count == 0) {
      break;
    }
    if (errno == EINTR) {
      continue;
    }

    LogError(@"cannot read %@: %s", ConfigPath, strerror(errno));
    close(descriptor);
    return nil;
  }

  if (close(descriptor) != 0) {
    LogError(@"cannot close %@ after reading: %s", ConfigPath, strerror(errno));
    return nil;
  }
  return data;
}

static NSDictionary<NSString *, id> *LoadConfig(void) {
  NSData *data = ReadConfigData();
  if (!data) {
    return nil;
  }

  NSError *error = nil;
  id propertyList = [NSPropertyListSerialization propertyListWithData:data
                                                               options:NSPropertyListImmutable
                                                                format:nil
                                                                 error:&error];
  if (![propertyList isKindOfClass:[NSDictionary class]]) {
    LogError(@"%@ must contain a property-list dictionary%@",
             ConfigPath,
             error ? [NSString stringWithFormat:@": %@", error.localizedDescription] : @"");
    return nil;
  }

  NSDictionary<NSString *, id> *config = propertyList;
  NSSet<NSString *> *expectedKeys = [NSSet setWithArray:@[
    @"Executable",
    @"Arguments",
    @"Environment",
    @"RequireScreenRecording",
    @"RequireAccessibility",
  ]];
  NSSet<NSString *> *actualKeys = [NSSet setWithArray:config.allKeys];
  if (![actualKeys isEqualToSet:expectedKeys]) {
    NSMutableSet<NSString *> *missing = [expectedKeys mutableCopy];
    [missing minusSet:actualKeys];
    NSMutableSet<NSString *> *unknown = [actualKeys mutableCopy];
    [unknown minusSet:expectedKeys];
    LogError(@"%@ has invalid keys (missing: %@; unknown: %@)",
             ConfigPath,
             [[missing.allObjects sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@", "] ?: @"",
             [[unknown.allObjects sortedArrayUsingSelector:@selector(compare:)] componentsJoinedByString:@", "] ?: @"");
    return nil;
  }

  NSString *executable = config[@"Executable"];
  NSArray *arguments = config[@"Arguments"];
  NSDictionary *environment = config[@"Environment"];
  id requireScreenRecording = config[@"RequireScreenRecording"];
  id requireAccessibility = config[@"RequireAccessibility"];

  if (![executable isKindOfClass:[NSString class]] || executable.length == 0 ||
      !executable.isAbsolutePath || !IsCStringSafe(executable)) {
    LogError(@"%@ key Executable must be a non-empty absolute UTF-8 path", ConfigPath);
    return nil;
  }
  if (![arguments isKindOfClass:[NSArray class]]) {
    LogError(@"%@ key Arguments must be an array of strings", ConfigPath);
    return nil;
  }
  for (id argument in arguments) {
    if (![argument isKindOfClass:[NSString class]] || !IsCStringSafe(argument)) {
      LogError(@"%@ key Arguments must contain only UTF-8 strings without NUL bytes", ConfigPath);
      return nil;
    }
  }
  if (![environment isKindOfClass:[NSDictionary class]]) {
    LogError(@"%@ key Environment must be a dictionary of strings", ConfigPath);
    return nil;
  }
  for (id key in environment) {
    id value = environment[key];
    if (![key isKindOfClass:[NSString class]] || [key length] == 0 ||
        [key rangeOfString:@"="].location != NSNotFound || !IsCStringSafe(key) ||
        ![value isKindOfClass:[NSString class]] || !IsCStringSafe(value)) {
      LogError(@"%@ key Environment must contain valid UTF-8 NAME=VALUE entries", ConfigPath);
      return nil;
    }
  }
  if (!IsBoolean(requireScreenRecording) || !IsBoolean(requireAccessibility)) {
    LogError(@"%@ permission requirement keys must be booleans", ConfigPath);
    return nil;
  }

  struct stat executableMetadata;
  if (stat(executable.fileSystemRepresentation, &executableMetadata) != 0) {
    LogError(@"configured executable %@ is unavailable: %s", executable, strerror(errno));
    return nil;
  }
  if (!S_ISREG(executableMetadata.st_mode) || access(executable.fileSystemRepresentation, X_OK) != 0) {
    LogError(@"configured executable %@ must be a regular executable file", executable);
    return nil;
  }

  return config;
}

static BOOL EnsureScreenRecordingPermission(void) {
  if (CGPreflightScreenCaptureAccess()) {
    return YES;
  }

  BOOL granted = CGRequestScreenCaptureAccess();
  if (granted && CGPreflightScreenCaptureAccess()) {
    return YES;
  }

  LogError(@"Screen Recording access is required; enable Camofox VNC Host in System Settings > Privacy & Security > Screen Recording");
  return NO;
}

static BOOL EnsureAccessibilityPermission(void) {
  if (AXIsProcessTrusted()) {
    return YES;
  }

  NSDictionary *options = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt : @YES};
  BOOL granted = AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)options);
  if (granted && AXIsProcessTrusted()) {
    return YES;
  }

  LogError(@"Accessibility access is required; enable Camofox VNC Host in System Settings > Privacy & Security > Accessibility");
  return NO;
}

static char **CopyCStringVector(NSArray<NSString *> *strings) {
  char **vector = calloc(strings.count + 1, sizeof(char *));
  if (!vector) {
    return NULL;
  }

  for (NSUInteger index = 0; index < strings.count; ++index) {
    vector[index] = strdup(strings[index].UTF8String);
    if (!vector[index]) {
      for (NSUInteger previous = 0; previous < index; ++previous) {
        free(vector[previous]);
      }
      free(vector);
      return NULL;
    }
  }
  return vector;
}

static void FreeCStringVector(char **vector) {
  if (!vector) {
    return;
  }
  for (char **entry = vector; *entry; ++entry) {
    free(*entry);
  }
  free(vector);
}

static NSArray<NSString *> *MergedEnvironmentStrings(NSDictionary<NSString *, NSString *> *configured) {
  NSMutableDictionary<NSString *, NSString *> *environment =
      [[[NSProcessInfo processInfo] environment] mutableCopy];
  [environment addEntriesFromDictionary:configured];

  NSArray<NSString *> *keys = [environment.allKeys sortedArrayUsingSelector:@selector(compare:)];
  NSMutableArray<NSString *> *entries = [NSMutableArray arrayWithCapacity:keys.count];
  for (NSString *key in keys) {
    NSString *value = environment[key];
    if (!IsCStringSafe(key) || [key rangeOfString:@"="].location != NSNotFound || !IsCStringSafe(value)) {
      LogError(@"inherited environment contains an entry that cannot be passed to the child");
      return nil;
    }
    [entries addObject:[NSString stringWithFormat:@"%@=%@", key, value]];
  }
  return entries;
}

static void ForwardSignal(int signalNumber) {
  sig_atomic_t child = ChildPID;
  if (child > 0) {
    kill((pid_t)child, signalNumber);
  }
}

static BOOL InstallSignalForwarders(void) {
  struct sigaction action;
  memset(&action, 0, sizeof(action));
  action.sa_handler = ForwardSignal;
  sigemptyset(&action.sa_mask);

  if (sigaction(SIGTERM, &action, NULL) != 0 || sigaction(SIGINT, &action, NULL) != 0) {
    LogError(@"cannot install signal handlers: %s", strerror(errno));
    return NO;
  }
  return YES;
}

static int SpawnAndWait(NSDictionary<NSString *, id> *config) {
  NSString *executable = config[@"Executable"];
  NSArray<NSString *> *configuredArguments = config[@"Arguments"];
  NSMutableArray<NSString *> *arguments = [NSMutableArray arrayWithObject:executable];
  [arguments addObjectsFromArray:configuredArguments];

  NSArray<NSString *> *environmentStrings = MergedEnvironmentStrings(config[@"Environment"]);
  if (!environmentStrings) {
    return EX_CONFIG;
  }

  char **argumentVector = CopyCStringVector(arguments);
  char **environmentVector = CopyCStringVector(environmentStrings);
  if (!argumentVector || !environmentVector) {
    LogError(@"cannot allocate child process arguments");
    FreeCStringVector(argumentVector);
    FreeCStringVector(environmentVector);
    return EX_OSERR;
  }

  if (!InstallSignalForwarders()) {
    FreeCStringVector(argumentVector);
    FreeCStringVector(environmentVector);
    return EX_OSERR;
  }

  sigset_t forwardedSignals;
  sigemptyset(&forwardedSignals);
  sigaddset(&forwardedSignals, SIGTERM);
  sigaddset(&forwardedSignals, SIGINT);
  sigset_t previousMask;
  if (sigprocmask(SIG_BLOCK, &forwardedSignals, &previousMask) != 0) {
    LogError(@"cannot block signals while spawning: %s", strerror(errno));
    FreeCStringVector(argumentVector);
    FreeCStringVector(environmentVector);
    return EX_OSERR;
  }

  posix_spawnattr_t attributes;
  int spawnError = posix_spawnattr_init(&attributes);
  BOOL attributesInitialized = spawnError == 0;
  if (attributesInitialized) {
    sigset_t defaultSignals;
    sigemptyset(&defaultSignals);
    sigaddset(&defaultSignals, SIGTERM);
    sigaddset(&defaultSignals, SIGINT);
    spawnError = posix_spawnattr_setsigmask(&attributes, &previousMask);
    if (spawnError == 0) {
      spawnError = posix_spawnattr_setsigdefault(&attributes, &defaultSignals);
    }
    if (spawnError == 0) {
      spawnError = posix_spawnattr_setflags(
          &attributes, POSIX_SPAWN_SETSIGMASK | POSIX_SPAWN_SETSIGDEF);
    }
  }

  pid_t child = 0;
  if (spawnError == 0) {
    spawnError = posix_spawn(&child,
                             executable.fileSystemRepresentation,
                             NULL,
                             &attributes,
                             argumentVector,
                             environmentVector);
  }
  if (spawnError == 0) {
    ChildPID = (sig_atomic_t)child;
  }

  int restoreError = sigprocmask(SIG_SETMASK, &previousMask, NULL);
  int restoreErrno = restoreError == 0 ? 0 : errno;
  if (attributesInitialized) {
    posix_spawnattr_destroy(&attributes);
  }
  FreeCStringVector(argumentVector);
  FreeCStringVector(environmentVector);

  if (spawnError != 0) {
    LogError(@"cannot start %@: %s", executable, strerror(spawnError));
    return EX_OSERR;
  }
  if (restoreError != 0) {
    LogError(@"cannot restore signal mask after spawning %@: %s",
             executable,
             strerror(restoreErrno));
    kill(child, SIGTERM);
  }

  int status = 0;
  pid_t waited;
  do {
    waited = waitpid(child, &status, 0);
  } while (waited < 0 && errno == EINTR);
  ChildPID = 0;

  if (waited < 0) {
    LogError(@"cannot wait for %@: %s", executable, strerror(errno));
    return EX_OSERR;
  }
  if (WIFEXITED(status)) {
    return WEXITSTATUS(status);
  }
  if (WIFSIGNALED(status)) {
    return 128 + WTERMSIG(status);
  }

  LogError(@"%@ ended with an unrecognized process status", executable);
  return EX_OSERR;
}

int main(int argc, const char *argv[]) {
  (void)argv;
  @autoreleasepool {
    if (argc != 1) {
      LogError(@"this host accepts no command-line arguments; configure only %@", ConfigPath);
      return EX_USAGE;
    }

    NSDictionary<NSString *, id> *config = LoadConfig();
    if (!config) {
      return EX_CONFIG;
    }

    BOOL permissionsAvailable = YES;
    if ([config[@"RequireScreenRecording"] boolValue]) {
      permissionsAvailable = EnsureScreenRecordingPermission() && permissionsAvailable;
    }
    if ([config[@"RequireAccessibility"] boolValue]) {
      permissionsAvailable = EnsureAccessibilityPermission() && permissionsAvailable;
    }
    if (!permissionsAvailable) {
      return EX_NOPERM;
    }

    return SpawnAndWait(config);
  }
}
