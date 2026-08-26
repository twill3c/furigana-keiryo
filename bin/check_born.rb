# frozen_string_literal: true

# 生年の結合率を検算する。結合できていないのに世代帯で較正すると、
# 全員が :unknown に落ちて G-06 が「一致 r = 1.000」という空虚な合格を返す。
require_relative "../lib/aozora/corpus"

b = Aozora::Corpus.birth_years
w = Aozora::Corpus.works
hit = w.count { |x| x.born }
puts "人物リストから引けた作品ID : #{b.size}"
puts "works.json との結合        : #{hit} / #{w.size}(#{'%.1f' % (hit * 100.0 / w.size)} %)"
puts "世代帯の分布               :"
w.group_by { |x| Aozora::Corpus.cohort(x.born) }
 .sort_by { |k, _| k.to_s }
 .each { |k, v| puts "  #{k}: #{v.size}" }
puts "例 : " + w.first(4).map { |x| "#{x.author}(#{x.born || '–'})" }.join(" / ")
