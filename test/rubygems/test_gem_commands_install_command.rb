# frozen_string_literal: true
require 'rubygems/test_case'
require 'rubygems/commands/install_command'
require 'rubygems/request_set'
require 'rubygems/rdoc'

class TestGemCommandsInstallCommand < Gem::TestCase

  def setup
    super
    common_installer_setup

    @cmd = Gem::Commands::InstallCommand.new
    @cmd.options[:document] = []

    @gemdeps = "tmp_install_gemdeps"
    @orig_args = Gem::Command.build_args

    common_installer_setup
  end

  def teardown
    super

    common_installer_teardown

    Gem::Command.build_args = @orig_args
    File.unlink @gemdeps if File.file? @gemdeps
    File.unlink "#{@gemdeps}.lock" if File.file? "#{@gemdeps}.lock"
  end

  def test_execute_exclude_prerelease
    spec_fetcher do |fetcher|
      fetcher.gem 'a', 2
      fetcher.gem 'a', '2.pre'
    end

    @cmd.options[:args] = %w[a]

    use_ui @ui do
      assert_raises Gem::MockGemUi::SystemExitException, @ui.error do
        @cmd.execute
      end
    end

    assert_equal %w[a-2], @cmd.installed_specs.map { |spec| spec.full_name }
  end

  def test_execute_explicit_version_includes_prerelease
    specs = spec_fetcher do |fetcher|
      fetcher.gem 'a', 2
      fetcher.gem 'a', '2.a'
    end

    a2_pre = specs['a-2.a']

    @cmd.handle_options [a2_pre.name, '--version', a2_pre.version.to_s,
                         "--no-document"]
    assert @cmd.options[:prerelease]
    assert @cmd.options[:version].satisfied_by?(a2_pre.version)

    use_ui @ui do
      assert_raises Gem::MockGemUi::SystemExitException, @ui.error do
        @cmd.execute
      end
    end

    assert_equal %w[a-2.a], @cmd.installed_specs.map { |spec| spec.full_name }
  end

  def test_execute_local
    specs = spec_fetcher do |fetcher|
      fetcher.gem 'a', 2
    end

    @cmd.options[:domain] = :local

    FileUtils.mv specs['a-2'].cache_file, @tempdir

    @cmd.options[:args] = %w[a]

    use_ui @ui do
      orig_dir = Dir.pwd
      begin
        Dir.chdir @tempdir
        assert_raises Gem::MockGemUi::SystemExitException, @ui.error do
          @cmd.execute
        end
      ensure
        Dir.chdir orig_dir
      end
    end

    assert_equal %w[a-2], @cmd.installed_specs.map { |spec| spec.full_name }

    assert_match "1 gem installed", @ui.output
  end

  def test_execute_local_transitive_prerelease
    specs = spec_fetcher do |fetcher|
      fetcher.download 'a', 2, 'b' => "2.a", 'c' => '3'
      fetcher.download 'b', '2.a'
      fetcher.download 'c', '3'
    end

    @cmd.options[:domain] = :local

    FileUtils.mv specs['a-2'].cache_file, @tempdir
    FileUtils.mv specs['b-2.a'].cache_file, @tempdir
    FileUtils.mv specs['c-3'].cache_file, @tempdir

    @cmd.options[:args] = %w[a]

    use_ui @ui do
      orig_dir = Dir.pwd
      begin
        Dir.chdir @tempdir
        FileUtils.rm_r [@gemhome, "gems"]
        assert_raises Gem::MockGemUi::SystemExitException, @ui.error do
          @cmd.execute
        end
      ensure
        Dir.chdir orig_dir
      end
    end

    assert_equal %w[a-2 b-2.a c-3], @cmd.installed_specs.map { |spec| spec.full_name }.sort

    assert_match "3 gems installed", @ui.output
  end

  def test_execute_no_user_install
    skip 'skipped on MS Windows (chmod has no effect)' if win_platform?
    skip 'skipped in root privilege' if Process.uid.zero?

    specs = spec_fetcher do |fetcher|
      fetcher.gem 'a', 2
    end

    @cmd.options[:user_install] = false

    FileUtils.mv specs['a-2'].cache_file, @tempdir

    @cmd.options[:args] = %w[a]

    use_ui @ui do
      orig_dir = Dir.pwd
      begin
        FileUtils.chmod 0755, @userhome
        FileUtils.chmod 0555, @gemhome

        Dir.chdir @tempdir
        assert_raises Gem::FilePermissionError do
          @cmd.execute
        end
      ensure
        Dir.chdir orig_dir
        FileUtils.chmod 0755, @gemhome
      end
    end
  end

  def test_execute_local_missing
    spec_fetcher

    @cmd.options[:domain] = :local

    @cmd.options[:args] = %w[no_such_gem]

    use_ui @ui do
      e = assert_raises Gem::MockGemUi::TermError do
        @cmd.execute
      end
      assert_equal 2, e.exit_code
    end

    # HACK no repository was checked
    assert_match(/ould not find a valid gem 'no_such_gem'/, @ui.error)
  end

  def test_execute_no_gem
    @cmd.options[:args] = %w[]

    assert_raises Gem::CommandLineError do
      @cmd.execute
    end
  end

  def test_execute_nonexistent
    spec_fetcher

    @cmd.options[:args] = %w[nonexistent]

    use_ui @ui do
      e = assert_raises Gem::MockGemUi::TermError do
        @cmd.execute
      end
      assert_equal 2, e.exit_code
    end

    assert_match(/ould not find a valid gem 'nonexistent'/, @ui.error)
  end

  def test_execute_dependency_nonexistent
    spec_fetcher do |fetcher|
      fetcher.spec 'foo', 2, 'bar' => '0.5'
    end

    @cmd.options[:args] = ['foo']

    use_ui @ui do
      e = assert_raises Gem::MockGemUi::TermError do
        @cmd.execute
      end

      assert_equal 2, e.exit_code
    end

    expected = <<-EXPECTED
