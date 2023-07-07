require 'test/unit'

class TestBundledGems < Test::Unit::TestCase
  def test_bundled_gems_in_load_path
    assert_separately(%w[-rtmpdir -rrubygems -rbundler], <<-'end;')
      Dir.mktmpdir do |tmpdir|
        Dir.chdir(tmpdir) do
          orig_gem_home = ENV["GEM_HOME"]
          ENV["GEM_HOME"] = "#{tmpdir}/gems"

          require "bundled_gems"
          Gem.bundled_gems.each do |name, version|
            next if ["nkf", "syslog"].include?(name) # We can't install native extension
            Gem.install name, version
          end
          Gem.install "rexml", "3.2.5"

          File.open("Gemfile", "w+") do |f|
            f.puts "source 'https://rubygems.org'"
            f.puts "gem 'rexml', '3.2.5'"
          end
          File.open("Gemfile.lock", "w+") do |f|
            f.puts <<~'LOCK'
              GEM
                remote: https://rubygems.org/
                specs:
                  rexml (3.2.5)

              PLATFORMS
                ruby

              DEPENDENCIES
                rss
            LOCK
          end
          require "bundler/setup"
          Bundler.ui.silence { Bundler.setup }

          Gem.bundled_gems.each do |name, version|
            next if ["nkf", "syslog"].include?(name)
            assert_include $LOAD_PATH.join(":"), "#{name}-#{version}/lib"
          end

          assert_include $LOAD_PATH.join(":"), "rexml-3.2.5/lib"

          ENV["GEM_HOME"] = orig_gem_home
        end
      end
    end;
  end

  def test_without_bundled_gems_list
    assert_separately(%w[-rtmpdir -rrubygems -rbundler], <<-'end;')
      Dir.mktmpdir do |tmpdir|
        Dir.chdir(tmpdir) do
          orig_gem_home = ENV["GEM_HOME"]
          ENV["GEM_HOME"] = "#{tmpdir}/gems"

          require "bundled_gems"
          Gem.bundled_gems.each do |name, version|
            next if ["nkf", "syslog"].include?(name) # We can't install native extension
            Gem.install name, version
          end
          Gem.install "rexml", "3.2.5"

          module Gem
            class << self
              undef_method :bundled_gems
              define_method(:bundled_gems, -> { [] })
            end
          end

          File.open("Gemfile", "w+") do |f|
            f.puts "source 'https://rubygems.org'"
            f.puts "gem 'rexml', '3.2.5'"
          end
          File.open("Gemfile.lock", "w+") do |f|
            f.puts <<~'LOCK'
              GEM
                remote: https://rubygems.org/
                specs:
                  rexml (3.2.5)

              PLATFORMS
                ruby

              DEPENDENCIES
                rss
            LOCK
          end
          require "bundler/setup"
          Bundler.ui.silence { Bundler.setup }

          module Gem
            class << self
              undef_method :bundled_gems
            end
          end
          load "bundled_gems.rb"
          Gem.bundled_gems.each do |name, version|
            next if ["nkf", "syslog"].include?(name) # We can't install native extension
            assert_not_include $LOAD_PATH.join(":"), "#{name}-#{version}/lib"
          end

          assert_include $LOAD_PATH.join(":"), "rexml-3.2.5/lib"

          ENV["GEM_HOME"] = orig_gem_home
        end
      end
    end;
  end
end