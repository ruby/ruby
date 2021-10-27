# frozen_string_literal: false
require_relative 'base'

class TestMkmf
  class TestInstall < TestMkmf
    def test_install_dirs
      Dir.mktmpdir do |dir|
        File.write(dir+"/extconf.rb", "require 'mkmf'; create_makefile('test')")
        all_assertions do |a|
          a.foreach(
            ["site"],
            ["vendor", "--vendor"],
          ) do |dest, *options|
            assert_ruby_status(["-C", dir, "extconf.rb", *options])
            mf = File.read(dir+"/Makefile")
            a.foreach(
              ["RUBYCOMMONDIR", "$(#{dest}dir)$(target_prefix)"],
              ["RUBYLIBDIR",    "$(#{dest}libdir)$(target_prefix)"],
              ["RUBYARCHDIR",   "$(#{dest}archdir)$(target_prefix)"],
              ["HDRDIR",        "$(#{dest}hdrdir)$(target_prefix)"],
              ["ARCHHDRDIR",    "$(#{dest}archhdrdir)$(target_prefix)"],
            ) do |(var, path)|
              assert_equal path, mf[/^#{var}\s*=\s*(.*)$/, 1]
            end
          end
        end
      end
    end
  end
end
