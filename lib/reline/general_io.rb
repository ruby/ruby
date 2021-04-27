require 'timeout'

class Reline::GeneralIO
  def self.reset
    @@pasting = false
  end

  def self.encoding
    RUBY_PLATFORM =~ /mswin|mingw/ ? Encoding::UTF_8 : Encoding::default_external
  end

  def self.win?
    false
  end

  def self.set_default_key_bindings(_)
  end

  @@buf = []

  def self.input=(val)
    @@input = val
  end

  def self.getc
    unless @@buf.empty?
      return @@buf.shift
    end
    c = nil
    loop do
      result = select([@@input], [], [], 0.1)
      next if result.nil?
      c = @@input.read(1)
      break
    end
    c&.ord
  end

  def self.ungetc(c)
    @@buf.unshift(c)
  end

  def self.get_screen_size
    [1, 1]
  end

  def self.cursor_pos
    Reline::CursorPos.new(1, 1)
  end

  def self.move_cursor_column(val)
  end

  def self.move_cursor_up(val)
  end

  def self.move_cursor_down(val)
  end

  def self.erase_after_cursor
  end

  def self.scroll_down(val)
  end

  def self.clear_screen
  end

  def self.set_screen_size(rows, columns)
  end

  def self.set_winch_handler(&handler)
  end

  @@pasting = false

  def self.in_pasting?
    @@pasting
  end

  def self.start_pasting
    @@pasting = true
  end

  def self.finish_pasting
    @@pasting = false
  end

  def self.prep
  end

  def self.deprep(otio)
  end
end
