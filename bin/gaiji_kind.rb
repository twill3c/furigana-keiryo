# frozen_string_literal: true

# 写像した外字のうち、実際に漢字はどれだけか。
# 「外字は定義上めずらしい字であり、そのほとんどが難読帯に属する」という
# SPEC の前提(loop_008 で書いた)が正しいかを確かめる。前提の検算である。

require "json"
OUT = File.expand_path("../out", __dir__)
j = JSON.parse(File.read("#{OUT}/gaiji_hondai.json", encoding: "UTF-8"))
chars = j["gaiji_chars"]

kanji, other = chars.partition { |ch, _| ch.match?(/\p{Han}/) }
kn = kanji.sum { |_, c| c }
on = other.sum { |_, c| c }
puts "上位 200 字の実例 #{kn + on} 件"
puts "  漢字     : #{kanji.size} 字 / #{kn} 件 (#{'%.1f' % (kn * 100.0 / (kn + on))} %)"
puts "  漢字以外 : #{other.size} 字 / #{on} 件 (#{'%.1f' % (on * 100.0 / (kn + on))} %)"
puts
puts "  漢字以外の上位 10: " + other.sort_by { |_, c| -c }.first(10).map { |ch, c| "#{ch}(#{c})" }.join(" ")
puts "  漢字の上位 10    : " + kanji.sort_by { |_, c| -c }.first(10).map { |ch, c| "#{ch}(#{c})" }.join(" ")
