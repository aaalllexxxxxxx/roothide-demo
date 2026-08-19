// crack_dylib.m
// 完整版：卡密验证弹窗 + PUBG HUD 绕过验证
// - 独立 UIWindow 盖住 app，阻止触摸
// - 弹卡密输入弹窗，输入正确才解锁
// - 卡密正确后：注入 offsets + feature config + swizzle 验证管道
// - 保护性 hook：阻止吊销/心跳/会话结束
// - 持久化：验证过后不再弹
//
// 编译:
// clang -arch arm64 -dynamiclib -framework Foundation -framework UIKit \
//   -framework QuartzCore -undefined dynamic_lookup -flat_namespace \
//   -isysroot $(xcrun --sdk iphoneos --show-sdk-path) \
//   -target arm64-apple-ios14.0 \
//   -o crack.dylib crack_dylib.m

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>

// ====== 常量 ======
static NSString *const KAMI_CORRECT = @"XianyuWeihuabinggan";
static NSString *const KEY_KAMI_VERIFIED = @"crack_kami_verified";

// ====== 前向声明（app 内的类） ======
@interface NwGameOffsets : NSObject
+ (void)applyDictionary:(NSDictionary *)dict;
+ (BOOL)isReady;
@end

@interface NxFeat : NSObject
+ (void)applyDictionary:(NSDictionary *)dict;
+ (BOOL)isReady;
@end

@interface NwSession : NSObject
+ (BOOL)runtimeLicenseOK;
- (void)setRuntimeLicenseOK:(BOOL)val;
- (void)nw_revokeRuntimeLicense:(BOOL)arg;
- (void)nw_sessEnd:(NSInteger)status message:(NSString *)msg;
- (void)clearSession;
- (void)startLicenseWatchWithInterval:(double)interval;
- (void)startHeartbeatWithInterval:(double)interval onResult:(id)block;
+ (void)showForceExitAlertWithMessage:(NSString *)msg;
@end

@interface NwEntryPanel : UIView
- (void)beginVerification;
- (void)nw_runEntryPipeline;
- (void)onActivateTap;
- (void)finishSuccess;
- (void)setBusy:(BOOL)busy;
- (void)setHidden:(BOOL)hidden;
@end

@interface MainRootViewController : UIViewController
- (void)nw_onSessEnd:(id)notif;
@end

// ====== 全局引用 ======
static UIWindow *g_crackWindow = nil;
static BOOL g_alertShowing = NO;
static BOOL g_bypassInstalled = NO;
static BOOL g_finishSuccessDone = NO;
static BOOL g_injected = NO;

// ====== 遮罩视图（吞掉触摸事件，透明不可见） ======
@interface CrackBlockerView : UIView
@end

@implementation CrackBlockerView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    return nil;
}
@end

// ====== 空的 ViewController（给 UIWindow 用） ======
@interface CrackViewController : UIViewController
@end

@implementation CrackViewController
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
}
- (BOOL)shouldAutorotate { return YES; }
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}
@end

// ====== 创建/显示独立窗口 ======
static UIViewController *getCrackRootVC() {
    if (!g_crackWindow) {
        CGRect screenBounds = [UIScreen mainScreen].bounds;
        g_crackWindow = [[UIWindow alloc] initWithFrame:screenBounds];
        g_crackWindow.windowLevel = UIWindowLevelAlert;
        g_crackWindow.backgroundColor = [UIColor clearColor];
        g_crackWindow.rootViewController = [[CrackViewController alloc] init];
        g_crackWindow.hidden = NO;
        [g_crackWindow makeKeyAndVisible];
        NSLog(@"[CRACK] crack window created");
    } else {
        g_crackWindow.hidden = NO;
        [g_crackWindow makeKeyAndVisible];
    }
    return g_crackWindow.rootViewController;
}

// ====== 持久化保护数据 ======
static void persistBypassData() {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSInteger exp2038 = 2147483647;
    [defaults setInteger:1 forKey:@"nw_authMode"];
    [defaults setInteger:1 forKey:@"authMode"];
    [defaults setBool:YES forKey:@"nw_licOK"];
    [defaults setBool:YES forKey:@"runtimeLicenseOK"];
    [defaults setInteger:exp2038 forKey:@"nw_kamiExp"];
    [defaults setInteger:exp2038 forKey:@"kamiExpireUnix"];
    [defaults setInteger:exp2038 forKey:@"tokenExpireUnix"];
    [defaults setBool:YES forKey:@"nw_activated"];
    [defaults setBool:YES forKey:@"nw_runtime_ok"];
    [defaults synchronize];
    NSLog(@"[CRACK] persistBypassData done");
}

