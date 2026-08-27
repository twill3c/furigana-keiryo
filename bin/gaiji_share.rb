# frozen_string_literal: true

# 外字を算入したとき、難読帯がどれだけ増えるか。
# SPEC に「難読帯を系統的に過小評価している疑い」と書いた。その**大きさ**を測る。
# 疑いを書いたなら大きさを測る。大きさを測らずに直すと、直したことに満足して終わる。

require "json"
require "set"
require_relative "../lib/aozora/axes"
require_relative "../lib/aozora/gaiji"

OUT = File.expand_path("../out", __dir__)
freq = JSON.parse(File.read("#{OUT}/global_freq.json", encoding: "UTF-8"))
gj = JSON.parse(File.read("#{OUT}/gaiji_hondai.json", encoding: "UTF-8"))

easy, hard = Aozora::Axes.bands(freq)
total = freq.values.sum
hard_n = hard.sum { |c| freq[c] }

# 写像した外字のうち漢字のものだけ。〻 は反復記号なので別に数える。
kanji = gj["gaiji_chars"].select { |ch, _| ch.match?(/\p{Han}/) }
iter = kanji.select { |ch, _| ch == "〻" }.values.sum
real = kanji.reject { |ch, _| ch == "〻" }
real_n = real.values.sum
# 上位 200 字しか保存していないので、全体はこの比率で外挿する。
scale = gj["gaiji"]["mapped"].to_f / gj["gaiji_chars"].values.sum
est = (real_n * scale).round

puts "== 漢字の出現(本文全体) =="
puts "  総数     : #{total}"
puts "  難読帯   : #{hard_n}(#{'%.2f' % (hard_n * 100.0 / total)} %) / #{hard.size} 字"
puts
puts "== 写像した外字のうち漢字 =="
puts "  上位200字内の漢字 : #{real_n} 件(反復記号 〻 #{iter} 件は別)"
puts "  全体への外挿      : 約 #{est} 件"
puts
puts "== 算入したときの増分 =="
puts "  難読帯に対して : #{'%.3f' % (est * 100.0 / hard_n)} %"
puts "  漢字全体に対して : #{'%.4f' % (est * 100.0 / total)} %"
