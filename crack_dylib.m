// crack_dylib.m
// 最简测试版：弹一个卡密输入弹窗（独立 UIWindow，不被覆盖）
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
#import <QuartzCore/QuartzCore.h>

// ====== 卡密验证视图 ======
@interface CrackVerifyView : UIView <UITextFieldDelegate>
@property (strong, nonatomic) UITextField *inputField;
@property (strong, nonatomic) UIButton *verifyButton;
@property (strong, nonatomic) UILabel *titleLabel;
@property (strong, nonatomic) UILabel *hintLabel;
@property (strong, nonatomic) UILabel *errorLabel;
@end

@implementation CrackVerifyView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.1 alpha:0.97];

    // 标题 "PUBG HUD"
    self.titleLabel = [[UILabel alloc] init];
    self.titleLabel.text = @"PUBG HUD";
    self.titleLabel.textColor = [UIColor colorWithRed:0.3 green:0.8 blue:0.4 alpha:1.0];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:28];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.titleLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.titleLabel];

    // 提示
    self.hintLabel = [[UILabel alloc] init];
    self.hintLabel.text = @"请输入卡密";
    self.hintLabel.textColor = [UIColor whiteColor];
    self.hintLabel.font = [UIFont systemFontOfSize:16];
    self.hintLabel.textAlignment = NSTextAlignmentCenter;
    self.hintLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.hintLabel];

    // 输入框
    self.inputField = [[UITextField alloc] init];
    self.inputField.backgroundColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.2 alpha:1.0];
    self.inputField.textColor = [UIColor whiteColor];
    self.inputField.layer.cornerRadius = 10;
    self.inputField.layer.masksToBounds = YES;
    self.inputField.borderStyle = UITextBorderStyleNone;
    self.inputField.placeholder = @"输入卡密";
    self.inputField.font = [UIFont systemFontOfSize:18];
    self.inputField.textAlignment = NSTextAlignmentCenter;
    self.inputField.secureTextEntry = YES;
    self.inputField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.inputField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.inputField.translatesAutoresizingMaskIntoConstraints = NO;
    self.inputField.delegate = self;
    [self addSubview:self.inputField];

    // 激活按钮
    self.verifyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.verifyButton setTitle:@"激 活" forState:UIControlStateNormal];
    self.verifyButton.titleLabel.font = [UIFont boldSystemFontOfSize:18];
    self.verifyButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.3 alpha:1.0];
    [self.verifyButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.verifyButton.layer.cornerRadius = 10;
    self.verifyButton.layer.masksToBounds = YES;
    self.verifyButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.verifyButton addTarget:self action:@selector(verifyKami) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.verifyButton];

    // 错误提示
    self.errorLabel = [[UILabel alloc] init];
    self.errorLabel.text = @"";
    self.errorLabel.textColor = [UIColor colorWithRed:0.9 green:0.3 blue:0.3 alpha:1.0];
    self.errorLabel.font = [UIFont systemFontOfSize:14];
    self.errorLabel.textAlignment = NSTextAlignmentCenter;
    self.errorLabel.numberOfLines = 2;
    self.errorLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:self.errorLabel];

    // 布局约束
    [NSLayoutConstraint activateConstraints:@[
        [self.titleLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.titleLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:120],

        [self.hintLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.hintLabel.topAnchor constraintEqualToAnchor:self.titleLabel.bottomAnchor constant:20],

        [self.inputField.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.inputField.topAnchor constraintEqualToAnchor:self.hintLabel.bottomAnchor constant:20],
        [self.inputField.widthAnchor constraintEqualToConstant:280],
        [self.inputField.heightAnchor constraintEqualToConstant:50],

        [self.verifyButton.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.verifyButton.topAnchor constraintEqualToAnchor:self.inputField.bottomAnchor constant:20],
        [self.verifyButton.widthAnchor constraintEqualToConstant:280],
        [self.verifyButton.heightAnchor constraintEqualToConstant:50],

        [self.errorLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [self.errorLabel.topAnchor constraintEqualToAnchor:self.verifyButton.bottomAnchor constant:15],
        [self.errorLabel.widthAnchor constraintEqualToConstant:300],
    ]];
}

- (void)verifyKami {
    NSString *input = self.inputField.text;
    NSString *correctKami = @"XianyuWeihuabinggan";

    if ([input isEqualToString:correctKami]) {
        // 卡密正确
        self.errorLabel.textColor = [UIColor colorWithRed:0.3 green:0.8 blue:0.4 alpha:1.0];
        self.errorLabel.text = @"卡密验证成功！";

        [UIView animateWithDuration:0.3 animations:^{
            self.alpha = 0;
        } completion:^(BOOL finished) {
            [self removeFromSuperview];
        }];
    } else {
        // 卡密错误
        self.errorLabel.text = @"请联系闲鱼威化饼干获取卡密";
        [self shakeAnimation];
    }
}

- (void)shakeAnimation {
    CAKeyframeAnimation *shake = [CAKeyframeAnimation animationWithKeyPath:@"transform.translation.x"];
    shake.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    shake.duration = 0.5;
    shake.values = @[@(-10), @(10), @(-10), @(10), @(-5), @(5), @0];
    [self.inputField.layer addAnimation:shake forKey:@"shake"];
}

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [self verifyKami];
    return YES;
}

@end

// ====== 空的 ViewController（给 UIWindow 用） ======
@interface CrackViewController : UIViewController
@end

@implementation CrackViewController
@end

// ====== 全局引用 ======
static UIWindow *g_crackWindow = nil;

// ====== 弹出卡密界面（使用独立 UIWindow） ======
static void showKamiView() {
    dispatch_async(dispatch_get_main_queue(), ^{
        @autoreleasepool {
            NSLog(@"[CRACK] showKamiView called");

            // 如果已经创建过，直接 bring to front
            if (g_crackWindow) {
                g_crackWindow.hidden = NO;
                [g_crackWindow makeKeyAndVisible];
                NSLog(@"[CRACK] reuse existing crack window");
                return;
            }

            CGRect screenBounds = [UIScreen mainScreen].bounds;

            // 创建独立的 UIWindow，windowLevel 设为 Alert 级别（高于普通窗口）
            g_crackWindow = [[UIWindow alloc] initWithFrame:screenBounds];
            g_crackWindow.windowLevel = UIWindowLevelAlert; // 比普通 app 窗口高
            g_crackWindow.backgroundColor = [UIColor clearColor];

            // 设置 rootViewController（iOS 13+ 需要 scene，但巨魔环境一般没 scene）
            CrackViewController *vc = [[CrackViewController alloc] init];
            g_crackWindow.rootViewController = vc;

            // 创建卡密验证视图
            CrackVerifyView *verifyView = [[CrackVerifyView alloc] initWithFrame:screenBounds];
            verifyView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
            [g_crackWindow addSubview:verifyView];

            // 显示窗口
            g_crackWindow.hidden = NO;
            [g_crackWindow makeKeyAndVisible];

            NSLog(@"[CRACK] crack window created and shown (level=Alert)");
        }
    });
}

// ====== dylib 加载入口 ======
__attribute__((constructor))
static void crack_init(int argc, const char **argv) {
    @autoreleasepool {
        NSLog(@"[CRACK] ===== crack.dylib loaded (UIWindow version) =====");

        // 延迟 2 秒后弹出卡密界面，确保 app UI 完全初始化
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            showKamiView();
        });
    }
}
