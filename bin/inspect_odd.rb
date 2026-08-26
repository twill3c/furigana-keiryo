# frozen_string_literal: true

# G-02 の「未知パターン」の中身を目で見るための調査用スクリプト。
# 件数だけ出して中身を見ないと、パーサの取りこぼしを地の文として握りつぶすことになる。
#
#   ruby bin/inspect_odd.rb 000351 000327 000455

require_relative "../lib/aozora/notation"
require_relative "../lib/aozora/document"

N = Aozora::Notation

ARGV.each do |id|
  raw = File.read(File.expand_path("../../aozora-sakuin/data/raw/#{id}.txt", __dir__), encoding: "UTF-8")
  body = Aozora::Document.split(raw)
  N.parse(body.text).each do |n|
    next unless n.is_a?(N::Text)

    n.raw.scan(/.{0,16}[《｜].{0,16}/m) do |ctx|
      puts "#{id}: #{ctx.gsub("\n", "⏎")}"
    end
  end
end
