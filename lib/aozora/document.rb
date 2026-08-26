# frozen_string_literal: true

module Aozora
  # 生テキストから計量対象の本文を切り出す(SPEC F-03)。
  #
  # 凡例ブロックには 《》 と ｜ の**実例**が入っている:
  #
  #     《》：ルビ
  #     （例）端物《はもの》の
  #
  # ここを剥がさずに数えると、全作品に同じ偽のルビが数件ずつ乗る。
  # 本文切り出しは前処理ではなく、計量の一部である。
  module Document
    RULE   = /\A-{20,}\z/          # 凡例ブロックの区切り線
    COLOPHON = /\A底本[：:]/       # 奥付の開始

    Body = Struct.new(:text, :head_lines, :foot_lines, :had_legend)

    module_function

    def split(raw)
      lines = raw.split("\n", -1)
      first = body_begin(lines)
      last  = body_end(lines, first)
      Body.new(
        lines[first...last].join("\n").strip,
        first,
        lines.length - last,
        lines[0...first].any? { |l| l.match?(RULE) }
      )
    end

    # 本文の開始行。凡例ブロックがあればその閉じ線の次、無ければ表題ブロックの次。
    def body_begin(lines)
      rules = lines.each_index.select { |i| lines[i].match?(RULE) }
      # 区切り線は凡例の開閉で 2 本組。3 本以上ある作品は本文中の罫線なので先頭 2 本だけ見る。
      return rules[1] + 1 if rules.length >= 2 && rules[1] < 60

      # 凡例なし: 表題・著者名の塊(先頭の非空行の連続)を落とす。
      i = 0
      i += 1 while i < lines.length && !lines[i].strip.empty?
      i += 1 while i < lines.length && lines[i].strip.empty?
      i
    end

    # 本文の終了行(この行は含まない)。奥付が無ければ末尾。
    def body_end(lines, from)
      idx = (from...lines.length).find { |i| lines[i].match?(COLOPHON) }
      idx || lines.length
    end
  end
end
