# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/aozora/notation"
require_relative "../lib/aozora/tally"

# 計量の混入テスト。
#
# 実測 2026-08-27: 外字注記が基底になるルビで、注記の説明文の漢字が
# そのままルビ付き漢字として計上されていた。定型句「第4水準」から
# 第 7,269 / 水 7,256 / 準 7,174 件が混入していた。
#
# HC-041: 陽性対照(混入してはならない字)と陰性対照(数えなければならない字)を対で置く。
# 片側だけだと、何も数えない実装も、何でも数える実装も緑になる。
class TestTally < Minitest::Test
  T = Aozora::Tally
  N = Aozora::Notation

  def count(src) = T.count(N.parse(src))

  # ── 陽性対照: 注記の説明文は数えてはならない ──────────────
  def test_gaiji_annotation_text_is_not_counted
    c = count("小心な※［＃「亞＋鳥」、第4水準2-94-23］《からす》が飛ぶ")
    %w[第 水 準 亞 鳥].each do |ch|
      assert_equal 0, c.rubied[ch] + c.plain[ch] + c.duty[ch],
                   "注記の説明文の #{ch} が計量に混入している"
    end
  end

  def test_gaiji_base_is_counted_as_the_character_it_stands_for
    # 2-94-23 は 鵶。注記が表す 1 文字だけがルビ付きとして数えられる。
    c = count("小心な※［＃「亞＋鳥」、第4水準2-94-23］《からす》が飛ぶ")
    assert_equal 1, c.rubied["鵶"], "外字が表す文字が数えられていない"
    assert_equal 1, c.rubied.values.sum, "外字ルビで数える字は 1 字だけのはず"
  end

  def test_standalone_gaiji_counts_as_plain_kanji
    # ルビが付かない外字も本文の漢字である。落とすと難読帯を過小評価する。
    c = count("彼は※［＃「亞＋鳥」、第4水準2-94-23］を見た")
    assert_equal 1, c.plain["鵶"]
    assert_equal 0, c.plain["第"]
  end

  def test_unmappable_gaiji_is_dropped_not_expanded
    # 面区点が無い注記は写像できない。説明文を数えるくらいなら落とす。
    c = count("什※［＃「麾」の「毛」にかえて「公」の右上の欠けたもの］《どんな》に")
    assert_equal 1, c.rubied["什"], "注記の前の基底が消えている"
    %w[麾 毛 公 右 上 欠].each { |ch| assert_equal 0, c.rubied[ch], "説明文の #{ch} が混入" }
  end

  # ── 陰性対照: 通常の本文は正しく数えなければならない ──────
  def test_ordinary_text_and_ruby_are_counted
    c = count("吾輩《わがはい》は猫である。名前はまだ無い")
    assert_equal 1, c.rubied["吾"]
    assert_equal 1, c.rubied["吾輩".chars.last]
    assert_equal 1, c.plain["猫"]
    assert_equal 1, c.plain["名"]
    assert_equal 0, c.duty.values.sum
  end

  def test_katakana_reading_goes_to_duty
    c = count("骨牌《カルタ》を配る")
    assert_equal 1, c.duty["骨"]
    assert_equal 0, c.rubied["骨"]
  end

  def test_input_annotation_body_is_never_counted
    # ［＃ここから１字下げ］の「字」「下」を数えてはならない。
    c = count("［＃ここから１字下げ］吾輩《わがはい》は猫")
    assert_equal 0, c.plain["字"] + c.plain["下"]
    assert_equal 1, c.plain["猫"]
  end

  # ── 混入していたら必ず落ちる形 ────────────────────────────
  def test_a_naive_implementation_would_fail_this
    # 基底を生文字列のまま each_char した実装では 5 字が rubied に入る。
    c = count("※［＃「亞＋鳥」、第4水準2-94-23］《からす》")
    assert_equal 1, c.rubied.values.sum,
                 "生の注記を展開している(旧実装なら 亞鳥第水準 の 5 字が入る)"
  end
end
