require 'test/unit'
require File.join(File.expand_path(File.dirname(__FILE__)), 'gemutilities')
require 'rubygems/ext'

class TestGemExtRakeBuilder < RubyGemTestCase

  def setup
    super

    @ext = File.join @tempdir, 'ext'
    @dest_path = File.join @tempdir, 'prefix'

    FileUtils.mkdir_p @ext
    FileUtils.mkdir_p @dest_path
  end

  def test_class_build
    File.open File.join(@ext, 'mkrf_conf.rb'), 'w' do |mkrf_conf|
      mkrf_conf.puts <<-EO_MKRF
        File.open("Rakefile","w") do |f|
          f.puts "task :default"
        end
      EO_MKRF
    end

    output = []
    realdir = nil # HACK /tmp vs. /private/tmp

    Dir.chdir @ext do
      realdir = Dir.pwd
      Gem::Ext::RakeBuilder.build 'mkrf_conf.rb', nil, @dest_path, output
    end

    expected = [
      "#{Gem.ruby} mkrf_conf.rb",
      "",
      "rake RUBYARCHDIR=#{@dest_path} RUBYLIBDIR=#{@dest_path}",
      "(in #{realdir})\n"
    ]

    assert_equal expected, output
  end

  def test_class_build_fail
    File.open File.join(@ext, 'mkrf_conf.rb'), 'w' do |mkrf_conf|
      mkrf_conf.puts <<-EO_MKRF
        File.open("Rakefile","w") do |f|
          f.puts "task :default do abort 'fail' end"
        end
        EO_MKRF
    end

    output = []

    error = assert_raise Gem::InstallError do
      Dir.chdir @ext do
        Gem::Ext::RakeBuilder.build "mkrf_conf.rb", nil, @dest_path, output
      end
    end

    expected = <<-EOF.strip
rake failed:

#{Gem.ruby} mkrf_conf.rb

rake RUBYARCHDIR=#{@dest_path} RUBYLIBDIR=#{@dest_path}
    EOF

    assert_equal expected, error.message.split("\n")[0..4].join("\n")
  end

end

