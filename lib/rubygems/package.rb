#++
# Copyright (C) 2004 Mauricio Julio Fernández Pradier
# See LICENSE.txt for additional licensing information.
#--

require 'fileutils'
require 'find'
require 'stringio'
require 'yaml'
require 'zlib'

require 'rubygems/digest/md5'
require 'rubygems/security'
require 'rubygems/specification'

# Wrapper for FileUtils meant to provide logging and additional operations if
# needed.
class Gem::FileOperations

  def initialize(logger = nil)
    @logger = logger
  end

  def method_missing(meth, *args, &block)
    case
    when FileUtils.respond_to?(meth)
      @logger.log "#{meth}: #{args}" if @logger
      FileUtils.send meth, *args, &block
    when Gem::FileOperations.respond_to?(meth)
      @logger.log "#{meth}: #{args}" if @logger
      Gem::FileOperations.send meth, *args, &block
    else
      super
    end
  end

end

module Gem::Package

  class Error < StandardError; end
  class NonSeekableIO < Error; end
  class ClosedIO < Error; end
  class BadCheckSum < Error; end
  class TooLongFileName < Error; end
  class FormatError < Error; end

  module FSyncDir
    private
    def fsync_dir(dirname)
      # make sure this hits the disc
      begin
        dir = open(dirname, "r")
        dir.fsync
      rescue # ignore IOError if it's an unpatched (old) Ruby
      ensure
        dir.close if dir rescue nil
      end
    end
  end

  class TarHeader
    FIELDS = [:name, :mode, :uid, :gid, :size, :mtime, :checksum, :typeflag,
      :linkname, :magic, :version, :uname, :gname, :devmajor,
      :devminor, :prefix]
    FIELDS.each {|x| attr_reader x}

    def self.new_from_stream(stream)
      data = stream.read(512)
      fields = data.unpack("A100" +   # record name
                           "A8A8A8" + # mode, uid, gid
                           "A12A12" + # size, mtime
                           "A8A" +    # checksum, typeflag
                           "A100" +   # linkname
                           "A6A2" +   # magic, version
                           "A32" +    # uname
                           "A32" +    # gname
                           "A8A8" +   # devmajor, devminor
                           "A155")    # prefix
      name = fields.shift
      mode = fields.shift.oct
      uid = fields.shift.oct
      gid = fields.shift.oct
      size = fields.shift.oct
      mtime = fields.shift.oct
      checksum = fields.shift.oct
      typeflag = fields.shift
      linkname = fields.shift
      magic = fields.shift
      version = fields.shift.oct
      uname = fields.shift
      gname = fields.shift
      devmajor = fields.shift.oct
      devminor = fields.shift.oct
      prefix = fields.shift

      empty = (data == "\0" * 512)

      new(:name=>name, :mode=>mode, :uid=>uid, :gid=>gid, :size=>size,
          :mtime=>mtime, :checksum=>checksum, :typeflag=>typeflag,
          :magic=>magic, :version=>version, :uname=>uname, :gname=>gname,
          :devmajor=>devmajor, :devminor=>devminor, :prefix=>prefix,
          :empty => empty )
    end

    def initialize(vals)
      unless vals[:name] && vals[:size] && vals[:prefix] && vals[:mode]
        raise ArgumentError, ":name, :size, :prefix and :mode required"
      end
      vals[:uid] ||= 0
      vals[:gid] ||= 0
      vals[:mtime] ||= 0
      vals[:checksum] ||= ""
      vals[:typeflag] ||= "0"
      vals[:magic] ||= "ustar"
      vals[:version] ||= "00"
      vals[:uname] ||= "wheel"
      vals[:gname] ||= "wheel"
      vals[:devmajor] ||= 0
      vals[:devminor] ||= 0
      FIELDS.each {|x| instance_variable_set "@#{x.to_s}", vals[x]}
      @empty = vals[:empty]
    end

    def empty?
      @empty
    end

    def to_s
      update_checksum
      header(checksum)
    end

    def update_checksum
      h = header(" " * 8)
      @checksum = oct(calculate_checksum(h), 6)
    end

    private
    def oct(num, len)
      "%0#{len}o" % num
    end

    def calculate_checksum(hdr)
      #hdr.split('').map { |c| c[0] }.inject { |a, b| a + b } # HACK rubinius
      hdr.unpack("C*").inject{|a,b| a+b}
    end

    def header(chksum)
      # struct tarfile_entry_posix {
      #   char name[100];   # ASCII + (Z unless filled)
      #   char mode[8];     # 0 padded, octal, null
      #   char uid[8];      # ditto
      #   char gid[8];      # ditto
      #   char size[12];    # 0 padded, octal, null
      #   char mtime[12];   # 0 padded, octal, null
      #   char checksum[8]; # 0 padded, octal, null, space
      #   char typeflag[1]; # file: "0"  dir: "5"
      #   char linkname[100]; # ASCII + (Z unless filled)
      #   char magic[6];      # "ustar\0"
      #   char version[2];    # "00"
      #   char uname[32];     # ASCIIZ
      #   char gname[32];     # ASCIIZ
      #   char devmajor[8];   # 0 padded, octal, null
      #   char devminor[8];   # o padded, octal, null
      #   char prefix[155];   # ASCII + (Z unless filled)
      # };
      arr = [name, oct(mode, 7), oct(uid, 7), oct(gid, 7), oct(size, 11),
        oct(mtime, 11), chksum, " ", typeflag, linkname, magic, version,
        uname, gname, oct(devmajor, 7), oct(devminor, 7), prefix]
      str = arr.pack("a100a8a8a8a12a12" + # name, mode, uid, gid, size, mtime
                     "a7aaa100a6a2" + # chksum, typeflag, linkname, magic, version
                     "a32a32a8a8a155") # uname, gname, devmajor, devminor, prefix
      str + "\0" * ((512 - str.size) % 512)
    end
  end

  class TarWriter
    class FileOverflow < StandardError; end
    class BlockNeeded < StandardError; end

    class BoundedStream
      attr_reader :limit, :written
      def initialize(io, limit)
        @io = io
        @limit = limit
        @written = 0
      end

      def write(data)
        if data.size + @written > @limit
          raise FileOverflow,
                  "You tried to feed more data than fits in the file."
        end
        @io.write data
        @written += data.size
        data.size
      end
    end

    class RestrictedStream
      def initialize(anIO)
        @io = anIO
      end

      def write(data)
        @io.write data
      end
    end

    def self.new(anIO)
      writer = super(anIO)
      return writer unless block_given?
      begin
        yield writer
      ensure
        writer.close
      end
      nil
    end

    def initialize(anIO)
      @io = anIO
      @closed = false
    end

    def add_file_simple(name, mode, size)
      raise BlockNeeded unless block_given?
      raise ClosedIO if @closed
      name, prefix = split_name(name)
      header = TarHeader.new(:name => name, :mode => mode,
                             :size => size, :prefix => prefix).to_s
      @io.write header
      os = BoundedStream.new(@io, size)
      yield os
      #FIXME: what if an exception is raised in the block?
      min_padding = size - os.written
      @io.write("\0" * min_padding)
      remainder = (512 - (size % 512)) % 512
      @io.write("\0" * remainder)
    end

    def add_file(name, mode)
      raise BlockNeeded unless block_given?
      raise ClosedIO if @closed
      raise NonSeekableIO unless @io.respond_to? :pos=
      name, prefix = split_name(name)
      init_pos = @io.pos
      @io.write "\0" * 512 # placeholder for the header
      yield RestrictedStream.new(@io)
      #FIXME: what if an exception is raised in the block?
      #FIXME: what if an exception is raised in the block?
      size = @io.pos - init_pos - 512
      remainder = (512 - (size % 512)) % 512
      @io.write("\0" * remainder)
      final_pos = @io.pos
      @io.pos = init_pos
      header = TarHeader.new(:name => name, :mode => mode,
                             :size => size, :prefix => prefix).to_s
      @io.write header
      @io.pos = final_pos
    end

    def mkdir(name, mode)
      raise ClosedIO if @closed
      name, prefix = split_name(name)
      header = TarHeader.new(:name => name, :mode => mode, :typeflag => "5",
                             :size => 0, :prefix => prefix).to_s
      @io.write header
      nil
    end

    def flush
      raise ClosedIO if @closed
      @io.flush if @io.respond_to? :flush
    end

    def close
      #raise ClosedIO if @closed
      return if @closed
      @io.write "\0" * 1024
      @closed = true
    end

    private
    def split_name name
      raise TooLongFileName if name.size > 256
      if name.size <= 100
        prefix = ""
      else
        parts = name.split(/\//)
        newname = parts.pop
        nxt = ""
        loop do
          nxt = parts.pop
          break if newname.size + 1 + nxt.size > 100
          newname = nxt + "/" + newname
        end
        prefix = (parts + [nxt]).join "/"
        name = newname
        raise TooLongFileName if name.size > 100 || prefix.size > 155
      end
      return name, prefix
    end
  end

  class TarReader

    include Gem::Package

    class UnexpectedEOF < StandardError; end

    module InvalidEntry
      def read(len=nil); raise ClosedIO; end
      def getc; raise ClosedIO;  end
      def rewind; raise ClosedIO;  end
    end

    class Entry
      TarHeader::FIELDS.each{|x| attr_reader x}

      def initialize(header, anIO)
        @io = anIO
        @name = header.name
        @mode = header.mode
        @uid = header.uid
        @gid = header.gid
        @size = header.size
        @mtime = header.mtime
        @checksum = header.checksum
        @typeflag = header.typeflag
        @linkname = header.linkname
        @magic = header.magic
        @version = header.version
        @uname = header.uname
        @gname = header.gname
        @devmajor = header.devmajor
        @devminor = header.devminor
        @prefix = header.prefix
        @read = 0
        @orig_pos = @io.pos
      end

      def read(len = nil)
        return nil if @read >= @size
        len ||= @size - @read
        max_read = [len, @size - @read].min
        ret = @io.read(max_read)
        @read += ret.size
        ret
      end

      def getc
        return nil if @read >= @size
        ret = @io.getc
        @read += 1 if ret
        ret
      end

      def is_directory?
        @typeflag == "5"
      end

      def is_file?
        @typeflag == "0"
      end

      def eof?
        @read >= @size
      end

      def pos
        @read
      end

      def rewind
        raise NonSeekableIO unless @io.respond_to? :pos=
          @io.pos = @orig_pos
        @read = 0
      end

      alias_method :is_directory, :is_directory?
      alias_method :is_file, :is_file?

      def bytes_read
        @read
      end

      def full_name
        if @prefix != ""
          File.join(@prefix, @name)
        else
          @name
        end
      end

      def close
        invalidate
      end

      private
      def invalidate
        extend InvalidEntry
      end
    end

    def self.new(anIO)
      reader = super(anIO)
      return reader unless block_given?
      begin
        yield reader
      ensure
        reader.close
      end
      nil
    end

    def initialize(anIO)
      @io = anIO
      @init_pos = anIO.pos
    end

    def each(&block)
      each_entry(&block)
    end

    # do not call this during a #each or #each_entry iteration
    def rewind
      if @init_pos == 0
        raise NonSeekableIO unless @io.respond_to? :rewind
        @io.rewind
      else
        raise NonSeekableIO unless @io.respond_to? :pos=
          @io.pos = @init_pos
      end
    end

    def each_entry
      loop do
        return if @io.eof?
        header = TarHeader.new_from_stream(@io)
        return if header.empty?
        entry = Entry.new header, @io
        size = entry.size
        yield entry
        skip = (512 - (size % 512)) % 512
        if @io.respond_to? :seek
          # avoid reading...
          @io.seek(size - entry.bytes_read, IO::SEEK_CUR)
        else
          pending = size - entry.bytes_read
          while pending > 0
            bread = @io.read([pending, 4096].min).size
            raise UnexpectedEOF if @io.eof?
            pending -= bread
          end
        end
        @io.read(skip) # discard trailing zeros
        # make sure nobody can use #read, #getc or #rewind anymore
        entry.close
      end
    end

    def close
    end

  end

  class TarInput

    include FSyncDir
    include Enumerable

    attr_reader :metadata

    class << self; private :new end

    def initialize(io, security_policy = nil)
      @io = io
      @tarreader = TarReader.new(@io)
      has_meta = false
      data_sig, meta_sig, data_dgst, meta_dgst = nil, nil, nil, nil
      dgst_algo = security_policy ? Gem::Security::OPT[:dgst_algo] : nil

      @tarreader.each do |entry|
        case entry.full_name
        when "metadata"
          @metadata = load_gemspec(entry.read)
          has_meta = true
          break
        when "metadata.gz"
          begin
            # if we have a security_policy, then pre-read the metadata file
            # and calculate it's digest
            sio = nil
            if security_policy
              Gem.ensure_ssl_available
              sio = StringIO.new(entry.read)
              meta_dgst = dgst_algo.digest(sio.string)
              sio.rewind
            end

            gzis = Zlib::GzipReader.new(sio || entry)
            # YAML wants an instance of IO
            @metadata = load_gemspec(gzis)
            has_meta = true
          ensure
            gzis.close unless gzis.nil?
          end
        when 'metadata.gz.sig'
          meta_sig = entry.read
        when 'data.tar.gz.sig'
          data_sig = entry.read
        when 'data.tar.gz'
          if security_policy
            Gem.ensure_ssl_available
            data_dgst = dgst_algo.digest(entry.read)
          end
        end
      end

      if security_policy then
        Gem.ensure_ssl_available

        # map trust policy from string to actual class (or a serialized YAML
        # file, if that exists)
        if String === security_policy then
          if Gem::Security::Policy.key? security_policy then
            # load one of the pre-defined security policies
            security_policy = Gem::Security::Policy[security_policy]
          elsif File.exist? security_policy then
            # FIXME: this doesn't work yet
            security_policy = YAML.load File.read(security_policy)
          else
            raise Gem::Exception, "Unknown trust policy '#{security_policy}'"
          end
        end

        if data_sig && data_dgst && meta_sig && meta_dgst then
          # the user has a trust policy, and we have a signed gem
          # file, so use the trust policy to verify the gem signature

          begin
            security_policy.verify_gem(data_sig, data_dgst, @metadata.cert_chain)
          rescue Exception => e
            raise "Couldn't verify data signature: #{e}"
          end

          begin
            security_policy.verify_gem(meta_sig, meta_dgst, @metadata.cert_chain)
          rescue Exception => e
            raise "Couldn't verify metadata signature: #{e}"
          end
        elsif security_policy.only_signed
          raise Gem::Exception, "Unsigned gem"
        else
          # FIXME: should display warning here (trust policy, but
          # either unsigned or badly signed gem file)
        end
      end

      @tarreader.rewind
      @fileops = Gem::FileOperations.new
      raise FormatError, "No metadata found!" unless has_meta
    end

    # Attempt to YAML-load a gemspec from the given _io_ parameter.  Return
    # nil if it fails.
    def load_gemspec(io)
      Gem::Specification.from_yaml(io)
    rescue Gem::Exception
      nil
    end

    def self.open(filename, security_policy = nil, &block)
      open_from_io(File.open(filename, "rb"), security_policy, &block)
    end

    def self.open_from_io(io, security_policy = nil,  &block)
      raise "Want a block" unless block_given?
      begin
        is = new(io, security_policy)
        yield is
      ensure
        is.close if is
      end
    end

    def each(&block)
      @tarreader.each do |entry|
        next unless entry.full_name == "data.tar.gz"
        is = zipped_stream(entry)
        begin
          TarReader.new(is) do |inner|
            inner.each(&block)
          end
        ensure
          is.close if is
        end
      end
      @tarreader.rewind
    end

    # Return an IO stream for the zipped entry.
    #
    # NOTE:  Originally this method used two approaches, Return a GZipReader
    # directly, or read the GZipReader into a string and return a StringIO on
    # the string.  The string IO approach was used for versions of ZLib before
    # 1.2.1 to avoid buffer errors on windows machines.  Then we found that
    # errors happened with 1.2.1 as well, so we changed the condition.  Then
    # we discovered errors occurred with versions as late as 1.2.3.  At this
    # point (after some benchmarking to show we weren't seriously crippling
    # the unpacking speed) we threw our hands in the air and declared that
    # this method would use the String IO approach on all platforms at all
    # times.  And that's the way it is.
    def zipped_stream(entry)
      # This is Jamis Buck's ZLib workaround.  The original code is
      # commented out while we evaluate this patch.
      entry.read(10) # skip the gzip header
      zis = Zlib::Inflate.new(-Zlib::MAX_WBITS)
      is = StringIO.new(zis.inflate(entry.read))
      # zis = Zlib::GzipReader.new entry
      # dis = zis.read
      # is = StringIO.new(dis)
    ensure
      zis.finish if zis
    end

    def extract_entry(destdir, entry, expected_md5sum = nil)
      if entry.is_directory?
        dest = File.join(destdir, entry.full_name)
        if file_class.dir? dest
          @fileops.chmod entry.mode, dest, :verbose=>false
        else
          @fileops.mkdir_p(dest, :mode => entry.mode, :verbose=>false)
        end
        fsync_dir dest
        fsync_dir File.join(dest, "..")
        return
      end
      # it's a file
      md5 = Digest::MD5.new if expected_md5sum
      destdir = File.join(destdir, File.dirname(entry.full_name))
      @fileops.mkdir_p(destdir, :mode => 0755, :verbose=>false)
      destfile = File.join(destdir, File.basename(entry.full_name))
      @fileops.chmod(0600, destfile, :verbose=>false) rescue nil  # Errno::ENOENT
      file_class.open(destfile, "wb", entry.mode) do |os|
        loop do
          data = entry.read(4096)
          break unless data
          md5 << data if expected_md5sum
          os.write(data)
        end
        os.fsync
      end
      @fileops.chmod(entry.mode, destfile, :verbose=>false)
      fsync_dir File.dirname(destfile)
      fsync_dir File.join(File.dirname(destfile), "..")
      if expected_md5sum && expected_md5sum != md5.hexdigest
        raise BadCheckSum
      end
    end

    def close
      @io.close
      @tarreader.close
    end

    private

    def file_class
      File
    end
  end

  class TarOutput

    class << self; private :new end

    def initialize(io)
      @io = io
      @external = TarWriter.new @io
    end

    def external_handle
      @external
    end

    def self.open(filename, signer = nil, &block)
      io = File.open(filename, "wb")
      open_from_io(io, signer, &block)
      nil
    end

    def self.open_from_io(io, signer = nil, &block)
      outputter = new(io)
      metadata = nil
      set_meta = lambda{|x| metadata = x}
      raise "Want a block" unless block_given?
      begin
        data_sig, meta_sig = nil, nil

        outputter.external_handle.add_file("data.tar.gz", 0644) do |inner|
          begin
            sio = signer ? StringIO.new : nil
            os = Zlib::GzipWriter.new(sio || inner)

            TarWriter.new(os) do |inner_tar_stream|
              klass = class << inner_tar_stream; self end
              klass.send(:define_method, :metadata=, &set_meta)
              block.call inner_tar_stream
            end
          ensure
            os.flush
            os.finish
            #os.close

            # if we have a signing key, then sign the data
            # digest and return the signature
            data_sig = nil
            if signer
              dgst_algo = Gem::Security::OPT[:dgst_algo]
              dig = dgst_algo.digest(sio.string)
              data_sig = signer.sign(dig)
              inner.write(sio.string)
            end
          end
        end

        # if we have a data signature, then write it to the gem too
        if data_sig
          sig_file = 'data.tar.gz.sig'
          outputter.external_handle.add_file(sig_file, 0644) do |os|
            os.write(data_sig)
          end
        end

        outputter.external_handle.add_file("metadata.gz", 0644) do |os|
          begin
            sio = signer ? StringIO.new : nil
            gzos = Zlib::GzipWriter.new(sio || os)
            gzos.write metadata
          ensure
            gzos.flush
            gzos.finish

            # if we have a signing key, then sign the metadata
            # digest and return the signature
            if signer
              dgst_algo = Gem::Security::OPT[:dgst_algo]
              dig = dgst_algo.digest(sio.string)
              meta_sig = signer.sign(dig)
              os.write(sio.string)
            end
          end
        end

        # if we have a metadata signature, then write to the gem as
        # well
        if meta_sig
          sig_file = 'metadata.gz.sig'
          outputter.external_handle.add_file(sig_file, 0644) do |os|
            os.write(meta_sig)
          end
        end

      ensure
        outputter.close
      end
      nil
    end

    def close
      @external.close
      @io.close
    end

  end

  #FIXME: refactor the following 2 methods

  def self.open(dest, mode = "r", signer = nil, &block)
    raise "Block needed" unless block_given?

    case mode
    when "r"
      security_policy = signer
      TarInput.open(dest, security_policy, &block)
    when "w"
      TarOutput.open(dest, signer, &block)
    else
      raise "Unknown Package open mode"
    end
  end

  def self.open_from_io(io, mode = "r", signer = nil, &block)
    raise "Block needed" unless block_given?

    case mode
    when "r"
      security_policy = signer
      TarInput.open_from_io(io, security_policy, &block)
    when "w"
      TarOutput.open_from_io(io, signer, &block)
    else
      raise "Unknown Package open mode"
    end
  end

  def self.pack(src, destname, signer = nil)
    TarOutput.open(destname, signer) do |outp|
      dir_class.chdir(src) do
        outp.metadata = (file_class.read("RPA/metadata") rescue nil)
        find_class.find('.') do |entry|
          case
          when file_class.file?(entry)
            entry.sub!(%r{\./}, "")
            next if entry =~ /\ARPA\//
            stat = File.stat(entry)
            outp.add_file_simple(entry, stat.mode, stat.size) do |os|
              file_class.open(entry, "rb") do |f|
                os.write(f.read(4096)) until f.eof?
              end
            end
          when file_class.dir?(entry)
            entry.sub!(%r{\./}, "")
            next if entry == "RPA"
            outp.mkdir(entry, file_class.stat(entry).mode)
          else
            raise "Don't know how to pack this yet!"
          end
        end
      end
    end
  end

  class << self
    def file_class
      File
    end

    def dir_class
      Dir
    end

    def find_class # HACK kill me
      Find
    end
  end

end

