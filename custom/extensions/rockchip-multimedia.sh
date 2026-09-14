#!/usr/bin/env bash
#
# custom/extensions/rockchip-multimedia.sh
#
# Rockchip RK3568 multimedia userspace for the z96a image. The kernel side is
# already complete (linux-rockchip-rk3568-z96a-legacy config has these =y):
#
#   component    userspace                  device node       kernel driver
#   -----------  -------------------------  ----------------  --------------------------
#   MPP (VPU)    librockchip-mpp.so.1       /dev/mpp_service  CONFIG_ROCKCHIP_MPP_*
#   RGA          librga.so (im2d API)       /dev/rga          CONFIG_VIDEO_ROCKCHIP_RGA
#   RKNN (NPU)   librknnrt.so               /dev/dri/renderD* CONFIG_ROCKCHIP_RKNPU (DRM)
#   GLES         Mesa Panfrost (distro)     /dev/dri/*        CONFIG_DRM_PANFROST
#   VA-API       rockchip_drv_video.so      (wraps MPP)       via libva2 -> MPP
#
# The VA-API driver gives Firefox-esr/mpv hardware video decode: libva dlopens
# rockchip_drv_video.so which links librockchip_mpp.so.1 and exports
# __vaDriverInit_1_17 (matches bookworm's libva 2.17, whose libva.pc reports
# VA-API Version: 1.17.0). Firefox prefs + LIBVA_DRIVER_NAME=rockchip are
# preseeded in the image.
#
# Vulkan is intentionally NOT provided: the G52 (Bifrost) is driven by Mesa
# Panfrost, and bookworm's Mesa (22.3) has no panvk Vulkan support for v9.
# panvk needs Mesa >= 24.2 (trixie/sid userspace). The old plan of injecting
# the proprietary libmali blob is dead: it needs CONFIG_MALI_BIFROST, which
# conflicts with Panfrost, and the blob in custom/blobs has no Vulkan symbols.
#
# Everything lands in the multiarch lib dir with headers + pkg-config files so
# applications can compile against MPP/RGA/RKNN on-device.
#
# Enable: ENABLE_EXTENSIONS="rockchip-multimedia" (set by custom/config/boards/z96a-v2.conf)

# Pinned upstream refs, fetched by full SHA so builds are reproducible:
#   rockchip-linux/mpp        develop 0986d01294d5c2449c14cf13af9b740368c33967 (2026-08-26)
#   airockchip/librga         main    2b32edcb97b601b25683e2941d888c8515da6d55 (2026-06-10, 1.10.6_[3])
#   airockchip/rknn-toolkit2  tag v2.3.2
#   intel/libva               tag 2.17.0 b431a1a94f5e1f060f2ea2cf3169024830b7d0b1 (headers only)
#   tarcila/libva-rkmpp       master  e69ea1368893cc15c8d59618397ab8d78df648b9 (2024-10-16)
declare -g EXT_RKMPP_GIT="https://github.com/rockchip-linux/mpp.git"
declare -g EXT_RKMPP_REF="0986d01294d5c2449c14cf13af9b740368c33967"
declare -g EXT_LIBRGA_GIT="https://github.com/airockchip/librga.git"
declare -g EXT_LIBRGA_REF="2b32edcb97b601b25683e2941d888c8515da6d55"
declare -g EXT_RKNN_VERSION="2.3.2"
declare -g EXT_RKNN_BASE="https://raw.githubusercontent.com/airockchip/rknn-toolkit2/v${EXT_RKNN_VERSION}/rknpu2/runtime/Linux/librknn_api"
declare -g EXT_LIBVA_GIT="https://github.com/intel/libva.git"
declare -g EXT_LIBVA_REF="2.17.0"
declare -g EXT_VADRV_GIT="https://github.com/tarcila/libva-rkmpp.git"
declare -g EXT_VADRV_REF="e69ea1368893cc15c8d59618397ab8d78df648b9"
declare -g EXT_MOONLIGHT_URL="https://github.com/jinyayayaya/armbian-build-sunniwell-Z96a/releases/download/26.5.1/z96a-moonlight-rkmpp.tar.gz"
declare -g EXT_RUSTDESK_URL="https://github.com/jinyayayaya/armbian-build-sunniwell-Z96a/releases/download/26.5.1/rustdesk-1.4.9-rk3568-arm64.deb"
declare -g EXT_CHROMIUM_ASSET_BASE="https://github.com/jinyayayaya/armbian-build-sunniwell-Z96a/releases/download/26.5.1"
# This is the AArch64 bundle already verified on the Z96A. Keep both the
# release and digest fixed so image builds do not depend on a mutable asset.
declare -g EXT_MPV_RKMPP_VERSION="26.5.2"
declare -g EXT_MPV_RKMPP_URL="https://github.com/jinyayayaya/armbian-build-sunniwell-Z96a/releases/download/${EXT_MPV_RKMPP_VERSION}/z96a-mpv-rkmpp.tar.gz"
declare -g EXT_MPV_RKMPP_SHA256="0a492aedafb6e8349ed92e0a06071457cd97e8eb27a8b869f4eac0018e99a588"

