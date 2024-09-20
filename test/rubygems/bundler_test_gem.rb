# frozen_string_literal: true

require_relative "helper"

class TestBundlerGem < Gem::TestCase
  PROJECT_DIR = File.expand_path("../..", __dir__)

  def test_self_use_gemdeps
    with_local_bundler_at(Gem.dir) do
      with_rubygems_gemdeps("-") do
        FileUtils.mkdir_p "detect/a/b"
        FileUtils.mkdir_p "detect/a/Isolate"

        FileUtils.touch "detect/Isolate"

        begin
          Dir.chdir "detect/a/b"

          Gem.use_gemdeps

          assert_equal add_bundler_full_name([]), loaded_spec_names
        ensure
          Dir.chdir @tempdir
        end
      end
    end
  end

  def test_self_find_files_with_gemfile
    with_local_bundler_at(Gem.dir) do
      cwd = File.expand_path("test/rubygems", PROJECT_DIR)
      actual_load_path = $LOAD_PATH.unshift(cwd).dup

      discover_path = File.join "lib", "sff", "discover.rb"

      foo1, _ = %w[1 2].map do |version|
        spec = quick_gem "sff", version do |s|
          s.files << discover_path
        end

        write_file(File.join("gems", spec.full_name, discover_path)) do |fp|
          fp.puts "# #{spec.full_name}"
        end

        spec
      end
      Gem.refresh

      write_file(File.join(Dir.pwd, "Gemfile")) do |fp|
        fp.puts "source 'https://rubygems.org'"
        fp.puts "gem '#{foo1.name}', '#{foo1.version}'"
      end
      Gem.use_gemdeps(File.join(Dir.pwd, "Gemfile"))

      expected = [
        File.expand_path("test/rubygems/sff/discover.rb", PROJECT_DIR),
        File.join(foo1.full_gem_path, discover_path),
      ].sort

      assert_equal expected, Gem.find_files("sff/discover").sort
      assert_equal expected, Gem.find_files("sff/**.rb").sort, "[ruby-core:31730]"
      assert_equal cwd, actual_load_path.shift
    end
  end

  def test_auto_activation_of_specific_gemdeps_file
    with_local_bundler_at(Gem.dir) do
      a = util_spec "a", "1", nil, "lib/a.rb"
      b = util_spec "b", "1", nil, "lib/b.rb"
      c = util_spec "c", "1", nil, "lib/c.rb"

      install_specs a, b, c

      path = File.join @tempdir, "gem.deps.rb"

      File.open path, "w" do |f|
        f.puts "gem 'a'"
        f.puts "gem 'b'"
        f.puts "gem 'c'"
      end

      with_rubygems_gemdeps(path) do
        Gem.use_gemdeps

        assert_equal add_bundler_full_name(%W[a-1 b-1 c-1]), loaded_spec_names
      end
    end
  end

  def test_auto_activation_of_used_gemdeps_file
    with_local_bundler_at(Gem.dir) do
      a = util_spec "a", "1", nil, "lib/a.rb"
      b = util_spec "b", "1", nil, "lib/b.rb"
      c = util_spec "c", "1", nil, "lib/c.rb"

      install_specs a, b, c

      path = File.join @tempdir, "gem.deps.rb"

      File.open path, "w" do |f|
        f.puts "gem 'a'"
        f.puts "gem 'b'"
        f.puts "gem 'c'"
      end

      with_rubygems_gemdeps("-") do
        expected_specs = [a, b, util_spec("bundler", Bundler::VERSION), c].compact.map(&:full_name)

        Gem.use_gemdeps

        assert_equal expected_specs, loaded_spec_names
      end
    end
  end

  def test_looks_for_gemdeps_files_automatically_from_binstubs
    path = File.join(@tempdir, "gd-tmp")

    with_local_bundler_at(path) do
      a = util_spec "a", "1" do |s|
        s.executables = %w[foo]
        s.bindir = "exe"
      end

      write_file File.join(@tempdir, "exe", "foo") do |fp|
        fp.puts "puts Gem.loaded_specs.values.map(&:full_name).sort"
      end

      b = util_spec "b", "1", nil, "lib/b.rb"
      c = util_spec "c", "1", nil, "lib/c.rb"

      install_specs a, b, c

      install_gem a, install_dir: path
      install_gem b, install_dir: path
      install_gem c, install_dir: path

      ENV["GEM_PATH"] = path

      with_rubygems_gemdeps("-") do
        new_path = [File.join(path, "bin"), ENV["PATH"]].join(File::PATH_SEPARATOR)
        new_rubyopt = "-I#{rubygems_path} -I#{bundler_path}"

        path = File.join @tempdir, "gem.deps.rb"

        File.open path, "w" do |f|
          f.puts "gem 'a'"
        end
        out0 = with_path_and_rubyopt(new_path, new_rubyopt) do
          IO.popen("foo", &:read).split(/\n/)
        end

        File.open path, "a" do |f|
          f.puts "gem 'b'"
          f.puts "gem 'c'"
        end
        out = with_path_and_rubyopt(new_path, new_rubyopt) do
          IO.popen("foo", &:read).split(/\n/)
        end

        assert_equal ["b-1", "c-1"], out - out0
      end
    end
  end

  def test_looks_for_gemdeps_files_automatically_from_binstubs_in_parent_dir
    path = File.join(@tempdir, "gd-tmp")

    with_local_bundler_at(path) do
      pend "IO.popen has issues on JRuby when passed :chdir" if Gem.java_platform?

      a = util_spec "a", "1" do |s|
        s.executables = %w[foo]
        s.bindir = "exe"
      end

      write_file File.join(@tempdir, "exe", "foo") do |fp|
        fp.puts "puts Gem.loaded_specs.values.map(&:full_name).sort"
      end

      b = util_spec "b", "1", nil, "lib/b.rb"
      c = util_spec "c", "1", nil, "lib/c.rb"

      install_specs a, b, c

      install_gem a, install_dir: path
      install_gem b, install_dir: path
      install_gem c, install_dir: path

      ENV["GEM_PATH"] = path

      with_rubygems_gemdeps("-") do
        Dir.mkdir "sub1"

        new_path = [File.join(path, "bin"), ENV["PATH"]].join(File::PATH_SEPARATOR)
        new_rubyopt = "-I#{rubygems_path} -I#{bundler_path}"

        path = File.join @tempdir, "gem.deps.rb"

        File.open path, "w" do |f|
          f.puts "gem 'a'"
        end
        out0 = with_path_and_rubyopt(new_path, new_rubyopt) do
          IO.popen("foo", chdir: "sub1", &:read).split(/\n/)
        end

        File.open path, "a" do |f|
          f.puts "gem 'b'"
          f.puts "gem 'c'"
        end
        out = with_path_and_rubyopt(new_path, new_rubyopt) do
          IO.popen("foo", chdir: "sub1", &:read).split(/\n/)
        end

        Dir.rmdir "sub1"

        assert_equal ["b-1", "c-1"], out - out0
      end
    end
  end

  def test_use_gemdeps
    with_local_bundler_at(Gem.dir) do
      gem_deps_file = "gem.deps.rb"
      spec = util_spec "a", 1
      install_specs spec

      spec = Gem::Specification.find {|s| s == spec }
      refute spec.activated?

      File.open gem_deps_file, "w" do |io|
        io.write 'gem "a"'
      end

      assert_nil Gem.gemdeps

      Gem.use_gemdeps gem_deps_file

      assert_equal add_bundler_full_name(%W[a-1]), loaded_spec_names
      refute_nil Gem.gemdeps
    end
  end

  def test_use_gemdeps_ENV
    with_local_bundler_at(Gem.dir) do
      with_rubygems_gemdeps(nil) do
        spec = util_spec "a", 1

        refute spec.activated?

        File.open "gem.deps.rb", "w" do |io|
          io.write 'gem "a"'
        end

        Gem.use_gemdeps

        refute spec.activated?
      end
    end
  end

  def test_use_gemdeps_argument_missing
    with_local_bundler_at(Gem.dir) do
      e = assert_raise ArgumentError do
        Gem.use_gemdeps "gem.deps.rb"
      end

      assert_equal "Unable to find gem dependencies file at gem.deps.rb",
                   e.message
    end
  end

  def test_use_gemdeps_argument_missing_match_ENV
    with_local_bundler_at(Gem.dir) do
      with_rubygems_gemdeps("gem.deps.rb") do
        e = assert_raise ArgumentError do
          Gem.use_gemdeps "gem.deps.rb"
        end

        assert_equal "Unable to find gem dependencies file at gem.deps.rb",
                     e.message
      end
    end
  end

  def test_use_gemdeps_automatic
    with_local_bundler_at(Gem.dir) do
      with_rubygems_gemdeps("-") do
        spec = util_spec "a", 1
        install_specs spec
        spec = Gem::Specification.find {|s| s == spec }

        refute spec.activated?

        File.open "Gemfile", "w" do |io|
          io.write 'gem "a"'
        end

        Gem.use_gemdeps

        assert_equal add_bundler_full_name(%W[a-1]), loaded_spec_names
      end
    end
  end

  def test_use_gemdeps_automatic_missing
    with_local_bundler_at(Gem.dir) do
      with_rubygems_gemdeps("-") do
        Gem.use_gemdeps

        assert true # count
      end
    end
  end

  def test_use_gemdeps_disabled
    with_local_bundler_at(Gem.dir) do
      with_rubygems_gemdeps("") do
        spec = util_spec "a", 1

        refute spec.activated?

        File.open "gem.deps.rb", "w" do |io|
          io.write 'gem "a"'
        end

        Gem.use_gemdeps

        refute spec.activated?
      end
    end
  end

  def test_use_gemdeps_missing_gem
    with_local_bundler_at(Gem.dir) do
      with_rubygems_gemdeps("x") do
        File.open "x", "w" do |io|
          io.write 'gem "a"'
        end

        expected = <<-EXPECTED
