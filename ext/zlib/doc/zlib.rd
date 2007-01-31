=begin
#
# zlib.rd.src
#
#   Copyright (C) UENO Katsuhiro 2000-2003
#
# $Id: zlib.rd,v 1.1.2.1 2004/03/28 14:10:39 akr Exp $
#

= Ruby/zlib version 0.6.0

Ruby/zlib is an extension library to use zlib from Ruby.
Ruby/zlib also provides the features for accessing gzipped files.

You can modify or redistribute Ruby/zlib in the same manner of
Ruby interpreter. The latest version of Ruby/zlib would be found
at ((<URL:http://www.blue.sky.or.jp/>)).

Any comments and suggestions are always welcome. Please send
them to ruby-list ML, ruby-ext ML, ruby-talk ML, or the author's
mail address ((<URL:mailto:katsu@blue.sky.or.jp>)).

This document is experimental and broken English version.
If you find some mistakes or strange expressions (including
kidding or unnatural ones) in this document, please let me know
for my study.

* ((<Zlib>))

  * ((<Zlib::Error>))
  * ((<Zlib::ZStream>))
  * ((<Zlib::Deflate>))
  * ((<Zlib::Inflate>))
  * ((<Zlib::GzipFile>))
  * ((<Zlib::GzipFile::Error>))
  * ((<Zlib::GzipWriter>))
  * ((<Zlib::GzipReader>))

* ((<Changes from 0.5 to 0.6>))
* ((<Changes from 0.4 to 0.5>))

== Zlib

Zlib is the module which provides the other features in zlib C
library. See zlib.h for detail of each module function.

=== Module Functions:

--- Zlib.zlib_version

    Returns the string which represents the version of zlib
    library.

--- Zlib.adler32([string[, adler]])

    Calculates Alder-32 checksum for ((|string|)),
    and returns updated value of ((|alder|)).
    If ((|string|)) is omitted, it returns the Adler-32 initial
    value. If ((|alder|)) is omitted, it assumes that the initial
    value is given to ((|alder|)).

--- Zlib.crc32([string[, crc]])

    Calculates CRC checksum for ((|string|)), and returns
    updated value of ((|crc|)). If ((|string|)) is omitted,
    it returns the CRC initial value. ((|crc|)) is omitted,
    it assumes that the initial value is given to ((|crc|)).

--- Zlib.crc_table

    Returns the table for calculating CRC checksum as an array.

=== Constants:

--- Zlib::VERSION

    The Ruby/zlib version string.

--- Zlib::ZLIB_VERSION

    The string which represents the version of zlib.h.

--- Zlib::BINARY
--- Zlib::ASCII
--- Zlib::UNKNOWN

    The integers representing data types which
    ((<Zlib::ZStream#data_type>)) method returns.

--- Zlib::NO_COMPRESSION
--- Zlib::BEST_SPEED
--- Zlib::BEST_COMPRESSION
--- Zlib::DEFAULT_COMPRESSION

    The integers representing compression levels which are
    an argument for ((<Zlib::Deflate.new>)),
    ((<Zlib::Deflate#deflate>)), and so on.

--- Zlib::FILTERED
--- Zlib::HUFFMAN_ONLY
--- Zlib::DEFAULT_STRATEGY

    The integers representing compression methods which are
    an argument for ((<Zlib::Deflate.new>)) and
    ((<Zlib::Deflate#params>)).

--- Zlib::DEF_MEM_LEVEL
--- Zlib::MAX_MEM_LEVEL

    The integers representing memory levels which are an
    argument for ((<Zlib::Deflate.new>)),
    ((<Zlib::Deflate#params>)), and so on.

--- Zlib::MAX_WBITS

    The default value of ((|windowBits|)) which is an argument for
    ((<Zlib::Deflate.new>)) and ((<Zlib::Inflate.new>)).

--- Zlib::NO_FLUSH
--- Zlib::SYNC_FLUSH
--- Zlib::FULL_FLUSH
--- Zlib::FINISH

    The integers to control the output of the deflate stream,
    which are an argument for ((<Zlib::Deflate#deflate>)) and so on.

--- Zlib::OS_CODE
--- Zlib::OS_MSDOS
--- Zlib::OS_AMIGA
--- Zlib::OS_VMS
--- Zlib::OS_UNIX
--- Zlib::OS_VMCMS
--- Zlib::OS_ATARI
--- Zlib::OS_OS2
--- Zlib::OS_MACOS
--- Zlib::OS_ZSYSTEM
--- Zlib::OS_CPM
--- Zlib::OS_TOPS20
--- Zlib::OS_WIN32
--- Zlib::OS_QDOS
--- Zlib::OS_RISCOS
--- Zlib::OS_UNKNOWN

    The return values of ((<Zlib::GzipFile#os_code>)) method.


== Zlib::Error

The superclass for all exceptions raised by Ruby/zlib.

The following exceptions are defined as subclasses of Zlib::Error.
These exceptions are raised when zlib library functions return
with an error status.

  * Zlib::StreamEnd
  * Zlib::NeedDict
  * Zlib::DataError
  * Zlib::StreamError
  * Zlib::MemError
  * Zlib::BufError
  * Zlib::VersionError

=== SuperClass:

* StandardError


== Zlib::ZStream

The abstract class for the stream which handles the compressed
data. The operations are defined in the subclasses,
((<Zlib::Deflate>)) for compression, and ((<Zlib::Inflate>))
for decompression.

An instance of Zlib::ZStream has one stream (struct zstream) and
two variable-length buffers which associated to the input
(next_in) of the stream and the output (next_out) of the stream.
In this document, "input buffer" means the buffer for input, and
"output buffer" means the buffer for output.

Data inputed into an instance of Zlib::ZStream are temporally
stored into the end of input buffer, and then data in input buffer
are processed from the beginning of the buffer until no more
output from the stream is produced (i.e. until avail_out > 0
after processing). During processing, output buffer is allocated
and expanded automatically to hold all output data.

Some particular instance methods consume the data in output buffer
and return them as a String.

Here is an ascii art for describing above:

     +================ an instance of Zlib::ZStream ================+
     ||                                                            ||
     ||     +--------+          +-------+          +--------+      ||
     ||  +--| output |<---------|zstream|<---------| input  |<--+  ||
     ||  |  | buffer |  next_out+-------+next_in   | buffer |   |  ||
     ||  |  +--------+                             +--------+   |  ||
     ||  |                                                      |  ||
     +===|======================================================|===+
         |                                                      |
         v                                                      |
     "output data"                                         "input data"

If an error is occurred during processing input buffer,
an exception which is a subclass of ((<Zlib::Error>)) is raised.
At that time, both input and output buffer keeps their conditions
at the time when the error is occurred.

=== SuperClass:

* Object

=== Class Methods:

--- Zlib::ZStream.new

    See ((<Zlib::Deflate.new>)) and ((<Zlib::Inflate.new>)).

=== Methods:

--- Zlib::ZStream#avail_in

    Returns bytes of data in input buffer.
    Normally, returns 0.

--- Zlib::ZStream#avail_out

    Returns bytes of free spaces in output buffer.
    Because the free spaces are allocated automatically,
    this method returns 0 normally.

--- Zlib::ZStream#avail_out = size

    Allocates free spaces of ((|size|)) bytes in output buffer.
    If there are more than ((|size|)) bytes spaces in the buffer,
    the buffer is truncated.
    Because the free spaces are allocated automatically,
    you usually need not to use this method.

--- Zlib::ZStream#flush_next_in

    Flushes input buffer and returns all data in that buffer.

--- Zlib::ZStream#flush_next_out

    Flushes output buffer and returns all data in that buffer.

--- Zlib::ZStream#total_in

    Returns the total bytes of the input data to the stream.

--- Zlib::ZStream#total_out

    Returns the total bytes of the output data from the stream.

--- Zlib::ZStream#data_type

    Guesses the type of the data which have been inputed into
    the stream. The returned value is either ((<Zlib::BINARY>)),
    ((<Zlib::ASCII>)), or ((<Zlib::UNKNOWN>)).

--- Zlib::ZStream#adler

    Returns the alder-32 checksum.

--- Zlib::ZStream#reset

    Resets and initializes the stream. All data in both
    input and output buffer are discarded.

--- Zlib::ZStream#finish

    Finishes the stream and flushes output buffer.
    See ((<Zlib::Deflate#finish>)) and ((<Zlib::Inflate#finish>))
    for detail of the behavior.

--- Zlib::ZStream#finished?
--- Zlib::ZStream#stream_end?

    Returns true if the stream is finished.

--- Zlib::ZStream#close
--- Zlib::ZStream#end

    Closes the stream. All operations on the closed stream
    will raise an exception.

--- Zlib::ZStream#closed?
--- Zlib::ZStream#ended?

    Returns true if the stream closed.


== Zlib::Deflate

The class for compressing string data.

=== SuperClass:

* ((<Zlib::ZStream>))

=== Class Methods:

--- Zlib::Deflate.deflate(string[, level])

    Compresses ((|string|)). The avail values of ((|level|)) are
    ((<Zlib::NO_COMPRESSION>)), ((<Zlib::BEST_SPEED>)),
    ((<Zlib::BEST_COMPRESSION>)), ((<Zlib::DEFAULT_COMPRESSION>)),
    and the integer from 0 to 9.

    This method is almost equivalent to the following code:

      def deflate(string, level)
        z = Zlib::Deflate.new(level)
        dst = z.deflate(string, Zlib::FINISH)
        z.close
        dst
      end

--- Zlib::Deflate.new([level[, windowBits[, memlevel[, strategy]]]])

    Creates a new deflate stream for compression.
    See zlib.h for details of each argument.
    If an argument is nil, the default value of that
    argument is used.

=== Methods:

--- Zlib::Deflate#clone

    Duplicates the deflate stream.

--- Zlib::Deflate#deflate(string[, flush])

    Inputs ((|string|)) into the deflate stream and returns
    the output from the stream. Calling this method,
    both input and output buffer of the stream are flushed.
    If ((|string|)) is nil, this method finishes the stream,
    just like ((<Zlib::ZStream#finish>)).
    The value of ((|flush|)) should be either ((<Zlib::NO_FLUSH>)),
    ((<Zlib::SYNC_FLUSH>)), ((<Zlib::FULL_FLUSH>)), or
    ((<Zlib::FINISH>)).
    See zlib.h for details.

--- Zlib::Deflate#<< string

    Inputs ((|string|)) into the deflate stream just like
    ((<Zlib::Deflate#deflate>)), but returns Zlib::Deflate object
    itself. The output from the stream is preserved in output
    buffer.

--- Zlib::Deflate#flush([flush])

    This method is equivalent to (({deflate('', ((|flush|)))})).
    If ((|flush|)) is omitted, ((<Zlib::SYNC_FLUSH>)) is used
    as ((|flush|)). This method is just provided for
    readability of your Ruby script.

--- Zlib::Deflate#finish

    Finishes the stream. This method is equivalent to
    (({deflate('', Zlib::FINISH)})).

--- Zlib::Deflate#params(level, strategy)

    Changes the parameters of the deflate stream.
    See zlib.h for details. The output from the stream
    by changing the params is preserved in output buffer.

--- Zlib::Deflate#set_dictionary(string)

    Sets the preset dictionary and returns ((|string|)).
    This method is available just only after
    ((<Zlib::Deflate.new>)) or ((<Zlib::ZStream#reset>)) method
    was called. See zlib.h for details.


== Zlib::Inflate

The class for decompressing compressed data.
Unlike ((<Zlib::Deflate>)), an instance of this class is not able
to duplicate (clone, dup) itself.

=== SuperClass:

* ((<Zlib::ZStream>))

=== Class Methods:

--- Zlib::Inflate.inflate(string)

    Decompresses ((|string|)). Raises a ((<Zlib::NeedDict>))
    exception if a preset dictionary is needed for decompression.

    This method is almost equivalent to the following code:

      def inflate(string)
        zstream = Zlib::Inflate.new
        buf = zstream.inflate(string)
        zstream.finish
        zstream.close
        buf
      end

--- Zlib::Inflate.new([windowBits])

    Creates a new inflate stream for decompression.
    See zlib.h for details of the argument.
    If ((|windowBits|)) is nil, the default value is used.

=== Methods:

--- Zlib::Inflate#inflate(string)

    Inputs ((|string|)) into the inflate stream and returns
    the output from the stream. Calling this method,
    both input and output buffer of the stream are flushed.
    If ((|string|)) is nil, this method finishes the stream,
    just like ((<Zlib::ZStream#finish>)).

    Raises a ((<Zlib::NeedDict>)) exception if a preset
    dictionary is needed to decompress. Set the dictionary
    by ((<Zlib::Inflate#set_dictionary>)) and then call
    this method again with an empty string.

--- Zlib::Inflate#<< string

    Inputs ((|string|)) into the inflate stream just like
    ((<Zlib::Inflate#inflate>)), but returns Zlib::Inflate object
    itself. The output from the stream is preserved in output
    buffer.

--- Zlib::Inflate#finish

    Finishes the inflate stream and returns the garbage
    following the compressed data. Raises an exception
    if the stream is not finished
    (i.e. ((<Zlib::ZStream#finished?>)) doesn't returns true).

    The inflate stream finishes itself as soon as it meets
    the end code of the compressed data, you need not to call
    this method explicitly. However, this method is useful
    for checking whether the data is correctly ended or not.

--- Zlib::Inflate#set_dictionary(string)

    Sets the preset dictionary and returns ((|string|))
    This method is available just only after a ((<Zlib::NeedDict>))
    exception was raised. See zlib.h for details.

--- Zlib::Inflate#sync(string)

    Inputs ((|string|)) into the end of input buffer and
    skips data until a full flush point can be found.
    If the point is found in the buffer, this method flushes
    the buffer and returns false. Otherwise it returns true
    and the following data of full flush point is preserved
    in the buffer.

--- Zlib::Inflate#sync_point?

    What is this?


== Zlib::GzipFile

The abstract class for handling a gzip formatted compressed file.
The operations are defined in the subclasses,
((<Zlib::GzipReader>)) for reading, and ((<Zlib::GzipWriter>))
for writing.

GzipReader should be used with associating an instance of IO class
(or an object which has the same methods as IO has).

=== SuperClass:

* Object

=== Class Methods:

--- Zlib::GzipFile.new(args...)

    See ((<Zlib::GzipReader.new>)) and ((<Zlib::GzipWriter.new>)).

--- Zlib::GzipFile.wrap(args...) {|gz| ... }

    See ((<Zlib::GzipReader.wrap>)) and ((<Zlib::GzipWriter.wrap>)).

--- Zlib::GzipFile.open(args...) {|gz| ... }

    See ((<Zlib::GzipReader.open>)) and ((<Zlib::GzipWriter.open>)).

=== Methods:

--- Zlib::GzipFile#closed?
--- Zlib::GzipFile#to_io

    Same as IO.

--- Zlib::GzipFile#close

    Closes the GzipFile object. This method calls close method
    of the associated IO object. Returns the associated IO object.

--- Zlib::GzipFile#finish

    Closes the GzipFile object. Unlike ((<Zlib::GzipFile#close>)),
    this method ((*never*)) calls close method of the associated IO
    object. Returns the associated IO object.

--- Zlib::GzipFile#crc

    Returns CRC value of the uncompressed data.

--- Zlib::GzipFile#level

    Returns compression level.

--- Zlib::GzipFile#mtime

    Returns last modification time recorded in the gzip
    file header.

--- Zlib::GzipFile#os_code

    Returns OS code number recorded in the gzip file header.

--- Zlib::GzipFile#orig_name

    Returns original filename recorded in the gzip file header,
    or nil if original filename is not present.

--- Zlib::GzipFile#comment

    Returns comments recorded in the gzip file header, or
    nil if the comments is not present.

--- Zlib::GzipFile#sync
--- Zlib::GzipFile#sync= flag

    Same as IO. If ((|flag|)) is true, the associated IO object
    must respond to flush method. While `sync' mode is true,
    the compression ratio decreases sharply.


== Zlib::GzipFile::Error

The superclass for all exceptions raised during processing a gzip
file.

The following exceptions are defined as subclasses of
Zlib::GzipFile::Error.

: Zlib::GzipFile::NoFooter

    Raised when gzip file footer has not found.

: Zlib::GzipFile::CRCError

    Raised when the CRC checksum recorded in gzip file footer
    is not equivalent to CRC checksum of the actually
    uncompressed data.

: Zlib::GzipFile::LengthError

    Raised when the data length recorded in gzip file footer
    is not equivalent to length of the actually uncompressed data.

=== SuperClass:

* ((<Zlib::Error>))


== Zlib::GzipReader

The class for reading a gzipped file. GzipReader should be used
with associating an instance of IO class (or an object which has
the same methods as IO has).

    Zlib::GzipReader.open('hoge.gz') {|gz|
      print gz.read
    }

    f = File.open('hoge.gz')
    gz = Zlib::GzipReader.new(f)
    print gz.read
    gz.close

=== SuperClass:

* ((<Zlib::GzipFile>))

=== Included Modules:

* Enumerable

=== Class Methods:

--- Zlib::GzipReader.new(io)

    Creates a GzipReader object associated with ((|io|)).
    The GzipReader object reads gzipped data from ((|io|)),
    and parses/decompresses them. At least, ((|io|)) must have
    read method that behaves same as read method in IO class.

    If the gzip file header is incorrect, raises an
    ((<Zlib::GzipFile::Error>)) exception.

--- Zlib::GzipReader.wrap(io) {|gz| ... }

    Creates a GzipReader object associated with ((|io|)), and
    executes the block with the newly created GzipReader object,
    just like File::open. The GzipReader object will be closed
    automatically after executing the block. If you want to keep
    the associated IO object opening, you may call
    ((<Zlib::GzipFile#finish>)) method in the block.

--- Zlib::GzipReader.open(filename)
--- Zlib::GzipReader.open(filename) {|gz| ... }

    Opens a file specified by ((|filename|)) as a gzipped file,
    and returns a GzipReader object associated with that file.
    Further details of this method are same as
    ((<Zlib::GzipReader.new>)) and ((<ZLib::GzipReader.wrap>)).

=== メソッド:

--- Zlib::GzipReader#eof
--- Zlib::GzipReader#eof?

    Returns true if the object reaches the end of compressed data.
    Note that eof? does ((*not*)) return true when reaches the
    end of ((*file*)).

--- Zlib::GzipReader#pos
--- Zlib::GzipReader#tell

    Returns the total bytes of data decompressed until now.
    Not that it does ((*not*)) the position of file pointer.

--- Zlib::GzipReader#each([rs])
--- Zlib::GzipReader#each_line([rs])
--- Zlib::GzipReader#each_byte([rs])
--- Zlib::GzipReader#gets([rs])
--- Zlib::GzipReader#getc
--- Zlib::GzipReader#lineno
--- Zlib::GzipReader#lineno=
--- Zlib::GzipReader#read([length])
--- Zlib::GzipReader#readchar
--- Zlib::GzipReader#readline([rs])
--- Zlib::GzipReader#readlines([rs])
--- Zlib::GzipReader#ungetc(char)

    Same as IO, but raises ((<Zlib::Error>)) or
    ((<Zlib::GzipFile::Error>)) exception if an error was found
    in the gzip file.

    Be careful of the footer of gzip file. A gzip file has
    the checksum of pre-compressed data in its footer.
    GzipReader checks all uncompressed data against that checksum
    at the following cases, and if failed, raises
    ((<Zlib::GzipFile::NoFooter>)), ((<Zlib::GzipFile::CRCError>)),
    or ((<Zlib::GzipFile::LengthError>)) exception.

    * When an reading request is received beyond the end of file
      (the end of compressed data).
      That is, when ((<Zlib::GzipReader#read>)),
      ((<Zlib::GzipReader#gets>)), or some other methods for reading
      returns nil.

    * When ((<Zlib::GzipFile#close>)) method is called after
      the object reaches the end of file.

    * When ((<Zlib::GzipReader#unused>)) method is called after
      the object reaches the end of file.

--- Zlib::GzipReader#rewind

    Resets the position of the file pointer to the point
    created the GzipReader object.
    The associated IO object need to respond to seek method.

--- Zlib::GzipReader#unused

    Returns the rest of the data which had read for parsing gzip
    format, or nil if the whole gzip file is not parsed yet.


== Zlib::GzipWriter

The class for writing a gzipped file. GzipWriter should be used
with associate with an instance of IO class (or an object which
has the same methods as IO has).

    Zlib::GzipWriter.open('hoge.gz') {|gz|
      gz.write 'jugemu jugemu gokou no surikire...'
    }

    f = File.open('hoge.gz', 'w')
    gz = Zlib::GzipWriter.new(f)
    gz.write 'jugemu jugemu gokou no surikire...'
    gz.close

NOTE: Due to the limitation in finalizer of Ruby, you must close
explicitly GzipWriter object by ((<Zlib::GzipWriter#close>)) etc.
Otherwise, GzipWriter should be not able to write gzip footer and
generate broken gzip file.

=== SuperClass:

* ((<Zlib::GzipFile>))

=== Class Methods:

--- Zlib::GzipWriter.new(io[, level[, strategy]])

    Creates a GzipWriter object associated with ((|io|)).
    ((|level|)) and ((|strategy|)) should be same as the
    arguments of ((<Zlib::Deflate.new>)). The GzipWriter object
    writes gzipped data to ((|io|)). At least, ((|io|)) must
    respond to write method that behaves same as write method
    in IO class.

--- Zlib::GzipWriter.wrap(io[, level[, strategy]]) {|gz| ... }

    Creates a GzipWriter object associated with ((|io|)), and
    executes the block with the newly created GzipWriter object,
    just like File::open. The GzipWriter object will be closed
    automatically after executing the block. If you want to keep
    the associated IO object opening, you may call
    ((<Zlib::GzipFile#finish>)) method in the block.

--- Zlib::GzipWriter.open(filename[, level[, strategy]])
--- Zlib::GzipWriter.open(filename[, level[, strategy]]) {|gz| ... }

    Opens a file specified by ((|filename|)) for writing
    gzip compressed data, and returns a GzipWriter object
    associated with that file. Further details of this method
    are same as ((<Zlib::GzipWriter.new>)) and
    ((<Zlib::GzipWriter#wrap>)).


=== Methods:

--- Zlib::GzipWriter#close
--- Zlib::GzipWriter#finish

    Closes the GzipFile object. This method calls close method
    of the associated IO object. Returns the associated IO object.
    See ((<Zlib::GzipFile#close>)) and ((<Zlib::GzipFile#finish>))
    for the difference between close and finish.

    ((*NOTE: Due to the limitation in finalizer of Ruby, you must
    close GzipWriter object explicitly. Otherwise, GzipWriter
    should be not able to write gzip footer and generate broken
    gzip file.*))

--- Zlib::GzipWriter#pos
--- Zlib::GzipWriter#tell

    Returns the total bytes of data compressed until now.
    Note that it does ((*not*)) the position of file pointer.

--- Zlib::GzipWriter#<< str
--- Zlib::GzipWriter#putc(ch)
--- Zlib::GzipWriter#puts(obj...)
--- Zlib::GzipWriter#print(arg...)
--- Zlib::GzipWriter#printf(format, arg...)
--- Zlib::GzipWriter#write(str)

    Same as IO.

--- Zlib::GzipWriter#flush([flush])

    Flushes all the internal buffers of the GzipWriter object.
    The meaning of ((|flush|)) is same as one of the argument of
    ((<Zlib::Deflate#deflate>)).
    ((<Zlib::SYNC_FLUSH>)) is used if ((|flush|)) is omitted.
    It is no use giving ((|flush|)) ((<Zlib::NO_FLUSH>)).

--- Zlib::GzipWriter#mtime= time

    Sets last modification time to be stored in the gzip file
    header. ((<Zlib::GzipFile::Error>)) exception will be raised
    if this method is called after writing method (like
    ((<Zlib::GzipWriter#write>))) was called.

--- Zlib::GzipWriter#orig_name= filename

    Sets original filename to be stored in the gzip file header.
    ((<Zlib::GzipFile::Error>)) exception will be raised
    if this method is called after writing method (like
    ((<Zlib::GzipWriter#write>))) was called.

--- Zlib::GzipWriter#comment= string

    Sets comments to be stored in the gzip file header.
    ((<Zlib::GzipFile::Error>)) exception will be raised
    if this method is called after writing method (like
    ((<Zlib::GzipWriter#write>))) was called.


== Changes from 0.5 to 0.6

* New methods:

  * ((<Zlib::GzipFile.wrap>))
  * ((<Zlib::GzipFile#finish>))

* New constants:

  * ((<Zlib::ZLIB_VERSION>))
  * ((<Zlib::OS_VMCMS>))
  * ((<Zlib::OS_ZSYSTEM>))
  * ((<Zlib::OS_CPM>))
  * ((<Zlib::OS_QDOS>))
  * ((<Zlib::OS_RISCOS>))
  * ((<Zlib::OS_UNKNOWN>))

* Changed methods:

  * ((<Zlib::GzipFile.new>)) now takes no block. Use
    ((<Zlib::GzipFile.wrap>)) instead.

  * ((<Zlib::GzipFile#close>)) now takes no argument. Use
    ((<Zlib::GzipFile#finish>)) instead.

* Renamed methods:

  * Zlib.version is renamed to ((<Zlib.zlib_version>)).

* Changed constants:

  * ((<Zlib::VERSION>)) indicates the version of Ruby/zlib.
    The zlib.h version is now in ((<Zlib::ZLIB_VERSION>)).

* Backward compatibility:

  * For backward compatibility for 0.5, the obsoleted methods and
    arguments are still available.

  * Obsoleted classes, methods, and constants for backward
    compatibility for 0.4 or earlier are removed.

== Changes from 0.4 to 0.5

Almost all the code are rewritten.
I hope all changes are enumerated below :-)

* The names of almost classes and some methods are changed.
  All classes and constants are now defined under module
  ((<Zlib>)). The obsoleted names are also available for backward
  compatibility.

  * Classes

    * Deflate -> ((<Zlib::Deflate>))
    * Inflate -> ((<Zlib::Inflate>))
    * Zlib::Gzip -> ((<Zlib::GzipFile>))
    * GzipReader -> ((<Zlib::GzipReader>))
    * GzipWriter -> ((<Zlib::GzipWriter>))
    * Zlib::Gzip::Error -> ((<Zlib::GzipFile::Error>))
    * Zlib::GzipReader::NoFooter -> ((<Zlib::GzipFile::NoFooter>))
    * Zlib::GzipReader::CRCError -> ((<Zlib::GzipFile::CRCError>))
    * Zlib::GzipReader::LengthError -> ((<Zlib::GzipFile::LengthError>))

  * Constants

    * Zlib::ZStream::BINARY -> ((<Zlib::BINARY>))
    * Zlib::ZStream::ASCII -> ((<Zlib::ASCII>))
    * Zlib::ZStream::UNKNOWN -> ((<Zlib::UNKNOWN>))
    * Zlib::Deflate::NO_COMPRESSION -> ((<Zlib::NO_COMPRESSION>))
    * Zlib::Deflate::BEST_SPEED -> ((<Zlib::BEST_SPEED>))
    * Zlib::Deflate::BEST_COMPRESSION -> ((<Zlib::BEST_COMPRESSION>))
    * Zlib::Deflate::DEFAULT_COMPRESSION -> ((<Zlib::DEFAULT_COMPRESSION>))
    * Zlib::Deflate::FILTERED -> ((<Zlib::FILTERED>))
    * Zlib::Deflate::HUFFMAN_ONLY -> ((<Zlib::HUFFMAN_ONLY>))
    * Zlib::Deflate::DEFAULT_STRATEGY -> ((<Zlib::DEFAULT_STRATEGY>))
    * Zlib::Deflate::MAX_WBITS -> ((<Zlib::MAX_WBITS>))
    * Zlib::Deflate::DEF_MEM_LEVEL -> ((<Zlib::DEF_MEM_LEVEL>))
    * Zlib::Deflate::MAX_MEM_LEVEL -> ((<Zlib::MAX_MEM_LEVEL>))
    * Zlib::Deflate::NO_FLUSH -> ((<Zlib::NO_FLUSH>))
    * Zlib::Deflate::SYNC_FLUSH -> ((<Zlib::SYNC_FLUSH>))
    * Zlib::Deflate::FULL_FLUSH -> ((<Zlib::FULL_FLUSH>))
    * Zlib::Inflate::MAX_WBITS -> ((<Zlib::MAX_WBITS>))
    * Zlib::GzipReader::OS_* -> ((<Zlib::OS_*|Zlib::OS_CODE>))

  * Methods

    * Zlib::ZStream#flush_out -> ((<Zlib::ZStream#flush_next_out>))

* Made buffer for input (next_in).

* ((<Zlib::GzipReader#unused>)) returns nil after closing.

* Now you are up to call ((<Zlib::GzipWriter#close>)) explicitly
to avoid segv in finalizer.
((<[ruby-dev:11915]|URL:http://blade.nagaokaut.ac.jp/cgi-bin/scat.rb/ruby/ruby-dev/11915>))

* divided initialize from new.

* remove sanity checks for arguments for deflateInit2 and
  inflateInit2.

* adapted the behavior of ((<Zlib::GzipWriter#puts>)) to Ruby-1.7.

* Made all functions static.


=end
