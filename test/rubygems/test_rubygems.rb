require_relative 'helper'

class GemTest < Gem::TestCase
  def test_rubygems_normal_behaviour
    _ = Gem::Util.popen(*ruby_with_rubygems_in_load_path, '-e', "'require \"rubygems\"'", {:err => [:child, :out]}).strip
    assert $?.success?
  end

  def test_operating_system_other_exceptions
    pend "does not apply to truffleruby" if RUBY_ENGINE == 'truffleruby'

    path = util_install_operating_system_rb <<-RUBY
      intentionally_not_implemented_method
    RUBY

    output = Gem::Util.popen(*ruby_with_rubygems_and_fake_operating_system_in_load_path(path), '-e', "'require \"rubygems\"'", {:err => [:child, :out]}).strip
    assert !$?.success?
    assert_includes output, "undefined local variable or method `intentionally_not_implemented_method'"
    assert_includes output, "Loading the rubygems/defaults/operating_system.rb file caused an error. " \
    "This file is owned by your OS, not by rubygems upstream. " \
    "Please find out which OS package this file belongs to and follow the guidelines from your OS to report " \
    "the problem and ask for help."
  end

  def test_operating_system_customizing_default_dir
    pend "does not apply to truffleruby" if RUBY_ENGINE == 'truffleruby'
    pend "loads a custom defaults/jruby file that gets in the middle" if RUBY_ENGINE == 'jruby'

    # On a non existing default dir, there should be no gems

    path = util_install_operating_system_rb <<-RUBY
      module Gem
        def self.default_dir
          File.expand_path("foo")
        end
      end
    RUBY

    output = Gem::Util.popen(
      *ruby_with_rubygems_and_fake_operating_system_in_load_path(path),
      '-e',
      "require \"rubygems\"; puts Gem::Specification.stubs.map(&:full_name)",
      {:err => [:child, :out]}
    ).strip
    assert_empty output
  end

  private

  def util_install_operating_system_rb(content)
    dir_lib = Dir.mktmpdir("test_operating_system_lib", @tempdir)
    dir_lib_arg = File.join dir_lib

    dir_lib_rubygems_defaults_arg = File.join dir_lib_arg, "lib", "rubygems", "defaults"
    FileUtils.mkdir_p dir_lib_rubygems_defaults_arg

    operating_system_rb = File.join dir_lib_rubygems_defaults_arg, "operating_system.rb"

    File.open(operating_system_rb, 'w') {|f| f.write content }

    File.join dir_lib_arg, "lib"
  end

  def ruby_with_rubygems_and_fake_operating_system_in_load_path(operating_system_path)
    [Gem.ruby, "-I", operating_system_path, "-I" , $LOAD_PATH.find{|p| p == File.dirname($LOADED_FEATURES.find{|f| f.end_with?("/rubygems.rb") }) }]
  end
end
