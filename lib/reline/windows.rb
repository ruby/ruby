require 'fiddle/import'

class Reline::Windows
  def self.encoding
    Encoding::UTF_8
  end

  def self.win?
    true
  end

  def self.win_legacy_console?
    @@legacy_console
  end

  def self.set_default_key_bindings(config)
    {
      [224, 72] => :ed_prev_history, # ↑
      [224, 80] => :ed_next_history, # ↓
      [224, 77] => :ed_next_char,    # →
      [224, 75] => :ed_prev_char,    # ←
      [224, 83] => :key_delete,      # Del
      [224, 71] => :ed_move_to_beg,  # Home
      [224, 79] => :ed_move_to_end,  # End
      [  0, 41] => :ed_unassigned,   # input method on/off
      [  0, 72] => :ed_prev_history, # ↑
      [  0, 80] => :ed_next_history, # ↓
      [  0, 77] => :ed_next_char,    # →
      [  0, 75] => :ed_prev_char,    # ←
      [  0, 83] => :key_delete,      # Del
      [  0, 71] => :ed_move_to_beg,  # Home
      [  0, 79] => :ed_move_to_end   # End
    }.each_pair do |key, func|
      config.add_default_key_binding_by_keymap(:emacs, key, func)
      config.add_default_key_binding_by_keymap(:vi_insert, key, func)
      config.add_default_key_binding_by_keymap(:vi_command, key, func)
    end

    {
      [27, 32] => :em_set_mark,             # M-<space>
      [24, 24] => :em_exchange_mark,        # C-x C-x
    }.each_pair do |key, func|
      config.add_default_key_binding_by_keymap(:emacs, key, func)
    end

    # Emulate ANSI key sequence.
    {
      [27, 91, 90] => :completion_journey_up, # S-Tab
    }.each_pair do |key, func|
      config.add_default_key_binding_by_keymap(:emacs, key, func)
      config.add_default_key_binding_by_keymap(:vi_insert, key, func)
    end
  end

  if defined? JRUBY_VERSION
    require 'win32api'
  else
    class Win32API
      DLL = {}
      TYPEMAP = {"0" => Fiddle::TYPE_VOID, "S" => Fiddle::TYPE_VOIDP, "I" => Fiddle::TYPE_LONG}
      POINTER_TYPE = Fiddle::SIZEOF_VOIDP == Fiddle::SIZEOF_LONG_LONG ? 'q*' : 'l!*'

      WIN32_TYPES = "VPpNnLlIi"
      DL_TYPES = "0SSI"

      def initialize(dllname, func, import, export = "0", calltype = :stdcall)
        @proto = [import].join.tr(WIN32_TYPES, DL_TYPES).sub(/^(.)0*$/, '\1')
        import = @proto.chars.map {|win_type| TYPEMAP[win_type.tr(WIN32_TYPES, DL_TYPES)]}
        export = TYPEMAP[export.tr(WIN32_TYPES, DL_TYPES)]
        calltype = Fiddle::Importer.const_get(:CALL_TYPE_TO_ABI)[calltype]

        handle = DLL[dllname] ||=
                 begin
                   Fiddle.dlopen(dllname)
                 rescue Fiddle::DLError
                   raise unless File.extname(dllname).empty?
                   Fiddle.dlopen(dllname + ".dll")
                 end

        @func = Fiddle::Function.new(handle[func], import, export, calltype)
      rescue Fiddle::DLError => e
        raise LoadError, e.message, e.backtrace
      end

      def call(*args)
        import = @proto.split("")
        args.each_with_index do |x, i|
          args[i], = [x == 0 ? nil : x].pack("p").unpack(POINTER_TYPE) if import[i] == "S"
          args[i], = [x].pack("I").unpack("i") if import[i] == "I"
        end
        ret, = @func.call(*args)
        return ret || 0
      end
    end
  end

  VK_RETURN = 0x0D
  VK_MENU = 0x12
  VK_LMENU = 0xA4
  VK_CONTROL = 0x11
  VK_SHIFT = 0x10
  VK_DIVIDE = 0x6F

  KEY_EVENT = 0x01
  WINDOW_BUFFER_SIZE_EVENT = 0x04

  CAPSLOCK_ON = 0x0080
  ENHANCED_KEY = 0x0100
  LEFT_ALT_PRESSED = 0x0002
  LEFT_CTRL_PRESSED = 0x0008
  NUMLOCK_ON = 0x0020
  RIGHT_ALT_PRESSED = 0x0001
  RIGHT_CTRL_PRESSED = 0x0004
  SCROLLLOCK_ON = 0x0040
  SHIFT_PRESSED = 0x0010

  VK_TAB = 0x09
  VK_END = 0x23
  VK_HOME = 0x24
  VK_LEFT = 0x25
  VK_UP = 0x26
  VK_RIGHT = 0x27
  VK_DOWN = 0x28
  VK_DELETE = 0x2E

  STD_INPUT_HANDLE = -10
  STD_OUTPUT_HANDLE = -11
  FILE_TYPE_PIPE = 0x0003
  FILE_NAME_INFO = 2
  @@getwch = Win32API.new('msvcrt', '_getwch', [], 'I')
  @@kbhit = Win32API.new('msvcrt', '_kbhit', [], 'I')
  @@GetKeyState = Win32API.new('user32', 'GetKeyState', ['L'], 'L')
  @@GetConsoleScreenBufferInfo = Win32API.new('kernel32', 'GetConsoleScreenBufferInfo', ['L', 'P'], 'L')
  @@SetConsoleCursorPosition = Win32API.new('kernel32', 'SetConsoleCursorPosition', ['L', 'L'], 'L')
  @@GetStdHandle = Win32API.new('kernel32', 'GetStdHandle', ['L'], 'L')
  @@FillConsoleOutputCharacter = Win32API.new('kernel32', 'FillConsoleOutputCharacter', ['L', 'L', 'L', 'L', 'P'], 'L')
  @@ScrollConsoleScreenBuffer = Win32API.new('kernel32', 'ScrollConsoleScreenBuffer', ['L', 'P', 'P', 'L', 'P'], 'L')
  @@hConsoleHandle = @@GetStdHandle.call(STD_OUTPUT_HANDLE)
  @@hConsoleInputHandle = @@GetStdHandle.call(STD_INPUT_HANDLE)
  @@GetNumberOfConsoleInputEvents = Win32API.new('kernel32', 'GetNumberOfConsoleInputEvents', ['L', 'P'], 'L')
  @@ReadConsoleInputW = Win32API.new('kernel32', 'ReadConsoleInputW', ['L', 'P', 'L', 'P'], 'L')
  @@GetFileType = Win32API.new('kernel32', 'GetFileType', ['L'], 'L')
  @@GetFileInformationByHandleEx = Win32API.new('kernel32', 'GetFileInformationByHandleEx', ['L', 'I', 'P', 'L'], 'I')
  @@FillConsoleOutputAttribute = Win32API.new('kernel32', 'FillConsoleOutputAttribute', ['L', 'L', 'L', 'L', 'P'], 'L')
  @@SetConsoleCursorInfo = Win32API.new('kernel32', 'SetConsoleCursorInfo', ['L', 'P'], 'L')

  @@GetConsoleMode = Win32API.new('kernel32', 'GetConsoleMode', ['L', 'P'], 'L')
  @@SetConsoleMode = Win32API.new('kernel32', 'SetConsoleMode', ['L', 'L'], 'L')
  @@WaitForSingleObject = Win32API.new('kernel32', 'WaitForSingleObject', ['L', 'L'], 'L')
  ENABLE_VIRTUAL_TERMINAL_PROCESSING = 4

  private_class_method def self.getconsolemode
    mode = "\000\000\000\000"
    @@GetConsoleMode.call(@@hConsoleHandle, mode)
    mode.unpack1('L')
  end

  private_class_method def self.setconsolemode(mode)
    @@SetConsoleMode.call(@@hConsoleHandle, mode)
  end

  @@legacy_console = (getconsolemode() & ENABLE_VIRTUAL_TERMINAL_PROCESSING == 0)
  #if @@legacy_console
  #  setconsolemode(getconsolemode() | ENABLE_VIRTUAL_TERMINAL_PROCESSING)
  #  @@legacy_console = (getconsolemode() & ENABLE_VIRTUAL_TERMINAL_PROCESSING == 0)
  #end

  @@input_buf = []
  @@output_buf = []

  def self.msys_tty?(io=@@hConsoleInputHandle)
    # check if fd is a pipe
    if @@GetFileType.call(io) != FILE_TYPE_PIPE
      return false
    end

    bufsize = 1024
    p_buffer = "\0" * bufsize
    res = @@GetFileInformationByHandleEx.call(io, FILE_NAME_INFO, p_buffer, bufsize - 2)
    return false if res == 0

    # get pipe name: p_buffer layout is:
    #   struct _FILE_NAME_INFO {
    #     DWORD FileNameLength;
    #     WCHAR FileName[1];
    #   } FILE_NAME_INFO
    len = p_buffer[0, 4].unpack("L")[0]
    name = p_buffer[4, len].encode(Encoding::UTF_8, Encoding::UTF_16LE, invalid: :replace)

    # Check if this could be a MSYS2 pty pipe ('\msys-XXXX-ptyN-XX')
    # or a cygwin pty pipe ('\cygwin-XXXX-ptyN-XX')
    name =~ /(msys-|cygwin-).*-pty/ ? true : false
  end

  KEY_MAP = [
    # It's treated as Meta+Enter on Windows.
    [ { control_keys: :CTRL,  virtual_key_code: 0x0D }, "\e\r".bytes ],
    [ { control_keys: :SHIFT, virtual_key_code: 0x0D }, "\e\r".bytes ],

    # It's treated as Meta+Space on Windows.
    [ { control_keys: :CTRL,  char_code: 0x20 }, "\e ".bytes ],

    # Emulate getwch() key sequences.
    [ { control_keys: [], virtual_key_code: VK_UP },     [0, 72] ],
    [ { control_keys: [], virtual_key_code: VK_DOWN },   [0, 80] ],
    [ { control_keys: [], virtual_key_code: VK_RIGHT },  [0, 77] ],
    [ { control_keys: [], virtual_key_code: VK_LEFT },   [0, 75] ],
    [ { control_keys: [], virtual_key_code: VK_DELETE }, [0, 83] ],
    [ { control_keys: [], virtual_key_code: VK_HOME },   [0, 71] ],
    [ { control_keys: [], virtual_key_code: VK_END },    [0, 79] ],

    # Emulate ANSI key sequence.
    [ { control_keys: :SHIFT, virtual_key_code: VK_TAB }, [27, 91, 90] ],
  ]

  def self.process_key_event(repeat_count, virtual_key_code, virtual_scan_code, char_code, control_key_state)

    key = KeyEventRecord.new(virtual_key_code, char_code, control_key_state)

    match = KEY_MAP.find { |args,| key.matches?(**args) }
    unless match.nil?
      @@output_buf.concat(match.last)
      return
    end

    # no char, only control keys
    return if key.char_code == 0 and key.control_keys.any?

    @@output_buf.concat(key.char.bytes)
  end

  def self.check_input_event
    num_of_events = 0.chr * 8
    while @@output_buf.empty? #or true
      next if @@WaitForSingleObject.(@@hConsoleInputHandle, 100) != 0 # max 0.1 sec
      next if @@GetNumberOfConsoleInputEvents.(@@hConsoleInputHandle, num_of_events) == 0 or num_of_events.unpack('L').first == 0
      input_record = 0.chr * 18
      read_event = 0.chr * 4
      if @@ReadConsoleInputW.(@@hConsoleInputHandle, input_record, 1, read_event) != 0
        event = input_record[0, 2].unpack('s*').first
        case event
        when WINDOW_BUFFER_SIZE_EVENT
          @@winch_handler.()
        when KEY_EVENT
          key_down = input_record[4, 4].unpack('l*').first
          repeat_count = input_record[8, 2].unpack('s*').first
          virtual_key_code = input_record[10, 2].unpack('s*').first
          virtual_scan_code = input_record[12, 2].unpack('s*').first
          char_code = input_record[14, 2].unpack('S*').first
          control_key_state = input_record[16, 2].unpack('S*').first
          is_key_down = key_down.zero? ? false : true
          if is_key_down
            process_key_event(repeat_count, virtual_key_code, virtual_scan_code, char_code, control_key_state)
          end
        end
      end
    end
  end

  def self.getc
    check_input_event
    @@output_buf.shift
  end

  def self.ungetc(c)
    @@output_buf.unshift(c)
  end

  def self.in_pasting?
    not self.empty_buffer?
  end

  def self.empty_buffer?
    if not @@input_buf.empty?
      false
    elsif @@kbhit.call == 0
      true
    else
      false
    end
  end

  def self.get_screen_size
    csbi = 0.chr * 22
    @@GetConsoleScreenBufferInfo.call(@@hConsoleHandle, csbi)
    csbi[0, 4].unpack('SS').reverse
  end

  def self.cursor_pos
    csbi = 0.chr * 22
    @@GetConsoleScreenBufferInfo.call(@@hConsoleHandle, csbi)
    x = csbi[4, 2].unpack('s*').first
    y = csbi[6, 2].unpack('s*').first
    Reline::CursorPos.new(x, y)
  end

  def self.move_cursor_column(val)
    @@SetConsoleCursorPosition.call(@@hConsoleHandle, cursor_pos.y * 65536 + val)
  end

  def self.move_cursor_up(val)
    if val > 0
      y = cursor_pos.y - val
      y = 0 if y < 0
      @@SetConsoleCursorPosition.call(@@hConsoleHandle, y * 65536 + cursor_pos.x)
    elsif val < 0
      move_cursor_down(-val)
    end
  end

  def self.move_cursor_down(val)
    if val > 0
      screen_height = get_screen_size.first
      y = cursor_pos.y + val
      y = screen_height - 1 if y > (screen_height - 1)
      @@SetConsoleCursorPosition.call(@@hConsoleHandle, (cursor_pos.y + val) * 65536 + cursor_pos.x)
    elsif val < 0
      move_cursor_up(-val)
    end
  end

  def self.erase_after_cursor
    csbi = 0.chr * 24
    @@GetConsoleScreenBufferInfo.call(@@hConsoleHandle, csbi)
    cursor = csbi[4, 4].unpack('L').first
    written = 0.chr * 4
    @@FillConsoleOutputCharacter.call(@@hConsoleHandle, 0x20, get_screen_size.last - cursor_pos.x, cursor, written)
    @@FillConsoleOutputAttribute.call(@@hConsoleHandle, 0, get_screen_size.last - cursor_pos.x, cursor, written)
  end

  def self.scroll_down(val)
    return if val.zero?
    screen_height = get_screen_size.first
    val = screen_height - 1 if val > (screen_height - 1)
    scroll_rectangle = [0, val, get_screen_size.last, get_screen_size.first].pack('s4')
    destination_origin = 0 # y * 65536 + x
    fill = [' '.ord, 0].pack('SS')
    @@ScrollConsoleScreenBuffer.call(@@hConsoleHandle, scroll_rectangle, nil, destination_origin, fill)
  end

  def self.clear_screen
    csbi = 0.chr * 22
    return if @@GetConsoleScreenBufferInfo.call(@@hConsoleHandle, csbi) == 0
    buffer_width = csbi[0, 2].unpack('S').first
    attributes = csbi[8, 2].unpack('S').first
    _window_left, window_top, _window_right, window_bottom = *csbi[10,8].unpack('S*')
    fill_length = buffer_width * (window_bottom - window_top + 1)
    screen_topleft = window_top * 65536
    written = 0.chr * 4
    @@FillConsoleOutputCharacter.call(@@hConsoleHandle, 0x20, fill_length, screen_topleft, written)
    @@FillConsoleOutputAttribute.call(@@hConsoleHandle, attributes, fill_length, screen_topleft, written)
    @@SetConsoleCursorPosition.call(@@hConsoleHandle, screen_topleft)
  end

  def self.set_screen_size(rows, columns)
    raise NotImplementedError
  end

  def self.hide_cursor
    size = 100
    visible = 0 # 0 means false
    cursor_info = [size, visible].pack('Li')
    @@SetConsoleCursorInfo.call(@@hConsoleHandle, cursor_info)
  end

  def self.show_cursor
    size = 100
    visible = 1 # 1 means true
    cursor_info = [size, visible].pack('Li')
    @@SetConsoleCursorInfo.call(@@hConsoleHandle, cursor_info)
  end

  def self.set_winch_handler(&handler)
    @@winch_handler = handler
  end

  def self.prep
    # do nothing
    nil
  end

  def self.deprep(otio)
    # do nothing
  end

  class KeyEventRecord

    attr_reader :virtual_key_code, :char_code, :control_key_state, :control_keys

    def initialize(virtual_key_code, char_code, control_key_state)
      @virtual_key_code = virtual_key_code
      @char_code = char_code
      @control_key_state = control_key_state
      @enhanced = control_key_state & ENHANCED_KEY != 0

      (@control_keys = []).tap do |control_keys|
        # symbols must be sorted to make comparison is easier later on
        control_keys << :ALT   if control_key_state & (LEFT_ALT_PRESSED | RIGHT_ALT_PRESSED) != 0
        control_keys << :CTRL  if control_key_state & (LEFT_CTRL_PRESSED | RIGHT_CTRL_PRESSED) != 0
        control_keys << :SHIFT if control_key_state & SHIFT_PRESSED != 0
      end.freeze
    end

    def char
      @char_code.chr(Encoding::UTF_8)
    end

    def enhanced?
      @enhanced
    end

    # Verifies if the arguments match with this key event.
    # Nil arguments are ignored, but at least one must be passed as non-nil.
    # To verify that no control keys were pressed, pass an empty array: `control_keys: []`.
    def matches?(control_keys: nil, virtual_key_code: nil, char_code: nil)
      raise ArgumentError, 'No argument was passed to match key event' if control_keys.nil? && virtual_key_code.nil? && char_code.nil?

      (control_keys.nil? || [*control_keys].sort == @control_keys) &&
      (virtual_key_code.nil? || @virtual_key_code == virtual_key_code) &&
      (char_code.nil? || char_code == @char_code)
    end

  end
end
