# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/aozora/notation"

# 期待値の出所: すべて青空文庫の記法定義(各生テキストの凡例ブロック)。
# 実例は data/raw の実測(2026-08-27)から採った。ファイル ID をケースごとに記す。
class TestNotation < Minitest::Test
  N = Aozora::Notation

  def rt(src) = N.rebuild(N.parse(src))

  # ── T-001..T-006 往復検査(F-02 / O-01) ───────────────────────
  # 往復検査は「基底推定が正しいこと」ではなく「原文が失われないこと」を見る。
  # 基底が下手に取れても連結すれば原文に戻る、という不変量を明示的に確かめる。
  def test_roundtrip_holds_for_every_notation_form
    [
      "お葉《えふ》は考へた",                                   # 暗黙基底 (000002)
      "先年｜仏蘭西《フランス》で死去した",                     # 明示基底 ｜ (000005)
      "※［＃「亞＋鳥」、第4水準2-94-23］《からす》が",          # 外字が基底 (000005)
      "什※［＃「麾」の「毛」…］《どんな》に",                  # 外字を含む基底 (000002)
      "［＃ここから１字下げ］\n　このあいびきは",               # 組版指示のみ
      "泣く程｜口惜《くや》しく",                               # ｜ + 漢字基底
      "ルビ無しの素の本文",                                     # 注記なし
      "《》：ルビ",                                             # 基底の取れない 《》
      "｜だけがあって鉤括弧が来ない",                           # 孤立した ｜
      "未閉じの《ルビ",                                         # 閉じない 《
      "座敷着［＃「着」は底本では「看」と誤記］《ざしきぎ》を",  # 基底と読みの間に注記 (000351)
      "○《まる》を書き",                                       # 記号が基底 (000327)
      "「《ルビ》」の形式で処理した",                           # 本文中の編集メモ (000455)
    ].each { |src| assert_equal src, rt(src), "往復検査が破れた: #{src.inspect}" }
  end

  # ── T-013..T-015 実測から出た形(2026-08-27 G-02 調査) ────────
  def test_annotation_between_base_and_reading_does_not_break_the_base
    # 000351 実測。件数だけ見て中身を見なければ、この作品のルビは地の文に落ちていた。
    ruby = N.parse("座敷着［＃「着」は底本では「看」と誤記］《ざしきぎ》").find { |x| x.is_a?(N::Ruby) }
    refute_nil ruby, "注記が割り込むとルビとして取れていない"
    assert_equal "座敷着", ruby.base
    assert_equal "ざしきぎ", ruby.reading
    assert_includes ruby.mid, "誤記", "割り込んだ注記が保持されていない"
  end

  def test_nested_annotation_does_not_leak_ruby_into_the_body
    # 001805 実測。入れ子の入力者注を内側の ］ で閉じると、残骸に 笊《 が現れて
    # 漢字ルビが地の文へ落ちる。往復検査は残骸ごと復元するので素通りする(HC-027)。
    src = "小笊《こざる》［＃「小笊《こざる》」は底本では" \
          "「小※［＃「竹かんむり／瓜」、314-上-1］《こざる》」］に盛った"
    assert_equal src, rt(src)
    rubies = N.parse(src).select { |x| x.is_a?(N::Ruby) }
    assert_equal 1, rubies.length, "注記の中のルビまで数えている"
    assert_equal "小笊", rubies.first.base
    # 述語: 地の文に漢字基底の 《 が残っていないこと。
    body = N.parse(src).select { |x| x.is_a?(N::Text) }.map(&:raw).join
    assert_empty body.scan(/[\p{Han}々〆ヵヶ]《/), "漢字基底のルビが地の文に落ちている"
  end

  def test_symbol_can_be_a_base
    # 000327 実測: ○《まる》。文字クラスに記号が無いと取りこぼす。
    assert_equal "○", N.parse("○《まる》を書き").find { |x| x.is_a?(N::Ruby) }.base
  end

  def test_fullwidth_latin_can_be_a_base
    # 051250 実測: ＭＲ《ミスタ》・タチバナ。半角 [A-Za-z] だけでは取りこぼす。
    assert_equal "ＭＲ", N.parse("ＭＲ《ミスタ》・タチバナ").find { |x| x.is_a?(N::Ruby) }.base
  end

  def test_non_japanese_scripts_can_be_a_base
    # G-02 の残骸を実例まで見て出た形。比率では 0.008% だが、性質はどれも本物の取りこぼし。
    {
      "γ《ガムマア》"     => "γ",   # ギリシャ  (001058)
      "Л《エル》"         => "Л",   # キリル    (051847)
      "＋《よこじゅうじ》" => "＋",   # 数学記号  (001317)
      "〔Ma_r〕《マール》" => "〔Ma_r〕", # 亀甲括弧の翻字 (042686)
    }.each do |src, base|
      ruby = N.parse(src).find { |x| x.is_a?(N::Ruby) }
      refute_nil ruby, "ルビとして取れていない: #{src}"
      assert_equal base, ruby.base
      assert_equal src, rt(src)
    end
  end

  def test_bar_used_as_a_rule_character_is_not_a_ruby_marker
    # 002714 実測: 盤面図の罫線に ｜ が 208 個。後に 《 が来ないので ｜ は地の文に戻る。
    src = "｜○｜●｜○｜\n├─┼─┼"
    assert_equal src, rt(src)
    assert_empty N.parse(src).select { |x| x.is_a?(N::Ruby) }
  end

  def test_editorial_memo_in_body_is_not_ruby
    # 000455 実測: 本文中に「●ルビは「《ルビ》」の形式で処理した」という編集メモがある。
    # 直前が 「 なので基底が取れず、ルビにならないのが正しい。
    assert_empty N.parse("「《ルビ》」の形式").select { |x| x.is_a?(N::Ruby) }
  end

  # ── T-007 基底の取り込み ──────────────────────────────────
  def test_implicit_base_takes_the_whole_kanji_run
    n = N.parse("女子挺身隊《じょしていしんたい》の少女")
    ruby = n.find { |x| x.is_a?(N::Ruby) }
    assert_equal "女子挺身隊", ruby.base
    assert_equal "じょしていしんたい", ruby.reading
    refute ruby.bar?
  end

  def test_explicit_base_takes_exactly_the_bar_span
    # ｜ は「漢字連続では切り出せない基底」を作者が明示するための記号。
    n = N.parse("半年のうちに｜醜の御楯《しこのみたて》といでたつ")
    ruby = n.find { |x| x.is_a?(N::Ruby) }
    assert_equal "醜の御楯", ruby.base   # 「の」を含む = 漢字連続では取れない
    assert ruby.bar?
  end

  def test_gaiji_becomes_its_own_base
    n = N.parse("※［＃「亞＋鳥」、第4水準2-94-23］《からす》")
    ruby = n.find { |x| x.is_a?(N::Ruby) }
    assert_equal "※［＃「亞＋鳥」、第4水準2-94-23］", ruby.base
    assert_equal "からす", ruby.reading
  end

  # ── T-010 基底が取れない 《》 はルビにしない(G-02) ──────────
  def test_guillemets_without_base_are_not_ruby
    # 凡例ブロックの「《》：ルビ」を誤ってルビと数えないこと。
    assert_empty N.parse("《》：ルビ").select { |x| x.is_a?(N::Ruby) }
  end

  # ── T-011 注記はルビの基底に混ざらない ────────────────────
  def test_annotation_is_a_separate_node
    n = N.parse("［＃ここから１字下げ］吾輩《わがはい》は猫である")
    assert_equal 1, n.count { |x| x.is_a?(N::Annot) }
    assert_equal "吾輩", n.find { |x| x.is_a?(N::Ruby) }.base
  end

  # ── T-012 カタカナ・英字の基底 ────────────────────────────
  def test_katakana_run_can_be_a_base
    n = N.parse("アクーリナ《Akulina》")
    assert_equal "アクーリナ", n.find { |x| x.is_a?(N::Ruby) }.base
  end
end
