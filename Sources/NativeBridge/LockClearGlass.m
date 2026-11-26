#import "NativeBridge.h"
#import <AppKit/NSColor.h>
#import <QuartzCore/QuartzCore.h>
#import <math.h>
#import <objc/message.h>

// Alcove 1.7.9's Clear material uses two backdrop filters fed by the same
// rounded signed-distance field. The optical baseline and source locations
// are recorded in docs/reports/lock-clear-glass-20261123.md.
static CALayer *CreateLayer(Class type) {
    if (![type isSubclassOfClass:CALayer.class]) return nil;
    CALayer *layer = [[type alloc] init];
    layer.anchorPoint = CGPointZero;
    return layer;
}

static NSObject *CreateGlassFilter(BOOL foreground) {
    Class type = NSClassFromString(@"CAFilter");
    SEL factory = NSSelectorFromString(@"filterWithType:");
    if (![type respondsToSelector:factory]) return nil;
    NSString *name = foreground ? @"glassForeground" : @"glassBackground";
    NSObject *filter = ((id (*)(id, SEL, id))objc_msgSend)(type, factory, name);
    if (!filter) return nil;
    NSDictionary<NSString *, id> *inputs;
    if (foreground) {
        inputs = @{
            @"inputAberrationAmount": @1.8, @"inputAberrationAngle": @0.2007,
            @"inputAberrationHeight": @0, @"inputAberrationOffset": @34,
            @"inputEdgeStart": @(-34.8), @"inputEdgeEnd": @0,
            @"inputEdgeOpacityStart": @1, @"inputEdgeOpacityEnd": @0,
            @"inputRefractionAmount": @0, @"inputRefractionHeight": @0,
            @"inputRefractionOffset": @0
        };
    } else {
        inputs = @{
            @"inputInnerRefractionAmount": @(-52.2), @"inputInnerRefractionHeight": @16.53,
            @"inputOuterRefractionAmount": @0, @"inputOuterRefractionHeight": @0,
            @"inputRefractionDistance0": @(-1), @"inputRefractionDistance1": @(-0.5),
            @"inputRefractionOpacity": @1, @"inputBlurRadius": @0,
            @"inputFaceOpacity": @1, @"inputFaceColorMatrixBlack": @0,
            @"inputFaceColorMatrixWhite": @1, @"inputFaceColorMatrixSaturation": @1,
            @"inputBleedAmount": @0, @"inputBleedHeight": @0, @"inputBleedBlurRadius": @0,
            @"inputBleedOpacity": @0, @"inputBleedDistance0": @0, @"inputBleedDistance1": @0,
            @"inputBleedColorMatrixBlack": @0, @"inputBleedColorMatrixWhite": @0,
            @"inputBleedColorMatrixSaturation": @0, @"inputShadowAmount": @43.5,
            @"inputShadowHeight": @0, @"inputShadowDistanceOffset": @0,
            @"inputShadowBlurRadius": @0, @"inputShadowRadius": @8,
            @"inputShadowColorMatrixBlack": @0, @"inputShadowColorMatrixWhite": @1,
            @"inputShadowColorMatrixSaturation": @1, @"inputShadowOpacity": @0.1,
            @"inputShadowVibrancyContribution": @0, @"inputMaxHeadroom": @9999,
            @"inputSDRGradientDistance0": @0, @"inputSDRGradientDistance1": @0,
            @"inputSDRShadowOpacity": @0, @"inputClamp": @1,
            @"inputBleedDarkenBlend": @NO, @"inputSDRHoldingToneEnabled": @NO,
            @"inputClampPreserveHue": @NO,
            @"inputFaceColorMatrixFillColor": (__bridge id)[NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:0].CGColor,
            @"inputShadowOffset": [NSValue valueWithSize:NSMakeSize(0, -7)]
        };
    }
    // CAFilter accepts dynamic keys. Ensure this OS advertises the inputs
    // before assigning them, so a partial recipe can fall back as a unit.
    NSArray *keys = [filter valueForKey:@"inputKeys"];
    if (![keys isKindOfClass:NSArray.class] || ![keys containsObject:@"inputSourceSublayerName"]
        || ![[NSSet setWithArray:inputs.allKeys] isSubsetOfSet:[NSSet setWithArray:keys]]) {
        return nil;
    }
    [filter setValue:name forKey:@"name"];
    [filter setValue:@"@0" forKey:@"inputSourceSublayerName"];
    [filter setValuesForKeysWithDictionary:inputs];
    return filter;
}

