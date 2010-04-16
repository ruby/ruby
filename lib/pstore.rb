# = PStore -- Transactional File Storage for Ruby Objects
#
# pstore.rb -
#   originally by matz
#   documentation by Kev Jackson and James Edward Gray II
#
# See PStore for documentation.


require "fileutils"
require "digest/md5"

#
# PStore implements a file based persistence mechanism based on a Hash.  User
# code can store hierarchies of Ruby objects (values) into the data store file
# by name (keys).  An object hierarchy may be just a single object.  User code
# may later read values back from the data store or even update data, as needed.
#
# The transactional behavior ensures that any changes succeed or fail together.
# This can be used to ensure that the data store is not left in a transitory
# state, where some values were updated but others were not.
#
# Behind the scenes, Ruby objects are stored to the data store file with
# Marshal.  That carries the usual limitations.  Proc objects cannot be
# marshalled, for example.
#
# == Usage example:
#
#  require "pstore"
#
#  # a mock wiki object...
#  class WikiPage
#    def initialize( page_name, author, contents )
#      @page_name = page_name
#      @revisions = Array.new
#
#      add_revision(author, contents)
#    end
#
#    attr_reader :page_name
#
#    def add_revision( author, contents )
#      @revisions << { :created  => Time.now,
#                      :author   => author,
#                      :contents => contents }
#    end
#
#    def wiki_page_references
#      [@page_name] + @revisions.last[:contents].scan(/\b(?:[A-Z]+[a-z]+){2,}/)
#    end
#
#    # ...
#  end
#
#  # create a new page...
#  home_page = WikiPage.new( "HomePage", "James Edward Gray II",
#                            "A page about the JoysOfDocumentation..." )
#
#  # then we want to update page data and the index together, or not at all...
#  wiki = PStore.new("wiki_pages.pstore")
#  wiki.transaction do  # begin transaction; do all of this or none of it
#    # store page...
#    wiki[home_page.page_name] = home_page
#    # ensure that an index has been created...
#    wiki[:wiki_index] ||= Array.new
#    # update wiki index...
#    wiki[:wiki_index].push(*home_page.wiki_page_references)
#  end                   # commit changes to wiki data store file
#
#  ### Some time later... ###
#
#  # read wiki data...
#  wiki.transaction(true) do  # begin read-only transaction, no changes allowed
#    wiki.roots.each do |data_root_name|
#      p data_root_name
#      p wiki[data_root_name]
#    end
#  end
#
class PStore
  binmode = defined?(File::BINARY) ? File::BINARY : 0
  RDWR_ACCESS = File::RDWR | File::CREAT | binmode
  RD_ACCESS = File::RDONLY | binmode
  WR_ACCESS = File::WRONLY | File::CREAT | File::TRUNC | binmode

  # The error type thrown by all PStore methods.
  class Error < StandardError
  end

  #
  # To construct a PStore object, pass in the _file_ path where you would like
  # the data to be stored.
  #
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

  # Raises PStore::Error if the calling code is not in a PStore#transaction.
  def in_transaction
    raise PStore::Error, "not in transaction" unless @transaction
  end
  #
  # Raises PStore::Error if the calling code is not in a PStore#transaction or
  # if the code is in a read-only PStore#transaction.
  #
  def in_transaction_wr()
    in_transaction()
    raise PStore::Error, "in read-only transaction" if @rdonly
  end
  private :in_transaction, :in_transaction_wr

  #
  # Retrieves a value from the PStore file data, by _name_.  The hierarchy of
  # Ruby objects stored under that root _name_ will be returned.
  #
  # *WARNING*:  This method is only valid in a PStore#transaction.  It will
  # raise PStore::Error if called at any other time.
  #
  def [](name)
    in_transaction
    @table[name]
  end
  #
  # This method is just like PStore#[], save that you may also provide a
  # _default_ value for the object.  In the event the specified _name_ is not
  # found in the data store, your _default_ will be returned instead.  If you do
  # not specify a default, PStore::Error will be raised if the object is not
  # found.
  #
  # *WARNING*:  This method is only valid in a PStore#transaction.  It will
  # raise PStore::Error if called at any other time.
  #
  def fetch(name, default=PStore::Error)
    in_transaction
    unless @table.key? name
      if default==PStore::Error
	raise PStore::Error, format("undefined root name `%s'", name)
      else
	return default
      end
    end
    @table[name]
  end
  #
  # Stores an individual Ruby object or a hierarchy of Ruby objects in the data
  # store file under the root _name_.  Assigning to a _name_ already in the data
  # store clobbers the old data.
  #
  # == Example:
  #
  #  require "pstore"
  #
  #  store = PStore.new("data_file.pstore")
  #  store.transaction do  # begin transaction
  #    # load some data into the store...
  #    store[:single_object] = "My data..."
  #    store[:obj_heirarchy] = { "Kev Jackson" => ["rational.rb", "pstore.rb"],
  #                              "James Gray"  => ["erb.rb", "pstore.rb"] }
  #  end                   # commit changes to data store file
  #
  # *WARNING*:  This method is only valid in a PStore#transaction and it cannot
  # be read-only.  It will raise PStore::Error if called at any other time.
  #
  def []=(name, value)
    in_transaction_wr()
    @table[name] = value
  end
  #
  # Removes an object hierarchy from the data store, by _name_.
  #
  # *WARNING*:  This method is only valid in a PStore#transaction and it cannot
  # be read-only.  It will raise PStore::Error if called at any other time.
  #
  def delete(name)
    in_transaction_wr()
    @table.delete name
  end

  #
  # Returns the names of all object hierarchies currently in the store.
  #
  # *WARNING*:  This method is only valid in a PStore#transaction.  It will
  # raise PStore::Error if called at any other time.
  #
  def roots
    in_transaction
    @table.keys
  end
  #
  # Returns true if the supplied _name_ is currently in the data store.
  #
  # *WARNING*:  This method is only valid in a PStore#transaction.  It will
  # raise PStore::Error if called at any other time.
  #
  def root?(name)
    in_transaction
    @table.key? name
  end
  # Returns the path to the data store file.
  def path
    @filename
  end

  #
  # Ends the current PStore#transaction, committing any changes to the data
  # store immediately.
  #
  # == Example:
  #
  #  require "pstore"
  #
  #  store = PStore.new("data_file.pstore")
  #  store.transaction do  # begin transaction
  #    # load some data into the store...
  #    store[:one] = 1
  #    store[:two] = 2
  #
  #    store.commit        # end transaction here, committing changes
  #
  #    store[:three] = 3   # this change is never reached
  #  end
  #
  # *WARNING*:  This method is only valid in a PStore#transaction.  It will
  # raise PStore::Error if called at any other time.
  #
  def commit
    in_transaction
    @abort = false
    throw :pstore_abort_transaction
  end
  #
  # Ends the current PStore#transaction, discarding any changes to the data
  # store.
  #
  # == Example:
  #
  #  require "pstore"
  #
  #  store = PStore.new("data_file.pstore")
  #  store.transaction do  # begin transaction
  #    store[:one] = 1     # this change is not applied, see below...
  #    store[:two] = 2     # this change is not applied, see below...
  #
  #    store.abort         # end transaction here, discard all changes
  #
  #    store[:three] = 3   # this change is never reached
  #  end
  #
  # *WARNING*:  This method is only valid in a PStore#transaction.  It will
  # raise PStore::Error if called at any other time.
  #
  def abort
    in_transaction
    @abort = true
    throw :pstore_abort_transaction
  end

  #
  # Opens a new transaction for the data store.  Code executed inside a block
  # passed to this method may read and write data to and from the data store
  # file.
  #
  # At the end of the block, changes are committed to the data store
  # automatically.  You may exit the transaction early with a call to either
  # PStore#commit or PStore#abort.  See those methods for details about how
  # changes are handled.  Raising an uncaught Exception in the block is
  # equivalent to calling PStore#abort.
  #
  # If _read_only_ is set to +true+, you will only be allowed to read from the
  # data store during the transaction and any attempts to change the data will
  # raise a PStore::Error.
  #
  # Note that PStore does not support nested transactions.
  #
  def transaction(read_only=false)  # :yields:  pstore
    raise PStore::Error, "nested transaction" if @transaction
    begin
      @rdonly = read_only
      @abort = false
      @transaction = true
      value = nil
      new_file = @filename + ".new"

      content = nil
      unless read_only
        file = File.open(@filename, RDWR_ACCESS)
        file.flock(File::LOCK_EX)
        commit_new(file) if FileTest.exist?(new_file)
        content = file.read()
      else
        begin
          file = File.open(@filename, RD_ACCESS)
          file.flock(File::LOCK_SH)
          content = (File.open(new_file, RD_ACCESS) {|n| n.read} rescue file.read())
        rescue Errno::ENOENT
          content = ""
        end
      end

      if content != ""
	@table = load(content)
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
	  content = dump(@table)
	  if !md5 || size != content.size || md5 != Digest::MD5.digest(content)
            File.open(tmp_file, WR_ACCESS) {|t| t.write(content)}
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

  # This method is just a wrapped around Marshal.dump.
  def dump(table)  # :nodoc:
    Marshal::dump(table)
  end

  # This method is just a wrapped around Marshal.load.
  def load(content)  # :nodoc:
    Marshal::load(content)
  end

  # This method is just a wrapped around Marshal.load.
  def load_file(file)  # :nodoc:
    Marshal::load(file)
  end

  private
  # Commits changes to the data store file.
  def commit_new(f)
    f.truncate(0)
    f.rewind
    new_file = @filename + ".new"
    File.open(new_file, RD_ACCESS) do |nf|
      FileUtils.copy_stream(nf, f)
    end
    File.unlink(new_file)
  end
end

# :enddoc:

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
