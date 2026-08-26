# frozen_string_literal: true

# out/axes.json から偏相関を出す(事後診断・ゲートではない)。
# 二つの第二軸候補が続けて総ルビ傾向に潰れたので、「潰れ方」の構造を見る。

require "json"
require_relative "../lib/aozora/axes"

A = Aozora::Axes
j = JSON.parse(File.read(File.expand_path("../out/axes.json", __dir__), encoding: "UTF-8"))
rows = j["authors"].select { |r|
  r["kindness"] && r["memory"] && r["trust"] &&
    r["hard_n"] >= j["min_n"] && r["easy_n"] >= j["min_n"] && r["repeats"] >= 200
}

k = rows.map { |r| r["kindness"] }
m = rows.map { |r| r["memory"] }
t = rows.map { |r| r["trust"] }
d = rows.map { |r| r["density"] }

def partial(r_xy, r_xz, r_yz)
  (r_xy - r_xz * r_yz) / Math.sqrt((1 - r_xz**2) * (1 - r_yz**2))
end

r_km = A.correlation(k, m)
r_kd = A.correlation(k, d)
r_md = A.correlation(m, d)
r_td = A.correlation(t, d)

puts "同一標本 #{rows.length} 作家"
puts
puts "== 素の相関 =="
puts "優しさ × 記憶       : #{'%+.3f' % r_km}"
puts "優しさ × 総ルビ傾向 : #{'%+.3f' % r_kd}"
puts "記憶   × 総ルビ傾向 : #{'%+.3f' % r_md}"
puts "信用   × 総ルビ傾向 : #{'%+.3f' % r_td}   (loop_002 の第二軸候補)"
puts
puts "== 総ルビ傾向を統制した偏相関 =="
puts "優しさ × 記憶       : #{'%+.3f' % partial(r_km, r_kd, r_md)}"
puts
puts "== 読み方 =="
puts "総ルビ傾向を知ってしまえば、優しさと記憶は互いにほとんど何も語らない。"
puts "つまり構造は「二つの軸」ではなく「支配的な 1 次元 + 弱い残差」である。"
