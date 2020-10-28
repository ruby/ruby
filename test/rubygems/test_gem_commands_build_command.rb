# frozen_string_literal: true
require 'rubygems/test_case'
require 'rubygems/commands/build_command'
require 'rubygems/package'

class TestGemCommandsBuildCommand < Gem::TestCase
  CERT_FILE = cert_path 'public3072'
  SIGNING_KEY = key_path 'private3072'

  EXPIRED_CERT_FILE = cert_path 'expired'
  PRIVATE_KEY_FILE  = key_path 'private'

  def setup
    super

    readme_file = File.join(@tempdir, 'README.md')

    begin
      umask_orig = File.umask(2)
      File.open readme_file, 'w' do |f|
        f.write 'My awesome gem'
      end
    ensure
      File.umask(umask_orig)
    end

    @gem = util_spec 'some_gem' do |s|
      s.license = 'AGPL-3.0'
      s.files = ['README.md']
    end

    @cmd = Gem::Commands::BuildCommand.new
  end

  def test_handle_options
    @cmd.handle_options %w[--force --strict]

    assert @cmd.options[:force]
    assert @cmd.options[:strict]
    assert @cmd.handles?(%W[--platform #{Gem::Platform.local}])
    assert_includes Gem.platforms, Gem::Platform.local
  end

  def test_options_filename
    gemspec_file = File.join(@tempdir, @gem.spec_name)

    File.open gemspec_file, 'w' do |gs|
      gs.write @gem.to_ruby
    end

    @cmd.options[:args] = [gemspec_file]
    @cmd.options[:output] = "test.gem"

    use_ui @ui do
      Dir.chdir @tempdir do
        @cmd.execute
      end
    end

    file = File.join(@tempdir, File::SEPARATOR, "test.gem")
    assert File.exist?(file)

    output = @ui.output.split "\n"
    assert_equal "  Successfully built RubyGem", output.shift
    assert_equal "  Name: some_gem", output.shift
    assert_equal "  Version: 2", output.shift
    assert_equal "  File: test.gem", output.shift
    assert_equal [], output
  end

  def test_handle_options_defaults
    @cmd.handle_options []

    refute @cmd.options[:force]
    refute @cmd.options[:strict]
    assert_nil @cmd.options[:output]
  end

  def test_execute
    gemspec_file = File.join(@tempdir, @gem.spec_name)

    File.open gemspec_file, 'w' do |gs|
      gs.write @gem.to_ruby
    end

    @cmd.options[:args] = [gemspec_file]

    util_test_build_gem @gem
  end

  def test_execute_platform
    gemspec_file = File.join(@tempdir, @gem.spec_name)

    File.open gemspec_file, 'w' do |gs|
      gs.write @gem.to_ruby
    end

    @cmd.options[:args] = [gemspec_file]

    platforms = Gem.platforms.dup
    begin
      Gem.platforms << Gem::Platform.new("java")

      spec = util_test_build_gem @gem, suffix: "java"
    ensure
      Gem.platforms.replace(platforms)
    end
    assert_match spec.platform, "java"
  end

  def test_execute_bad_name
    [".", "-", "_"].each do |special_char|
      gem = util_spec 'some_gem_with_bad_name' do |s|
        s.name = "#{special_char}bad_gem_name"
        s.license = 'AGPL-3.0'
        s.files = ['README.md']
      end

      gemspec_file = File.join(@tempdir, gem.spec_name)

      File.open gemspec_file, 'w' do |gs|
        gs.write gem.to_ruby
      end

      @cmd.options[:args] = [gemspec_file]

      use_ui @ui do
        Dir.chdir @tempdir do
          assert_raises Gem::InvalidSpecificationException do
            @cmd.execute
          end
        end
      end
    end
  end

  def test_execute_strict_without_warnings
    gemspec_file = File.join(@tempdir, @gem.spec_name)

    File.open gemspec_file, 'w' do |gs|
      gs.write @gem.to_ruby
    end

    @cmd.options[:strict] = true
    @cmd.options[:args] = [gemspec_file]

    util_test_build_gem @gem
  end

  def test_execute_rubyforge_project_warning
    rubyforge_gemspec = File.expand_path File.join("specifications", "rubyforge-0.0.1.gemspec"), __dir__

    @cmd.options[:args] = [rubyforge_gemspec]

    use_ui @ui do
      Dir.chdir @tempdir do
        @cmd.execute
      end
    end

    error = @ui.error.split("\n")
    assert_equal "WARNING:  rubyforge_project= is deprecated and ignored. Please remove this from your gemspec to ensure that your gem continues to build in the future.", error.shift
    assert_equal "WARNING:  See https://guides.rubygems.org/specification-reference/ for help", error.shift
    assert_equal [], error
  end

  def test_execute_strict_with_warnings
    bad_gem = util_spec 'some_bad_gem' do |s|
      s.files = ['README.md']
    end

    gemspec_file = File.join(@tempdir, bad_gem.spec_name)

    File.open gemspec_file, 'w' do |gs|
      gs.write bad_gem.to_ruby
    end

    @cmd.options[:args] = [gemspec_file]
    @cmd.options[:strict] = true

    use_ui @ui do
      Dir.chdir @tempdir do
        assert_raises Gem::InvalidSpecificationException do
          @cmd.execute
        end
      end
    end

    error = @ui.error.split "\n"
    assert_equal "WARNING:  licenses is empty, but is recommended.  Use a license identifier from", error.shift
    assert_equal "http://spdx.org/licenses or 'Nonstandard' for a nonstandard license.", error.shift
    assert_equal "WARNING:  See https://guides.rubygems.org/specification-reference/ for help", error.shift
    assert_equal [], error

    gem_file = File.join @tempdir, File.basename(@gem.cache_file)
    refute File.exist?(gem_file)
  end

  def test_execute_bad_spec
    @gem.date = "2010-11-08"

    gemspec_file = File.join(@tempdir, @gem.spec_name)

    File.open gemspec_file, 'w' do |gs|
      gs.write @gem.to_ruby.sub(/11-08/, "11-8")
    end

    @cmd.options[:args] = [gemspec_file]

    out, err = use_ui @ui do
      capture_io do
        assert_raises Gem::MockGemUi::TermError do
          @cmd.execute
        end
      end
    end

    assert_equal "", out
    assert_match(/invalid date format in specification/, err)

    assert_equal '', @ui.output
    assert_equal "ERROR:  Error loading gemspec. Aborting.\n", @ui.error
  end

  def test_execute_missing_file
    @cmd.options[:args] = %w[some_gem]
    use_ui @ui do
      assert_raises Gem::MockGemUi::TermError do
        @cmd.execute
      end
    end

    assert_equal '', @ui.output
    assert_equal "ERROR:  Gemspec file not found: some_gem.gemspec\n", @ui.error
  end

  def test_execute_outside_dir
    gemspec_dir = File.join @tempdir, 'build_command_gem'
    gemspec_file = File.join gemspec_dir, @gem.spec_name
    readme_file = File.join gemspec_dir, 'README.md'

    FileUtils.mkdir_p gemspec_dir

    File.open readme_file, 'w' do |f|
      f.write "My awesome gem"
    end

    File.open gemspec_file, 'w' do |gs|
      gs.write @gem.to_ruby
    end

    @cmd.options[:build_path] = gemspec_dir
    @cmd.options[:args] = [gemspec_file]

    use_ui @ui do
      @cmd.execute
    end

    output = @ui.output.split "\n"
    assert_equal "  Successfully built RubyGem", output.shift
    assert_equal "  Name: some_gem", output.shift
    assert_equal "  Version: 2", output.shift
    assert_equal "  File: some_gem-2.gem", output.shift
    assert_equal [], output

    gem_file = File.join gemspec_dir, File.basename(@gem.cache_file)
    assert File.exist?(gem_file)

    spec = Gem::Package.new(gem_file).spec

    assert_equal "some_gem", spec.name
    assert_equal "this is a summary", spec.summary
  end

  def test_can_find_gemspecs_without_dot_gemspec
    gemspec_file = File.join(@tempdir, @gem.spec_name)

    File.open gemspec_file + ".gemspec", 'w' do |gs|
      gs.write @gem.to_ruby
    end

    @cmd.options[:args] = [gemspec_file]

    util_test_build_gem @gem
  end

  def test_execute_without_gem_name
    some_gem = util_spec "some_gem"
    gemspec_dir = File.join(@tempdir, "build_command_gem")
    gemspec_file = File.join(gemspec_dir, some_gem.spec_name)

    FileUtils.mkdir_p(gemspec_dir)

    File.open(gemspec_file, "w") do |gs|
      gs.write(some_gem.to_ruby)
    end

    @cmd.options[:args] = []

    use_ui @ui do
      Dir.chdir(gemspec_dir) do
        @cmd.execute
      end
    end

    output = @ui.output.split("\n")
    assert_equal "  Successfully built RubyGem", output.shift
    assert_equal "  Name: some_gem", output.shift
    assert_equal "  Version: 2", output.shift
    assert_equal "  File: some_gem-2.gem", output.shift
    assert_equal [], output

    some_gem = File.join(gemspec_dir, File.basename(some_gem.cache_file))
    assert File.exist?(some_gem)
  end

  def test_execute_multiple_gemspec_without_gem_name
    some_gem = util_spec "some_gem"
    another_gem = util_spec "another_gem"
    gemspec_dir = File.join(@tempdir, "build_command_gem")
    gemspec_file = File.join(gemspec_dir, some_gem.spec_name)
    another_gemspec_file = File.join(gemspec_dir, another_gem.spec_name)

    FileUtils.mkdir_p(gemspec_dir)

    File.open(gemspec_file, "w") do |gs|
      gs.write(some_gem.to_ruby)
    end

    File.open(another_gemspec_file, "w") do |gs|
      gs.write(another_gem.to_ruby)
    end

    @cmd.options[:args] = []

    use_ui @ui do
      Dir.chdir(gemspec_dir) do
        assert_raises Gem::MockGemUi::TermError do
          @cmd.execute
        end
      end
    end

    gemspecs = ["another_gem-2.gemspec", "some_gem-2.gemspec"]
    assert_equal "", @ui.output
    assert_equal @ui.error, "ERROR:  Multiple gemspecs found: #{gemspecs}, please specify one\n"

    expected_gem = File.join(gemspec_dir, File.basename(another_gem.cache_file))
    refute File.exist?(expected_gem)
  end

  def util_test_build_gem(gem, suffix: nil)
    use_ui @ui do
      Dir.chdir @tempdir do
        @cmd.execute
      end
    end
    suffix &&= "-#{suffix}"
    gem_file = "some_gem-2#{suffix}.gem"
    output = @ui.output.split "\n"
    assert_equal "  Successfully built RubyGem", output.shift
    assert_equal "  Name: some_gem", output.shift
    assert_equal "  Version: 2", output.shift
    assert_equal "  File: #{gem_file}", output.shift
    assert_equal [], output

    gem_file = File.join(@tempdir, gem_file)
    assert File.exist?(gem_file)

    spec = Gem::Package.new(gem_file).spec

    assert_equal "some_gem", spec.name
    assert_equal "this is a summary", spec.summary
    spec
  end

  def test_execute_force
    gemspec_file = File.join(@tempdir, @gem.spec_name)

    @gem.send :remove_instance_variable, :@rubygems_version

    File.open gemspec_file, 'w' do |gs|
      gs.write @gem.to_ruby
    end

    @cmd.options[:args] = [gemspec_file]
    @cmd.options[:force] = true

    util_test_build_gem @gem
  end

  def test_build_signed_gem
    skip 'openssl is missing' unless defined?(OpenSSL::SSL) && !java_platform?

    trust_dir = Gem::Security.trust_dir

    spec = util_spec 'some_gem' do |s|
      s.signing_key = SIGNING_KEY
      s.cert_chain = [CERT_FILE]
    end

    gemspec_file = File.join(@tempdir, spec.spec_name)

    File.open gemspec_file, 'w' do |gs|
      gs.write spec.to_ruby
    end

    @cmd.options[:args] = [gemspec_file]

    util_test_build_gem spec

    trust_dir.trust_cert OpenSSL::X509::Certificate.new(File.read(CERT_FILE))

    gem = Gem::Package.new(File.join(@tempdir, spec.file_name),
                           Gem::Security::HighSecurity)
    assert gem.verify
  end

  def test_build_signed_gem_with_cert_expiration_length_days
    skip 'openssl is missing' unless defined?(OpenSSL::SSL) && !java_platform?

    gem_path = File.join Gem.user_home, ".gem"
    Dir.mkdir gem_path

    Gem::Security.trust_dir

    tmp_expired_cert_file = File.join gem_path, "gem-public_cert.pem"
    File.write(tmp_expired_cert_file, File.read(EXPIRED_CERT_FILE))

    tmp_private_key_file = File.join gem_path, "gem-private_key.pem"
    File.write(tmp_private_key_file, File.read(PRIVATE_KEY_FILE))

    spec = util_spec 'some_gem' do |s|
      s.signing_key = tmp_private_key_file
      s.cert_chain  = [tmp_expired_cert_file]
    end

    gemspec_file = File.join(@tempdir, spec.spec_name)

    File.open gemspec_file, 'w' do |gs|
      gs.write spec.to_ruby
    end

    @cmd.options[:args] = [gemspec_file]

    Gem.configuration.cert_expiration_length_days = 28

    use_ui @ui do
      Dir.chdir @tempdir do
        @cmd.execute
      end
    end

    re_signed_cert = OpenSSL::X509::Certificate.new(File.read(tmp_expired_cert_file))
    cert_days_to_expire = (re_signed_cert.not_after - re_signed_cert.not_before).to_i / (24 * 60 * 60)

    gem_file = File.join @tempdir, File.basename(spec.cache_file)

    assert File.exist?(gem_file)
    assert_equal(28, cert_days_to_expire)
  end

  def test_build_auto_resign_cert
    skip 'openssl is missing' unless defined?(OpenSSL::SSL) && !java_platform?

    gem_path = File.join Gem.user_home, ".gem"
    Dir.mkdir gem_path

    Gem::Security.trust_dir

    tmp_expired_cert_file = File.join gem_path, "gem-public_cert.pem"
    File.write(tmp_expired_cert_file, File.read(EXPIRED_CERT_FILE))

    tmp_private_key_file = File.join gem_path, "gem-private_key.pem"
    File.write(tmp_private_key_file, File.read(PRIVATE_KEY_FILE))

    spec = util_spec 'some_gem' do |s|
      s.signing_key = tmp_private_key_file
      s.cert_chain  = [tmp_expired_cert_file]
    end

    gemspec_file = File.join(@tempdir, spec.spec_name)

    File.open gemspec_file, 'w' do |gs|
      gs.write spec.to_ruby
    end

    @cmd.options[:args] = [gemspec_file]

    Gem.configuration.cert_expiration_length_days = 28

    use_ui @ui do
      Dir.chdir @tempdir do
        @cmd.execute
      end
    end

    output = @ui.output.split "\n"
    assert_equal "INFO:  Your certificate has expired, trying to re-sign it...", output.shift
    assert_equal "INFO:  Your cert: #{tmp_expired_cert_file } has been auto re-signed with the key: #{tmp_private_key_file}", output.shift
    assert_match(/INFO:  Your expired cert will be located at: .+\Wgem-public_cert\.pem\.expired\.[0-9]+/, output.shift)
  end

  def test_build_is_reproducible
    epoch = ENV["SOURCE_DATE_EPOCH"]
    new_epoch = Time.now.to_i.to_s
    ENV["SOURCE_DATE_EPOCH"] = new_epoch

    gem_file = File.basename(@gem.cache_file)

    gemspec_file = File.join(@tempdir, @gem.spec_name)
    File.write(gemspec_file, @gem.to_ruby)
    @cmd.options[:args] = [gemspec_file]

    util_test_build_gem @gem

    build1_contents = File.read(gem_file)

    # Guarantee the time has changed.
    sleep 1 if Time.now.to_i == new_epoch

    ENV["SOURCE_DATE_EPOCH"] = new_epoch

    @ui = Gem::MockGemUi.new
    @cmd.options[:args] = [gemspec_file]

    util_test_build_gem @gem

    build2_contents = File.read(gem_file)

    assert_equal build1_contents, build2_contents
  ensure
    ENV["SOURCE_DATE_EPOCH"] = epoch
  end
end
