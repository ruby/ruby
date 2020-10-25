# frozen_string_literal: true
#--
# Copyright 2006 by Chad Fowler, Rich Kilmer, Jim Weirich and others.
# All rights reserved.
# See LICENSE.txt for permissions.
#++

require 'shellwords'

class Gem::Ext::ExtConfBuilder < Gem::Ext::Builder
  def self.build(extension, dest_path, results, args=[], lib_dir=nil)
    require 'fileutils'
    require 'tempfile'

    # SOURCE_EPOCH_DATE is used for reproducible builds. Assume that we are
    # in a build sandbox when it's set.
    if ENV['SOURCE_EPOCH_DATE']
      tmp_dest = Time.at(ENV['SOURCE_EPOCH_DATE'].to_i).strftime(".gem.%Y%m%d")
      Dir.mkdir(tmp_dest)
    else
      tmp_dest = Dir.mktmpdir(".gem.", ".")
    end

    # Some versions of `mktmpdir` return absolute paths, which will break make
    # if the paths contain spaces. However, on Ruby 1.9.x on Windows, relative
    # paths cause all C extension builds to fail.
    #
    # As such, we convert to a relative path unless we are using Ruby 1.9.x on
    # Windows. This means that when using Ruby 1.9.x on Windows, paths with
    # spaces do not work.
    #
    # Details: https://github.com/rubygems/rubygems/issues/977#issuecomment-171544940
    tmp_dest = get_relative_path(tmp_dest)

    Tempfile.open %w[siteconf .rb], "." do |siteconf|
      siteconf.puts "require 'rbconfig'"
      siteconf.puts "dest_path = #{tmp_dest.dump}"
      %w[sitearchdir sitelibdir].each do |dir|
        siteconf.puts "RbConfig::MAKEFILE_CONFIG['#{dir}'] = dest_path"
        siteconf.puts "RbConfig::CONFIG['#{dir}'] = dest_path"
      end

      siteconf.close

      destdir = ENV["DESTDIR"]

      begin
        cmd = Gem.ruby.shellsplit << "-I" << File.expand_path("../../..", __FILE__) <<
              "-r" << get_relative_path(siteconf.path) << File.basename(extension)
        cmd.push(*args)

        begin
          run(cmd, results) do |s, r|
            if File.exist? 'mkmf.log'
              unless s.success?
                r << "To see why this extension failed to compile, please check" \
                  " the mkmf.log which can be found here:\n"
                r << "  " + File.join(dest_path, 'mkmf.log') + "\n"
              end
              FileUtils.mv 'mkmf.log', dest_path
            end
          end
          siteconf.unlink
        end

        ENV["DESTDIR"] = nil

        make dest_path, results

        if tmp_dest
          # TODO remove in RubyGems 3
          if Gem.install_extension_in_lib and lib_dir
            FileUtils.mkdir_p lib_dir
            entries = Dir.entries(tmp_dest) - %w[. ..]
            entries = entries.map {|entry| File.join tmp_dest, entry }
            FileUtils.cp_r entries, lib_dir, :remove_destination => true
          end

          FileUtils::Entry_.new(tmp_dest).traverse do |ent|
            destent = ent.class.new(dest_path, ent.rel)
            destent.exist? or FileUtils.mv(ent.path, destent.path)
          end
        end
      ensure
        ENV["DESTDIR"] = destdir
        siteconf.close!
      end
    end

    results
  ensure
    FileUtils.rm_rf tmp_dest if tmp_dest
  end

  private

  def self.get_relative_path(path)
    path[0..Dir.pwd.length - 1] = '.' if path.start_with?(Dir.pwd)
    path
  end
end