# Rockchip Chromium 111 is paired with libv4l-rkmpp 1.7.0. These packages are
# published as release assets instead of being checked into the repository.
declare -g EXT_CHROMIUM_DEB_MANIFEST=(
	"librockchip-mpp1-dummy.deb|e8ba1de2418bbe32d882bc53936f7a0034d8e6bde5d72d38c2a5528872efe50c"
	"libv4lconvert0_1.22.1-5_arm64.deb|5bf2872bcca7016a84d114776ab4a18218c62e249da526a614583c1cacb637c5"
	"libv4l-0_1.22.1-5_arm64.deb|b984dd5a50622f13aafcaef3c9e63a01136734380592c5a8015dfc82453b4391"
	"libv4l-rkmpp_1.7.0-1_arm64.deb|7a2cb60c87d5625f53aa4903781aaa559534ea49a09ebdf554446e3a3bc55823"
	"rockchip-chromium-x11-utils_0.2.3_all.deb|ca7f722a41ae4271230062c55a382e459979e23636f7dda9ce44b742bcf42c3b"
	"chromium-x11_111.0.5563.147_arm64.deb|8ecbdbd8233414c632d3e77e80cf940d2625c4f7c8a2c4d9faf1366a738a6979"
)

# Fetch `repo_url` at pinned `sha` into `dest_dir` (idempotent).
function _rockchip_multimedia_fetch_pinned() {
	local repo_url="${1}" sha="${2}" dest_dir="${3}"
	if [[ ! -d "${dest_dir}/.git" ]]; then
		run_host_command_logged git init "${dest_dir}"
		run_host_command_logged git -C "${dest_dir}" remote add origin "${repo_url}"
	fi
	# GitHub enables allow-reachable-SHA-in-want, so depth-1 fetch by sha works.
	run_host_command_logged git -C "${dest_dir}" fetch --depth 1 origin "${sha}"
	run_host_command_logged git -C "${dest_dir}" checkout --detach FETCH_HEAD
	return 0
}

# Download a release asset only when it is absent or fails its pinned hash.
function _rockchip_multimedia_fetch_verified() {
	local url="${1}" sha256="${2}" destination="${3}"
	if [[ -f "${destination}" ]] && printf '%s  %s\n' "${sha256}" "${destination}" | sha256sum -c - >/dev/null 2>&1; then
		return 0
	fi

	rm -f "${destination}"
	run_host_command_logged curl -fL --retry 3 -o "${destination}" "${url}"
	if ! printf '%s  %s\n' "${sha256}" "${destination}" | sha256sum -c -; then
		exit_with_error "rockchip-multimedia: checksum verification failed for ${url}"
	fi
}

function _rockchip_multimedia_patch_chromium_wrapper() {
	local wrapper="${1}"
	[[ -f "${wrapper}" ]] || exit_with_error "rockchip-multimedia: Chromium wrapper is missing: ${wrapper}"
	command -v python3 >/dev/null 2>&1 || exit_with_error "rockchip-multimedia: host python3 is required to patch Chromium wrapper"

	python3 - "${wrapper}" <<-'PY_PATCH_CHROMIUM_WRAPPER'
		from pathlib import Path
		import sys

		path = Path(sys.argv[1])
		text = path.read_text()
		marker_begin = "# Z96A_CHROMIUM_CONFIG_BEGIN"
		marker_end = "# Z96A_CHROMIUM_CONFIG_END"
		old_exec = 'exec -a "$0" "$HERE/chromium-bin" ${CHROME_EXTRA_ARGS} "$@"'
		new_exec = 'exec -a "$0" "$HERE/chromium-bin" ${CHROME_EXTRA_ARGS} ${CHROMIUM_FLAGS} "$@"'
		config_hook = '''# Z96A_CHROMIUM_CONFIG_BEGIN
		CHROMIUM_FLAGS="${CHROMIUM_FLAGS:-}"
		if [ -d /etc/chromium.d ]; then
		  for config in /etc/chromium.d/*; do
		    [ -f "$config" ] && . "$config"
		  done
		fi
		# Z96A_CHROMIUM_CONFIG_END'''

		if marker_begin in text:
		    start = text.index(marker_begin)
		    end = text.index(marker_end, start) + len(marker_end)
		    text = text[:start] + config_hook + text[end:]
		    if new_exec not in text and old_exec in text:
		        text = text.replace(old_exec, new_exec, 1)
		elif old_exec in text:
		    text = text.replace(old_exec, config_hook + "\n" + new_exec, 1)
		else:
		    raise SystemExit("unsupported Chromium wrapper: final exec line not found")

		path.write_text(text)
	PY_PATCH_CHROMIUM_WRAPPER
	chmod 0755 "${wrapper}"
}

# Build host: cross toolchain + build systems for MPP and the VA-API driver.
function add_host_dependencies__rockchip_multimedia_host_deps() {
	declare -g EXTRA_BUILD_DEPS="${EXTRA_BUILD_DEPS} gcc-aarch64-linux-gnu g++-aarch64-linux-gnu cmake ninja-build autoconf automake libtool pkg-config"
}

