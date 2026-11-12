# 封面内存有界化（2026-11-10）

## 范围

仅处理封面准备链路；未改歌词/动画、锁屏、截图窗口、AirPods、媒体 helper、设置页或真实播放控制。保留 build57 作为动画回退候选。

## 输入像素预算

- 封面实际显示为 56pt；当前 Retina 2x 为 112px。
- `ArtworkImage.maxPixel = 256`，为 3x 和非方形源留余量；不把 pt 当 px。
- 大图从压缩 `Data` 直接用 ImageIO `CGImageSourceCreateThumbnailAtIndex` 降采样；`kCGImageSourceCreateThumbnailWithTransform` 处理 EXIF 方向，`FromImageAlways` 只对超预算源使用。
- 源图最长边不超过 256px 时直接取原 CGImage，不放大。
- `MediaController.applySystem` 由 `NSImage(data:)` 改为 `ArtworkImage.prepare(data)`；媒体 source 的原始 `Data` 协议、去重和 current/target/queued 过渡保持不变。

## 身份策略

- 封面 identity 不再序列化整张 TIFF。
- identity 来自规范化 **64×64 sRGB 像素 + 宽高比** 的 SHA-256；不是 32×32 调色板/颜色列表。
- 相同视觉的无损重编码保持稳定（PNG/TIFF 测试）；不同图片即使主色相同，因像素/比例不同不混淆。
- 调色板仍使用原来的 32×32 画布、7 桶、距离 0.08、最多 4 色规则；只用有界图提色，不新建全局缓存。

## 验证

新增 `ArtworkMemoryBoundedTests`，7 个测试通过（另附 orientation 定向）：

- 3000×3000 PNG 经新路径最大边 ≤256；
- 120×60 小图不放大；1200×600 保留 2:1；
- PNG/TIFF 同像素 identity 相同；
- 同主色不同比例 identity 不同；
- 透明/不透明 identity 不同，损坏/空 Data 返回 nil；
- EXIF orientation 6 输出纵向；
- 56pt 隔离视图 old/new 截图对照（实心 fixture）differing 0.000%，meanRGB 0.00。

大图一次性估算（不是实测 footprint）：

```text
ARTWORK_EST compressed=165099
originalPixels=9000000 originalRGBA=36000000
preparedPixels=65536 preparedRGBA=262144
```

这是 3000×3000 单张图的像素/RGBA 估算；新准备位图为 256×256。不能据此宣称用户稳态内存一定减少几十 MB，未做真实峰值/长期 footprint 测量。

## 未验项

- 真实 Apple Music/QQ 音乐封面、真实 3x 屏、非方形/损坏封面的实机体感未在本批读取真实媒体验证；
- 256px 对极细纹理的 56pt 视觉差异仅做了单张隔离 fixture，不能承诺所有封面数学无损；
- 真实内存峰值和长期稳态仍待 Codex/用户配合；
- 未提交 Git，未改真实用户偏好。

## 候选

- `/private/tmp/valora-artwork-memory-bounded-20261110/Valora.app`
- `1.0.3 (58)`
- binary SHA-256：`7e51ee508233d0b221dfb82b05e9b79cfe622d02a31cd73d11dff1dc23960389`
- strict/deep 签名通过
- 当前唯一实例 PID `20124`，普通启动无诊断环境变量
- 回退保留 build57：`/private/tmp/valora-lyrics-transition-parity-r3e-20261110/Valora.app`

## R1：小图 EXIF 与完整有界身份

build58 独立验收发现两处具体风险，R1 已修正：

### 1. 小图 EXIF 方向

`ArtworkImage.prepare` 现在读取 `kCGImagePropertyOrientation`：

- orientation == 1 且最长边 ≤256 时仍走无重采样原图路径；
- orientation 非 1（2—8 镜像/旋转）一律走 ImageIO `CreateThumbnailWithTransform`，即使原图很小；
- 缩略预算取 `min(256, 原图最长边)`，保证小图不放大；
- 方向通过实际像素变换实现，不在 NSImage 逻辑 size 上交换数字。

独立回归 `testSmallArtworkHonorsExifOrientation`（120×60 TIFF，orientation=6）现在通过，输出 60×120。

### 2. 身份不再用 64×64 缩略

`ArtworkPalette` 的 identity 改为哈希**完整的有界规范化像素**：

- 输入在 256px 预算内规范化到 sRGB/premultipliedLast；
- 哈希包含实际 width/height 和全部有效 RGBA 行；
- 缓冲区每行 stride = width×4，零初始化，不哈希未使用的 padding；
- 不再把 256×256 checkerboard 缩成 64×64 后碰撞；独立 `testDifferentFineDetailArtworkHasDifferentIdentity` 通过；
- identity 与 32×32 调色板分离，PNG/TIFF 同像素稳定。

### 验证

- `IndependentArtworkPreparationTests` 2 项通过；
- `ArtworkMemoryBoundedTests` 8 项通过（含小图/大图/EXIF/透明/非方形/损坏/PNG-TIFF identity）；
- `ArtworkGapTransitionTests` 6 项、`RealArtworkViewStageTests` 2 项通过；
- 56pt 有细节样本（30 块彩色 checker，1200×1200）对照：differing 33.538%，meanRGB 3.83；边缘像素因重采样仍可不同，不声称像素无损；
- 3000×3000 一次性估算仍为 originalRGBA 36,000,000 → preparedRGBA 262,144；identity 现在额外使用完整有界像素，但仍不长期保留原图或整歌缓存；
- 未读取/控制真实媒体，未测真实 footprint。

### R1 候选

- `/private/tmp/valora-artwork-memory-bounded-r1-20261110/Valora.app`
- `1.0.3 (59)`
- binary SHA-256：`dbb077d32b8bb802eba539b0c0bbdf34a7143d1ac7fe5a8a4f921b66534183c6`
- strict/deep 签名通过
- 当前唯一实例 PID `22112`，普通启动无诊断
- 回退保留 build58：`/private/tmp/valora-artwork-memory-bounded-20261110/Valora.app`；build57：`/private/tmp/valora-lyrics-transition-parity-r3e-20261110/Valora.app`
