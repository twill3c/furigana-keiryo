# frozen_string_literal: true

# G-03c 混入を直したことで作家の順位がどれだけ動いたか。
#
# 判定線 > 0.95(測定前に宣言・commit 412e8a2)。
# 直した効果が「無かった」ことを示すのではない。**直しても結論が変わらない**ことを
# 確かめる。大きく動くなら、公開済みの数値は撤回して測り直す話になる。

require "json"
require_relative "../lib/aozora/axes"

OUT = File.expand_path("../out", __dir__)
before = JSON.parse(File.read("#{OUT}/three_axes_before_gaiji.json", encoding: "UTF-8"))["authors"]
after  = JSON.parse(File.read("#{OUT}/three_axes.json", encoding: "UTF-8"))["authors"]

b = before.to_h { |a| [a["author"], a] }
common = after.select { |a| b.key?(a["author"]) }
puts "共通の作家: #{common.length}(前 #{before.length} / 後 #{after.length})"

def spearman(xs, ys)
  rank = lambda { |v| v.each_with_index.sort_by { |x, _| x }.each_with_index
                       .to_h { |(_, i), r| [i, r.to_f] }.sort.map(&:last) }
  Aozora::Axes.correlation(rank.call(xs), rank.call(ys))
end

%w[resid_hard resid_repeat].each do |k|
  x = common.map { |a| b[a["author"]][k] }
  y = common.map { |a| a[k] }
  moved = x.zip(y).map { |p, q| (p - q).abs }
  puts
  puts "== #{k} =="
  puts "  ピアソン相関   : #{'%.4f' % Aozora::Axes.correlation(x, y)}"
  puts "  スピアマン順位 : #{'%.4f' % spearman(x, y)}"
  puts "  値のずれ 中央値: #{'%.3f' % moved.sort[moved.length / 2]} / 最大 #{'%.3f' % moved.max}"
end

d = common.map { |a| [b[a["author"]]["full"]["density"], a["full"]["density"]] }
puts
puts "== 総ルビ傾向 =="
puts "  相関 #{'%.4f' % Aozora::Axes.correlation(d.map(&:first), d.map(&:last))}"
puts "  最も動いた 5 名:"
common.map { |a| [a["author"], (b[a["author"]]["full"]["density"] - a["full"]["density"]).abs,
                  b[a["author"]]["full"]["density"], a["full"]["density"]] }
      .sort_by { |x| -x[1] }.first(5)
      .each { |n, dd, o, w| puts format("    %-14s %.2f → %.2f (差 %.2f)", n, o, w, dd) }
