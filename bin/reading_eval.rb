# frozen_string_literal: true

# 読み在庫を作り、熟字訓の判定器を評価する(SPEC F-14)。
#
#   ruby bin/reading_eval.rb
#
# 判定するゲート(判定線は測定前に SPEC へ書き、commit 70280d8 で封じてある):
#   G-17 取り置き検証で単字ルビ実例の 90% 以上を再現
#   G-18 手作業の正解セットで精度・再現率とも 0.8 以上
#   G-20 在庫の入力は単字基底のみ(循環の禁止)
#
# 単字ルビの実例を出現順に交互へ振り分け、**片方だけで在庫を作り、もう片方で試す**。
# 全部で作って全部で試すと再現率はほぼ 1 になり、緑でも何も検査していない。

require "json"
require "set"
require_relative "../lib/aozora/corpus"
require_relative "../lib/aozora/notation"
require_relative "../lib/aozora/reading"

C = Aozora::Corpus
N = Aozora::Notation
R = Aozora::Reading

OUT = File.expand_path("../out", __dir__)
CACHE = "#{OUT}/ruby_pairs.json"

# ── 収集(結果をキャッシュする) ───────────────────────────────
pairs =
  if File.exist?(CACHE)
    warn "ルビ対をキャッシュから読む"
    JSON.parse(File.read(CACHE, encoding: "UTF-8"))
  else
    warn "全作品を走査してルビ対を集める(約 13 分)"
    single = [Hash.new { |h, k| h[k] = Hash.new(0) }, Hash.new { |h, k| h[k] = Hash.new(0) }]
    multi = Hash.new { |h, k| h[k] = Hash.new(0) }
    seen = 0
    C.works.each_with_index do |w, i|
      nodes = C.parse(w.id)
      next if nodes.nil?

      nodes.each do |n|
        next unless n.is_a?(N::Ruby)
        next unless n.reading.match?(R::KANA)
        next unless n.base.match?(/\A#{R::KANJI.source}+\z/)

        if n.base.length == 1
          # 出現順に交互へ。取り置き検証のため(G-17)。
          single[seen % 2][n.base][n.reading] += 1
          seen += 1
        else
          multi[n.base][n.reading] += 1
        end
      end
      warn "  #{i + 1}/#{C.works.length}" if ((i + 1) % 1000).zero?
    end
    h = { "single_a" => single[0], "single_b" => single[1], "multi" => multi }
    File.write(CACHE, JSON.generate(h))
    h
  end

def to_inv(h) = h.transform_values { |v| v.transform_keys(&:to_s) }

train = to_inv(pairs["single_a"])
test  = to_inv(pairs["single_b"])
multi = to_inv(pairs["multi"])

inv_train = R.prune(train, min: 2)
inv_all   = R.prune(train.merge(test) { |_, a, b| a.merge(b) { |_, x, y| x + y } }, min: 2)

puts "== 読み在庫 =="
puts "単字ルビ実例 : #{train.values.sum { |h| h.values.sum } + test.values.sum { |h| h.values.sum }}"
puts "在庫の漢字   : #{inv_all.size} 字 / 読み #{inv_all.values.sum(&:size)} 通り"
puts "多字基底     : #{multi.size} 種 / 実例 #{multi.values.sum { |h| h.values.sum }}"

# ── G-17 取り置き検証 ────────────────────────────────────────
hit = 0
miss = 0
unknown = 0
test.each do |ch, hs|
  hs.each do |r, c|
    if inv_train[ch].nil? then unknown += c
    elsif inv_train[ch].include?(r) then hit += c
    else miss += c
    end
  end
end
cov = hit * 100.0 / (hit + miss + unknown)
puts
puts "== G-17 取り置き検証(判定線 90%・測定前に宣言) =="
puts "  片側だけで作った在庫が、もう片側の実例を再現できた割合"
puts "  一致 #{hit} / 読み違い #{miss} / 字が在庫に無い #{unknown}"
puts "  再現率 #{'%.2f' % cov} %"
g17 = cov >= 90
puts(g17 ? "  → 合格" : "  → 失格。在庫が薄すぎて判定に使えない")

# ── G-18 手作業の正解セット ──────────────────────────────────
# 出所: 私(エージェント)の知識による手作業のラベル。小さく、網羅的でもない。
# だからこそ陽性対照と陰性対照を対で置く(HC-041)。実測日 2026-08-27。
JUKUJIKUN = {
  "今宵" => "こよい", "田舎" => "いなか", "大人" => "おとな", "紅葉" => "もみじ",
  "眼鏡" => "めがね", "息子" => "むすこ", "五月雨" => "さみだれ", "時雨" => "しぐれ",
  "相撲" => "すもう", "土産" => "みやげ", "果物" => "くだもの", "玄人" => "くろうと",
  "素人" => "しろうと", "老舗" => "しにせ", "為替" => "かわせ", "行方" => "ゆくえ",
  "浴衣" => "ゆかた", "足袋" => "たび", "海女" => "あま", "吹雪" => "ふぶき"
}.freeze
NORMAL = {
  "学校" => "がっこう", "世相" => "せそう", "見当" => "けんとう", "訣別" => "けつべつ",
  "記憶" => "きおく", "人間" => "にんげん", "全盛" => "ぜんせい", "三階" => "さんがい",
  "熾熱燈" => "しねつとう", "女子挺身隊" => "じょしていしんたい", "手紙" => "てがみ",
  "国花" => "こっか", "見返" => "みかえ", "中等室" => "ちゅうとうしつ",
  "薄暗" => "うすぐら", "名前" => "なまえ", "記録" => "きろく", "青年" => "せいねん",
  "山桜" => "やまざくら", "夕暮" => "ゆうぐれ"
}.freeze

def judge(base, reading, inv)
  return :undecidable if Aozora::Reading.undecidable?(base, inv)

  Aozora::Reading.decomposable?(base, reading, inv) ? :normal : :jukujikun
end

tp = fn = und_j = 0
JUKUJIKUN.each do |b, r|
  case judge(b, r, inv_all)
  when :jukujikun then tp += 1
  when :normal then (fn += 1; puts "  取りこぼし: #{b}《#{r}》")
  else und_j += 1
  end
end
fp = tn = und_n = 0
NORMAL.each do |b, r|
  case judge(b, r, inv_all)
  when :jukujikun then (fp += 1; puts "  誤検出: #{b}《#{r}》")
  when :normal then tn += 1
  else und_n += 1
  end
end
prec = tp.zero? ? 0.0 : tp.to_f / (tp + fp)
rec  = tp.zero? ? 0.0 : tp.to_f / (tp + fn)
puts
puts "== G-18 手作業の正解セット(判定線 精度・再現率とも 0.8・測定前に宣言) =="
puts "  陽性対照(熟字訓)   #{JUKUJIKUN.size} 件: 捕捉 #{tp} / 取りこぼし #{fn} / 判定不能 #{und_j}"
puts "  陰性対照(通常の音訓) #{NORMAL.size} 件: 正しく見送り #{tn} / 誤検出 #{fp} / 判定不能 #{und_n}"
puts "  精度 #{'%.3f' % prec} / 再現率 #{'%.3f' % rec}"
g18 = prec >= 0.8 && rec >= 0.8
puts(g18 ? "  → 合格" : "  → 失格。判定器を軸に使ってはならない")

# ── コーパス全体での効き方 ───────────────────────────────────
tally = Hash.new(0)
duty_examples = Hash.new(0)
multi.each do |b, hs|
  hs.each do |r, c|
    k = judge(b, r, inv_all)
    tally[k] += c
    duty_examples["#{b}《#{r}》"] += c if k == :jukujikun
  end
end
tot = tally.values.sum
puts
puts "== コーパス全体(多字基底のルビ #{tot} 件) =="
%i[normal jukujikun undecidable].each do |k|
  puts format("  %-12s %8d 件 (%.1f %%)", k, tally[k], tally[k] * 100.0 / tot)
end
puts "  熟字訓と判定された上位 20:"
duty_examples.sort_by { |_, c| -c }.first(20).each_slice(4) do |row|
  puts "    " + row.map { |k, c| "#{k} #{c}" }.join(" / ")
end

File.write("#{OUT}/reading.json", JSON.pretty_generate(
  gates: { g17_coverage: cov, g17_pass: g17,
           g18_precision: prec, g18_recall: rec, g18_pass: g18 },
  inventory_kanji: inv_all.size,
  tally: tally.transform_keys(&:to_s),
  inventory: inv_all.transform_values(&:to_a)
))
exit(g17 && g18 ? 0 : 1)
