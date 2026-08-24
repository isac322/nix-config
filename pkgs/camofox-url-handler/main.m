#import <Cocoa/Cocoa.h>
#import <dispatch/dispatch.h>

#ifndef CAMOFOX_API_PORT
#define CAMOFOX_API_PORT 9377
#endif

static NSURL *CamofoxEndpointURL(void) {
  NSString *endpoint = [NSString stringWithFormat:@"http://127.0.0.1:%d/tabs", CAMOFOX_API_PORT];
  return [NSURL URLWithString:endpoint];
}
static NSString *const CamofoxUserID = @"omp";
static NSString *const CamofoxSessionKey = @"default-browser";

static void LogFailure(NSString *message) {
  fprintf(stderr, "camofox-open-url: %s\n", message.UTF8String);
  NSLog(@"camofox-open-url: %@", message);
}

static BOOL OpenURLInCamofox(NSURL *url) {
  NSString *scheme = url.scheme.lowercaseString;
  if (!url || !([scheme isEqualToString:@"http"] || [scheme isEqualToString:@"https"])) {
    LogFailure([NSString stringWithFormat:@"refusing non-HTTP URL: %@", url.absoluteString ?: @"(null)"]);
    return NO;
  }

  NSError *jsonError = nil;
  NSData *body = [NSJSONSerialization dataWithJSONObject:@{
    @"url" : url.absoluteString,
    @"userId" : CamofoxUserID,
    @"sessionKey" : CamofoxSessionKey,
  } options:0 error:&jsonError];
  if (!body) {
    LogFailure([NSString stringWithFormat:@"could not encode request: %@", jsonError.localizedDescription]);
    return NO;
  }

  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:CamofoxEndpointURL()];
  request.HTTPMethod = @"POST";
  request.HTTPBody = body;
  request.timeoutInterval = 40.0;
  [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];

  NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
  NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
  dispatch_semaphore_t finished = dispatch_semaphore_create(0);
  __block NSData *responseData = nil;
  __block NSURLResponse *response = nil;
  __block NSError *requestError = nil;

  NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                         completionHandler:^(NSData *data, NSURLResponse *receivedResponse, NSError *error) {
    responseData = data;
    response = receivedResponse;
    requestError = error;
    dispatch_semaphore_signal(finished);
  }];
  [task resume];

  if (dispatch_semaphore_wait(finished, dispatch_time(DISPATCH_TIME_NOW, 45 * NSEC_PER_SEC)) != 0) {
    [task cancel];
    [session invalidateAndCancel];
    LogFailure(@"Camofox API did not answer within 45 seconds");
    return NO;
  }
  [session finishTasksAndInvalidate];

  if (requestError) {
    LogFailure([NSString stringWithFormat:@"Camofox API request failed: %@", requestError.localizedDescription]);
    return NO;
  }

  NSInteger status = [(NSHTTPURLResponse *)response statusCode];
  if (status < 200 || status >= 300) {
    NSString *responseText = responseData
      ? [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding]
      : @"";
    LogFailure([NSString stringWithFormat:@"Camofox API returned HTTP %ld: %@", (long)status, responseText]);
    return NO;
  }

  return YES;
}

@interface CamofoxAppDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic) NSUInteger pendingURLCount;
@property(nonatomic) dispatch_queue_t workerQueue;
@end

@implementation CamofoxAppDelegate

- (instancetype)init {
  self = [super init];
  if (self) {
    _workerQueue = dispatch_queue_create("com.bhyoo.camofox-url-handler", DISPATCH_QUEUE_SERIAL);
  }
  return self;
}

- (void)scheduleTerminationAfter:(NSTimeInterval)delay {
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{
    if (self.pendingURLCount == 0) {
      [NSApp terminate:nil];
    }
  });
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
  (void)notification;
  [self scheduleTerminationAfter:2.0];
}

- (void)application:(NSApplication *)application openURLs:(NSArray<NSURL *> *)urls {
  (void)application;
  self.pendingURLCount += urls.count;

  for (NSURL *url in urls) {
    dispatch_async(self.workerQueue, ^{
      OpenURLInCamofox(url);
      dispatch_async(dispatch_get_main_queue(), ^{
        self.pendingURLCount -= 1;
        [self scheduleTerminationAfter:1.0];
      });
    });
  }
}

@end

int main(int argc, const char *argv[]) {
  @autoreleasepool {
    NSMutableArray<NSURL *> *argumentURLs = [NSMutableArray array];
    for (int index = 1; index < argc; ++index) {
      NSString *argument = [NSString stringWithUTF8String:argv[index]];
      if (!argument) {
        LogFailure(@"refusing argument that is not valid UTF-8");
        return 1;
      }
      if ([argument hasPrefix:@"-psn_"]) {
        continue;
      }
      NSURL *url = [NSURL URLWithString:argument];
      if (url) {
        [argumentURLs addObject:url];
      }
    }

    if (argumentURLs.count > 0) {
      BOOL succeeded = YES;
      for (NSURL *url in argumentURLs) {
        succeeded = OpenURLInCamofox(url) && succeeded;
      }
      return succeeded ? 0 : 1;
    }

    NSApplication *application = [NSApplication sharedApplication];
    [application setActivationPolicy:NSApplicationActivationPolicyAccessory];
    CamofoxAppDelegate *delegate = [[CamofoxAppDelegate alloc] init];
    application.delegate = delegate;
    [application run];
  }
  return 0;
}
