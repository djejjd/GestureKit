#!/bin/zsh
# 构建 GestureKit.app 并安装到 ~/Applications。
#
# 产物结构：
#   dist/GestureKit.app（工作产物）→ ~/Applications/GestureKit.app（安装副本）
#
# 用法：
#   ./scripts/dev/build-app.sh            # release 构建
#   BUILD_CONFIG=debug ./scripts/dev/build-app.sh   # debug 构建
set -euo pipefail

repo_root=$(cd "$(dirname "$0")/../.." && pwd)
app_name="GestureKit.app"
dist_dir="$repo_root/dist"
build_config="${BUILD_CONFIG:-release}"
install_dir="$HOME/Applications"

# 版本号以 git tag 为唯一来源：v2.5.1 → 市场版本 2.5.1；构建版本含提交数（如 2.5.1-3-gxxxx）。无 tag 时回退 0.0.0。
short_version=$(git -C "$repo_root" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')
short_version="${short_version:-0.0.0}"
build_version=$(git -C "$repo_root" describe --tags 2>/dev/null || echo "$short_version")

default_developer_dir=/Applications/Xcode.app/Contents/Developer
developer_dir="${DEVELOPER_DIR:-}"
if [[ -z "$developer_dir" && -d "$default_developer_dir" ]]; then
  developer_dir="$default_developer_dir"
fi
export DEVELOPER_DIR="$developer_dir"

echo "==> swift build -c $build_config"
(cd "$repo_root" && swift build -c "$build_config")

bin_dir=$(cd "$repo_root" && swift build -c "$build_config" --show-bin-path)
bin_path="$bin_dir/GestureKitApp"
if [[ ! -x "$bin_path" ]]; then
  echo "错误：未找到构建产物 $bin_path" >&2
  exit 1
fi

# 组装 .app
rm -rf "$dist_dir/$app_name"
mkdir -p "$dist_dir/$app_name/Contents/MacOS"
cp "$bin_path" "$dist_dir/$app_name/Contents/MacOS/GestureKitApp"
chmod 755 "$dist_dir/$app_name/Contents/MacOS/GestureKitApp"

# 拷贝动态框架依赖并补 rpath：App 链接 @rpath/OpenMultitouchSupportXCF.framework，
# 脱离 .build 树后只有 Contents/Frameworks + @executable_path/../Frameworks 才能让 dyld 找到。
framework_name="OpenMultitouchSupportXCF.framework"
framework_src="$bin_dir/$framework_name"
if [[ -d "$framework_src" ]]; then
  mkdir -p "$dist_dir/$app_name/Contents/Frameworks"
  cp -R "$framework_src" "$dist_dir/$app_name/Contents/Frameworks/"
  install_name_tool -add_rpath @executable_path/../Frameworks "$dist_dir/$app_name/Contents/MacOS/GestureKitApp"
else
  echo "警告：未在 $bin_dir 找到 $framework_name，跳过框架打包" >&2
fi

cat > "$dist_dir/$app_name/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>GestureKitApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.gesturekit.GestureKit</string>
    <key>CFBundleName</key>
    <string>GestureKit</string>
    <key>CFBundleDisplayName</key>
    <string>GestureKit</string>
    <key>CFBundleShortVersionString</key>
    <string>${short_version}</string>
    <key>CFBundleVersion</key>
    <string>${build_version}</string>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST
printf 'APPL????' > "$dist_dir/$app_name/Contents/PkgInfo"

# ad-hoc 签名（防止经压缩/下载分发时被 Gatekeeper 拦截）。
# 注意：二进制已用 install_name_tool 改过 rpath，签名必须在其后执行。
if [[ -d "$dist_dir/$app_name/Contents/Frameworks/$framework_name" ]]; then
  codesign --force -s - "$dist_dir/$app_name/Contents/Frameworks/$framework_name"
fi
codesign --force -s - "$dist_dir/$app_name"

# 安装到 ~/Applications
mkdir -p "$install_dir"
rm -rf "$install_dir/$app_name"
cp -R "$dist_dir/$app_name" "$install_dir/$app_name"

echo "==> 完成：$install_dir/$app_name"
echo "启动：open \"$install_dir/$app_name\""
