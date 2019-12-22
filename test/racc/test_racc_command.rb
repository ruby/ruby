require File.expand_path(File.join(File.dirname(__FILE__), 'helper'))

module Racc
  class TestRaccCommand < TestCase
    def test_syntax_y
      assert_compile 'syntax.y', '-v'
      assert_debugfile 'syntax.y', [0,0,0,0,0]
    end

    def test_percent_y
      assert_compile 'percent.y'
      assert_debugfile 'percent.y', []
      assert_exec 'percent.y'
    end

    def test_scan_y
      assert_compile 'scan.y'
      assert_debugfile 'scan.y', []
      assert_exec 'scan.y'
    end

    def test_newsyn_y
      assert_compile 'newsyn.y'
      assert_debugfile 'newsyn.y', []
    end

    def test_normal_y
      assert_compile 'normal.y'
      assert_debugfile 'normal.y', []

      assert_compile 'normal.y', '-vg'
      assert_debugfile 'normal.y', []
    end

    def test_chk_y
      assert_compile 'chk.y', '-vg'
      assert_debugfile 'chk.y', []
      assert_exec 'chk.y'

      assert_compile 'chk.y', '--line-convert-all'
      assert_debugfile 'chk.y', []
      assert_exec 'chk.y'
    end

    def test_echk_y
      assert_compile 'echk.y', '-E'
      assert_debugfile 'echk.y', []
      assert_exec 'echk.y'
    end

    def test_err_y
      assert_compile 'err.y'
      assert_debugfile 'err.y', []
      assert_exec 'err.y'
    end

    def test_mailp_y
      assert_compile 'mailp.y'
      assert_debugfile 'mailp.y', []
    end

    def test_conf_y
      assert_compile 'conf.y', '-v'
      assert_debugfile 'conf.y', [4,1,1,2]
    end

    def test_rrconf_y
      assert_compile 'rrconf.y'
      assert_debugfile 'rrconf.y', [1,1,0,0]
    end

    def test_useless_y
      assert_compile 'useless.y'
      assert_debugfile 'useless.y', [0,0,1,2]
    end

    def test_opt_y
      assert_compile 'opt.y'
      assert_debugfile 'opt.y', []
      assert_exec 'opt.y'
    end

    def test_yyerr_y
      assert_compile 'yyerr.y'
      assert_debugfile 'yyerr.y', []
      assert_exec 'yyerr.y'
    end

    def test_recv_y
      assert_compile 'recv.y'
      assert_debugfile 'recv.y', [5,10,1,4]
    end

    def test_ichk_y
      assert_compile 'ichk.y'
      assert_debugfile 'ichk.y', []
      assert_exec 'ichk.y'
    end

    def test_intp_y
      assert_compile 'intp.y'
      assert_debugfile 'intp.y', []
      assert_exec 'intp.y'
    end

    def test_expect_y
      assert_compile 'expect.y'
      assert_debugfile 'expect.y', [1,0,0,0,1]
    end

    def test_nullbug1_y
      assert_compile 'nullbug1.y'
      assert_debugfile 'nullbug1.y', [0,0,0,0]
    end

    def test_nullbug2_y
      assert_compile 'nullbug2.y'
      assert_debugfile 'nullbug2.y', [0,0,0,0]
    end

    def test_firstline_y
      assert_compile 'firstline.y'
      assert_debugfile 'firstline.y', []
    end

    def test_nonass_y
      assert_compile 'nonass.y'
      assert_debugfile 'nonass.y', []
      assert_exec 'nonass.y'
    end

    def test_digraph_y
      assert_compile 'digraph.y'
      assert_debugfile 'digraph.y', []
      assert_exec 'digraph.y'
    end

    def test_noend_y
      assert_compile 'noend.y'
      assert_debugfile 'noend.y', []
    end

    def test_norule_y
      assert_raise(Test::Unit::AssertionFailedError) {
        assert_compile 'norule.y'
      }
    end

    def test_unterm_y
      assert_raise(Test::Unit::AssertionFailedError) {
        assert_compile 'unterm.y'
      }
    end

    # Regression test for a problem where error recovery at EOF would cause
    # a Racc-generated parser to go into an infinite loop (on some grammars)
    def test_error_recovery_y
      assert_compile 'error_recovery.y'
      Timeout.timeout(10) do
        assert_exec 'error_recovery.y'
      end
    end

    # .y files from `parser` gem

    def test_ruby18
      assert_compile 'ruby18.y', [], timeout: 60
      assert_debugfile 'ruby18.y', []
      assert_output_unchanged 'ruby18.y'
    end

    def test_ruby22
      assert_compile 'ruby22.y', [], timeout: 60
      assert_debugfile 'ruby22.y', []
      assert_output_unchanged 'ruby22.y'
    end

    # .y file from csspool gem

    def test_csspool
      assert_compile 'csspool.y'
      assert_debugfile 'csspool.y', [5, 3]
      assert_output_unchanged 'csspool.y'
    end

    # .y file from opal gem

    def test_opal
      assert_compile 'opal.y', [], timeout: 60
      assert_debugfile 'opal.y', []
      assert_output_unchanged 'opal.y'
    end

    # .y file from journey gem

    def test_journey
      assert_compile 'journey.y'
      assert_debugfile 'journey.y', []
      assert_output_unchanged 'journey.y'
    end

    # .y file from nokogiri gem

    def test_nokogiri_css
      assert_compile 'nokogiri-css.y'
      assert_debugfile 'nokogiri-css.y', [0, 1]
      assert_output_unchanged 'nokogiri-css.y'
    end

    # .y file from edtf-ruby gem

    def test_edtf
      assert_compile 'edtf.y'
      assert_debugfile 'edtf.y', [0, 0, 0, 0, 0]
      assert_output_unchanged 'edtf.y'
    end

    # .y file from namae gem

    def test_namae
      assert_compile 'namae.y'
      assert_debugfile 'namae.y', [0, 0, 0, 0, 0]
      assert_output_unchanged 'namae.y'
    end

    # .y file from liquor gem

    def test_liquor
      assert_compile 'liquor.y'
      assert_debugfile 'liquor.y', [0, 0, 0, 0, 15]
      assert_output_unchanged 'liquor.y'
    end

    # .y file from nasl gem

    def test_nasl
      assert_compile 'nasl.y'
      assert_debugfile 'nasl.y', [0, 0, 0, 0, 1]
      assert_output_unchanged 'nasl.y'
    end

    # .y file from riml gem

    def test_riml
      assert_compile 'riml.y'
      assert_debugfile 'riml.y', [289, 0, 0, 0]
      assert_output_unchanged 'riml.y'
    end

    # .y file from ruby-php-serialization gem

    def test_php_serialization
      assert_compile 'php_serialization.y'
      assert_debugfile 'php_serialization.y', [0, 0, 0, 0]
      assert_output_unchanged 'php_serialization.y'
    end

    # .y file from huia language implementation

    def test_huia
      assert_compile 'huia.y'
      assert_debugfile 'huia.y', [285, 0, 0, 0]
      assert_output_unchanged 'huia.y'
    end

    # .y file from cast gem

    def test_cast
      assert_compile 'cast.y'
      assert_debugfile 'cast.y', [0, 0, 0, 0, 1]
      assert_output_unchanged 'cast.y'
    end

    # .y file from cadenza gem

    def test_cadenza
      assert_compile 'cadenza.y'
      assert_debugfile 'cadenza.y', [0, 0, 0, 0, 37]
      assert_output_unchanged 'cadenza.y'
    end

    # .y file from mediacloth gem

    def test_mediacloth
      assert_compile 'mediacloth.y'
      assert_debugfile 'mediacloth.y', [0, 0, 0, 0]
      assert_output_unchanged 'mediacloth.y'
    end

    # .y file from twowaysql gem

    def test_twowaysql
      assert_compile 'twowaysql.y'
      assert_debugfile 'twowaysql.y', [4, 0, 0, 0]
      assert_output_unchanged 'twowaysql.y'
    end

    # .y file from machete gem

    def test_machete
      assert_compile 'machete.y'
      assert_debugfile 'machete.y', [0, 0, 0, 0]
      assert_output_unchanged 'machete.y'
    end

    # .y file from mof gem

    def test_mof
      assert_compile 'mof.y'
      assert_debugfile 'mof.y', [7, 4, 0, 0]
      assert_output_unchanged 'mof.y'
    end

    # .y file from tp_plus gem

    def test_tp_plus
      assert_compile 'tp_plus.y'
      assert_debugfile 'tp_plus.y', [21, 0, 0, 0]
      assert_output_unchanged 'tp_plus.y'
    end
  end
end
