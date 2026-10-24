# V0004-R3：落实深色原图转灰度

用户已明确同意并要求“先落地”：菜单栏用用户确认的Transparent深色版完整图标转灰度。覆盖R2以浅色AppIcon.icns为菜单栏输入的选择；保留完整构图/圆角底板/V/明暗层次/透明外角，18pt、isTemplate=false。应用包默认图标仍为彩色浅色版，不能为菜单栏修改AppIcon.icns或CFBundleIconFile。

从Resources/AppIcons/dark/Velora-dark.icns明确打包独立菜单栏来源（例如MenuBarIcon.icns），加载此资源后沿用CIColorControls(saturation=0)，不重画、不生成图。构建时缺资源应明确报错，记录来源/包内指纹；修正--verify-menubar中的来源描述与检查，不能仍写AppIcon.icns/浅色。只修改必要加载/打包/验证与说明，不重构业务、改音乐UI或菜单行为。

重建dist/Valora.app并验签；核对彩色应用图标未变、菜单栏来源与用户深色源逐字节一致、实际button.image为18pt无彩色且透明外角正常。查看菜单栏小尺寸预览，条件允许只截菜单栏图标区域，区分实屏和离屏。报告docs/reports/v0004-r3.md、必要证据docs/verification/v0004-r3/，完成后停止等Codex独立验收。禁止真实播放/切歌/seek/系统设置写入、安装发布或Git提交。无需重复大批与本改动无关的回归。
