# frozen_string_literal: true

# 人物リストは 1 作品につき複数行(著者・訳者・編者…)を持つ。
# 作品ID をキーに素朴に取り込むと、最後の行(多くは訳者)の生年で上書きされる。
# 紫式部『源氏物語』の生年が 1878(與謝野晶子)になっていないかを確かめる。

require "csv"

path = File.expand_path("../../aozora-sakuin/data/index_cache/list_person_all_extended_utf8.csv", __dir__)
rows = Hash.new { |h, k| h[k] = [] }
File.read(path, mode: "rb:bom|utf-8").split("\r\n").each do |line|
  next if line.empty?

  r = begin
    CSV.parse_line(line.tr("\n", " "), liberal_parsing: true)
  rescue CSV::MalformedCSVError
    next
  end
  next if r.nil? || r[0] == "作品ID"

  rows[r[0]] << { name: "#{r[15]}#{r[16]}", born: r[24].to_s[/\A(\d{4})/, 1], role: r[23] }
end

multi = rows.count { |_, v| v.length > 1 }
puts "作品            : #{rows.size}"
puts "人物行が複数の作品: #{multi}(#{'%.1f' % (multi * 100.0 / rows.size)} %)"
puts
ARGV.each do |id|
  puts "#{id}:"
  rows[id].each { |p| puts "  #{p[:name]}(#{p[:born] || '–'}) 役割=#{p[:role]}" }
end
