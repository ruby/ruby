# -*- encoding: binary -*-
require_relative '../fixtures/marshal_data'

describe :marshal_load, shared: true do
  before :all do
    @num_self_class = 1
  end

  it "raises an ArgumentError when the dumped data is truncated" do
    obj = {first: 1, second: 2, third: 3}
    -> { Marshal.send(@method, Marshal.dump(obj)[0, 5]) }.should raise_error(ArgumentError, "marshal data too short")
  end

  it "raises an ArgumentError when the argument is empty String" do
    -> { Marshal.send(@method, "") }.should raise_error(ArgumentError, "marshal data too short")
  end

  it "raises an ArgumentError when the dumped class is missing" do
    Object.send(:const_set, :KaBoom, Class.new)
    kaboom = Marshal.dump(KaBoom.new)
    Object.send(:remove_const, :KaBoom)

    -> { Marshal.send(@method, kaboom) }.should raise_error(ArgumentError)
  end

  describe "when called with freeze: true" do
    it "returns frozen strings" do
      string = Marshal.send(@method, Marshal.dump("foo"), freeze: true)
      string.should == "foo"
      string.should.frozen?

      utf8_string = "foo".encode(Encoding::UTF_8)
      string = Marshal.send(@method, Marshal.dump(utf8_string), freeze: true)
      string.should == utf8_string
      string.should.frozen?
    end

    it "returns frozen arrays" do
      array = Marshal.send(@method, Marshal.dump([1, 2, 3]), freeze: true)
      array.should == [1, 2, 3]
      array.should.frozen?
    end

    it "returns frozen hashes" do
      hash = Marshal.send(@method, Marshal.dump({foo: 42}), freeze: true)
      hash.should == {foo: 42}
      hash.should.frozen?
    end

    it "returns frozen regexps" do
      regexp = Marshal.send(@method, Marshal.dump(/foo/), freeze: true)
      regexp.should == /foo/
      regexp.should.frozen?
    end

    it "returns frozen structs" do
      struct = Marshal.send(@method, Marshal.dump(MarshalSpec::StructToDump.new(1, 2)), freeze: true)
      struct.should == MarshalSpec::StructToDump.new(1, 2)
      struct.should.frozen?
    end

    it "returns frozen objects" do
      source_object = Object.new

      object = Marshal.send(@method, Marshal.dump(source_object), freeze: true)
      object.should.frozen?
    end

    describe "deep freezing" do
      it "returns hashes with frozen keys and values" do
        key = Object.new
        value = Object.new
        source_object = {key => value}

        hash = Marshal.send(@method, Marshal.dump(source_object), freeze: true)
        hash.size.should == 1
        hash.keys[0].should.frozen?
        hash.values[0].should.frozen?
      end

      it "returns arrays with frozen elements" do
        object = Object.new
        source_object = [object]

        array = Marshal.send(@method, Marshal.dump(source_object), freeze: true)
        array.size.should == 1
        array[0].should.frozen?
      end

      it "returns structs with frozen members" do
        object1 = Object.new
        object2 = Object.new
        source_object = MarshalSpec::StructToDump.new(object1, object2)

        struct = Marshal.send(@method, Marshal.dump(source_object), freeze: true)
        struct.a.should.frozen?
        struct.b.should.frozen?
      end

      it "returns objects with frozen instance variables" do
        source_object = Object.new
        instance_variable = Object.new
        source_object.instance_variable_set(:@a, instance_variable)

        object = Marshal.send(@method, Marshal.dump(source_object), freeze: true)
        object.instance_variable_get(:@a).should != nil
        object.instance_variable_get(:@a).should.frozen?
      end

      it "deduplicates frozen strings" do
        source_object = ["foo" + "bar", "foobar"]
        object = Marshal.send(@method, Marshal.dump(source_object), freeze: true)

        object[0].should equal(object[1])
      end
    end

    it "does not freeze modules" do
      object = Marshal.send(@method, Marshal.dump(Kernel), freeze: true)
      object.should_not.frozen?
      Kernel.should_not.frozen?
    end

    it "does not freeze classes" do
      object = Marshal.send(@method, Marshal.dump(Object), freeze: true)
      object.should_not.frozen?
      Object.should_not.frozen?
    end

    ruby_bug "#19427", ""..."3.3" do
      it "does freeze extended objects" do
        object = Marshal.load("\x04\be:\x0FEnumerableo:\vObject\x00", freeze: true)
        object.should.frozen?
      end

      it "does freeze extended objects with instance variables" do
        object = Marshal.load("\x04\be:\x0FEnumerableo:\vObject\x06:\n@ivarT", freeze: true)
        object.should.frozen?
      end
    end

    ruby_bug "#19427", ""..."3.3" do
      it "returns frozen object having #_dump method" do
        object = Marshal.send(@method, Marshal.dump(UserDefined.new), freeze: true)
        object.should.frozen?
      end

      it "returns frozen object responding to #marshal_dump and #marshal_load" do
        object = Marshal.send(@method, Marshal.dump(UserMarshal.new), freeze: true)
        object.should.frozen?
      end

      it "returns frozen object extended by a module" do
        object = Object.new
        object.extend(MarshalSpec::ModuleToExtendBy)

        object = Marshal.send(@method, Marshal.dump(object), freeze: true)
        object.should.frozen?
      end
    end

    it "does not call freeze method" do
      object = MarshalSpec::ObjectWithFreezeRaisingException.new
      object = Marshal.send(@method, Marshal.dump(object), freeze: true)
      object.should.frozen?
    end

    it "returns frozen object even if object does not respond to freeze method" do
      object = MarshalSpec::ObjectWithoutFreeze.new
      object = Marshal.send(@method, Marshal.dump(object), freeze: true)
      object.should.frozen?
    end

    it "returns a frozen object when is an instance of String/Array/Regexp/Hash subclass and has instance variables" do
      source_object = UserString.new
      source_object.instance_variable_set(:@foo, "bar")

      object = Marshal.send(@method, Marshal.dump(source_object), freeze: true)
      object.should.frozen?
    end

    describe "when called with a proc" do
      it "call the proc with frozen objects" do
        arr = []
        s = +'hi'
        s.instance_variable_set(:@foo, 5)
        st = Struct.new("Brittle", :a).new
        st.instance_variable_set(:@clue, 'none')
        st.a = 0.0
        h = Hash.new('def')
        h['nine'] = 9
        a = [:a, :b, :c]
        a.instance_variable_set(:@two, 2)
        obj = [s, 10, s, s, st, a]
        obj.instance_variable_set(:@zoo, 'ant')
        proc = Proc.new { |o| arr << o; o}

        Marshal.send(
          @method,
          "\x04\bI[\vI\"\ahi\a:\x06EF:\t@fooi\ni\x0F@\x06@\x06IS:\x14Struct::Brittle\x06:\x06af\x060\x06:\n@clueI\"\tnone\x06;\x00FI[\b;\b:\x06b:\x06c\x06:\t@twoi\a\x06:\t@zooI\"\bant\x06;\x00F",
          proc,
          freeze: true,
        )

        arr.should == [
          false, 5, "hi", 10, "hi", "hi", 0.0, false, "none", st,
          :b, :c, 2, a, false, "ant", ["hi", 10, "hi", "hi", st, [:a, :b, :c]],
        ]

        arr.each do |v|
          v.should.frozen?
        end

        Struct.send(:remove_const, :Brittle)
      end

      it "does not freeze the object returned by the proc" do
        string = Marshal.send(@method, Marshal.dump("foo"), proc { |o| o.upcase }, freeze: true)
        string.should == "FOO"
        string.should_not.frozen?
      end
    end
  end

  describe "when called with a proc" do
    it "call the proc with fully initialized strings" do
      utf8_string = "foo".encode(Encoding::UTF_8)
      Marshal.send(@method, Marshal.dump(utf8_string), proc { |arg|
        if arg.is_a?(String)
          arg.should == utf8_string
          arg.encoding.should == Encoding::UTF_8
        end
        arg
      })
    end

    it "no longer mutate the object after it was passed to the proc" do
      string = Marshal.load(Marshal.dump("foo"), :freeze.to_proc)
      string.should.frozen?
    end

    ruby_bug "#19427", ""..."3.3" do
      it "call the proc with extended objects" do
        objs = []
        obj = Marshal.load("\x04\be:\x0FEnumerableo:\vObject\x00", Proc.new { |o| objs << o; o })
        objs.should == [obj]
      end
    end

    it "returns the value of the proc" do
      Marshal.send(@method, Marshal.dump([1,2]), proc { [3,4] }).should ==  [3,4]
    end

    it "calls the proc for recursively visited data" do
      a = [1]
      a << a
      ret = []
      Marshal.send(@method, Marshal.dump(a), proc { |arg| ret << arg.inspect; arg })
      ret[0].should == 1.inspect
      ret[1].should == a.inspect
      ret.size.should == 2
    end

    it "loads an Array with proc" do
      arr = []
      s = +'hi'
      s.instance_variable_set(:@foo, 5)
      st = Struct.new("Brittle", :a).new
      st.instance_variable_set(:@clue, 'none')
      st.a = 0.0
      h = Hash.new('def')
      h['nine'] = 9
      a = [:a, :b, :c]
      a.instance_variable_set(:@two, 2)
      obj = [s, 10, s, s, st, a]
      obj.instance_variable_set(:@zoo, 'ant')
      proc = Proc.new { |o| arr << o.dup; o}

      Marshal.send(@method, "\x04\bI[\vI\"\ahi\a:\x06EF:\t@fooi\ni\x0F@\x06@\x06IS:\x14Struct::Brittle\x06:\x06af\x060\x06:\n@clueI\"\tnone\x06;\x00FI[\b;\b:\x06b:\x06c\x06:\t@twoi\a\x06:\t@zooI\"\bant\x06;\x00F", proc)

      arr.should == [
        false, 5, "hi", 10, "hi", "hi", 0.0, false, "none", st,
        :b, :c, 2, a, false, "ant", ["hi", 10, "hi", "hi", st, [:a, :b, :c]],
      ]
      Struct.send(:remove_const, :Brittle)
    end
  end

  describe "when called with nil for the proc argument" do
    it "behaves as if no proc argument was passed" do
      a = [1]
      a << a
      b = Marshal.send(@method, Marshal.dump(a), nil)
      b.should == a
    end
  end

  describe "when called on objects with custom _dump methods" do
    it "does not set instance variables of an object with user-defined _dump/_load" do
      # this string represents: <#UserPreviouslyDefinedWithInitializedIvar @field2=7 @field1=6>
      dump_str = "\004\bu:-UserPreviouslyDefinedWithInitializedIvar\a:\f@field2i\f:\f@field1i\v"

      UserPreviouslyDefinedWithInitializedIvar.should_receive(:_load).and_return(UserPreviouslyDefinedWithInitializedIvar.new)
      marshaled_obj = Marshal.send(@method, dump_str)

      marshaled_obj.should be_an_instance_of(UserPreviouslyDefinedWithInitializedIvar)
      marshaled_obj.field1.should be_nil
      marshaled_obj.field2.should be_nil
    end

    it "loads the String in non US-ASCII and non UTF-8 encoding" do
      source_object = UserDefinedString.new("a".encode("windows-1251"))
      object = Marshal.send(@method, Marshal.dump(source_object))
      object.string.should == "a".encode("windows-1251")
    end

    it "loads the String in multibyte encoding" do
      source_object = UserDefinedString.new("a".encode("utf-32le"))
      object = Marshal.send(@method, Marshal.dump(source_object))
      object.string.should == "a".encode("utf-32le")
    end

    describe "that returns an immediate value" do
      it "loads an array containing an instance of the object, followed by multiple instances of another object" do
        str = "string"

        # this string represents: [<#UserDefinedImmediate A>, <#String "string">, <#String "string">]
        marshaled_obj = Marshal.send(@method, "\004\b[\bu:\031UserDefinedImmediate\000\"\vstring@\a")

        marshaled_obj.should == [nil, str, str]
      end

      it "loads any structure with multiple references to the same object, followed by multiple instances of another object" do
        str = "string"

        # this string represents: {a: <#UserDefinedImmediate A>, b: <#UserDefinedImmediate A>, c: <#String "string">, d: <#String "string">}
        hash_dump = "\x04\b{\t:\x06aIu:\x19UserDefinedImmediate\x00\x06:\x06ET:\x06b@\x06:\x06cI\"\vstring\x06;\aT:\x06d@\a"

        marshaled_obj = Marshal.send(@method, hash_dump)
        marshaled_obj.should == {a: nil, b: nil, c: str, d: str}

        # this string represents: [<#UserDefinedImmediate A>, <#UserDefinedImmediate A>, <#String "string">, <#String "string">]
        array_dump = "\x04\b[\tIu:\x19UserDefinedImmediate\x00\x06:\x06ET@\x06I\"\vstring\x06;\x06T@\a"

        marshaled_obj = Marshal.send(@method, array_dump)
        marshaled_obj.should == [nil, nil, str, str]
      end

      it "loads an array containing references to multiple instances of the object, followed by multiple instances of another object" do
        str = "string"

        # this string represents: [<#UserDefinedImmediate A>, <#UserDefinedImmediate B>, <#String "string">, <#String "string">]
        array_dump = "\x04\b[\tIu:\x19UserDefinedImmediate\x00\x06:\x06ETIu;\x00\x00\x06;\x06TI\"\vstring\x06;\x06T@\b"

        marshaled_obj = Marshal.send(@method, array_dump)
        marshaled_obj.should == [nil, nil, str, str]
      end
    end
  end

  it "loads an array containing objects having _dump method, and with proc" do
    arr = []
    myproc = Proc.new { |o| arr << o.dup; o }
    o1 = UserDefined.new;
    o2 = UserDefinedWithIvar.new
    obj = [o1, o2, o1, o2]

    Marshal.send(@method, "\x04\b[\tu:\x10UserDefined\x18\x04\b[\aI\"\nstuff\x06:\x06EF@\x06u:\x18UserDefinedWithIvar>\x04\b[\bI\"\nstuff\a:\x06EF:\t@foo:\x18UserDefinedWithIvarI\"\tmore\x06;\x00F@\a@\x06@\a", myproc)

    arr[0].should == o1
    arr[1].should == o2
    arr[2].should == obj
    arr.size.should == 3
  end

  it "loads an array containing objects having marshal_dump method, and with proc" do
    arr = []
    proc = Proc.new { |o| arr << o.dup; o }
    o1 = UserMarshal.new
    o2 = UserMarshalWithIvar.new

    Marshal.send(@method, "\004\b[\tU:\020UserMarshal\"\nstuffU:\030UserMarshalWithIvar[\006\"\fmy data@\006@\b", proc)

    arr[0].should == 'stuff'
    arr[1].should == o1
    arr[2].should == 'my data'
    arr[3].should == ['my data']
    arr[4].should == o2
    arr[5].should == [o1, o2, o1, o2]

    arr.size.should == 6
  end

  it "assigns classes to nested subclasses of Array correctly" do
    arr = ArraySub.new(ArraySub.new)
    arr_dump = Marshal.dump(arr)
    Marshal.send(@method, arr_dump).class.should == ArraySub
  end

  it "loads subclasses of Array with overridden << and push correctly" do
    arr = ArraySubPush.new
    arr[0] = '1'
    arr_dump = Marshal.dump(arr)
    Marshal.send(@method, arr_dump).should == arr
  end

  it "raises a TypeError with bad Marshal version" do
    marshal_data = +'\xff\xff'
    marshal_data[0] = (Marshal::MAJOR_VERSION).chr
    marshal_data[1] = (Marshal::MINOR_VERSION + 1).chr

    -> { Marshal.send(@method, marshal_data) }.should raise_error(TypeError)

    marshal_data = +'\xff\xff'
    marshal_data[0] = (Marshal::MAJOR_VERSION - 1).chr
    marshal_data[1] = (Marshal::MINOR_VERSION).chr

    -> { Marshal.send(@method, marshal_data) }.should raise_error(TypeError)
  end

  it "raises EOFError on loading an empty file" do
    temp_file = tmp("marshal.rubyspec.tmp.#{Process.pid}")
    file = File.new(temp_file, "w+")
    begin
      -> { Marshal.send(@method, file) }.should raise_error(EOFError)
    ensure
      file.close
      rm_r temp_file
    end
  end

  # Note: Ruby 1.9 should be compatible with older marshal format
  MarshalSpec::DATA.each do |description, (object, marshal, attributes)|
    it "loads a #{description}" do
      Marshal.send(@method, marshal).should == object
    end
  end

  MarshalSpec::DATA_19.each do |description, (object, marshal, attributes)|
    it "loads a #{description}" do
      Marshal.send(@method, marshal).should == object
    end
  end

  describe "for an Array" do
    it "loads an array containing the same objects" do
      s = 'oh'
      b = 'hi'
      r = //
      d = [b, :no, s, :go]
      c = String
      f = 1.0

      o1 = UserMarshalWithIvar.new; o2 = UserMarshal.new

      obj = [:so, 'hello', 100, :so, :so, d, :so, o2, :so, :no, o2,
             :go, c, nil, Struct::Pyramid.new, f, :go, :no, s, b, r,
             :so, 'huh', o1, true, b, b, 99, r, b, s, :so, f, c, :no, o1, d]

      Marshal.send(@method, "\004\b[*:\aso\"\nhelloii;\000;\000[\t\"\ahi:\ano\"\aoh:\ago;\000U:\020UserMarshal\"\nstuff;\000;\006@\n;\ac\vString0S:\024Struct::Pyramid\000f\0061;\a;\006@\t@\b/\000\000;\000\"\bhuhU:\030UserMarshalWithIvar[\006\"\fmy dataT@\b@\bih@\017@\b@\t;\000@\016@\f;\006@\021@\a").should ==
        obj
    end

    it "loads an array having ivar" do
      s = +'well'
      s.instance_variable_set(:@foo, 10)
      obj = ['5', s, 'hi'].extend(Meths, MethsMore)
      obj.instance_variable_set(:@mix, s)
      new_obj = Marshal.send(@method, "\004\bI[\b\"\0065I\"\twell\006:\t@fooi\017\"\ahi\006:\t@mix@\a")
      new_obj.should == obj
      new_obj.instance_variable_get(:@mix).should equal new_obj[1]
      new_obj[1].instance_variable_get(:@foo).should == 10
    end

    it "loads an extended Array object containing a user-marshaled object" do
      obj = [UserMarshal.new, UserMarshal.new].extend(Meths)
      dump = "\x04\be:\nMeths[\ao:\x10UserMarshal\x06:\n@dataI\"\nstuff\x06:\x06ETo;\x06\x06;\aI\"\nstuff\x06;\bT"
      new_obj = Marshal.send(@method, dump)

      new_obj.should == obj
      obj_ancestors = class << obj; ancestors[1..-1]; end
      new_obj_ancestors = class << new_obj; ancestors[1..-1]; end
      obj_ancestors.should == new_obj_ancestors
    end
  end

  describe "for a Hash" do
    it "loads an extended_user_hash with a parameter to initialize" do
      obj = UserHashInitParams.new(:abc).extend(Meths)

      new_obj = Marshal.send(@method, "\004\bIe:\nMethsC:\027UserHashInitParams{\000\006:\a@a:\babc")

      new_obj.should == obj
      new_obj_metaclass_ancestors = class << new_obj; ancestors; end
      new_obj_metaclass_ancestors[@num_self_class].should == Meths
      new_obj_metaclass_ancestors[@num_self_class+1].should == UserHashInitParams
    end

    it "loads an extended hash object containing a user-marshaled object" do
      obj = {a: UserMarshal.new}.extend(Meths)

      new_obj = Marshal.send(@method, "\004\be:\nMeths{\006:\006aU:\020UserMarshal\"\nstuff")

      new_obj.should == obj
      new_obj_metaclass_ancestors = class << new_obj; ancestors; end
      new_obj_metaclass_ancestors[@num_self_class].should == Meths
      new_obj_metaclass_ancestors[@num_self_class+1].should == Hash
    end

    it "preserves hash ivars when hash contains a string having ivar" do
      s = +'string'
      s.instance_variable_set :@string_ivar, 'string ivar'
      h = { key: s }
      h.instance_variable_set :@hash_ivar, 'hash ivar'

      unmarshalled = Marshal.send(@method, Marshal.dump(h))
      unmarshalled.instance_variable_get(:@hash_ivar).should == 'hash ivar'
      unmarshalled[:key].instance_variable_get(:@string_ivar).should == 'string ivar'
    end

    it "preserves compare_by_identity behaviour" do
      h = { a: 1 }
      h.compare_by_identity
      unmarshalled = Marshal.send(@method, Marshal.dump(h))
      unmarshalled.should.compare_by_identity?

      h = { a: 1 }
      unmarshalled = Marshal.send(@method, Marshal.dump(h))
      unmarshalled.should_not.compare_by_identity?
    end

    it "preserves compare_by_identity behaviour for a Hash subclass" do
      h = UserHash.new({ a: 1 })
      h.compare_by_identity
      unmarshalled = Marshal.send(@method, Marshal.dump(h))
      unmarshalled.should.compare_by_identity?

      h = UserHash.new({ a: 1 })
      unmarshalled = Marshal.send(@method, Marshal.dump(h))
      unmarshalled.should_not.compare_by_identity?
    end

    it "allocates an instance of the proper class when Hash subclass with compare_by_identity behaviour" do
      h = UserHash.new({ a: 1 })
      h.compare_by_identity

      unmarshalled = Marshal.send(@method, Marshal.dump(h))
      unmarshalled.should.kind_of?(UserHash)
    end
  end

  describe "for a Symbol" do
    it "loads a Symbol" do
      sym = Marshal.send(@method, "\004\b:\vsymbol")
      sym.should == :symbol
      sym.encoding.should == Encoding::US_ASCII
    end

    it "loads a big Symbol" do
      sym = ('big' * 100).to_sym
      Marshal.send(@method, "\004\b:\002,\001#{'big' * 100}").should == sym
    end

    it "loads an encoded Symbol" do
      s = "\u2192"

      sym = Marshal.send(@method, "\x04\bI:\b\xE2\x86\x92\x06:\x06ET")
      sym.should == s.encode("utf-8").to_sym
      sym.encoding.should == Encoding::UTF_8

      sym = Marshal.send(@method, "\x04\bI:\t\xFE\xFF!\x92\x06:\rencoding\"\vUTF-16")
      sym.should == s.encode("utf-16").to_sym
      sym.encoding.should == Encoding::UTF_16

      sym = Marshal.send(@method, "\x04\bI:\a\x92!\x06:\rencoding\"\rUTF-16LE")
      sym.should == s.encode("utf-16le").to_sym
      sym.encoding.should == Encoding::UTF_16LE

      sym = Marshal.send(@method, "\x04\bI:\a!\x92\x06:\rencoding\"\rUTF-16BE")
      sym.should == s.encode("utf-16be").to_sym
      sym.encoding.should == Encoding::UTF_16BE

      sym = Marshal.send(@method, "\x04\bI:\a\xA2\xAA\x06:\rencoding\"\vEUC-JP")
      sym.should == s.encode("euc-jp").to_sym
      sym.encoding.should == Encoding::EUC_JP

      sym = Marshal.send(@method, "\x04\bI:\a\x81\xA8\x06:\rencoding\"\x10Windows-31J")
      sym.should == s.encode("sjis").to_sym
      sym.encoding.should == Encoding::SJIS
    end

    it "loads a binary encoded Symbol" do
      s = "\u2192".dup.force_encoding("binary").to_sym
      sym = Marshal.send(@method, "\x04\b:\b\xE2\x86\x92")
      sym.should == s
      sym.encoding.should == Encoding::BINARY
    end

    it "loads multiple Symbols sharing the same encoding" do
      # Note that the encoding is a link for the second Symbol
      symbol1 = "I:\t\xE2\x82\xACa\x06:\x06ET"
      symbol2 = "I:\t\xE2\x82\xACb\x06;\x06T"
      dump = "\x04\b[\a#{symbol1}#{symbol2}"
      value = Marshal.send(@method, dump)
      value.map(&:encoding).should == [Encoding::UTF_8, Encoding::UTF_8]
      expected = [
        "€a".dup.force_encoding(Encoding::UTF_8).to_sym,
        "€b".dup.force_encoding(Encoding::UTF_8).to_sym
      ]
      value.should == expected

      value = Marshal.send(@method, "\x04\b[\b#{symbol1}#{symbol2};\x00")
      value.map(&:encoding).should == [Encoding::UTF_8, Encoding::UTF_8, Encoding::UTF_8]
      value.should == [*expected, expected[0]]
    end

    it "raises ArgumentError when end of byte sequence reached before symbol characters end" do
      Marshal.dump(:hello).should == "\x04\b:\nhello"

      -> {
        Marshal.send(@method, "\x04\b:\nhel")
      }.should raise_error(ArgumentError, "marshal data too short")
    end
  end

  describe "for a String" do
    it "loads a string having ivar with ref to self" do
      obj = +'hi'
      obj.instance_variable_set(:@self, obj)
      Marshal.send(@method, "\004\bI\"\ahi\006:\n@self@\000").should == obj
    end

    it "loads a string through StringIO stream" do
      require 'stringio'
      obj = "This is a string which should be unmarshalled through StringIO stream!"
      Marshal.send(@method, StringIO.new(Marshal.dump(obj))).should == obj
    end

    it "sets binmode if it is loading through StringIO stream" do
      io = StringIO.new("\004\b:\vsymbol")
      def io.binmode; raise "binmode"; end
      -> { Marshal.load(io) }.should raise_error(RuntimeError, "binmode")
    end

    it "loads a string with an ivar" do
      str = Marshal.send(@method, "\x04\bI\"\x00\x06:\t@fooI\"\bbar\x06:\x06EF")
      str.instance_variable_get("@foo").should == "bar"
    end

    it "loads a String subclass with custom constructor" do
      str = Marshal.send(@method, "\x04\bC: UserCustomConstructorString\"\x00")
      str.should be_an_instance_of(UserCustomConstructorString)
    end

    it "loads a US-ASCII String" do
      str = "abc".dup.force_encoding("us-ascii")
      data = "\x04\bI\"\babc\x06:\x06EF"
      result = Marshal.send(@method, data)
      result.should == str
      result.encoding.should equal(Encoding::US_ASCII)
    end

    it "loads a UTF-8 String" do
      str = "\x6d\xc3\xb6\x68\x72\x65".dup.force_encoding("utf-8")
      data = "\x04\bI\"\vm\xC3\xB6hre\x06:\x06ET"
      result = Marshal.send(@method, data)
      result.should == str
      result.encoding.should equal(Encoding::UTF_8)
    end

    it "loads a String in another encoding" do
      str = "\x6d\x00\xf6\x00\x68\x00\x72\x00\x65\x00".dup.force_encoding("utf-16le")
      data = "\x04\bI\"\x0Fm\x00\xF6\x00h\x00r\x00e\x00\x06:\rencoding\"\rUTF-16LE"
      result = Marshal.send(@method, data)
      result.should == str
      result.encoding.should equal(Encoding::UTF_16LE)
    end

    it "loads a String as BINARY if no encoding is specified at the end" do
      str = "\xC3\xB8".dup.force_encoding("BINARY")
      data = "\x04\b\"\a\xC3\xB8".dup.force_encoding("UTF-8")
      result = Marshal.send(@method, data)
      result.encoding.should == Encoding::BINARY
      result.should == str
    end

    it "raises ArgumentError when end of byte sequence reached before string characters end" do
      Marshal.dump("hello").should == "\x04\b\"\nhello"

      -> {
        Marshal.send(@method, "\x04\b\"\nhel")
      }.should raise_error(ArgumentError, "marshal data too short")
    end
  end

  describe "for a Struct" do
    it "loads a extended_struct having fields with same objects" do
      s = 'hi'
      obj = Struct.new("Extended", :a, :b).new.extend(Meths)
      dump = "\004\be:\nMethsS:\025Struct::Extended\a:\006a0:\006b0"
      Marshal.send(@method, dump).should == obj

      obj.a = [:a, s]
      obj.b = [:Meths, s]
      dump = "\004\be:\nMethsS:\025Struct::Extended\a:\006a[\a;\a\"\ahi:\006b[\a;\000@\a"
      Marshal.send(@method, dump).should == obj
      Struct.send(:remove_const, :Extended)
    end

    it "loads a struct having ivar" do
      obj = Struct.new("Thick").new
      obj.instance_variable_set(:@foo, 5)
      reloaded = Marshal.send(@method, "\004\bIS:\022Struct::Thick\000\006:\t@fooi\n")
      reloaded.should == obj
      reloaded.instance_variable_get(:@foo).should == 5
      Struct.send(:remove_const, :Thick)
    end

    it "loads a struct having fields" do
      obj = Struct.new("Ure1", :a, :b).new
      Marshal.send(@method, "\004\bS:\021Struct::Ure1\a:\006a0:\006b0").should == obj
      Struct.send(:remove_const, :Ure1)
    end

    it "does not call initialize on the unmarshaled struct" do
      threadlocal_key = MarshalSpec::StructWithUserInitialize::THREADLOCAL_KEY

      s = MarshalSpec::StructWithUserInitialize.new('foo')
      Thread.current[threadlocal_key].should == ['foo']
      s.a.should == 'foo'

      Thread.current[threadlocal_key] = nil

      dumped = Marshal.dump(s)
      loaded = Marshal.send(@method, dumped)

      Thread.current[threadlocal_key].should == nil
      loaded.a.should == 'foo'
    end
  end

  describe "for a Data" do
    it "loads a Data" do
      obj = MarshalSpec::DataSpec::Measure.new(100, 'km')
      dumped = "\x04\bS:#MarshalSpec::DataSpec::Measure\a:\vamountii:\tunit\"\akm"
      Marshal.dump(obj).should == dumped

      Marshal.send(@method, dumped).should == obj
    end

    it "loads an extended Data" do
      obj = MarshalSpec::DataSpec::MeasureExtended.new(100, "km")
      dumped = "\x04\bS:+MarshalSpec::DataSpec::MeasureExtended\a:\vamountii:\tunit\"\akm"
      Marshal.dump(obj).should == dumped

      Marshal.send(@method, dumped).should == obj
    end

    it "returns a frozen object" do
      obj = MarshalSpec::DataSpec::Measure.new(100, 'km')
      dumped = "\x04\bS:#MarshalSpec::DataSpec::Measure\a:\vamountii:\tunit\"\akm"
      Marshal.dump(obj).should == dumped

      Marshal.send(@method, dumped).should.frozen?
    end
  end

  describe "for an Exception" do
    it "loads a marshalled exception with no message" do
      obj = Exception.new
      loaded = Marshal.send(@method, "\004\bo:\016Exception\a:\abt0:\tmesg0")
      loaded.message.should == obj.message
      loaded.backtrace.should == obj.backtrace
      loaded = Marshal.send(@method, "\x04\bo:\x0EException\a:\tmesg0:\abt0")
      loaded.message.should == obj.message
      loaded.backtrace.should == obj.backtrace
    end

    it "loads a marshalled exception with a message" do
      obj = Exception.new("foo")
      loaded = Marshal.send(@method, "\004\bo:\016Exception\a:\abt0:\tmesg\"\bfoo")
      loaded.message.should == obj.message
      loaded.backtrace.should == obj.backtrace
      loaded = Marshal.send(@method, "\x04\bo:\x0EException\a:\tmesgI\"\bfoo\x06:\x06EF:\abt0")
      loaded.message.should == obj.message
      loaded.backtrace.should == obj.backtrace
    end

    it "loads a marshalled exception with a backtrace" do
      obj = Exception.new("foo")
      obj.set_backtrace(["foo/bar.rb:10"])
      loaded = Marshal.send(@method, "\004\bo:\016Exception\a:\abt[\006\"\022foo/bar.rb:10:\tmesg\"\bfoo")
      loaded.message.should == obj.message
      loaded.backtrace.should == obj.backtrace
      loaded = Marshal.send(@method, "\x04\bo:\x0EException\a:\tmesgI\"\bfoo\x06:\x06EF:\abt[\x06I\"\x12foo/bar.rb:10\x06;\aF")
      loaded.message.should == obj.message
      loaded.backtrace.should == obj.backtrace
    end

    it "loads an marshalled exception with ivars" do
      s = 'hi'
      arr = [:so, :so, s, s]
      obj = Exception.new("foo")
      obj.instance_variable_set :@arr, arr

      loaded = Marshal.send(@method, "\x04\bo:\x0EException\b:\tmesg\"\bfoo:\abt0:\t@arr[\t:\aso;\t\"\ahi@\b")
      new_arr = loaded.instance_variable_get :@arr

      loaded.message.should == obj.message
      new_arr.should == arr
    end
  end

  describe "for an Object" do
    it "loads an object" do
      Marshal.send(@method, "\004\bo:\vObject\000").should be_kind_of(Object)
    end

    it "loads an extended Object" do
      obj = Object.new.extend(Meths)

      new_obj = Marshal.send(@method, "\004\be:\nMethso:\vObject\000")

      new_obj.class.should == obj.class
      new_obj_metaclass_ancestors = class << new_obj; ancestors; end
      new_obj_metaclass_ancestors[@num_self_class, 2].should == [Meths, Object]
    end

    it "loads an object having ivar" do
      s = 'hi'
      arr = [:so, :so, s, s]
      obj = Object.new
      obj.instance_variable_set :@str, arr

      new_obj = Marshal.send(@method, "\004\bo:\vObject\006:\t@str[\t:\aso;\a\"\ahi@\a")
      new_str = new_obj.instance_variable_get :@str

      new_str.should == arr
    end

    it "loads an Object with a non-US-ASCII instance variable" do
      ivar = "@é".dup.force_encoding(Encoding::UTF_8).to_sym
      obj = Marshal.send(@method, "\x04\bo:\vObject\x06I:\b@\xC3\xA9\x06:\x06ETi\x06")
      obj.instance_variables.should == [ivar]
      obj.instance_variables[0].encoding.should == Encoding::UTF_8
      obj.instance_variable_get(ivar).should == 1
    end

    it "raises ArgumentError if the object from an 'o' stream is not dumpable as 'o' type user class" do
      -> do
        Marshal.send(@method, "\x04\bo:\tFile\001\001:\001\005@path\"\x10/etc/passwd")
      end.should raise_error(ArgumentError)
    end

    it "raises ArgumentError when end of byte sequence reached before class name end" do
      Marshal.dump(Object.new).should == "\x04\bo:\vObject\x00"

      -> {
        Marshal.send(@method, "\x04\bo:\vObj")
      }.should raise_error(ArgumentError, "marshal data too short")
    end
  end

  describe "for an object responding to #marshal_dump and #marshal_load" do
    it "loads a user-marshaled object" do
      obj = UserMarshal.new
      obj.data = :data
      value = [obj, :data]
      dump = Marshal.dump(value)
      dump.should == "\x04\b[\aU:\x10UserMarshal:\tdata;\x06"
      reloaded = Marshal.load(dump)
      reloaded.should == value
    end
  end

  describe "for a user object" do
    it "loads a user-marshaled extended object" do
      obj = UserMarshal.new.extend(Meths)

      new_obj = Marshal.send(@method, "\004\bU:\020UserMarshal\"\nstuff")

      new_obj.should == obj
      new_obj_metaclass_ancestors = class << new_obj; ancestors; end
      new_obj_metaclass_ancestors[@num_self_class].should == UserMarshal
    end

    it "loads a UserObject" do
      Marshal.send(@method, "\004\bo:\017UserObject\000").should be_kind_of(UserObject)
    end

    describe "that extends a core type other than Object or BasicObject" do
      after :each do
        MarshalSpec.reset_swapped_class
      end

      it "raises ArgumentError if the resulting class does not extend the same type" do
        MarshalSpec.set_swapped_class(Class.new(Hash))
        data = Marshal.dump(MarshalSpec::SwappedClass.new)

        MarshalSpec.set_swapped_class(Class.new(Array))
        -> { Marshal.send(@method, data) }.should raise_error(ArgumentError)

        MarshalSpec.set_swapped_class(Class.new)
        -> { Marshal.send(@method, data) }.should raise_error(ArgumentError)
      end
    end
  end

  describe "for a Regexp" do
    it "loads an extended Regexp" do
      obj = /[a-z]/.dup.extend(Meths, MethsMore)
      new_obj = Marshal.send(@method, "\004\be:\nMethse:\016MethsMore/\n[a-z]\000")

      new_obj.should == obj
      new_obj_metaclass_ancestors = class << new_obj; ancestors; end
      new_obj_metaclass_ancestors[@num_self_class, 3].should ==
        [Meths, MethsMore, Regexp]
    end

    it "loads a Regexp subclass instance variables when it is extended with a module" do
      obj = UserRegexp.new('').extend(Meths)
      obj.instance_variable_set(:@noise, 'much')

      new_obj = Marshal.send(@method, "\004\bIe:\nMethsC:\017UserRegexp/\000\000\006:\v@noise\"\tmuch")

      new_obj.should == obj
      new_obj.instance_variable_get(:@noise).should == 'much'
      new_obj_metaclass_ancestors = class << new_obj; ancestors; end
      new_obj_metaclass_ancestors[@num_self_class, 3].should ==
        [Meths, UserRegexp, Regexp]
    end

    ruby_bug "#19439", ""..."3.3" do
      it "restore the regexp instance variables" do
        obj = Regexp.new("hello")
        obj.instance_variable_set(:@regexp_ivar, [42])

        new_obj = Marshal.send(@method, "\x04\bI/\nhello\x00\a:\x06EF:\x11@regexp_ivar[\x06i/")
        new_obj.instance_variables.should == [:@regexp_ivar]
        new_obj.instance_variable_get(:@regexp_ivar).should == [42]
      end
    end

    it "preserves Regexp encoding" do
      source_object = Regexp.new("a".encode("utf-32le"))
      regexp = Marshal.send(@method, Marshal.dump(source_object))

      regexp.encoding.should == Encoding::UTF_32LE
      regexp.source.should == "a".encode("utf-32le")
    end

    it "raises ArgumentError when end of byte sequence reached before source string end" do
      Marshal.dump(/hello world/).should == "\x04\bI/\x10hello world\x00\x06:\x06EF"

      -> {
        Marshal.send(@method, "\x04\bI/\x10hel")
      }.should raise_error(ArgumentError, "marshal data too short")
    end
  end

  describe "for a Float" do
    it "loads a Float NaN" do
      obj = 0.0 / 0.0
      Marshal.send(@method, "\004\bf\bnan").to_s.should == obj.to_s
    end

    it "loads a Float 1.3" do
      Marshal.send(@method, "\004\bf\v1.3\000\314\315").should == 1.3
    end

    it "loads a Float -5.1867345e-22" do
      obj = -5.1867345e-22
      Marshal.send(@method, "\004\bf\037-5.1867345000000008e-22\000\203_").should be_close(obj, 1e-30)
    end

    it "loads a Float 1.1867345e+22" do
      obj = 1.1867345e+22
      Marshal.send(@method, "\004\bf\0361.1867344999999999e+22\000\344@").should == obj
    end

    it "raises ArgumentError when end of byte sequence reached before float string representation end" do
      Marshal.dump(1.3).should == "\x04\bf\b1.3"

      -> {
        Marshal.send(@method, "\004\bf\v1")
      }.should raise_error(ArgumentError, "marshal data too short")
    end
  end

  describe "for an Integer" do
    it "loads 0" do
      Marshal.send(@method, "\004\bi\000").should == 0
      Marshal.send(@method, "\004\bi\005").should == 0
    end

    it "loads an Integer 8" do
      Marshal.send(@method, "\004\bi\r" ).should == 8
    end

    it "loads and Integer -8" do
      Marshal.send(@method, "\004\bi\363" ).should == -8
    end

    it "loads an Integer 1234" do
      Marshal.send(@method, "\004\bi\002\322\004").should == 1234
    end

    it "loads an Integer -1234" do
      Marshal.send(@method, "\004\bi\376.\373").should == -1234
    end

    it "loads an Integer 4611686018427387903" do
      Marshal.send(@method, "\004\bl+\t\377\377\377\377\377\377\377?").should == 4611686018427387903
    end

    it "loads an Integer -4611686018427387903" do
      Marshal.send(@method, "\004\bl-\t\377\377\377\377\377\377\377?").should == -4611686018427387903
    end

    it "loads an Integer 2361183241434822606847" do
      Marshal.send(@method, "\004\bl+\n\377\377\377\377\377\377\377\377\177\000").should == 2361183241434822606847
    end

    it "loads an Integer -2361183241434822606847" do
      Marshal.send(@method, "\004\bl-\n\377\377\377\377\377\377\377\377\177\000").should == -2361183241434822606847
    end

    it "raises ArgumentError if the input is too short" do
      ["\004\bi",
       "\004\bi\001",
       "\004\bi\002",
       "\004\bi\002\0",
       "\004\bi\003",
       "\004\bi\003\0",
       "\004\bi\003\0\0",
       "\004\bi\004",
       "\004\bi\004\0",
       "\004\bi\004\0\0",
       "\004\bi\004\0\0\0"].each do |invalid|
        -> { Marshal.send(@method, invalid) }.should raise_error(ArgumentError)
      end
    end

    if 0.size == 8 # for platforms like x86_64
      it "roundtrips 4611686018427387903 from dump/load correctly" do
        Marshal.send(@method, Marshal.dump(4611686018427387903)).should == 4611686018427387903
      end
    end
  end

  describe "for a Rational" do
    it "loads" do
      r = Marshal.send(@method, Marshal.dump(Rational(1, 3)))
      r.should == Rational(1, 3)
      r.should.frozen?
    end
  end

  describe "for a Complex" do
    it "loads" do
      c = Marshal.send(@method, Marshal.dump(Complex(4, 3)))
      c.should == Complex(4, 3)
      c.should.frozen?
    end
  end

  describe "for a Bignum" do
    platform_is c_long_size: 64 do
      context "that is Bignum on 32-bit platforms but Fixnum on 64-bit" do
        it "dumps a Fixnum" do
          val = Marshal.send(@method, "\004\bl+\ab:wU")
          val.should == 1433877090
          val.class.should == Integer
        end

        it "dumps an array containing multiple references to the Bignum as an array of Fixnum" do
          arr = Marshal.send(@method, "\004\b[\al+\a\223BwU@\006")
          arr.should == [1433879187, 1433879187]
          arr.each { |v| v.class.should == Integer }
        end
      end
    end
  end

  describe "for a Time" do
    it "loads" do
      Marshal.send(@method, Marshal.dump(Time.at(1))).should == Time.at(1)
    end

    it "loads serialized instance variables" do
      t = Time.new
      t.instance_variable_set(:@foo, 'bar')

      Marshal.send(@method, Marshal.dump(t)).instance_variable_get(:@foo).should == 'bar'
    end

    it "loads Time objects stored as links" do
      t = Time.new

      t1, t2 = Marshal.send(@method, Marshal.dump([t, t]))
      t1.should equal t2
    end

    it "keeps the local zone" do
      with_timezone 'AST', 3 do
        t = Time.local(2012, 1, 1)
        Marshal.send(@method, Marshal.dump(t)).zone.should == t.zone
      end
    end

    it "keeps UTC zone" do
      t = Time.now.utc
      t2 = Marshal.send(@method, Marshal.dump(t))
      t2.should.utc?
    end

    it "keeps the zone" do
      t = nil

      with_timezone 'AST', 4 do
        t = Time.local(2012, 1, 1)
      end

      with_timezone 'EET', -2 do
        Marshal.send(@method, Marshal.dump(t)).zone.should == 'AST'
      end
    end

    it "keeps utc offset" do
      t = Time.new(2007,11,1,15,25,0, "+09:00")
      t2 = Marshal.send(@method, Marshal.dump(t))
      t2.utc_offset.should == 32400
    end

    it "keeps nanoseconds" do
      t = Time.now
      Marshal.send(@method, Marshal.dump(t)).nsec.should == t.nsec
    end

    it "does not add any additional instance variable" do
      t = Time.now
      t2 = Marshal.send(@method, Marshal.dump(t))
      t2.instance_variables.should.empty?
    end
  end

  describe "for nil" do
    it "loads" do
      Marshal.send(@method, "\x04\b0").should be_nil
    end
  end

  describe "for true" do
    it "loads" do
      Marshal.send(@method, "\x04\bT").should be_true
    end
  end

  describe "for false" do
    it "loads" do
      Marshal.send(@method, "\x04\bF").should be_false
    end
  end

  describe "for a Class" do
    it "loads" do
      Marshal.send(@method, "\x04\bc\vString").should == String
    end

    it "raises ArgumentError if given the name of a non-Module" do
      -> { Marshal.send(@method, "\x04\bc\vKernel") }.should raise_error(ArgumentError)
    end

    it "raises ArgumentError if given a nonexistent class" do
      -> { Marshal.send(@method, "\x04\bc\vStrung") }.should raise_error(ArgumentError)
    end

    it "raises ArgumentError when end of byte sequence reached before class name end" do
      Marshal.dump(String).should == "\x04\bc\vString"

      -> {
        Marshal.send(@method, "\x04\bc\vStr")
      }.should raise_error(ArgumentError, "marshal data too short")
    end
  end

  describe "for a Module" do
    it "loads a module" do
      Marshal.send(@method, "\x04\bm\vKernel").should == Kernel
    end

    it "raises ArgumentError if given the name of a non-Class" do
      -> { Marshal.send(@method, "\x04\bm\vString") }.should raise_error(ArgumentError)
    end

    it "loads an old module" do
      Marshal.send(@method, "\x04\bM\vKernel").should == Kernel
    end

    it "raises ArgumentError when end of byte sequence reached before module name end" do
      Marshal.dump(Kernel).should == "\x04\bm\vKernel"

      -> {
        Marshal.send(@method, "\x04\bm\vKer")
      }.should raise_error(ArgumentError, "marshal data too short")
    end
  end

  describe "for a wrapped C pointer" do
    it "loads" do
      class DumpableDir < Dir
        def _dump_data
          path
        end
        def _load_data path
          initialize(path)
        end
      end

      data = "\x04\bd:\x10DumpableDirI\"\x06.\x06:\x06ET"

      dir = Marshal.send(@method, data)
      begin
        dir.path.should == '.'
      ensure
        dir.close
      end
    end

    it "raises TypeError when the local class is missing _load_data" do
      class UnloadableDumpableDir < Dir
        def _dump_data
          path
        end
        # no _load_data
      end

      data = "\x04\bd:\x1AUnloadableDumpableDirI\"\x06.\x06:\x06ET"

      -> { Marshal.send(@method, data) }.should raise_error(TypeError)
    end

    it "raises ArgumentError when the local class is a regular object" do
      data = "\004\bd:\020UserDefined\0"

      -> { Marshal.send(@method, data) }.should raise_error(ArgumentError)
    end
  end

  describe "when a class does not exist in the namespace" do
    before :each do
      NamespaceTest.send(:const_set, :SameName, Class.new)
      @data = Marshal.dump(NamespaceTest::SameName.new)
      NamespaceTest.send(:remove_const, :SameName)
    end

    it "raises an ArgumentError" do
      message = "undefined class/module NamespaceTest::SameName"
      -> { Marshal.send(@method, @data) }.should raise_error(ArgumentError, message)
    end
  end

  it "raises an ArgumentError with full constant name when the dumped constant is missing" do
    NamespaceTest.send(:const_set, :KaBoom, Class.new)
    @data = Marshal.dump(NamespaceTest::KaBoom.new)
    NamespaceTest.send(:remove_const, :KaBoom)

    -> { Marshal.send(@method, @data) }.should raise_error(ArgumentError, /NamespaceTest::KaBoom/)
  end
end
