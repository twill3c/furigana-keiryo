# frozen_string_literal: true

require_relative "notation"

module Aozora
  # 読みの在庫と、多字基底の分解(SPEC F-14 / G-07)。
  #
  # 熟字訓・当て字は「難読だから振る」のではなく「振らないと読みが一意に定まらない」。
  # 今宵《こよい》 の こよい は 今《こん・いま》 と 宵《よい》 の連結では作れない。
  # 一方 女子挺身隊《じょしていしんたい》 は 女《じょ》子《し》挺《てい》身《しん》隊《たい》
  # に分解できる。**分解できるか否か**を判定に使う。
  #
  # 辞書は持たない。コーパスの**単字**基底のルビ(山《やま》)だけを集めて在庫を作る。
  #
  # 循環の禁止(G-20 / HC-045): 在庫の入力は単字基底のみである。
  # 判定対象である多字基底を在庫に入れてはならない。入れると
  # 今宵《こよい》 から 今宵→こよい が在庫に入り、分解が自明に成功して、
  # 緑のまま何も検査していないことになる。
  module Reading
    KANJI = /[\p{Han}々〆ヵヶ]/
    KANA  = /\A[\p{Hiragana}ー]+\z/

    # 連濁: 後続要素の頭が濁る。促音便: 前要素の末尾が っ になる。
    RENDAKU = {
      "か" => "が", "き" => "ぎ", "く" => "ぐ", "け" => "げ", "こ" => "ご",
      "さ" => "ざ", "し" => "じ", "す" => "ず", "せ" => "ぜ", "そ" => "ぞ",
      "た" => "だ", "ち" => "ぢ", "つ" => "づ", "て" => "で", "と" => "ど",
      "は" => "ば", "ひ" => "び", "ふ" => "ぶ", "へ" => "べ", "ほ" => "ぼ"
    }.freeze
    HANDAKU = { "は" => "ぱ", "ひ" => "ぴ", "ふ" => "ぷ", "へ" => "ぺ", "ほ" => "ぽ" }.freeze
    SOKUON = %w[く つ ち き].freeze

    module_function

    # 解析木の列 → 漢字 1 字ごとの読みの集合。単字基底のみを採る(G-20)。
    def inventory(nodes_enum)
      inv = Hash.new { |h, k| h[k] = Hash.new(0) }
      nodes_enum.each do |nodes|
        nodes.each do |n|
          next unless n.is_a?(Notation::Ruby)
          next unless n.base.length == 1 && n.base.match?(KANJI)
          next unless n.reading.match?(KANA)

          inv[n.base][n.reading] += 1
        end
      end
      inv
    end

    # 出現が少ない読みは誤り・特殊読みなので落とす。
    def prune(inv, min: 2)
      inv.transform_values { |h| h.select { |_, c| c >= min }.keys.to_set }
         .reject { |_, s| s.empty? }
    end

    # 基底の読みが構成漢字の読みの連結に分解できるか。
    # 分解できれば true(通常の音訓)、できなければ false(熟字訓・当て字)。
    def decomposable?(base, reading, inv)
      chars = base.each_char.to_a
      return false unless chars.all? { |c| c.match?(KANJI) }
      return false unless reading.match?(KANA)
      # 在庫に無い字が混じる基底は判定不能。判定不能は「分解できない」と扱わない。
      return true if chars.any? { |c| inv[c].nil? }

      walk(chars, 0, reading, 0, inv)
    end

    # 在庫に無い字を含み、判定できない基底かどうか。
    def undecidable?(base, inv)
      base.each_char.any? { |c| c.match?(KANJI) && inv[c].nil? }
    end

    # chars[i..] が reading[j..] を食い切れるか。前から順に貪欲でなく総当たりで見る。
    def walk(chars, i, reading, j, inv)
      return j == reading.length if i == chars.length

      last = i == chars.length - 1
      inv[chars[i]].each do |r|
        variants(r, first: i.zero?, last: last).each do |v|
          next unless reading[j, v.length] == v

          return true if walk(chars, i + 1, reading, j + v.length, inv)
        end
      end
      false
    end

    # 音便の異形。先頭要素は連濁しない。末尾要素は促音便を起こさない。
    def variants(r, first:, last:)
      out = [r]
      unless first
        head = r[0]
        out << (RENDAKU[head] + r[1..]) if RENDAKU[head]
        out << (HANDAKU[head] + r[1..]) if HANDAKU[head]
      end
      out << "#{r[0..-2]}っ" if !last && r.length >= 2 && SOKUON.include?(r[-1])
      out
    end
  end
end