Could not find gem 'a' in locally installed gems.
You may need to `bundle install` to install missing gems

      EXPECTED

        Gem::Deprecate.skip_during do
          actual_stdout, actual_stderr = capture_output do
            Gem.use_gemdeps
          end
          assert_empty actual_stdout
          assert_equal(expected, actual_stderr)
        end
      end
    end
  end

  def test_use_gemdeps_specific
    with_local_bundler_at(Gem.dir) do
      with_rubygems_gemdeps("x") do
        spec = util_spec "a", 1
        install_specs spec

        spec = Gem::Specification.find {|s| s == spec }
        refute spec.activated?

        File.open "x", "w" do |io|
          io.write 'gem "a"'
        end

        Gem.use_gemdeps

        assert_equal add_bundler_full_name(%W[a-1]), loaded_spec_names
      end
    end
  end

  private

  def add_bundler_full_name(names)
    names << "bundler-#{Bundler::VERSION}"
    names.sort!
    names
  end

  def with_path_and_rubyopt(path_value, rubyopt_value)
    path = ENV["PATH"]
    ENV["PATH"] = path_value
    rubyopt = ENV["RUBYOPT"]
    ENV["RUBYOPT"] = rubyopt_value

    yield
  ensure
    ENV["PATH"] = path
    ENV["RUBYOPT"] = rubyopt
  end

  def with_rubygems_gemdeps(value)
    rubygems_gemdeps = ENV["RUBYGEMS_GEMDEPS"]
    ENV["RUBYGEMS_GEMDEPS"] = value

    yield
  ensure
    ENV["RUBYGEMS_GEMDEPS"] = rubygems_gemdeps
  end

  def with_local_bundler_at(path)
    require "bundler"

    # If bundler gemspec exists, pretend it's installed
    bundler_gemspec = File.expand_path("../../bundler/bundler.gemspec", __dir__)
    if File.exist?(bundler_gemspec)
      target_gemspec_location = "#{path}/specifications/bundler-#{Bundler::VERSION}.gemspec"

      FileUtils.mkdir_p File.dirname(target_gemspec_location)

      File.write target_gemspec_location, Gem::Specification.load(bundler_gemspec).to_ruby_for_cache
    end

    yield
  ensure
    Bundler.reset!
  end
end
