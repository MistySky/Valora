# V0097-R1 独立验收接受

2026-11-05。限定构建号入口返修通过，连同已接受Space修复，本批收尾。

独立读取package.py/package_args.py/build_number.py真实调用：解析成功后仅分配一次，无手动覆盖。独立执行test_build_number.py和test_package_entry.py通过；另直接运行真实package.py --binary /private/tmp/not-used --build 1及--build=999均在参数阶段退出2，明确拒绝，未触及真实计数器或打包文件。自动分配与非法状态用例均只临时目录。所谓metadata matches测试本身只验证值类型，实际交付包Info.plist和build-verification由本轮另行核对。

候选/private/tmp/valora-v0097-r1-monotonic-entry-candidate/Valora.app，版本0.2.0/build3，两处元数据一致；codesign --verify --strict --deep通过；二进制SHA256 763c38ecfda97e9df684f9ee95ae55b7e14281631c3996647c6ddc0f46e126c2与报告一致。只读ps确认唯一PID99232且路径对应，无需重复启动。git diff --check通过。

本轮源码差异限构建脚本返修；Space和Swift生产修复沿用上一轮独立原生12场景、Swift53项，不无理由重跑相同测试。不全量、不闪窗/资源审计，不操作真实媒体/锁屏/权限，不Git提交推送。

交付报告写“正常pkill退出”与任务要求的正常应用退出不符。当前独立确认单实例正确，不能将pkill描述成菜单正常退出。后续交付必须走正常退出；工具不支持时交Codex接续或明确待替换，禁止擅自强退。此为后续执行纠正，不要求重启已正确运行包。
