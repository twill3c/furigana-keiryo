# frozen_string_literal: true

require_relative "notation"
require_relative "gaiji"

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

    # 解析木 → Counts。注記の**説明文**は作者の文章ではないので数えない。
    #
    # 外字注記は基底になりうる(※［＃「亞＋鳥」…］《からす》)。この注記を
    # 生の文字列のまま数えると、字形の説明「亞＋鳥」と定型句「第4水準」の漢字が
    # そのままルビ付き漢字として計上される。実測 2026-08-27: 外字基底のルビ 8,932 件から
    # 47,421 字が混入し、第 7,269 / 水 7,256 / 準 7,174 と定型句が上位を占めていた。
    # 注記は**それが表す 1 文字**に開いてから数える(SPEC F-15 / G-03)。
    def count(nodes)
      c = Counts.empty
      nodes.each do |n|
        case n
        when Notation::Text
          n.raw.each_char { |ch| c.plain[ch] += 1 if ch.match?(KANJI) }
        when Notation::Gaiji
          ch = Gaiji.map(n.raw)&.char
          c.plain[ch] += 1 if ch&.match?(KANJI)
        when Notation::Ruby
          bucket = duty?(n) ? c.duty : c.rubied
          base_chars(n.base).each { |ch| bucket[ch] += 1 if ch.match?(KANJI) }
        end
      end
      c
    end

    # 基底の文字列を「実際の文字の並び」に開く。
    # 埋め込まれた外字注記は写像した 1 文字に、写像できなければ捨てる。
    def base_chars(base)
      return base.each_char.to_a unless base.include?("［＃")

      out = []
      rest = base
      while (i = rest.index(/※?［＃/))
        out.concat(rest[0, i].each_char.to_a)
        rest = rest[i..]
        note, rest = peel(rest)
        ch = Gaiji.map(note)&.char
        out << ch if ch
      end
      out.concat(rest.each_char.to_a)
      out
    end

    # 先頭の注記を 1 件、括弧の深さを数えて切り出す(注記は入れ子になる)。
    def peel(s)
      depth = 0
      s.each_char.with_index do |ch, i|
        depth += 1 if ch == "［"
        if ch == "］"
          depth -= 1
          return [s[0..i], s[(i + 1)..] || ""] if depth.zero?
        end
      end
      [s, ""]
    end

    # 読みにカタカナを含むルビは、難読ゆえではなく読みが定まらないゆえに振られている。
    def duty?(ruby) = ruby.reading.match?(KATAKANA)
  end
end
