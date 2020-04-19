# `FileTest` implements file test operations similar to those used in
# `File::Stat` . It exists as a standalone module, and its methods are
# also insinuated into the `File` class. (Note that this is not done by
# inclusion: the interpreter cheats).
module FileTest
  def self.blockdev?: (String | IO file_name) -> bool

  def self.chardev?: (String | IO file_name) -> bool

  def self.directory?: (String | IO file_name) -> bool

  def self.empty?: (String | IO file_name) -> bool

  def self.executable?: (String | IO file_name) -> bool

  def self.executable_real?: (String | IO file_name) -> bool

  def self.exist?: (String | IO file_name) -> bool

  def self.exists?: (String | IO file_name) -> bool

  def self.file?: (String | IO file) -> bool

  def self.grpowned?: (String | IO file_name) -> bool

  def self.identical?: (String | IO file_1, String | IO file_2) -> bool

  def self.owned?: (String | IO file_name) -> bool

  def self.pipe?: (String | IO file_name) -> bool

  def self.readable?: (String | IO file_name) -> bool

  def self.readable_real?: (String | IO file_name) -> bool

  def self.setgid?: (String | IO file_name) -> bool

  def self.setuid?: (String | IO file_name) -> bool

  def self.size: (String | IO file_name) -> Integer

  def self.size?: (String | IO file_name) -> Integer?

  def self.socket?: (String | IO file_name) -> bool

  def self.sticky?: (String | IO file_name) -> bool

  def self.symlink?: (String | IO file_name) -> bool

  def self.world_readable?: (String | IO file_name) -> Integer?

  def self.world_writable?: (String | IO file_name) -> Integer?

  def self.writable?: (String | IO file_name) -> bool

  def self.writable_real?: (String | IO file_name) -> bool

  def self.zero?: (String | IO file_name) -> bool
end
