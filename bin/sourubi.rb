# frozen_string_literal: true

# 総ルビ組版を作品単位で検出する(SPEC F-13)。
#
#   ruby bin/sourubi.rb [--limit N]
#
# 判定するゲート(判定線は測定前に SPEC へ書き、commit 63b0631 で封じてある):
#   G-14 p_easy の分布が二峰性を示す      … 総ルビは別の母集団か
#   G-15 総ルビ作を持つ作家の過半数が非総ルビ作も持つ … 組版方針か文体か
#
# 検出は密度ではなく**難易度への非依存**で行う。総ルビの署名は
# 「易読帯の漢字にまでルビが振られる」ことである。
#
# 帯は全作家合算の頻度から作る(一人抜きをしない)。ここで見たいのは
# 作家ごとの難読度ではなく、作品の組版方針だからである。

require "json"
require_relative "../lib/aozora/corpus"
require_relative "../lib/aozora/tally"
require_relative "../lib/aozora/axes"

C = Aozora::Corpus
T = Aozora::Tally
A = Aozora::Axes

MIN_EASY = 200   # 易読帯の出現がこれ未満の作品は p_easy を測れない

limit = (i = ARGV.index("--limit")) ? ARGV[i + 1].to_i : nil
works = C.works.sort_by(&:id)
works = works.first(limit) if limit

# ── 第 1 走査: 全体の漢字頻度から帯を作る ────────────────────
warn "pass 1/2: 頻度表"
global = Hash.new(0)
works.each_with_index do |w, i|
  nodes = C.parse(w.id)
  next if nodes.nil?

  A.frequency(T.count(nodes)).each { |ch, n| global[ch] += n }
  warn "  #{i + 1}/#{works.length}" if ((i + 1) % 1000).zero?
end
easy, hard = A.bands(global)
warn "  易読帯 #{easy.size} 字 / 難読帯 #{hard.size} 字"

# ── 第 2 走査: 作品ごとの p_easy ─────────────────────────────
warn "pass 2/2: 作品ごとの易読帯ルビ率"
rows = []
works.each_with_index do |w, i|
  nodes = C.parse(w.id)
  next if nodes.nil?

  c = T.count(nodes)
  den_e = easy.sum { |ch| c.rubied[ch] + c.plain[ch] }
  next if den_e < MIN_EASY

  den_h = hard.sum { |ch| c.rubied[ch] + c.plain[ch] }
  rows << {
    id: w.id, author: w.author, title: w.title, kana: w.kana,
    p_easy: easy.sum { |ch| c.rubied[ch] }.to_f / den_e,
    p_hard: den_h.zero? ? nil : hard.sum { |ch| c.rubied[ch] }.to_f / den_h,
    easy_n: den_e, hard_n: den_h
  }
  warn "  #{i + 1}/#{works.length}" if ((i + 1) % 1000).zero?
end

# ── G-14 二峰性 ──────────────────────────────────────────────
bins = Hash.new(0)
rows.each { |r| bins[(r[:p_easy] * 20).floor.clamp(0, 19)] += 1 }
puts "== p_easy の分布(易読帯漢字のうちルビが振られた割合) =="
20.times do |b|
  lo = b / 20.0
  n = bins[b]
  puts format("  %.2f–%.2f  %5d  %s", lo, lo + 0.05, n, "#" * [n / 8, 60].min)
end

low  = rows.count { |r| r[:p_easy] >= 0.1 && r[:p_easy] < 0.5 }
mid  = rows.count { |r| r[:p_easy] >= 0.5 && r[:p_easy] < 0.9 }
high = rows.count { |r| r[:p_easy] >= 0.9 }
puts
puts "== G-14 二峰性(判定線: 谷が両側より少ない・測定前に宣言) =="
puts "  [0.10,0.50) 左の山 : #{low}"
puts "  [0.50,0.90) 谷     : #{mid}"
puts "  [0.90,1.00] 右の山 : #{high}"
g14 = mid < low && mid < high
puts(g14 ? "  → 合格。総ルビは別の母集団である" : "  → 失格。総ルビは連続的な程度問題であり、分離してはならない")

# ── G-15 作家内混在 ──────────────────────────────────────────
sou = rows.select { |r| r[:p_easy] >= 0.9 }
by_author = rows.group_by { |r| r[:author] }
sou_authors = sou.map { |r| r[:author] }.uniq
mixed = sou_authors.count { |a| by_author[a].any? { |r| r[:p_easy] < 0.9 } }
puts
puts "== G-15 作家内混在(判定線: 過半数・測定前に宣言) =="
puts "  総ルビ作品         : #{sou.length} / #{rows.length}(#{'%.1f' % (sou.length * 100.0 / rows.length)} %)"
puts "  総ルビ作を持つ作家 : #{sou_authors.length}"
puts "  うち非総ルビ作も持つ: #{mixed}(#{sou_authors.empty? ? 0 : '%.1f' % (mixed * 100.0 / sou_authors.length)} %)"
g15 = !sou_authors.empty? && mixed * 2 > sou_authors.length
puts(g15 ? "  → 合格。同じ作家が両方を持つ。組版方針であって文体ではない" :
           "  → 失格。作家ごとに一貫している = 文体。分離してはならない")

puts
puts "== 作家内で割れている例 =="
sou_authors.select { |a| by_author[a].any? { |r| r[:p_easy] < 0.9 } }
           .sort_by { |a| -by_author[a].length }.first(6).each do |a|
  g = by_author[a].sort_by { |r| -r[:p_easy] }
  puts "  #{a}:"
  [g.first, g.last].each { |r| puts format("    p_easy %.3f  %s", r[:p_easy], r[:title][0, 24]) }
end

File.write(File.expand_path("../out/sourubi.json", __dir__),
           JSON.pretty_generate(
             works_scanned: works.length, limit: limit, measured: rows.length,
             easy_band: easy.size, hard_band: hard.size, min_easy: MIN_EASY,
             gates: { g14_low: low, g14_mid: mid, g14_high: high, g14_pass: g14,
                      g15_authors: sou_authors.length, g15_mixed: mixed, g15_pass: g15 },
             sourubi_ids: sou.map { |r| r[:id] }.sort,
             works: rows
           ))
exit(g14 && g15 ? 0 : 1)
