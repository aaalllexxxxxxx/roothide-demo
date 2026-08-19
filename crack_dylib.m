// crack_dylib.m
// 完整版：卡密验证弹窗 + PUBG HUD 绕过验证
// 用 IMP hook（类似 Frida Interceptor.replace）而非 method_exchange
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

// 保存原始 IMP
static IMP g_orig_beginVerification = NULL;
static IMP g_orig_onActivateTap = NULL;
static IMP g_orig_nw_runEntryPipeline = NULL;
static IMP g_orig_finishSuccess = NULL;
static IMP g_orig_setRuntimeLicenseOK = NULL;
static IMP g_orig_nw_revokeRuntimeLicense = NULL;
static IMP g_orig_clearSession = NULL;
static IMP g_orig_startLicenseWatch = NULL;
static IMP g_orig_startHeartbeat = NULL;
static IMP g_orig_showForceExitAlert = NULL;
static IMP g_orig_nw_onSessEnd = NULL;

// ====== 遮罩视图 ======
@interface CrackBlockerView : UIView
@end

@implementation CrackBlockerView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    return nil;
}
@end

// ====== 空的 ViewController ======
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

        NSMutableDictionary *offsetsDict = [NSMutableDictionary dictionary];
        [offsetsDict setObject:@"0x10C464C8" forKey:@"gWorld"];

        NSMutableDictionary *offsetsFull = [NSMutableDictionary dictionary];
        [offsetsFull setObject:@"pubg" forKey:@"game"];
        [offsetsFull setObject:@(1) forKey:@"cfg_ver"];
        [offsetsFull setObject:@(2147483647) forKey:@"exp"];
        [offsetsFull setObject:offsetsDict forKey:@"offsets"];

        @try {
            [NwGameOffsets applyDictionary:offsetsFull];
            NSLog(@"[CRACK] NwGameOffsets applyDictionary: injected!");
        } @catch (NSException *e) {
            NSLog(@"[CRACK] NwGameOffsets applyDictionary: error: %@", e);
        }

        @try {
            BOOL ready = [NwGameOffsets isReady];
            NSLog(@"[CRACK] NwGameOffsets.isReady = %d", ready);
        } @catch (NSException *e) {}

        NSMutableDictionary *featDict = [NSMutableDictionary dictionary];
        [featDict setObject:@(1) forKey:@"cfg_ver"];
        [featDict setObject:@(1) forKey:@"esp_enabled"];
        [featDict setObject:@(2147483647) forKey:@"exp"];

        @try {
            [NxFeat applyDictionary:featDict];
            NSLog(@"[CRACK] NxFeat applyDictionary: injected!");
        } @catch (NSException *e) {
            NSLog(@"[CRACK] NxFeat applyDictionary: error: %@", e);
        }

        @try {
            BOOL featReady = [NxFeat isReady];
            NSLog(@"[CRACK] NxFeat.isReady = %d", featReady);
        } @catch (NSException *e) {}
    }
}

// ====== IMP hook 工具（类似 Frida Interceptor.replace） ======
// 保存原始 IMP，用 class_replaceMethod 替换为新实现
// 新实现里可以通过保存的 orig IMP 调用原始方法
static IMP hookInstanceMethod(Class cls, SEL sel, IMP newImp) {
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) {
        NSLog(@"[CRACK] hookInstanceMethod: method %@ not found on %@",
              NSStringFromSelector(sel), cls);
        return NULL;
    }
    // 先保存原始 IMP
    IMP origImp = method_getImplementation(m);
    // 如果类没有实现这个方法（继承的），要先添加
    // class_replaceMethod: 如果方法不存在会添加，如果存在会替换
    class_replaceMethod(cls, sel, newImp, method_getTypeEncoding(m));
    return origImp;
}

