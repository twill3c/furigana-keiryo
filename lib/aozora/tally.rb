# frozen_string_literal: true

require_relative "notation"

module Aozora
  # 本文 1 作を漢字の出現単位で数える(SPEC F-05)。
  #
  # 数える単位は**字種ではなく出現**である。読者はその字に出会うたびに助けられるか
  # 放っておかれるかするので、「その字を何回使ったか」ではなく「何回出会ったか」で測る。
  #
  # 漢字 1 出現につき、次のいずれか 1 つに必ず分類される:
  #
  #   plain   ルビが無い     … 分母に入る。ルビ無しとして数える
  #   rubied  ルビが有る     … 分母と分子に入る
  #   duty    義務ルビが有る … **両方から外す**(SPEC F-05 の三分類の「義務」)
  #
  # 義務ルビは「難読だから振る」のではなく「振らないと読みが一意に定まらない」もの。
  # 骨牌《カルタ》 玻璃《ガラス》 のように読みがカタカナのものを、本ループでは
  # 義務とみなす。熟字訓(今宵《こよい》)は取れていない — G-07 は保留のままである。
  module Tally
    KANJI = /[\p{Han}々〆ヵヶ]/
    KATAKANA = /\p{Katakana}/

    Counts = Struct.new(:plain, :rubied, :duty) do
      def self.empty = new(Hash.new(0), Hash.new(0), Hash.new(0))

      def merge!(other)
        %i[plain rubied duty].each do |k|
          other[k].each { |c, n| self[k][c] += n }
        end
        self
      end

      def total_chars = plain.values.sum + rubied.values.sum + duty.values.sum
    end

    module_function

    # 解析木 → Counts。注記(Annot / Gaiji)の中身は作者の文章ではないので数えない。
    def count(nodes)
      c = Counts.empty
      nodes.each do |n|
        case n
        when Notation::Text
          n.raw.each_char { |ch| c.plain[ch] += 1 if ch.match?(KANJI) }
        when Notation::Ruby
          bucket = duty?(n) ? c.duty : c.rubied
          n.base.each_char { |ch| bucket[ch] += 1 if ch.match?(KANJI) }
        end
      end
      c
    end

    # 読みにカタカナを含むルビは、難読ゆえではなく読みが定まらないゆえに振られている。
    def duty?(ruby) = ruby.reading.match?(KATAKANA)
  end
end
