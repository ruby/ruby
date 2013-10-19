require 'rubygems/test_case'
require 'rubygems/commands/install_command'
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
  end

  def test_execute_exclude_prerelease
    util_setup_fake_fetcher :prerelease
    util_setup_spec_fetcher

    @fetcher.data["#{@gem_repo}gems/#{@a2.file_name}"] =
      read_binary(@a2.cache_file)
    @fetcher.data["#{@gem_repo}gems/#{@a2_pre.file_name}"] =
      read_binary(@a2_pre.cache_file)

    @cmd.options[:args] = [@a2.name]

    use_ui @ui do
      assert_raises Gem::MockGemUi::SystemExitException, @ui.error do
        @cmd.execute
      end
    end

    assert_equal %w[a-2], @cmd.installed_specs.map { |spec| spec.full_name }
  end

  def test_execute_explicit_version_includes_prerelease
    util_setup_fake_fetcher :prerelease
    util_setup_spec_fetcher

    @fetcher.data["#{@gem_repo}gems/#{@a2.file_name}"] =
      read_binary(@a2.cache_file)
    @fetcher.data["#{@gem_repo}gems/#{@a2_pre.file_name}"] =
      read_binary(@a2_pre.cache_file)

    @cmd.handle_options [@a2_pre.name, '--version', @a2_pre.version.to_s,
                         "--no-ri", "--no-rdoc"]
    assert @cmd.options[:prerelease]
    assert @cmd.options[:version].satisfied_by?(@a2_pre.version)

    use_ui @ui do
      assert_raises Gem::MockGemUi::SystemExitException, @ui.error do
        @cmd.execute
      end
    end

    assert_equal %w[a-2.a], @cmd.installed_specs.map { |spec| spec.full_name }
  end

  def test_execute_local
    util_setup_fake_fetcher
    @cmd.options[:domain] = :local

    FileUtils.mv @a2.cache_file, @tempdir

    @cmd.options[:args] = [@a2.name]

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

  def test_execute_no_user_install
    skip 'skipped on MS Windows (chmod has no effect)' if win_platform?

    util_setup_fake_fetcher
    @cmd.options[:user_install] = false

    FileUtils.mv @a2.cache_file, @tempdir

    @cmd.options[:args] = [@a2.name]

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
    util_setup_fake_fetcher
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
    util_setup_fake_fetcher
    util_setup_spec_fetcher

    @cmd.options[:args] = %w[nonexistent]

    use_ui @ui do
      e = assert_raises Gem::MockGemUi::TermError do
        @cmd.execute
      end
      assert_equal 2, e.exit_code
    end

    assert_match(/ould not find a valid gem 'nonexistent'/, @ui.error)
  end

  def test_execute_bad_source
    util_setup_fake_fetcher
    util_setup_spec_fetcher

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

  def test_execute_nonexistent_with_hint
    misspelled = "nonexistent_with_hint"
    correctly_spelled = "non_existent_with_hint"

    util_setup_fake_fetcher
    util_setup_spec_fetcher quick_spec(correctly_spelled, '2')

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

    util_setup_fake_fetcher
    util_setup_spec_fetcher quick_spec(correctly_spelled, '2')

    @cmd.options[:args] = [misspelled]

    use_ui @ui do
      e = assert_raises Gem::MockGemUi::TermError do
        @cmd.execute
      end

      assert_equal 2, e.exit_code
    end

    expected = ["ERROR:  Could not find a valid gem 'non-existent_with-hint' (>= 0) in any repository", "ERROR:  Possible alternatives: nonexistent-with_hint"]

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
    util_setup_fake_fetcher :prerelease
    util_clear_gems
    util_setup_spec_fetcher @a1, @a2_pre

    @fetcher.data["#{@gem_repo}gems/#{@a1.file_name}"] =
      read_binary(@a1.cache_file)
    @fetcher.data["#{@gem_repo}gems/#{@a2_pre.file_name}"] =
      read_binary(@a2_pre.cache_file)

    @cmd.options[:prerelease] = false
    @cmd.options[:args] = [@a2_pre.name]

    use_ui @ui do
      assert_raises Gem::MockGemUi::SystemExitException, @ui.error do
        @cmd.execute
      end
    end

    assert_equal %w[a-1], @cmd.installed_specs.map { |spec| spec.full_name }
  end

  def test_execute_prerelease_wins_over_previous_ver
    util_setup_fake_fetcher :prerelease
    util_clear_gems
    util_setup_spec_fetcher @a1, @a2_pre

    @fetcher.data["#{@gem_repo}gems/#{@a1.file_name}"] =
      read_binary(@a1.cache_file)
    @fetcher.data["#{@gem_repo}gems/#{@a2_pre.file_name}"] =
      read_binary(@a2_pre.cache_file)

    @cmd.options[:prerelease] = true
    @cmd.options[:args] = [@a2_pre.name]

    use_ui @ui do
      assert_raises Gem::MockGemUi::SystemExitException, @ui.error do
        @cmd.execute
      end
    end

    assert_equal %w[a-2.a], @cmd.installed_specs.map { |spec| spec.full_name }
  end

  def test_execute_prerelease_skipped_when_non_pre_available
    util_setup_fake_fetcher :prerelease
    util_clear_gems
    util_setup_spec_fetcher @a2, @a2_pre

    @fetcher.data["#{@gem_repo}gems/#{@a2.file_name}"] =
      read_binary(@a2.cache_file)
    @fetcher.data["#{@gem_repo}gems/#{@a2_pre.file_name}"] =
      read_binary(@a2_pre.cache_file)

    @cmd.options[:prerelease] = true
    @cmd.options[:args] = [@a2_pre.name]

    use_ui @ui do
      assert_raises Gem::MockGemUi::SystemExitException, @ui.error do
        @cmd.execute
      end
    end

    assert_equal %w[a-2], @cmd.installed_specs.map { |spec| spec.full_name }
  end

  def test_execute_rdoc
    util_setup_fake_fetcher

    Gem.done_installing(&Gem::RDoc.method(:generation_hook))

    @cmd.options[:document] = %w[rdoc ri]
    @cmd.options[:domain] = :local

    FileUtils.mv @a2.cache_file, @tempdir

    @cmd.options[:args] = [@a2.name]

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

    assert_path_exists File.join(@a2.doc_dir, 'ri')
    assert_path_exists File.join(@a2.doc_dir, 'rdoc')
  end

  def test_execute_saves_build_args
    util_setup_fake_fetcher

    args = %w!--with-awesome=true --more-awesome=yes!

    Gem::Command.build_args = args

    @cmd.options[:domain] = :local

    FileUtils.mv @a2.cache_file, @tempdir

    @cmd.options[:args] = [@a2.name]

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

    path = @a2.build_info_file
    assert_path_exists path

    assert_equal args, @a2.build_args
  end


  def test_execute_remote
    util_setup_fake_fetcher
    util_setup_spec_fetcher

    @fetcher.data["#{@gem_repo}gems/#{@a2.file_name}"] =
      read_binary(@a2.cache_file)

    @cmd.options[:args] = [@a2.name]

    use_ui @ui do
      assert_raises Gem::MockGemUi::SystemExitException, @ui.error do
        @cmd.execute
      end
    end

    assert_equal %w[a-2], @cmd.installed_specs.map { |spec| spec.full_name }

    assert_match "1 gem installed", @ui.output
  end

  def test_execute_remote_ignores_files
    util_setup_fake_fetcher
    util_setup_spec_fetcher

    @cmd.options[:domain] = :remote

    FileUtils.mv @a2.cache_file, @tempdir

    @fetcher.data["#{@gem_repo}gems/#{@a2.file_name}"] =
      read_binary(@a1.cache_file)

    @cmd.options[:args] = [@a2.name]

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
    util_setup_fake_fetcher
    @cmd.options[:domain] = :local

    FileUtils.mv @a2.cache_file, @tempdir

    FileUtils.mv @b2.cache_file, @tempdir

    @cmd.options[:args] = [@a2.name, @b2.name]

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

    msg = "ERROR:  Can't use --version w/ multiple gems. Use name:ver instead."

    assert_empty @ui.output
    assert_equal msg, @ui.error.chomp
  end

  def test_execute_conservative
    util_setup_fake_fetcher
    util_setup_spec_fetcher

    @fetcher.data["#{@gem_repo}gems/#{@b2.file_name}"] =
      read_binary(@b2.cache_file)

    uninstall_gem(@b2)

    @cmd.options[:conservative] = true

    @cmd.options[:args] = [@a2.name, @b2.name]

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

  def test_parses_requirement_from_gemname
    util_setup_fake_fetcher
    @cmd.options[:domain] = :local

    FileUtils.mv @a2.cache_file, @tempdir

    FileUtils.mv @b2.cache_file, @tempdir

    req = "#{@a2.name}:10.0"

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
    assert_match %r!Could not find a valid gem 'blah' \(>= 0\)!, @ui.error
    assert_match %r!Unable to download data from http://not-there\.nothing!, @ui.error
  end

  def test_show_source_problems_even_on_success
    util_setup_fake_fetcher
    util_setup_spec_fetcher

    Gem.sources << "http://nonexistent.example"

    @fetcher.data["#{@gem_repo}gems/#{@a2.file_name}"] =
      read_binary(@a2.cache_file)

    @cmd.options[:args] = [@a2.name]

    use_ui @ui do
      assert_raises Gem::MockGemUi::SystemExitException, @ui.error do
        @cmd.execute
      end
    end

    assert_equal %w[a-2], @cmd.installed_specs.map { |spec| spec.full_name }

    assert_match "1 gem installed", @ui.output

    e = @ui.error

    x = "WARNING:  Unable to pull data from 'http://nonexistent.example': no data for http://nonexistent.example/latest_specs.4.8.gz (http://nonexistent.example/latest_specs.4.8.gz)\n"
    assert_equal x, e
  end

  def test_execute_uses_from_a_gemdeps
    util_setup_fake_fetcher
    util_setup_spec_fetcher

    @fetcher.data["#{@gem_repo}gems/#{@a2.file_name}"] =
      read_binary(@a2.cache_file)

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
  end

  def test_execute_installs_from_a_gemdeps
    util_setup_fake_fetcher
    util_setup_spec_fetcher @a2
    util_clear_gems

    @fetcher.data["#{@gem_repo}gems/#{@a2.file_name}"] =
      read_binary(@a2.cache_file)

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
    q, q_gem = util_gem 'q', '1.0'
    r, r_gem = util_gem 'r', '2.0', 'q' => nil

    util_setup_fake_fetcher
    util_setup_spec_fetcher q, r
    util_clear_gems

    add_to_fetcher q, q_gem
    add_to_fetcher r, r_gem

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
    q, _     = util_gem 'q', '1.0'
    r, r_gem = util_gem 'r', '2.0', 'q' => nil

    util_setup_fake_fetcher
    util_setup_spec_fetcher q, r
    util_clear_gems

    add_to_fetcher r, r_gem

    Gem::Specification.add_specs q

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
    q, q_gem = util_gem 'q', '1.0'
    r, r_gem = util_gem 'r', '2.0', 'q' => nil

    util_setup_fake_fetcher
    util_setup_spec_fetcher q, r
    util_clear_gems

    add_to_fetcher q, q_gem
    add_to_fetcher r, r_gem

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
    q, q_gem = util_gem 'q', '1.0'
    r, r_gem = util_gem 'r', '2.0', 'q' => nil

    util_setup_fake_fetcher
    util_setup_spec_fetcher q, r
    util_clear_gems

    add_to_fetcher q, q_gem
    add_to_fetcher r, r_gem

    Gem::Specification.add_specs q

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
    q, q_gem = util_gem 'q', '1.0'
    r, r_gem = util_gem 'r', '2.0', 'q' => nil

    util_setup_fake_fetcher
    util_setup_spec_fetcher q, r
    util_clear_gems

    add_to_fetcher r, r_gem

    i = Gem::Installer.new q_gem, :install_dir => "gf-path"
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
    @cmd.handle_options %w[-g Gemfile]

    assert_equal 'Gemfile', @cmd.options[:gemdeps]

    @cmd.handle_options %w[--file gem.deps.rb]

    assert_equal 'gem.deps.rb', @cmd.options[:gemdeps]

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

end
