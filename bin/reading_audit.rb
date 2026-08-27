# frozen_string_literal: true

# 判定器の実データでの精度を見積もる。
#
#   ruby bin/reading_audit.rb
#
# 手作業の正解セット(G-18)は私が選んだ 40 件であり、
# **選んだ時点で当たりやすい例に偏っている**。実データでの精度は、
# 判定結果から無作為に抜いて目で見るのが唯一の見積り方である。
#
# あわせて在庫の穴を数える。誤検出 訣別《けつべつ》・全盛《ぜんせい》 の形から、
# 「音読みは単字ルビとして現れにくい」という系統的な偏りが疑われる。
# 全《ぜん》 に単独でルビを振る書き手はいないので、在庫に ぜん が入らない。

require "json"
require "set"
require_relative "../lib/aozora/reading"

R = Aozora::Reading
OUT = File.expand_path("../out", __dir__)
pairs = JSON.parse(File.read("#{OUT}/ruby_pairs.json", encoding: "UTF-8"))
inv = R.prune(
  pairs["single_a"].merge(pairs["single_b"]) { |_, a, b| a.merge(b) { |_, x, y| x + y } },
  min: 2
)
multi = pairs["multi"]

# ── 判定結果を並べる ─────────────────────────────────────────
juku = []
multi.each do |b, hs|
  hs.each do |r, c|
    next if R.undecidable?(b, inv)

    juku << [b, r, c] unless R.decomposable?(b, r, inv)
  end
end

# 無作為抽出。seed 固定で再実行しても同じ標本を見る。
rng = Random.new(20_260_827)
sample = juku.sample(40, random: rng)

puts "== 熟字訓と判定されたものからの無作為標本 40 件 =="
puts "  (基底×読みの種から一様に抜いた。実例数の重みはかけていない)"
sample.each_slice(2) do |row|
  puts "  " + row.map { |b, r, c| format("%-16s %5d 件", "#{b}《#{r}》", c) }.join(" | ")
end

# ── 在庫の穴 ─────────────────────────────────────────────────
puts
puts "== 在庫の穴(G-18 の誤検出 3 件を分解し直す) =="
[["訣別", "けつべつ"], ["全盛", "ぜんせい"], ["熾熱燈", "しねつとう"]].each do |b, r|
  have = b.each_char.map { |c| "#{c}:#{(inv[c] || Set[]).to_a.first(4).join('・')}" }
  puts "  #{b}《#{r}》"
  puts "    在庫 → #{have.join(' / ')}"
end

freq = JSON.parse(File.read("#{OUT}/global_freq.json", encoding: "UTF-8"))
top = freq.sort_by { |_, n| -n }.first(500).map(&:first)
no_inv = top.count { |c| inv[c].nil? }
few = top.count { |c| inv[c] && inv[c].size <= 2 }
puts
puts "== 在庫の被覆(頻出漢字 上位 500 字) =="
puts "  在庫に無い        : #{no_inv} 字"
puts "  読みが 2 通り以下 : #{few} 字"
puts "  → 頻出字ほど単独でルビが振られないので、在庫が薄くなる"

File.write("#{OUT}/reading_audit.json", JSON.pretty_generate(
  sample: sample.map { |b, r, c| { base: b, reading: r, count: c } },
  top500_missing: no_inv, top500_thin: few
))
