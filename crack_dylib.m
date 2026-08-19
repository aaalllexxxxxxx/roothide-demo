// crack_dylib.m
// PUBG HUD 破解 dylib - 免卡密 + 自定义卡密验证
//
// 编译方式 (需要在 macOS 交叉编译环境):
// clang -arch arm64 -dynamiclib -framework Foundation -framework UIKit \
//   -framework QuartzCore -o crack.dylib crack_dylib.m
//
// 或者用 theos:
// make package
//
// 功能:
// 1. app 启动时自动注入 offsets 和 feature config
// 2. 跳过原始验证管道，直接 finishSuccess
// 3. 显示自定义卡密验证界面，输入指定卡密才能进入
// 4. 阻止后续的吊销/心跳/定时器

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

// ====== 前向声明 ======
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
- (void)removeFromSuperview;
@property (retain, nonatomic) UITextField *kamiField;
@end

@interface MainRootViewController : UIViewController
- (void)nw_onSessEnd:(id)notif;
@end

// ====== 自定义卡密验证界面 ======
@interface CrackVerifyView : UIView <UITextFieldDelegate>
@property (strong, nonatomic) UITextField *inputField;
@property (strong, nonatomic) UIButton *verifyButton;
@property (strong, nonatomic) UILabel *titleLabel;
@property (strong, nonatomic) UILabel *hintLabel;
@property (strong, nonatomic) UILabel *errorLabel;
@property (strong, nonatomic) void (^onSuccess)(void);
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
    self.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.1 alpha:0.95];

    // 标题
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

    // 验证按钮
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

    // 指定卡密
    NSString *correctKami = @"XianyuWeihuabinggan";

    if ([input isEqualToString:correctKami]) {
        // 卡密正确
        self.errorLabel.textColor = [UIColor colorWithRed:0.3 green:0.8 blue:0.4 alpha:1.0];
        self.errorLabel.text = @"卡密验证成功，正在进入...";

        [UIView animateWithDuration:0.3 animations:^{
            self.alpha = 0;
        } completion:^(BOOL finished) {
            [self removeFromSuperview];
            if (self.onSuccess) {
                self.onSuccess();
            }
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

// ====== Method Swizzle 工具 ======
#import <objc/runtime.h>

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

// ====== 破解逻辑 ======
static NwEntryPanel *g_panel = nil;
static BOOL g_finishSuccessDone = NO;
static BOOL g_injected = NO;

// 注入 offsets 和 feature config
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
        [NwGameOffsets applyDictionary:offsetsFull];
        NSLog(@"[CRACK] NwGameOffsets applyDictionary: injected!");

        BOOL ready = [NwGameOffsets isReady];
        NSLog(@"[CRACK] NwGameOffsets.isReady = %d", ready);

        // 构造 feature config 字典
        NSMutableDictionary *featDict = [NSMutableDictionary dictionary];
        [featDict setObject:@(1) forKey:@"cfg_ver"];
        [featDict setObject:@(1) forKey:@"esp_enabled"];
        [featDict setObject:@(2147483647) forKey:@"exp"];

        // 调用 NxFeat applyDictionary:
        [NxFeat applyDictionary:featDict];
        NSLog(@"[CRACK] NxFeat applyDictionary: injected!");

        BOOL featReady = [NxFeat isReady];
        NSLog(@"[CRACK] NxFeat.isReady = %d", featReady);
    }
}

// ====== Swizzled 方法实现 ======
// 必须放在一个 Category 里，否则编译器报 "missing context for method declaration"

@interface NwEntryPanel (Crack)
- (void)crack_beginVerification;
- (void)crack_onActivateTap;
- (void)crack_nw_runEntryPipeline;
- (void)crack_finishSuccess;
- (void)crack_setRuntimeLicenseOK:(BOOL)val;
- (void)crack_nw_revokeRuntimeLicense:(BOOL)arg;
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

@implementation NwEntryPanel (Crack)

// beginVerification → 替换为卡密验证界面
- (void)crack_beginVerification {
    @autoreleasepool {
        NSLog(@"[CRACK] beginVerification intercepted - showing kami verify");

        NwEntryPanel *panel = (NwEntryPanel *)self;
        g_panel = panel;

        // 创建卡密验证界面
        CrackVerifyView *verifyView = [[CrackVerifyView alloc] initWithFrame:panel.bounds];
        verifyView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        verifyView.onSuccess = ^{
            // 卡密验证成功后，注入数据并 finishSuccess
            injectOffsetsAndFeature();
            [g_panel setBusy:NO];
            [g_panel finishSuccess];
        };

        // 添加到面板上
        [panel addSubview:verifyView];
    }
}

// onActivateTap → 替换（不做事，因为卡密界面已显示）
- (void)crack_onActivateTap {
    NSLog(@"[CRACK] onActivateTap intercepted (ignored, kami view shown)");
}

// nw_runEntryPipeline → 替换为卡密验证界面
- (void)crack_nw_runEntryPipeline {
    @autoreleasepool {
        NSLog(@"[CRACK] nw_runEntryPipeline intercepted - showing kami verify");
        [(id)self crack_beginVerification];
    }
}

// finishSuccess → 保护原始实现
- (void)crack_finishSuccess {
    @autoreleasepool {
        NSLog(@"[CRACK] finishSuccess intercepted");
        if (g_finishSuccessDone) {
            NSLog(@"[CRACK] finishSuccess already done, skip");
            return;
        }
        g_finishSuccessDone = YES;

        // 确保数据已注入
        injectOffsetsAndFeature();

        // 调用原始实现
        [(id)self crack_finishSuccess];
        NSLog(@"[CRACK] finishSuccess original done");
    }
}

// setRuntimeLicenseOK: → 强制 YES
- (void)crack_setRuntimeLicenseOK:(BOOL)val {
    @autoreleasepool {
        [(id)self crack_setRuntimeLicenseOK:YES];
    }
}

// nw_revokeRuntimeLicense: → 阻止
- (void)crack_nw_revokeRuntimeLicense:(BOOL)arg {
    NSLog(@"[CRACK] Blocked nw_revokeRuntimeLicense:");
}

@end

@implementation NwSession (Crack)

// setRuntimeLicenseOK: → 强制 YES
- (void)crack_setRuntimeLicenseOK:(BOOL)val {
    @autoreleasepool {
        [(id)self crack_setRuntimeLicenseOK:YES];
    }
}

// nw_revokeRuntimeLicense: → 阻止
- (void)crack_nw_revokeRuntimeLicense:(BOOL)arg {
    NSLog(@"[CRACK] Blocked nw_revokeRuntimeLicense:");
}

// nw_sessEnd:message: → 阻止
- (void)crack_nw_sessEnd:(NSInteger)status message:(NSString *)msg {
    NSLog(@"[CRACK] Blocked nw_sessEnd:status:");
}

// clearSession → 阻止
- (void)crack_clearSession {
    NSLog(@"[CRACK] Blocked clearSession");
}

// startLicenseWatchWithInterval: → 阻止
- (void)crack_startLicenseWatchWithInterval:(double)interval {
    NSLog(@"[CRACK] Blocked startLicenseWatch");
}

// startHeartbeatWithInterval:onResult: → 阻止
- (void)crack_startHeartbeatWithInterval:(double)interval onResult:(id)block {
    NSLog(@"[CRACK] Blocked startHeartbeat");
}

// showForceExitAlertWithMessage: → 阻止 (类方法)
+ (void)crack_showForceExitAlertWithMessage:(NSString *)msg {
    NSLog(@"[CRACK] Blocked showForceExitAlertWithMessage:");
}

@end

@implementation MainRootViewController (Crack)

// nw_onSessEnd: → 阻止
- (void)crack_nw_onSessEnd:(id)notif {
    NSLog(@"[CRACK] Blocked nw_onSessEnd:");
}

@end

// ====== dylib 加载入口 ======
__attribute__((constructor))
static void crack_init(int argc, const char **argv) {
    @autoreleasepool {
        NSLog(@"[CRACK] ===== crack.dylib loaded =====");

        // Method swizzle
        Class panelClass = objc_getClass("NwEntryPanel");

        if (panelClass) {
            // 实例方法
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

            swizzleMethod(panelClass,
                NSSelectorFromString(@"setRuntimeLicenseOK:"),
                NSSelectorFromString(@"crack_setRuntimeLicenseOK:"));
            NSLog(@"[CRACK] Swizzled setRuntimeLicenseOK:");

            swizzleMethod(panelClass,
                NSSelectorFromString(@"nw_revokeRuntimeLicense:"),
                NSSelectorFromString(@"crack_nw_revokeRuntimeLicense:"));
            NSLog(@"[CRACK] Swizzled nw_revokeRuntimeLicense:");

            // 如果 nw_sessEnd:message: 是 NwEntryPanel 的方法
            // 实际上它在 NwSession 上，需要单独处理
        }

        // NwSession 的方法
        Class sessionClass = objc_getClass("NwSession");
        if (sessionClass) {
            swizzleMethod(sessionClass,
                NSSelectorFromString(@"setRuntimeLicenseOK:"),
                NSSelectorFromString(@"crack_setRuntimeLicenseOK:"));
            swizzleMethod(sessionClass,
                NSSelectorFromString(@"nw_revokeRuntimeLicense:"),
                NSSelectorFromString(@"crack_nw_revokeRuntimeLicense:"));

            // 检查 nw_sessEnd:message: 在哪个类上
            Method sessEndMethod = class_getInstanceMethod(sessionClass,
                NSSelectorFromString(@"nw_sessEnd:status:message:"));
            if (sessEndMethod) {
                swizzleMethod(sessionClass,
                    NSSelectorFromString(@"nw_sessEnd:status:message:"),
                    NSSelectorFromString(@"crack_nw_sessEnd:message:"));
                NSLog(@"[CRACK] Swizzled nw_sessEnd:status:message:");
            }

            sessEndMethod = class_getInstanceMethod(sessionClass,
                NSSelectorFromString(@"nw_sessEnd:status:"));
            if (sessEndMethod) {
                swizzleMethod(sessionClass,
                    NSSelectorFromString(@"nw_sessEnd:status:"),
                    NSSelectorFromString(@"crack_nw_sessEnd:message:"));
                NSLog(@"[CRACK] Swizzled nw_sessEnd:status:");
            }

            swizzleMethod(sessionClass,
                NSSelectorFromString(@"clearSession"),
                NSSelectorFromString(@"crack_clearSession"));
            NSLog(@"[CRACK] Swizzled clearSession");

            swizzleMethod(sessionClass,
                NSSelectorFromString(@"startLicenseWatchWithInterval:"),
                NSSelectorFromString(@"crack_startLicenseWatchWithInterval:"));
            NSLog(@"[CRACK] Swizzled startLicenseWatchWithInterval:");

            swizzleMethod(sessionClass,
                NSSelectorFromString(@"startHeartbeatWithInterval:onResult:"),
                NSSelectorFromString(@"crack_startHeartbeatWithInterval:onResult:"));
            NSLog(@"[CRACK] Swizzled startHeartbeatWithInterval:onResult:");

            // 类方法
            swizzleClassMethod(sessionClass,
                NSSelectorFromString(@"showForceExitAlertWithMessage:"),
                NSSelectorFromString(@"crack_showForceExitAlertWithMessage:"));
            NSLog(@"[CRACK] Swizzled showForceExitAlertWithMessage:");
        }

        // MainRootViewController
        Class rootClass = objc_getClass("MainRootViewController");
        if (rootClass) {
            swizzleMethod(rootClass,
                NSSelectorFromString(@"nw_onSessEnd:"),
                NSSelectorFromString(@"crack_nw_onSessEnd:"));
            NSLog(@"[CRACK] Swizzled nw_onSessEnd:");
        }

        NSLog(@"[CRACK] ===== All swizzles done =====");
        NSLog(@"[CRACK] Waiting for app to show kami verify view...");
    }
}