@interface ARLockGlassPass : NSObject
@property(nonatomic, strong) CALayer *backdrop;
@property(nonatomic, strong) CALayer *distanceField;
@property(nonatomic, strong) CALayer *shape;
@end
@implementation ARLockGlassPass
@end

static ARLockGlassPass *CreateGlassPass(BOOL foreground) {
    CALayer *backdrop = CreateLayer(NSClassFromString(@"CABackdropLayer"));
    CALayer *distanceField = CreateLayer(NSClassFromString(@"CASDFLayer"));
    CALayer *shape = CreateLayer(NSClassFromString(@"CASDFElementLayer"));
    Class effectType = NSClassFromString(@"CASDFOutputEffect");
    if (![effectType isSubclassOfClass:NSObject.class] || !backdrop || !distanceField || !shape) return nil;
    NSObject *output = [[effectType alloc] init];
    NSObject *filter = CreateGlassFilter(foreground);
    if (!output || !filter) return nil;

    backdrop.name = foreground ? @"@1" : @"@0";
    [backdrop setValuesForKeysWithDictionary:@{
        @"scale": @1, @"tracksLuma": @NO, @"allowsFilteredLuma": @YES,
        @"lumaUpdateRate": @0.25, @"allowsInPlaceFiltering": @YES,
        @"disablesOccludedBackdropBlurs": @YES, @"ignoresOffscreenGroups": @YES,
        @"windowServerAware": @YES
    }];
    if (foreground) [backdrop setValue:@40 forKey:@"marginWidth"];
    [output setValuesForKeysWithDictionary:@{@"minimum": @(-10000), @"maximum": @1}];
    distanceField.name = @"@0";
    distanceField.allowsGroupOpacity = YES;
    [distanceField setValuesForKeysWithDictionary:@{
        @"allowsGroupBlending": @YES, @"smoothness": @0, @"gaussianRadius": @0,
        @"effectOffset": @0, @"mergeElements": @NO, @"effect": output
    }];
    shape.cornerCurve = kCACornerCurveContinuous;
    shape.allowsGroupOpacity = YES;
    [shape setValuesForKeysWithDictionary:@{
        @"allowsGroupBlending": @YES, @"hitTestsAsFill": @YES,
        @"gradientOvalization": @0.5, @"contentsZeroValueDistance": @0,
        @"contentsOneValueDistance": @1, @"mode": @"bounds", @"operation": @"union"
    }];
    CALayer *shapeGroup = CreateLayer(CALayer.class);
    [shapeGroup addSublayer:shape];
    [distanceField addSublayer:shapeGroup];
    [backdrop addSublayer:distanceField];
    backdrop.filters = @[filter];

    ARLockGlassPass *pass = [ARLockGlassPass new];
    pass.backdrop = backdrop;
    pass.distanceField = distanceField;
    pass.shape = shape;
    return pass;
}

static CALayer *CreateBorder(NSColor *color) {
    CALayer *border = CreateLayer(CALayer.class);
    border.cornerCurve = kCACornerCurveContinuous;
    border.borderWidth = 1;
    border.borderColor = color.CGColor;
    return border;
}

@interface ARLockClearGlassView : NSView
- (instancetype)initWithFrame:(NSRect)frame radius:(CGFloat)radius passes:(NSArray<ARLockGlassPass *> *)passes;
- (void)setTintOpacity:(CGFloat)rawOpacity;
@end

@implementation ARLockClearGlassView {
    CGFloat _radius;
    NSArray<ARLockGlassPass *> *_passes;
    CALayer *_tint;
    CALayer *_innerContainer, *_innerMiddle, *_innerBorder, *_outerBorder;
    CAGradientLayer *_edgeGradient;
}

