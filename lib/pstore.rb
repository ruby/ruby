#
# How to use:
#
# db = PStore.new("/tmp/foo")
# db.transaction do
#   p db.roots
#   ary = db["root"] = [1,2,3,4]
#   ary[0] = [1,1.5]
# end

# db.transaction do
#   p db["root"]
# end

require "fileutils"
require "digest/md5"

class PStore
  class Error < StandardError
  end

  def initialize(file)
    dir = File::dirname(file)
    unless File::directory? dir
      raise PStore::Error, format("directory %s does not exist", dir)
    end
    if File::exist? file and not File::readable? file
      raise PStore::Error, format("file %s not readable", file)
    end
    @transaction = false
    @filename = file
    @abort = false
  end

  def in_transaction
    raise PStore::Error, "not in transaction" unless @transaction
  end
  def in_transaction_wr()
    in_transaction()
    raise PStore::Error, "in read-only transaction" if @rdonly
  end
  private :in_transaction, :in_transaction_wr

  def [](name)
    in_transaction
    @table[name]
  end
  def fetch(name, default=PStore::Error)
    unless @table.key? name
      if default==PStore::Error
	raise PStore::Error, format("undefined root name `%s'", name)
      else
	default
      end
    end
    self[name]
  end
  def []=(name, value)
    in_transaction_wr()
    @table[name] = value
  end
  def delete(name)
    in_transaction_wr()
    @table.delete name
  end

  def roots
    in_transaction
    @table.keys
  end
  def root?(name)
    in_transaction
    @table.key? name
  end
  def path
    @filename
  end

  def commit
    in_transaction
    @abort = false
    throw :pstore_abort_transaction
  end
  def abort
    in_transaction
    @abort = true
    throw :pstore_abort_transaction
  end

  def transaction(read_only=false)
    raise PStore::Error, "nested transaction" if @transaction
    begin
      @rdonly = read_only
      @abort = false
      @transaction = true
      value = nil
      new_file = @filename + ".new"

      content = nil
      file = File.open(@filename, File::RDWR | File::CREAT)
      if !read_only
        file.flock(File::LOCK_EX)
        commit_new(file) if FileTest.exist?(new_file)
        content = file.read()
      else
        file.flock(File::LOCK_SH)
        if FileTest.exist?(new_file)
          File.open(new_file) {|fp| content = fp.read()}
        else
          content = file.read()
        end
      end

      if content != ""
	@table = Marshal::load(content)
        if !read_only
          size = content.size
          md5 = Digest::MD5.digest(content)
        end
      else
	@table = {}
      end
      content = nil		# unreference huge data

      begin
	catch(:pstore_abort_transaction) do
	  value = yield(self)
	end
      rescue Exception
	@abort = true
	raise
      ensure
	if !read_only and !@abort
          tmp_file = @filename + ".tmp"
	  content = Marshal::dump(@table)
	  if !md5 || size != content.size || md5 != Digest::MD5.digest(content)
            File.open(tmp_file, "w") {|t|
              t.write(content)
            }
            File.rename(tmp_file, new_file)
            commit_new(file)
          end
          content = nil		# unreference huge data
	end
      end
    ensure
      @table = nil
      @transaction = false
      file.close if file
    end
    value
  end

  private
  def commit_new(f)
    f.truncate(0)
    f.rewind
    new_file = @filename + ".new"
    File.open(new_file) do |nf|
      FileUtils.copy_stream(nf, f)
    end
    File.unlink(new_file)
  end
end

if __FILE__ == $0
  db = PStore.new("/tmp/foo")
  db.transaction do
    p db.roots
    ary = db["root"] = [1,2,3,4]
    ary[1] = [1,1.5]
  end

  1000.times do
    db.transaction do
      db["root"][0] += 1
      p db["root"][0]
    end
  end

  db.transaction(true) do
    p db["root"]
  end
end
