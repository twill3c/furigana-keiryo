# frozen_string_literal: true

# O-01 往復検査を全作品で回す(SPEC G-01)。
# ここが通らないうちは、以後どんな計量値も信用してはならない。
#
#   ruby bin/roundtrip.rb [--limit N]

require "json"
require_relative "../lib/aozora/notation"
require_relative "../lib/aozora/document"

RAW = File.expand_path("../../aozora-sakuin/data/raw", __dir__)
N = Aozora::Notation

limit = (i = ARGV.index("--limit")) ? ARGV[i + 1].to_i : nil
files = Dir.children(RAW).select { |f| f.end_with?(".txt") }.sort
files = files.first(limit) if limit

stat = Hash.new(0)
mismatch = []
odd_guillemet = []   # 基底の取れない 《》 を持つ作品(G-02)
orphan_bar = []      # 対応する 《 が来ない ｜ を持つ作品(G-02)
kanji_residue = []   # 漢字基底なのにルビとして取れなかった作品(G-02 の失格条件)

files.each do |name|
  raw = File.read(File.join(RAW, name), encoding: "UTF-8")
  body = Aozora::Document.split(raw)
  nodes = N.parse(body.text)

  stat[:works] += 1
  stat[:legend] += 1 if body.had_legend
  stat[:chars] += body.text.length
  stat[:ruby] += nodes.count { |n| n.is_a?(N::Ruby) }
  stat[:bar]   += nodes.count { |n| n.is_a?(N::Ruby) && n.bar }
  stat[:gaiji] += nodes.count { |n| n.is_a?(N::Gaiji) }
  stat[:annot] += nodes.count { |n| n.is_a?(N::Annot) }

  # 基底の取れなかった 《》 と孤立 ｜ は Text 節点に残る。件数を必ず出す(G-02)。
  text = nodes.select { |n| n.is_a?(N::Text) }.map(&:raw).join
  if (c = text.count("《")).positive?
    stat[:odd_guillemet] += c
    odd_guillemet << [name, c]
    # G-02 の本体はこの述語である(HC-030: ゲートは閾値でなく述語で書く)。
    # 二軸の計量は漢字基底のルビしか使わない。残骸に漢字基底が混じっていなければ、
    # 残骸が何件あろうと計量値は損なわれない。混じっていたら件数に関係なく失格。
    kanji_left = text.scan(/([\p{Han}々〆ヵヶ])《/).flatten
    unless kanji_left.empty?
      stat[:kanji_residue] += kanji_left.length
      kanji_residue << [name, kanji_left.first(5).join(",")]
    end
  end
  if (c = text.count("｜")).positive?
    stat[:orphan_bar] += c
    orphan_bar << [name, c]
  end

  back = N.rebuild(nodes)
  if back == body.text
    stat[:pass] += 1
  else
    stat[:fail] += 1
    at = (0...[back.length, body.text.length].max).find { |i| back[i] != body.text[i] }
    mismatch << { file: name, at: at,
                  expected: body.text[[at - 20, 0].max, 50],
                  actual: back[[at - 20, 0].max, 50] }
  end
end

puts "== O-01 往復検査 =="
puts "作品        : #{stat[:works]}"
puts "一致        : #{stat[:pass]}"
puts "不一致      : #{stat[:fail]}"
puts "一致率      : #{'%.4f' % (stat[:pass] * 100.0 / stat[:works])} %"
puts
puts "== 内訳 =="
puts "本文字数    : #{stat[:chars]}"
puts "ルビ        : #{stat[:ruby]}(うち ｜ 明示 #{stat[:bar]})"
puts "外字注記    : #{stat[:gaiji]}"
puts "入力者注    : #{stat[:annot]}"
puts "凡例あり    : #{stat[:legend]} / #{stat[:works]}"
puts
puts "== G-02 未知パターン =="
puts "基底なし 《 : #{stat[:odd_guillemet]} 件 / #{odd_guillemet.length} 作"
puts "孤立 ｜     : #{stat[:orphan_bar]} 件 / #{orphan_bar.length} 作"

# HC-035: 残骸は件数で報告してはならない。件数だけだと比率の小ささを根拠に
# 全体を棄却してしまう。実例を前後文脈つきで出し、目で見て分類する。
def examples(list, mark, n = 6)
  list.sort_by { |_, c| -c }.first(n).each do |name, count|
    raw = File.read(File.join(RAW, name), encoding: "UTF-8")
    body = Aozora::Document.split(raw)
    ctx = N.parse(body.text).select { |x| x.is_a?(N::Text) }.map(&:raw).join
             .scan(/.{0,18}#{mark}.{0,18}/m).first
    puts "  #{name} (#{count} 件): #{ctx.to_s.gsub("\n", '⏎')}"
  end
end

puts "-- 実例(基底なし 《) --"
examples(odd_guillemet, "《")
puts "-- 実例(孤立 ｜) --"
examples(orphan_bar, "｜")
puts
puts "== G-02 述語: 残骸に漢字基底が無いこと =="
puts "漢字基底の取りこぼし : #{stat[:kanji_residue]} 件 / #{kanji_residue.length} 作"
kanji_residue.first(10).each { |f, k| puts "  #{f}: #{k}" }
puts kanji_residue.empty? ? "  → 合格。残骸はすべて非漢字基底であり、二軸の計量に影響しない" : "  → 失格。件数に関係なく計量値は無効"

unless mismatch.empty?
  puts
  puts "== 不一致の先頭 5 件 =="
  mismatch.first(5).each do |m|
    puts "  #{m[:file]} @#{m[:at]}"
    puts "    原文: #{m[:expected].inspect}"
    puts "    復元: #{m[:actual].inspect}"
  end
end

File.write(File.expand_path("../out/roundtrip.json", __dir__),
           JSON.pretty_generate(stat: stat, mismatch: mismatch.first(50)))
exit(stat[:fail].zero? && stat[:kanji_residue].zero? ? 0 : 1)
