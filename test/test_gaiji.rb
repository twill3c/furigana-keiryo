# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/aozora/gaiji"

# 外字写像のテスト。
#
# HC-041: 検出・変換系には陽性対照と陰性対照を対で置く。
# 「写像できた」だけを見ると、何でも適当な字を返す壊れた写像器が緑になる。
# 「写像できない入力を弾いた」だけを見ると、何も写像しない写像器が緑になる。
#
# 期待値の出所(HC-016): すべて data/raw の実測(2026-08-27)。
# 面区点 → 文字 の対応は、注記の中の**字形の説明**と突き合わせて確かめている。
# 「亞＋鳥」と書かれた注記が 鵶(亞+鳥)を返すなら、写像規則は正しい。
class TestGaiji < Minitest::Test
  G = Aozora::Gaiji

  # ── 陽性対照: 写像できなければならない ────────────────────
  def test_maps_real_annotations_to_the_character_the_note_describes
    {
      # 注記の生文字列 => [期待される字, 字形の説明との照合]
      "※［＃「亞＋鳥」、第4水準2-94-23］" => ["鵶", "亞 と 鳥 の合字"],
      "※［＃「弓＋單」、第3水準1-84-22］" => ["弴", "弓 と 單 の合字"]
    }.each do |raw, (want, why)|
      got = G.map(raw)
      refute_nil got, "写像できていない: #{raw}"
      assert_equal want, got.char, "#{why} のはずが #{got.char}"
    end
  end

  def test_maps_both_planes
    assert_equal 1, G.map("※［＃「弓＋單」、第3水準1-84-22］").men
    assert_equal 2, G.map("※［＃「亞＋鳥」、第4水準2-94-23］").men
  end

  # ── G-03b 独立した二欄の整合 ──────────────────────────────
  def test_level_label_agrees_with_the_plane_number
    # 第3水準 → 面 1 / 第4水準 → 面 2。注記の別々の欄なので、
    # 写像規則が誤っていればここが食い違う(非循環の検算)。
    assert G.map("※［＃「弓＋單」、第3水準1-84-22］").level_agrees?
    assert G.map("※［＃「亞＋鳥」、第4水準2-94-23］").level_agrees?
  end

  def test_level_disagreement_is_detected
    # 壊れた入力を検出できること。検査が働いていることの確認。
    refute G.map("※［＃「亞＋鳥」、第3水準2-94-23］").level_agrees?
    refute G.map("※［＃「弓＋單」、第4水準1-84-22］").level_agrees?
  end

  def test_level_is_nil_when_the_note_has_no_label
    # ラベルの無い注記では整合を検査しない(false ではなく nil)。
    assert_nil G.map("※［＃「弓＋單」、1-84-22］").level_agrees?
  end

  # ── 陰性対照: 写像してはならない ──────────────────────────
  def test_returns_nil_for_notes_without_a_menkuten
    # 字形の説明だけで番号が無い注記は写像できない。適当な字を返してはならない。
    [
      "※［＃「麾」の「毛」にかえて「公」の右上の欠けたもの］",
      "［＃ここから１字下げ］",
      "※［＃小書き片仮名ヰ］"
    ].each { |raw| assert_nil G.map(raw), "写像できないはずの注記を写像した: #{raw}" }
  end

  def test_returns_nil_for_out_of_range_numbers
    assert_nil G.to_char(3, 10, 10), "面 3 は存在しない"
    assert_nil G.to_char(1, 0, 10)
    assert_nil G.to_char(1, 95, 10)
    assert_nil G.to_char(1, 10, 95)
  end

  def test_unassigned_code_points_return_nil_not_garbage
    # 未割当の区点は nil。置換文字や空文字を返してはならない。
    got = G.to_char(1, 15, 94)
    assert(got.nil? || (got.length == 1 && got != "�"),
           "未割当が置換文字になっている: #{got.inspect}")
  end

  # ── 写像した字が実際に使えるか ────────────────────────────
  def test_mapped_characters_are_single_kanji
    %w[2-94-23 1-84-22].each do |s|
      men, ku, ten = s.split("-").map(&:to_i)
      ch = G.to_char(men, ku, ten)
      assert_equal 1, ch.length, "合成文字ではなく 1 字であること"
      assert ch.match?(/\p{Han}/), "漢字として扱えること: #{ch}"
    end
  end
end
