# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/aozora/tally"
require_relative "../lib/aozora/axes"
require_relative "../lib/aozora/notation"

class TestAxes < Minitest::Test
  A = Aozora::Axes
  T = Aozora::Tally
  N = Aozora::Notation

  def counts(plain: {}, rubied: {}, duty: {})
    T::Counts.new(Hash.new(0).merge(plain), Hash.new(0).merge(rubied), Hash.new(0).merge(duty))
  end

  # ── O-03 循環の禁止 ───────────────────────────────────────
  def test_frequency_ignores_whether_ruby_was_applied
    # 同じ出現分布を、ルビの有無だけ入れ替えて渡す。頻度表は一致しなければならない。
    # 一致しなければ「難読度をルビ分布から作っている」ことになり、G-05 で失格。
    a = counts(plain: { "山" => 10, "麒" => 1 })
    b = counts(rubied: { "山" => 10 }, duty: { "麒" => 1 })
    assert_equal A.frequency(a), A.frequency(b)
  end

  def test_frequency_of_stripped_text_equals_frequency_of_ruby_text
    # 本文からルビを剥がしても頻度表は変わらない(O-03 の実文による検算)。
    src = "吾輩《わがはい》は猫である。麒麟《きりん》も猫も獣である"
    with = T.count(N.parse(src))
    without = T.count(N.parse(N.parse(src).map { |n|
      n.is_a?(N::Ruby) ? N::Text.new(n.base) : n
    }.then { |ns| N.rebuild(ns) }))
    assert_equal A.frequency(with), A.frequency(without)
  end

  # ── O-04 作家一人抜きが実際に効いている ───────────────────
  def test_leave_one_out_removes_the_authors_own_usage
    global = { "山" => 100, "麒" => 30 }
    own    = { "麒" => 28 }   # 麒 の大半はこの作家が使っている
    loo = A.leave_one_out(global, own)
    assert_equal 100, loo["山"]
    assert_equal 2, loo["麒"], "自分の使用分が引かれていない"
    refute_equal global, loo, "一人抜きが恒等写像になっている"
  end

  def test_leave_one_out_can_make_a_kanji_disappear
    # その作家しか使っていない字は、抜いた表から消える(＝最難読として扱われる)。
    assert_empty A.leave_one_out({ "麒" => 5 }, { "麒" => 5 })
  end

  def test_leave_one_out_changes_which_band_a_kanji_falls_in
    # 一人抜きが帯の割り当てを実際に動かすことを見る。動かないなら O-04 は無意味。
    global = { "山" => 60, "川" => 30, "麒" => 40 }
    own    = { "麒" => 39 }
    _, hard_all = A.bands(global)
    _, hard_loo = A.bands(A.leave_one_out(global, own))
    refute_equal hard_all, hard_loo, "一人抜きで帯が変わらない"
    assert_includes hard_loo, "麒"
  end

  # ── O-02 二軸の母集団が互いに素 ───────────────────────────
  def test_bands_are_disjoint
    freq = (1..300).to_h { |i| [i.chr(Encoding::UTF_8), 301 - i] }
    easy, hard = A.bands(freq)
    assert_empty easy & hard, "易読帯と難読帯が重なっている"
    refute_empty easy
    refute_empty hard
  end

  def test_bands_leave_a_buffer_between_them
    # 緩衝帯(75〜95%)があること。境界が接していると、頻度の僅差で帯が入れ替わる。
    freq = (1..300).to_h { |i| [i.chr(Encoding::UTF_8), 301 - i] }
    easy, hard = A.bands(freq)
    assert_operator easy.length + hard.length, :<, freq.length, "緩衝帯が消えている"
  end

  # ── F-05 義務ルビは両軸から外す ───────────────────────────
  def test_duty_ruby_is_excluded_from_both_numerator_and_denominator
    hard = Set["麒"]
    # 麒 が 10 回出て、うち 10 回すべて義務ルビ。分母が 0 なので測定不能(nil)。
    r = A.measure(counts(duty: { "麒" => 10 }), Set[], hard)
    assert_nil r.kindness, "義務ルビだけの字で優しさが算出されている"
    assert_equal 0, r.hard_n
  end

  def test_duty_ruby_does_not_dilute_the_rate
    hard = Set["麒"]
    # ルビ有 3 / 無 1 / 義務 96。義務を分母に入れれば 3%、外せば 75%。
    r = A.measure(counts(plain: { "麒" => 1 }, rubied: { "麒" => 3 }, duty: { "麒" => 96 }), Set[], hard)
    assert_in_delta 75.0, r.kindness, 0.001
  end

  # ── F-06 二軸の向き ───────────────────────────────────────
  def test_kindness_is_high_when_hard_kanji_get_ruby
    r = A.measure(counts(rubied: { "麒" => 9 }, plain: { "麒" => 1 }), Set[], Set["麒"])
    assert_in_delta 90.0, r.kindness, 0.001
  end

  def test_trust_is_high_when_easy_kanji_are_left_alone
    # 易読帯にルビを振らない = 読者を信用している。
    r = A.measure(counts(plain: { "山" => 99 }, rubied: { "山" => 1 }), Set["山"], Set[])
    assert_in_delta 99.0, r.trust, 0.001
  end

  def test_the_two_axes_move_independently
    # 同じ「総ルビ密度」でも、どちらの帯に振ったかで二軸は逆に振れる。
    # これが分離できなければ二軸にする意味がない(SPEC 1 の主張)。
    easy = Set["山"]
    hard = Set["麒"]
    guide = counts(plain: { "山" => 100, "麒" => 50 }, rubied: { "麒" => 50 })   # 難所だけ振る
    fussy = counts(plain: { "麒" => 100 }, rubied: { "山" => 50 }, )              # 易所だけ振る
    g = A.measure(guide, easy, hard)
    f = A.measure(fussy, easy, hard)
    assert_operator g.kindness, :>, f.kindness || 0
    assert_operator g.trust, :>, f.trust
  end

  # ── G-04 相関 ─────────────────────────────────────────────
  def test_correlation_detects_a_straight_line
    assert_in_delta 1.0, A.correlation([1.0, 2, 3, 4], [2.0, 4, 6, 8]), 1e-9
    assert_in_delta(-1.0, A.correlation([1.0, 2, 3, 4], [8.0, 6, 4, 2]), 1e-9)
  end
end
