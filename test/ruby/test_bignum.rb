# frozen_string_literal: false
require 'test/unit'
begin
  require '-test-/integer'
rescue LoadError
else

class TestBignum < Test::Unit::TestCase
  FIXNUM_MIN = RbConfig::LIMITS['FIXNUM_MIN']
  FIXNUM_MAX = RbConfig::LIMITS['FIXNUM_MAX']

  BIGNUM_MIN = FIXNUM_MAX + 1
  b = BIGNUM_MIN

  f = BIGNUM_MIN
  n = 0
  until f == 0
    f >>= 1
    n += 1
  end
  BIGNUM_MIN_BITS = n

  T_ZERO = 0.to_bignum
  T_ONE  = 1.to_bignum
  T_MONE = (-1).to_bignum
  T31  = (2**31).to_bignum   # 2147483648
  T31P = (T31 - 1).to_bignum # 2147483647
  T32  = (2**32).to_bignum   # 4294967296
  T32P = (T32 - 1).to_bignum # 4294967295
  T64  = (2**64).to_bignum   # 18446744073709551616
  T64P = (T64 - 1).to_bignum # 18446744073709551615
  T128  = (2**128).to_bignum
  T128P = (T128 - 1).to_bignum
  T1024  = (2**1024).to_bignum
  T1024P = (T1024 - 1).to_bignum

  def setup
    @verbose = $VERBOSE
    $VERBOSE = nil
    @fmax = Float::MAX.to_i
    @fmax2 = @fmax * 2
    @big = (1 << BIGNUM_MIN_BITS) - 1
  end

  def teardown
    $VERBOSE = @verbose
  end

  def fact(n)
    return 1 if n == 0
    f = 1
    while n>0
      f *= n
      n -= 1
    end
    return f
  end

  def test_prepare
    assert_bignum(@big)
    assert_bignum(T_ZERO)
    assert_bignum(T_ONE)
    assert_bignum(T_MONE)
    assert_bignum(T31)
    assert_bignum(T31P)
    assert_bignum(T32)
    assert_bignum(T32P)
    assert_bignum(T64)
    assert_bignum(T64P)
    assert_bignum(T1024)
    assert_bignum(T1024P)
  end

  def test_bignum
    $x = fact(40)
    assert_equal($x, $x)
    assert_equal($x, fact(40))
    assert_operator($x, :<, $x+2)
    assert_operator($x, :>, $x-2)
    assert_equal(815915283247897734345611269596115894272000000000, $x)
    assert_not_equal(815915283247897734345611269596115894272000000001, $x)
    assert_equal(815915283247897734345611269596115894272000000001, $x+1)
    assert_equal(335367096786357081410764800000, $x/fact(20))
    $x = -$x
    assert_equal(-815915283247897734345611269596115894272000000000, $x)

    b = 2*BIGNUM_MIN
    assert_equal(2-b, -(b-2))
    assert_equal(b - 5, (b-3)-2)

    for i in 1000..1014
      assert_equal(2 ** i, 1 << i)
    end

    n1 = 1 << 1000
    for i in 1000..1014
      assert_equal(n1, 1 << i)
      n1 *= 2
    end

    n2=n1
    for i in 1..10
      n1 = n1 / 2
      n2 = n2 >> 1
      assert_equal(n1, n2)
    end

    for i in 4000..4096
      n1 = 1 << i;
      assert_equal(n1-1, (n1**2-1) / (n1+1))
    end
  end

  def test_calc
    b = 10**80
    a = b * 9 + 7
    assert_equal(7, a.modulo(b))
    assert_equal(-b + 7, a.modulo(-b))
    assert_equal(b + -7, (-a).modulo(b))
    assert_equal(-7, (-a).modulo(-b))
    assert_equal(7, a.remainder(b))
    assert_equal(7, a.remainder(-b))
    assert_equal(-7, (-a).remainder(b))
    assert_equal(-7, (-a).remainder(-b))

    assert_equal(10000000000000000000100000000000000000000, 10**40+10**20)
    assert_equal(100000000000000000000, 10**40/10**20)

    a = 677330545177305025495135714080
    b = 14269972710765292560
    assert_equal(0, a % b)
    assert_equal(0, -a % b)
  end

  def shift_test(a)
    b = a / (2 ** 32)
    c = a >> 32
    assert_equal(b, c)

    b = a * (2 ** 32)
    c = a << 32
    assert_equal(b, c)
  end

  def test_shift
    shift_test(-4518325415524767873)
    shift_test(-0xfffffffffffffffff)
  end

  def test_to_s
    assert_equal("fvvvvvvvvvvvv" ,18446744073709551615.to_s(32), "[ruby-core:10686]")
    assert_equal("g000000000000" ,18446744073709551616.to_s(32), "[ruby-core:10686]")
    assert_equal("3w5e11264sgsf" ,18446744073709551615.to_s(36), "[ruby-core:10686]")
    assert_equal("3w5e11264sgsg" ,18446744073709551616.to_s(36), "[ruby-core:10686]")
    assert_equal("nd075ib45k86f" ,18446744073709551615.to_s(31), "[ruby-core:10686]")
    assert_equal("nd075ib45k86g" ,18446744073709551616.to_s(31), "[ruby-core:10686]")
    assert_equal("1777777777777777777777" ,18446744073709551615.to_s(8))
    assert_equal("-1777777777777777777777" ,-18446744073709551615.to_s(8))
    assert_match(/\A10{99}1\z/, (10**100+1).to_s)
    assert_match(/\A10{900}9{100}\z/, (10**1000+(10**100-1)).to_s)
  end

  def test_big_2comp
    assert_equal("-4294967296", (~T32P).to_s)
    assert_equal("..f00000000", "%x" % -T32)
  end

  def test_int2inum
    assert_equal([T31P], [T31P].pack("I").unpack("I"))
    assert_equal([T31P], [T31P].pack("i").unpack("i"))
  end

  def test_quad_pack
    assert_equal([    1], [    1].pack("q").unpack("q"))
    assert_equal([-   1], [-   1].pack("q").unpack("q"))
    assert_equal([ T31P], [ T31P].pack("q").unpack("q"))
    assert_equal([-T31P], [-T31P].pack("q").unpack("q"))
    assert_equal([ T64P], [ T64P].pack("Q").unpack("Q"))
    assert_equal([    0], [ T64 ].pack("Q").unpack("Q"))
  end

  def test_str_to_inum
    assert_equal(1, " +1".to_i)
    assert_equal(-1, " -1".to_i)
    assert_equal(0, "++1".to_i)
    assert_equal(73, "111".oct)
    assert_equal(273, "0x111".oct)
    assert_equal(7, "0b111".oct)
    assert_equal(73, "0o111".oct)
    assert_equal(111, "0d111".oct)
    assert_equal(73, "0111".oct)
    assert_equal(111, Integer("111"))
    assert_equal(13, "111".to_i(3))
    assert_raise(ArgumentError) { "111".to_i(37) }
    assert_equal(1333, "111".to_i(36))
    assert_equal(1057, "111".to_i(32))
    assert_equal(0, "00a".to_i)
    assert_equal(1, Integer("1 "))
    assert_raise(ArgumentError) { Integer("1_") }
    assert_raise(ArgumentError) { Integer("1__") }
    assert_raise(ArgumentError) { Integer("1_0 x") }
    assert_equal(T31P, "1111111111111111111111111111111".to_i(2))
    assert_equal(0_2, '0_2'.to_i)
    assert_equal(00_2, '00_2'.to_i)
    assert_equal(00_02, '00_02'.to_i)
  end

  def test_to_s2
    assert_raise(ArgumentError) { T31P.to_s(37) }
    assert_equal("9" * 32768, (10**32768-1).to_s)
    assert_raise(RangeError) { Process.wait(1, T64P) }
    assert_equal("0", T_ZERO.to_s)
    assert_equal("1", T_ONE.to_s)
  end

  def test_to_f
    assert_nothing_raised { T31P.to_f.to_i }
    assert_raise(FloatDomainError) { (1024**1024).to_f.to_i }
    assert_equal(1, (2**50000).to_f.infinite?)
    assert_equal(-1, (-(2**50000)).to_f.infinite?)
  end

  def test_cmp
    assert_operator(T31P, :>, 1)
    assert_operator(T31P, :<, 2147483648.0)
    assert_operator(T31P, :<, T64P)
    assert_operator(T64P, :>, T31P)
    assert_raise(ArgumentError) { T31P < "foo" }
    assert_operator(T64, :<, (1.0/0.0))
    assert_not_operator(T64, :>, (1.0/0.0))
  end

  def test_eq
    assert_not_equal(T31P, 1)
    assert_equal(T31P, 2147483647.0)
    assert_not_equal(T31P, "foo")
    assert_not_equal(2**77889, (1.0/0.0), '[ruby-core:31603]')
  end

  def test_eql
    assert_send([T31P, :eql?, T31P])
  end

  def test_convert
    assert_equal([255], [T_MONE].pack("C").unpack("C"))
    assert_equal([0], [T32].pack("C").unpack("C"))
    assert_raise(RangeError) { 0.to_s(T32) }
  end

  def test_sub
    assert_equal(-T31, T32 - (T32 + T31))
    x = 2**100
    assert_equal(1, (x+2) - (x+1))
    assert_equal(-1, (x+1) - (x+2))
    assert_equal(0, (2**100) - (2.0**100))
    o = Object.new
    def o.coerce(x); [x, 2**100+2]; end
    assert_equal(-1, (2**100+1) - o)
    assert_equal(-1, T_ONE - 2)
  end

  def test_plus
    assert_equal(T32.to_f, T32P + 1.0)
    assert_raise(TypeError) { T32 + "foo" }
    assert_equal(1267651809154049016125877911552, (2**100) + (2**80))
    assert_equal(1267651809154049016125877911552, (2**80) + (2**100))
    assert_equal(2**101, (2**100) + (2.0**100))
    o = Object.new
    def o.coerce(x); [x, 2**80]; end
    assert_equal(1267651809154049016125877911552, (2**100) + o)
  end

  def test_minus
    assert_equal(T32P.to_f, T32 - 1.0)
    assert_raise(TypeError) { T32 - "foo" }
  end

  def test_mul
    assert_equal(T32.to_f, T32 * 1.0)
    assert_raise(TypeError) { T32 * "foo" }
    o = Object.new
    def o.coerce(x); [x, 2**100]; end
    assert_equal(2**180, (2**80) * o)
  end

  def test_positive_p
    assert_predicate(T_ONE, :positive?)
    assert_not_predicate(T_MONE, :positive?)
    assert_not_predicate(T_ZERO, :positive?)
  end

  def test_negative_p
    assert_not_predicate(T_ONE, :negative?)
    assert_predicate(T_MONE, :negative?)
    assert_not_predicate(T_ZERO, :negative?)
  end

  def test_mul_balance
    assert_equal(3**7000, (3**5000) * (3**2000))
  end

  def test_mul_large_numbers
    a = %w[
      32580286268570032115047167942578356789222410206194227403993117616454027392
      62501901985861926098797067562795526004375784403965882943322008991129440928
      33855888840298794008677656280486901895499985197580043127115026675632969396
      55040226415022070581995493731570435346323030715226718346725312551631168110
      83966158581772380474470605428802018934282425947323171408377505151988776271
      85865548747366001752375899635539662017095652855537225416899242508164949615
      96848508410008685252121247181772953744297349638273854170932226446528911938
      03430429031094465344063914822790537339912760237589085026016396616506014081
      53557719631183538265614091691713138728177917059624255801026099255450058876
      97412698978242128457751836011774504753020608663272925708049430557191193188
      23212591809241860763625985763438355314593186083254640117460724730431447842
      15432124830037389073162094304199742919767272162759192882136828372588787906
      96027938532441670018954643423581446981760344524184231299785949158765352788
      38452309862972527623669323263424418781899966895996672291193305401609553502
      63893514163147729201340204483973131948541009975283778189609285614445485714
      63843850089417416331356938086609682943037801440660232801570877143192251897
      63026816485314923378023904237699794122181407920355722922555234540701118607
      37971417665315821995516986204709574657462370947443531049033704997194647442
      13711787319587466437795542850136751816475182349380345341647976135081955799
      56787050815348701001765730577514591032367920292271016649813170789854524395
      72571698998841196411826453893352760318867994518757872432266374568779920489
      55597104558927387008506485038236352630863481679853742412042588244086070827
      43705456833283086410967648483312972903432798923897357373793064381177468258
      69131640408147806442422254638590386673344704147156793990832671592488742473
      31524606724894164324227362735271650556732855509929890983919463699819116427
    ].join.to_i
    b = %w[
      31519454770031243652776765515030872050264386564379909299874378289835540661
      99756262835346828114038365624177182230027040172583473561802565238817167503
      85144159132462819032164726177606533272071955542237648482852154879445654746
      25061253606344846225905712926863168413666058602449408307586532461776530803
      56810626880722653177544008166119272373179841889454920521993413902672848145
      77974951972342194855267960390195830413354782136431833731467699250684103370
      98571305167189174270854698169136844578685346745340041520068176478277580590
      43810457765638903028049263788987034217272442328962400931269515791911786205
      15357047519615932249418012945178659435259428163356223753159488306813844040
      93609959555018799309373542926110109744437994067754004273450659607204900586
      28878103661124568217617766580438460505513654179249613168352070584906185237
      34829991855182473813233425492094534396541544295119674419522772382981982574
      64708442087451070125274285088681225122475041996116377707892328889948526913
      82239084041628877737628853240361038273348062246951097300286513836140601495
      63604611754185656404194406869925540477185577643853560887894081047256701731
      66884554460428760857958761948461476977864005799494946578017758268987123749
      85937011490156431231903167442071541493304390639100774497107347884381581049
      85451663323551635322518839895028929788021096587229364219084708576998525298
      39594168681411529110089531428721005176467479027585291807482375043729783455
      35827667428080449919778142400266842990117940984804919512360370451936835708
      76338722049621773169385978521438867493162717866679193103745711403152099047
      27294943901673885707639094215339506973982546487889199083181789561917985023
      82368442718514694400160954955539704757794969665555505203532944598698824542
      00599461848630034847211204029842422678421808487300084850702007663003230882
      16645745324467830796203354080471008809087072562876681588151822072260738003
    ].join.to_i
    c = %w[
      10269128594368631269792194698469828812223242061960065022209211719149714886
      03494742299892841188636314745174778237781513956755034582435818316155459882
      71422025990633195596790290038198841087091600598192959108790192789550336119
      13849937951116346796903163312950010689963716629093190601532313463306463573
      64436438673379454947908896258675634478867189655764364639888427350090856831
      84369949421175534994092429682748078316130135651006102162888937624830856951
      64818150356583421988135211585954838926347035741143424980258821170351244310
      33072045488402539147707418016613224788469923473310249137422855065567940804
      75231970365923936034328561426062696074717204901606475826224235014948198414
      19979210494282212322919438926816203585575357874850252052656098969732107129
      30639419804565653489687198910271702181183420960744232756057631336661646896
      48734093497394719644969417287962767186599484579769717220518657324467736902
      16947995288312851432262922140679347615046098863974141226499783975470926697
      95970415188661518504275964397022973192968233221707696639386238428211541334
      69925631385166494600401675904803418143232703594169525858261988389529181035
      06048776134746377586210180203524132714354779486439559392942733781343640971
      02430607931736785273011780813863748280091795277451796799961887248262211653
      38966967509803488282644299584920109534552889962877144862747797551711984992
      00726518175235286668236031649728858774545087668286506201943248842967749907
      05345423019480534625965140632428736051632750698608916592720742728646191514
      86268964807395494825321744802493138032936406889713953832376411900451422777
      06372983421062172556566901346288286168790235741528630664513209619789835729
      36999522461733403414326366959273556098219489572448083984779946889707480205
      42459898495081687425132939473146331452400120169525968892769310016015870148
      66821361032541586130017904207971120217385522074967066199941112154460026348
      07223950375610474071278649031647998546085807777970592429037128484222394216
      33776560239741740193444702279919018283324070210090106960567819910943036248
      16660475627526085805165023447934326510232828674828006752369603151390527384
      16810180735871644266726954590262010744712519045524839388305761859432443670
      05188791334908140831469790180096209292338569623252372975043915954675335333
      66614002146554533771788633057869340167604765688639181655208751680821446276
      75871494160208888666798836473728725968253820774671626436794492530356258709
      62318715778035246655925307167306434486713879511272648637608703497794724929
      54912261106702913491290913962825303534484477936036071463820553314826894581
      36951927032835690160443252405644718368516656317176848748544135126122940034
      68454782581240953957381976073459570718038035358630417744490242611126043987
      89191812971310096496208294948623403471433467614886863238916702384858514703
      24327715474804343531844042107910755966152655912676456945146277848606406879
      49724219295823540160221752189725460676360350860849986313532861445465771187
      86822806696323658053947125253562001971534265078959827450518368635828010637
      91977444206363529864361796188661941906329947840521598310396004328950804758
      79728679236044038853668859284513594307352133390781441610395116807369310560
      35193762565748328526426224069629084264376146174383444988110993194030351064
      29660536743256949099972314033972121470913480844652490838985461134989129492
      75577567064571716731774820127381261057956083604361635892088585967074514802
      51958582645785905276289980534832170529946494815794770854644518463332458915
      77572397432680871220602513555535017751714443325264019171753694163676670792
      04353584782364068773777058727187323211012094819929720407636607815292764459
      21851731257845562153822058534043916834839514338448582518847879059020959697
      90538105704766415685100946308842788321400392381169436435078204622400475281
    ].join.to_i
    assert_equal(c, a*b, '[ruby-core:48552]')
  end

  def test_divrem
    assert_equal(0, T32 / T64)
  end

  def test_divide
    bug5490 = '[ruby-core:40429]'
    assert_raise(ZeroDivisionError, bug5490) {T1024./(0)}
    assert_equal(Float::INFINITY, T1024./(0.0), bug5490)
  end

  def test_div
    assert_equal(T32.to_f, T32 / 1.0)
    assert_raise(TypeError) { T32 / "foo" }
    assert_equal(0x20000000, 0x40000001.div(2.0), "[ruby-dev:34553]")
    bug5490 = '[ruby-core:40429]'
    assert_raise(ZeroDivisionError, bug5490) {T1024.div(0)}
    assert_raise(ZeroDivisionError, bug5490) {T1024.div(0.0)}
  end

  def test_idiv
    assert_equal(715827882, 1073741824.div(Rational(3,2)), ' [ruby-dev:34066]')
  end

  def test_modulo
    assert_raise(TypeError) { T32 % "foo" }
  end

  def test_remainder
    assert_equal(0, T32.remainder(1))
    assert_raise(TypeError) { T32.remainder("foo") }
  end

  def test_divmod
    assert_equal([T32, 0], T32.divmod(1))
    assert_equal([2, 0], T32.divmod(T31))
    assert_raise(TypeError) { T32.divmod("foo") }
  end

  def test_quo
    assert_kind_of(Float, T32.quo(1.0))

    assert_equal(T32.to_f, T32.quo(1))
    assert_equal(T32.to_f, T32.quo(1.0))
    assert_equal(T32.to_f, T32.quo(T_ONE))

    assert_raise(TypeError) { T32.quo("foo") }

    assert_equal(1024**1024, (1024**1024).quo(1))
    assert_equal(Float::INFINITY, (1024**1024).quo(1.0))
    assert_equal(1024**1024*2, (1024**1024*2).quo(1))
    inf = 1 / 0.0; nan = inf / inf

    assert_send([(1024**1024*2).quo(nan), :nan?])
  end

  def test_pow
    assert_equal(1.0, T32 ** 0.0)
    assert_equal(1.0 / T32, T32 ** -1)
    assert_equal(1, (T32 ** T32).infinite?)
    assert_equal(1, (T32 ** (2**30-1)).infinite?)

    ### rational changes the behavior of Bignum#**
    #assert_raise(TypeError) { T32**"foo" }
    assert_raise(TypeError, ArgumentError) { T32**"foo" }

    feature3429 = '[ruby-core:30735]'
    assert_kind_of(Integer, (2 ** 7830457), feature3429)
  end

  def test_and
    assert_equal(0, T32 & 1)
    assert_equal(-T32, (-T32) & (-T31))
    assert_equal(0, T32 & T64)
  end

  def test_or
    assert_equal(T32 + 1, T32 | 1)
    assert_equal(T32 + T31, T32 | T31)
    assert_equal(-T31, (-T32) | (-T31))
    assert_equal(T64 + T32, T32 | T64)
    assert_equal(FIXNUM_MAX, T_ZERO | FIXNUM_MAX)
  end

  def test_xor
    assert_equal(T32 + 1, T32 ^ 1)
    assert_equal(T32 + T31, T32 ^ T31)
    assert_equal(T31, (-T32) ^ (-T31))
    assert_equal(T64 + T32, T32 ^ T64)
  end

  class DummyNumeric < Numeric
    def to_int
      1
    end
  end

  def test_and_with_float
    assert_raise(TypeError) { T1024 & 1.5 }
  end

  def test_and_with_rational
    assert_raise(TypeError, "#1792") { T1024 & Rational(3, 2) }
  end

  def test_and_with_nonintegral_numeric
    assert_raise(TypeError, "#1792") { T1024 & DummyNumeric.new }
  end

  def test_or_with_float
    assert_raise(TypeError) { T1024 | 1.5 }
  end

  def test_or_with_rational
    assert_raise(TypeError, "#1792") { T1024 | Rational(3, 2) }
  end

  def test_or_with_nonintegral_numeric
    assert_raise(TypeError, "#1792") { T1024 | DummyNumeric.new }
  end

  def test_xor_with_float
    assert_raise(TypeError) { T1024 ^ 1.5 }
  end

  def test_xor_with_rational
    assert_raise(TypeError, "#1792") { T1024 ^ Rational(3, 2) }
  end

  def test_xor_with_nonintegral_numeric
    assert_raise(TypeError, "#1792") { T1024 ^ DummyNumeric.new }
  end

  def test_shift2
    b = BIGNUM_MIN_BITS
    n = BIGNUM_MIN << 1
    assert_equal(2**(b+1), n <<  1)
    assert_equal(2**(b-1), n << -1)
    assert_equal(2**(b+1), n <<  1.0)
    assert_equal(2**(b-1), n << -1.0)
    assert_equal(2**(b+1), n << T_ONE)
    assert_equal(2**(b-1), n << T_MONE)
    assert_equal(2**(b-1), n >>  1)
    assert_equal(2**(b+1), n >> -1)
    assert_equal(2**(b-1), n >>  1.0)
    assert_equal(2**(b+1), n >> -1.0)
    assert_equal(2**(b-1), n >> T_ONE)
    assert_equal(2**(b+1), n >> T_MONE)
    assert_equal( 0,  n >> n)
    assert_equal(-1, -n >> n)
    assert_equal( 0,  n >> (b*4))
    assert_equal(-1, -n >> (b*4))
    assert_equal( 0,  (n/2) >> b)
    assert_equal(-1, -(n/2) >> b)
  end

  def test_shift_bigshift
    big = 2**300
    assert_equal(2**65538 / (2**65537), 2**65538 >> big.coerce(65537).first)
  end

  def test_aref
    assert_equal(0, BIGNUM_MIN[0])
    assert_equal(0, BIGNUM_MIN[BIGNUM_MIN])
    assert_equal(0, BIGNUM_MIN[-BIGNUM_MIN])
    assert_equal(0, BIGNUM_MIN[T_ZERO])
    assert_equal(0, (-(BIGNUM_MIN*BIGNUM_MIN))[0])
    assert_equal(1, (-2**(BIGNUM_MIN_BITS*4))[BIGNUM_MIN_BITS*4])
  end

  def test_hash
    assert_nothing_raised { T31P.hash }
  end

  def test_coerce
    assert_equal([T64P, T31P], T31P.coerce(T64P))
    assert_raise(TypeError) { T31P.coerce(nil) }
    obj = eval("class C\u{1f5ff}; self; end").new
    assert_raise_with_message(TypeError, /C\u{1f5ff}/) { T31P.coerce(obj) }
  end

  def test_abs
    assert_equal(T31P, (-T31P).abs)
  end

  def test_size
    assert_kind_of(Integer, T31P.size)
  end

  def test_odd
    assert_equal(true, (BIGNUM_MIN+1).odd?)
    assert_equal(false, BIGNUM_MIN.odd?)
  end

  def test_even
    assert_equal(false, (BIGNUM_MIN+1).even?)
    assert_equal(true, BIGNUM_MIN.even?)
  end

  def test_interrupt_during_to_s
    if defined?(Integer::GMP_VERSION)
      return # GMP doesn't support interrupt during an operation.
    end
    time = Time.now
    start_flag = false
    end_flag = false
    num = (65536 ** 65536)
    q = Queue.new
    thread = Thread.new do
      assert_raise(RuntimeError) {
        q << true
        num.to_s
        end_flag = true
      }
    end
    q.pop # sync
    thread.raise
    thread.join
    time = Time.now - time
    skip "too fast cpu" if end_flag
    assert_operator(time, :<, 10)
  end

  def test_interrupt_during_bigdivrem
    if defined?(Integer::GMP_VERSION)
      return # GMP doesn't support interrupt during an operation.
    end
    return unless Process.respond_to?(:kill)
    begin
      trace = []
      oldtrap = Signal.trap(:INT) {|sig| trace << :int }
      a = 456 ** 100
      b = 123 ** 100
      c = nil
      100.times do |n|
        a **= 3
        b **= 3
        trace.clear
        th = Thread.new do
          sleep 0.1; Process.kill :INT, $$
          sleep 0.1; Process.kill :INT, $$
        end
        c = a / b
        trace << :end
        th.join
        if trace == [:int, :int, :end]
          assert_equal(a / b, c)
          return
        end
      end
      skip "cannot create suitable test case"
    ensure
      Signal.trap(:INT, oldtrap) if oldtrap
    end
  end

  def test_too_big_to_s
    if (big = 2**31-1).fixnum?
      return
    end
    assert_raise_with_message(RangeError, /too big to convert/) {(1 << big).to_s}
  end

  def test_fix_fdiv
    assert_not_equal(0, 1.fdiv(@fmax2))
    assert_in_delta(0.5, 1.fdiv(@fmax2) * @fmax, 0.01)
  end

  def test_big_fdiv
    assert_equal(1, @big.fdiv(@big))
    assert_not_equal(0, @big.fdiv(@fmax2))
    assert_not_equal(0, @fmax2.fdiv(@big))
    assert_not_equal(0, @fmax2.fdiv(@fmax2))
    assert_in_delta(0.5, @fmax.fdiv(@fmax2), 0.01)
    assert_in_delta(1.0, @fmax2.fdiv(@fmax2), 0.01)
  end

  def test_float_fdiv
    b = 1E+300.to_i
    assert_equal(b, (b ** 2).fdiv(b))
    assert_send([@big.fdiv(0.0 / 0.0), :nan?])
    assert_in_delta(1E+300, (10**500).fdiv(1E+200), 1E+285)
  end

  def test_obj_fdiv
    o = Object.new
    def o.coerce(x); [x, 2**100]; end
    assert_equal((2**200).to_f, (2**300).fdiv(o))
    o = Object.new
    def o.coerce(x); [self, x]; end
    def o.fdiv(x); 1; end
    assert_equal(1.0, (2**300).fdiv(o))
  end

  def test_singleton_method
    # this test assumes 32bit/64bit platform
    assert_raise(TypeError) { a = 1 << 64; def a.foo; end }
  end

  def test_frozen
    assert_equal(true, (2**100).frozen?)
  end

  def test_bitwise_and_with_integer_mimic_object
    def (obj = Object.new).to_int
      10
    end
    assert_raise(TypeError, '[ruby-core:39491]') { T1024 & obj }

    def obj.coerce(other)
      [other, 10]
    end
    assert_equal(T1024 & 10, T1024 & obj)
  end

  def test_bitwise_or_with_integer_mimic_object
    def (obj = Object.new).to_int
      10
    end
    assert_raise(TypeError, '[ruby-core:39491]') { T1024 | obj }

    def obj.coerce(other)
      [other, 10]
    end
    assert_equal(T1024 | 10, T1024 | obj)
  end

  def test_bitwise_xor_with_integer_mimic_object
    def (obj = Object.new).to_int
      10
    end
    assert_raise(TypeError, '[ruby-core:39491]') { T1024 ^ obj }

    def obj.coerce(other)
      [other, 10]
    end
    assert_equal(T1024 ^ 10, T1024 ^ obj)
  end

  def test_digits
    assert_equal([90, 78, 56, 34, 12], 1234567890.to_bignum.digits(100))
    assert_equal([7215, 2413, 6242], T1024P.digits(10_000).first(3))
    assert_equal([11], 11.digits(T1024P))
    assert_equal([T1024P - 1, 1], (T1024P + T1024P - 1).digits(T1024P))
  end

  def test_digits_for_negative_numbers
    assert_raise(Math::DomainError) { -11.digits(T1024P) }
    assert_raise(Math::DomainError) { (-T1024P).digits }
    assert_raise(Math::DomainError) { (-T1024P).digits(T1024P) }
  end

  def test_digits_for_invalid_base_numbers
    assert_raise(ArgumentError) { T1024P.to_bignum.digits(0) }
    assert_raise(ArgumentError) { T1024P.to_bignum.digits(-1) }
    assert_raise(ArgumentError) { T1024P.to_bignum.digits(0.to_bignum) }
    assert_raise(ArgumentError) { T1024P.to_bignum.digits(1.to_bignum) }
    assert_raise(ArgumentError) { T1024P.to_bignum.digits(-T1024P) }
    assert_raise(ArgumentError) { 10.digits(0.to_bignum) }
    assert_raise(ArgumentError) { 10.digits(1.to_bignum) }
  end

  def test_digits_for_non_integral_base_numbers
    assert_equal([11], 11.digits(T128P.to_r))
    assert_equal([11], 11.digits(T128P.to_f))

    t1024p_digits_in_t32 = [T32P]*32
    assert_equal(t1024p_digits_in_t32, T1024P.digits(T32.to_r))
    assert_equal(t1024p_digits_in_t32, T1024P.digits(T32.to_f))

    assert_raise(RangeError) { T128P.digits(10+1i) }
  end

  def test_digits_for_non_numeric_base_argument
    assert_raise(TypeError) { T1024P.digits("10") }
    assert_raise(TypeError) { T1024P.digits("a") }
  end

  def test_finite_p
    assert_predicate(T1024P, :finite?)
    assert_predicate(-T1024P, :finite?)
  end

  def test_infinite_p
    assert_nil(T1024P.infinite?)
    assert_nil((-T1024P).infinite?)
  end
end
end
