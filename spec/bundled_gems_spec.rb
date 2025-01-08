require "bundled_gems"

require "bundler"
require "fileutils"

require_relative "bundler/support/builders"
require_relative "bundler/support/helpers"
require_relative "bundler/support/path"

module Gem
  def self.ruby=(ruby)
    @ruby = ruby
  end
end

RSpec.configure do |config|
  config.include Spec::Builders
  config.include Spec::Helpers
  config.include Spec::Path

  config.before(:suite) do
    Gem.ruby = ENV["RUBY"] if ENV["RUBY"]

    require_relative "bundler/support/rubygems_ext"
    Spec::Rubygems.test_setup
    Spec::Helpers.install_dev_bundler
  end

  config.around(:each) do |example|
    FileUtils.cp_r Spec::Path.pristine_system_gem_path, Spec::Path.system_gem_path
    FileUtils.mkdir_p Spec::Path.base_system_gem_path.join("gems")
    %w[sinatra rack tilt rack-protection rack-session rack-test mustermann base64 compact_index].each do |gem|
      path = Dir[File.expand_path("../.bundle/gems/#{gem}-*", __dir__)].map(&:to_s).first
      FileUtils.cp_r path, Spec::Path.base_system_gem_path.join("gems")
    end

    with_gem_path_as(system_gem_path) do
      Bundler.ui.silence { example.run }

      all_output = all_commands_output
      if example.exception && !all_output.empty?
        message = all_output + "\n" + example.exception.message
        (class << example.exception; self; end).send(:define_method, :message) do
          message
        end
      end
    end
  ensure
    reset!
  end

  config.after :suite do
    FileUtils.rm_rf Spec::Path.pristine_system_gem_path
  end
end

