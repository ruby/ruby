# frozen_string_literal: true
require 'rubygems/test_case'
require 'rubygems/doctor'

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
    a = gem 'a'
    b = gem 'b'
    c = gem 'c'

    Gem.use_paths @userhome, @gemhome

    FileUtils.rm b.spec_file

    File.open c.spec_file, 'w' do |io|
      io.write 'this will raise an exception when evaluated.'
    end

    assert_path_exists File.join(a.gem_dir, 'Rakefile')
    assert_path_exists File.join(a.gem_dir, 'lib', 'a.rb')

    assert_path_exists b.gem_dir
    refute_path_exists b.spec_file

    assert_path_exists c.gem_dir
    assert_path_exists c.spec_file

    doctor = Gem::Doctor.new @gemhome

    capture_io do
      use_ui @ui do
        doctor.doctor
      end
    end

    assert_path_exists File.join(a.gem_dir, 'Rakefile')
    assert_path_exists File.join(a.gem_dir, 'lib', 'a.rb')

    refute_path_exists b.gem_dir
    refute_path_exists b.spec_file

    refute_path_exists c.gem_dir
    refute_path_exists c.spec_file

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
    a = gem 'a'
    b = gem 'b'
    c = gem 'c'

    Gem.use_paths @userhome, @gemhome

    FileUtils.rm b.spec_file

    File.open c.spec_file, 'w' do |io|
      io.write 'this will raise an exception when evaluated.'
    end

    assert_path_exists File.join(a.gem_dir, 'Rakefile')
    assert_path_exists File.join(a.gem_dir, 'lib', 'a.rb')

    assert_path_exists b.gem_dir
    refute_path_exists b.spec_file

    assert_path_exists c.gem_dir
    assert_path_exists c.spec_file

    doctor = Gem::Doctor.new @gemhome, true

    capture_io do
      use_ui @ui do
        doctor.doctor
      end
    end

    assert_path_exists File.join(a.gem_dir, 'Rakefile')
    assert_path_exists File.join(a.gem_dir, 'lib', 'a.rb')

    assert_path_exists b.gem_dir
    refute_path_exists b.spec_file

    assert_path_exists c.gem_dir
    assert_path_exists c.spec_file

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

  def test_doctor_non_gem_home
    other_dir = File.join @tempdir, 'other', 'dir'

    FileUtils.mkdir_p other_dir

    doctor = Gem::Doctor.new @tempdir

    capture_io do
      use_ui @ui do
        doctor.doctor
      end
    end

    assert_path_exists other_dir

    expected = <<-OUTPUT
Checking #{@tempdir}
This directory does not appear to be a RubyGems repository, skipping

    OUTPUT

    assert_equal expected, @ui.output
  end

  def test_doctor_child_missing
    doctor = Gem::Doctor.new @gemhome

    doctor.doctor_child 'missing', ''

    assert true # count
  end

  def test_doctor_badly_named_plugins
    gem 'a'

    Gem.use_paths @gemhome.to_s

    FileUtils.mkdir_p Gem.plugindir
    bad_plugin = File.join(Gem.plugindir, "a_badly_named_file.rb")
    write_file bad_plugin

    doctor = Gem::Doctor.new @gemhome

    capture_io do
      use_ui @ui do
        doctor.doctor
      end
    end

    # refute_path_exists bad_plugin

    expected = <<-OUTPUT
Checking #{@gemhome}
Removed file plugins/a_badly_named_file.rb

    OUTPUT

    assert_equal expected, @ui.output
  end

  def test_gem_repository_eh
    doctor = Gem::Doctor.new @gemhome

    refute doctor.gem_repository?, 'no gems installed'

    install_specs util_spec 'a'

    doctor = Gem::Doctor.new @gemhome

    assert doctor.gem_repository?, 'gems installed'
  end

end