function post_family_config__rockchip_multimedia_gles_packages() {
	[[ "${BOARDFAMILY:-}" != "rockchip-rk3568-z96a" ]] && return 0
	display_alert "rockchip-multimedia" "adding Mesa GLES userspace packages" "info"
	# Mesa Panfrost provides EGL/GLES3.1; libgl1-mesa-dri ships the gallium drivers.
	# libva2/libva-drm2 runtime + vainfo for the VA-API->MPP decode path.
	# mpv itself is the pinned RKMPP bundle installed below, not Debian's mpv.
	add_packages_to_image \
		libasound2 libass9 libdrm2 libegl1 libfontconfig1 libfreetype6 libgbm1 \
		libgl1 libgles2 libpulse0 libva2 libva-drm2 libx11-6 libxcb1 libxext6 \
		libxfixes3 libxpresent1 libxrandr2 libxss1 libxv1 libfribidi0 \
		libharfbuzz0b libglib2.0-0 libgcc-s1 libstdc++6 libxrender1 \
		libgl1-mesa-dri vainfo
	if [[ "${BUILD_MINIMAL:-}" != "yes" ]]; then
		add_packages_to_image glmark2-es2 # on-device GLES sanity check
	fi
	if [[ "${BUILD_DESKTOP:-}" == "yes" ]]; then
		# Moonlight Qt6 runtime + SDL2 + Opus + VA-API helpers
		add_packages_to_image libsdl2-2.0-0 libsdl2-ttf-2.0-0 libopus0 libva-x11-2 libva-wayland2 \
			qml6-module-qtquick qml6-module-qtquick-controls qml6-module-qtquick-layouts \
			qml6-module-qtquick-templates qml6-module-qtquick-window qml6-module-qtqml-workerscript \
			qt6-qpa-plugins libqt6svg6
		# Samba/CIFS network share browsing and streaming
		add_packages_to_image gvfs gvfs-backends gvfs-fuse cifs-utils smbclient libsmbclient
		# RustDesk remote desktop dependencies
		add_packages_to_image libxdo3 libayatana-appindicator3-1 gstreamer1.0-pipewire
	fi
	return 0
}

# Resolve the aarch64 cross-compiler prefix. Prefer the framework's own
# toolchain (CROSS_COMPILE, possibly "ccache /path/prefix-"); fall back to the
# apt-installed debian cross gcc, which add_host_dependencies guarantees.
function _rockchip_multimedia_cross_prefix() {
	local prefix="${CROSS_COMPILE:-aarch64-linux-gnu-}"
	prefix="${prefix##* }" # drop "ccache " style prefixes
	if [[ -z "${prefix}" ]] || ! type -p "${prefix}gcc" > /dev/null 2>&1; then
		prefix="aarch64-linux-gnu-"
	fi
	echo "${prefix}"
	return 0
}

