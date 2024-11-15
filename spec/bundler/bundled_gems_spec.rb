require "bundled_gems"

RSpec.describe "bundled_gems.rb" do
  ENV["TEST_BUNDLED_GEMS"] = "true"

  def script(code, options = {})
    options[:artifice] ||= "compact_index"
    ruby("require 'bundler/inline'\n\n" + code, options)
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
      require "ostruct"
    RUBY

    expect(err).to include(/csv was loaded from (.*) from Ruby 3.4.0/)
    expect(err).to include(/ostruct was loaded from (.*) from Ruby 3.5.0/)
  end

  it "Show warning when bundled gems called as dependency" do
    build_lib "activesupport", "7.0.7.2" do |s|
      s.write "lib/active_support/all.rb", "require 'ostruct'"
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

    expect(err).to include(/ostruct was loaded from (.*) from Ruby 3.5.0/)
    # TODO: We should assert caller location like below:
    # $GEM_HOME/gems/activesupport-7.0.7.2/lib/active_support/core_ext/big_decimal.rb:3: warning: bigdecimal ...
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
    expect(err).to include("You can add net-smtp")
  end

  it "Show warning sub-feature like fiddle/import" do
    script <<-RUBY
      gemfile do
        source "https://rubygems.org"
      end

      require "fiddle/import"
    RUBY

    expect(err).to include(/fiddle was loaded from (.*) from Ruby 3.5.0/)
  end

  it "Show warning when bundle exec with ruby and script" do
    code = <<-RUBY
      require "ostruct"
    RUBY
    create_file("script.rb", code)
    create_file("Gemfile", "source 'https://rubygems.org'")

    bundle "exec ruby script.rb"

    expect(err).to include(/ostruct was loaded from (.*) from Ruby 3.5.0/)
  end

  it "Show warning when bundle exec with shebang's script" do
    code = <<-RUBY
      #!/usr/bin/env ruby
      require "ostruct"
    RUBY
    create_file("script.rb", code)
    FileUtils.chmod(0o777, bundled_app("script.rb"))
    create_file("Gemfile", "source 'https://rubygems.org'")

    bundle "exec ./script.rb"

    expect(err).to include(/ostruct was loaded from (.*) from Ruby 3.5.0/)
  end

  it "Show warning when bundle exec with -r option" do
    create_file("Gemfile", "source 'https://rubygems.org'")
    bundle "exec ruby -rostruct -e ''"

    expect(err).to include(/ostruct was loaded from (.*) from Ruby 3.5.0/)
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

          require "ostruct"
        end

        extend self
      end

      My.my
    RUBY

    expect(err).to include(/ostruct was loaded from (.*) from Ruby 3.5.0/)
  end

  it "Show warning when bundled gems called as dependency" do
    build_lib "activesupport", "7.0.7.2" do |s|
      s.write "lib/active_support/all.rb", "require 'ostruct'"
    end
    build_lib "ostruct", "1.0.0" do |s|
      s.write "lib/ostruct.rb", "puts 'ostruct'"
    end

    script <<-RUBY, env: { "BUNDLER_SPEC_GEM_REPO" => gem_repo1.to_s }
      gemfile do
        source "https://gem.repo1"
        path "#{lib_path}" do
          gem "activesupport", "7.0.7.2"
          gem "ostruct"
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
      require Gem::BUNDLED_GEMS::LIBDIR + 'ostruct'
    RUBY

    expect(err).to include(/ostruct was loaded from (.*) from Ruby 3.5.0/)
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
    build_lib "childprocess", "5.0.0" do |s|
      # bootsnap expand required feature to full path
      # require 'logger'
      rubylibpath = File.expand_path(File.join(__dir__, "..", "..", "lib"))
      s.write "lib/childprocess.rb", "require '#{rubylibpath}/logger'"
    end

    script <<-RUBY
      gemfile do
        source "https://rubygems.org"
        # gem "bootsnap", require: false
        path "#{lib_path}" do
          gem "childprocess", "5.0.0"
        end
      end

      # require 'bootsnap'
      # Bootsnap.setup(cache_dir: 'tmp/cache')

      # bootsnap expand required feature to full path
      # require 'childprocess'
      require Gem.loaded_specs["childprocess"].full_gem_path + '/lib/childprocess'
    RUBY

    expect(err).to include(/logger was loaded from (.*) from Ruby 3.5.0/)
    # TODO: We should assert caller location like below:
    # $GEM_HOME/gems/childprocess-5.0.0/lib/childprocess.rb:7: warning:
  end

  it "Show warning with zeitwerk" do
    libpath = Dir[Spec::Path.base_system_gem_path.join("gems/{zeitwerk}-*/lib")].map(&:to_s).first
    code = <<-RUBY
      $LOAD_PATH.unshift("#{libpath}")
      require "zeitwerk"
      loader = Zeitwerk::Loader.for_gem(warn_on_extra_files: false)
      loader.setup

      require 'ostruct'
    RUBY
    create_file("script.rb", code)
    create_file("Gemfile", "source 'https://rubygems.org'")
    bundle "exec ruby script.rb"

    expect(err).to include(/ostruct was loaded from (.*) from Ruby 3.5.0/)
    # TODO: We should assert caller location like below:
    # test_warn_zeitwerk.rb:15: warning: ...
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
    create_file("Gemfile", "source 'https://rubygems.org'")
    bundle "exec ruby -rirb -e ''"

    expect(err).to include(/irb was loaded from (.*) from Ruby 3.5.0/)
    expect(err).to_not include(/reline was loaded from (.*) from Ruby 3.5.0/)
  end
end
