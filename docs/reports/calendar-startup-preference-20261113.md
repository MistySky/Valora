# 日历开关启动恢复修复

用户反馈重启或重装后，系统授权仍在，但日历开关需要重新开启。本批在 codex/resource-idle-render-dedup 修复权限初始状态；不改歌词、动画、日历样式或用户偏好。

AppPermissions 原先虽然将默认 EventKitCalendarAuthorization 保存到 self.calendarProvider，初始化 calendar 却读取可选参数 calendarProvider。生产构造不传该参数，因此初始状态总为 unknown。SettingsView 首次显示时会将非 fullAccess 的已开启偏好写成 false；应用激活后的 refresh 即使读到 fullAccess，也不会恢复已经写成关闭的选择。启动的节假日读取门控同样使用该初始状态。

现改为从已经解析的 self.calendarProvider.status 初始化。显式注入 calendar 状态仍优先；只调用 EventKit 的授权状态查询，不请求授权、不创建事件存储、不读取事件。既有主动关闭、权限拒绝及取消流程不变，不因系统授权存在而自动打开用户关闭的功能。

新增默认生产 provider 初始化回归和隔离 UserDefaults 重建后保留 on/off 的回归。修改前4项中1项失败：系统查询 notDetermined，但 AppPermissions.calendar 为 unknown。修改后 IndependentCalendarPermissionTests、AppPermissionsTests、IndependentPermissionFlowTests、IndependentPersistedPermissionTests 共21项通过，git diff --check通过。日志：/private/tmp/valora-calendar-startup-before-20261113.log 和 /private/tmp/valora-calendar-startup-after-20261113.log。

测试验证的是初始状态缺陷与隔离偏好恢复；没有重启用户真实应用或实际重装验证。已被旧版写成 false 的偏好无法与用户主动关闭区分，不自动修改；修复版本中用户重新打开一次后应保留，前提是系统授权仍有效且偏好文件未被卸载清理。

仅源码与测试完成，未构建正式候选、提交、推送、发布或合入main；未替换Brew安装、未控制播放。歌词高亮落后及偶发左右重复的反馈仍未定位，本次修复不代表解决了歌词问题。
