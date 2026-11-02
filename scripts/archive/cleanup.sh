#!/bin/sh
R=/data/ohc/rootfs/claude/root
mkdir -p /data/ohc/scripts

# 留档：安装脚本和 API 测试脚本
cp -f "$R/install-claude.sh" /data/ohc/scripts/ 2>/dev/null
cp -f "$R/test-api.sh"      /data/ohc/scripts/ 2>/dev/null
cp -f "$R/demo.sh"          /data/ohc/scripts/ 2>/dev/null

# 清掉容器 /root 下的调试脚本，只留 .claude.json 和 .claude/
for f in envcheck.sh findenv.sh install-claude.sh ls-pkg.sh lsroot.sh onboard.sh \
         smoke.sh strings.sh test-api.sh checkcfg.sh findcfg.sh home.sh \
         catcfg.sh demo.sh; do
    rm -f "$R/$f"
done

echo "--- 容器 /root 现在的内容 ---"
ls -la "$R"
echo "--- /data/ohc/scripts ---"
ls -la /data/ohc/scripts
