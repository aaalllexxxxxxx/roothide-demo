// crack_dylib.m
// 用系统自带 UIAlertController 弹窗输入卡密
// - 首次进入需要输入卡密，验证通过后持久化（NSUserDefaults）
// - 验证成功后弹"获取更多破解软件"窗口，可选"知道了"或"以后不再提示"
// - 卡密错误窗口有"获取卡密"按钮跳转淘宝链接
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
static NSString *const KEY_SKIP_PROMO = @"crack_skip_promo";
static NSString *const TB_URL = @"https://m.tb.cn/h.8j1x0aY?tk=pUyOTc0PWG7";

// ====== 全局引用 ======
static UIWindow *g_crackWindow = nil;

// ====== 空的 ViewController（给 UIWindow 用） ======
@interface CrackViewController : UIViewController
@end

@implementation CrackViewController
@end

// ====== 跳转 URL ======
static void openURL(NSString *urlString) {
    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            NSURL *url = [NSURL URLWithString:urlString];
            if (url) {
                [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:^(BOOL success) {
                    NSLog(@"[CRACK] openURL %@ success=%d", urlString, success);
                }];
            }
        }
    });
}

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

// ====== 弹出"获取更多破解软件"窗口 ======
static void showPromoAlert() {
    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            NSLog(@"[CRACK] showPromoAlert");

            UIViewController *rootVC = getCrackRootVC();
            if (rootVC.presentedViewController) {
                NSLog(@"[CRACK] promo: alert already showing, skip");
                return;
            }

            UIAlertController *alert = [UIAlertController
                alertControllerWithTitle:@"获取更多破解软件"
                                 message:@"更多精彩破解软件等你来发现"
                          preferredStyle:UIAlertControllerStyleAlert];

            // 跳转按钮
            UIAlertAction *goAction = [UIAlertAction
                actionWithTitle:@"获取卡密"
                          style:UIAlertActionStyleDefault
                        handler:^(UIAlertAction *action) {
                    NSLog(@"[CRACK] promo: open taobao");
                    openURL(TB_URL);
                    // 跳转后隐藏窗口
                    g_crackWindow.hidden = YES;
                }];

            // 知道了
            UIAlertAction *okAction = [UIAlertAction
                actionWithTitle:@"知道了"
                          style:UIAlertActionStyleDefault
                        handler:^(UIAlertAction *action) {
                    NSLog(@"[CRACK] promo: ok");
                    g_crackWindow.hidden = YES;
                }];

            // 以后不再提示
            UIAlertAction *skipAction = [UIAlertAction
                actionWithTitle:@"以后不再提示"
                          style:UIAlertActionStyleCancel
                        handler:^(UIAlertAction *action) {
                    NSLog(@"[CRACK] promo: skip forever");
                    [[NSUserDefaults standardUserDefaults] setBool:YES forKey:KEY_SKIP_PROMO];
                    [[NSUserDefaults standardUserDefaults] synchronize];
                    g_crackWindow.hidden = YES;
                }];

            [alert addAction:goAction];
            [alert addAction:okAction];
            [alert addAction:skipAction];

            [rootVC presentViewController:alert animated:YES completion:nil];
        }
    });
}

// ====== 弹出卡密输入弹窗 ======
static void showKamiAlert() {
    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            NSLog(@"[CRACK] showKamiAlert");

            // 检查是否已验证过（持久化）
            BOOL alreadyVerified = [[NSUserDefaults standardUserDefaults] boolForKey:KEY_KAMI_VERIFIED];
            if (alreadyVerified) {
                NSLog(@"[CRACK] already verified (persisted), skip kami input");

                // 检查是否需要弹推广窗口
                BOOL skipPromo = [[NSUserDefaults standardUserDefaults] boolForKey:KEY_SKIP_PROMO];
                if (!skipPromo) {
                    NSLog(@"[CRACK] showing promo alert");
                    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                                   dispatch_get_main_queue(), ^{
                        showPromoAlert();
                    });
                }
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

                        // 弹出推广窗口
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                                       dispatch_get_main_queue(), ^{
                            showPromoAlert();
                        });

                    } else {
                        // 卡密错误
                        NSLog(@"[CRACK] kami wrong, retry");
                        UIAlertController *errorAlert = [UIAlertController
                            alertControllerWithTitle:@"卡密错误"
                                             message:@"请联系闲鱼威化饼干获取卡密"
                                      preferredStyle:UIAlertControllerStyleAlert];

                        // 重新输入
                        UIAlertAction *retryAction = [UIAlertAction
                            actionWithTitle:@"重新输入"
                                      style:UIAlertActionStyleDefault
                                    handler:^(UIAlertAction *a) {
                                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                                               dispatch_get_main_queue(), ^{
                                    showKamiAlert();
                                });
                            }];

                        // 获取卡密 - 跳转淘宝
                        UIAlertAction *getKamiAction = [UIAlertAction
                            actionWithTitle:@"获取卡密"
                                      style:UIAlertActionStyleDefault
                                    handler:^(UIAlertAction *a) {
                                NSLog(@"[CRACK] open taobao for kami");
                                openURL(TB_URL);
                                // 跳转后重新弹卡密输入
                                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                                               dispatch_get_main_queue(), ^{
                                    showKamiAlert();
                                });
                            }];

                        [errorAlert addAction:retryAction];
                        [errorAlert addAction:getKamiAction];

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