ERROR:  Could not find a valid gem 'bar' (= 0.5) (required by 'foo' (>= 0)) in any repository
    EXPECTED

    assert_equal expected, @ui.error
  end

  def test_execute_http_proxy
    use_ui @ui do
      e = assert_raises ArgumentError, @ui.error do
        @cmd.handle_options %w[-p=foo.bar.com]
      end

      assert_match "Invalid uri scheme for =foo.bar.com\nPreface URLs with one of [\"http://\", \"https://\", \"file://\", \"s3://\"]", e.message
    end
  end

  def test_execute_bad_source
    spec_fetcher

    # This is needed because we need to exercise the cache path
    # within SpecFetcher
    path = File.join Gem.spec_cache_dir, "not-there.nothing%80", "latest_specs.4.8"

    FileUtils.mkdir_p File.dirname(path)

    File.open path, "w" do |f|
      f.write Marshal.dump([])
    end

    Gem.sources.replace ["http://not-there.nothing"]

    @cmd.options[:args] = %w[nonexistent]

    use_ui @ui do
      e = assert_raises Gem::MockGemUi::TermError do
        @cmd.execute
      end
      assert_equal 2, e.exit_code
    end

    errs = @ui.error.split("\n")

    assert_match(/ould not find a valid gem 'nonexistent'/, errs.shift)
    assert_match(%r!Unable to download data from http://not-there.nothing!, errs.shift)
  end

  def test_execute_nonexistent_hint_disabled
    misspelled = "nonexistent_with_hint"
    correctly_spelled = "non_existent_with_hint"

    spec_fetcher do |fetcher|
      fetcher.spec correctly_spelled, 2
    end

    @cmd.options[:args] = [misspelled]
    @cmd.options[:suggest_alternate] = false

    use_ui @ui do
      e = assert_raises Gem::MockGemUi::TermError do
        @cmd.execute
      end

      assert_equal 2, e.exit_code
    end

    expected = <<-EXPECTED
ERROR:  Could not find a valid gem 'nonexistent_with_hint' (>= 0) in any repository
    EXPECTED

    assert_equal expected, @ui.error
  end

  def test_execute_nonexistent_with_hint
    misspelled = "nonexistent_with_hint"
    correctly_spelled = "non_existent_with_hint"

    spec_fetcher do |fetcher|
      fetcher.spec correctly_spelled, 2
    end

    @cmd.options[:args] = [misspelled]

    use_ui @ui do
      e = assert_raises Gem::MockGemUi::TermError do
        @cmd.execute
      end

      assert_equal 2, e.exit_code
    end

    expected = "ERROR:  Could not find a valid gem 'nonexistent_with_hint' (>= 0) in any repository
ERROR:  Possible alternatives: non_existent_with_hint
"

    assert_equal expected, @ui.error
  end

  def test_execute_nonexistent_with_dashes
    misspelled = "non-existent_with-hint"
    correctly_spelled = "nonexistent-with_hint"

    spec_fetcher do |fetcher|
      fetcher.download correctly_spelled, 2
    end

    @cmd.options[:args] = [misspelled]

    use_ui @ui do
      e = assert_raises Gem::MockGemUi::TermError do
        @cmd.execute
      end

      assert_equal 2, e.exit_code
    end

    expected = [
      "ERROR:  Could not find a valid gem 'non-existent_with-hint' (>= 0) in any repository",
      "ERROR:  Possible alternatives: nonexistent-with_hint"
    ]

    output = @ui.error.split "\n"

    assert_equal expected, output
  end

  def test_execute_conflicting_install_options
    @cmd.options[:user_install] = true
    @cmd.options[:install_dir] = "whatever"

    use_ui @ui do
      assert_raises Gem::MockGemUi::TermError do
        @cmd.execute
      end
    end

    expected = "ERROR:  Use --install-dir or --user-install but not both\n"

    assert_equal expected, @ui.error
  end

  def test_execute_prerelease_skipped_when_no_flag_set
    spec_fetcher do |fetcher|
      fetcher.gem 'a', 1
      fetcher.gem 'a', '3.a'
    end

    @cmd.options[:prerelease] = false
    @cmd.options[:args] = %w[a]

    use_ui @ui do
      assert_raises Gem::MockGemUi::SystemExitException, @ui.error do
        @cmd.execute
      end
    end

    assert_equal %w[a-1], @cmd.installed_specs.map { |spec| spec.full_name }
  end

  def test_execute_prerelease_wins_over_previous_ver
    spec_fetcher do |fetcher|
      fetcher.download 'a', 1
      fetcher.download 'a', '2.a'
    end

    @cmd.options[:prerelease] = true
    @cmd.options[:args] = %w[a]

    use_ui @ui do
      assert_raises Gem::MockGemUi::SystemExitException, @ui.error do
        @cmd.execute
      end
    end

    assert_equal %w[a-2.a], @cmd.installed_specs.map { |spec| spec.full_name }
  end

  def test_execute_with_version_specified_by_colon
    spec_fetcher do |fetcher|
      fetcher.download 'a', 1
      fetcher.download 'a', 2
    end

    @cmd.options[:args] = %w[a:1]

    use_ui @ui do
      assert_raises Gem::MockGemUi::SystemExitException, @ui.error do
        @cmd.execute
      end
    end

    assert_equal %w[a-1], @cmd.installed_specs.map { |spec| spec.full_name }
  end

  def test_execute_prerelease_skipped_when_non_pre_available
    spec_fetcher do |fetcher|
      fetcher.gem 'a', '2.pre'
      fetcher.gem 'a', 2
    end

    @cmd.options[:prerelease] = true
    @cmd.options[:args] = %w[a]

    use_ui @ui do
      assert_raises Gem::MockGemUi::SystemExitException, @ui.error do
        @cmd.execute
      end
    end

    assert_equal %w[a-2], @cmd.installed_specs.map { |spec| spec.full_name }
  end

  def test_execute_rdoc
    specs = spec_fetcher do |fetcher|
      fetcher.gem 'a', 2
    end

    Gem.done_installing(&Gem::RDoc.method(:generation_hook))

    @cmd.options[:document] = %w[rdoc ri]
    @cmd.options[:domain] = :local

    a2 = specs['a-2']
    FileUtils.mv a2.cache_file, @tempdir

    @cmd.options[:args] = %w[a]

    use_ui @ui do
      # Don't use Dir.chdir with a block, it warnings a lot because
      # of a downstream Dir.chdir with a block
      old = Dir.getwd

      begin
        Dir.chdir @tempdir
        assert_raises Gem::MockGemUi::SystemExitException, @ui.error do
          @cmd.execute
        end
      ensure
        Dir.chdir old
      end
    end

    wait_for_child_process_to_exit

    assert_path_exists File.join(a2.doc_dir, 'ri')
    assert_path_exists File.join(a2.doc_dir, 'rdoc')
  end

  def test_execute_rdoc_with_path
    specs = spec_fetcher do |fetcher|
      fetcher.gem 'a', 2
    end

    Gem.done_installing(&Gem::RDoc.method(:generation_hook))

    @cmd.options[:document] = %w[rdoc ri]
    @cmd.options[:domain] = :local
    @cmd.options[:install_dir] = 'whatever'

    a2 = specs['a-2']
    FileUtils.mv a2.cache_file, @tempdir

    @cmd.options[:args] = %w[a]

    use_ui @ui do
      # Don't use Dir.chdir with a block, it warnings a lot because
      # of a downstream Dir.chdir with a block
      old = Dir.getwd

      begin
        Dir.chdir @tempdir
        assert_raises Gem::MockGemUi::SystemExitException, @ui.error do
          @cmd.execute
        end
      ensure
        Dir.chdir old
      end
    end

    wait_for_child_process_to_exit

    assert_path_exists 'whatever/doc/a-2', 'documentation not installed'
  end

  def test_execute_saves_build_args
    specs = spec_fetcher do |fetcher|
      fetcher.gem 'a', 2
    end

    args = %w!--with-awesome=true --more-awesome=yes!

    Gem::Command.build_args = args

    a2 = specs['a-2']
    FileUtils.mv a2.cache_file, @tempdir

    @cmd.options[:domain] = :local

    @cmd.options[:args] = %w[a]

    use_ui @ui do
      # Don't use Dir.chdir with a block, it warnings a lot because
      # of a downstream Dir.chdir with a block
      old = Dir.getwd

      begin
        Dir.chdir @tempdir
        assert_raises Gem::MockGemUi::SystemExitException, @ui.error do
          @cmd.execute
        end
      ensure
        Dir.chdir old
      end
    end

    path = a2.build_info_file
    assert_path_exists path

    assert_equal args, a2.build_args
  end


  def test_execute_remote
    spec_fetcher do |fetcher|
      fetcher.gem 'a', 2
    end

    @cmd.options[:args] = %w[a]

    use_ui @ui do
      assert_raises Gem::MockGemUi::SystemExitException, @ui.error do
        @cmd.execute
      end
    end

    assert_equal %w[a-2], @cmd.installed_specs.map { |spec| spec.full_name }

    assert_match "1 gem installed", @ui.output
  end

  def test_execute_with_invalid_gem_file
    FileUtils.touch("a.gem")

    spec_fetcher do |fetcher|
      fetcher.gem 'a', 2
    end

    @cmd.options[:args] = %w[a]

    use_ui @ui do
      assert_raises Gem::MockGemUi::SystemExitException, @ui.error do
        @cmd.execute
      end
    end

    assert_equal %w[a-2], @cmd.installed_specs.map { |spec| spec.full_name }

    assert_match "1 gem installed", @ui.output
  end

  def test_execute_remote_ignores_files
    specs = spec_fetcher do |fetcher|
      fetcher.gem 'a', 1
      fetcher.gem 'a', 2
    end

    @cmd.options[:domain] = :remote

    a1 = specs['a-1']
    a2 = specs['a-2']

    FileUtils.mv a2.cache_file, @tempdir

    @fetcher.data["#{@gem_repo}gems/#{a2.file_name}"] =
      read_binary(a1.cache_file)

    @cmd.options[:args] = [a2.name]

    gemdir     = File.join @gemhome, 'specifications'

    a2_gemspec = File.join(gemdir, "a-2.gemspec")
    a1_gemspec = File.join(gemdir, "a-1.gemspec")

    FileUtils.rm_rf a1_gemspec
    FileUtils.rm_rf a2_gemspec

    start = Dir["#{gemdir}/*"]

    use_ui @ui do
      Dir.chdir @tempdir do
        assert_raises Gem::MockGemUi::SystemExitException, @ui.error do
          @cmd.execute
        end
      end
    end

    assert_equal %w[a-1], @cmd.installed_specs.map { |spec| spec.full_name }

    assert_match "1 gem installed", @ui.output

    fin = Dir["#{gemdir}/*"]

    assert_equal [a1_gemspec], fin - start
  end

  def test_execute_two
    specs = spec_fetcher do |fetcher|
      fetcher.gem 'a', 2
      fetcher.gem 'b', 2
    end

    FileUtils.mv specs['a-2'].cache_file, @tempdir
    FileUtils.mv specs['b-2'].cache_file, @tempdir

    @cmd.options[:domain] = :local

    @cmd.options[:args] = %w[a b]

    use_ui @ui do
      orig_dir = Dir.pwd
      begin
        Dir.chdir @tempdir
        assert_raises Gem::MockGemUi::SystemExitException, @ui.error do
          @cmd.execute
        end
      ensure
        Dir.chdir orig_dir
      end
    end

    assert_equal %w[a-2 b-2], @cmd.installed_specs.map { |spec| spec.full_name }

    assert_match "2 gems installed", @ui.output
  end

  def test_execute_two_version
    @cmd.options[:args] = %w[a b]
    @cmd.options[:version] = Gem::Requirement.new("> 1")

    use_ui @ui do
      e = assert_raises Gem::MockGemUi::TermError do
        @cmd.execute
      end

      assert_equal 1, e.exit_code
    end

    assert_empty @cmd.installed_specs

    msg = "ERROR:  Can't use --version with multiple gems. You can specify multiple gems with" \
      " version requirements using `gem install 'my_gem:1.0.0' 'my_other_gem:~>2.0.0'`"

    assert_empty @ui.output
    assert_equal msg, @ui.error.chomp
  end

  def test_execute_two_version_specified_by_colon
    spec_fetcher do |fetcher|
      fetcher.gem 'a', 1
      fetcher.gem 'a', 2
      fetcher.gem 'b', 1
      fetcher.gem 'b', 2
    end

    @cmd.options[:args] = %w[a:1 b:1]

    use_ui @ui do
      assert_raises Gem::MockGemUi::SystemExitException, @ui.error do
        @cmd.execute
      end
    end

    assert_equal %w[a-1 b-1], @cmd.installed_specs.map { |spec| spec.full_name }
  end

  def test_execute_conservative
    spec_fetcher do |fetcher|
      fetcher.download 'b', 2

      fetcher.gem 'a', 2
    end

    @cmd.options[:conservative] = true

    @cmd.options[:args] = %w[a b]

    use_ui @ui do
      orig_dir = Dir.pwd
      begin
        Dir.chdir @tempdir
        assert_raises Gem::MockGemUi::SystemExitException do
          @cmd.execute
        end
      ensure
        Dir.chdir orig_dir
      end
    end

    assert_equal %w[b-2], @cmd.installed_specs.map { |spec| spec.full_name }

    assert_equal "", @ui.error
    assert_match "1 gem installed", @ui.output
  end

  def test_install_gem_ignore_dependencies_both
    done_installing = false
    Gem.done_installing do
      done_installing = true
    end

    spec = util_spec 'a', 2

    util_build_gem spec

    FileUtils.mv spec.cache_file, @tempdir

    @cmd.options[:ignore_dependencies] = true

    @cmd.install_gem 'a', '>= 0'

    assert_equal %w[a-2], @cmd.installed_specs.map { |s| s.full_name }

    assert done_installing, 'documentation was not generated'
  end

  def test_install_gem_ignore_dependencies_remote
    spec_fetcher do |fetcher|
      fetcher.gem 'a', 2
    end

    @cmd.options[:ignore_dependencies] = true

    @cmd.install_gem 'a', '>= 0'

    assert_equal %w[a-2], @cmd.installed_specs.map { |spec| spec.full_name }
  end

  def test_install_gem_ignore_dependencies_specific_file
    spec = util_spec 'a', 2

    util_build_gem spec

    FileUtils.mv spec.cache_file, @tempdir

    @cmd.options[:ignore_dependencies] = true

    @cmd.install_gem File.join(@tempdir, spec.file_name), nil

    assert_equal %w[a-2], @cmd.installed_specs.map { |s| s.full_name }
  end

  def test_parses_requirement_from_gemname
    spec_fetcher do |fetcher|
      fetcher.gem 'a', 2
      fetcher.gem 'b', 2
    end

    @cmd.options[:domain] = :local

    req = "a:10.0"

    @cmd.options[:args] = [req]

    e = nil
    use_ui @ui do
      orig_dir = Dir.pwd
      begin
        Dir.chdir @tempdir
        e = assert_raises Gem::MockGemUi::TermError do
          @cmd.execute
        end
      ensure
        Dir.chdir orig_dir
      end
    end

    assert_equal 2, e.exit_code
    assert_match %r!Could not find a valid gem 'a' \(= 10.0\)!, @ui.error
  end

  def test_show_errors_on_failure
    Gem.sources.replace ["http://not-there.nothing"]

    @cmd.options[:args] = ["blah"]

    e = nil
    use_ui @ui do
      orig_dir = Dir.pwd
      begin
        Dir.chdir @tempdir
        e = assert_raises Gem::MockGemUi::TermError do
          @cmd.execute
        end
      ensure
        Dir.chdir orig_dir
      end
    end

    assert_equal 2, e.exit_code

    assert_match 'Unable to download data', @ui.error
  end

  def test_show_source_problems_even_on_success
    spec_fetcher do |fetcher|
      fetcher.download 'a', 2
    end

    Gem.sources << "http://nonexistent.example"

    @cmd.options[:args] = %w[a]

    use_ui @ui do
      assert_raises Gem::MockGemUi::SystemExitException, @ui.error do
        @cmd.execute
      end
    end

    assert_equal %w[a-2], @cmd.installed_specs.map { |spec| spec.full_name }

    assert_match "1 gem installed", @ui.output

    e = @ui.error

    x = "WARNING:  Unable to pull data from 'http://nonexistent.example': no data for http://nonexistent.example/specs.4.8.gz (http://nonexistent.example/specs.4.8.gz)\n"
    assert_equal x, e
  end

  def test_execute_uses_from_a_gemdeps
    spec_fetcher do |fetcher|
      fetcher.gem 'a', 2
    end

    File.open @gemdeps, "w" do |f|
      f << "gem 'a'"
    end

    @cmd.options[:gemdeps] = @gemdeps

    use_ui @ui do
      assert_raises Gem::MockGemUi::SystemExitException, @ui.error do
        @cmd.execute
      end
    end

    assert_equal %w[], @cmd.installed_specs.map { |spec| spec.full_name }

    assert_match "Using a (2)", @ui.output
    assert File.exist?("#{@gemdeps}.lock")
  end

  def test_execute_uses_from_a_gemdeps_with_no_lock
    spec_fetcher do |fetcher|
      fetcher.gem 'a', 2
    end

    File.open @gemdeps, "w" do |f|
      f << "gem 'a'"
    end

    @cmd.handle_options %w[--no-lock]
    @cmd.options[:gemdeps] = @gemdeps

    use_ui @ui do
      assert_raises Gem::MockGemUi::SystemExitException, @ui.error do
        @cmd.execute
      end
    end

    assert_equal %w[], @cmd.installed_specs.map { |spec| spec.full_name }

    assert_match "Using a (2)", @ui.output
    assert !File.exist?("#{@gemdeps}.lock")
  end

  def test_execute_installs_from_a_gemdeps_with_conservative
    spec_fetcher do |fetcher|
      fetcher.download 'a', 2
      fetcher.gem 'a', 1
    end

    File.open @gemdeps, "w" do |f|
      f << "gem 'a'"
    end

    @cmd.handle_options %w[--conservative]
    @cmd.options[:gemdeps] = @gemdeps

    use_ui @ui do
      assert_raises Gem::MockGemUi::SystemExitException, @ui.error do
        @cmd.execute
      end
    end

    assert_equal %w[], @cmd.installed_specs.map { |spec| spec.full_name }

    assert_match "Using a (1)", @ui.output
  end

  def test_execute_installs_from_a_gemdeps
    spec_fetcher do |fetcher|
      fetcher.download 'a', 2
    end

    File.open @gemdeps, "w" do |f|
      f << "gem 'a'"
    end

    @cmd.options[:gemdeps] = @gemdeps

    use_ui @ui do
      assert_raises Gem::MockGemUi::SystemExitException, @ui.error do
        @cmd.execute
      end
    end

    assert_equal %w[a-2], @cmd.installed_specs.map { |spec| spec.full_name }

    assert_match "Installing a (2)", @ui.output
  end

  def test_execute_installs_deps_a_gemdeps
    spec_fetcher do |fetcher|
      fetcher.download 'q', '1.0'
      fetcher.download 'r', '2.0', 'q' => nil
    end

    File.open @gemdeps, "w" do |f|
      f << "gem 'r'"
    end

    @cmd.options[:gemdeps] = @gemdeps

    use_ui @ui do
      assert_raises Gem::MockGemUi::SystemExitException, @ui.error do
        @cmd.execute
      end
    end

    names = @cmd.installed_specs.map { |spec| spec.full_name }

    assert_equal %w[q-1.0 r-2.0], names

    assert_match "Installing q (1.0)", @ui.output
    assert_match "Installing r (2.0)", @ui.output
  end

  def test_execute_uses_deps_a_gemdeps
    spec_fetcher do |fetcher|
      fetcher.download 'r', '2.0', 'q' => nil

      fetcher.spec 'q', '1.0'
    end

    File.open @gemdeps, "w" do |f|
      f << "gem 'r'"
    end

    @cmd.options[:gemdeps] = @gemdeps

    use_ui @ui do
      assert_raises Gem::MockGemUi::SystemExitException, @ui.error do
        @cmd.execute
      end
    end

    names = @cmd.installed_specs.map { |spec| spec.full_name }

    assert_equal %w[r-2.0], names

    assert_match "Using q (1.0)",      @ui.output
    assert_match "Installing r (2.0)", @ui.output
  end

  def test_execute_installs_deps_a_gemdeps_into_a_path
    spec_fetcher do |fetcher|
      fetcher.download 'q', '1.0'
      fetcher.download 'r', '2.0', 'q' => nil
    end

    File.open @gemdeps, "w" do |f|
      f << "gem 'r'"
    end

    @cmd.options[:install_dir] = "gf-path"
    @cmd.options[:gemdeps] = @gemdeps

    use_ui @ui do
      assert_raises Gem::MockGemUi::SystemExitException, @ui.error do
        @cmd.execute
      end
    end

    names = @cmd.installed_specs.map { |spec| spec.full_name }

    assert_equal %w[q-1.0 r-2.0], names

    assert_match "Installing q (1.0)", @ui.output
    assert_match "Installing r (2.0)", @ui.output

    assert File.file?("gf-path/specifications/q-1.0.gemspec"), "not installed"
    assert File.file?("gf-path/specifications/r-2.0.gemspec"), "not installed"
  end

  def test_execute_with_gemdeps_path_ignores_system
    specs = spec_fetcher do |fetcher|
      fetcher.download 'q', '1.0'
      fetcher.download 'r', '2.0', 'q' => nil
    end

    install_specs specs['q-1.0']

    File.open @gemdeps, "w" do |f|
      f << "gem 'r'"
    end

    @cmd.options[:install_dir] = "gf-path"
    @cmd.options[:gemdeps] = @gemdeps

    use_ui @ui do
      assert_raises Gem::MockGemUi::SystemExitException, @ui.error do
        @cmd.execute
      end
    end

    names = @cmd.installed_specs.map { |spec| spec.full_name }

    assert_equal %w[q-1.0 r-2.0], names

    assert_match "Installing q (1.0)", @ui.output
    assert_match "Installing r (2.0)", @ui.output

    assert File.file?("gf-path/specifications/q-1.0.gemspec"), "not installed"
    assert File.file?("gf-path/specifications/r-2.0.gemspec"), "not installed"
  end

  def test_execute_uses_deps_a_gemdeps_with_a_path
    specs = spec_fetcher do |fetcher|
      fetcher.gem 'q', '1.0'
      fetcher.gem 'r', '2.0', 'q' => nil
    end

    i = Gem::Installer.at specs['q-1.0'].cache_file, :install_dir => "gf-path"
    i.install

    assert File.file?("gf-path/specifications/q-1.0.gemspec"), "not installed"

    File.open @gemdeps, "w" do |f|
      f << "gem 'r'"
    end

    @cmd.options[:install_dir] = "gf-path"
    @cmd.options[:gemdeps] = @gemdeps

    use_ui @ui do
      assert_raises Gem::MockGemUi::SystemExitException, @ui.error do
        @cmd.execute
      end
    end

    names = @cmd.installed_specs.map { |spec| spec.full_name }

    assert_equal %w[r-2.0], names

    assert_match "Using q (1.0)", @ui.output
    assert_match "Installing r (2.0)", @ui.output
  end

  def test_handle_options_file
    FileUtils.touch 'Gemfile'

    @cmd.handle_options %w[-g Gemfile]

    assert_equal 'Gemfile', @cmd.options[:gemdeps]

    FileUtils.rm 'Gemfile'

    FileUtils.touch 'gem.deps.rb'

    @cmd.handle_options %w[--file gem.deps.rb]

    assert_equal 'gem.deps.rb', @cmd.options[:gemdeps]

    FileUtils.rm 'gem.deps.rb'

    FileUtils.touch 'Isolate'

    @cmd.handle_options %w[-g]

    assert_equal 'Isolate', @cmd.options[:gemdeps]

    FileUtils.touch 'Gemfile'

    @cmd.handle_options %w[-g]

    assert_equal 'Gemfile', @cmd.options[:gemdeps]

    FileUtils.touch 'gem.deps.rb'

    @cmd.handle_options %w[-g]

    assert_equal 'gem.deps.rb', @cmd.options[:gemdeps]
  end

  def test_handle_options_suggest
    assert @cmd.options[:suggest_alternate]

    @cmd.handle_options %w[--no-suggestions]

    refute @cmd.options[:suggest_alternate]

    @cmd.handle_options %w[--suggestions]

    assert @cmd.options[:suggest_alternate]
  end

  def test_handle_options_without
    @cmd.handle_options %w[--without test]

    assert_equal [:test], @cmd.options[:without_groups]

    @cmd.handle_options %w[--without test,development]

    assert_equal [:test, :development], @cmd.options[:without_groups]
  end

end
