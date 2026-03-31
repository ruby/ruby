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

include FileUtils::Verbose
mkpath(workdir)
Dir.chdir(workdir) {
  mkpath(dirs)
  File.write('Makefile', [MakeMakefile.configuration(srcdir.to_s), <<~MAKEFILE].join(""))
    target = #{target}#{$EXEEXT}
    objs = #{objs.join(' ')}

    $(target): $(objs)
    \t#{link} $(objs)

    objs: $(objs)
    .c.#{$OBJEXT}:
    \t#{MakeMakefile::COMPILE_C}

    clean:
    \t$(RM) $(target) $(objs) Makefile
    \t$(RMDIRS) #{dirs.join(' ')}
  MAKEFILE
}
