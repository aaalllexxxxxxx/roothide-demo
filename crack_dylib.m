// crack_dylib.m
// 最简测试版：用系统自带 UIAlertController 弹窗输入卡密
// 不做任何 swizzle/hook，只验证 dylib 被加载
//
// 编译:
// clang -arch arm64 -dynamiclib -framework Foundation -framework UIKit \
//   -framework QuartzCore -undefined dynamic_lookup -flat_namespace \
//   -isysroot $(xcrun --sdk iphoneos --show-sdk-path) \
//   -target arm64-apple-ios14.0 \
//   -o crack.dylib crack_dylib.m

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// ====== 全局引用 ======
static UIWindow *g_crackWindow = nil;
static BOOL g_verified = NO;

// ====== 空的 ViewController（给 UIWindow 用） ======
@interface CrackViewController : UIViewController
@end

@implementation CrackViewController
@end

// ====== 弹出系统自带卡密输入弹窗 ======
static void showKamiAlert() {
    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            NSLog(@"[CRACK] showKamiAlert called, g_verified=%d", g_verified);

            if (g_verified) {
                NSLog(@"[CRACK] already verified, skip");
                return;
            }

            // 获取或创建独立窗口
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

            // 如果已有 controller 在显示，不重复弹
            UIViewController *rootVC = g_crackWindow.rootViewController;
            if (rootVC.presentedViewController) {
                NSLog(@"[CRACK] alert already showing, skip");
                return;
            }

            // 创建系统自带弹窗
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
                    NSString *correctKami = @"XianyuWeihuabinggan";

                    NSLog(@"[CRACK] input: %@", input);

                    if ([input isEqualToString:correctKami]) {
                        // 卡密正确
                        g_verified = YES;
                        NSLog(@"[CRACK] kami correct!");

                        // 弹出成功提示，然后消失
                        UIAlertController *successAlert = [UIAlertController
                            alertControllerWithTitle:@"验证成功"
                                             message:@"卡密验证成功！"
                                      preferredStyle:UIAlertControllerStyleAlert];

                        UIAlertAction *okAction = [UIAlertAction
                            actionWithTitle:@"确定"
                                      style:UIAlertActionStyleDefault
                                    handler:^(UIAlertAction *a) {
                                // 隐藏窗口
                                g_crackWindow.hidden = YES;
                                NSLog(@"[CRACK] verified, window hidden");
                            }];

                        [successAlert addAction:okAction];
                        [rootVC presentViewController:successAlert animated:YES completion:nil];

                    } else {
                        // 卡密错误，重新弹窗
                        NSLog(@"[CRACK] kami wrong, retry");
                        UIAlertController *errorAlert = [UIAlertController
                            alertControllerWithTitle:@"卡密错误"
                                             message:@"请联系闲鱼威化饼干获取卡密"
                                      preferredStyle:UIAlertControllerStyleAlert];

                        UIAlertAction *retryAction = [UIAlertAction
                            actionWithTitle:@"重新输入"
                                      style:UIAlertActionStyleDefault
                                    handler:^(UIAlertAction *a) {
                                // 延迟一点再重新弹
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
                    // 1 秒后重新弹
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
        NSLog(@"[CRACK] ===== crack.dylib loaded (UIAlertController version) =====");

        // 延迟 2 秒后弹出卡密界面，确保 app UI 完全初始化
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            showKamiAlert();
        });
    }
}
