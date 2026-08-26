# frozen_string_literal: true

require "set"
require_relative "notation"

module Aozora
  # 反復率(SPEC F-11)。第二軸「記憶への信用」の材料。
  #
  # 作品の中で一度でもルビが振られた基底語 B について、B の**2 回目以降の出現**を数え、
  # そのうち何回ルビが再度振られたかを見る。
  #
  #   反復率 高 … 何度出てきても振り直す = 読者の記憶を信用していない
  #   反復率 低 … 一度教えたら放っておく = 読者の記憶を信用している
  #
  # 初出を分母から外すのが要点である。初出にルビを振るのは慣行なので、
  # 含めると全作家が同じ値に寄り、軸が潰れる(判定前に決めた規則・SPEC 4 節)。
  #
  # この母集団は「その作家が振ると決めた語の再出現」に限られる。総ルビ傾向が
  # どれだけ高くても低くても、再出現で振り直すかどうかは別に選べる。
  # **統計的な統制ではなく、定義によって交絡から独立させている**(G-10)。
  #
  # 単位は作品である。読者は一作を通して読むのであって、全集を通読しない。
  module Repeat
    KANJI_ONLY = /\A[\p{Han}々〆ヵヶ]+\z/
    KATAKANA = /\p{Katakana}/

    Tally = Struct.new(:repeats, :re_rubied) do
      def self.empty = new(0, 0)
      def merge!(o) = (self.repeats += o.repeats; self.re_rubied += o.re_rubied; self)
      def rate = repeats.zero? ? nil : re_rubied.to_f / repeats
    end

    module_function

    # 解析木 1 作 → Tally。
    def count(nodes)
      plain, spans = flatten(nodes)
      bases = ruby_bases(nodes)
      return Tally.empty if bases.empty?

      # Ruby の String は UTF-8 では文字単位の添字が O(n) なので、
      # plain[i] を回すと全体が O(n^2) になる(実測 2026-08-27: 400 作が 6 分でも終わらず)。
      # 文字配列に落として O(1) の添字にする。
      chars = plain.chars
      t = Tally.empty
      # 長さ別に Set で引く。Array#include? は O(n) で、5,000 作では終わらない
      # (実測 2026-08-27: 400 作で 5 分を超えた)。
      by_len = bases.group_by(&:length).transform_values(&:to_set)
      heads = bases.map { |b| b[0] }.to_set
      lens = by_len.keys.sort.reverse   # 長い基底を優先

      seen = Hash.new(0)
      i = 0
      n = chars.length
      while i < n
        unless heads.include?(chars[i])
          i += 1
          next
        end
        # 長い基底を優先する。短い基底が長い基底の一部を食うのを防ぐ。
        hit = lens.find { |l| by_len[l].include?(chars[i, l].join) }
        if hit.nil?
          i += 1
          next
        end
        b = chars[i, hit].join
        seen[b] += 1
        if seen[b] > 1   # 初出は数えない
          t.repeats += 1
          t.re_rubied += 1 if spans.include?(i)
        end
        i += hit
      end
      t
    end

    # 解析木 → [本文(注記を除く), ルビが始まる位置の集合]
    def flatten(nodes)
      plain = +""
      spans = Set.new
      nodes.each do |n|
        case n
        when Notation::Text then plain << n.raw
        when Notation::Ruby
          spans << plain.length
          plain << n.base
        end
      end
      [plain, spans]
    end

    # 計量対象になる基底語。漢字のみ・2 字以上・義務ルビでないもの。
    # 1 字の基底を外すのは、頻出漢字が偶然一致して反復を水増しするため。
    def ruby_bases(nodes)
      nodes.filter_map { |n|
        next unless n.is_a?(Notation::Ruby)
        next if n.reading.match?(KATAKANA)      # 義務ルビ(当て字・外来語)
        next unless n.base.match?(KANJI_ONLY)
        next if n.base.length < 2

        n.base
      }.uniq
    end
  end
end
