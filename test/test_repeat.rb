# frozen_string_literal: true

require "minitest/autorun"
require "set"
require_relative "../lib/aozora/notation"
require_relative "../lib/aozora/repeat"

class TestRepeat < Minitest::Test
  R = Aozora::Repeat
  N = Aozora::Notation

  def tally(src) = R.count(N.parse(src))

  # ── F-11 初出を数えない ───────────────────────────────────
  def test_first_occurrence_is_not_counted
    # ルビ 1 回・再出現なし → 分母 0 → 測定不能。
    t = tally("吾輩《わがはい》は猫である")
    assert_equal 0, t.repeats
    assert_nil t.rate
  end

  def test_repeat_without_ruby_means_the_reader_is_trusted
    # 2 回目にルビ無し → 反復率 0 = 記憶を信用している。
    t = tally("吾輩《わがはい》は猫である。吾輩はここで人間を見た")
    assert_equal 1, t.repeats
    assert_equal 0, t.re_rubied
    assert_in_delta 0.0, t.rate, 1e-9
  end

  def test_repeat_with_ruby_means_the_reader_is_not_trusted
    t = tally("吾輩《わがはい》は猫。吾輩《わがはい》はここに居る")
    assert_equal 1, t.repeats
    assert_equal 1, t.re_rubied
    assert_in_delta 1.0, t.rate, 1e-9
  end

  def test_third_occurrence_counts_too
    t = tally("吾輩《わがはい》。吾輩《わがはい》。吾輩。")
    assert_equal 2, t.repeats
    assert_equal 1, t.re_rubied
    assert_in_delta 0.5, t.rate, 1e-9
  end

  # ── G-10 交絡からの独立を定義で担保する ───────────────────
  def test_rate_does_not_change_when_overall_ruby_density_changes
    # 同じ反復のふるまいのまま、ルビの総量だけを増やす。
    # 反復率が動けば、この軸は総ルビ傾向を測ってしまっている。
    sparse = tally("吾輩《わがはい》は猫である。吾輩はここに居る")
    dense  = tally("吾輩《わがはい》は猫《ねこ》である。吾輩はここに居る。" \
                   "人間《にんげん》。世界《せかい》。時間《じかん》。")
    assert_in_delta sparse.rate, dense.rate, 1e-9,
                    "総ルビ量を変えただけで反復率が動いた(G-10 の前提が崩れる)"
  end

  # ── 母集団の限定 ──────────────────────────────────────────
  def test_only_bases_that_received_ruby_are_counted
    # ルビが一度も付かない語は、何度出てきても分母に入らない。
    t = tally("猫である。猫である。猫である。")
    assert_equal 0, t.repeats
  end

  def test_single_character_bases_are_excluded
    # 1 字基底は頻出漢字と偶然一致して反復を水増しする。
    t = tally("山《やま》を見る。山を見る。山を見る。")
    assert_equal 0, t.repeats
  end

  def test_duty_ruby_is_excluded
    # 当て字・外来語(カタカナ読み)は難読でも記憶でもないので外す。
    t = tally("骨牌《カルタ》を配る。骨牌を配る。")
    assert_equal 0, t.repeats
  end

  # ── 走査の正しさ ──────────────────────────────────────────
  def test_longer_base_wins_over_shorter_one
    # 女子挺身隊 と 挺身隊 が両方ルビ基底のとき、長い方で食う。
    src = "女子挺身隊《じょしていしんたい》と挺身隊《ていしんたい》。女子挺身隊。"
    t = tally(src)
    assert_equal 1, t.repeats, "短い基底が長い基底の一部を食っている"
    assert_equal 0, t.re_rubied
  end

  def test_annotation_text_is_not_scanned
    # 入力者注の中身は作者の文章ではないので、反復に数えない。
    t = tally("吾輩《わがはい》は猫。［＃「吾輩」は底本では「吾軰」］である。")
    assert_equal 0, t.repeats
  end

  def test_merge_accumulates_across_works
    a = tally("吾輩《わがはい》。吾輩。")
    b = tally("吾輩《わがはい》。吾輩《わがはい》。")
    assert_in_delta 0.5, a.merge!(b).rate, 1e-9
  end
end
