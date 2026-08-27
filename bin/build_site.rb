# frozen_string_literal: true

# 配信用データを組む(SPEC F-07 / F-09 / N-04)。
#
#   ruby bin/build_site.rb
#
# 出力は out/site/data.json ひとつ。Vercel は静的配信のみで、
# サーバ側処理も運用コストも持たない。
#
# 本文の抜粋は**その場で分類し直す**。画面で色分けするルビの三分類は
# 計量に使ったものと同じ経路から出さなければ、図だけが嘘になる。

require "json"
require "set"
require_relative "../lib/aozora/corpus"
require_relative "../lib/aozora/notation"
require_relative "../lib/aozora/tally"
require_relative "../lib/aozora/axes"

C = Aozora::Corpus
N = Aozora::Notation
T = Aozora::Tally
A = Aozora::Axes

OUT = File.expand_path("../out", __dir__)
three = JSON.parse(File.read("#{OUT}/three_axes.json", encoding: "UTF-8"))
sou   = JSON.parse(File.read("#{OUT}/sourubi.json", encoding: "UTF-8"))

# 抜粋する作品。三軸の両端と、総ルビの対を見せる。
# 第二軸(難所への偏り)の両端から実際に選んだ作品。
# 上位 = 自分の総ルビ量から予測されるより難読字に偏って振る作家。
SAMPLES = %w[003328 000201 051918 058400].freeze
# 総ルビの証拠として並べる対(同じ話の別訳)。
PAIR = sou["works"].select { |w| w["title"].to_s.include?("ヒルの子") || w["title"].to_s.include?("家鴨の子") }

# ── 帯は sourubi.rb と同じ全作家合算で作る(画面と計量の経路を一致させる) ──
# 全作品の走査に 13 分かかるので頻度表を out/global_freq.json に残す。
# 画面の調整のたびに 13 分待つと、調整そのものをやめてしまう。
CACHE = "#{OUT}/global_freq.json"
global = if File.exist?(CACHE)
           warn "頻度表をキャッシュから読む(#{CACHE})"
           JSON.parse(File.read(CACHE, encoding: "UTF-8"))
         else
           warn "帯を作る(全作品走査・約 13 分)"
           g = Hash.new(0)
           C.works.each_with_index do |w, i|
             nodes = C.parse(w.id)
             next if nodes.nil?

             A.frequency(T.count(nodes)).each { |ch, n| g[ch] += n }
             warn "  #{i + 1}/#{C.works.length}" if ((i + 1) % 1000).zero?
           end
           File.write(CACHE, JSON.generate(g))
           g
         end
easy, hard = A.bands(global)

# ── 抜粋を分類する ───────────────────────────────────────────
def classify(ruby, easy, hard)
  return "duty" if T.duty?(ruby)
  return "other" unless ruby.base.match?(T::KANJI)

  chars = ruby.base.each_char.select { |c| c.match?(T::KANJI) }
  return "help" if chars.any? { |c| hard.include?(c) }
  return "over" if chars.all? { |c| easy.include?(c) }

  "mid"
end

samples = SAMPLES.filter_map do |id|
  w = C.works.find { |x| x.id == id }
  nodes = C.parse(id)
  next if w.nil? || nodes.nil?

  # 先頭から 700 字ぶんの節点だけ取る。切り口がルビの途中に来ないよう節点境界で切る。
  taken = []
  len = 0
  nodes.each do |n|
    break if len > 700

    case n
    when N::Text  then (taken << { t: "text", s: n.raw }; len += n.raw.length)
    when N::Ruby  then (taken << { t: "ruby", b: n.base, r: n.reading, k: classify(n, easy, hard) }
                        len += n.base.length)
    end
  end
  { id: id, title: w.title, author: w.author, kana: w.kana, nodes: taken }
end

# ── p_easy の分布(20 区間) ───────────────────────────────────
bins = Array.new(20, 0)
sou["works"].each { |w| bins[(w["p_easy"] * 20).floor.clamp(0, 19)] += 1 }

# ── 作家表 ───────────────────────────────────────────────────
authors = three["authors"].map { |a|
  { n: a["author"], y: a["born"], w: a["works"], k: a["kana"],
    d: a["full"]["density"].round(2),
    kind: a["full"]["kindness"].round(1), mem: a["full"]["memory"].round(1),
    rh: a["resid_hard"].round(2), rr: a["resid_repeat"].round(2) }
}

data = {
  generated: "2026-08-27",
  corpus: { works: three["works_scanned"], sourubi_excluded: three["sourubi_excluded"],
            authors_total: 921, authors_measured: three["authors_full"],
            authors_split: three["authors_split"],
            undecidable: sou["works_scanned"] - sou["measured"] },
  gates: three["gates"].merge(sou["gates"]),
  bands: { easy: easy.size, hard: hard.size,
           easy_head: global.sort_by { |c, n| [-n, c] }.first(40).map(&:first).join,
           hard_tail: hard.to_a.sort.first(40).join },
  authors: authors,
  hist: bins,
  pair: PAIR.map { |w| { title: w["title"], author: w["author"], p: w["p_easy"].round(3) } },
  samples: samples
}

Dir.mkdir("#{OUT}/site") unless Dir.exist?("#{OUT}/site")
File.write("#{OUT}/site/data.json", JSON.generate(data))
warn "out/site/data.json #{(File.size("#{OUT}/site/data.json") / 1024.0).round} KB"
warn "  作家 #{authors.length} / 抜粋 #{samples.length} / 対 #{PAIR.length}"
