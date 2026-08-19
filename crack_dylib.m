// crack_dylib.m
// 单纯卡密验证弹窗（系统 UIAlertController）
// - 首次进入弹卡密输入，验证通过后持久化（NSUserDefaults），以后不再弹
// - 弹窗前盖全屏遮罩，阻止用户操作 app
// - 输入错误 → 提示重新输入
// - 点取消 → 闪退退出
//
// 编译:
// clang -arch arm64 -dynamiclib -framework Foundation -framework UIKit \
//   -framework QuartzCore -undefined dynamic_lookup -flat_namespace \
//   -isysroot $(xcrun --sdk iphoneos --show-sdk-path) \
//   -target arm64-apple-ios14.0 \
//   -o crack.dylib crack_dylib.m

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// ====== 常量 ======
static NSString *const KAMI_CORRECT = @"XianyuWeihuabinggan";
static NSString *const KEY_KAMI_VERIFIED = @"crack_kami_verified";

// ====== 全局引用 ======
static UIWindow *g_crackWindow = nil;
static BOOL g_alertShowing = NO;

// ====== 遮罩视图（吞掉触摸事件） ======
@interface CrackBlockerView : UIView
@end

@implementation CrackBlockerView
// hitTest 返回 nil → 吞掉所有触摸，不传递给下面的 app 内容
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    return nil;
}
@end

// ====== 空的 ViewController（给 UIWindow 用） ======
@interface CrackViewController : UIViewController
@end

@implementation CrackViewController
@end

// ====== 获取或创建独立窗口 ======
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

// ====== 盖住 app 所有窗口的遮罩 ======
static void blockAllWindows() {
    @autoreleasepool {
        // 遍历所有窗口（除了我们自己的 g_crackWindow）
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (w == g_crackWindow) continue;

            // 检查是否已经有遮罩
            BOOL hasBlocker = NO;
            for (UIView *sub in w.subviews) {
                if ([sub isKindOfClass:[CrackBlockerView class]]) {
                    hasBlocker = YES;
                    break;
                }
            }
            if (hasBlocker) continue;

            CGRect bounds = w.bounds;
            CrackBlockerView *blocker = [[CrackBlockerView alloc] initWithFrame:bounds];
            blocker.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.5];
            blocker.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [w addSubview:blocker];
            NSLog(@"[CRACK] blocker added to window: %@", w);
        }
    }
}

// ====== 移除遮罩 ======
static void unblockAllWindows() {
    @autoreleasepool {
        for (UIWindow *w in [UIApplication sharedApplication].windows) {
            if (w == g_crackWindow) continue;
            for (UIView *sub in w.subviews) {
                if ([sub isKindOfClass:[CrackBlockerView class]]) {
                    [sub removeFromSuperview];
                    NSLog(@"[CRACK] blocker removed from window: %@", w);
                }
            }
        }
    }
}

// ====== 弹出卡密输入弹窗 ======
static void showKamiAlert() {
    @autoreleasepool {
        NSLog(@"[CRACK] showKamiAlert");

        // 检查是否已验证过（持久化）
        BOOL alreadyVerified = [[NSUserDefaults standardUserDefaults] boolForKey:KEY_KAMI_VERIFIED];
        if (alreadyVerified) {
            NSLog(@"[CRACK] already verified (persisted), skip");
            return;
        }

        // 防止重复弹出
        if (g_alertShowing) {
            NSLog(@"[CRACK] alert already showing, skip");
            return;
        }

        // 先盖遮罩，阻止用户操作 app
        blockAllWindows();

        UIViewController *rootVC = getCrackRootVC();
        if (rootVC.presentedViewController) {
            NSLog(@"[CRACK] something already presented, skip");
            return;
        }

        g_alertShowing = YES;

        // 创建卡密输入弹窗
        UIAlertController *alert = [UIAlertController
            alertControllerWithTitle:@"PUBG HUD"
                             message:@"请输入卡密"
                      preferredStyle:UIAlertControllerStyleAlert];

        // 添加输入框
        [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
            textField.placeholder = @"输入卡密";
            textField.secureTextEntry = YES;
            textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
            textField.autocorrectionType = UITextAutocorrectionTypeNo;
            textField.font = [UIFont systemFontOfSize:16];
        }];

        // 激活按钮
        UIAlertAction *verifyAction = [UIAlertAction
            actionWithTitle:@"激 活"
                      style:UIAlertActionStyleDefault
                    handler:^(UIAlertAction *action) {
                g_alertShowing = NO;
                NSString *input = alert.textFields.firstObject.text;
                NSLog(@"[CRACK] input: %@", input);

                if ([input isEqualToString:KAMI_CORRECT]) {
                    // 卡密正确 - 持久化保存
                    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:KEY_KAMI_VERIFIED];
                    [[NSUserDefaults standardUserDefaults] synchronize];
                    NSLog(@"[CRACK] kami correct! persisted.");
                    // 移除遮罩，恢复 app 操作
                    unblockAllWindows();
                    g_crackWindow.hidden = YES;

                } else {
                    // 卡密错误
                    NSLog(@"[CRACK] kami wrong, retry");
                    UIAlertController *errorAlert = [UIAlertController
                        alertControllerWithTitle:@"卡密错误"
                                         message:@"卡密不正确，请重新输入"
                                  preferredStyle:UIAlertControllerStyleAlert];

                    UIAlertAction *retryAction = [UIAlertAction
                        actionWithTitle:@"重新输入"
                                  style:UIAlertActionStyleDefault
                                handler:^(UIAlertAction *a) {
                            // 立即重新弹窗，不延迟
                            showKamiAlert();
                        }];

                    [errorAlert addAction:retryAction];
                    [rootVC presentViewController:errorAlert animated:NO completion:nil];
                }
            }];

        // 取消按钮 → 立即闪退
        UIAlertAction *cancelAction = [UIAlertAction
            actionWithTitle:@"取消"
                      style:UIAlertActionStyleCancel
                    handler:^(UIAlertAction *action) {
                NSLog(@"[CRACK] user cancelled, crash exit");
                // 立即闪退，不等动画
                abort();
            }];

        [alert addAction:verifyAction];
        [alert addAction:cancelAction];

        // animated:NO 去掉弹出动画延迟
        [rootVC presentViewController:alert animated:NO completion:nil];
        NSLog(@"[CRACK] alert presented");
    }
}

// ====== dylib 加载入口 ======
__attribute__((constructor))
static void crack_init(int argc, const char **argv) {
    @autoreleasepool {
        NSLog(@"[CRACK] ===== crack.dylib loaded =====");

        // 注册 NSNotificationCenter 监听 app 激活，立即弹出
        [[NSNotificationCenter defaultCenter]
            addObserverForName:UIApplicationDidBecomeActiveNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
            NSLog(@"[CRACK] app became active, showing kami alert");
            // 延迟 0.1 秒，确保 app 的窗口都已创建
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)),
                           dispatch_get_main_queue(), ^{
                showKamiAlert();
            });
        }];
    }
}
