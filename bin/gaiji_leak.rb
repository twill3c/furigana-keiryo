# frozen_string_literal: true

# 外字注記の説明文が計量に混入している規模を測る。
require_relative "../lib/aozora/corpus"
require_relative "../lib/aozora/notation"

C = Aozora::Corpus
N = Aozora::Notation
GAIJI_BASE = /\A※?［＃/

n_ruby = 0
n_gaiji_ruby = 0
leaked = Hash.new(0)
C.works.each_with_index do |w, i|
  nodes = C.parse(w.id)
  next if nodes.nil?

  nodes.each do |x|
    next unless x.is_a?(N::Ruby)

    n_ruby += 1
    next unless x.base.match?(GAIJI_BASE)

    n_gaiji_ruby += 1
    x.base.each_char { |ch| leaked[ch] += 1 if ch.match?(/[\p{Han}々〆ヵヶ]/) }
  end
  warn "  #{i + 1}/#{C.works.length}" if ((i + 1) % 1000).zero?
end
tot = leaked.values.sum
puts "ルビ総数           : #{n_ruby}"
puts "外字が基底のルビ   : #{n_gaiji_ruby}(#{'%.2f' % (n_gaiji_ruby * 100.0 / n_ruby)} %)"
puts "混入した漢字の延べ : #{tot}"
puts "混入の上位 12      :"
leaked.sort_by { |_, c| -c }.first(12).each_slice(6) do |row|
  puts "  " + row.map { |ch, c| "#{ch} #{c}" }.join(" / ")
end
