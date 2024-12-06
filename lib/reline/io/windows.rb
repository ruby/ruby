require 'fiddle/import'

class Reline::Windows < Reline::IO

  attr_writer :output

  def initialize
    @input_buf = []
    @output_buf = []

    @output = STDOUT
    @hsg = nil
    @getwch = Win32API.new('msvcrt', '_getwch', [], 'I')
    @kbhit = Win32API.new('msvcrt', '_kbhit', [], 'I')
    @GetKeyState = Win32API.new('user32', 'GetKeyState', ['L'], 'L')
    @GetConsoleScreenBufferInfo = Win32API.new('kernel32', 'GetConsoleScreenBufferInfo', ['L', 'P'], 'L')
    @SetConsoleCursorPosition = Win32API.new('kernel32', 'SetConsoleCursorPosition', ['L', 'L'], 'L')
    @GetStdHandle = Win32API.new('kernel32', 'GetStdHandle', ['L'], 'L')
    @FillConsoleOutputCharacter = Win32API.new('kernel32', 'FillConsoleOutputCharacter', ['L', 'L', 'L', 'L', 'P'], 'L')
    @ScrollConsoleScreenBuffer = Win32API.new('kernel32', 'ScrollConsoleScreenBuffer', ['L', 'P', 'P', 'L', 'P'], 'L')
    @hConsoleHandle = @GetStdHandle.call(STD_OUTPUT_HANDLE)
    @hConsoleInputHandle = @GetStdHandle.call(STD_INPUT_HANDLE)
    @GetNumberOfConsoleInputEvents = Win32API.new('kernel32', 'GetNumberOfConsoleInputEvents', ['L', 'P'], 'L')
    @ReadConsoleInputW = Win32API.new('kernel32', 'ReadConsoleInputW', ['L', 'P', 'L', 'P'], 'L')
    @GetFileType = Win32API.new('kernel32', 'GetFileType', ['L'], 'L')
    @GetFileInformationByHandleEx = Win32API.new('kernel32', 'GetFileInformationByHandleEx', ['L', 'I', 'P', 'L'], 'I')
    @FillConsoleOutputAttribute = Win32API.new('kernel32', 'FillConsoleOutputAttribute', ['L', 'L', 'L', 'L', 'P'], 'L')
    @SetConsoleCursorInfo = Win32API.new('kernel32', 'SetConsoleCursorInfo', ['L', 'P'], 'L')

    @GetConsoleMode = Win32API.new('kernel32', 'GetConsoleMode', ['L', 'P'], 'L')
    @SetConsoleMode = Win32API.new('kernel32', 'SetConsoleMode', ['L', 'L'], 'L')
    @WaitForSingleObject = Win32API.new('kernel32', 'WaitForSingleObject', ['L', 'L'], 'L')

    @legacy_console = getconsolemode & ENABLE_VIRTUAL_TERMINAL_PROCESSING == 0
  end

  def encoding
    Encoding::UTF_8
  end

  def win?
    true
  end

  def win_legacy_console?
    @legacy_console
  end

  def set_default_key_bindings(config)
    {
      [224, 72] => :ed_prev_history, # ↑
      [224, 80] => :ed_next_history, # ↓
      [224, 77] => :ed_next_char,    # →
      [224, 75] => :ed_prev_char,    # ←
      [224, 83] => :key_delete,      # Del
      [224, 71] => :ed_move_to_beg,  # Home
      [224, 79] => :ed_move_to_end,  # End
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
          args[i], = [x == 0 ? nil : +x].pack("p").unpack(POINTER_TYPE) if import[i] == "S"
          args[i], = [x].pack("I").unpack("i") if import[i] == "I"
        end
        ret, = @func.call(*args)
        return ret || 0
      end
    end
  end

  VK_RETURN = 0x0D
  VK_MENU = 0x12 # ALT key
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
  ENABLE_WRAP_AT_EOL_OUTPUT = 2
  ENABLE_VIRTUAL_TERMINAL_PROCESSING = 4

  # Calling Win32API with console handle is reported to fail after executing some external command.
  # We need to refresh console handle and retry the call again.
  private def call_with_console_handle(win32func, *args)
    val = win32func.call(@hConsoleHandle, *args)
    return val if val != 0

    @hConsoleHandle = @GetStdHandle.call(STD_OUTPUT_HANDLE)
    win32func.call(@hConsoleHandle, *args)
  end

  private def getconsolemode
    mode = +"\0\0\0\0"
    call_with_console_handle(@GetConsoleMode, mode)
    mode.unpack1('L')
  end

  private def setconsolemode(mode)
    call_with_console_handle(@SetConsoleMode, mode)
  end

  #if @legacy_console
  #  setconsolemode(getconsolemode() | ENABLE_VIRTUAL_TERMINAL_PROCESSING)
  #  @legacy_console = (getconsolemode() & ENABLE_VIRTUAL_TERMINAL_PROCESSING == 0)
  #end

  def msys_tty?(io = @hConsoleInputHandle)
    # check if fd is a pipe
    if @GetFileType.call(io) != FILE_TYPE_PIPE
      return false
    end

    bufsize = 1024
    p_buffer = "\0" * bufsize
    res = @GetFileInformationByHandleEx.call(io, FILE_NAME_INFO, p_buffer, bufsize - 2)
    return false if res == 0

    # get pipe name: p_buffer layout is:
    #   struct _FILE_NAME_INFO {
    #     DWORD FileNameLength;
    #     WCHAR FileName[1];
    #   } FILE_NAME_INFO
    len = p_buffer[0, 4].unpack1("L")
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

  def process_key_event(repeat_count, virtual_key_code, virtual_scan_code, char_code, control_key_state)

    # high-surrogate
    if 0xD800 <= char_code and char_code <= 0xDBFF
      @hsg = char_code
      return
    end
    # low-surrogate
    if 0xDC00 <= char_code and char_code <= 0xDFFF
      if @hsg
        char_code = 0x10000 + (@hsg - 0xD800) * 0x400 + char_code - 0xDC00
        @hsg = nil
      else
        # no high-surrogate. ignored.
        return
      end
    else
      # ignore high-surrogate without low-surrogate if there
      @hsg = nil
    end

    key = KeyEventRecord.new(virtual_key_code, char_code, control_key_state)

    match = KEY_MAP.find { |args,| key.match?(**args) }
    unless match.nil?
      @output_buf.concat(match.last)
      return
    end

    # no char, only control keys
    return if key.char_code == 0 and key.control_keys.any?

    @output_buf.push("\e".ord) if key.control_keys.include?(:ALT) and !key.control_keys.include?(:CTRL)

    @output_buf.concat(key.char.bytes)
  end

  def check_input_event
    num_of_events = 0.chr * 8
    while @output_buf.empty?
      Reline.core.line_editor.handle_signal
      if @WaitForSingleObject.(@hConsoleInputHandle, 100) != 0 # max 0.1 sec
        # prevent for background consolemode change
        @legacy_console = getconsolemode & ENABLE_VIRTUAL_TERMINAL_PROCESSING == 0
        next
      end
      next if @GetNumberOfConsoleInputEvents.(@hConsoleInputHandle, num_of_events) == 0 or num_of_events.unpack1('L') == 0
      input_records = 0.chr * 20 * 80
      read_event = 0.chr * 4
      if @ReadConsoleInputW.(@hConsoleInputHandle, input_records, 80, read_event) != 0
        read_events = read_event.unpack1('L')
        0.upto(read_events) do |idx|
          input_record = input_records[idx * 20, 20]
          event = input_record[0, 2].unpack1('s*')
          case event
          when WINDOW_BUFFER_SIZE_EVENT
            @winch_handler.()
          when KEY_EVENT
            key_down = input_record[4, 4].unpack1('l*')
            repeat_count = input_record[8, 2].unpack1('s*')
            virtual_key_code = input_record[10, 2].unpack1('s*')
            virtual_scan_code = input_record[12, 2].unpack1('s*')
            char_code = input_record[14, 2].unpack1('S*')
            control_key_state = input_record[16, 2].unpack1('S*')
            is_key_down = key_down.zero? ? false : true
            if is_key_down
              process_key_event(repeat_count, virtual_key_code, virtual_scan_code, char_code, control_key_state)
            end
          end
        end
      end
    end
  end

  def with_raw_input
    yield
  end

  def write(string)
    @output.write(string)
  end

  def buffered_output
    yield
  end

  def getc(_timeout_second)
    check_input_event
    @output_buf.shift
  end

  def ungetc(c)
    @output_buf.unshift(c)
  end

  def in_pasting?
    not empty_buffer?
  end

  def empty_buffer?
    if not @output_buf.empty?
      false
    elsif @kbhit.call == 0
      true
    else
      false
    end
  end

  def get_console_screen_buffer_info
    # CONSOLE_SCREEN_BUFFER_INFO
    # [ 0,2] dwSize.X
    # [ 2,2] dwSize.Y
    # [ 4,2] dwCursorPositions.X
    # [ 6,2] dwCursorPositions.Y
    # [ 8,2] wAttributes
    # [10,2] srWindow.Left
    # [12,2] srWindow.Top
    # [14,2] srWindow.Right
    # [16,2] srWindow.Bottom
    # [18,2] dwMaximumWindowSize.X
    # [20,2] dwMaximumWindowSize.Y
    csbi = 0.chr * 22
    if call_with_console_handle(@GetConsoleScreenBufferInfo, csbi) != 0
      # returns [width, height, x, y, attributes, left, top, right, bottom]
      csbi.unpack("s9")
    else
      return nil
    end
  end

  ALTERNATIVE_CSBI = [80, 24, 0, 0, 7, 0, 0, 79, 23].freeze

  def get_screen_size
    width, _, _, _, _, _, top, _, bottom = get_console_screen_buffer_info || ALTERNATIVE_CSBI
    [bottom - top + 1, width]
  end

  def cursor_pos
    _, _, x, y, _, _, top, = get_console_screen_buffer_info || ALTERNATIVE_CSBI
    Reline::CursorPos.new(x, y - top)
  end

  def move_cursor_column(val)
    _, _, _, y, = get_console_screen_buffer_info
    call_with_console_handle(@SetConsoleCursorPosition, y * 65536 + val) if y
  end

  def move_cursor_up(val)
    if val > 0
      _, _, x, y, _, _, top, = get_console_screen_buffer_info
      return unless y
      y = (y - top) - val
      y = 0 if y < 0
      call_with_console_handle(@SetConsoleCursorPosition, (y + top) * 65536 + x)
    elsif val < 0
      move_cursor_down(-val)
    end
  end

  def move_cursor_down(val)
    if val > 0
      _, _, x, y, _, _, top, _, bottom = get_console_screen_buffer_info
      return unless y
      screen_height = bottom - top
      y = (y - top) + val
      y = screen_height if y > screen_height
      call_with_console_handle(@SetConsoleCursorPosition, (y + top) * 65536 + x)
    elsif val < 0
      move_cursor_up(-val)
    end
  end

  def erase_after_cursor
    width, _, x, y, attributes, = get_console_screen_buffer_info
    return unless x
    written = 0.chr * 4
    call_with_console_handle(@FillConsoleOutputCharacter, 0x20, width - x, y * 65536 + x, written)
    call_with_console_handle(@FillConsoleOutputAttribute, attributes, width - x, y * 65536 + x, written)
  end

  # This only works when the cursor is at the bottom of the scroll range
  # For more details, see https://github.com/ruby/reline/pull/577#issuecomment-1646679623
  def scroll_down(x)
    return if x.zero?
    # We use `\n` instead of CSI + S because CSI + S would cause https://github.com/ruby/reline/issues/576
    @output.write "\n" * x
  end

  def clear_screen
    if @legacy_console
      width, _, _, _, attributes, _, top, _, bottom = get_console_screen_buffer_info
      return unless width
      fill_length = width * (bottom - top + 1)
      screen_topleft = top * 65536
      written = 0.chr * 4
      call_with_console_handle(@FillConsoleOutputCharacter, 0x20, fill_length, screen_topleft, written)
      call_with_console_handle(@FillConsoleOutputAttribute, attributes, fill_length, screen_topleft, written)
      call_with_console_handle(@SetConsoleCursorPosition, screen_topleft)
    else
      @output.write "\e[2J" "\e[H"
    end
  end

  def set_screen_size(rows, columns)
    raise NotImplementedError
  end

  def hide_cursor
    size = 100
    visible = 0 # 0 means false
    cursor_info = [size, visible].pack('Li')
    call_with_console_handle(@SetConsoleCursorInfo, cursor_info)
  end

  def show_cursor
    size = 100
    visible = 1 # 1 means true
    cursor_info = [size, visible].pack('Li')
    call_with_console_handle(@SetConsoleCursorInfo, cursor_info)
  end

  def set_winch_handler(&handler)
    @winch_handler = handler
  end

  def prep
    # do nothing
    nil
  end

  def deprep(otio)
    # do nothing
  end

  def disable_auto_linewrap(setting = true, &block)
    mode = getconsolemode
    if 0 == (mode & ENABLE_VIRTUAL_TERMINAL_PROCESSING)
      if block
        begin
          setconsolemode(mode & ~ENABLE_WRAP_AT_EOL_OUTPUT)
          block.call
        ensure
          setconsolemode(mode | ENABLE_WRAP_AT_EOL_OUTPUT)
        end
      else
        if setting
          setconsolemode(mode & ~ENABLE_WRAP_AT_EOL_OUTPUT)
        else
          setconsolemode(mode | ENABLE_WRAP_AT_EOL_OUTPUT)
        end
      end
    else
      block.call if block
    end
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
    def match?(control_keys: nil, virtual_key_code: nil, char_code: nil)
      raise ArgumentError, 'No argument was passed to match key event' if control_keys.nil? && virtual_key_code.nil? && char_code.nil?

      (control_keys.nil? || [*control_keys].sort == @control_keys) &&
      (virtual_key_code.nil? || @virtual_key_code == virtual_key_code) &&
      (char_code.nil? || char_code == @char_code)
    end

  end
end
