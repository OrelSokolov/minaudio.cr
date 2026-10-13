# Build vendor/miniaudio.h + ext/miniaudio.c into lib/libminaudio.a.
#
#   rake build   # compile the static library
#   rake spec    # headless specs (decoder only; no audio device needed)
#
# After `shards install` into an app, the app's build must run this once
# inside lib/minaudio (see README — "Integrating" section) and add
# -L<shard>/lib to its link flags. The @[Link] attributes in
# src/minaudio/lib.cr carry the platform libs/frameworks.

require "fileutils"

WINDOWS = Gem.win_platform?

OBJ  = WINDOWS ? "ext/miniaudio.obj" : "ext/miniaudio.o"
LIB  = WINDOWS ? "lib/miniaudio.lib" : "lib/libminaudio.a"

def msvc(script)
  vswhere = "C:\\Program Files (x86)\\Microsoft Visual Studio\\Installer\\vswhere.exe"
  vs = %x{"#{vswhere}" -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath}.strip
  vcvars = File.join(vs, "VC", "Auxiliary", "Build", "vcvars64.bat")
  sh %Q{cmd /c ""#{vcvars}" >nul && #{script}"}
end

directory "lib"

file OBJ => ["ext/miniaudio.c", "vendor/miniaudio.h"] do
  if WINDOWS
    # /MD matches Crystal's windows-msvc binaries (dynamic CRT).
    msvc("cl /nologo /O2 /MD /std:c11 /c ext\\miniaudio.c /Fo#{OBJ}")
  else
    sh "cc -O2 -fPIC -c ext/miniaudio.c -o #{OBJ}"
  end
end

file LIB => [OBJ, "lib"] do
  FileUtils.rm_f(LIB)
  if WINDOWS
    msvc("lib /nologo /OUT:#{LIB} #{OBJ}")
  else
    sh "ar rcs #{LIB} #{OBJ}"
  end
end

desc "Compile vendor C into #{LIB}"
task "build" => LIB

# Android cross-build: ext/miniaudio_android.o for the NDK toolchain.
# The object is passed as an extra .o to the app's APK link (egui.cr:
# tmp/android/build_apk.sh) — the @[Link] attributes in lib.cr add
# -laaudio/-lOpenSLES to the Crystal side.
#   ANDROID_NDK=~/Library/Android/sdk/ndk/25.2.9519653 rake build:android
#   API=33 rake build:android   # Android platform level (default 33)
ANDROID_OBJ = "ext/miniaudio_android.o"
task "build:android" do
  api = ENV.fetch("API", "33")
  ndk = ENV["ANDROID_NDK"] || begin
    sdk = ENV["ANDROID_SDK"] ||
      (Dir.exist?(File.expand_path("~/Library/Android/sdk")) ?
        File.expand_path("~/Library/Android/sdk") : File.expand_path("~/android-sdk"))
    Dir[File.join(sdk, "ndk", "*")].sort.last
  end
  abort "no Android NDK found (set ANDROID_NDK)" unless ndk && Dir.exist?(ndk)
  pre = RUBY_PLATFORM.include?("darwin") ? "darwin-x86_64" : "linux-x86_64"
  cc = File.join(ndk, "toolchains", "llvm", "prebuilt", pre, "bin", "clang")
  sh "#{cc} --target=aarch64-linux-android#{api} -O2 -fPIC " \
     "-c ext/miniaudio.c -o #{ANDROID_OBJ}"
  puts "android object: #{ANDROID_OBJ} (pass to build_apk.sh as an extra .o)"
end

# iOS cross-build: ext/miniaudio_ios_sim.o + ext/miniaudio_ios_device.o.
# miniaudio's iOS backend includes AVFoundation headers (Objective-C),
# so the unit compiles as ObjC — like egui.cr's sokol shim. Objects go
# into the app link (egui.cr: tmp/ios build scripts); frameworks
# (CoreAudio/AudioToolbox/CoreFoundation) come from lib.cr's @[Link]
# darwin branch, which applies to the ios target as well.
#   TARGET=sim rake build:ios    # or TARGET=device (both by default)
task "build:ios" do
  # xcrun needs a full Xcode (CommandLineTools alone has no iOS SDKs).
  ENV["DEVELOPER_DIR"] ||= "/Applications/Xcode.app/Contents/Developer"
  targets = { "sim" => ["arm64-apple-ios17.0-simulator", "iphonesimulator",
                        "ext/miniaudio_ios_sim.o"],
              "device" => ["arm64-apple-ios17.0", "iphoneos",
                           "ext/miniaudio_ios_device.o"] }
  selected = ENV["TARGET"] ? {ENV["TARGET"] => targets[ENV["TARGET"]]} : targets
  selected.each do |name, (triple, sdk, obj)|
    sdk_path = %x{xcrun --sdk #{sdk} --show-sdk-path}.strip
    abort "no #{sdk} SDK (installed Xcode?)" if sdk_path.empty?
    sh "cc -O2 -x objective-c -target #{triple} -isysroot #{sdk_path} " \
       "-c ext/miniaudio.c -o #{obj}"
    puts "ios #{name} object: #{obj}"
  end
end

desc "Run the spec suite (headless)"
task :spec => LIB do
  libdir = File.expand_path("lib")
  sh "crystal spec --link-flags \"-L#{libdir}\""
end

task default: [:build]

def sh(cmd)
  puts cmd
  system(cmd) || abort("command failed: #{cmd}")
end