// ====== 注入 offsets 和 feature config ======
static void injectOffsetsAndFeature() {
    if (g_injected) return;
    g_injected = YES;

    @autoreleasepool {
        NSLog(@"[CRACK] Injecting offsets and feature config...");

        // 构造 offsets 字典
        NSMutableDictionary *offsetsDict = [NSMutableDictionary dictionary];
        [offsetsDict setObject:@"0x10C464C8" forKey:@"gWorld"];

        NSMutableDictionary *offsetsFull = [NSMutableDictionary dictionary];
        [offsetsFull setObject:@"pubg" forKey:@"game"];
        [offsetsFull setObject:@(1) forKey:@"cfg_ver"];
        [offsetsFull setObject:@(2147483647) forKey:@"exp"];
        [offsetsFull setObject:offsetsDict forKey:@"offsets"];

        // 调用 NwGameOffsets applyDictionary:
        @try {
            [NwGameOffsets applyDictionary:offsetsFull];
            NSLog(@"[CRACK] NwGameOffsets applyDictionary: injected!");
        } @catch (NSException *e) {
            NSLog(@"[CRACK] NwGameOffsets applyDictionary: error: %@", e);
        }

        // 检查 isReady
        @try {
            BOOL ready = [NwGameOffsets isReady];
            NSLog(@"[CRACK] NwGameOffsets.isReady = %d", ready);
        } @catch (NSException *e) {}

        // 构造 feature config 字典
        NSMutableDictionary *featDict = [NSMutableDictionary dictionary];
        [featDict setObject:@(1) forKey:@"cfg_ver"];
        [featDict setObject:@(1) forKey:@"esp_enabled"];
        [featDict setObject:@(2147483647) forKey:@"exp"];

        // 调用 NxFeat applyDictionary:
        @try {
            [NxFeat applyDictionary:featDict];
            NSLog(@"[CRACK] NxFeat applyDictionary: injected!");
        } @catch (NSException *e) {
            NSLog(@"[CRACK] NxFeat applyDictionary: error: %@", e);
        }

        // 检查 NxFeat isReady
        @try {
            BOOL featReady = [NxFeat isReady];
            NSLog(@"[CRACK] NxFeat.isReady = %d", featReady);
        } @catch (NSException *e) {}
    }
}

// ====== Method Swizzle 工具 ======
static void swizzleMethod(Class class, SEL originalSel, SEL swizzledSel) {
    Method originalMethod = class_getInstanceMethod(class, originalSel);
    Method swizzledMethod = class_getInstanceMethod(class, swizzledSel);
    if (originalMethod && swizzledMethod) {
        method_exchangeImplementations(originalMethod, swizzledMethod);
    }
}

static void swizzleClassMethod(Class class, SEL originalSel, SEL swizzledSel) {
    Method originalMethod = class_getClassMethod(class, originalSel);
    Method swizzledMethod = class_getClassMethod(class, swizzledSel);
    if (originalMethod && swizzledMethod) {
        method_exchangeImplementations(originalMethod, swizzledMethod);
    }
}

// ====== Swizzled 方法实现 ======

@interface NwEntryPanel (Crack)
- (void)crack_beginVerification;
- (void)crack_onActivateTap;
- (void)crack_nw_runEntryPipeline;
- (void)crack_finishSuccess;
@end

@interface NwSession (Crack)
- (void)crack_setRuntimeLicenseOK:(BOOL)val;
- (void)crack_nw_revokeRuntimeLicense:(BOOL)arg;
- (void)crack_nw_sessEnd:(NSInteger)status message:(NSString *)msg;
- (void)crack_clearSession;
- (void)crack_startLicenseWatchWithInterval:(double)interval;
- (void)crack_startHeartbeatWithInterval:(double)interval onResult:(id)block;
+ (void)crack_showForceExitAlertWithMessage:(NSString *)msg;
@end

