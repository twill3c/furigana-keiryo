# frozen_string_literal: true

# 原文側の文脈をそのまま見る(パーサを通さない)。
#   ruby bin/inspect_raw.rb 000351 ざしきぎ

id, needle = ARGV
raw = File.read(File.expand_path("../../aozora-sakuin/data/raw/#{id}.txt", __dir__), encoding: "UTF-8")
raw.scan(/.{0,40}#{Regexp.escape(needle)}.{0,20}/m) do |ctx|
  puts ctx.gsub("\n", "⏎")
  puts "  codepoints: " + ctx.chars.first(45).map { |c| format("%s(U+%04X)", c, c.ord) }.last(18).join(" ")
end
