// crack_dylib.m
// 单纯卡密验证弹窗（系统 UIAlertController）
// - 首次进入需要输入卡密，验证通过后持久化（NSUserDefaults）
// - 卡密错误提示重新输入，不跳转任何链接
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

// ====== 弹出卡密输入弹窗 ======
static void showKamiAlert() {
    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            NSLog(@"[CRACK] showKamiAlert");

            // 检查是否已验证过（持久化）
            BOOL alreadyVerified = [[NSUserDefaults standardUserDefaults] boolForKey:KEY_KAMI_VERIFIED];
            if (alreadyVerified) {
                NSLog(@"[CRACK] already verified (persisted), skip");
                return;
            }

            UIViewController *rootVC = getCrackRootVC();
            if (rootVC.presentedViewController) {
                NSLog(@"[CRACK] alert already showing, skip");
                return;
            }

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
                    NSString *input = alert.textFields.firstObject.text;
                    NSLog(@"[CRACK] input: %@", input);

                    if ([input isEqualToString:KAMI_CORRECT]) {
                        // 卡密正确 - 持久化保存
                        [[NSUserDefaults standardUserDefaults] setBool:YES forKey:KEY_KAMI_VERIFIED];
                        [[NSUserDefaults standardUserDefaults] synchronize];
                        NSLog(@"[CRACK] kami correct! persisted.");
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
                                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                                               dispatch_get_main_queue(), ^{
                                    showKamiAlert();
                                });
                            }];

                        [errorAlert addAction:retryAction];
                        [rootVC presentViewController:errorAlert animated:YES completion:nil];
                    }
                }];

            // 取消按钮（点了也会重新弹）
            UIAlertAction *cancelAction = [UIAlertAction
                actionWithTitle:@"取消"
                          style:UIAlertActionStyleCancel
                        handler:^(UIAlertAction *action) {
                    NSLog(@"[CRACK] user cancelled, re-show in 1s");
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                                   dispatch_get_main_queue(), ^{
                        showKamiAlert();
                    });
                }];

            [alert addAction:verifyAction];
            [alert addAction:cancelAction];

            [rootVC presentViewController:alert animated:YES completion:nil];
            NSLog(@"[CRACK] alert presented");
        }
    });
}

// ====== dylib 加载入口 ======
__attribute__((constructor))
static void crack_init(int argc, const char **argv) {
    @autoreleasepool {
        NSLog(@"[CRACK] ===== crack.dylib loaded =====");

        // 延迟 2 秒后弹出卡密界面，确保 app UI 完全初始化
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            showKamiAlert();
        });
    }
}
