# frozen_string_literal: true

require "bundler/version"

if Bundler::VERSION > "2.6.9"
  require "bundler"
else
  previous_platforms = {}

  platform_const_list = ["JAVA", "MSWIN", "MSWIN64", "MINGW", "X64_MINGW_LEGACY", "X64_MINGW", "UNIVERSAL_MINGW", "WINDOWS", "X64_LINUX", "X64_LINUX_MUSL"]

  platform_const_list.each do |platform|
    previous_platforms[platform] = Gem::Platform.const_get(platform)
    Gem::Platform.send(:remove_const, platform)
  end

  require "bundler"

  platform_const_list.each do |platform|
    Gem::Platform.send(:remove_const, platform) if Gem::Platform.const_defined?(platform)
    Gem::Platform.const_set(platform, previous_platforms[platform])
  end
end
