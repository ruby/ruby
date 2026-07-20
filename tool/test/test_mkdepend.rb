require 'test/unit'
require 'tmpdir'
require 'stringio'
require_relative '../mkdepend'

class TestMkdepend < Test::Unit::TestCase
  MARK_START = Mkdepend::MARK_START
  MARK_END = Mkdepend::MARK_END

  def mkdepend
    @mkdepend ||= Mkdepend.new
  end

  def test_scanner_follows_all_possible_project_headers
    Dir.mktmpdir('mkdepend-scanner') do |dir|
      File.write(File.join(dir, 'main.c'), <<~C)
        #include "local.h"
        #if FEATURE
        # include "left.h"
        #else
        # include "right.h"
        #endif
        #if 0 && FEATURE
        # include "never.h"
        #endif
        #include GENERATED_HEADER
        #include "generated.rbinc"
        #include "aliased.h"
        #include "path/parse.h"
        #ifdef DISABLED
        # include "never_disabled.h"
        #endif
        #ifndef ENABLED
        # include "never_enabled.h"
        #endif
        #include <external.h>
      C
      File.binwrite(File.join(dir, 'local.h'),
                    "/* \xff */\n#include \"nested.h\"\n".b)
      %w[left.h right.h never.h never_disabled.h never_enabled.h nested.h].each do |header|
        File.write(File.join(dir, header), "")
      end
      File.write(File.join(dir, 'aliased.h.erb'), "#include \"nested.h\"\n")
      Dir.mkdir(File.join(dir, 'path'))
      File.write(File.join(dir, 'path/parse.h'), "#include \"../path_nested.h\"\n")
      File.write(File.join(dir, 'path_nested.h'), "")

      scanner = Mkdepend::Scanner.new(
        root: dir,
        include_dirs: [dir],
        macros: {'GENERATED_HEADER' => 'generated.h'},
        generated: %w[parse.h],
        aliases: {'aliased.h' => 'aliased.h.erb'},
        dependencies: {'generated.h' => %w[virtual.h]},
        defined: %w[ENABLED],
        undefined: %w[DISABLED],
      )

      assert_equal(
        %w[aliased.h generated.rbinc left.h local.h main.c nested.h path/parse.h path_nested.h right.h virtual.h],
        scanner.scan('main.c'),
      )
    end
  end

  def test_scanner_prefers_quoted_path
    Dir.mktmpdir('mkdepend-scanner') do |dir|
      root = File.join(dir, 'src')
      source_dir = File.join(root, 'ext/-test-/float')
      missing_dir = File.join(root, 'missing')
      outer_missing_dir = File.join(dir, 'missing')
      [source_dir, missing_dir, outer_missing_dir].each do |path|
        FileUtils.mkdir_p(path)
      end
      File.write(
        File.join(source_dir, 'nextafter.c'),
        "#include \"../../../missing/nextafter.c\"\n",
      )
      File.write(
        File.join(missing_dir, 'nextafter.c'),
        "#include \"right.h\"\n",
      )
      File.write(File.join(missing_dir, 'right.h'), '')
      File.write(
        File.join(outer_missing_dir, 'nextafter.c'),
        "#include \"wrong.h\"\n",
      )
      File.write(File.join(outer_missing_dir, 'wrong.h'), '')

      scanner = Mkdepend::Scanner.new(
        root: root,
        include_dirs: [root],
      )

      assert_equal(
        %w[ext/-test-/float/nextafter.c missing/nextafter.c missing/right.h],
        scanner.scan('ext/-test-/float/nextafter.c'),
      )
    end
  end

  def test_virtual_dependencies_are_declared
    declarations = mkdepend.dependency_declarations('depend')
    assert_equal(
      %w[include/ruby.h include/ruby/version.h config.h],
      declarations.dependencies['config.h'],
    )
    assert_equal(
      declarations.dependencies['config.h'],
      declarations.dependencies['ruby/config.h'],
    )
    assert_equal(%w[probes.h probes.dmyh], declarations.dependencies['probes.h'])
    assert_equal(
      'prism/templates/src/node.c.erb',
      declarations.scan['prism/node.c'],
    )
    assert_equal(
      'prism/templates/include/prism/ast.h.erb',
      declarations.scan['prism/ast.h'],
    )
    assert_equal('thread_pthread.h', declarations.scan['THREAD_IMPL_H'])
    assert_equal('thread_pthread.c', declarations.scan['THREAD_IMPL_SRC'])
    assert_equal(
      %w[thread_$(THREAD_MODEL).h],
      declarations.dependencies['THREAD_IMPL_H'],
    )
    assert_equal(
      %w[thread_$(THREAD_MODEL).c],
      declarations.dependencies['THREAD_IMPL_SRC'],
    )
    assert_equal(
      %w[{$(VPATH)}$(COROUTINE_H)],
      declarations.dependencies['COROUTINE_H'],
    )
    assert_equal(%w[RIPPER], declarations.undefines['parse.y'])
    ripper = mkdepend.dependency_declarations('ext/ripper/depend')
    assert_equal(%w[RIPPER], ripper.defines['ripper.y'])
    assert_equal(
      %w[eventids1.h {$(VPATH)}eventids1.c],
      ripper.dependencies['eventids1.c'],
    )
    console = mkdepend.dependency_declarations('ext/io/console/depend')
    assert_equal(%w[$(VK_HEADER)], console.dependencies['win32_vk.inc'])
    assert_path_not_exist(File.expand_path('../mkdepend', __dir__))
  end

  def test_scan_patterns_are_expanded_from_selected_root
    Dir.mktmpdir('mkdepend-prism') do |dir|
      FileUtils.mkdir_p(File.join(dir, 'prism/templates/src'))
      FileUtils.mkdir_p(File.join(dir, 'prism/templates/ext/prism'))
      FileUtils.mkdir_p(File.join(dir, 'prism/templates/include/prism/internal'))
      FileUtils.mkdir_p(File.join(dir, 'enc/trans'))
      File.write(File.join(dir, 'prism/templates/src/node.c.erb'), '')
      File.write(File.join(dir, 'prism/templates/ext/prism/api.c.erb'), '')
      File.write(File.join(dir, 'prism/templates/include/prism/ast.h.erb'), '')
      File.write(
        File.join(dir, 'prism/templates/include/prism/internal/node.h.erb'),
        '',
      )
      File.write(File.join(dir, 'enc/trans/example.trans'), '')
      File.write(File.join(dir, 'depend'), <<~DEPEND)
        # mkdepend: scan prism/*.c => prism/templates/src/*.c.erb
        # mkdepend: scan prism/*.c => prism/templates/ext/prism/*.c.erb
        # mkdepend: scan **/*.h => prism/templates/include/**/*.h.erb
        # mkdepend: scan enc/trans/*.c => enc/trans/*.trans
      DEPEND

      mkdepend = Mkdepend.new(root: dir)
      assert_equal(
        {
          'enc/trans/example.c' => 'enc/trans/example.trans',
          'prism/api.c' => 'prism/templates/ext/prism/api.c.erb',
          'prism/ast.h' => 'prism/templates/include/prism/ast.h.erb',
          'prism/internal/node.h' =>
            'prism/templates/include/prism/internal/node.h.erb',
          'prism/node.c' => 'prism/templates/src/node.c.erb',
        },
        mkdepend.dependency_declarations('depend').scan,
      )
    end
  end

  def test_dependency_declarations_control_scanning_and_output
    Dir.mktmpdir('mkdepend-declarations') do |dir|
      FileUtils.mkdir_p(File.join(dir, 'ext/example'))
      File.write(File.join(dir, 'depend'), <<~DEPEND)
        # mkdepend: scan aliased.h => alias.h.tmpl
        # mkdepend: depends virtual.h => first.h second.h
        #{MARK_START}
        #{MARK_END}
      DEPEND
      File.write(File.join(dir, 'alias.h.tmpl'), "#include \"nested.h\"\n")
      File.write(File.join(dir, 'nested.h'), '')
      File.write(File.join(dir, 'template.c'), <<~C)
        #include "aliased.h"
        #include "generated.h"
        #include "virtual.h"
        #include "vpath.inc"
        #include "selected.inc"
      C
      input = File.join(dir, 'ext/example/depend')
      File.write(input, <<~DEPEND)
        # mkdepend: scan generated.c => template.c
        # mkdepend: generated generated.h
        # mkdepend: generated vpath.inc
        # mkdepend: depends vpath.inc => {$(VPATH)}vpath.inc
        # mkdepend: depends selected.inc => $(SELECTED_HEADER)
        #{MARK_START}
        generated.o: generated.c
        #{MARK_END}
      DEPEND

      output = File.join(dir, '.deps')
      mkdepend = Mkdepend.new(root: dir)
      assert_true(mkdepend.run_mkdepend([input], output: output, nmake: true))
      generated = File.read(File.join(output, 'ext/example/depend'))
      assert_include(generated, 'generated.o: generated.c')
      assert_include(generated, 'generated.o: generated.h')
      assert_include(generated, 'generated.o: {$(VPATH)}vpath.inc')
      assert_include(generated, 'generated.o: $(SELECTED_HEADER)')
      assert_include(generated, 'generated.o: $(top_srcdir)/first.h')
      assert_include(generated, 'generated.o: $(top_srcdir)/second.h')
      assert_include(generated, 'generated.o: $(top_srcdir)/nested.h')
    end
  end

  def test_invalid_dependency_declaration
    Dir.mktmpdir('mkdepend-declarations') do |dir|
      path = File.join(dir, 'depend')
      [
        '# mkdepend: depends ignored.h =>',
        '# mkdepend: generated generated.h => $(GENERATED_HEADER)',
        '# mkdepend: unknown header.h',
        '# mkdepend: scan generated/*.c => template.c.erb',
        '# mkdepend: scan generated/*.c => missing/*.c.erb',
      ].each do |declaration|
        File.write(path, "manual: rule\n#{declaration}\n")
        error = assert_raise(RuntimeError) do
          Mkdepend.new(root: dir).parse_dependency_declarations(path)
        end
        assert_equal(
          "#{path}:2: invalid mkdepend declaration: #{declaration}",
          error.message,
        )
      end
    end
  end

  def test_duplicate_dependency_declaration
    Dir.mktmpdir('mkdepend-declarations') do |dir|
      path = File.join(dir, 'depend')
      File.write(path, <<~DEPEND)
        # mkdepend: depends generated.c => generated.h
        # mkdepend: depends generated.c => generated.inc
      DEPEND
      error = assert_raise(RuntimeError) do
        Mkdepend.new(root: dir).parse_dependency_declarations(path)
      end
      assert_equal(
        "#{path}:2: duplicate mkdepend declaration: generated.c",
        error.message,
      )
    end
  end

  def test_dependency_files
    files = mkdepend.dependency_files
    assert_include(files, 'depend')
    assert_include(files, 'enc/depend')
    assert_include(files, 'ext/date/depend')
    assert(files.all? {|file| File.read(File.join(TOP_SRCDIR, file)).include?(MARK_START)})
  end

  def test_unicode_header
    assert_equal(
      ['$(UNICODE_HDR_DIR)/name2ctype.h'],
      mkdepend.depends(['enc/unicode/15.0.0/name2ctype.h'], nil),
    )
  end

  def test_vpath_for_dependency_file
    assert_equal('{$(VPATH)}', mkdepend.dependency_vpath('depend', 'enc/ascii.c'))
    assert_nil(mkdepend.dependency_vpath('enc/depend', 'enc/ascii.c'))
    assert_equal('{$(VPATH)}', mkdepend.dependency_vpath('depend', 'array.c'))
    assert_equal(['{$(VPATH)}enc/ascii.c'], mkdepend.depends(['enc/ascii.c'], '{$(VPATH)}'))
    assert_equal(['enc/ascii.c'], mkdepend.depends(['enc/ascii.c'], nil))
    assert_equal(
      ['{$(VPATH)}thread_$(THREAD_MODEL).h'],
      mkdepend.depends(['{$(VPATH)}thread_$(THREAD_MODEL).h'], '{$(VPATH)}'),
    )
  end

  def test_ruby_sources_are_not_headers
    assert_empty(mkdepend.depends(%w[array.rb array.rbinc], '{$(VPATH)}') & ['{$(VPATH)}array.rb'])
  end

  def test_tool_sources
    assert_equal(
      %w[
        $(top_srcdir)/tool/dump_ast.c
        $(top_srcdir)/tool/mkdepend/yaml.h
      ],
      mkdepend.depends(%w[tool/dump_ast.c tool/mkdepend/yaml.h], '{$(VPATH)}'),
    )
  end

  def test_dependency_sources
    assert_equal(
      %w[array.c parse.y],
      mkdepend.dependency_sources(<<~RULES, 'depend'),
        array.$(OBJEXT): {$(VPATH)}array.c
        parse.$(OBJEXT): {$(VPATH)}parse.c
        parse.$(OBJEXT): {$(VPATH)}parse.y
      RULES
    )
    assert_equal(
      %w[enc/ascii.c],
      mkdepend.dependency_sources(<<~RULES, 'enc/depend'),
        enc/ascii.$(OBJEXT): enc/ascii.c
      RULES
    )
    assert_equal(
      %w[ext/date/date_core.c],
      mkdepend.dependency_sources(<<~RULES, 'ext/date/depend'),
        date_core.o: date_core.c
      RULES
    )
    assert_equal(
      %w[ext/-test-/float/nextafter.c],
      mkdepend.dependency_sources(<<~RULES, 'ext/-test-/float/depend'),
        nextafter.o: $(top_srcdir)/missing/nextafter.c
        nextafter.o: nextafter.c
      RULES
    )
    assert_equal(
      %w[ext/-test-/load/dot.dot/dot.dot.c],
      mkdepend.dependency_sources(<<~RULES, 'ext/-test-/load/dot.dot/depend'),
        dot.dot.o: dot.dot.c
      RULES
    )
    assert_equal(
      %w[prism/api_node.c],
      mkdepend.dependency_sources(<<~RULES, 'depend'),
        prism/api_node.$(OBJEXT): $(top_srcdir)/prism/api_node.c
      RULES
    )
    assert_equal(
      {'dump_ast-dump_ast' => 'tool/dump_ast.c'},
      mkdepend.dependency_source_map(<<~RULES, 'depend'),
        dump_ast-dump_ast.$(OBJEXT): $(top_srcdir)/tool/dump_ast.c
      RULES
    )
  end

  def test_extension_headers
    assert_equal(
      [
        '$(RUBY_EXTCONF_H)',
        '$(arch_hdrdir)/ruby/config.h',
        '$(hdrdir)/ruby.h',
        '$(hdrdir)/ruby/internal/intern/parse.h',
        '$(hdrdir)/ruby/internal/value.h',
        '$(hdrdir)/ruby/version.h',
        '$(top_srcdir)/internal.h',
        '$(top_srcdir)/internal/parse.h',
        'date_tmx.h',
        '{$(VPATH)}probes.dmyh',
      ],
      mkdepend.depends(
        %w[
          extconf.h
          config.h
          include/ruby/internal/intern/parse.h
          include/ruby/internal/value.h
          internal.h
          internal/parse.h
          probes.h
          ext/date/date_tmx.h
        ],
        nil,
        source: 'ext/date/date_core.c',
      ),
    )
    assert_equal(
      ['$(srcdir)/../digest.h'],
      mkdepend.depends(['ext/digest/md5/../digest.h'], nil, source: 'ext/digest/md5/md5.c'),
    )
    assert_equal(
      ['{$(VPATH)}ripper.c'],
      mkdepend.depends(['ext/ripper/ripper.c'], nil, source: 'ext/ripper/ripper.y'),
    )
    assert_equal(
      ['$(top_srcdir)/thread_$(THREAD_MODEL).h'],
      mkdepend.depends(['THREAD_IMPL_H'], nil, source: 'ext/coverage/coverage.c'),
    )
    assert_equal(
      ['{$(VPATH)}probes.dmyh'],
      mkdepend.depends(%w[probes.h probes.dmyh], nil, source: 'ext/ripper/ripper.y'),
    )
  end

  def test_object_name
    assert_equal('array.$(OBJEXT)', mkdepend.object_name('array.c'))
    assert_equal('enc/utf_8.$(OBJEXT)', mkdepend.object_name('enc/utf_8.c'))
    assert_equal('date_core.o', mkdepend.object_name('ext/date/date_core.c'))
    assert_equal('ripper.o', mkdepend.object_name('ext/ripper/ripper.y'))
    assert_equal('ffs.$(OBJEXT)', mkdepend.object_name('missing/ffs.c'))
  end

  def test_parse_and_ripper_conditions
    assert_not_include(mkdepend.makedepend('parse.y').join, 'eventids1.h')
    assert_include(mkdepend.makedepend('ext/ripper/ripper.y').join, 'eventids1.h')
  end

  def test_generated_headers_are_dependencies
    unicode = mkdepend.makedepend('enc/unicode.c').join
    assert_include(unicode, '$(UNICODE_HDR_DIR)/casefold.h')
    assert_include(unicode, '$(UNICODE_HDR_DIR)/name2ctype.h')
    assert_include(mkdepend.makedepend('loadpath.c').join, '{$(VPATH)}verconf.h')
    assert_include(mkdepend.makedepend('ruby-runner.c').join, '{$(VPATH)}ruby-runner.h')
  end

  def test_compact_dependencies
    rules = <<~RULES
      array.$(OBJEXT): common.h
      hash.$(OBJEXT): common.h
      array.$(OBJEXT): array.c
      hash.$(OBJEXT): hash.c
    RULES
    assert_equal(<<~DEPEND, mkdepend.compact_dependencies(rules))
      array.$(OBJEXT) hash.$(OBJEXT): common.h
      array.$(OBJEXT): array.c
      hash.$(OBJEXT): hash.c
    DEPEND
  end

  def test_compact_dependencies_keeps_separate_targets_for_nmake
    rules = <<~RULES
      array.o: common.h
      hash.o: common.h
      array.o: array.c
      hash.o: hash.c
    RULES
    assert_equal(<<~DEPEND, mkdepend.compact_dependencies(rules, group: false))
      array.o: array.c
      array.o: common.h
      hash.o: common.h
      hash.o: hash.c
    DEPEND
  end

  def test_minimize_deps_keeps_only_preferred_source_rules
    rules = <<~RULES
      array.$(OBJEXT): common.h
      array.$(OBJEXT): {$(VPATH)}array.c
      parse.$(OBJEXT): {$(VPATH)}parse.c
      parse.$(OBJEXT): {$(VPATH)}parse.y
      hash.$(OBJEXT): common.h
      hash.$(OBJEXT): hash.c
    RULES
    assert_equal(<<~DEPEND, mkdepend.minimize_deps(rules, 'depend'))
      array.$(OBJEXT): {$(VPATH)}array.c
      hash.$(OBJEXT): hash.c
      parse.$(OBJEXT): {$(VPATH)}parse.y
    DEPEND
  end

  def test_minimize_deps_preserves_text_outside_markers
    content = +<<~DEPEND
      manual: rule
      #{MARK_START}
      array.$(OBJEXT): common.h
      array.$(OBJEXT): {$(VPATH)}array.c
      #{MARK_END}
      upstream: rule
    DEPEND
    Dir.mktmpdir('mkdepend') do |dir|
      path = File.join(dir, 'depend')
      File.write(path, content)

      assert_false(mkdepend.run([path], sources: true, inplace: true))
      assert_equal(<<~DEPEND, File.read(path))
        manual: rule
        #{MARK_START}
        array.$(OBJEXT): {$(VPATH)}array.c
        #{MARK_END}
        upstream: rule
      DEPEND
    end
  end

  def test_relative_source
    assert_equal('array.c', mkdepend.relative_source(File.join(TOP_SRCDIR, 'array.c')))
    assert_equal(
      'array.c',
      mkdepend.relative_source(File.join(TOP_SRCDIR, '.+aarch64-darwin', '..', 'array.c')),
    )
  end

  def test_replace_file_without_leftovers
    Dir.mktmpdir('mkdepend') do |dir|
      path = File.join(dir, 'depend')
      File.write(path, <<~DEPEND)
        #{MARK_START}
        array.$(OBJEXT): {$(VPATH)}array.c
        #{MARK_END}
      DEPEND
      File.chmod(0644, path)
      content = File.read(path)

      assert_false(mkdepend.run([path], inplace: true))

      assert_include(File.read(path), 'array.$(OBJEXT): $(hdrdir)/ruby/ruby.h')
      assert_equal(0644, File.stat(path).mode & 0777)
      assert_equal(%w[depend], Dir.children(dir))
    end
  end

  def test_run_writes_expanded_dependency_to_output_directory
    Dir.mktmpdir('mkdepend-output') do |dir|
      source = File.join(TOP_SRCDIR, 'ext/date/depend')
      output = File.join(dir, 'build-deps')
      original = File.read(source)

      assert_true(mkdepend.run([source], output: output))
      generated = File.read(File.join(output, 'ext/date/depend'))
      assert_include(generated, 'date_core.o: date_core.c')
      assert_match(/date_core\.o.*: \$\(hdrdir\)\/ruby\/ruby\.h/, generated)
      assert_not_include(generated, '{$(VPATH)}')
      assert_equal(original, File.read(source))
    end
  end

  def test_run_preserves_vpath_notation_for_nmake_output
    Dir.mktmpdir('mkdepend-output') do |dir|
      source = File.join(TOP_SRCDIR, 'ext/-test-/thread/id/depend')

      assert_true(mkdepend.run([source], output: dir, nmake: true))
      generated = File.read(File.join(dir, 'ext/-test-/thread/id/depend'))
      assert_include(generated, '{$(VPATH)}id.c')
    end
  end

  def test_run_removes_vpath_notation_from_build_output
    Dir.mktmpdir('mkdepend-output') do |dir|
      source = File.join(TOP_SRCDIR, 'ext/-test-/thread/id/depend')

      assert_true(mkdepend.run([source], output: dir))
      generated = File.read(File.join(dir, 'ext/-test-/thread/id/depend'))
      assert_include(generated, 'id.o: id.c')
      assert_not_include(generated, '{$(VPATH)}')
    end
  end

  def test_run_writes_unchanged_dependencies_to_output_directory
    Dir.mktmpdir('mkdepend-input') do |input_dir|
      Dir.mktmpdir('mkdepend-output') do |output|
        mkdepend = Mkdepend.new(root: input_dir)
        input = File.join(input_dir, 'depend')
        File.write(File.join(input_dir, 'array.c'), '')
        rules = "array.$(OBJEXT): {$(VPATH)}array.c\n"
        File.write(input, "#{MARK_START}\n#{rules}#{MARK_END}\n")
        destination = File.join(output, 'depend')

        assert_true(mkdepend.run([input], output: output))
        assert_equal(
          mkdepend.normalize_dependency_rules(File.read(input)),
          File.read(destination),
        )
      end
    end
  end

  def test_build_frontends_use_selected_dependency_directory
    common = File.read(File.join(TOP_SRCDIR, 'common.mk'))
    configure = File.read(File.join(TOP_SRCDIR, 'configure.ac'))
    makefile = File.read(File.join(TOP_SRCDIR, 'template/Makefile.in'))
    gnumakefile = File.read(File.join(TOP_SRCDIR, 'template/GNUmakefile.in'))
    prereq = File.read(File.join(TOP_SRCDIR, 'tool/prereq.status'))
    win32 = File.read(File.join(TOP_SRCDIR, 'win32/Makefile.sub'))

    assert_include(common, '!include $(DEPENDENCIES_DIR)/depend')
    assert_include(configure, 'AC_SUBST(X_DEPENDENCIES_DIR)')
    assert_include(configure, "X_DEPENDENCIES_DIR='\$X_DEPENDENCIES_DIR'")
    assert_not_include(configure, 'AC_SUBST(DEPENDENCIES_DIR)')
    assert_include(configure, '-root="$srcdir"')
    assert_include(makefile, 'DEPENDENCIES_DIR = @X_DEPENDENCIES_DIR@')
    assert_include(prereq, 's,@X_DEPENDENCIES_DIR@,$(srcdir),g')
    assert_include(gnumakefile, 'include $(DEPENDENCIES_DIR)/depend')
    assert_match(/filter-out .*DEPENDENCIES_DIR.*common_mk_includes/, gnumakefile)
    assert_include(win32, 'DEPENDENCIES_DIR = .deps')
    assert_include(win32, 'DEPENDENCIES_DIR = $(srcdir)')
  end

  def test_common_dependency_maintenance_targets
    common = File.read(File.join(TOP_SRCDIR, 'common.mk'))
    gmake = File.read(File.join(TOP_SRCDIR, 'defs/gmake.mk'))
    setup = File.read(File.join(TOP_SRCDIR, 'win32/setup.mak'))
    snapshot = File.read(File.join(TOP_SRCDIR, 'tool/make-snapshot'))

    assert_match(/^fix-depends: PHONY$/, common)
    assert_match(/^check-depends: PHONY$/, common)
    assert_match(/^distclean-local::.*\n\t-\$\(Q\)\$\(RMALL\) \.deps$/, common)
    assert_not_match(/^fix-depends:/, gmake)
    assert_not_match(/^check-depends:/, gmake)
    assert_match(/rm\.bat -f -r \.deps/, setup)
    assert_include(setup, '-root=$(srcdir)')
    assert_match(
      %r{tool[\\/]mkdepend\.rb -root=\$\(srcdir\) -all -nmake -output=\.deps},
      setup,
    )
    assert_include(snapshot, 'args["MKDEPEND_OPTIONS"] = ""')
    assert_include(snapshot, 'make.run("fix-depends")')
  end

  def test_file_without_markers_is_not_updated
    Dir.mktmpdir('mkdepend') do |dir|
      path = File.join(dir, 'depend')
      content = "array.$(OBJEXT): {$(VPATH)}array.c\n"
      File.write(path, content)

      assert_true(mkdepend.run([path], inplace: true))
      assert_equal(content, File.read(path))
    end
  end

  def test_unterminated_dependency_section_is_rejected
    content = +<<~DEPEND
      #{MARK_START}
      array.$(OBJEXT): {$(VPATH)}array.c
    DEPEND

    [content, MARK_START].each do |deps|
      Dir.mktmpdir('mkdepend') do |dir|
        path = File.join(dir, 'depend')
        File.write(path, deps)
        error = assert_raise(RuntimeError) {mkdepend.run([path])}
        assert_include(error.message, "missing #{MARK_END}")
      end
    end
  end

  def test_object_rules_without_a_source_are_rejected
    content = +<<~DEPEND
      #{MARK_START}
      unknown.o: unknown.h
      #{MARK_END}
    DEPEND
    Dir.mktmpdir('mkdepend') do |dir|
      path = File.join(dir, 'depend')
      File.write(path, content)
      error = assert_raise(RuntimeError) {mkdepend.run([path])}
      assert_include(error.message, 'no source files')
    end
  end

  def test_missing_dependency_source_is_rejected
    rules = <<~DEPEND
      unknown.o: unknown.c
    DEPEND

    error = assert_raise(RuntimeError) do
      mkdepend.minimize_deps(rules, 'ext/test/depend')
    end
    assert_include(error.message, 'source file not found: ext/test/unknown.c')

    error = assert_raise(RuntimeError) do
      mkdepend.update_deps(rules, 'ext/test/depend')
    end
    assert_include(error.message, 'source file not found: ext/test/unknown.c')
  end

  def test_vpath_notation_does_not_affect_dependency_comparison
    input = 'ext/-test-/thread/id/depend'
    expected = mkdepend.compact_dependencies(
      mkdepend.makedepend('ext/-test-/thread/id/id.c', input: input).join,
    )
    plain = expected.gsub('{$(VPATH)}', '')

    assert_true(mkdepend.same_dependency_rules?(expected, plain))
    assert_true(mkdepend.same_dependency_rules?(plain, expected))

    assert_true(mkdepend.same_dependency_rules?(plain, mkdepend.update_deps(plain, input)))
  end

  def test_outdated_dependency_report_shows_small_rule_changes
    current = <<~RULES
      array.$(OBJEXT): common.h
      array.$(OBJEXT): {$(VPATH)}array.c
    RULES
    expected = "array.$(OBJEXT): {$(VPATH)}array.c\n"
    err = StringIO.new

    mkdepend.report_outdated_dependencies('depend', current, expected, err: err)

    assert_include(err.string, 'depend: dependencies are outdated')
    assert_include(err.string, 'current dependency rules:')
    assert_include(err.string, 'array.$(OBJEXT): common.h')
    assert_include(err.string, 'expected source rules:')
  end

  def test_outdated_dependency_report_summarizes_large_rule_changes
    headers = 25.times.map {|i| "array.$(OBJEXT): header#{i}.h\n"}.join
    current = headers + "array.$(OBJEXT): {$(VPATH)}array.c\n"
    expected = "array.$(OBJEXT): {$(VPATH)}array.c\n"
    err = StringIO.new

    mkdepend.report_outdated_dependencies('depend', current, expected, err: err)

    assert_include(err.string, 'current section has 26 rules; expected 1 source rule')
    assert_not_include(err.string, 'header0.h')
    assert_include(err.string, expected.strip)
  end
end
