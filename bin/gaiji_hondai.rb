# frozen_string_literal: true

# 外字の写像率(G-03a/b)と、底本差によるルビ揺れ(G-21/G-22)を測る。
#
#   ruby bin/gaiji_hondai.rb
#
# 判定線は測定前に SPEC へ書き、commit 412e8a2 で封じてある。

require "json"
require "set"
require_relative "../lib/aozora/corpus"
require_relative "../lib/aozora/notation"
require_relative "../lib/aozora/tally"
require_relative "../lib/aozora/gaiji"

C = Aozora::Corpus
N = Aozora::Notation
T = Aozora::Tally
G = Aozora::Gaiji

OUT = File.expand_path("../out", __dir__)
sou = JSON.parse(File.read("#{OUT}/sourubi.json", encoding: "UTF-8"))
SOU_IDS = sou["sourubi_ids"].to_set

def median(a) = a.empty? ? nil : a.sort[a.length / 2]

# ── 走査 ─────────────────────────────────────────────────────
gaiji = { total: 0, with_num: 0, mapped: 0, level_ok: 0, level_ng: 0, level_none: 0 }
bad_level = []
gaiji_chars = Hash.new(0)
per_work = {}

C.works.each_with_index do |w, i|
  nodes = C.parse(w.id)
  next if nodes.nil?

  nodes.each do |n|
    next unless n.is_a?(N::Gaiji)

    gaiji[:total] += 1
    m = G.map(n.raw)
    if m.nil?
      gaiji[:with_num] += 1 if n.raw.match?(/\d-\d{1,2}-\d{1,2}/)
      next
    end
    gaiji[:with_num] += 1
    gaiji[:mapped] += 1
    gaiji_chars[m.char] += 1
    case m.level_agrees?
    when true then gaiji[:level_ok] += 1
    when false then (gaiji[:level_ng] += 1; bad_level << [w.id, m.note[0, 40], m.men, m.level])
    else gaiji[:level_none] += 1
    end
  end

  c = T.count(nodes)
  rub = c.rubied.values.sum
  pln = c.plain.values.sum
  next if (rub + pln) < 500

  per_work[w.id] = { author: w.author, title: w.title,
                     density: rub * 100.0 / (rub + pln), sou: SOU_IDS.include?(w.id) }
  warn "  #{i + 1}/#{C.works.length}" if ((i + 1) % 1000).zero?
end

# ── G-03a / G-03b ────────────────────────────────────────────
rate = gaiji[:mapped] * 100.0 / [gaiji[:with_num], 1].max
lvl_tot = gaiji[:level_ok] + gaiji[:level_ng]
lvl_rate = lvl_tot.zero? ? 100.0 : gaiji[:level_ok] * 100.0 / lvl_tot

puts "== 外字注記 =="
puts "  注記の総数            : #{gaiji[:total]}"
puts "  面区点番号を持つもの  : #{gaiji[:with_num]}"
puts "  写像できたもの        : #{gaiji[:mapped]}"
puts "  異なり字数            : #{gaiji_chars.size}"
puts
puts "== G-03a 写像率(判定線 90%・測定前に宣言) =="
puts "  #{'%.2f' % rate} %"
g03a = rate >= 90
puts(g03a ? "  → 合格" : "  → 失格")
puts
puts "== G-03b 水準ラベルと面番号の整合(判定線 99%・測定前に宣言) =="
puts "  ラベルあり #{lvl_tot}(一致 #{gaiji[:level_ok]} / 食い違い #{gaiji[:level_ng]}) / ラベル無し #{gaiji[:level_none]}"
puts "  一致率 #{'%.2f' % lvl_rate} %"
g03b = lvl_rate >= 99
puts(g03b ? "  → 合格。写像規則は注記の独立した欄と整合する" : "  → 失格。写像規則が疑わしい")
bad_level.first(5).each { |id, note, men, lv| puts "    食い違い #{id}: 面#{men} vs 第#{lv}水準 / #{note}" }
puts
puts "  よく出る外字 上位 12:"
gaiji_chars.sort_by { |_, c| -c }.first(12).each_slice(6) do |row|
  puts "    " + row.map { |ch, c| "#{ch} #{c}" }.join(" / ")
end

# ── G-21 / G-22 底本差 ───────────────────────────────────────
# 同一作家・同一題名の作品対を異版とみなす。題名は括弧書き等を落として正規化する。
def norm(t) = t.gsub(/[（(《【〔].*?[）)》】〕]/, "").gsub(/\s+/, "").strip

live = per_work.reject { |_, v| v[:sou] }
groups = live.values.group_by { |v| [v[:author], norm(v[:title])] }
             .select { |_, v| v.length >= 2 }

within = []
groups.each_value do |ws|
  ws.combination(2) { |a, b| within << (a[:density] - b[:density]).abs }
end

# 作家間の差: 作家をまたぐ作品対を seed 固定で無作為に同数抜く。
rng = Random.new(20_260_827)
vals = live.values
between = Array.new([within.length, 2000].max) do
  a = vals[rng.rand(vals.length)]
  b = vals[rng.rand(vals.length)]
  a[:author] == b[:author] ? nil : (a[:density] - b[:density]).abs
end.compact

mw = median(within)
mb = median(between)
puts
puts "== G-22 底本差の標本(判定線 30 対以上・測定前に宣言) =="
puts "  同一作家・同一題名の組 : #{groups.size} 組 / 対 #{within.length}"
g22 = within.length >= 30
puts(g22 ? "  → 合格" : "  → 標本不足。G-21 は判定不能とする")
puts
puts "== G-21 底本差 vs 作家差(判定線 異版差 < 作家差 × 0.5・測定前に宣言) =="
if g22
  puts "  異版間のルビ密度差 中央値 : #{'%.2f' % mw} 点"
  puts "  作家間のルビ密度差 中央値 : #{'%.2f' % mb} 点(#{between.length} 対)"
  puts "  比 #{'%.3f' % (mw / mb)}"
  g21 = mw < mb * 0.5
  puts(g21 ? "  → 合格。第一軸は主に作家を測っている" :
             "  → 失格。第一軸は版元の方針を強く含む。軸の名前と説明を改める")
  puts "  差の大きい組 上位 5:"
  groups.map { |k, ws|
    [k, ws.map { |w| w[:density] }.minmax]
  }.sort_by { |_, mm| -(mm[1] - mm[0]) }.first(5).each do |(au, ti), (lo, hi)|
    puts format("    %-12s 『%s』 %.1f 〜 %.1f", au, ti[0, 16], lo, hi)
  end
else
  g21 = nil
  puts "  判定不能(G-22 が落ちている)"
end

File.write("#{OUT}/gaiji_hondai.json", JSON.pretty_generate(
  gaiji: gaiji, gaiji_rate: rate, level_rate: lvl_rate,
  gaiji_chars: gaiji_chars.sort_by { |_, c| -c }.first(200).to_h,
  hondai: { groups: groups.size, pairs: within.length,
            median_within: mw, median_between: mb },
  gates: { g03a_pass: g03a, g03b_pass: g03b, g21_pass: g21, g22_pass: g22 }
))
exit(g03a && g03b && g22 && g21 ? 0 : 1)
