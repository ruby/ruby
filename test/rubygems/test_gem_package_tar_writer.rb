require 'rubygems/package/tar_test_case'
require 'rubygems/package/tar_writer'
require 'minitest/mock'

class TestGemPackageTarWriter < Gem::Package::TarTestCase

  def setup
    super

    @data = 'abcde12345'
    @io = TempIO.new
    @tar_writer = Gem::Package::TarWriter.new @io
  end

  def teardown
    @tar_writer.close unless @tar_writer.closed?

    super
  end

  def test_add_file
    Time.stub :now, Time.at(1458518157) do
      @tar_writer.add_file 'x', 0644 do |f| f.write 'a' * 10 end

      assert_headers_equal(tar_file_header('x', '', 0644, 10, Time.now),
                         @io.string[0, 512])
    end
    assert_equal "aaaaaaaaaa#{"\0" * 502}", @io.string[512, 512]
    assert_equal 1024, @io.pos
  end

  def test_add_file_digest
    digest_algorithms = Digest::SHA1, Digest::SHA512

    Time.stub :now, Time.at(1458518157) do
      digests = @tar_writer.add_file_digest 'x', 0644, digest_algorithms do |io|
        io.write 'a' * 10
      end

      assert_equal '3495ff69d34671d1e15b33a63c1379fdedd3a32a',
                   digests['SHA1'].hexdigest
      assert_equal '4714870aff6c97ca09d135834fdb58a6389a50c1' \
                   '1fef8ec4afef466fb60a23ac6b7a9c92658f14df' \
                   '4993d6b40a4e4d8424196afc347e97640d68de61' \
                   'e1cf14b0',
                   digests['SHA512'].hexdigest

      assert_headers_equal(tar_file_header('x', '', 0644, 10, Time.now),
                         @io.string[0, 512])
    end
    assert_equal "aaaaaaaaaa#{"\0" * 502}", @io.string[512, 512]
    assert_equal 1024, @io.pos
  end

  def test_add_file_digest_multiple
    digest_algorithms = [Digest::SHA1, Digest::SHA512]

    Time.stub :now, Time.at(1458518157) do
      digests = @tar_writer.add_file_digest 'x', 0644, digest_algorithms do |io|
        io.write 'a' * 10
      end

      assert_equal '3495ff69d34671d1e15b33a63c1379fdedd3a32a',
                   digests['SHA1'].hexdigest
      assert_equal '4714870aff6c97ca09d135834fdb58a6389a50c1' \
                   '1fef8ec4afef466fb60a23ac6b7a9c92658f14df' \
                   '4993d6b40a4e4d8424196afc347e97640d68de61' \
                   'e1cf14b0',
                   digests['SHA512'].hexdigest

      assert_headers_equal(tar_file_header('x', '', 0644, 10, Time.now),
                           @io.string[0, 512])
    end
    assert_equal "aaaaaaaaaa#{"\0" * 502}", @io.string[512, 512]
    assert_equal 1024, @io.pos
  end

  def test_add_file_signer
    skip 'openssl is missing' unless defined?(OpenSSL::SSL)

    signer = Gem::Security::Signer.new PRIVATE_KEY, [PUBLIC_CERT]

    Time.stub :now, Time.at(1458518157) do
      @tar_writer.add_file_signed 'x', 0644, signer do |io|
        io.write 'a' * 10
      end

      assert_headers_equal(tar_file_header('x', '', 0644, 10, Time.now),
                           @io.string[0, 512])


      assert_equal "aaaaaaaaaa#{"\0" * 502}", @io.string[512, 512]

      digest = signer.digest_algorithm.new
      digest.update 'a' * 10

      signature = signer.sign digest.digest

      assert_headers_equal(tar_file_header('x.sig', '', 0444, signature.length,
                                           Time.now),
                           @io.string[1024, 512])
      assert_equal "#{signature}#{"\0" * (512 - signature.length)}",
                   @io.string[1536, 512]

      assert_equal 2048, @io.pos
    end

  end

  def test_add_file_signer_empty
    signer = Gem::Security::Signer.new nil, nil

    Time.stub :now, Time.at(1458518157) do

      @tar_writer.add_file_signed 'x', 0644, signer do |io|
        io.write 'a' * 10
      end

      assert_headers_equal(tar_file_header('x', '', 0644, 10, Time.now),
                         @io.string[0, 512])
    end
    assert_equal "aaaaaaaaaa#{"\0" * 502}", @io.string[512, 512]

    assert_equal 1024, @io.pos
  end

  def test_add_file_simple
    Time.stub :now, Time.at(1458518157) do
      @tar_writer.add_file_simple 'x', 0644, 10 do |io| io.write "a" * 10 end

      assert_headers_equal(tar_file_header('x', '', 0644, 10, Time.now),
                         @io.string[0, 512])
    end

    assert_equal "aaaaaaaaaa#{"\0" * 502}", @io.string[512, 512]
    assert_equal 1024, @io.pos
  end

  def test_add_file_simple_padding
    Time.stub :now, Time.at(1458518157) do
      @tar_writer.add_file_simple 'x', 0, 100

      assert_headers_equal tar_file_header('x', '', 0, 100, Time.now),
                         @io.string[0, 512]
    end

    assert_equal "\0" * 512, @io.string[512, 512]
  end

  def test_add_file_simple_data
    @tar_writer.add_file_simple("lib/foo/bar", 0, 10) { |f| f.write @data }
    @tar_writer.flush

    assert_equal @data + ("\0" * (512-@data.size)),
                 @io.string[512, 512]
  end

  def test_add_file_simple_size
    assert_raises Gem::Package::TarWriter::FileOverflow do
      @tar_writer.add_file_simple("lib/foo/bar", 0, 10) do |io|
        io.write "1" * 11
      end
    end
  end

  def test_add_file_unseekable
    assert_raises Gem::Package::NonSeekableIO do
      Gem::Package::TarWriter.new(Object.new).add_file 'x', 0
    end
  end

  def test_close
    @tar_writer.close

    assert_equal "\0" * 1024, @io.string

    e = assert_raises IOError do
      @tar_writer.close
    end
    assert_equal 'closed Gem::Package::TarWriter', e.message

    e = assert_raises IOError do
      @tar_writer.flush
    end
    assert_equal 'closed Gem::Package::TarWriter', e.message

    e = assert_raises IOError do
      @tar_writer.add_file 'x', 0
    end
    assert_equal 'closed Gem::Package::TarWriter', e.message

    e = assert_raises IOError do
      @tar_writer.add_file_simple 'x', 0, 0
    end
    assert_equal 'closed Gem::Package::TarWriter', e.message

    e = assert_raises IOError do
      @tar_writer.mkdir 'x', 0
    end
    assert_equal 'closed Gem::Package::TarWriter', e.message
  end

  def test_mkdir
    Time.stub :now, Time.at(1458518157) do
      @tar_writer.mkdir 'foo', 0644

      assert_headers_equal tar_dir_header('foo', '', 0644, Time.now),
                           @io.string[0, 512]

      assert_equal 512, @io.pos
    end
  end

  def test_split_name
    assert_equal ['b' * 100, 'a' * 155],
                 @tar_writer.split_name("#{'a' * 155}/#{'b' * 100}")

    assert_equal ["#{'qwer/' * 19}bla", 'a' * 151],
                 @tar_writer.split_name("#{'a' * 151}/#{'qwer/' * 19}bla")
  end

  def test_split_name_too_long_name
    name = File.join 'a', 'b' * 100
    assert_equal ['b' * 100, 'a'], @tar_writer.split_name(name)

    assert_raises Gem::Package::TooLongFileName do
      name = File.join 'a', 'b' * 101
      @tar_writer.split_name name
    end
  end

  def test_split_name_too_long_prefix
    name = File.join 'a' * 155, 'b'
    assert_equal ['b', 'a' * 155], @tar_writer.split_name(name)

    assert_raises Gem::Package::TooLongFileName do
      name = File.join 'a' * 156, 'b'
      @tar_writer.split_name name
    end
  end

  def test_split_name_too_long_total
    assert_raises Gem::Package::TooLongFileName do
      @tar_writer.split_name 'a' * 257
    end
  end

end