@interface MainRootViewController (Crack)
- (void)crack_nw_onSessEnd:(id)notif;
@end

// ---- NwEntryPanel swizzled methods ----
@implementation NwEntryPanel (Crack)

- (void)crack_beginVerification {
    @autoreleasepool {
        NSLog(@"[CRACK] beginVerification → inject + finishSuccess");
        injectOffsetsAndFeature();
        @try {
            NwEntryPanel *panel = (NwEntryPanel *)self;
            [panel setBusy:NO];
            [panel finishSuccess];
        } @catch (NSException *e) {
            NSLog(@"[CRACK] finishSuccess error: %@", e);
        }
    }
}

- (void)crack_onActivateTap {
    @autoreleasepool {
        NSLog(@"[CRACK] onActivateTap → inject + finishSuccess");
        injectOffsetsAndFeature();
        @try {
            NwEntryPanel *panel = (NwEntryPanel *)self;
            [panel setBusy:NO];
            [panel finishSuccess];
        } @catch (NSException *e) {
            NSLog(@"[CRACK] finishSuccess error: %@", e);
        }
    }
}

- (void)crack_nw_runEntryPipeline {
    @autoreleasepool {
        NSLog(@"[CRACK] nw_runEntryPipeline → inject + finishSuccess");
        injectOffsetsAndFeature();
        @try {
            NwEntryPanel *panel = (NwEntryPanel *)self;
            [panel setBusy:NO];
            [panel finishSuccess];
        } @catch (NSException *e) {
            NSLog(@"[CRACK] finishSuccess error: %@", e);
        }
    }
}

- (void)crack_finishSuccess {
    @autoreleasepool {
        NSLog(@"[CRACK] finishSuccess intercepted");
        if (g_finishSuccessDone) {
            NSLog(@"[CRACK] finishSuccess already done, skip");
            return;
        }
        g_finishSuccessDone = YES;

        injectOffsetsAndFeature();

        // 调用原始实现
        [(id)self crack_finishSuccess];
        NSLog(@"[CRACK] finishSuccess original done");
    }
}

@end

// ---- NwSession swizzled methods ----
@implementation NwSession (Crack)

- (void)crack_setRuntimeLicenseOK:(BOOL)val {
    // 强制始终 YES
    [(id)self crack_setRuntimeLicenseOK:YES];
}

- (void)crack_nw_revokeRuntimeLicense:(BOOL)arg {
    NSLog(@"[CRACK] Blocked nw_revokeRuntimeLicense:");
}

- (void)crack_nw_sessEnd:(NSInteger)status message:(NSString *)msg {
    NSLog(@"[CRACK] Blocked nw_sessEnd:status:");
}

- (void)crack_clearSession {
    NSLog(@"[CRACK] Blocked clearSession");
    persistBypassData();
}

- (void)crack_startLicenseWatchWithInterval:(double)interval {
    NSLog(@"[CRACK] Blocked startLicenseWatch");
}

- (void)crack_startHeartbeatWithInterval:(double)interval onResult:(id)block {
    NSLog(@"[CRACK] Blocked startHeartbeat");
}

+ (void)crack_showForceExitAlertWithMessage:(NSString *)msg {
    NSLog(@"[CRACK] Blocked showForceExitAlertWithMessage:");
}

@end

// ---- MainRootViewController swizzled methods ----
@implementation MainRootViewController (Crack)

- (void)crack_nw_onSessEnd:(id)notif {
    NSLog(@"[CRACK] Blocked nw_onSessEnd:");
}

@end

