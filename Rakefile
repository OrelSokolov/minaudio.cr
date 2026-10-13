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
