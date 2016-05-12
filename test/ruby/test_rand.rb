# frozen_string_literal: false
require 'test/unit'

class TestRand < Test::Unit::TestCase
  def assert_random_int(ws, m, init = 0)
    srand(init)
    rnds = [Random.new(init)]
    rnds2 = [rnds[0].dup]
    rnds3 = [rnds[0].dup]
    ws.each_with_index do |w, i|
      w = w.to_i
      assert_equal(w, rand(m))
      rnds.each do |rnd|
        assert_equal(w, rnd.rand(m))
      end
      rnds2.each do |rnd|
        r=rnd.rand(i...(m+i))
        assert_equal(w+i, r)
      end
      rnds3.each do |rnd|
        r=rnd.rand(i..(m+i-1))
        assert_equal(w+i, r)
      end
      rnds << Marshal.load(Marshal.dump(rnds[-1]))
      rnds2 << Marshal.load(Marshal.dump(rnds2[-1]))
    end
  end

  def test_mt
    assert_random_int(%w(1067595299  955945823  477289528 4107218783 4228976476),
                      0x100000000, 0x00000456_00000345_00000234_00000123)
  end

  def test_0x3fffffff
    assert_random_int(%w(209652396 398764591 924231285 404868288 441365315),
                      0x3fffffff)
  end

  def test_0x40000000
    assert_random_int(%w(209652396 398764591 924231285 404868288 441365315),
                      0x40000000)
  end

  def test_0x40000001
    assert_random_int(%w(209652396 398764591 924231285 441365315 192771779),
                      0x40000001)
  end

  def test_0xffffffff
    assert_random_int(%w(2357136044 2546248239 3071714933 3626093760 2588848963),
                      0xffffffff)
  end

  def test_0x100000000
    assert_random_int(%w(2357136044 2546248239 3071714933 3626093760 2588848963),
                      0x100000000)
  end

  def test_0x100000001
    assert_random_int(%w(2546248239 1277901399 243580376 1171049868 2051556033),
                      0x100000001)
  end

  def test_rand_0x100000000
    assert_random_int(%w(4119812344 3870378946 80324654 4294967296 410016213),
                      0x100000001, 311702798)
  end

  def test_0x1000000000000
    assert_random_int(%w(11736396900911
                         183025067478208
                         197104029029115
                         130583529618791
                         180361239846611),
                      0x1000000000000)
  end

  def test_0x1000000000001
    assert_random_int(%w(187121911899765
                         197104029029115
                         180361239846611
                         236336749852452
                         208739549485656),
                      0x1000000000001)
  end

  def test_0x3fffffffffffffff
    assert_random_int(%w(900450186894289455
                         3969543146641149120
                         1895649597198586619
                         827948490035658087
                         3203365596207111891),
                      0x3fffffffffffffff)
  end

  def test_0x4000000000000000
    assert_random_int(%w(900450186894289455
                         3969543146641149120
                         1895649597198586619
                         827948490035658087
                         3203365596207111891),
                      0x4000000000000000)
  end

  def test_0x4000000000000001
    assert_random_int(%w(900450186894289455
                         3969543146641149120
                         1895649597198586619
                         827948490035658087
                         2279347887019741461),
                      0x4000000000000001)
  end

  def test_0x10000000000
    ws = %w(455570294424 1073054410371 790795084744 2445173525 1088503892627)
    assert_random_int(ws, 0x10000000000, 3)
  end

  def test_0x10000
    ws = %w(2732 43567 42613 52416 45891)
    assert_random_int(ws, 0x10000)
  end

  def test_types
    srand(0)
    rnd = Random.new(0)
    assert_equal(44, rand(100.0))
    assert_equal(44, rnd.rand(100))
    assert_equal(1245085576965981900420779258691, rand((2**100).to_f))
    assert_equal(1245085576965981900420779258691, rnd.rand(2**100))
    assert_equal(914679880601515615685077935113, rand(-(2**100).to_f))

    srand(0)
    rnd = Random.new(0)
    assert_equal(997707939797331598305742933184, rand(2**100))
    assert_equal(997707939797331598305742933184, rnd.rand(2**100))
    assert_in_delta(0.602763376071644, rand((2**100).coerce(0).first),
                    0.000000000000001)
    assert_raise(ArgumentError) {rnd.rand((2**100).coerce(0).first)}

    srand(0)
    rnd = Random.new(0)
    assert_in_delta(0.548813503927325, rand(nil),
                    0.000000000000001)
    assert_in_delta(0.548813503927325, rnd.rand(),
                    0.000000000000001)
    srand(0)
    rnd = Random.new(0)
    o = Object.new
    def o.to_int; 100; end
    assert_equal(44, rand(o))
    assert_equal(44, rnd.rand(o))
    assert_equal(47, rand(o))
    assert_equal(47, rnd.rand(o))
    assert_equal(64, rand(o))
    assert_equal(64, rnd.rand(o))
  end

  def test_srand
    srand
    assert_kind_of(Integer, rand(2))
    assert_kind_of(Integer, Random.new.rand(2))

    srand(2**100)
    rnd = Random.new(2**100)
    %w(3258412053).each {|w|
      assert_equal(w.to_i, rand(0x100000000))
      assert_equal(w.to_i, rnd.rand(0x100000000))
    }
  end

  def test_shuffle
    srand(0)
    result = [*1..5].shuffle
    assert_equal([*1..5], result.sort)
    assert_equal(result, [*1..5].shuffle(random: Random.new(0)))
  end

  def test_big_seed
    assert_random_int(%w(2757555016), 0x100000000, 2**1000000-1)
  end

  def test_random_gc
    r = Random.new(0)
    %w(2357136044 2546248239 3071714933).each do |w|
      assert_equal(w.to_i, r.rand(0x100000000))
    end
    GC.start
    %w(3626093760 2588848963 3684848379).each do |w|
      assert_equal(w.to_i, r.rand(0x100000000))
    end
  end

  def test_random_type_error
    assert_raise(TypeError) { Random.new(Object.new) }
    assert_raise(TypeError) { Random.new(0).rand(Object.new) }
  end

  def test_random_argument_error
    r = Random.new(0)
    assert_raise(ArgumentError) { r.rand(0, 0) }
    assert_raise(ArgumentError, '[ruby-core:24677]') { r.rand(-1) }
    assert_raise(ArgumentError, '[ruby-core:24677]') { r.rand(-1.0) }
    assert_raise(ArgumentError, '[ruby-core:24677]') { r.rand(0) }
    assert_equal(0, r.rand(1), '[ruby-dev:39166]')
    assert_equal(0, r.rand(0...1), '[ruby-dev:39166]')
    assert_equal(0, r.rand(0..0), '[ruby-dev:39166]')
    assert_equal(0.0, r.rand(0.0..0.0), '[ruby-dev:39166]')
    assert_raise(ArgumentError, '[ruby-dev:39166]') { r.rand(0...0) }
    assert_raise(ArgumentError, '[ruby-dev:39166]') { r.rand(0..-1) }
    assert_raise(ArgumentError, '[ruby-dev:39166]') { r.rand(0.0...0.0) }
    assert_raise(ArgumentError, '[ruby-dev:39166]') { r.rand(0.0...-0.1) }
    bug3027 = '[ruby-core:29075]'
    assert_raise(ArgumentError, bug3027) { r.rand(nil) }
  end

  def test_random_seed
    assert_equal(0, Random.new(0).seed)
    assert_equal(0x100000000, Random.new(0x100000000).seed)
    assert_equal(2**100, Random.new(2**100).seed)
  end

  def test_random_dup
    r1 = Random.new(0)
    r2 = r1.dup
    %w(2357136044 2546248239 3071714933).each do |w|
      assert_equal(w.to_i, r1.rand(0x100000000))
    end
    %w(2357136044 2546248239 3071714933).each do |w|
      assert_equal(w.to_i, r2.rand(0x100000000))
    end
    r2 = r1.dup
    %w(3626093760 2588848963 3684848379).each do |w|
      assert_equal(w.to_i, r1.rand(0x100000000))
    end
    %w(3626093760 2588848963 3684848379).each do |w|
      assert_equal(w.to_i, r2.rand(0x100000000))
    end
  end

  def test_random_state
    state = <<END
