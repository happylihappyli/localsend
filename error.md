┌────────────────────────────────────────────────────────────────┐
│  LocalSend 工具箱  v1.18.2-2-gdaa65270-dirty git: main @ daa65270*  ·  │
│  工具链: fvm ✓                                                  │
│  共 55 个任务（8 个 tab）                                           │
└────────────────────────────────────────────────────────────────┘
点上面 tab 按钮跑任务。chain 任务自动串行；长任务转圈说明在跑。

=== 打 Linux AppImage (build + appimage-builder) ===
$ bash -c 'cd app && fvm flutter build linux --release && cd .. && rm -rf AppDir appimage-build LocalSend-*.AppImage && mkdir -p AppDir && cp -r app/build/linux/x64/release/bundle/* AppDir/ && cp support/build/appimage/AppImageBuilder_x86_64.yml AppImageBuilder.yml && APPIMAGE_BUILDER=$(command -v appimage-builder 2>/dev/null || ls -1 /usr/local/bin/appimage-builder ~/.local/bin/appimage-builder /home/bv/code/localsend/.tools/appimage-builder 2>/dev/null | head -1) && if [ -z "$APPIMAGE_BUILDER" ] || [ ! -x "$APPIMAGE_BUILDER" ]; then echo '[错误] appimage-builder 未安装或不可执行。跑：'; echo '       python3 install-appimage-builder.py'; exit 1; fi && echo "[使用] $APPIMAGE_BUILDER" && "$APPIMAGE_BUILDER" --recipe AppImageBuilder.yml && chmod +x LocalSend-*-x86_64.AppImage && echo '\n[完成] AppImage 产物：' && ls -lh LocalSend-*.AppImage'
  (cwd: /home/bv/code/localsend)
  [代理: http://127.0.0.1:7890，NO_PROXY=localhost,127.0.0.1,::1]
  [镜像: 未启用]
Resolving dependencies in `/home/bv/code/localsend`...
Downloading packages...
  _fe_analyzer_shared 93.0.0 (105.0.0 available)
  analyzer 10.0.1 (14.1.0 available)
  assorted_layout_widgets 11.0.0 (12.12.1 available)
  build 4.0.7 (4.0.10 available)
  build_runner 2.15.1 (2.16.0 available)
  code_assets 1.2.1 (2.0.0 available)
  dart_mappable_builder 4.8.0 (4.9.0 available)
  dart_style 3.1.7 (3.1.12 available)
  desktop_drop 0.7.1 (0.8.1 available)
! device_apps 2.2.0 from git https://github.com/Tienisto/device_apps.git at 5dc795 (overridden)
  device_info_plus 12.4.0 (13.2.0 available)
  device_info_plus_platform_interface 7.0.3 (8.1.0 available)
  dynamic_color 1.8.1 (2.1.0 available)
  file_picker 11.0.3 (12.1.0 available)
  file_selector_android 0.5.2+6 (0.5.2+9 available)
  flex_seed_scheme 4.0.1 (5.0.0 available)
  flutter_foreground_task 9.2.2 (11.0.1 available)
  flutter_rust_bridge 2.12.0 (2.13.0 available)
  freezed 3.2.5 (4.0.0 available)
  hooks 2.0.2 (2.2.0 available)
  image 4.9.1 (4.9.2 available)
  image_picker_android 0.8.13+17 (0.8.13+19 available)
  in_app_purchase_android 0.5.0 (0.5.2 available)
  intl 0.20.2 (0.20.3 available)
  matcher 0.12.19 (0.12.20 available)
  material_color_utilities 0.13.0 (0.13.1 available)
  meta 1.17.0 (1.19.0 available)
  mockito 5.6.4 (5.8.1 available)
  network_info_plus 7.0.0 (8.2.1 available)
  network_info_plus_platform_interface 2.0.2 (3.1.0 available)
  objective_c 9.5.0 (9.6.0 available)
  package_config 2.2.0 (3.0.0 available)
  package_info_plus 9.0.1 (10.2.1 available)
  package_info_plus_platform_interface 3.2.1 (4.1.0 available)
! pasteboard 0.3.0 from git https://github.com/Seidko/flutter-plugins.git at 58748d in packages/pasteboard (overridden)
  permission_handler 12.0.3 (13.0.1 available)
  permission_handler_android 13.0.1 (14.0.0 available)
! permission_handler_windows 0.1.2 from git https://github.com/localsend/permission_handler_windows_noop.git at 2dadd8 (overridden)
  qr 3.0.2 (4.0.0 available)
  record_use 0.6.0 (1.1.1 available)
  share_handler 0.0.22 (0.0.25 available)
  shared_preferences_android 2.4.23 (2.4.27 available)
  shelf_web_socket 2.0.1 (3.0.0 available)
  source_gen 4.2.4 (4.3.0 available)
  test 1.30.0 (1.31.2 available)
  test_api 0.7.10 (0.7.13 available)
  test_core 0.6.16 (0.6.19 available)
  uri_content 3.1.1 (4.0.1 available)
  url_launcher_android 6.3.30 (6.3.32 available)
  vector_math 2.2.0 (2.4.2 available)
  video_player 2.11.1 (2.14.0 available)
  video_player_android 2.9.5 (2.12.0 available)
  wakelock_plus 1.5.2 (1.7.0 available)
  win32 5.15.0 (6.4.0 available)
  win32_registry 2.1.0 (3.0.3 available)
Got dependencies in `/home/bv/code/localsend`!
52 packages have newer versions incompatible with dependency constraints.
Try `flutter pub outdated` for more information.
Building Linux application...                                   
✓ Built build/linux/x64/release/bundle/localsend_app
[使用] /home/bv/code/localsend/.tools/appimage-builder
INFO:main:Running main script
which mksquashfs || apt install squashfs-tools
/usr/bin/mksquashfs
INFO:main:Running apt deploy
INFO:apt:apt-get update
获取:1 http://security.ubuntu.com/ubuntu jammy-security InRelease [129 kB]
获取:2 http://archive.ubuntu.com/ubuntu jammy InRelease [270 kB]
忽略:1 http://security.ubuntu.com/ubuntu jammy-security InRelease
忽略:2 http://archive.ubuntu.com/ubuntu jammy InRelease
获取:3 http://security.ubuntu.com/ubuntu jammy-security/multiverse amd64 Packages [69.1 kB]
获取:4 http://archive.ubuntu.com/ubuntu jammy-updates InRelease [128 kB]
获取:5 http://security.ubuntu.com/ubuntu jammy-security/universe amd64 Packages [1,047 kB]
忽略:4 http://archive.ubuntu.com/ubuntu jammy-updates InRelease
获取:6 http://archive.ubuntu.com/ubuntu jammy-backports InRelease [127 kB]
忽略:6 http://archive.ubuntu.com/ubuntu jammy-backports InRelease
获取:7 http://security.ubuntu.com/ubuntu jammy-security/main amd64 Packages [3,497 kB]
获取:8 http://archive.ubuntu.com/ubuntu jammy/main amd64 Packages [1,395 kB]
获取:9 http://security.ubuntu.com/ubuntu jammy-security/restricted amd64 Packages [6,269 kB]
获取:10 http://archive.ubuntu.com/ubuntu jammy/universe amd64 Packages [14.1 MB]
获取:11 http://archive.ubuntu.com/ubuntu jammy/restricted amd64 Packages [129 kB]
获取:12 http://archive.ubuntu.com/ubuntu jammy/multiverse amd64 Packages [217 kB]
获取:13 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 Packages [3,771 kB]
获取:14 http://archive.ubuntu.com/ubuntu jammy-updates/multiverse amd64 Packages [76.5 kB]
获取:15 http://archive.ubuntu.com/ubuntu jammy-updates/restricted amd64 Packages [6,510 kB]
获取:16 http://archive.ubuntu.com/ubuntu jammy-updates/universe amd64 Packages [1,282 kB]
获取:17 http://archive.ubuntu.com/ubuntu jammy-backports/main amd64 Packages [70.2 kB]
获取:18 http://archive.ubuntu.com/ubuntu jammy-backports/universe amd64 Packages [30.8 kB]
已下载 39.1 MB，耗时 43秒 (899 kB/s)
正在读取软件包列表...
W
: GPG 错误：http://security.ubuntu.com/ubuntu jammy-security InRelease: 由于没有公钥，无法验证下列签名： NO_PUBKEY 871920D1991BC93C
W: 仓库 “http://security.ubuntu.com/ubuntu jammy-security InRelease” 没有数字签名。
W: GPG 错误：http://archive.ubuntu.com/ubuntu jammy InRelease: 由于没有公钥，无法验证下列签名： NO_PUBKEY 871920D1991BC93C
W: 仓库 “http://archive.ubuntu.com/ubuntu jammy InRelease” 没有数字签名。
W: GPG 错误：http://archive.ubuntu.com/ubuntu jammy-updates InRelease: 由于没有公钥，无法验证下列签名： NO_PUBKEY 871920D1991BC93C
W: 仓库 “http://archive.ubuntu.com/ubuntu jammy-updates InRelease” 没有数字签名。
W: GPG 错误：http://archive.ubuntu.com/ubuntu jammy-backports InRelease: 由于没有公钥，无法验证下列签名： NO_PUBKEY 871920D1991BC93C
W: 仓库 “http://archive.ubuntu.com/ubuntu jammy-backports InRelease” 没有数字签名。
正在读取软件包列表...
正在分析软件包的依赖关系树...
将会同时安装下列软件：
  avahi-daemon dbus dbus-user-session dconf-gsettings-backend dconf-service
  fdisk fontconfig fontconfig-config fonts-dejavu-core gcc-12-base
  hicolor-icon-theme libacl1 libapparmor1 libargon2-1 libatk-bridge2.0-0
  libatk1.0-0 libatk1.0-data libatspi2.0-0 libaudit-common libaudit1
  libavahi-client3 libavahi-common-data libavahi-common3 libavahi-core7
  libayatana-ido3-0.4-0 libayatana-indicator3-7 libblkid1 libbrotli1 libc6
  libcairo-gobject2 libcairo2 libcap-ng0 libcap2 libcap2-bin libcolord2
  libcom-err2 libcrypt1 libcryptsetup12 libcups2 libdaemon0 libdatrie1
  libdb5.3 libdbus-1-3 libdbusmenu-glib4 libdbusmenu-gtk3-4 libdconf1
  libdeflate0 libdevmapper1.02.1 libepoxy0 libexpat1 libfdisk1 libffi8
  libfontconfig1 libfreetype6 libfribidi0 libgcc-s1 libgcrypt20
  libgdk-pixbuf-2.0-0 libgdk-pixbuf2.0-common libglib2.0-0 libgmp10
  libgnutls30 libgpg-error0 libgraphite2-3 libgssapi-krb5-2 libgtk-3-0
  libgtk-3-common libharfbuzz0b libhogweed6 libicu70 libidn2-0 libip4tc2
  libjbig0 libjpeg-turbo8 libjpeg8 libjson-c5 libk5crypto3 libkeyutils1
  libkmod2 libkrb5-3 libkrb5support0 liblcms2-2 liblz4-1 liblzma5 libmount1
  libncursesw6 libnettle8 libnsl2 libp11-kit0 libpam-modules
  libpam-modules-bin libpam-runtime libpam-systemd libpam0g libpango-1.0-0
  libpangocairo-1.0-0 libpangoft2-1.0-0 libpcre2-8-0 libpcre3 libpixman-1-0
  libpng16-16 libreadline8 librsvg2-2 libseccomp2 libselinux1 libsmartcols1
  libssl3 libstdc++6 libsystemd0 libtasn1-6 libthai-data libthai0 libtiff5
  libtinfo6 libtirpc-common libtirpc3 libudev1 libunistring2 libuuid1 libwebp7
  libxcomposite1 libxcursor1 libxdamage1 libxext6 libxfixes3 libxi6
  libxinerama1 libxkbcommon0 libxml2 libxrandr2 libxrender1 libzstd1 mount
  readline-common systemd systemd-sysv util-linux xkb-data zlib1g
建议安装：
  avahi-autoipd glibc-doc locales colord cups-common rng-tools gnutls-bin
  krb5-doc krb5-user gvfs liblcms2-utils cryptsetup-bin libpam-doc
  librsvg2-bin nfs-common readline-doc systemd-container libfido2-1
  libtss2-esys-3.0.2-0 libtss2-mu0 libtss2-rc0 policykit-1 dosfstools kbd
  util-linux-locales
推荐安装：
  libnss-mdns at-spi2-core libnss-nis libnss-nisplus libpam-cap dmsetup
  libgdk-pixbuf2.0-bin libglib2.0-data libgpg-error-l10n libgtk-3-bin
  krb5-locales libgpm2 uuid-runtime networkd-dispatcher systemd-timesyncd
  | time-daemon libnss-systemd
下列【新】软件包将被安装：
  dbus-user-session dconf-gsettings-backend dconf-service fonts-dejavu-core
  gcc-12-base hicolor-icon-theme libacl1 libapparmor1 libargon2-1
  libatk-bridge2.0-0 libatk1.0-0 libatk1.0-data libatspi2.0-0 libaudit-common
  libaudit1 libavahi-client3 libavahi-common-data libavahi-common3
  libavahi-core7 libayatana-appindicator3-1 libayatana-ido3-0.4-0
  libayatana-indicator3-7 libblkid1 libbrotli1 libc6 libcairo-gobject2
  libcairo2 libcap-ng0 libcap2 libcolord2 libcom-err2 libcrypt1
  libcryptsetup12 libcups2 libdaemon0 libdatrie1 libdb5.3 libdbus-1-3
  libdbusmenu-glib4 libdbusmenu-gtk3-4 libdconf1 libdeflate0
  libdevmapper1.02.1 libepoxy0 libexpat1 libfdisk1 libffi8 libfontconfig1
  libfreetype6 libfribidi0 libgcc-s1 libgcrypt20 libgdk-pixbuf-2.0-0
  libgdk-pixbuf2.0-common libglib2.0-0 libgmp10 libgnutls30 libgpg-error0
  libgraphite2-3 libgssapi-krb5-2 libgtk-3-0 libgtk-3-common libharfbuzz0b
  libhogweed6 libicu70 libidn2-0 libip4tc2 libjbig0 libjpeg-turbo8 libjpeg8
  libjson-c5 libk5crypto3 libkeyutils1 libkmod2 libkrb5-3 libkrb5support0
  liblcms2-2 liblz4-1 liblzma5 libmount1 libncursesw6 libnettle8 libnsl2
  libp11-kit0 libpam-modules libpam-systemd libpam0g libpango-1.0-0
  libpangocairo-1.0-0 libpangoft2-1.0-0 libpcre2-8-0 libpcre3 libpixman-1-0
  libpng16-16 libreadline8 librsvg2-2 librsvg2-common libseccomp2 libselinux1
  libsmartcols1 libssl3 libstdc++6 libsystemd0 libtasn1-6 libthai-data
  libthai0 libtiff5 libtinfo6 libtirpc-common libtirpc3 libudev1 libunistring2
  libuuid1 libwebp7 libxcomposite1 libxcursor1 libxdamage1 libxext6 libxfixes3
  libxi6 libxinerama1 libxkbcommon0 libxml2 libxrandr2 libxrender1 libzstd1
  readline-common xkb-data zlib1g
下列软件包将被升级：
  avahi-daemon dbus fdisk fontconfig fontconfig-config libcap2-bin
  libpam-modules-bin libpam-runtime mount systemd systemd-sysv util-linux
升级了 12 个软件包，新安装了 129 个软件包，要卸载 0 个软件包，有 99 个软件包未被升级。
需要下载 47.1 MB 的归档。
解压缩后会消耗 161 MB 的额外空间。
【警告】：下列软件包不能通过认证！
  libaudit-common gcc-12-base libgcc-s1 libcrypt1 libc6 libcap-ng0 libaudit1
  libblkid1 libpcre2-8-0 libselinux1 libmount1 libpam0g libsmartcols1 libcap2
  libgpg-error0 libgcrypt20 liblz4-1 liblzma5 libzstd1 libsystemd0 libtinfo6
  libudev1 libuuid1 zlib1g util-linux libdb5.3 libcom-err2 libkrb5support0
  libk5crypto3 libkeyutils1 libssl3 libkrb5-3 libgssapi-krb5-2 libtirpc-common
  libtirpc3 libnsl2 libpam-modules-bin libpam-modules mount libacl1
  libapparmor1 libargon2-1 libdevmapper1.02.1 libjson-c5 libcryptsetup12
  libgmp10 libnettle8 libhogweed6 libunistring2 libidn2-0 libffi8 libp11-kit0
  libtasn1-6 libgnutls30 libip4tc2 libkmod2 libseccomp2 systemd systemd-sysv
  libavahi-common-data libavahi-common3 libavahi-core7 libdaemon0 libdbus-1-3
  libexpat1 dbus avahi-daemon libncursesw6 libpam-runtime libpcre3 libcap2-bin
  libfribidi0 libglib2.0-0 libstdc++6 libicu70 libpam-systemd readline-common
  libreadline8 libxml2 xkb-data libpng16-16 libxext6 dbus-user-session
  libdconf1 dconf-service dconf-gsettings-backend libfdisk1 fdisk libbrotli1
  libfreetype6 fonts-dejavu-core fontconfig-config libfontconfig1 fontconfig
  hicolor-icon-theme libatk1.0-data libatk1.0-0 libxi6 libatspi2.0-0
  libatk-bridge2.0-0 libavahi-client3 libpixman-1-0 libxrender1 libcairo2
  libgdk-pixbuf2.0-common libjpeg-turbo8 libjpeg8 libdeflate0 libjbig0
  libwebp7 libtiff5 libgdk-pixbuf-2.0-0 libcairo-gobject2 liblcms2-2
  libcolord2 libcups2 libepoxy0 libgraphite2-3 libharfbuzz0b libthai-data
  libdatrie1 libthai0 libpango-1.0-0 libpangoft2-1.0-0 libpangocairo-1.0-0
  libxcomposite1 libxfixes3 libxcursor1 libxdamage1 libxinerama1 libxkbcommon0
  libxrandr2 libgtk-3-common libgtk-3-0 libayatana-ido3-0.4-0
  libayatana-indicator3-7 libdbusmenu-glib4 libdbusmenu-gtk3-4
  libayatana-appindicator3-1 librsvg2-2 librsvg2-common
已忽略认证警告。
获取:1 http://archive.ubuntu.com/ubuntu jammy/main amd64 libaudit-common all 1:3.0.7-1build1 [4,726 B]
获取:2 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 gcc-12-base amd64 12.3.0-1ubuntu1~22.04.3 [216 kB]
获取:3 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libgcc-s1 amd64 12.3.0-1ubuntu1~22.04.3 [53.9 kB]
获取:4 http://archive.ubuntu.com/ubuntu jammy/main amd64 libcrypt1 amd64 1:4.4.27-1 [82.0 kB]
获取:5 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libc6 amd64 2.35-0ubuntu3.14 [3,234 kB]
获取:6 http://archive.ubuntu.com/ubuntu jammy/main amd64 libcap-ng0 amd64 0.7.9-2.2build3 [11.6 kB]
获取:7 http://archive.ubuntu.com/ubuntu jammy/main amd64 libaudit1 amd64 1:3.0.7-1build1 [46.9 kB]
获取:8 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libblkid1 amd64 2.37.2-4ubuntu3.5 [103 kB]
获取:9 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libpcre2-8-0 amd64 10.39-3ubuntu0.1 [221 kB]
获取:10 http://archive.ubuntu.com/ubuntu jammy/main amd64 libselinux1 amd64 3.3-1build2 [74.6 kB]
获取:11 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libmount1 amd64 2.37.2-4ubuntu3.5 [122 kB]
获取:12 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libpam0g amd64 1.4.0-11ubuntu2.7 [59.7 kB]
获取:13 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libsmartcols1 amd64 2.37.2-4ubuntu3.5 [50.7 kB]
获取:14 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libcap2 amd64 1:2.44-1ubuntu0.22.04.3 [18.5 kB]
获取:15 http://archive.ubuntu.com/ubuntu jammy/main amd64 libgpg-error0 amd64 1.43-3 [69.7 kB]
获取:16 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libgcrypt20 amd64 1.9.4-3ubuntu3.2 [516 kB]
获取:17 http://archive.ubuntu.com/ubuntu jammy/main amd64 liblz4-1 amd64 1.9.3-2build2 [56.9 kB]
获取:18 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 liblzma5 amd64 5.2.5-2ubuntu1.1 [99.6 kB]
获取:19 http://archive.ubuntu.com/ubuntu jammy/main amd64 libzstd1 amd64 1.4.8+dfsg-3build1 [324 kB]
获取:20 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libsystemd0 amd64 249.11-0ubuntu3.22 [316 kB]
获取:21 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libtinfo6 amd64 6.3-2ubuntu0.2 [105 kB]
获取:22 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libudev1 amd64 249.11-0ubuntu3.22 [75.9 kB]
获取:23 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libuuid1 amd64 2.37.2-4ubuntu3.5 [23.6 kB]
获取:24 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 zlib1g amd64 1:1.2.11.dfsg-2ubuntu9.2 [58.4 kB]
获取:25 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 util-linux amd64 2.37.2-4ubuntu3.5 [1,067 kB]
获取:26 http://archive.ubuntu.com/ubuntu jammy/main amd64 libdb5.3 amd64 5.3.28+dfsg1-0.8ubuntu3 [722 kB]
获取:27 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libcom-err2 amd64 1.46.5-2ubuntu1.2 [9,304 B]
获取:28 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libkrb5support0 amd64 1.19.2-2ubuntu0.8 [32.7 kB]
获取:29 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libk5crypto3 amd64 1.19.2-2ubuntu0.8 [86.5 kB]
获取:30 http://archive.ubuntu.com/ubuntu jammy/main amd64 libkeyutils1 amd64 1.6.1-2ubuntu3 [10.4 kB]
获取:31 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libssl3 amd64 3.0.2-0ubuntu1.29 [1,906 kB]
获取:32 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libkrb5-3 amd64 1.19.2-2ubuntu0.8 [356 kB]
获取:33 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libgssapi-krb5-2 amd64 1.19.2-2ubuntu0.8 [145 kB]
获取:34 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libtirpc-common all 1.3.2-2ubuntu0.1 [7,766 B]
获取:35 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libtirpc3 amd64 1.3.2-2ubuntu0.1 [82.3 kB]
获取:36 http://archive.ubuntu.com/ubuntu jammy/main amd64 libnsl2 amd64 1.3.0-2build2 [42.3 kB]
获取:37 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libpam-modules-bin amd64 1.4.0-11ubuntu2.7 [37.6 kB]
获取:38 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libpam-modules amd64 1.4.0-11ubuntu2.7 [282 kB]
获取:39 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 mount amd64 2.37.2-4ubuntu3.5 [114 kB]
获取:40 http://archive.ubuntu.com/ubuntu jammy/main amd64 libacl1 amd64 2.3.1-1 [16.2 kB]
获取:41 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libapparmor1 amd64 3.0.4-2ubuntu2.5 [39.6 kB]
获取:42 http://archive.ubuntu.com/ubuntu jammy/main amd64 libargon2-1 amd64 0~20171227-0.3 [19.5 kB]
获取:43 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libdevmapper1.02.1 amd64 2:1.02.175-2.1ubuntu5 [139 kB]
获取:44 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libjson-c5 amd64 0.15-3~ubuntu1.22.04.2 [33.5 kB]
获取:45 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libcryptsetup12 amd64 2:2.4.3-1ubuntu1.3 [211 kB]
获取:46 http://archive.ubuntu.com/ubuntu jammy/main amd64 libgmp10 amd64 2:6.2.1+dfsg-3ubuntu1 [250 kB]
获取:47 http://archive.ubuntu.com/ubuntu jammy/main amd64 libnettle8 amd64 3.7.3-1build2 [159 kB]
获取:48 http://archive.ubuntu.com/ubuntu jammy/main amd64 libhogweed6 amd64 3.7.3-1build2 [199 kB]
获取:49 http://archive.ubuntu.com/ubuntu jammy/main amd64 libunistring2 amd64 1.0-1 [554 kB]
获取:50 http://archive.ubuntu.com/ubuntu jammy/main amd64 libidn2-0 amd64 2.3.2-2build1 [66.4 kB]
获取:51 http://archive.ubuntu.com/ubuntu jammy/main amd64 libffi8 amd64 3.4.2-4 [22.3 kB]
获取:52 http://archive.ubuntu.com/ubuntu jammy/main amd64 libp11-kit0 amd64 0.24.0-6build1 [252 kB]
获取:53 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libtasn1-6 amd64 4.18.0-4ubuntu0.2 [43.6 kB]
获取:54 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libgnutls30 amd64 3.7.3-4ubuntu1.9 [971 kB]
获取:55 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libip4tc2 amd64 1.8.7-1ubuntu5.2 [19.9 kB]
获取:56 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libkmod2 amd64 29-1ubuntu1.1 [48.1 kB]
获取:57 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libseccomp2 amd64 2.5.3-2ubuntu3~22.04.1 [47.4 kB]
获取:58 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 systemd amd64 249.11-0ubuntu3.22 [4,587 kB]
获取:59 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 systemd-sysv amd64 249.11-0ubuntu3.22 [10.5 kB]
获取:60 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libavahi-common-data amd64 0.8-5ubuntu5.5 [24.0 kB]
获取:61 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libavahi-common3 amd64 0.8-5ubuntu5.5 [23.9 kB]
获取:62 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libavahi-core7 amd64 0.8-5ubuntu5.5 [91.5 kB]
获取:63 http://archive.ubuntu.com/ubuntu jammy/main amd64 libdaemon0 amd64 0.14-7.1ubuntu3 [14.1 kB]
获取:64 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libdbus-1-3 amd64 1.12.20-2ubuntu4.1 [189 kB]
获取:65 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 libexpat1 amd64 2.4.7-1ubuntu0.7 [92.1 kB]
获取:66 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 dbus amd64 1.12.20-2ubuntu4.1 [158 kB]
获取:67 http://archive.ubuntu.com/ubuntu jammy-updates/main amd64 avahi-daemon amd64 0.8-5ubuntu5.5 [69.7 kB]
