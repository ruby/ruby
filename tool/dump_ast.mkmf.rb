require 'mkmf'
require 'pathname'
require 'fileutils'

workdir, src, *objs = ARGV
src = Pathname(src)
tooldir = src.parent.relative_path_from(workdir)
srcdir = tooldir.parent
target = Pathname('.').relative_path_from(workdir) + src.basename.sub_ext('')
dirs = objs.map {|obj| File.dirname(obj)}.uniq - %w[.]

include FileUtils::Verbose
mkpath(workdir)
Dir.chdir(workdir) {
  mkpath(dirs)
  prismdir= "$(srcdir)/#{dirs.first}"
  $VPATH = ["$(srcdir)", "$(srcdir)/#{tooldir.basename}", prismdir, tooldir]
  $INCFLAGS << " -I#{prismdir}"
  File.write('Makefile', [MakeMakefile.configuration(srcdir.to_s), <<~MAKEFILE].join(""))
    target = #{target}#{$EXEEXT}
    objs = #{File.basename(target, '.*')}.#{$OBJEXT} #{objs.join(' ')}

    $(target): $(objs)
    \t#{MakeMakefile::TRY_LINK.sub(MakeMakefile::CONFTEST, '$(@)')} $(objs)

    .c.#{$OBJEXT}:
    \t#{MakeMakefile::COMPILE_C}

    clean:
    \t$(RM) $(target) $(objs) Makefile
    \t$(RMDIRS) #{dirs.join(' ')}
  MAKEFILE
}
