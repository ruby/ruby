require 'rubygems/installer_test_case'

class TestGemInstaller < Gem::InstallerTestCase

  def setup
    super
    common_installer_setup

    if __name__ =~ /^test_install(_|$)/ then
      FileUtils.rm_r @spec.gem_dir
      FileUtils.rm_r @user_spec.gem_dir
    end

    @config = Gem.configuration
  end

  def teardown
    common_installer_teardown

    super

    Gem.configuration = @config
  end

  def test_app_script_text
    util_make_exec @spec, ''

    expected = <<-EOF
#!#{Gem.ruby}
#
# This file was generated by RubyGems.
#
# The application 'a' is installed as part of a gem, and
# this file is here to facilitate running it.
#

require 'rubygems'

version = \">= 0.a\"

if ARGV.first
  str = ARGV.first
  str = str.dup.force_encoding("BINARY") if str.respond_to? :force_encoding
  if str =~ /\\A_(.*)_\\z/ and Gem::Version.correct?($1) then
    version = $1
    ARGV.shift
  end
end

gem 'a', version
load Gem.bin_path('a', 'executable', version)
    EOF

    wrapper = @installer.app_script_text 'executable'
    assert_equal expected, wrapper
  end

  def test_check_executable_overwrite
    @installer.generate_bin

    @spec = Gem::Specification.new do |s|
      s.files = ['lib/code.rb']
      s.name = "a"
      s.version = "3"
      s.summary = "summary"
      s.description = "desc"
      s.require_path = 'lib'
    end

    util_make_exec
    @installer.gem_dir = util_gem_dir @spec
    @installer.wrappers = true
    @installer.generate_bin

    installed_exec = File.join util_inst_bindir, 'executable'
    assert_path_exists installed_exec

    wrapper = File.read installed_exec
    assert_match %r|generated by RubyGems|, wrapper
  end

  def test_check_executable_overwrite_default_bin_dir
    if defined?(RUBY_FRAMEWORK_VERSION)
      orig_RUBY_FRAMEWORK_VERSION = RUBY_FRAMEWORK_VERSION
      Object.send :remove_const, :RUBY_FRAMEWORK_VERSION
    end
    orig_bindir = RbConfig::CONFIG['bindir']
    RbConfig::CONFIG['bindir'] = Gem.bindir

    util_conflict_executable false

    ui = Gem::MockGemUi.new "n\n"
    use_ui ui do
      e = assert_raises Gem::InstallError do
        @installer.generate_bin
      end

      conflicted = File.join @gemhome, 'bin', 'executable'
      assert_match %r%\A"executable" from a conflicts with (?:#{Regexp.quote(conflicted)}|installed executable from conflict)\z%,
                   e.message
    end
  ensure
    Object.const_set :RUBY_FRAMEWORK_VERSION, orig_RUBY_FRAMEWORK_VERSION if
      orig_RUBY_FRAMEWORK_VERSION
    if orig_bindir then
      RbConfig::CONFIG['bindir'] = orig_bindir
    else
      RbConfig::CONFIG.delete 'bindir'
    end
  end

  def test_check_executable_overwrite_format_executable
    @installer.generate_bin

    @spec = Gem::Specification.new do |s|
      s.files = ['lib/code.rb']
      s.name = "a"
      s.version = "3"
      s.summary = "summary"
      s.description = "desc"
      s.require_path = 'lib'
    end

    open File.join(util_inst_bindir, 'executable'), 'w' do |io|
     io.write <<-EXEC
#!/usr/local/bin/ruby
#
# This file was generated by RubyGems

gem 'other', version
     EXEC
    end

    util_make_exec
    Gem::Installer.exec_format = 'foo-%s-bar'
    @installer.gem_dir = @spec.gem_dir
    @installer.wrappers = true
    @installer.format_executable = true

    @installer.generate_bin # should not raise

    installed_exec = File.join util_inst_bindir, 'foo-executable-bar'
    assert_path_exists installed_exec

    wrapper = File.read installed_exec
    assert_match %r|generated by RubyGems|, wrapper
  end

  def test_check_executable_overwrite_other_gem
    util_conflict_executable true

    ui = Gem::MockGemUi.new "n\n"

    use_ui ui do
      e = assert_raises Gem::InstallError do
        @installer.generate_bin
      end

      assert_equal '"executable" from a conflicts with installed executable from conflict',
                   e.message
    end
  end

  def test_check_executable_overwrite_other_gem_force
    util_conflict_executable true
    @installer.wrappers = true
    @installer.force = true

    @installer.generate_bin

    installed_exec = File.join util_inst_bindir, 'executable'
    assert_path_exists installed_exec

    wrapper = File.read installed_exec
    assert_match %r|generated by RubyGems|, wrapper
  end

  def test_check_executable_overwrite_other_non_gem
    util_conflict_executable false
    @installer.wrappers = true

    @installer.generate_bin

    installed_exec = File.join util_inst_bindir, 'executable'
    assert_path_exists installed_exec

    wrapper = File.read installed_exec
    assert_match %r|generated by RubyGems|, wrapper
  end unless Gem.win_platform?

  def test_check_that_user_bin_dir_is_in_path
    bin_dir = @installer.bin_dir

    if Gem.win_platform?
      bin_dir = bin_dir.downcase.gsub(File::SEPARATOR, File::ALT_SEPARATOR)
    end

    orig_PATH, ENV['PATH'] =
      ENV['PATH'], [ENV['PATH'], bin_dir].join(File::PATH_SEPARATOR)

    use_ui @ui do
      @installer.check_that_user_bin_dir_is_in_path
    end

    assert_empty @ui.error
  ensure
    ENV['PATH'] = orig_PATH
  end

  def test_check_that_user_bin_dir_is_in_path_tilde
    skip "Tilde is PATH is not supported under MS Windows" if win_platform?

    orig_PATH, ENV['PATH'] =
      ENV['PATH'], [ENV['PATH'], '~/bin'].join(File::PATH_SEPARATOR)

    @installer.bin_dir.replace File.join @userhome, 'bin'

    use_ui @ui do
      @installer.check_that_user_bin_dir_is_in_path
    end

    assert_empty @ui.error
  ensure
    ENV['PATH'] = orig_PATH unless win_platform?
  end

  def test_check_that_user_bin_dir_is_in_path_not_in_path
    use_ui @ui do
      @installer.check_that_user_bin_dir_is_in_path
    end

    expected = @installer.bin_dir

    if Gem.win_platform? then
      expected = expected.downcase.gsub(File::SEPARATOR, File::ALT_SEPARATOR)
    end

    assert_match expected, @ui.error
  end

  def test_ensure_dependency
    util_spec 'a'

    dep = Gem::Dependency.new 'a', '>= 2'
    assert @installer.ensure_dependency(@spec, dep)

    dep = Gem::Dependency.new 'b', '> 2'
    e = assert_raises Gem::InstallError do
      @installer.ensure_dependency @spec, dep
    end

    assert_equal 'a requires b (> 2)', e.message
  end

  def test_ensure_loadable_spec
    a, a_gem = util_gem 'a', 2 do |s|
      s.add_dependency 'garbage ~> 5'
    end

    installer = Gem::Installer.at a_gem

    e = assert_raises Gem::InstallError do
      installer.ensure_loadable_spec
    end

    assert_equal "The specification for #{a.full_name} is corrupt " +
                 "(SyntaxError)", e.message
  end

  def test_ensure_loadable_spec_security_policy
    skip 'openssl is missing' unless defined?(OpenSSL::SSL)

    _, a_gem = util_gem 'a', 2 do |s|
      s.add_dependency 'garbage ~> 5'
    end

    policy = Gem::Security::HighSecurity
    installer = Gem::Installer.at a_gem, security_policy: policy

    assert_raises Gem::Security::Exception do
      installer.ensure_loadable_spec
    end
  end

  def test_extract_files
    @installer.extract_files

    assert_path_exists File.join util_gem_dir, 'bin/executable'
  end

  def test_generate_bin_bindir
    @installer.wrappers = true

    @spec.executables = %w[executable]
    @spec.bindir = '.'

    exec_file = @installer.formatted_program_filename 'executable'
    exec_path = File.join util_gem_dir(@spec), exec_file
    File.open exec_path, 'w' do |f|
      f.puts '#!/usr/bin/ruby'
    end

    @installer.gem_dir = util_gem_dir

    @installer.generate_bin

    assert_equal true, File.directory?(util_inst_bindir)
    installed_exec = File.join(util_inst_bindir, 'executable')
    assert_path_exists installed_exec
    assert_equal mask, File.stat(installed_exec).mode unless win_platform?

    wrapper = File.read installed_exec
    assert_match %r|generated by RubyGems|, wrapper
  end

  def test_generate_bin_bindir_with_user_install_warning
    bin_dir = Gem.win_platform? ? File.expand_path(ENV["WINDIR"]).upcase :
                                  "/usr/bin"

    options = {
      bin_dir: bin_dir,
      install_dir: "/non/existent"
    }

    inst = Gem::Installer.at '', options

    Gem::Installer.path_warning = false

    use_ui @ui do
      inst.check_that_user_bin_dir_is_in_path
    end

    assert_equal "", @ui.error
  end

  def test_generate_bin_script
    @installer.wrappers = true
    util_make_exec
    @installer.gem_dir = util_gem_dir

    @installer.generate_bin
    assert File.directory? util_inst_bindir
    installed_exec = File.join util_inst_bindir, 'executable'
    assert_path_exists installed_exec
    assert_equal mask, File.stat(installed_exec).mode unless win_platform?

    wrapper = File.read installed_exec
    assert_match %r|generated by RubyGems|, wrapper
  end

  def test_generate_bin_script_format
    @installer.format_executable = true
    @installer.wrappers = true
    util_make_exec
    @installer.gem_dir = util_gem_dir

    Gem::Installer.exec_format = 'foo-%s-bar'
    @installer.generate_bin
    assert_equal true, File.directory?(util_inst_bindir)
    installed_exec = File.join util_inst_bindir, 'foo-executable-bar'
    assert_path_exists installed_exec
  ensure
    Gem::Installer.exec_format = nil
  end

  def test_generate_bin_script_format_disabled
    @installer.wrappers = true
    util_make_exec
    @installer.gem_dir = util_gem_dir

    Gem::Installer.exec_format = 'foo-%s-bar'
    @installer.generate_bin
    assert_equal true, File.directory?(util_inst_bindir)
    installed_exec = File.join util_inst_bindir, 'executable'
    assert_path_exists installed_exec
  ensure
    Gem::Installer.exec_format = nil
  end

  def test_generate_bin_script_install_dir
    @installer.wrappers = true

    gem_dir = File.join("#{@gemhome}2", "gems", @spec.full_name)
    gem_bindir = File.join gem_dir, 'bin'
    FileUtils.mkdir_p gem_bindir
    File.open File.join(gem_bindir, 'executable'), 'w' do |f|
      f.puts "#!/bin/ruby"
    end

    @installer.gem_home = "#{@gemhome}2"
    @installer.gem_dir = gem_dir
    @installer.bin_dir = File.join "#{@gemhome}2", 'bin'

    @installer.generate_bin

    installed_exec = File.join("#{@gemhome}2", "bin", 'executable')
    assert_path_exists installed_exec
    assert_equal mask, File.stat(installed_exec).mode unless win_platform?

    wrapper = File.read installed_exec
    assert_match %r|generated by RubyGems|, wrapper
  end

  def test_generate_bin_script_no_execs
    util_execless

    @installer.wrappers = true
    @installer.generate_bin

    refute_path_exists util_inst_bindir, 'bin dir was created when not needed'
  end

  def test_generate_bin_script_no_perms
    @installer.wrappers = true
    util_make_exec

    Dir.mkdir util_inst_bindir

    if win_platform?
      skip('test_generate_bin_script_no_perms skipped on MS Windows')
    else
      FileUtils.chmod 0000, util_inst_bindir

      assert_raises Gem::FilePermissionError do
        @installer.generate_bin
      end
    end
  ensure
    FileUtils.chmod 0755, util_inst_bindir unless ($DEBUG or win_platform?)
  end

  def test_generate_bin_script_no_shebang
    @installer.wrappers = true
    @spec.executables = %w[executable]

    gem_dir = File.join @gemhome, 'gems', @spec.full_name
    gem_bindir = File.join gem_dir, 'bin'
    FileUtils.mkdir_p gem_bindir
    File.open File.join(gem_bindir, 'executable'), 'w' do |f|
      f.puts "blah blah blah"
    end

    @installer.generate_bin

    installed_exec = File.join @gemhome, 'bin', 'executable'
    assert_path_exists installed_exec
    assert_equal mask, File.stat(installed_exec).mode unless win_platform?

    wrapper = File.read installed_exec
    assert_match %r|generated by RubyGems|, wrapper
    # HACK some gems don't have #! in their executables, restore 2008/06
    #assert_no_match %r|generated by RubyGems|, wrapper
  end

  def test_generate_bin_script_wrappers
    @installer.wrappers = true
    util_make_exec
    @installer.gem_dir = util_gem_dir
    installed_exec = File.join(util_inst_bindir, 'executable')

    real_exec = File.join util_gem_dir, 'bin', 'executable'

    # fake --no-wrappers for previous install
    unless Gem.win_platform? then
      FileUtils.mkdir_p File.dirname(installed_exec)
      FileUtils.ln_s real_exec, installed_exec
    end

    @installer.generate_bin
    assert_equal true, File.directory?(util_inst_bindir)
    assert_path_exists installed_exec
    assert_equal mask, File.stat(installed_exec).mode unless win_platform?

    assert_match %r|generated by RubyGems|, File.read(installed_exec)

    refute_match %r|generated by RubyGems|, File.read(real_exec),
                 'real executable overwritten'
  end

  def test_generate_bin_symlink
    return if win_platform? #Windows FS do not support symlinks

    @installer.wrappers = false
    util_make_exec
    @installer.gem_dir = util_gem_dir

    @installer.generate_bin
    assert_equal true, File.directory?(util_inst_bindir)
    installed_exec = File.join util_inst_bindir, 'executable'
    assert_equal true, File.symlink?(installed_exec)
    assert_equal(File.join(util_gem_dir, 'bin', 'executable'),
                 File.readlink(installed_exec))
  end

  def test_generate_bin_symlink_no_execs
    util_execless

    @installer.wrappers = false
    @installer.generate_bin

    refute_path_exists util_inst_bindir
  end

  def test_generate_bin_symlink_no_perms
    @installer.wrappers = false
    util_make_exec
    @installer.gem_dir = util_gem_dir

    Dir.mkdir util_inst_bindir

    if win_platform?
      skip('test_generate_bin_symlink_no_perms skipped on MS Windows')
    else
      FileUtils.chmod 0000, util_inst_bindir

      assert_raises Gem::FilePermissionError do
        @installer.generate_bin
      end
    end
  ensure
    FileUtils.chmod 0755, util_inst_bindir unless ($DEBUG or win_platform?)
  end

  def test_generate_bin_symlink_update_newer
    return if win_platform? #Windows FS do not support symlinks

    @installer.wrappers = false
    util_make_exec
    @installer.gem_dir = util_gem_dir

    @installer.generate_bin
    installed_exec = File.join(util_inst_bindir, 'executable')
    assert_equal(File.join(util_gem_dir, 'bin', 'executable'),
                 File.readlink(installed_exec))

    @spec = Gem::Specification.new do |s|
      s.files = ['lib/code.rb']
      s.name = "a"
      s.version = "3"
      s.summary = "summary"
      s.description = "desc"
      s.require_path = 'lib'
    end

    util_make_exec
    @installer.gem_dir = util_gem_dir @spec
    @installer.generate_bin
    installed_exec = File.join(util_inst_bindir, 'executable')
    assert_equal(@spec.bin_file('executable'),
                 File.readlink(installed_exec),
                 "Ensure symlink moved to latest version")
  end

  def test_generate_bin_symlink_update_older
    return if win_platform? #Windows FS do not support symlinks

    @installer.wrappers = false
    util_make_exec
    @installer.gem_dir = util_gem_dir

    @installer.generate_bin
    installed_exec = File.join(util_inst_bindir, 'executable')
    assert_equal(File.join(util_gem_dir, 'bin', 'executable'),
                 File.readlink(installed_exec))

    spec = Gem::Specification.new do |s|
      s.files = ['lib/code.rb']
      s.name = "a"
      s.version = "1"
      s.summary = "summary"
      s.description = "desc"
      s.require_path = 'lib'
    end

    util_make_exec
    one = @spec.dup
    one.version = 1
    @installer = Gem::Installer.for_spec spec
    @installer.gem_dir = util_gem_dir one

    @installer.generate_bin

    installed_exec = File.join util_inst_bindir, 'executable'
    expected = File.join util_gem_dir, 'bin', 'executable'
    assert_equal(expected,
                 File.readlink(installed_exec),
                 "Ensure symlink not moved")
  end

  def test_generate_bin_symlink_update_remove_wrapper
    return if win_platform? #Windows FS do not support symlinks

    @installer.wrappers = true
    util_make_exec
    @installer.gem_dir = util_gem_dir

    @installer.generate_bin

    installed_exec = File.join util_inst_bindir, 'executable'
    assert_path_exists installed_exec

    @spec = Gem::Specification.new do |s|
      s.files = ['lib/code.rb']
      s.name = "a"
      s.version = "3"
      s.summary = "summary"
      s.description = "desc"
      s.require_path = 'lib'
    end
    util_make_exec

    util_installer @spec, @gemhome
    @installer.wrappers = false
    @installer.gem_dir = util_gem_dir

    @installer.generate_bin

    installed_exec = File.join util_inst_bindir, 'executable'
    assert_equal(@spec.bin_file('executable'),
                 File.readlink(installed_exec),
                 "Ensure symlink moved to latest version")
  end

  def test_generate_bin_symlink_win32
    old_win_platform = Gem.win_platform?
    Gem.win_platform = true
    old_alt_separator = File::ALT_SEPARATOR
    File.__send__(:remove_const, :ALT_SEPARATOR)
    File.const_set(:ALT_SEPARATOR, '\\')
    @installer.wrappers = false
    util_make_exec
    @installer.gem_dir = util_gem_dir

    use_ui @ui do
      @installer.generate_bin
    end

    assert_equal true, File.directory?(util_inst_bindir)
    installed_exec = File.join(util_inst_bindir, 'executable')
    assert_path_exists installed_exec

    assert_match(/Unable to use symlinks on Windows, installing wrapper/i,
                 @ui.error)

    wrapper = File.read installed_exec
    assert_match(/generated by RubyGems/, wrapper)
  ensure
    File.__send__(:remove_const, :ALT_SEPARATOR)
    File.const_set(:ALT_SEPARATOR, old_alt_separator)
    Gem.win_platform = old_win_platform
  end

  def test_generate_bin_uses_default_shebang
    return if win_platform? #Windows FS do not support symlinks

    @installer.wrappers = true
    util_make_exec

    @installer.generate_bin

    default_shebang = Gem.ruby
    shebang_line = open("#{@gemhome}/bin/executable") { |f| f.readlines.first }
    assert_match(/\A#!/, shebang_line)
    assert_match(/#{default_shebang}/, shebang_line)
  end

  def test_initialize
    spec = util_spec 'a' do |s| s.platform = Gem::Platform.new 'mswin32' end
    gem = File.join @tempdir, spec.file_name

    Dir.mkdir util_inst_bindir
    util_build_gem spec
    FileUtils.mv spec.cache_file, @tempdir

    installer = Gem::Installer.at gem

    assert_equal File.join(@gemhome, 'gems', spec.full_name), installer.gem_dir
    assert_equal File.join(@gemhome, 'bin'), installer.bin_dir
  end

  def test_initialize_user_install
    installer = Gem::Installer.at @gem, user_install: true

    assert_equal File.join(Gem.user_dir, 'gems', @spec.full_name),
                 installer.gem_dir
    assert_equal Gem.bindir(Gem.user_dir), installer.bin_dir
  end

  def test_initialize_user_install_bin_dir
    installer =
      Gem::Installer.at @gem, user_install: true, bin_dir: @tempdir

    assert_equal File.join(Gem.user_dir, 'gems', @spec.full_name),
                 installer.gem_dir
    assert_equal @tempdir, installer.bin_dir
  end

  def test_install
    Dir.mkdir util_inst_bindir
    util_setup_gem
    util_clear_gems

    gemdir     = File.join @gemhome, 'gems', @spec.full_name
    cache_file = File.join @gemhome, 'cache', @spec.file_name
    stub_exe   = File.join @gemhome, 'bin', 'executable'
    rakefile   = File.join gemdir, 'ext', 'a', 'Rakefile'
    spec_file  = File.join @gemhome, 'specifications', @spec.spec_name

    Gem.pre_install do |installer|
      refute_path_exists cache_file, 'cache file must not exist yet'
      refute_path_exists spec_file,  'spec file must not exist yet'
      true
    end

    Gem.post_build do |installer|
      assert_path_exists gemdir, 'gem install dir must exist'
      assert_path_exists rakefile, 'gem executable must exist'
      refute_path_exists stub_exe, 'gem executable must not exist'
      refute_path_exists spec_file, 'spec file must not exist yet'
      true
    end

    Gem.post_install do |installer|
      assert_path_exists cache_file, 'cache file must exist'
      assert_path_exists spec_file,  'spec file must exist'
    end

    @newspec = nil
    build_rake_in do
      use_ui @ui do
        @newspec = @installer.install
      end
    end

    assert_equal @spec, @newspec
    assert_path_exists gemdir
    assert_path_exists stub_exe, 'gem executable must exist'

    exe = File.join gemdir, 'bin', 'executable'
    assert_path_exists exe

    exe_mode = File.stat(exe).mode & 0111
    assert_equal 0111, exe_mode, "0%o" % exe_mode unless win_platform?

    assert_path_exists File.join gemdir, 'lib', 'code.rb'

    assert_path_exists rakefile

    spec_file = File.join(@gemhome, 'specifications', @spec.spec_name)

    assert_equal spec_file, @newspec.loaded_from
    assert_path_exists spec_file

    assert_same @installer, @post_build_hook_arg
    assert_same @installer, @post_install_hook_arg
    assert_same @installer, @pre_install_hook_arg
  end

  def test_install_creates_working_binstub
    Dir.mkdir util_inst_bindir
    util_setup_gem
    util_clear_gems

    @installer.wrappers = true

    gemdir = File.join @gemhome, 'gems', @spec.full_name

    @newspec = nil
    build_rake_in do
      use_ui @ui do
        @newspec = @installer.install
      end
    end

    exe = File.join gemdir, 'bin', 'executable'

    e = assert_raises RuntimeError do
      instance_eval File.read(exe)
    end

    assert_match(/ran executable/, e.message)
  end

  def test_install_creates_binstub_that_understand_version
    Dir.mkdir util_inst_bindir
    util_setup_gem
    util_clear_gems

    @installer.wrappers = true

    @newspec = nil
    build_rake_in do
      use_ui @ui do
        @newspec = @installer.install
      end
    end

    exe = File.join @gemhome, 'bin', 'executable'

    ARGV.unshift "_3.0_"

    begin
      Gem::Specification.reset

      e = assert_raises Gem::LoadError do
        instance_eval File.read(exe)
      end
    ensure
      ARGV.shift if ARGV.first == "_3.0_"
    end

    assert_match(/\(= 3\.0\)/, e.message)
  end

  def test_install_creates_binstub_that_dont_trust_encoding
    skip unless "".respond_to?(:force_encoding)

    Dir.mkdir util_inst_bindir
    util_setup_gem
    util_clear_gems

    @installer.wrappers = true

    @newspec = nil
    build_rake_in do
      use_ui @ui do
        @newspec = @installer.install
      end
    end

    exe = File.join @gemhome, 'bin', 'executable'

    extra_arg = "\xE4pfel".force_encoding("UTF-8")
    ARGV.unshift extra_arg

    begin
      Gem::Specification.reset

      e = assert_raises RuntimeError do
        instance_eval File.read(exe)
      end
    ensure
      ARGV.shift if ARGV.first == extra_arg
    end

    assert_match(/ran executable/, e.message)
  end

  def test_install_with_no_prior_files
    Dir.mkdir util_inst_bindir
    util_clear_gems

    util_setup_gem
    build_rake_in do
      use_ui @ui do
        assert_equal @spec, @installer.install
      end
    end

    gemdir = File.join(@gemhome, 'gems', @spec.full_name)
    assert_path_exists File.join gemdir, 'lib', 'code.rb'

    util_setup_gem
    # Morph spec to have lib/other.rb instead of code.rb and recreate
    @spec.files = File.join('lib', 'other.rb')
    Dir.chdir @tempdir do
      File.open File.join('lib', 'other.rb'), 'w' do |f| f.puts '1' end
      use_ui ui do
        FileUtils.rm @gem
        Gem::Package.build @spec
      end
    end
    @installer = Gem::Installer.at @gem
    build_rake_in do
      use_ui @ui do
        assert_equal @spec, @installer.install
      end
    end

    assert_path_exists File.join gemdir, 'lib', 'other.rb'
    refute_path_exists File.join gemdir, 'lib', 'code.rb',
           "code.rb from prior install of same gem shouldn't remain here"
  end

  def test_install_force
    use_ui @ui do
      installer = Gem::Installer.at old_ruby_required, force: true
      installer.install
    end

    gem_dir = File.join(@gemhome, 'gems', 'old_ruby_required-1')
    assert_path_exists gem_dir
  end

  def test_install_missing_dirs
    FileUtils.rm_f File.join(Gem.dir, 'cache')
    FileUtils.rm_f File.join(Gem.dir, 'docs')
    FileUtils.rm_f File.join(Gem.dir, 'specifications')

    use_ui @ui do
      @installer.install
    end

    File.directory? File.join(Gem.dir, 'cache')
    File.directory? File.join(Gem.dir, 'docs')
    File.directory? File.join(Gem.dir, 'specifications')

    assert_path_exists File.join @gemhome, 'cache', @spec.file_name
    assert_path_exists File.join @gemhome, 'specifications', @spec.spec_name
  end

  def test_install_post_build_false
    util_clear_gems

    Gem.post_build do
      false
    end

    use_ui @ui do
      e = assert_raises Gem::InstallError do
        @installer.install
      end

      location = "#{__FILE__}:#{__LINE__ - 9}"

      assert_equal "post-build hook at #{location} failed for a-2", e.message
    end

    spec_file = File.join @gemhome, 'specifications', @spec.spec_name
    refute_path_exists spec_file

    gem_dir = File.join @gemhome, 'gems', @spec.full_name
    refute_path_exists gem_dir
  end

  def test_install_post_build_nil
    util_clear_gems

    Gem.post_build do
      nil
    end

    use_ui @ui do
      @installer.install
    end

    spec_file = File.join @gemhome, 'specifications', @spec.spec_name
    assert_path_exists spec_file

    gem_dir = File.join @gemhome, 'gems', @spec.full_name
    assert_path_exists gem_dir
  end

  def test_install_pre_install_false
    util_clear_gems

    Gem.pre_install do
      false
    end

    use_ui @ui do
      e = assert_raises Gem::InstallError do
        @installer.install
      end

      location = "#{__FILE__}:#{__LINE__ - 9}"

      assert_equal "pre-install hook at #{location} failed for a-2", e.message
    end

    spec_file = File.join @gemhome, 'specifications', @spec.spec_name
    refute_path_exists spec_file
  end

  def test_install_pre_install_nil
    util_clear_gems

    Gem.pre_install do
      nil
    end

    use_ui @ui do
      @installer.install
    end

    spec_file = File.join @gemhome, 'specifications', @spec.spec_name
    assert_path_exists spec_file
  end

  def test_install_with_message
    @spec.post_install_message = 'I am a shiny gem!'

    use_ui @ui do
      path = Gem::Package.build @spec

      @installer = Gem::Installer.at path
      @installer.install
    end

    assert_match %r|I am a shiny gem!|, @ui.output
  end

  def test_install_extension_dir
    gemhome2 = "#{@gemhome}2"

    @spec.extensions << "extconf.rb"
    write_file File.join(@tempdir, "extconf.rb") do |io|
      io.write <<-RUBY
        require "mkmf"
        create_makefile("#{@spec.name}")
      RUBY
    end

    @spec.files += %w[extconf.rb]

    use_ui @ui do
      path = Gem::Package.build @spec

      installer = Gem::Installer.at path, install_dir: gemhome2
      installer.install
    end

    expected_makefile = File.join gemhome2, 'gems', @spec.full_name, 'Makefile'

    assert_path_exists expected_makefile
  end

  def test_install_extension_and_script
    @spec.extensions << "extconf.rb"
    write_file File.join(@tempdir, "extconf.rb") do |io|
      io.write <<-RUBY
        require "mkmf"
        create_makefile("#{@spec.name}")
      RUBY
    end

    rb = File.join("lib", "#{@spec.name}.rb")
    @spec.files += [rb]
    write_file File.join(@tempdir, rb) do |io|
      io.write <<-RUBY
        # #{@spec.name}.rb
      RUBY
    end

    Dir.mkdir(File.join("lib", @spec.name))
    rb2 = File.join("lib", @spec.name, "#{@spec.name}.rb")
    @spec.files << rb2
    write_file File.join(@tempdir, rb2) do |io|
      io.write <<-RUBY
        # #{@spec.name}/#{@spec.name}.rb
      RUBY
    end

    refute_path_exists File.join @spec.gem_dir, rb
    refute_path_exists File.join @spec.gem_dir, rb2
    use_ui @ui do
      path = Gem::Package.build @spec

      @installer = Gem::Installer.at path
      @installer.install
    end
    assert_path_exists File.join @spec.gem_dir, rb
    assert_path_exists File.join @spec.gem_dir, rb2
  end

  def test_install_extension_flat
    skip '1.9.2 and earlier mkmf.rb does not create TOUCH' if
      RUBY_VERSION < '1.9.3'

    if RUBY_VERSION == "1.9.3" and RUBY_PATCHLEVEL <= 194
      skip "TOUCH was introduced into 1.9.3 after p194"
    end

    @spec.require_paths = ["."]

    @spec.extensions << "extconf.rb"

    write_file File.join(@tempdir, "extconf.rb") do |io|
      io.write <<-RUBY
        require "mkmf"

        CONFIG['CC'] = '$(TOUCH) $@ ||'
        CONFIG['LDSHARED'] = '$(TOUCH) $@ ||'
        $ruby = '#{Gem.ruby}'

        create_makefile("#{@spec.name}")
      RUBY
    end

    # empty depend file for no auto dependencies
    @spec.files += %W"depend #{@spec.name}.c".each {|file|
      write_file File.join(@tempdir, file)
    }

    so = File.join(@spec.gem_dir, "#{@spec.name}.#{RbConfig::CONFIG["DLEXT"]}")
    refute_path_exists so
    use_ui @ui do
      path = Gem::Package.build @spec

      @installer = Gem::Installer.at path
      @installer.install
    end
    assert_path_exists so
  rescue
    puts '-' * 78
    puts File.read File.join(@gemhome, 'gems', 'a-2', 'Makefile')
    puts '-' * 78

    path = File.join(@gemhome, 'gems', 'a-2', 'gem_make.out')

    if File.exist?(path)
      puts File.read(path)
      puts '-' * 78
    end

    raise
  end

  def test_installation_satisfies_dependency_eh
    util_spec 'a'

    dep = Gem::Dependency.new 'a', '>= 2'
    assert @installer.installation_satisfies_dependency?(dep)

    dep = Gem::Dependency.new 'a', '> 2'
    refute @installer.installation_satisfies_dependency?(dep)
  end

  def test_installation_satisfies_dependency_eh_development
    @installer.options[:development] = true
    @installer.options[:dev_shallow] = true

    util_spec 'a'

    dep = Gem::Dependency.new 'a', :development
    assert @installer.installation_satisfies_dependency?(dep)
  end

  def test_pre_install_checks_dependencies
    @spec.add_dependency 'b', '> 5'
    util_setup_gem

    use_ui @ui do
      assert_raises Gem::InstallError do
        @installer.install
      end
    end
  end

  def test_pre_install_checks_dependencies_ignore
    @spec.add_dependency 'b', '> 5'
    @installer.ignore_dependencies = true

    build_rake_in do
      use_ui @ui do
        assert @installer.pre_install_checks
      end
    end
  end

  def test_pre_install_checks_dependencies_install_dir
    gemhome2 = "#{@gemhome}2"
    @spec.add_dependency 'd'

    quick_gem 'd', 2

    gem = File.join @gemhome, @spec.file_name

    FileUtils.mv @gemhome, gemhome2
    FileUtils.mkdir @gemhome

    FileUtils.mv File.join(gemhome2, 'cache', @spec.file_name), gem

    # Don't leak any already activated gems into the installer, require
    # that it work everything out on it's own.
    Gem::Specification.reset

    installer = Gem::Installer.at gem, install_dir: gemhome2

    build_rake_in do
      use_ui @ui do
        assert installer.pre_install_checks
      end
    end
  end

  def test_pre_install_checks_ruby_version
    use_ui @ui do
      installer = Gem::Installer.at old_ruby_required
      e = assert_raises Gem::InstallError do
        installer.pre_install_checks
      end
      assert_equal 'old_ruby_required requires Ruby version = 1.4.6.',
                   e.message
    end
  end

  def test_pre_install_checks_wrong_rubygems_version
    spec = util_spec 'old_rubygems_required', '1' do |s|
      s.required_rubygems_version = '< 0'
    end

    util_build_gem spec

    gem = File.join(@gemhome, 'cache', spec.file_name)

    use_ui @ui do
      @installer = Gem::Installer.at gem
      e = assert_raises Gem::InstallError do
        @installer.pre_install_checks
      end
      assert_equal 'old_rubygems_required requires RubyGems version < 0. ' +
        "Try 'gem update --system' to update RubyGems itself.", e.message
    end
  end

  def test_shebang
    util_make_exec @spec, "#!/usr/bin/ruby"

    shebang = @installer.shebang 'executable'

    assert_equal "#!#{Gem.ruby}", shebang
  end

  def test_process_options
    assert_nil @installer.build_root
    assert_equal File.join(@gemhome, 'bin'), @installer.bin_dir
    assert_equal @gemhome, @installer.gem_home
  end

  def test_process_options_build_root
    build_root = File.join @tempdir, 'build_root'

    @installer = Gem::Installer.at @gem, build_root: build_root

    assert_equal Pathname(build_root), @installer.build_root
    assert_equal File.join(build_root, @gemhome, 'bin'), @installer.bin_dir
    assert_equal File.join(build_root, @gemhome), @installer.gem_home
  end

  def test_shebang_arguments
    util_make_exec @spec, "#!/usr/bin/ruby -ws"

    shebang = @installer.shebang 'executable'

    assert_equal "#!#{Gem.ruby} -ws", shebang
  end

  def test_shebang_empty
    util_make_exec @spec, ''

    shebang = @installer.shebang 'executable'
    assert_equal "#!#{Gem.ruby}", shebang
  end

  def test_shebang_env
    util_make_exec @spec, "#!/usr/bin/env ruby"

    shebang = @installer.shebang 'executable'

    assert_equal "#!#{Gem.ruby}", shebang
  end

  def test_shebang_env_arguments
    util_make_exec @spec, "#!/usr/bin/env ruby -ws"

    shebang = @installer.shebang 'executable'

    assert_equal "#!#{Gem.ruby} -ws", shebang
  end

  def test_shebang_env_shebang
    util_make_exec @spec, ''
    @installer.env_shebang = true

    shebang = @installer.shebang 'executable'

    env_shebang = "/usr/bin/env" unless Gem.win_platform?

    assert_equal("#!#{env_shebang} #{RbConfig::CONFIG['ruby_install_name']}",
                 shebang)
  end

  def test_shebang_nested
    util_make_exec @spec, "#!/opt/local/ruby/bin/ruby"

    shebang = @installer.shebang 'executable'

    assert_equal "#!#{Gem.ruby}", shebang
  end

  def test_shebang_nested_arguments
    util_make_exec @spec, "#!/opt/local/ruby/bin/ruby -ws"

    shebang = @installer.shebang 'executable'

    assert_equal "#!#{Gem.ruby} -ws", shebang
  end

  def test_shebang_version
    util_make_exec @spec, "#!/usr/bin/ruby18"

    shebang = @installer.shebang 'executable'

    assert_equal "#!#{Gem.ruby}", shebang
  end

  def test_shebang_version_arguments
    util_make_exec @spec, "#!/usr/bin/ruby18 -ws"

    shebang = @installer.shebang 'executable'

    assert_equal "#!#{Gem.ruby} -ws", shebang
  end

  def test_shebang_version_env
    util_make_exec @spec, "#!/usr/bin/env ruby18"

    shebang = @installer.shebang 'executable'

    assert_equal "#!#{Gem.ruby}", shebang
  end

  def test_shebang_version_env_arguments
    util_make_exec @spec, "#!/usr/bin/env ruby18 -ws"

    shebang = @installer.shebang 'executable'

    assert_equal "#!#{Gem.ruby} -ws", shebang
  end

  def test_shebang_custom
    conf = Gem::ConfigFile.new []
    conf[:custom_shebang] = 'test'

    Gem.configuration = conf

    util_make_exec @spec, "#!/usr/bin/ruby"

    shebang = @installer.shebang 'executable'

    assert_equal "#!test", shebang
  end

  def test_shebang_custom_with_expands
    bin_env = win_platform? ? '' : '/usr/bin/env'
    conf = Gem::ConfigFile.new []
    conf[:custom_shebang] = '1 $env 2 $ruby 3 $exec 4 $name'

    Gem.configuration = conf

    util_make_exec @spec, "#!/usr/bin/ruby"

    shebang = @installer.shebang 'executable'

    assert_equal "#!1 #{bin_env} 2 #{Gem.ruby} 3 executable 4 a", shebang
  end

  def test_shebang_custom_with_expands_and_arguments
    bin_env = win_platform? ? '' : '/usr/bin/env'
    conf = Gem::ConfigFile.new []
    conf[:custom_shebang] = '1 $env 2 $ruby 3 $exec'

    Gem.configuration = conf

    util_make_exec @spec, "#!/usr/bin/ruby -ws"

    shebang = @installer.shebang 'executable'

    assert_equal "#!1 #{bin_env} 2 #{Gem.ruby} -ws 3 executable", shebang
  end

  def test_unpack
    util_setup_gem

    dest = File.join @gemhome, 'gems', @spec.full_name

    @installer.unpack dest

    assert_path_exists File.join dest, 'lib', 'code.rb'
    assert_path_exists File.join dest, 'bin', 'executable'
  end

  def test_write_build_info_file
    refute_path_exists @spec.build_info_file

    @installer.build_args = %w[
      --with-libyaml-dir /usr/local/Cellar/libyaml/0.1.4
    ]

    @installer.write_build_info_file

    assert_path_exists @spec.build_info_file

    expected = "--with-libyaml-dir\n/usr/local/Cellar/libyaml/0.1.4\n"

    assert_equal expected, File.read(@spec.build_info_file)
  end

  def test_write_build_info_file_empty
    refute_path_exists @spec.build_info_file

    @installer.write_build_info_file

    refute_path_exists @spec.build_info_file
  end

  def test_write_build_info_file_install_dir
    installer = Gem::Installer.at @gem, install_dir: "#{@gemhome}2"

    installer.build_args = %w[
      --with-libyaml-dir /usr/local/Cellar/libyaml/0.1.4
    ]

    installer.write_build_info_file

    refute_path_exists @spec.build_info_file
    assert_path_exists \
      File.join("#{@gemhome}2", 'build_info', "#{@spec.full_name}.info")
  end

  def test_write_cache_file
    cache_file = File.join @gemhome, 'cache', @spec.file_name
    gem = File.join @gemhome, @spec.file_name

    FileUtils.mv cache_file, gem
    refute_path_exists cache_file

    installer = Gem::Installer.at gem
    installer.gem_home = @gemhome

    installer.write_cache_file

    assert_path_exists cache_file
  end

  def test_write_spec
    FileUtils.rm @spec.spec_file
    refute_path_exists @spec.spec_file

    @installer = Gem::Installer.for_spec @spec
    @installer.gem_home = @gemhome

    @installer.write_spec

    assert_path_exists @spec.spec_file

    loaded = Gem::Specification.load @spec.spec_file

    assert_equal @spec, loaded

    assert_equal Gem.rubygems_version, @spec.installed_by_version
  end

  def test_write_spec_writes_cached_spec
    FileUtils.rm @spec.spec_file
    refute_path_exists @spec.spec_file

    @spec.files = %w[a.rb b.rb c.rb]

    @installer = Gem::Installer.for_spec @spec
    @installer.gem_home = @gemhome

    @installer.write_spec

    # cached specs have no file manifest:
    @spec.files = []

    assert_equal @spec, eval(File.read(@spec.spec_file))
  end

  def test_dir
    assert_match %r!/gemhome/gems/a-2$!, @installer.dir
  end

  def test_default_gem_loaded_from
    spec = util_spec 'a'
    installer = Gem::Installer.for_spec spec, install_as_default: true
    installer.install
    assert_predicate spec, :default_gem?
  end

  def test_default_gem
    FileUtils.rm_f File.join(Gem.dir, 'specifications')

    @installer.wrappers = true
    @installer.options[:install_as_default] = true
    @installer.gem_dir = util_gem_dir @spec
    @installer.generate_bin

    use_ui @ui do
      @installer.install
    end

    assert File.directory? util_inst_bindir
    installed_exec = File.join util_inst_bindir, 'executable'
    assert_path_exists installed_exec

    assert File.directory? File.join(Gem.default_dir, 'specifications')
    assert File.directory? File.join(Gem.default_dir, 'specifications', 'default')

    default_spec = eval File.read File.join(Gem.default_dir, 'specifications', 'default', 'a-2.gemspec')
    assert_equal Gem::Version.new("2"), default_spec.version
    assert_equal ['bin/executable'], default_spec.files
  end

  def old_ruby_required
    spec = util_spec 'old_ruby_required', '1' do |s|
      s.required_ruby_version = '= 1.4.6'
    end

    util_build_gem spec

    spec.cache_file
  end

  def util_execless
    @spec = util_spec 'z'
    util_build_gem @spec

    @installer = util_installer @spec, @gemhome
  end

  def util_conflict_executable wrappers
    conflict = quick_gem 'conflict' do |spec|
      util_make_exec spec
    end

    util_build_gem conflict

    installer = util_installer conflict, @gemhome
    installer.wrappers = wrappers
    installer.generate_bin
  end

  def mask
    0100755 & (~File.umask)
  end
end
