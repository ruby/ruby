#!/usr/bin/ruby
# Assemble a relocatable binary package from a staged installation on
# Windows (mswin).  Invoked by the `binary-package` target in
# win32/Makefile.sub; not intended to be run manually.

require 'optparse'
require 'fileutils'

stage = name = arch = srcdir = vcpkgdir = output = nil
opt = OptionParser.new
opt.on('--stage=DIR') {|v| stage = v}
opt.on('--name=NAME') {|v| name = v}
opt.on('--arch=ARCH') {|v| arch = v}
opt.on('--srcdir=DIR') {|v| srcdir = v}
opt.on('--vcpkg-dir=DIR') {|v| vcpkgdir = v}
opt.on('--output=FILE') {|v| output = v}
opt.parse!(ARGV)
abort(opt.to_s) unless stage and name and arch and srcdir and vcpkgdir and output

stage = File.expand_path(stage)
output = File.expand_path(output)

# Find the installed prefix inside the stage.  DESTDIR staging
# reproduces the prefix below the stage directory (with the drive
# letter stripped), so descend while there is a single directory
# until bin/ appears.
root = stage
until File.directory?(File.join(root, "bin"))
  entries = Dir.children(root)
  unless entries.size == 1 and File.directory?(dir = File.join(root, entries[0]))
    abort "#{$0}: could not locate installed prefix under #{stage}"
  end
  root = dir
end
abort "#{$0}: prefix must not be the stage root" if root == stage

bindir = File.join(root, "bin")

# Bundle the vcpkg runtime DLLs next to ruby.exe, where they are
# found first by the DLL search order.
dlls = Dir.glob(File.join(vcpkgdir, "bin", "*.dll"))
dlls.reject! {|f| File.basename(f, ".dll") == "readline"}
abort "#{$0}: no DLLs in #{vcpkgdir}/bin; run `nmake install-vcpkg' first" if dlls.empty?
dlls.each {|f| FileUtils.cp(f, bindir)}

# Bundle the VC runtime (app-local deployment).  UCRT ships with the
# OS since Windows 10, but vcruntime140*.dll does not.
vcruntime = []
if redist = ENV["VCToolsRedistDir"]
  cpu = arch == "i386" ? "x86" : arch
  # backslashes would be glob escapes
  pattern = File.join(redist.tr("\\", "/"), cpu, "Microsoft.VC*.CRT", "vcruntime140*.dll")
  vcruntime = Dir.glob(pattern)
  vcruntime.each {|f| FileUtils.cp(f, bindir)}
end
warn "#{$0}: vcruntime140.dll not bundled; run under vcvars to set VCToolsRedistDir" if vcruntime.empty?

# Collect license terms of everything the package redistributes.
licdir = File.join(root, "LICENSES")
FileUtils.mkdir_p(File.join(licdir, "ruby"))
%w[COPYING COPYING.ja BSDL LEGAL].each do |f|
  src = File.join(srcdir, f)
  FileUtils.cp(src, File.join(licdir, "ruby", f)) if File.exist?(src)
end
Dir.glob(File.join(vcpkgdir, "share", "*", "copyright")) do |f|
  FileUtils.cp(f, File.join(licdir, "#{File.basename(File.dirname(f))}.txt"))
end

# Scrub build-machine specific paths from the recorded configure
# arguments.  mkmf applies $configure_args (notably --with-opt-dir) to
# every extension build, so a leftover absolute path breaks or taints
# gem compilation on the destination machine.
rbconfigs = Dir.glob(File.join(root, "lib/ruby/*/*/rbconfig.rb"))
abort "#{$0}: rbconfig.rb not found under #{root}" if rbconfigs.empty?
rbconfigs.each do |file|
  src = File.binread(file)
  src.sub!(/^(\s*CONFIG\["configure_args"\]\s*=\s*")(.*)(")/) do
    pre, args, post = $1, $2, $3
    kept = args.scan(/\\".*?\\"|\S+/).reject {|t| t.match?(%r{[A-Za-z]:[/\\]})}
    pre + kept.join(" ") + post
  end or abort "#{$0}: configure_args not found in #{file}"
  File.binwrite(file, src)
end

# Rename the prefix directory to the package name and archive it with
# bsdtar, which ships with Windows 10 and later.
pkgdir = File.join(stage, name)
File.rename(root, pkgdir) unless root == pkgdir
FileUtils.rm_f(output)
system("tar", "-a", "-c", "-f", output, "-C", stage, name, exception: true)
puts "packaged #{output}"