- (instancetype)initWithFrame:(NSRect)frame radius:(CGFloat)radius passes:(NSArray<ARLockGlassPass *> *)passes {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    _radius = radius;
    _passes = [passes copy];
    self.wantsLayer = YES;
    self.layer = CreateLayer(NSClassFromString(@"SwiftUI.SDFLayer")) ?: CreateLayer(CALayer.class);
    self.layer.cornerCurve = kCACornerCurveContinuous;
    self.layer.masksToBounds = NO;
    for (ARLockGlassPass *pass in _passes) [self.layer addSublayer:pass.backdrop];

    // Tint the refracted wallpaper. The foreground optics and border highlights
    // are composited above this layer and the playback controls remain independent.
    _tint = CreateLayer(CALayer.class);
    _tint.backgroundColor = NSColor.blackColor.CGColor;
    _tint.cornerCurve = kCACornerCurveContinuous;
    _tint.cornerRadius = radius;
    _tint.opacity = 0;
    _tint.hidden = YES;
    [self.layer insertSublayer:_tint below:_passes.lastObject.backdrop];

    _innerContainer = CreateLayer(CALayer.class);
    _innerContainer.compositingFilter = @"plusL";
    _innerContainer.zPosition = 1000;
    _innerMiddle = CreateLayer(CALayer.class);
    [self.layer addSublayer:_innerContainer];
    [_innerContainer addSublayer:_innerMiddle];

    _edgeGradient = [CAGradientLayer layer];
    _edgeGradient.anchorPoint = CGPointZero;
    _edgeGradient.geometryFlipped = YES;
    NSMutableArray *colors = [NSMutableArray new];
    for (NSNumber *alpha in @[@0, @0.5, @1, @1, @1, @0.5, @0]) {
        NSColor *color = [NSColor colorWithSRGBRed:0 green:0 blue:0 alpha:alpha.doubleValue];
        [colors addObject:(__bridge id)color.CGColor];
    }
    _edgeGradient.colors = colors;
    _edgeGradient.locations = @[@0, @0.125, @0.25, @0.5, @0.75, @0.875, @1];
    _edgeGradient.startPoint = CGPointMake(1, 0);
    _edgeGradient.endPoint = CGPointMake(-0.178138314, 0.299679190);
    _innerMiddle.mask = _edgeGradient;
    _innerBorder = CreateBorder([NSColor colorWithSRGBRed:1 green:1 blue:1 alpha:0.2]);
    [_innerMiddle addSublayer:_innerBorder];
    _outerBorder = CreateBorder([NSColor colorWithSRGBRed:0 green:0 blue:0 alpha:0.1375]);
    _outerBorder.compositingFilter = @"plusD";
    _outerBorder.zPosition = 1001;
    [self.layer addSublayer:_outerBorder];
    [self setNeedsLayout:YES];
    [self layoutSubtreeIfNeeded];
    return self;
}

- (NSView *)hitTest:(NSPoint)point {
    return nil;
}

- (void)setTintOpacity:(CGFloat)rawOpacity {
    float opacity = isfinite(rawOpacity) ? (float)MIN(1.0, MAX(0.0, rawOpacity)) : 0;
    if (_tint.opacity == opacity) return;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    _tint.opacity = opacity;
    _tint.hidden = opacity == 0;
    [CATransaction commit];
}

- (void)layout {
    [super layout];
    CGRect bounds = self.bounds;
    [CATransaction begin];
    // The card owns the resize animation. Its optical geometry follows each
    // presented size without creating an additional Core Animation timeline.
    [CATransaction setDisableActions:YES];
    for (ARLockGlassPass *pass in _passes) {
        pass.backdrop.frame = bounds;
        pass.distanceField.frame = bounds;
        pass.shape.frame = bounds;
        pass.shape.cornerRadius = _radius;
    }
    _tint.frame = bounds;
    _innerContainer.frame = bounds;
    _innerMiddle.frame = (CGRect){CGPointZero, bounds.size};
    _edgeGradient.frame = _innerMiddle.bounds;
    _innerBorder.frame = (CGRect){CGPointMake(1, 1), bounds.size};
    _innerBorder.cornerRadius = _radius;
    _outerBorder.frame = CGRectInset(bounds, -1, -1);
    _outerBorder.cornerRadius = _radius + 1;
    [CATransaction commit];
}
@end

NSView *ARCreateLockClearGlassView(NSRect frame, CGFloat radius) {
    // Keep private KVC failures on the Objective-C side of the Swift boundary.
    @try {
        ARLockGlassPass *background = CreateGlassPass(NO);
        if (!background) return nil;
        ARLockGlassPass *foreground = CreateGlassPass(YES);
        if (!foreground) return nil;
        return [[ARLockClearGlassView alloc] initWithFrame:frame radius:radius passes:@[background, foreground]];
    } @catch (NSException *exception) {
        return nil;
    }
}

void ARSetLockClearGlassTintOpacity(NSView *view, CGFloat rawOpacity) {
    if ([view isKindOfClass:ARLockClearGlassView.class]) {
        [(ARLockClearGlassView *)view setTintOpacity:rawOpacity];
    }
}