static IMP hookClassMethod(Class cls, SEL sel, IMP newImp) {
    Method m = class_getClassMethod(cls, sel);
    if (!m) {
        NSLog(@"[CRACK] hookClassMethod: method %@ not found on %@",
              NSStringFromSelector(sel), cls);
        return NULL;
    }
    IMP origImp = method_getImplementation(m);
    // 类方法的替换需要改 meta class
    Class metaCls = object_getClass(cls);
    class_replaceMethod(metaCls, sel, newImp, method_getTypeEncoding(m));
    return origImp;
}

// ====== Hook 函数实现（C 函数，直接操作 IMP） ======

// beginVerification → 注入 + finishSuccess
static void hook_beginVerification(id self, SEL _cmd) {
    @autoreleasepool {
        NSLog(@"[CRACK] beginVerification → inject + finishSuccess");
        injectOffsetsAndFeature();
        @try {
            NwEntryPanel *panel = (NwEntryPanel *)self;
            [panel setBusy:NO];
            // 直接调原始 finishSuccess（不经过 hook，因为我们要让它跑）
            // 但 finishSuccess 也被 hook 了，我们用保存的 orig IMP
            if (g_orig_finishSuccess) {
                ((void(*)(id, SEL))g_orig_finishSuccess)(self, @selector(finishSuccess));
            }
        } @catch (NSException *e) {
            NSLog(@"[CRACK] finishSuccess error: %@", e);
        }
    }
}

// onActivateTap → 注入 + finishSuccess
static void hook_onActivateTap(id self, SEL _cmd) {
    @autoreleasepool {
        NSLog(@"[CRACK] onActivateTap → inject + finishSuccess");
        injectOffsetsAndFeature();
        @try {
            NwEntryPanel *panel = (NwEntryPanel *)self;
            [panel setBusy:NO];
            if (g_orig_finishSuccess) {
                ((void(*)(id, SEL))g_orig_finishSuccess)(self, @selector(finishSuccess));
            }
        } @catch (NSException *e) {
            NSLog(@"[CRACK] finishSuccess error: %@", e);
        }
    }
}

// nw_runEntryPipeline → 注入 + finishSuccess
static void hook_nw_runEntryPipeline(id self, SEL _cmd) {
    @autoreleasepool {
        NSLog(@"[CRACK] nw_runEntryPipeline → inject + finishSuccess");
        injectOffsetsAndFeature();
        @try {
            NwEntryPanel *panel = (NwEntryPanel *)self;
            [panel setBusy:NO];
            if (g_orig_finishSuccess) {
                ((void(*)(id, SEL))g_orig_finishSuccess)(self, @selector(finishSuccess));
            }
        } @catch (NSException *e) {
            NSLog(@"[CRACK] finishSuccess error: %@", e);
        }
    }
}

// finishSuccess → 保护，防止重复调用
static void hook_finishSuccess(id self, SEL _cmd) {
    @autoreleasepool {
        NSLog(@"[CRACK] finishSuccess intercepted");
        if (g_finishSuccessDone) {
            NSLog(@"[CRACK] finishSuccess already done, skip");
            return;
        }
        g_finishSuccessDone = YES;

        injectOffsetsAndFeature();

        // 调原始实现
        if (g_orig_finishSuccess) {
            ((void(*)(id, SEL))g_orig_finishSuccess)(self, _cmd);
            NSLog(@"[CRACK] finishSuccess original done");
        } else {
            // 没有原始实现，手动隐藏面板
            @try {
                NwEntryPanel *panel = (NwEntryPanel *)self;
                [panel setBusy:NO];
                [panel setHidden:YES];
                NSLog(@"[CRACK] panel hidden (fallback)");
            } @catch (NSException *e) {
                NSLog(@"[CRACK] fallback error: %@", e);
            }
        }
    }
}

// setRuntimeLicenseOK: → 强制 YES
static void hook_setRuntimeLicenseOK(id self, SEL _cmd, BOOL val) {
    @autoreleasepool {
        if (g_orig_setRuntimeLicenseOK) {
            ((void(*)(id, SEL, BOOL))g_orig_setRuntimeLicenseOK)(self, _cmd, YES);
        }
    }
}

