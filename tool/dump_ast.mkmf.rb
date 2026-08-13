#!ruby -s
require 'mkmf'
require 'pathname'
require 'fileutils'

workdir, src, *objs = ARGV
src = Pathname(src)
tooldir = src.parent.relative_path_from(workdir)
srcdir = tooldir.parent
target = src.basename.sub_ext('')
dirs = objs.map {|obj| File.dirname(obj)}.uniq - %w[.]
link = MakeMakefile::TRY_LINK.sub(MakeMakefile::CONFTEST+$EXEEXT, '$(@)')
prismdir= "$(srcdir)/#{dirs.first}"
$VPATH = ["$(srcdir)", "$(srcdir)/#{tooldir.basename}", prismdir, tooldir]
$INCFLAGS << " -I#{prismdir}"
$CPPFLAGS = $CFLAGS = $INCFLAGS
if $objext && $OBJEXT && $objext != $OBJEXT
  ext1, ext2 = ".#{$objext}", ".#{$OBJEXT}"
  objs.each {|obj| obj.chomp!(ext1) << ext2}
end

include FileUtils::Verbose
mkpath(workdir)
Dir.chdir(workdir) {
  mkpath(dirs)
  File.write('Makefile', [MakeMakefile.configuration(srcdir.to_s), <<~MAKEFILE].join(""))
    target = #{target}#{$EXEEXT}
    objs = #{objs.join(' ')}
    Q =
    .SUFFIXES: .c .#{$OBJEXT}

    $(target): $(objs)
    \t$(Q) #{link} $(objs)

    objs: $(objs)
    .c.#{$OBJEXT}:
    \t$(Q) #{MakeMakefile::COMPILE_C}

    clean:
    \t$(Q) $(RM) $(target) $(objs) Makefile
    \t$(Q) $(RMDIRS) #{dirs.join(' ')}
  MAKEFILE
}
