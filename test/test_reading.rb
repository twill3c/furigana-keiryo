# frozen_string_literal: true

require "minitest/autorun"
require "set"
require_relative "../lib/aozora/notation"
require_relative "../lib/aozora/reading"

# 熟字訓の判定器のテスト。
#
# HC-041: 検出系のテストには**陽性対照と陰性対照を対で置く**。
# 「熟字訓を捕まえた」だけを見ると、何でも熟字訓と言う壊れた判定器が緑になる。
# 「通常の音訓を撃たない」だけを見ると、何も捕まえない判定器が緑になる。
# 両方を同じ場所に並べ、**判定器そのものをテストする**。
class TestReading < Minitest::Test
  R = Aozora::Reading
  N = Aozora::Notation

  # 在庫は手で組む。実データから作った在庫でテストすると、
  # 在庫の欠けと判定器の誤りが混ざって、どちらが原因か分からなくなる。
  def inv
    @inv ||= {
      "今" => Set["こん", "いま"], "宵" => Set["よい", "しょう"],
      "田" => Set["でん", "た"],   "舎" => Set["しゃ"],
      "女" => Set["じょ", "おんな"], "子" => Set["し", "こ"],
      "挺" => Set["てい"], "身" => Set["しん", "み"], "隊" => Set["たい"],
      "訣" => Set["けつ"], "別" => Set["べつ", "わか"],
      "学" => Set["がく"], "校" => Set["こう"],
      "世" => Set["せ", "よ"], "相" => Set["そう", "あい"],
      "見" => Set["けん", "み"], "当" => Set["とう", "あ"],
      "大" => Set["だい", "おお"], "人" => Set["じん", "にん", "ひと"],
      "紅" => Set["こう", "べに"], "葉" => Set["よう", "は"],
      "眼" => Set["がん", "め"],  "鏡" => Set["きょう", "かがみ"],
      "山" => Set["さん", "やま"], "車" => Set["しゃ", "くるま"],
      "息" => Set["そく", "いき"], "月" => Set["げつ", "つき"],
      "五" => Set["ご", "いつ"],  "雨" => Set["う", "あめ"],
      "国" => Set["こく", "くに"], "花" => Set["か", "はな"],
      "手" => Set["しゅ", "て"],  "紙" => Set["し", "かみ"],
      "一" => Set["いち", "ひと"], "歩" => Set["ほ", "あゆ"]
    }
  end

  def dec?(base, reading) = R.decomposable?(base, reading, inv)

  # ── 陰性対照: 撃ってはならない（通常の音訓の連結） ──────────
  # ここが落ちると、判定器は正当なルビまで義務ルビとして両軸から外してしまう。
  def test_normal_compounds_are_decomposable
    {
      "学校" => "がっこう",           # 促音便 がく + こう
      "世相" => "せそう",
      "見当" => "けんとう",
      "訣別" => "けつべつ",
      "女子挺身隊" => "じょしていしんたい",
      "国花" => "こっか",             # 促音便 こく + か
      "一歩" => "いっぽ",             # 促音便 + 半濁 いち + ほ
      "手紙" => "てがみ",             # 連濁 て + かみ
      "山車" => "やまぐるま",          # 連濁（だし ではない読み方の場合）
      "見" => "み"                   # 単字も分解できる
    }.each { |b, r| assert dec?(b, r), "通常の音訓を熟字訓と誤判定: #{b}《#{r}》" }
  end

  # ── 陽性対照: 必ず捕まえるべき（熟字訓・当て字） ─────────────
  # ここが落ちると、判定器は何も捕まえず、G-07 は保留のままになる。
  def test_jukujikun_are_not_decomposable
    {
      "今宵" => "こよい",
      "田舎" => "いなか",
      "大人" => "おとな",
      "紅葉" => "もみじ",
      "眼鏡" => "めがね",
      "山車" => "だし",
      "息子" => "むすこ",
      "五月雨" => "さみだれ"
    }.each { |b, r| refute dec?(b, r), "熟字訓を取りこぼした: #{b}《#{r}》" }
  end

  # ── 判定器そのものが働いているか ──────────────────────────
  def test_a_detector_that_says_yes_to_everything_would_fail_this
    # 出鱈目な読みは分解できてはならない。
    refute dec?("学校", "あいうえお")
    refute dec?("見当", "ぜんぜんちがう")
  end

  def test_a_detector_that_says_no_to_everything_would_fail_this
    # 素直な連結は必ず通らなければならない。
    assert dec?("学校", "がくこう")
    assert dec?("世相", "せそう")
  end

  # ── G-20 循環の禁止 ───────────────────────────────────────
  def test_inventory_takes_only_single_character_bases
    # 多字基底が在庫に入ると、その基底の分解は自明に成功する。
    nodes = [N.parse("今宵《こよい》の山《やま》")]
    got = R.inventory(nodes)
    assert_equal ["山"], got.keys, "多字基底が在庫に混入している(G-20 違反)"
    assert_equal({ "やま" => 1 }, got["山"])
  end

  def test_inventory_ignores_katakana_readings
    # 当て字（骨牌《カルタ》）を在庫に入れると、以後カルタが正当な読みになる。
    assert_empty R.inventory([N.parse("牌《カルタ》")])
  end

  # ── 判定不能の扱い ────────────────────────────────────────
  def test_unknown_kanji_is_undecidable_not_jukujikun
    # 在庫に無い字を「分解できない = 熟字訓」と扱うと、
    # 珍しい字を含む基底が軒並み義務ルビになって両軸から消える。
    assert R.undecidable?("麒麟", inv)
    assert dec?("麒麟", "きりん"), "判定不能を熟字訓として扱っている"
  end

  # ── 音便の異形 ────────────────────────────────────────────
  def test_rendaku_only_applies_after_the_first_element
    assert_includes R.variants("かみ", first: false, last: true), "がみ"
    refute_includes R.variants("かみ", first: true, last: true), "がみ"
  end

  def test_sokuon_only_applies_before_the_last_element
    assert_includes R.variants("がく", first: true, last: false), "がっ"
    refute_includes R.variants("がく", first: true, last: true), "がっ"
  end

  # ── 在庫の枝刈り ──────────────────────────────────────────
  def test_prune_drops_readings_seen_only_once
    inv = { "山" => { "やま" => 9, "ざん" => 1 } }
    assert_equal Set["やま"], R.prune(inv, min: 2)["山"]
  end
end