function pre_customize_image__rockchip_multimedia_install() {
	[[ "${BOARDFAMILY:-}" != "rockchip-rk3568-z96a" ]] && return 0
	[[ "${RELEASE:-}" == "bookworm" ]] || exit_with_error \
		"rockchip-multimedia: pinned RKMPP mpv bundle requires Debian bookworm"

	local lib_dir="usr/lib/aarch64-linux-gnu"
	local work_dir="${SRC}/output/rockchip-multimedia"
	local src_dir="${work_dir}/src"
	local stage="${work_dir}/stage"
	local prefix cross

	prefix="$( _rockchip_multimedia_cross_prefix )"
	cross="aarch64-linux-gnu" # multiarch triplet for the target libs

	display_alert "rockchip-multimedia" "installing MPP/RGA/RKNN userspace (cross prefix: ${prefix})" "info"
	mkdir -p "${stage}/${lib_dir}" "${stage}/usr/include" "${src_dir}"

	# ------------------------------------------------------- Chromium + V4L2/MPP --
	# The Debian Chromium build is not compatible with the Rockchip V4L2 bridge.
	# Install the tested X11 build and its matching libv4l-rkmpp plugin only for
	# desktop images. Release assets are hash-pinned so a mutable download cannot
	# silently change the image contents.
	if [[ "${BUILD_DESKTOP:-}" == "yes" ]]; then
		[[ "${RELEASE:-}" == "bookworm" ]] || exit_with_error \
			"rockchip-multimedia: Rockchip Chromium assets require Debian bookworm"
		local chromium_deb_dir="${work_dir}/chromium"
		local chromium_manifest chromium_name chromium_sha chromium_deb
		mkdir -p "${chromium_deb_dir}"

		for chromium_manifest in "${EXT_CHROMIUM_DEB_MANIFEST[@]}"; do
			IFS='|' read -r chromium_name chromium_sha <<< "${chromium_manifest}"
			chromium_deb="${chromium_deb_dir}/${chromium_name}"
			_rockchip_multimedia_fetch_verified \
				"${EXT_CHROMIUM_ASSET_BASE}/${chromium_name}" \
				"${chromium_sha}" "${chromium_deb}"
		done

		# These dependencies are not pulled by the old Debian Chromium package
		# metadata but are required by the Rockchip build at runtime.
		chroot_sdcard apt-get update -o Acquire::Check-Valid-Until=false
		chroot_sdcard apt-get install -y --no-install-recommends \
			libc++1 libgdk-pixbuf2.0-bin libjsoncpp25

		# chromium-x11 declares Conflicts against all Debian Chromium package
		# names. Purge any package inherited from a desktop base image first.
		for chromium_package in chromium chromium-common chromium-sandbox chromium-l10n chromium-browser chromium-browser-l10n chromium-codecs-ffmpeg-extra; do
			if chroot_sdcard dpkg-query -W -f='${Status}' "${chromium_package}" 2>/dev/null | grep -qx 'install ok installed'; then
				chroot_sdcard apt-get purge -y "${chromium_package}"
			fi
		done

		# Install the dummy dependency before libv4l-rkmpp. It intentionally does
		# not ship a library: the board's MPP extension installs the newer library.
		local chromium_install_order=(
			"librockchip-mpp1-dummy.deb"
			"libv4lconvert0_1.22.1-5_arm64.deb"
			"libv4l-0_1.22.1-5_arm64.deb"
			"libv4l-rkmpp_1.7.0-1_arm64.deb"
			"rockchip-chromium-x11-utils_0.2.3_all.deb"
			"chromium-x11_111.0.5563.147_arm64.deb"
		)
		for chromium_name in "${chromium_install_order[@]}"; do
			install_deb_chroot "${chromium_deb_dir}/${chromium_name}"
		done

		mkdir -p "${SDCARD}/etc/chromium.d" "${SDCARD}/usr/lib/libv4l"
		cat > "${SDCARD}/etc/chromium.d/panfrost" <<-'EOF'
			# RK3568 Chromium: native EGL is required by the V4L2/MPP video path.
			export CHROMIUM_FLAGS="$CHROMIUM_FLAGS \
			  --use-gl=egl \
			  --ignore-gpu-blocklist \
			  --enable-gpu-rasterization \
			  --enable-zero-copy \
			  --disable-features=Translate,OptimizationHints \
			  --disable-sync \
			  --disable-background-networking \
			  --disable-component-update \
			  --disable-domain-reliability \
			  --disable-breakpad \
			  --disable-crash-reporter \
			  --process-per-site \
			  --no-first-run \
			  --no-default-browser-check \
			  --disk-cache-size=104857600 \
			  --media-cache-size=104857600"
		EOF
		chmod 0644 "${SDCARD}/etc/chromium.d/panfrost"

		# chromium-bin looks for libv4l2.so and the plugin in legacy paths.
		ln -sfn /usr/lib/aarch64-linux-gnu/libv4l/plugins "${SDCARD}/usr/lib/libv4l/plugins"
		ln -sfnT lib "${SDCARD}/usr/lib64"
		_rockchip_multimedia_patch_chromium_wrapper "${SDCARD}/usr/lib/chromium/chromium-wrapper"

		# The package's service creates /dev/video-dec0 and /dev/video-enc0 at
		# graphical.target, where the desktop Chromium process can access them.
		mkdir -p "${SDCARD}/etc/systemd/system/graphical.target.wants"
		ln -sfn /lib/systemd/system/rockchip-chromium-x11-utils.service \
			"${SDCARD}/etc/systemd/system/graphical.target.wants/rockchip-chromium-x11-utils.service"
	fi

	# ------------------------------------------------------------------ MPP --
	# NOTE: upstream develop names the library with an underscore:
	#       librockchip_mpp.so.1 (Debian's packages use a hyphen; this is not Debian).
	if [[ ! -e "${stage}/${lib_dir}/librockchip_mpp.so.1" ]]; then
		_rockchip_multimedia_fetch_pinned "${EXT_RKMPP_GIT}" "${EXT_RKMPP_REF}" "${src_dir}/mpp"
		# Cross toolchain file for cmake; MPP has no external deps beyond libc.
		cat > "${src_dir}/aarch64-cross.cmake" <<- EOT
			set(CMAKE_SYSTEM_NAME Linux)
			set(CMAKE_SYSTEM_PROCESSOR aarch64)
			set(CMAKE_C_COMPILER "${prefix}gcc")
			set(CMAKE_CXX_COMPILER "${prefix}g++")
			set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
			set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
			set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
			set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
		EOT
		run_host_command_logged cmake -S "${src_dir}/mpp" -B "${src_dir}/mpp/build" -G Ninja \
			"-DCMAKE_TOOLCHAIN_FILE=${src_dir}/aarch64-cross.cmake" \
			"-DCMAKE_BUILD_TYPE=Release" \
			"-DCMAKE_INSTALL_PREFIX=/usr" \
			"-DCMAKE_INSTALL_LIBDIR=${lib_dir#usr/}" \
			"-DCMAKE_INSTALL_INCLUDEDIR=include" \
			"-DBUILD_SHARED_LIBS=ON" \
			"-DBUILD_TEST=ON"
		run_host_command_logged cmake --build "${src_dir}/mpp/build" -j "$(nproc)"
		run_host_command_logged env DESTDIR="${stage}" cmake --install "${src_dir}/mpp/build"
	else
		display_alert "rockchip-multimedia" "MPP already staged, reusing" "debug"
	fi

	# ---------------------------------------------------------------- librga --
	# The librga core is only buildable via AOSP (Android.bp); upstream ships
	# prebuilt aarch64 libs + im2d headers in-repo, which is what we stage.
	if [[ ! -e "${stage}/${lib_dir}/librga.so" ]]; then
		_rockchip_multimedia_fetch_pinned "${EXT_LIBRGA_GIT}" "${EXT_LIBRGA_REF}" "${src_dir}/librga"
		run_host_command_logged cp -av "${src_dir}/librga/libs/Linux/gcc-aarch64/librga.so" "${stage}/${lib_dir}/"
		run_host_command_logged mkdir -pv "${stage}/usr/include/rga"
		run_host_command_logged cp -av "${src_dir}/librga/include/"*.h "${src_dir}/librga/include/im2d.hpp" "${stage}/usr/include/rga/"
		cat > "${stage}/${lib_dir}/pkgconfig/librga.pc" <<- EOT
			prefix=/usr
			libdir=\${prefix}/lib/${cross}
			includedir=\${prefix}/include

			Name: librga
			Description: Rockchip RGA userspace library (im2d API)
			Version: 1.10.6
			Libs: -L\${libdir} -lrga
			Cflags: -I\${includedir}/rga
		EOT
	else
		display_alert "rockchip-multimedia" "librga already staged, reusing" "debug"
	fi

	# ------------------------------------------------------------------ RKNN --
	if [[ ! -e "${stage}/${lib_dir}/librknnrt.so" ]]; then
		run_host_command_logged mkdir -pv "${stage}/usr/include/rknn"
		run_host_command_logged curl -fL --retry 3 -o "${stage}/${lib_dir}/librknnrt.so" \
			"${EXT_RKNN_BASE}/aarch64/librknnrt.so"
		for rknn_header in rknn_api.h rknn_matmul_api.h rknn_custom_op.h; do
			run_host_command_logged curl -fL --retry 3 -o "${stage}/usr/include/rknn/${rknn_header}" \
				"${EXT_RKNN_BASE}/include/${rknn_header}"
		done
		cat > "${stage}/${lib_dir}/pkgconfig/librknnrt.pc" <<- EOT
			prefix=/usr
			libdir=\${prefix}/lib/${cross}
			includedir=\${prefix}/include

			Name: librknnrt
			Description: Rockchip RKNN runtime (NPU C API)
			Version: ${EXT_RKNN_VERSION}
			Libs: -L\${libdir} -lrknnrt
			Cflags: -I\${includedir}/rknn
		EOT
	else
		display_alert "rockchip-multimedia" "RKNN already staged, reusing" "debug"
	fi

	# ---------------------------------------------------------------- VA-API --
	# rockchip_drv_video.so: VA-API backend wrapping MPP, so Firefox/mpv get
	# hardware video decode. Cross-built with libva 2.17 headers (headers-only,
	# vendored from the tag) because the builder container's distro libva would
	# emit the wrong init-symbol version. Verified in a bookworm container: the
	# result links only librockchip_mpp.so.1 + libc and exports
	# __vaDriverInit_1_17, matching bookworm's libva2 2.17 runtime.
	if [[ ! -e "${stage}/${lib_dir}/dri/rockchip_drv_video.so" ]]; then
		local va_sysroot="${work_dir}/libva-sysroot"
		rm -rf "${va_sysroot}"
		mkdir -p "${va_sysroot}/usr/include" "${va_sysroot}/usr/lib/aarch64-linux-gnu/pkgconfig"
		_rockchip_multimedia_fetch_pinned "${EXT_LIBVA_GIT}" "${EXT_LIBVA_REF}" "${src_dir}/libva"
		# Headers live at the repo root in libva/<va> (not include/va).
		run_host_command_logged cp -a "${src_dir}/libva/va" "${va_sysroot}/usr/include/"
		# The git tag ships only the va_version.h.in template; distro libva-dev
		# packages ship it pre-generated. Generate it for VA-API 1.17.0 (= libva
		# 2.17.0), matching the .pc Version below - rockchip_drv_video.c includes
		# <va/va_version.h> (via va.h) and the build fails without it.
		sed -e 's/@VA_API_MAJOR_VERSION@/1/' \
			-e 's/@VA_API_MINOR_VERSION@/17/' \
			-e 's/@VA_API_MICRO_VERSION@/0/' \
			-e 's/@VA_API_VERSION@/1.17.0/' \
			"${src_dir}/libva/va/va_version.h.in" > "${va_sysroot}/usr/include/va/va_version.h"
		# Replicate bookworm's libva.pc: Version is the VA-API version (1.17.0),
		# NOT the libva release version (2.17.0) - configure derives the
		# __vaDriverInit_<maj>_<min> symbol from this field.
		cat > "${va_sysroot}/usr/lib/aarch64-linux-gnu/pkgconfig/libva.pc" <<- EOT
			prefix=/usr
			exec_prefix=\${prefix}
			libdir=\${prefix}/lib/aarch64-linux-gnu
			includedir=\${prefix}/include
			driverdir=\${prefix}/lib/aarch64-linux-gnu/dri

			Name: libva
			Description: Userspace Video Acceleration (VA) core interface
			Version: 1.17.0
			Libs: -L\${libdir} -lva
			Cflags: -I\${includedir}
		EOT

		_rockchip_multimedia_fetch_pinned "${EXT_VADRV_GIT}" "${EXT_VADRV_REF}" "${src_dir}/libva-rkmpp"
		# autogen.sh runs `autoreconf -v --install` then `./configure "$@"`,
		# so flags must be passed positionally. Both of those are relative to
		# the source dir (autoreconf looks for configure.ac in $PWD, configure
		# is generated and run in-place), so cd into the source tree first -
		# calling autogen.sh by absolute path from the framework root CWD fails
		# with "autoreconf: error: 'configure.ac' is required" and Error 127.
		# Pass pkg-config + sysroot include (matches the libc/libdrm + VA
		# headers we vendored) and a sysroot library lookup so the driver
		# links librockchip_mpp.so.1 from the stage dir (already cross-built
		# above).
		# LIBS must NOT be forced here: configure's "compiler creates
		# executables" sanity check links a test binary and would try to link
		# -lrockchip_mpp against a lib dir that is still empty at that point,
		# failing with "C compiler cannot create executables" (Error 77, run
		# 34563571369). libtool picks -lrockchip_mpp up from the driver's own
		# Makefile.am at make time, with LDFLAGS pointing at the stage dir.
		run_host_command_logged cd "${src_dir}/libva-rkmpp" "&&" \
			env -u PKG_CONFIG_PATH PKG_CONFIG_PATH="${va_sysroot}/usr/lib/aarch64-linux-gnu/pkgconfig" \
			./autogen.sh \
				--host=aarch64-linux-gnu \
				--prefix=/usr \
				--with-drivers-path="/usr/${lib_dir#usr/}/dri" \
				CPPFLAGS="-I${va_sysroot}/usr/include" \
				LDFLAGS="-L${stage}/${lib_dir}" \
				ac_cv_func_malloc_0_nonnull=yes ac_cv_func_realloc_0_nonnull=yes
		run_host_command_logged make -C "${src_dir}/libva-rkmpp" -j "$(nproc)"
		run_host_command_logged mkdir -pv "${stage}/${lib_dir}/dri"
		run_host_command_logged cp -av "${src_dir}/libva-rkmpp/src/.libs/rockchip_drv_video.so" "${stage}/${lib_dir}/dri/"
	else
		display_alert "rockchip-multimedia" "VA-API driver already staged, reusing" "debug"
	fi

	# --------------------------------------------- Moonlight + FFmpeg Rockchip --
	if [[ ! -e "${stage}/usr/local/bin/moonlight" ]]; then
		display_alert "rockchip-multimedia" "fetching and staging Moonlight-Qt + ffmpeg-rockchip" "info"
		local ml_tar="${work_dir}/z96a-moonlight-rkmpp.tar.gz"
		run_host_command_logged curl -fL --retry 3 -o "${ml_tar}" "${EXT_MOONLIGHT_URL}"
		run_host_command_logged tar -zxvf "${ml_tar}" -C "${stage}/"
	else
		display_alert "rockchip-multimedia" "Moonlight already staged, reusing" "debug"
	fi

	# -------------------------------------------------------- RKMPP mpv bundle --
	# The bundle was built and tested separately on AArch64. Downloading it here
	# keeps normal image builds fast and avoids rebuilding FFmpeg/mpv under QEMU.
	local mpv_tar="${work_dir}/z96a-mpv-rkmpp.tar.gz"
	local mpv_root="${SDCARD}/opt/z96a-mpv-rkmpp"
	display_alert "rockchip-multimedia" "fetching pinned RKMPP mpv ${EXT_MPV_RKMPP_VERSION}" "info"
	_rockchip_multimedia_fetch_verified \
		"${EXT_MPV_RKMPP_URL}" \
		"${EXT_MPV_RKMPP_SHA256}" \
		"${mpv_tar}"
	run_host_command_logged rm -rf "${mpv_root}"
	run_host_command_logged mkdir -p "${SDCARD}/opt"
	run_host_command_logged tar --no-same-owner --no-same-permissions -xzf "${mpv_tar}" -C "${SDCARD}/opt"
	if [[ ! -x "${mpv_root}/bin/mpv" || ! -f "${mpv_root}/config/mpv.conf" ]]; then
		exit_with_error "rockchip-multimedia: downloaded RKMPP mpv bundle is incomplete"
	fi

	# Remove any distro mpv that may have entered the rootfs through a desktop
	# app group. The image must not retain the old software-decoder binary.
	chroot_sdcard apt-get purge -y mpv >/dev/null 2>&1 || true
	run_host_command_logged rm -f \
		"${SDCARD}/usr/bin/mpv.real" \
		"${SDCARD}/usr/local/bin/mpv.bin" \
		"${SDCARD}/etc/mpv/mpv.conf"

	# Reuse the bundle's desktop entry and icons; Exec=mpv resolves to the SMB
	# wrapper installed by the board hook below.
	if [[ -f "${mpv_root}/share/applications/mpv.desktop" ]]; then
		run_host_command_logged mkdir -p "${SDCARD}/usr/share/applications"
		run_host_command_logged cp -a "${mpv_root}/share/applications/mpv.desktop" "${SDCARD}/usr/share/applications/"
	fi
	if [[ -d "${mpv_root}/share/icons/hicolor" ]]; then
		run_host_command_logged mkdir -p "${SDCARD}/usr/share/icons/hicolor"
		run_host_command_logged cp -a "${mpv_root}/share/icons/hicolor/." "${SDCARD}/usr/share/icons/hicolor/"
	fi

	# --------------------------------------------- RustDesk (RKMPP accelerated) --
	if [[ "${BUILD_DESKTOP:-}" == "yes" && ! -e "${SDCARD}/usr/share/rustdesk/rustdesk" ]]; then
		display_alert "rockchip-multimedia" "fetching and installing RustDesk RKMPP" "info"
		local rd_deb="${work_dir}/rustdesk-1.4.9-rk3568-arm64.deb"
		run_host_command_logged curl -fL --retry 3 -o "${rd_deb}" "${EXT_RUSTDESK_URL}"
		install_deb_chroot "${rd_deb}"
		# In chroot environments, /proc/1/exe is not systemd, so rustdesk.postinst
		# skips copying the service file and creating /usr/bin/rustdesk symlink.
		if [[ -f "${SDCARD}/usr/share/rustdesk/files/systemd/rustdesk.service" ]]; then
			mkdir -p "${SDCARD}/usr/lib/systemd/system"
			cp -f "${SDCARD}/usr/share/rustdesk/files/systemd/rustdesk.service" "${SDCARD}/usr/lib/systemd/system/rustdesk.service"
			# RustDesk is available on demand but must not start automatically.
			chroot_sdcard systemctl disable rustdesk 2>/dev/null || true
			for target in multi-user graphical default; do
				rm -f "${SDCARD}/etc/systemd/system/${target}.target.wants/rustdesk.service"
			done
		fi
		if [[ ! -e "${SDCARD}/usr/bin/rustdesk" && ! -L "${SDCARD}/usr/bin/rustdesk" ]]; then
			ln -sf /usr/share/rustdesk/rustdesk "${SDCARD}/usr/bin/rustdesk"
		fi
	fi

	# --------------------------------------------- udev rules + copy to rootfs --
	cat > "${SDCARD}/etc/udev/rules.d/60-rockchip-multimedia.rules" <<- 'EOF'
		# Rockchip multimedia accelerators: allow the 'video' group.
		# /dev/mpp_service - VPU via MPP   /dev/rga - 2D blitter   /dev/rknpu - NPU
		KERNEL=="mpp_service", MODE="0660", GROUP="video"
		KERNEL=="rga",         MODE="0660", GROUP="video"
		KERNEL=="rknpu",       MODE="0660", GROUP="video"
	EOF

	# Point libva at the rockchip backend + relax the RDD sandbox that blocks
	# VAAPI in Firefox on this stack. /etc/environment covers display-manager
	# sessions; /etc/profile.d covers shell logins.
	cat > "${SDCARD}/etc/profile.d/rockchip-vaapi.sh" <<- 'EOF'
		export LIBVA_DRIVER_NAME=rockchip
		export MOZ_DISABLE_RDD_SANDBOX=1
	EOF
	chmod 0755 "${SDCARD}/etc/profile.d/rockchip-vaapi.sh"
	if ! grep -q "^LIBVA_DRIVER_NAME=" "${SDCARD}/etc/environment" 2>/dev/null; then
		echo 'LIBVA_DRIVER_NAME=rockchip' >> "${SDCARD}/etc/environment"
		echo 'MOZ_DISABLE_RDD_SANDBOX=1' >> "${SDCARD}/etc/environment"
	fi

	# Firefox-esr prefs (only when firefox-esr is present in this image).
	local ff_pref_dir="${SDCARD}/usr/lib/firefox-esr/defaults/pref"
	if [[ -d "${SDCARD}/usr/lib/firefox-esr" ]]; then
		mkdir -p "${ff_pref_dir}"
		cat > "${ff_pref_dir}/rockchip-vaapi.js" <<- 'EOF'
			// Hardware video decode via VA-API -> rockchip(MPP). Set by the
			// rockchip-multimedia build extension.
			pref("media.ffmpeg.vaapi.enabled", true);
			pref("media.hardware-video-decoding.force-enabled", true);
			pref("media.rdd-ffmpeg.enabled", true);
			pref("media.av1.enabled", false); // RK3568 has no AV1 decoder; avoid sw-AV1 on youtube
		EOF
	else
		display_alert "rockchip-multimedia" "firefox-esr not in image, skipping browser prefs" "info"
	fi

	display_alert "rockchip-multimedia" "copying staged userspace into rootfs" "info"
	# Debian bookworm images use merged-/usr, where /lib is a symlink to
	# /usr/lib. Copying the staged top-level directory in one operation makes
	# cp try to replace that symlink with the Moonlight archive's lib directory.
	# Merge lib's contents into the symlink target instead, while retaining the
	# old destination for non-merged-/usr rootfs layouts.
	if [[ -d "${stage}/lib" ]]; then
		local lib_target="${SDCARD}/lib"
		if [[ -L "${SDCARD}/lib" ]]; then
			lib_target="${SDCARD}/usr/lib"
		fi
		run_host_command_logged mkdir -p "${lib_target}"
		run_host_command_logged cp -av "${stage}/lib/." "${lib_target}/"
	fi

	local staged_path staged_name
	for staged_path in "${stage}"/*; do
		[[ -e "${staged_path}" || -L "${staged_path}" ]] || continue
		staged_name=${staged_path##*/}
		[[ "${staged_name}" = lib ]] && continue
		run_host_command_logged cp -av "${staged_path}" "${SDCARD}/"
	done
	chroot_sdcard ldconfig

	return 0
}