// ====== 安装保护性 swizzle ======
static void installBypassSwizzles() {
    if (g_bypassInstalled) return;
    g_bypassInstalled = YES;

    @autoreleasepool {
        NSLog(@"[CRACK] ===== Installing bypass swizzles =====");

        // 持久化保护数据
        persistBypassData();

        // NwEntryPanel swizzle
        Class panelClass = objc_getClass("NwEntryPanel");
        NSLog(@"[CRACK] NwEntryPanel class = %@", panelClass);
        if (panelClass) {
            swizzleMethod(panelClass,
                NSSelectorFromString(@"beginVerification"),
                NSSelectorFromString(@"crack_beginVerification"));
            NSLog(@"[CRACK] Swizzled beginVerification");

            swizzleMethod(panelClass,
                NSSelectorFromString(@"onActivateTap"),
                NSSelectorFromString(@"crack_onActivateTap"));
            NSLog(@"[CRACK] Swizzled onActivateTap");

            swizzleMethod(panelClass,
                NSSelectorFromString(@"nw_runEntryPipeline"),
                NSSelectorFromString(@"crack_nw_runEntryPipeline"));
            NSLog(@"[CRACK] Swizzled nw_runEntryPipeline");

            swizzleMethod(panelClass,
                NSSelectorFromString(@"finishSuccess"),
                NSSelectorFromString(@"crack_finishSuccess"));
            NSLog(@"[CRACK] Swizzled finishSuccess");
        } else {
            NSLog(@"[CRACK] WARNING: NwEntryPanel not found!");
        }

        // NwSession swizzle
        Class sessionClass = objc_getClass("NwSession");
        NSLog(@"[CRACK] NwSession class = %@", sessionClass);
        if (sessionClass) {
            swizzleMethod(sessionClass,
                NSSelectorFromString(@"setRuntimeLicenseOK:"),
                NSSelectorFromString(@"crack_setRuntimeLicenseOK:"));

            swizzleMethod(sessionClass,
                NSSelectorFromString(@"nw_revokeRuntimeLicense:"),
                NSSelectorFromString(@"crack_nw_revokeRuntimeLicense:"));

            // 尝试两种 sessEnd 签名
            Method m = class_getInstanceMethod(sessionClass,
                NSSelectorFromString(@"nw_sessEnd:status:message:"));
            if (m) {
                swizzleMethod(sessionClass,
                    NSSelectorFromString(@"nw_sessEnd:status:message:"),
                    NSSelectorFromString(@"crack_nw_sessEnd:message:"));
                NSLog(@"[CRACK] Swizzled nw_sessEnd:status:message:");
            }

            m = class_getInstanceMethod(sessionClass,
                NSSelectorFromString(@"nw_sessEnd:status:"));
            if (m) {
                swizzleMethod(sessionClass,
                    NSSelectorFromString(@"nw_sessEnd:status:"),
                    NSSelectorFromString(@"crack_nw_sessEnd:message:"));
                NSLog(@"[CRACK] Swizzled nw_sessEnd:status:");
            }

            swizzleMethod(sessionClass,
                NSSelectorFromString(@"clearSession"),
                NSSelectorFromString(@"crack_clearSession"));

            swizzleMethod(sessionClass,
                NSSelectorFromString(@"startLicenseWatchWithInterval:"),
                NSSelectorFromString(@"crack_startLicenseWatchWithInterval:"));

            swizzleMethod(sessionClass,
                NSSelectorFromString(@"startHeartbeatWithInterval:onResult:"),
                NSSelectorFromString(@"crack_startHeartbeatWithInterval:onResult:"));

            swizzleClassMethod(sessionClass,
                NSSelectorFromString(@"showForceExitAlertWithMessage:"),
                NSSelectorFromString(@"crack_showForceExitAlertWithMessage:"));
            NSLog(@"[CRACK] NwSession swizzles done");
        } else {
            NSLog(@"[CRACK] WARNING: NwSession not found!");
        }

        // MainRootViewController swizzle
        Class rootClass = objc_getClass("MainRootViewController");
        NSLog(@"[CRACK] MainRootViewController class = %@", rootClass);
        if (rootClass) {
            swizzleMethod(rootClass,
                NSSelectorFromString(@"nw_onSessEnd:"),
                NSSelectorFromString(@"crack_nw_onSessEnd:"));
            NSLog(@"[CRACK] Swizzled nw_onSessEnd:");
        }

        NSLog(@"[CRACK] ===== All bypass swizzles installed =====");
    }
}

// ====== 弹窗逻辑 ======
static void showKamiAlert();

