# frozen_string_literal: true

module Aozora
  # 外字注記の写像(SPEC F-15 / G-03)。
  #
  #   ※［＃「亞＋鳥」、第4水準2-94-23］  →  鵶
  #
  # 底本の文字が基本文字集合に無いとき、青空文庫は面区点番号つきの注記を置く。
  # **外字は定義上めずらしい字であり、そのほとんどが難読帯に属する。**
  # 落としたままにすると難読帯を系統的に過小評価する。
  #
  # 写像は JIS X 0213 の面区点 → EUC-JIS-2004 のバイト列 → Unicode で行う。
  # 面 1 は 2 バイト、面 2 は 0x8F を前置した 3 バイト。
  #
  # 非循環の検算(G-03b): 注記の中の「第3水準 / 第4水準」という語と面区点番号は
  # **別々に入力された独立の欄**である。第3水準は面 1、第4水準は面 2 に対応するので、
  # 写像規則が正しければ一致し、間違っていれば食い違う。
  # 写像結果を写像規則で検算する循環にならない(HC-045)。
  module Gaiji
    # 「…、第4水準2-94-23］」「…、1-84-22］」の両方を拾う。
    MENKUTEN = /(\d)-(\d{1,2})-(\d{1,2})\s*(?:］|］)?\s*\z/
    LEVEL = /第([34])水準/

    Mapped = Struct.new(:char, :men, :ku, :ten, :level, :note, keyword_init: true) do
      # 水準ラベルと面番号が合っているか。ラベルが無いときは検査しない(nil)。
      def level_agrees?
        return nil if level.nil?

        (level == 3 && men == 1) || (level == 4 && men == 2)
      end
    end

    module_function

    # 外字注記の生文字列 → Mapped、または nil(面区点が無い・写像できない)。
    def map(raw)
      inner = raw.sub(/\A※?［＃/, "").sub(/］\z/, "")
      m = inner.match(/(\d)-(\d{1,2})-(\d{1,2})/)
      return nil if m.nil?

      men = m[1].to_i
      ku = m[2].to_i
      ten = m[3].to_i
      ch = to_char(men, ku, ten)
      return nil if ch.nil?

      Mapped.new(char: ch, men: men, ku: ku, ten: ten,
                 level: inner[LEVEL, 1]&.to_i, note: inner)
    end

    # 面区点 → 文字。範囲外・未割当は nil。
    def to_char(men, ku, ten)
      return nil unless [1, 2].include?(men)
      return nil unless ku.between?(1, 94) && ten.between?(1, 94)

      bytes = men == 1 ? [0xA0 + ku, 0xA0 + ten] : [0x8F, 0xA0 + ku, 0xA0 + ten]
      s = bytes.pack("C*").force_encoding("EUC-JIS-2004")
      return nil unless s.valid_encoding?

      s.encode("UTF-8")
    rescue Encoding::UndefinedConversionError, Encoding::InvalidByteSequenceError
      nil
    end
  end
end
