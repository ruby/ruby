# frozen_string_literal: true

require_relative "helper"
require "rubygems/doctor"

class TestGemDoctor < Gem::TestCase
  def gem(name)
    spec = quick_gem name do |gem|
      gem.files = %W[lib/#{name}.rb Rakefile]
    end

    write_file File.join(*%W[gems #{spec.full_name} lib #{name}.rb])
    write_file File.join(*%W[gems #{spec.full_name} Rakefile])

    spec
  end

  def test_doctor
    a = gem "a"
    b = gem "b"
    c = gem "c"

    Gem.use_paths @userhome, @gemhome

    FileUtils.rm b.spec_file

    File.open c.spec_file, "w" do |io|
      io.write "this will raise an exception when evaluated."
    end

    assert_path_exist File.join(a.gem_dir, "Rakefile")
    assert_path_exist File.join(a.gem_dir, "lib", "a.rb")

    assert_path_exist b.gem_dir
    assert_path_not_exist b.spec_file

    assert_path_exist c.gem_dir
    assert_path_exist c.spec_file

    doctor = Gem::Doctor.new @gemhome

    capture_output do
      use_ui @ui do
        doctor.doctor
      end
    end

    assert_path_exist File.join(a.gem_dir, "Rakefile")
    assert_path_exist File.join(a.gem_dir, "lib", "a.rb")

    assert_path_not_exist b.gem_dir
    assert_path_not_exist b.spec_file

    assert_path_not_exist c.gem_dir
    assert_path_not_exist c.spec_file

    expected = <<-OUTPUT
Checking #{@gemhome}
Removed file specifications/c-2.gemspec
Removed directory gems/b-2
Removed directory gems/c-2

    OUTPUT

    assert_equal expected, @ui.output

    assert_equal Gem.dir,  @userhome
    assert_equal Gem.path, [@gemhome, @userhome]
  end

  def test_doctor_dry_run
    a = gem "a"
    b = gem "b"
    c = gem "c"

    Gem.use_paths @userhome, @gemhome

    FileUtils.rm b.spec_file

    File.open c.spec_file, "w" do |io|
      io.write "this will raise an exception when evaluated."
    end

    assert_path_exist File.join(a.gem_dir, "Rakefile")
    assert_path_exist File.join(a.gem_dir, "lib", "a.rb")

    assert_path_exist b.gem_dir
    assert_path_not_exist b.spec_file

    assert_path_exist c.gem_dir
    assert_path_exist c.spec_file

    doctor = Gem::Doctor.new @gemhome, true

    capture_output do
      use_ui @ui do
        doctor.doctor
      end
    end

    assert_path_exist File.join(a.gem_dir, "Rakefile")
    assert_path_exist File.join(a.gem_dir, "lib", "a.rb")

    assert_path_exist b.gem_dir
    assert_path_not_exist b.spec_file

    assert_path_exist c.gem_dir
    assert_path_exist c.spec_file

    expected = <<-OUTPUT
Checking #{@gemhome}
Extra file specifications/c-2.gemspec
Extra directory gems/b-2
Extra directory gems/c-2

    OUTPUT

    assert_equal expected, @ui.output

    assert_equal Gem.dir,  @userhome
    assert_equal Gem.path, [@gemhome, @userhome]
  end

  def test_doctor_keeps_build_logs_of_installed_gems
    a = gem "a"

    Gem.use_paths @userhome, @gemhome

    build_info_dir = File.join @gemhome, "build_info"
    FileUtils.mkdir_p build_info_dir

    kept = ["#{a.full_name}.mkmf.log", "#{a.full_name}.gem_make.out"].map do |name|
      File.join build_info_dir, name
    end
    stale = File.join build_info_dir, "b-2.gem_make.out"

    FileUtils.touch kept + [stale]

    doctor = Gem::Doctor.new @gemhome

    capture_output do
      use_ui @ui do
        doctor.doctor
      end
    end

    kept.each {|path| assert_path_exist path }
    assert_path_not_exist stale
  end

  def test_doctor_non_gem_home
    other_dir = File.join @tempdir, "other", "dir"

    FileUtils.mkdir_p other_dir

    doctor = Gem::Doctor.new @tempdir

    capture_output do
      use_ui @ui do
        doctor.doctor
      end
    end

    assert_path_exist other_dir

    expected = <<-OUTPUT
Checking #{@tempdir}
This directory does not appear to be a RubyGems repository, skipping

    OUTPUT

    assert_equal expected, @ui.output
  end

  def test_doctor_child_missing
    doctor = Gem::Doctor.new @gemhome

    doctor.doctor_child "missing", ""

    assert true # count
  end

  def test_doctor_badly_named_plugins
    gem "a"

    Gem.use_paths @gemhome.to_s

    FileUtils.mkdir_p Gem.plugindir
    bad_plugin = File.join(Gem.plugindir, "a_badly_named_file.rb")
    write_file bad_plugin

    doctor = Gem::Doctor.new @gemhome

    capture_output do
      use_ui @ui do
        doctor.doctor
      end
    end

    # assert_path_not_exist bad_plugin

    expected = <<-OUTPUT
Checking #{@gemhome}
Removed file plugins/a_badly_named_file.rb

    OUTPUT

    assert_equal expected, @ui.output
  end

  def test_gem_repository_eh
    doctor = Gem::Doctor.new @gemhome

    refute doctor.gem_repository?, "no gems installed"

    install_specs util_spec "a"

    doctor = Gem::Doctor.new @gemhome

    assert doctor.gem_repository?, "gems installed"
  end

  def test_doctor_preserves_valid_abi_scoped_gemspec
    spec = util_ca_spec "ca_gem", "1", "aabbccdd",
      required_ruby_version: "~> #{Gem.ruby_abi}.0",
      platform: Gem::Platform.local.to_s
    abi_dir = File.join @gemhome, "specifications", Gem.ruby_abi
    FileUtils.mkdir_p abi_dir
    gemspec_path = File.join(abi_dir, "#{spec.full_name}.gemspec")
    File.write gemspec_path, spec.to_ruby_for_cache

    doctor = Gem::Doctor.new @gemhome

    use_ui @ui do
      doctor.doctor
    end

    assert_path_exist abi_dir
    assert_path_exist gemspec_path
  end

  def test_doctor_removes_corrupt_abi_scoped_gemspec
    install_specs util_spec "regular_gem"

    spec = util_ca_spec "ca_gem", "1", "aabbccdd",
      required_ruby_version: "~> #{Gem.ruby_abi}.0",
      platform: Gem::Platform.local.to_s
    abi_dir = File.join @gemhome, "specifications", Gem.ruby_abi
    FileUtils.mkdir_p abi_dir
    gemspec_path = File.join(abi_dir, "#{spec.full_name}.gemspec")
    File.write gemspec_path, spec.to_ruby_for_cache

    corrupt_path = File.join(abi_dir, "corrupt_gem-1-deadbeef.gemspec")
    File.write corrupt_path, "this will raise an exception when evaluated."

    doctor = Gem::Doctor.new @gemhome

    use_ui @ui do
      doctor.doctor
    end

    assert_path_exist abi_dir
    assert_path_exist gemspec_path
    assert_path_not_exist corrupt_path
  end

  def test_doctor_preserves_other_abi_dir
    install_specs util_spec "regular_gem"

    abi_dir = File.join @gemhome, "specifications", "9.9"
    FileUtils.mkdir_p abi_dir
    gemspec_path = File.join(abi_dir, "other_ruby_gem-1-deadbeef.gemspec")
    File.write gemspec_path, "belongs to another Ruby installation"

    doctor = Gem::Doctor.new @gemhome

    use_ui @ui do
      doctor.doctor
    end

    assert_path_exist abi_dir
    assert_path_exist gemspec_path
  end

  def test_doctor_does_not_recurse_into_abi_symlink
    pend "symlinks not supported" unless symlink_supported?

    install_specs util_spec "regular_gem"

    target_dir = File.join @tempdir, "outside_repository"
    FileUtils.mkdir_p target_dir
    outside_path = File.join(target_dir, "outside_gem-1-deadbeef.gemspec")
    File.write outside_path, "outside the gem repository"

    link = File.join @gemhome, "specifications", Gem.ruby_abi
    File.symlink target_dir, link

    doctor = Gem::Doctor.new @gemhome

    use_ui @ui do
      doctor.doctor
    end

    assert File.symlink?(link)
    assert_path_exist outside_path
  end

  def test_doctor_preserves_empty_abi_dir
    install_specs util_spec "regular_gem"
    abi_dir = File.join @gemhome, "specifications", Gem.ruby_abi
    FileUtils.mkdir_p abi_dir

    doctor = Gem::Doctor.new @gemhome

    use_ui @ui do
      doctor.doctor
    end

    assert_path_exist abi_dir
  end
end