static void showKamiAlert() {
    @autoreleasepool {
        NSLog(@"[CRACK] showKamiAlert");

        // 检查是否已验证过（持久化）
        BOOL alreadyVerified = [[NSUserDefaults standardUserDefaults] boolForKey:KEY_KAMI_VERIFIED];
        if (alreadyVerified) {
            NSLog(@"[CRACK] already verified (persisted), skip");
            g_crackWindow.hidden = YES;
            return;
        }

        if (g_alertShowing) {
            NSLog(@"[CRACK] alert already showing, skip");
            return;
        }

        UIViewController *rootVC = getCrackRootVC();
        if (rootVC.presentedViewController) {
            NSLog(@"[CRACK] something already presented, skip");
            return;
        }

        g_alertShowing = YES;

        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"PUBG HUD"
                             message:@"请输入卡密"
                      preferredStyle:UIAlertControllerStyleAlert];

        [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.placeholder = @"输入卡密";
            textField.secureTextEntry = YES;
            textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
            textField.autocorrectionType = UITextAutocorrectionTypeNo;
            textField.font = [UIFont systemFontOfSize:16];
        }];

        UIAlertAction *verifyAction = [UIAlertAction
            actionWithTitle:@"激 活"
                      style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *action) {
                g_alertShowing = NO;
                NSString *input = alert.textFields.firstObject.text;
                NSLog(@"[CRACK] input: %@", input);

                if ([input isEqualToString:KAMI_CORRECT]) {
                    // 卡密正确
                    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:KEY_KAMI_VERIFIED];
                    [[NSUserDefaults standardUserDefaults] synchronize];
                    NSLog(@"[CRACK] kami correct! persisted.");

                    // 安装绕过 swizzle
                    installBypassSwizzles();

                    // 隐藏遮罩窗口
                    g_crackWindow.hidden = YES;
                    NSLog(@"[CRACK] bypass installed, window hidden");

                } else {
                    NSLog(@"[CRACK] kami wrong, retry");
                    UIAlertController *errorAlert = [UIAlertController
                        alertControllerWithTitle:@"卡密错误"
                                         message:@"卡密不正确，请重新输入"
                                  preferredStyle:UIAlertControllerStyleAlert];

                    UIAlertAction *retryAction = [UIAlertAction
                        actionWithTitle:@"重新输入"
                                  style:UIAlertActionStyleDefault
                                handler:^(UIAlertAction *a) {
                            showKamiAlert();
                        }];

                    [errorAlert addAction:retryAction];
                    [rootVC presentViewController:errorAlert animated:NO completion:nil];
                }
            }];

        UIAlertAction *cancelAction = [UIAlertAction
            actionWithTitle:@"取消"
                      style:UIAlertActionStyleCancel
                    handler:^(UIAlertAction *action) {
                NSLog(@"[CRACK] user cancelled, crash exit");
                abort();
            }];

        [alert addAction:verifyAction];
        [alert addAction:cancelAction];

        [rootVC presentViewController:alert animated:NO completion:nil];
        NSLog(@"[CRACK] alert presented");
    }
}

// ====== dylib 加载入口 ======
__attribute__((constructor))
static void crack_init(int argc, const char **argv) {
    @autoreleasepool {
        NSLog(@"[CRACK] ===== crack.dylib loaded =====");

        dispatch_async(dispatch_get_main_queue(), ^{
            BOOL alreadyVerified = [[NSUserDefaults standardUserDefaults] boolForKey:KEY_KAMI_VERIFIED];

            if (alreadyVerified) {
                // 已验证，直接安装绕过 swizzle（不需要弹窗）
                NSLog(@"[CRACK] already verified, installing bypass directly");
                installBypassSwizzles();
                return;
            }

            // 未验证：创建独立窗口盖住 app，阻止触摸
            UIViewController *rootVC = getCrackRootVC();
            [rootVC loadViewIfNeeded];

            // 把 rootVC.view 替换成吞触摸的 blocker
            CrackBlockerView *blocker = [[CrackBlockerView alloc] initWithFrame:[UIScreen mainScreen].bounds];
            blocker.backgroundColor = [UIColor clearColor];
            blocker.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [rootVC setValue:blocker forKey:@"view"];
            NSLog(@"[CRACK] blocker view set as rootVC.view");

            // 监听 app 激活，弹出卡密弹窗
            [[NSNotificationCenter defaultCenter]
                addObserverForName:UIApplicationDidBecomeActiveNotification
                            object:nil
                             queue:[NSOperationQueue mainQueue]
                        usingBlock:^(NSNotification *note) {
                    NSLog(@"[CRACK] app became active, showing kami alert");
                    showKamiAlert();
                }];
        });
    }
}
