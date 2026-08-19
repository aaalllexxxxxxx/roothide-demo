// crack_dylib.m
// 单纯卡密验证弹窗（系统 UIAlertController）
// - 首次进入弹卡密输入，验证通过后持久化（NSUserDefaults），以后不再弹
// - 用独立 UIWindow 盖住 app，阻止触摸
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

// ====== 遮罩视图（吞掉触摸事件，透明不可见） ======
@interface CrackBlockerView : UIView
@end

@implementation CrackBlockerView
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    return nil;  // 吞掉所有触摸
}
@end

// ====== 空的 ViewController（给 UIWindow 用） ======
@interface CrackViewController : UIViewController
@end

@implementation CrackViewController

// view 加载后加遮罩
- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor clearColor];
}

// 支持旋转
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

// ====== 弹出卡密输入弹窗 ======
static void showKamiAlert() {
    @autoreleasepool {
        NSLog(@"[CRACK] showKamiAlert");

        // 检查是否已验证过（持久化）
        BOOL alreadyVerified = [[NSUserDefaults standardUserDefaults] boolForKey:KEY_KAMI_VERIFIED];
        if (alreadyVerified) {
            NSLog(@"[CRACK] already verified (persisted), skip");
            // 已验证，隐藏窗口，恢复 app
            g_crackWindow.hidden = YES;
            return;
        }

        // 防止重复弹出
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
                    // 隐藏窗口，恢复 app 操作
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

        // dispatch_async 到主队列，等主线程 runloop 启动
        dispatch_async(dispatch_get_main_queue(), ^{
            // 检查是否已验证
            BOOL alreadyVerified = [[NSUserDefaults standardUserDefaults] boolForKey:KEY_KAMI_VERIFIED];

            if (alreadyVerified) {
                // 已验证，什么都不做
                NSLog(@"[CRACK] already verified, no window needed");
                return;
            }

            // 未验证：创建独立窗口盖住 app
            // g_crackWindow 的 rootViewController.view 是透明的
            // 但窗口 makeKeyAndVisible 后会成为 keyWindow
            // app 原来的窗口在下面，触摸事件被我们的窗口拦截
            // 因为窗口本身会接收触摸（rootViewController.view 存在）
            // 但我们用 CrackBlockerView 作为 rootViewController.view 吞掉触摸

            // 替换 rootVC 的 view 为吞触摸的 blocker
            UIViewController *rootVC = getCrackRootVC();

            // 确保 rootVC.view 已加载
            [rootVC loadViewIfNeeded];

            // 把 rootVC.view 替换成吞触摸的 blocker
            CrackBlockerView *blocker = [[CrackBlockerView alloc] initWithFrame:[UIScreen mainScreen].bounds];
            blocker.backgroundColor = [UIColor clearColor];
            blocker.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            // 用 KVC 替换 view（避免触发 setView: 的额外逻辑）
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