// nw_revokeRuntimeLicense: → 阻止
static void hook_nw_revokeRuntimeLicense(id self, SEL _cmd, BOOL arg) {
    NSLog(@"[CRACK] Blocked nw_revokeRuntimeLicense:");
}

// clearSession → 阻止 + 重新持久化
static void hook_clearSession(id self, SEL _cmd) {
    NSLog(@"[CRACK] Blocked clearSession");
    persistBypassData();
}

// startLicenseWatchWithInterval: → 阻止
static void hook_startLicenseWatch(id self, SEL _cmd, double interval) {
    NSLog(@"[CRACK] Blocked startLicenseWatch");
}

// startHeartbeatWithInterval:onResult: → 阻止
static void hook_startHeartbeat(id self, SEL _cmd, double interval, id block) {
    NSLog(@"[CRACK] Blocked startHeartbeat");
}

// showForceExitAlertWithMessage: → 阻止（类方法）
static void hook_showForceExitAlert(id self, SEL _cmd, id msg) {
    NSLog(@"[CRACK] Blocked showForceExitAlertWithMessage:");
}

// nw_onSessEnd: → 阻止
static void hook_nw_onSessEnd(id self, SEL _cmd, id notif) {
    NSLog(@"[CRACK] Blocked nw_onSessEnd:");
}

// ====== 安装 hook ======
static void installBypassHooks() {
    if (g_bypassInstalled) return;
    g_bypassInstalled = YES;

    @autoreleasepool {
        NSLog(@"[CRACK] ===== Installing bypass hooks (IMP replace) =====");

        persistBypassData();

        // NwEntryPanel hooks
        Class panelClass = objc_getClass("NwEntryPanel");
        NSLog(@"[CRACK] NwEntryPanel class = %@", panelClass);
        if (panelClass) {
            g_orig_beginVerification = hookInstanceMethod(panelClass,
                @selector(beginVerification), (IMP)hook_beginVerification);
            NSLog(@"[CRACK] Hooked beginVerification (orig=%p)", g_orig_beginVerification);

            g_orig_onActivateTap = hookInstanceMethod(panelClass,
                @selector(onActivateTap), (IMP)hook_onActivateTap);
            NSLog(@"[CRACK] Hooked onActivateTap (orig=%p)", g_orig_onActivateTap);

            g_orig_nw_runEntryPipeline = hookInstanceMethod(panelClass,
                @selector(nw_runEntryPipeline), (IMP)hook_nw_runEntryPipeline);
            NSLog(@"[CRACK] Hooked nw_runEntryPipeline (orig=%p)", g_orig_nw_runEntryPipeline);

            // finishSuccess 必须最后 hook，因为上面的 hook 要用 g_orig_finishSuccess
            g_orig_finishSuccess = hookInstanceMethod(panelClass,
                @selector(finishSuccess), (IMP)hook_finishSuccess);
            NSLog(@"[CRACK] Hooked finishSuccess (orig=%p)", g_orig_finishSuccess);
        } else {
            NSLog(@"[CRACK] WARNING: NwEntryPanel not found!");
        }

        // NwSession hooks
        Class sessionClass = objc_getClass("NwSession");
        NSLog(@"[CRACK] NwSession class = %@", sessionClass);
        if (sessionClass) {
            g_orig_setRuntimeLicenseOK = hookInstanceMethod(sessionClass,
                @selector(setRuntimeLicenseOK:), (IMP)hook_setRuntimeLicenseOK);
            NSLog(@"[CRACK] Hooked setRuntimeLicenseOK: (orig=%p)", g_orig_setRuntimeLicenseOK);

            g_orig_nw_revokeRuntimeLicense = hookInstanceMethod(sessionClass,
                @selector(nw_revokeRuntimeLicense:), (IMP)hook_nw_revokeRuntimeLicense);
            NSLog(@"[CRACK] Hooked nw_revokeRuntimeLicense: (orig=%p)", g_orig_nw_revokeRuntimeLicense);

            g_orig_clearSession = hookInstanceMethod(sessionClass,
                @selector(clearSession), (IMP)hook_clearSession);
            NSLog(@"[CRACK] Hooked clearSession (orig=%p)", g_orig_clearSession);

            g_orig_startLicenseWatch = hookInstanceMethod(sessionClass,
                @selector(startLicenseWatchWithInterval:), (IMP)hook_startLicenseWatch);
            NSLog(@"[CRACK] Hooked startLicenseWatchWithInterval: (orig=%p)", g_orig_startLicenseWatch);

            g_orig_startHeartbeat = hookInstanceMethod(sessionClass,
                @selector(startHeartbeatWithInterval:onResult:), (IMP)hook_startHeartbeat);
            NSLog(@"[CRACK] Hooked startHeartbeatWithInterval:onResult: (orig=%p)", g_orig_startHeartbeat);

            g_orig_showForceExitAlert = hookClassMethod(sessionClass,
                @selector(showForceExitAlertWithMessage:), (IMP)hook_showForceExitAlert);
            NSLog(@"[CRACK] Hooked showForceExitAlertWithMessage: (orig=%p)", g_orig_showForceExitAlert);
        } else {
            NSLog(@"[CRACK] WARNING: NwSession not found!");
        }

        // MainRootViewController hooks
        Class rootClass = objc_getClass("MainRootViewController");
        NSLog(@"[CRACK] MainRootViewController class = %@", rootClass);
        if (rootClass) {
            g_orig_nw_onSessEnd = hookInstanceMethod(rootClass,
                @selector(nw_onSessEnd:), (IMP)hook_nw_onSessEnd);
            NSLog(@"[CRACK] Hooked nw_onSessEnd: (orig=%p)", g_orig_nw_onSessEnd);
        }

        NSLog(@"[CRACK] ===== All bypass hooks installed =====");
    }
}

