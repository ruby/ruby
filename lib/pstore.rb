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

require "ftools"
require "digest/md5"

class PStore
  class Error < StandardError
  end

  def initialize(file)
    dir = File::dirname(file)
    unless File::directory? dir
      raise PStore::Error, format("directory %s does not exist", dir)
    end
    unless File::writable? dir
      raise PStore::Error, format("directory %s not writable", dir)
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
  private :in_transaction

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
    in_transaction
    @table[name] = value
  end
  def delete(name)
    in_transaction
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
      @transaction = true
      value = nil
      backup = @filename+"~"
      begin
	file = File::open(@filename, "rb+")
	orig = true
      rescue Errno::ENOENT
	raise if read_only
	file = File::open(@filename, "wb+")
      end
      file.flock(read_only ? File::LOCK_SH : File::LOCK_EX)
      if read_only
	@table = Marshal::load(file)
      elsif orig and (content = file.read) != nil
	@table = Marshal::load(content)
	size = content.size
	md5 = Digest::MD5.digest(content)
	content = nil		# unreference huge data
      else
	@table = {}
      end
      begin
	catch(:pstore_abort_transaction) do
	  value = yield(self)
	end
      rescue Exception
	@abort = true
	raise
      ensure
	if !read_only && !@abort
	  file.rewind
	  content = Marshal::dump(@table)
	  if !md5 || size != content.size || md5 != Digest::MD5.digest(content)
	    File::copy @filename, backup
	    begin
	      file.write(content)
	      file.truncate(file.pos)
	      content = nil		# unreference huge data
	    rescue
	      File::rename backup, @filename if File::exist?(backup)
	      raise
	    end
	  end
	end
	@abort = false
      end
    ensure
      @table = nil
      @transaction = false
      file.close if file
    end
    value
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