# Fail the build loudly if anything is missing - replaces the old "set +e and
# hope" GH-action approach that silently produced broken images.
function pre_umount_final_image__rockchip_multimedia_verify() {
	[[ "${BOARDFAMILY:-}" != "rockchip-rk3568-z96a" ]] && return 0

	local lib_dir="usr/lib/aarch64-linux-gnu"
	local f
	for f in \
		"${lib_dir}/librockchip_mpp.so.1" \
		"${lib_dir}/librga.so" \
		"${lib_dir}/librknnrt.so" \
		"${lib_dir}/pkgconfig/rockchip_mpp.pc" \
		"${lib_dir}/pkgconfig/librga.pc" \
		"${lib_dir}/pkgconfig/librknnrt.pc" \
		"usr/include/rockchip/rk_mpi.h" \
		"usr/include/rga/im2d.h" \
		"usr/include/rknn/rknn_api.h" \
		"${lib_dir}/dri/rockchip_drv_video.so" \
		"etc/udev/rules.d/60-rockchip-multimedia.rules" \
		"etc/profile.d/rockchip-vaapi.sh" \
		"opt/z96a-mpv-rkmpp/bin/mpv" \
		"opt/z96a-mpv-rkmpp/bin/mpv.bin" \
		"opt/z96a-mpv-rkmpp/config/mpv.conf" \
		"opt/z96a-mpv-rkmpp/share/build-manifest.txt" \
		"usr/local/bin/mpv" \
		"usr/bin/mpv" \
		"usr/local/bin/moonlight" \
		"usr/local/bin/moonlight-qt-wrapper" \
		"opt/ffmpeg-rockchip/lib/libavcodec.so.60" \
		"etc/ld.so.conf.d/00-ffmpeg-rockchip.conf"; do
		if [[ ! -e "${SDCARD}/${f}" && ! -L "${SDCARD}/${f}" ]]; then
			exit_with_error "rockchip-multimedia: expected file missing from rootfs: /${f}"
		fi
	done
	if [[ -e "${SDCARD}/usr/bin/mpv.real" || -e "${SDCARD}/usr/local/bin/mpv.bin" || -e "${SDCARD}/etc/mpv/mpv.conf" ]]; then
		exit_with_error "rockchip-multimedia: obsolete Debian mpv files remain in rootfs"
	fi

	if [[ "${BUILD_DESKTOP:-}" == "yes" ]]; then
		for f in \
			"usr/bin/chromium" \
			"usr/lib/chromium/chromium-wrapper" \
			"etc/chromium.d/panfrost" \
			"usr/lib/aarch64-linux-gnu/libv4l/plugins/libv4l-rkmpp.so" \
			"lib/systemd/system/rockchip-chromium-x11-utils.service"; do
			if [[ ! -e "${SDCARD}/${f}" && ! -L "${SDCARD}/${f}" ]]; then
				exit_with_error "rockchip-multimedia: expected Chromium file missing from rootfs: /${f}"
			fi
		done
		if ! grep -Fq -- '--use-gl=egl' "${SDCARD}/etc/chromium.d/panfrost" || \
			grep -Fq -- '--use-gl=angle' "${SDCARD}/etc/chromium.d/panfrost"; then
			exit_with_error "rockchip-multimedia: Chromium must use native EGL, not ANGLE"
		fi
		if ! grep -Fq -- '# Z96A_CHROMIUM_CONFIG_BEGIN' "${SDCARD}/usr/lib/chromium/chromium-wrapper" || \
			! grep -Fq -- '${CHROMIUM_FLAGS}' "${SDCARD}/usr/lib/chromium/chromium-wrapper"; then
			exit_with_error "rockchip-multimedia: Chromium wrapper does not load /etc/chromium.d"
		fi
		for f in "usr/share/rustdesk/rustdesk" "usr/share/rustdesk/lib/librustdesk.so"; do
			if [[ ! -e "${SDCARD}/${f}" && ! -L "${SDCARD}/${f}" ]]; then
				exit_with_error "rockchip-multimedia: expected file missing from rootfs: /${f}"
			fi
		done
		# usr/bin/rustdesk is a symlink to /usr/share/rustdesk/rustdesk
		if [[ ! -e "${SDCARD}/usr/bin/rustdesk" && ! -L "${SDCARD}/usr/bin/rustdesk" ]]; then
			exit_with_error "rockchip-multimedia: expected file missing from rootfs: /usr/bin/rustdesk"
		fi
	fi

	display_alert "rockchip-multimedia" "verified: MPP + librga + RKNN + GLES + VA-API + Moonlight (RKMPP) + mpv + RustDesk installed" "info"
	display_alert "rockchip-multimedia" "on-device checks: vainfo, mpi_dec_test, glmark2-es2; firefox about:support should show HW decode" "info"
	return 0
}
