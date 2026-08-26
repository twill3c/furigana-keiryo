# frozen_string_literal: true

require "json"
require "csv"
require_relative "notation"
require_relative "document"

module Aozora
  # 作品と作家の台帳、および本文の走査(SPEC F-04 の入力側)。
  #
  # コーパスは aozora-sakuin の既取得分をそのまま使う。再取得しない(SPEC N-02)。
  # 刊行年は台帳に無いため、**作家の生年**を世代の代理として使う(G-06)。
  # 生年は青空文庫の人物リストから取る。作品の刊行年ではないので、
  # 「その作家がいつの人か」以上の精度を求めてはならない。
  module Corpus
    DATA = File.expand_path("../../../aozora-sakuin/data", __dir__)

    Work = Struct.new(:id, :title, :author, :kana, :ndc, :born, keyword_init: true)

    module_function

    def works
      @works ||= begin
        born = birth_years
        JSON.parse(File.read(File.join(DATA, "works.json"), encoding: "UTF-8"))["works"]
            .map { |w|
              Work.new(id: w["id"], title: w["title"], author: w["author"],
                       kana: w["kana"], ndc: w["ndc"], born: born[w["id"]])
            }
      end
    end

    # 作品ID → 作家の生年(西暦)。人物リストの 生年月日 は "1872-05-02" 形式。
    def birth_years
      path = File.join(DATA, "index_cache", "list_person_all_extended_utf8.csv")
      out = {}
      # 人物リストは規格上壊れている(実測 2026-08-27): レコード区切りは CRLF だが、
      # 引用符の外に生の LF が入る欄がある。Python の csv は黙って通すが Ruby は落ちる。
      # レコードを CRLF で切り、欄内の LF を空白に潰してから 1 行ずつ解析する。
      # Windows のテキストモードは CRLF を LF に潰すので、rb で読まないと区切りが消える。
      File.read(path, mode: "rb:bom|utf-8").split("\r\n").each do |line|
        next if line.empty?

        row = begin
          CSV.parse_line(line.tr("\n", " "), liberal_parsing: true)
        rescue CSV::MalformedCSVError
          next
        end
        next if row.nil? || row[0] == "作品ID"

        y = row[24].to_s[/\A(\d{4})/, 1]
        out[row[0]] = y.to_i if y
      end
      out
    end

    # 本文を解析木にして返す。取得できない作品は nil。
    def parse(id)
      path = File.join(DATA, "raw", "#{id}.txt")
      return nil unless File.exist?(path)

      Notation.parse(Document.split(File.read(path, encoding: "UTF-8")).text)
    end

    # 生年から世代帯を決める。帯の境界は明治・大正・昭和の書き手の交替におおむね対応する。
    # 帯は「同時代の読者にとっての難読度」を作るためのものであり、精密な区分ではない。
    def cohort(born)
      return :unknown if born.nil?
      return :c1 if born <= 1865   # 幕末生まれ(鴎外 1862・漱石 1867 の直前)
      return :c2 if born <= 1885   # 明治前期生まれ(一葉 1872・漱石 1867)
      return :c3 if born <= 1905   # 明治後期生まれ

      :c4                          # 明治末〜大正生まれ(安吾 1906)
    end
  end
end