RSpec.describe "bundled_gems.rb" do
  let(:stub_code) {
    <<~STUB
      Gem::BUNDLED_GEMS.send(:remove_const, :LIBDIR)
      Gem::BUNDLED_GEMS.send(:remove_const, :ARCHDIR)
      Gem::BUNDLED_GEMS.send(:remove_const, :SINCE)
      Gem::BUNDLED_GEMS.send(:remove_const, :SINCE_FAST_PATH)
      Gem::BUNDLED_GEMS.const_set(:LIBDIR, File.expand_path(File.join(__dir__, "../../..", "lib")) + "/")
      Gem::BUNDLED_GEMS.const_set(:ARCHDIR, File.expand_path($LOAD_PATH.find{|path| path.include?(".ext/common") }) + "/")
      Gem::BUNDLED_GEMS.const_set(:SINCE, { "fiddle" => "3.5.0", "irb" => "3.5.0", "csv" => "3.4.0", "net-smtp" => "3.1.0", "erb" => RUBY_VERSION })
      Gem::BUNDLED_GEMS.const_set(:SINCE_FAST_PATH, Gem::BUNDLED_GEMS::SINCE.transform_keys { |g| g.sub(/\A.*\-/, "") } )
    STUB
  }

  def script(code, options = {})
    options[:artifice] ||= "compact_index"
    code = <<~RUBY
      #{stub_code}
      require 'bundler/inline'

      #{code}
    RUBY
    ruby(code, options)
  end

  it "Show warning require and LoadError" do
    script <<-RUBY
      gemfile do
        source "https://rubygems.org"
      end

      begin
        require "csv"
      rescue LoadError
      end
      require "erb"
    RUBY

    expect(err).to include(/csv was loaded from (.*) from Ruby 3.4.0/)
    expect(err).to include(/-e:17/)
    expect(err).to include(/erb was loaded from (.*) from Ruby #{RUBY_VERSION}/)
    expect(err).to include(/-e:20/)
  end

  it "Show warning when bundled gems called as dependency" do
    build_lib "activesupport", "7.0.7.2" do |s|
      s.write "lib/active_support/all.rb", "require 'erb'"
    end

    script <<-RUBY, env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo1.to_s }
      gemfile do
        source "https://gem.repo1"
        path "#{lib_path}" do
          gem "activesupport", "7.0.7.2"
        end
      end

      require "active_support/all"
    RUBY

    expect(err).to include(/erb was loaded from (.*) from Ruby 3.5.0/)
    expect(err).to include(/lib\/active_support\/all\.rb:1/)
  end

  it "Show warning dash gem like net/smtp" do
    script <<-RUBY
      gemfile do
        source "https://rubygems.org"
      end

      begin
        require "net/smtp"
      rescue LoadError
      end
    RUBY

    expect(err).to include(/net\/smtp was loaded from (.*) from Ruby 3.1.0/)
    expect(err).to include(/-e:17/)
    expect(err).to include("You can add net-smtp")
  end

  it "Show warning sub-feature like fiddle/import" do
    skip "This test is not working on Windows" if Gem.win_platform?

    script <<-RUBY
      gemfile do
        source "https://rubygems.org"
      end

      require "fiddle/import"
    RUBY

    expect(err).to include(/fiddle\/import is found in fiddle, (.*) part of the default gems starting from Ruby 3\.5\.0/)
    expect(err).to include(/-e:16/)
  end

  it "Show warning when bundle exec with ruby and script" do
    code = <<-RUBY
      #{stub_code}
      require "erb"
    RUBY
    create_file("script.rb", code)
    create_file("Gemfile", "source 'https://rubygems.org'")

    bundle "exec ruby script.rb"

    expect(err).to include(/erb was loaded from (.*) from Ruby 3.5.0/)
    expect(err).to include(/script\.rb:10/)
  end

  it "Show warning when bundle exec with shebang's script" do
    skip "This test is not working on Windows" if Gem.win_platform?

    code = <<-RUBY
      #!/usr/bin/env ruby
      #{stub_code}
      require "erb"
    RUBY
    create_file("script.rb", code)
    FileUtils.chmod(0o777, bundled_app("script.rb"))
    create_file("Gemfile", "source 'https://rubygems.org'")

    bundle "exec ./script.rb"

    expect(err).to include(/erb was loaded from (.*) from Ruby 3.5.0/)
    expect(err).to include(/script\.rb:11/)
  end

  it "Show warning when bundle exec with -r option" do
    create_file("stub.rb", stub_code)
    create_file("Gemfile", "source 'https://rubygems.org'")
    bundle "exec ruby -r./stub -rerb -e ''"

    expect(err).to include(/erb was loaded from (.*) from Ruby 3.5.0/)
  end

  it "Show warning when warn is not the standard one in the current scope" do
    script <<-RUBY
      module My
        def warn(msg)
        end

        def my
          gemfile do
            source "https://rubygems.org"
          end

          require "erb"
        end

        extend self
      end

      My.my
    RUBY

    expect(err).to include(/erb was loaded from (.*) from Ruby 3.5.0/)
    expect(err).to include(/-e:21/)
  end

  it "Don't show warning when bundled gems called as dependency" do
    build_lib "activesupport", "7.0.7.2" do |s|
      s.write "lib/active_support/all.rb", "require 'erb'"
    end
    build_lib "erb", "1.0.0" do |s|
      s.write "lib/erb.rb", "puts 'erb'"
    end

    script <<-RUBY, env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo1.to_s }
      gemfile do
        source "https://gem.repo1"
        path "#{lib_path}" do
          gem "activesupport", "7.0.7.2"
          gem "erb"
        end
      end

      require "active_support/all"
    RUBY

    expect(err).to be_empty
  end

  it "Show warning with bootsnap cases" do
    script <<-RUBY
      gemfile do
        source "https://rubygems.org"
        # gem "bootsnap", require: false
      end

      # require 'bootsnap'
      # Bootsnap.setup(cache_dir: 'tmp/cache')

      # bootsnap expand required feature to full path
      # require 'csv'
      require Gem::BUNDLED_GEMS::LIBDIR + 'erb'
    RUBY

    expect(err).to include(/erb was loaded from (.*) from Ruby 3.5.0/)
    # TODO: We should assert caller location like below:
    # test_warn_bootsnap.rb:14: warning: ...
  end

  it "Show warning with bootsnap for gem with native extension" do
    script <<-RUBY
      gemfile do
        source "https://rubygems.org"
        # gem "bootsnap", require: false
      end

      # require 'bootsnap'
      # Bootsnap.setup(cache_dir: 'tmp/cache')

      # bootsnap expand required feature to full path
      # require 'fiddle'
      require Gem::BUNDLED_GEMS::ARCHDIR + "fiddle"
    RUBY

    expect(err).to include(/fiddle was loaded from (.*) from Ruby 3.5.0/)
    # TODO: We should assert caller location like below:
    # test_warn_bootsnap_rubyarchdir_gem.rb:14: warning: ...
  end

  it "Show warning with bootsnap and some gem in Gemfile" do
    # Original issue is childprocess 5.0.0 and logger.
    build_lib "erb2", "5.0.0" do |s|
      # bootsnap expand required feature to full path
      rubylibpath = File.expand_path(File.join(__dir__, "..", "lib"))
      s.write "lib/erb2.rb", "require '#{rubylibpath}/erb'"
    end

    script <<-RUBY
      gemfile do
        source "https://rubygems.org"
        # gem "bootsnap", require: false
        path "#{lib_path}" do
          gem "erb2", "5.0.0"
        end
      end

      # require 'bootsnap'
      # Bootsnap.setup(cache_dir: 'tmp/cache')

      # bootsnap expand required feature to full path
      require Gem.loaded_specs["erb2"].full_gem_path + '/lib/erb2'
    RUBY

    expect(err).to include(/erb was loaded from (.*) from Ruby #{RUBY_VERSION}/)
    # TODO: We should assert caller location like below:
    # $GEM_HOME/gems/childprocess-5.0.0/lib/childprocess.rb:7: warning:
  end

  it "Show warning with zeitwerk" do
    libpath = Dir[File.expand_path("../.bundle/gems/{zeitwerk}-*/lib", __dir__)].map(&:to_s).first
    code = <<-RUBY
      #{stub_code}
      $LOAD_PATH.unshift("#{libpath}")
      require "zeitwerk"
      loader = Zeitwerk::Loader.for_gem(warn_on_extra_files: false)
      loader.setup

      require 'erb'
    RUBY
    create_file("script.rb", code)
    create_file("Gemfile", "source 'https://rubygems.org'")
    bundle "exec ruby script.rb"

    expect(err).to include(/erb was loaded from (.*) from Ruby 3.5.0/)
    expect(err).to include(/script\.rb:15/)
  end

  it "Don't show warning fiddle/import when fiddle on Gemfile" do
    build_lib "fiddle", "1.0.0" do |s|
      s.write "lib/fiddle.rb", "puts 'fiddle'"
      s.write "lib/fiddle/import.rb", "puts 'fiddle/import'"
    end

    script <<-RUBY, env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo1.to_s }
      gemfile do
        source "https://gem.repo1"
        path "#{lib_path}" do
          gem "fiddle"
        end
      end

      require "fiddle/import"
    RUBY

    expect(err).to be_empty
  end

  it "Don't show warning with net/smtp when net-smtp on Gemfile" do
    build_lib "net-smtp", "1.0.0" do |s|
      s.write "lib/net/smtp.rb", "puts 'net-smtp'"
    end

    script <<-RUBY, env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo1.to_s }
      gemfile do
        source "https://gem.repo1"
        path "#{lib_path}" do
          gem "net-smtp"
        end
      end

      require "net/smtp"
    RUBY

    expect(err).to be_empty
  end

  it "Don't show warning for reline when using irb from standard library" do
    create_file("stub.rb", stub_code)
    create_file("Gemfile", "source 'https://rubygems.org'")
    bundle "exec ruby -r./stub -rirb -e ''"

    expect(err).to include(/irb was loaded from (.*) from Ruby 3.5.0/)
    expect(err).to_not include(/reline was loaded from (.*) from Ruby 3.5.0/)
  end
end