3877134065023083674777481835852171977222677629000095857864323111193832400974413
4782302161934463784850675209112299537259006497924090422596764895633625964527441
6943943249411681406395713106007661119327771293929504639878577616749110507385924
0173026285378896836022134086386136835407107422834685854738117043791709411958489
3504364936306163473541948635570644161010981140452515307286926529085424765299100
1255453260115310687580777474046203049197643434654645011966794531914127596390825
0832232869378617194193100828000236737535657699356156021286278281306055217995213
8911536025132779573429499813926910299964681785069915877910855089314686097947757
2621451199734871158015842198110309034467412292693435515184023707918034746119728
8223459645048255809852819129671833854560563104716892857257229121211527031509280
2390605053896565646658122125171846129817536096211475312518457776328637574563312
8113489216547503743508184872149896518488714209752552442327273883060730945969461
6568672445225657265545983966820639165285082194907591432296265618266901318398982
0560425129536975583916120558652408261759226803976460322062347123360444839683204
9868507788028894111577023917218846128348302845774997500569465902983227180328307
3735301552935104196244116381766459468172162284042207680945316590536094294865648
5953156978630954893391701383648157037914019502853776972615500142898763385846315
8457790690531675205213829055442306187692107777193071680668153335688203945049935
3404449910419303330872435985327845889440458370416464132629866593538629877042969
7589948685901343135964343582727302330074331803900821801076139161904900333497836
6627028345784450211920229170280462474456504317367706849373957309797251052447898
8436235456995644876515032202483449807136139063937892187299239634252391529822163
9187055268750679730919937006195967184206072757082920250075756273182004964087790
3812024063897424219316687828337007888030994779068081666133751070479581394604974
6022215489604777611774245181115126041390161592199230774968475944753915533936834
4740049163514318351045644344358598159463605453475585370226041981040238023241538
4958436364776113598408428801867643946791659645708540669432995503575075657406359
8086928867900590554805639837071298576728564946552163206007997000988745940681607
4542883814997403673656291618517107133421335645430345871041730410669209035640945
5024601618318371192091626092482640364669969307766919645222516407626038616667754
5781148898846306894862390724358039251444333889446128074209417936830253204064223
3424784857908022314095011879203259864909560830176189727132432100010493659154644
8407326292884826469503093409465946018496358514999175268200846200025235441426140
7783386235191526371372655894290440356560751680752191224383460972099834655086068
9989413443881686756951804138910911737670495391762470293978321414964443502180391
4665982575919524372985773336921990352313629822677022891307943536442258282401255
5387646898976193134193506239982621725093291970351083631367582570375381334759004
1784150668048523676387894646666460369896619585113435743180899362844070393586212
5023920017185866399742380706352739465848708746963693663004068892056705603018655
8686663087894205699555906146534549176352859823832196938386172810274748624517052
8356758650653040545267425513047130342286119889879774951060662713807133125543465
5104086026298674827575216701372513525846650644773241437066782037334367982012148
7987782004646896468089089826267467005660035604553432197455616078731159778086155
9443250946037119223468305483694093795324036812927501783593256716590840500905291
2096608538205270323065573109227029887731553399324547696295234105140157179430410
4003109602564833086703863221058381556776789018351726488797845637981974580864082
1630093543020854542240690897858757985640869209737744458407777584279553258261599
0246922348101147034463235613998979344685018577901996218099622190722307356620796
5137485271371502385527388080824050288371607602101805675021790116223360483508538
8832149997794718410946818866375912486788005950091851067237358294899771385995876
7088239104394332452501033090159333224995108984871426750597513314521294001864578
2353528356752869732412552685554334966798888534847483030947310518891788722418172
6008607577773612004956373863580996793809969715725508939568919714424871639667201
7922255031431159347210833846575355772055570279673262115911154370983086189948124
4653677615895887099814174914248255026619941911735341818489822197472499295786997
7728418516719104857455960900092226749725407204388193002835497055305427730656889
1508308778869166073740855838213112709306743479676740893150000714099064468263284
1873435518542972182497755500300784177067568586395485329021157235696300013490087
2866571034916258390528533374944905429089028336079264760836949419754851422499614
5732326011260304142074554782259843903215064144396140106592193961703288125005023
5334375212799817540775536847622032852415253966587517800661605905489339306359573
2234947905196298436841723673626428243649931398749552780311877734063703985375067
1239508613417041942487245370152912391885566432830659640677893488723724763120121
4111855277511356759926232894062814360449757490961653026194107761340614059045172
1123363102660719217740126157997033682099769790976313166682432732518101889210276
9574144065390305904944821051736021310524344626348851573631697771556587859836330
6997324121866564283654784470215100159122764509197570402997911258816526554863326
9877535269005418736225944874608987238997316999444215865249840762640949599725696
0773083894168959823152054508672272612355108904098579447774398451678239199426513
3439507737424049578587487505080347686371029156845461151278198605267053408259090
3158676794894709281917034995611352710898103415304769654883981727681820369090169
9295163908214854813365413456264812190842699054830709079275249714169405719140093
1347572458245530016346604698682269779841803667099480215265926316505737171177810
9969036572310084022695109125200937135540995157279354438704321290061646592229860
0156566013602344870223183295508278359111174872740360473845615437106413256386849
2286259982118315248148847764929974917157683083659364623458927512616369119194574
2254080
END
    state = state.split.join.to_i
    r = Random.new(0)
    srand(0)
    assert_equal(state, r.instance_eval { state })
    assert_equal(state, Random.instance_eval { state })
    r.rand(0x100)
    assert_equal(state, r.instance_eval { state })
  end

  def test_random_left
    r = Random.new(0)
    assert_equal(1, r.instance_eval { left })
    r.rand(0x100)
    assert_equal(624, r.instance_eval { left })
    r.rand(0x100)
    assert_equal(623, r.instance_eval { left })
    srand(0)
    assert_equal(1, Random.instance_eval { left })
    rand(0x100)
    assert_equal(624, Random.instance_eval { left })
    rand(0x100)
    assert_equal(623, Random.instance_eval { left })
  end

  def test_random_bytes
    assert_random_bytes(Random.new(0))
  end

  def assert_random_bytes(r)
    assert_equal("", r.bytes(0))
    assert_equal("\xAC".force_encoding("ASCII-8BIT"), r.bytes(1))
    assert_equal("/\xAA\xC4\x97u\xA6\x16\xB7\xC0\xCC".force_encoding("ASCII-8BIT"),
                 r.bytes(10))
  end

  def test_random_range
    srand(0)
    r = Random.new(0)
    %w(9 5 8).each {|w|
      assert_equal(w.to_i, rand(5..9))
      assert_equal(w.to_i, r.rand(5..9))
    }
    %w(-237 731 383).each {|w|
      assert_equal(w.to_i, rand(-1000..1000))
      assert_equal(w.to_i, r.rand(-1000..1000))
    }
    %w(1267650600228229401496703205382
       1267650600228229401496703205384
       1267650600228229401496703205383).each do |w|
      assert_equal(w.to_i, rand(2**100+5..2**100+9))
      assert_equal(w.to_i, r.rand(2**100+5..2**100+9))
    end

    v = rand(3.1..4)
    assert_instance_of(Float, v, '[ruby-core:24679]')
    assert_include(3.1..4, v)

    v = r.rand(3.1..4)
    assert_instance_of(Float, v, '[ruby-core:24679]')
    assert_include(3.1..4, v)

    now = Time.now
    assert_equal(now, rand(now..now))
    assert_equal(now, r.rand(now..now))
  end

  def test_random_float
    r = Random.new(0)
    assert_in_delta(0.5488135039273248, r.rand, 0.0001)
    assert_in_delta(0.7151893663724195, r.rand, 0.0001)
    assert_in_delta(0.6027633760716439, r.rand, 0.0001)
    assert_in_delta(1.0897663659937937, r.rand(2.0), 0.0001)
    assert_in_delta(5.3704626067153264e+29, r.rand((2**100).to_f), 10**25)

    assert_raise(Errno::EDOM, Errno::ERANGE) { r.rand(1.0 / 0.0) }
    assert_raise(Errno::EDOM, Errno::ERANGE) { r.rand(0.0 / 0.0) }

    r = Random.new(0)
    assert_in_delta(1.5488135039273248, r.rand(1.0...2.0), 0.0001, '[ruby-core:24655]')
    assert_in_delta(1.7151893663724195, r.rand(1.0...2.0), 0.0001, '[ruby-core:24655]')
    assert_in_delta(7.027633760716439, r.rand(1.0...11.0), 0.0001, '[ruby-core:24655]')
    assert_in_delta(3.0897663659937937, r.rand(2.0...4.0), 0.0001, '[ruby-core:24655]')

    assert_nothing_raised {r.rand(-Float::MAX..Float::MAX)}
  end

  def test_random_equal
    r = Random.new(0)
    assert_equal(r, r)
    assert_equal(r, r.dup)
    r1 = r.dup
    r2 = r.dup
    r1.rand(0x100)
    assert_not_equal(r1, r2)
    r2.rand(0x100)
    assert_equal(r1, r2)
  end

  def test_fork_shuffle
    pid = fork do
      (1..10).to_a.shuffle
      raise 'default seed is not set' if srand == 0
    end
    _, st = Process.waitpid2(pid)
    assert_predicate(st, :success?, "#{st.inspect}")
  rescue NotImplementedError, ArgumentError
  end

  def assert_fork_status(n, mesg, &block)
    IO.pipe do |r, w|
      (1..n).map do
        p1 = fork {w.puts(block.call.to_s)}
        _, st = Process.waitpid2(p1)
        assert_send([st, :success?], mesg)
        r.gets.strip
      end
    end
  end

  def test_rand_reseed_on_fork
    GC.start
    bug5661 = '[ruby-core:41209]'

    assert_fork_status(1, bug5661) {Random.rand(4)}
    r1, r2 = *assert_fork_status(2, bug5661) {Random.rand}
    assert_not_equal(r1, r2, bug5661)

    assert_fork_status(1, bug5661) {rand(4)}
    r1, r2 = *assert_fork_status(2, bug5661) {rand}
    assert_not_equal(r1, r2, bug5661)

    stable = Random.new
    assert_fork_status(1, bug5661) {stable.rand(4)}
    r1, r2 = *assert_fork_status(2, bug5661) {stable.rand}
    assert_equal(r1, r2, bug5661)
  rescue NotImplementedError
  end

  def test_seed
    bug3104 = '[ruby-core:29292]'
    rand_1 = Random.new(-1).rand
    assert_not_equal(rand_1, Random.new((1 << 31) -1).rand, "#{bug3104} (2)")
    assert_not_equal(rand_1, Random.new((1 << 63) -1).rand, "#{bug3104} (2)")

    [-1, -2**10, -2**40].each {|n|
      b = (2**64).coerce(n)[0]
      r1 = Random.new(n).rand
      r2 = Random.new(b).rand
      assert_equal(r1, r2)
    }
  end

  def test_default
    r1 = Random::DEFAULT.dup
    r2 = Random::DEFAULT.dup
    3.times do
      x0 = rand
      x1 = r1.rand
      x2 = r2.rand
      assert_equal(x0, x1)
      assert_equal(x0, x2)
    end
  end

  def test_marshal
    bug3656 = '[ruby-core:31622]'
    assert_raise(TypeError, bug3656) {
      Random.new.__send__(:marshal_load, 0)
    }
  end

  def test_initialize_frozen
    r = Random.new(0)
    r.freeze
    assert_raise(RuntimeError, '[Bug #6540]') do
      r.__send__(:initialize, r)
    end
  end

  def test_marshal_load_frozen
    r = Random.new(0)
    d = r.__send__(:marshal_dump)
    r.freeze
    assert_raise(RuntimeError, '[Bug #6540]') do
      r.__send__(:marshal_load, d)
    end
  end

  def test_random_ulong_limited
    def (gen = Object.new).rand(*) 1 end
    assert_equal([2], (1..100).map {[1,2,3].sample(random: gen)}.uniq)

    def (gen = Object.new).rand(*) 100 end
    assert_raise_with_message(RangeError, /big 100\z/) {[1,2,3].sample(random: gen)}

    bug7903 = '[ruby-dev:47061] [Bug #7903]'
    def (gen = Object.new).rand(*) -1 end
    assert_raise_with_message(RangeError, /small -1\z/, bug7903) {[1,2,3].sample(random: gen)}

    bug7935 = '[ruby-core:52779] [Bug #7935]'
    class << (gen = Object.new)
      def rand(limit) @limit = limit; 0 end
      attr_reader :limit
    end
    [1, 2].sample(1, random: gen)
    assert_equal(2, gen.limit, bug7935)
  end

  def test_random_ulong_limited_no_rand
    c = Class.new do
      undef rand
      def bytes(n)
        "\0"*n
      end
    end
    gen = c.new.extend(Random::Formatter)
    assert_equal(1, [1, 2].sample(random: gen))
  end

  def test_default_seed
    assert_separately([], <<-End)
      seed = Random::DEFAULT::seed
      rand1 = Random::DEFAULT::rand
      rand2 = Random.new(seed).rand
      assert_equal(rand1, rand2)

      srand seed
      rand3 = rand
      assert_equal(rand1, rand3)
    End
  end
end