// ====== 重试安装 hook ======
static void tryInstallBypassWithRetry() {
    @autoreleasepool {
        Class panelClass = objc_getClass("NwEntryPanel");
        Class sessionClass = objc_getClass("NwSession");

        if (panelClass && sessionClass) {
            installBypassHooks();
        } else {
            NSLog(@"[CRACK] Classes not ready (panel=%@ session=%@), retry in 0.5s...",
                  panelClass, sessionClass);
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                tryInstallBypassWithRetry();
            });
        }
    }
}

// ====== 弹窗逻辑 ======
static void showKamiAlert() {
    @autoreleasepool {
        NSLog(@"[CRACK] showKamiAlert");

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
                    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:KEY_KAMI_VERIFIED];
                    [[NSUserDefaults standardUserDefaults] synchronize];
                    NSLog(@"[CRACK] kami correct! persisted.");

                    if (!g_bypassInstalled) {
                        installBypassHooks();
                    }

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
            // 1. 立即安装绕过 hook（带重试）
            tryInstallBypassWithRetry();

            // 2. 检查卡密验证状态
            BOOL alreadyVerified = [[NSUserDefaults standardUserDefaults] boolForKey:KEY_KAMI_VERIFIED];

            if (alreadyVerified) {
                NSLog(@"[CRACK] already verified, no window needed");
                return;
            }

            // 3. 未验证：创建独立窗口盖住 app
            UIViewController *rootVC = getCrackRootVC();
            [rootVC loadViewIfNeeded];

            CrackBlockerView *blocker = [[CrackBlockerView alloc] initWithFrame:[UIScreen mainScreen].bounds];
            blocker.backgroundColor = [UIColor clearColor];
            blocker.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [rootVC setValue:blocker forKey:@"view"];
            NSLog(@"[CRACK] blocker view set as rootVC.view");

            // 4. 监听 app 激活，弹出卡密弹窗
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
