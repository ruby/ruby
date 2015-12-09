#
# iseq_loader.rb - sample of compiler/loader for binary compiled file
#
# Usage as a compiler: ruby iseq_loader.rb [file or directory] ...
#
#   It compiles and stores specified files.
#   If directories are specified, then compiles and stores all *.rb files.
#   (using Dir.glob)
#
# TODO: add remove option
# TODO: add verify option
#
# Usage as a loader: simply require this file with the following setting.
#
# Setting with environment variables.
#
#  * RUBY_ISEQ_LOADER_STORAGE to select storage type
#    * dbm: use dbm
#    * fs: [default] use file system. locate a compiled binary files in same
#      directory of scripts like Rubinius. foo.rb.yarb will be created for foo.rb.
#    * fs2: use file system. locate compiled file in specified directory.
#    * nothing: do nothing.
#
#  * RUBY_ISEQ_LOADER_STORAGE_DIR to select directory
#    * default: ~/.ruby_binaries/
#
#  * RUBY_ISEQ_LOADER_STORAGE_COMPILE_IF_NOT_COMPILED
#    * true: store compiled file if compiled data is not available.
#    * false: [default] do nothing if there is no compiled iseq data.

class RubyVM::InstructionSequence
  $ISEQ_LOADER_LOADED = 0
  $ISEQ_LOADER_COMPILED = 0
  $ISEQ_LOADER_IGNORED = 0
  LAUNCHED_TIME = Time.now
  COMPILE_FILE_ENABLE = false || true
  COMPILE_VERBOSE = $VERBOSE || false # || true
  COMPILE_DEBUG = ENV['RUBY_ISEQ_LOADER_DEBUG']
  COMPILE_IF_NOT_COMPILED = ENV['RUBY_ISEQ_LOADER_STORAGE_COMPILE_IF_NOT_COMPILED'] == 'true'

  at_exit{
    STDERR.puts "[ISEQ_LOADER] #{Process.pid} time: #{Time.now - LAUNCHED_TIME}, " +
                "loaded: #{$ISEQ_LOADER_LOADED}, " +
                "compied: #{$ISEQ_LOADER_COMPILED}, " +
                "ignored: #{$ISEQ_LOADER_IGNORED}"
  } if COMPILE_VERBOSE

  unless cf_dir = ENV['RUBY_ISEQ_LOADER_STORAGE_DIR']
    cf_dir = File.expand_path("~/.ruby_binaries")
    unless File.exist?(cf_dir)
      Dir.mkdir(cf_dir)
    end
  end
  CF_PREFIX = "#{cf_dir}/cb."

  class NullStorage
    def load_iseq fname; end
    def compile_and_save_isq fname; end
    def unlink_compiled_iseq; end
  end

  class BasicStorage
    def initialize
      require 'digest/sha1'
    end

    def load_iseq fname
      iseq_key = iseq_key_name(fname)
      if compiled_iseq_exist?(fname, iseq_key) && compiled_iseq_is_younger?(fname, iseq_key)
        $ISEQ_LOADER_LOADED += 1
        STDERR.puts "[ISEQ_LOADER] #{Process.pid} load #{fname} from #{iseq_key}" if COMPILE_DEBUG
        binary = read_compiled_iseq(fname, iseq_key)
        iseq = RubyVM::InstructionSequence.load_from_binary(binary)
        # p [extra_data(iseq.path), RubyVM::InstructionSequence.load_from_binary_extra_data(binary)]
        # raise unless extra_data(iseq.path) == RubyVM::InstructionSequence.load_from_binary_extra_data(binary)
        iseq
      elsif COMPILE_IF_NOT_COMPILED
        compile_and_save_iseq(fname, iseq_key)
      else
        $ISEQ_LOADER_IGNORED += 1
        # p fname
        nil
      end
    end

    def extra_data fname
      "SHA-1:#{::Digest::SHA1.file(fname).digest}"
    end

    def compile_and_save_iseq fname, iseq_key = iseq_key_name(fname)
      $ISEQ_LOADER_COMPILED += 1
      STDERR.puts "[RUBY_COMPILED_FILE] compile #{fname}" if COMPILE_DEBUG
      iseq = RubyVM::InstructionSequence.compile_file(fname)

      binary = iseq.to_binary(extra_data(fname))
      write_compiled_iseq(fname, iseq_key, binary)
      iseq
    end

    # def unlink_compiled_iseq; nil; end # should implement at sub classes

    private

    def iseq_key_name fname
      fname
    end

    # should implement at sub classes
    # def compiled_iseq_younger? fname, iseq_key; end
    # def compiled_iseq_exist? fname, iseq_key; end
    # def read_compiled_file fname, iseq_key; end
    # def write_compiled_file fname, iseq_key, binary; end
  end

  class FSStorage < BasicStorage
    def initialize
      super
      require 'fileutils'
      @dir = CF_PREFIX + "files"
      unless File.directory?(@dir)
        FileUtils.mkdir_p(@dir)
      end
    end

    def unlink_compiled_iseq
      File.unlink(compile_file_path)
    end

    private

    def iseq_key_name fname
      "#{fname}.yarb" # same directory
    end

    def compiled_iseq_exist? fname, iseq_key
      File.exist?(iseq_key)
    end

    def compiled_iseq_is_younger? fname, iseq_key
      File.mtime(iseq_key) >= File.mtime(fname)
    end

    def read_compiled_iseq fname, iseq_key
      open(iseq_key, 'rb'){|f| f.read}
    end

    def write_compiled_iseq fname, iseq_key, binary
      open(iseq_key, 'wb'){|f| f.write(binary)}
    end
  end

  class FS2Storage < FSStorage
    def iseq_key_name fname
      @dir + fname.gsub(/[^A-Za-z0-9\._-]/){|c| '%02x' % c.ord} # special directory
    end
  end

  class DBMStorage < BasicStorage
    def initialize
      require 'dbm'
      @db = DBM.open(CF_PREFIX+'db')
    end

    def unlink_compiled_iseq
      @db.delete fname
    end

    private

    def date_key_name fname
      "date.#{fname}"
    end

    def iseq_key_name fname
      "body.#{fname}"
    end

    def compiled_iseq_exist? fname, iseq_key
      @db.has_key? iseq_key
    end

    def compiled_iseq_is_younger? fname, iseq_key
      date_key = date_key_name(fname)
      if @db.has_key? date_key
        @db[date_key].to_i >= File.mtime(fname).to_i
      end
    end

    def read_compiled_iseq fname, iseq_key
      @db[iseq_key]
    end

    def write_compiled_iseq fname, iseq_key, binary
      date_key = date_key_name(fname)
      @db[iseq_key] = binary
      @db[date_key] = Time.now.to_i
    end
  end

  STORAGE = case ENV['RUBY_ISEQ_LOADER_STORAGE']
            when 'dbm'
              DBMStorage.new
            when 'fs'
              FSStorage.new
            when 'fs2'
              FS2Storage.new
            when 'null'
              NullStorage.new
            else
              FSStorage.new
            end

  STDERR.puts "[ISEQ_LOADER] use #{STORAGE.class} " if COMPILE_VERBOSE

  def self.load_iseq fname
    STORAGE.load_iseq(fname)
  end

  def self.compile_and_save_iseq fname
    STORAGE.compile_and_save_iseq fname
  end

  def self.unlink_compiled_iseq fname
    STORAGE.unlink_compiled_iseq fname
  end
end

if __FILE__ == $0
  ARGV.each{|path|
    if File.directory?(path)
      pattern = File.join(path, '**/*.rb')
      Dir.glob(pattern){|file|
        begin
          RubyVM::InstructionSequence.compile_and_save_iseq(file)
        rescue SyntaxError => e
          STDERR.puts e
        end
      }
    else
      RubyVM::InstructionSequence.compile_and_save_iseq(path)
    end
  }
end
