# frozen_string_literal: true

require "strscan"

module Aozora
  # 青空文庫の注記記法を解析木にする(SPEC F-01)。
  #
  # 設計の要は「往復検査が原理的に通ること」である(SPEC O-01)。そのために
  # 各節点は**復元に必要な情報をすべて自分で持つ**:
  #
  #   - ルビ始点記号 ｜ の有無(bar)
  #   - 基底文字列そのもの(規則から導き直さない)
  #
  # 規則から導き直す設計にすると、基底の推定規則を直すたびに往復検査が壊れる。
  # 逆に基底を実体として持てば、**基底推定が下手でも往復検査は必ず通る**
  # (取りこぼした分は前の Text 節点に残り、連結すれば原文に戻るため)。
  # つまり O-01 はパーサの完全性を保証するが、基底推定の質は保証しない。
  # 基底推定の質は G-02(未知パターン件数)で別に見る。
  module Notation
    Text  = Struct.new(:raw)                     # 地の文
    Gaiji = Struct.new(:raw)                     # ※［＃…］ 外字注記
    Annot = Struct.new(:raw)                     # ［＃…］  入力者注・組版指示
    # 基底《読み》。mid は基底と 《 の間に割り込んだ入力者注の生文字列。
    #   例: 座敷着［＃「着」は底本では「看」と誤記］《ざしきぎ》  (000351 実測 2026-08-27)
    # 割り込みを捨てると往復検査が壊れ、基底に含めると計量が壊れるので、別に持つ。
    Ruby  = Struct.new(:base, :reading, :bar, :mid) do
      def bar? = bar
      def mid = self[:mid] || ""
    end

    # 基底として後方に取り込む文字。漢字・々・〆・ヶヵ・繰り返し記号。
    KANJI = /[\p{Han}々〆ヵヶ]/
    # 基底の推定に使う文字クラス。同一クラスの連続を基底とみなす。
    # \p{So} は ○《まる》 のような記号基底のため(000327 実測 2026-08-27)。
    # 以下はすべて G-02 の残骸を実例まで見て判明した形(実測 2026-08-27)。
    #   全角ラテン ＭＲ《ミスタ》(051250) / ギリシャ γ《ガムマア》(001058)
    #   キリル Л《エル》(051847) / 数学記号 ＋《よこじゅうじ》(001317)
    CLASSES = [/\p{Han}|[々〆ヵヶ]/, /\p{Katakana}ー*/, /\p{Hiragana}/,
               /[A-Za-zＡ-Ｚａ-ｚ]/, /[0-9０-９]/,
               /\p{Greek}/, /\p{Cyrillic}/, /\p{So}/, /\p{Sm}/].freeze
    # 亀甲括弧で囲んだ翻字が基底になる形 〔Ma_r〕《マール》(042686)。
    BRACKETED = /〔[^〔〕]*〕\z/

    module_function

    # 原文 → 節点の配列。
    def parse(src)
      s = StringScanner.new(src)
      nodes = []
      buf = +""

      # buf を Text 節点として確定する。
      flush = lambda do
        nodes << Text.new(buf) unless buf.empty?
        buf = +""
      end

      until s.eos?
        if s.match?(/※［＃/)
          flush.call
          nodes << Gaiji.new(scan_annotation(s))
        elsif s.match?(/［＃/)
          flush.call
          nodes << Annot.new(scan_annotation(s))
        elsif s.scan(/｜/)
          # ｜ 以降・次の 《 までが基底。《 が来なければ ｜ は地の文に戻す。
          if (m = s.scan(/([^《》｜]*)《([^》]*)》/))
            flush.call
            nodes << Ruby.new(s[1], s[2], true)
          else
            buf << "｜"
          end
        elsif (m = s.scan(/《([^》]*)》/))
          reading = s[1]
          base, mid = take_base!(buf, nodes)
          if base.empty?
            # 基底が取れない 《》 は注記ではなく地の文の記号とみなす(G-02 で計数)。
            # 剥がした注記は buf に戻す。節点として積むと Text より前に出て順序が壊れる。
            buf << mid << m
          else
            flush.call
            nodes << Ruby.new(base, reading, false, mid)
          end
        else
          buf << s.getch
        end
      end
      flush.call
      nodes
    end

    # 節点の配列 → 原文(SPEC F-02)。往復検査の片道。
    def rebuild(nodes)
      nodes.map { |n|
        case n
        when Text, Gaiji, Annot then n.raw
        when Ruby then (n.bar ? "｜" : "") + n.base + n.mid + "《" + n.reading + "》"
        else raise ArgumentError, "未知の節点: #{n.class}"
        end
      }.join
    end

    # 入力者注を 1 件、括弧の深さを数えながら読み取る。
    #
    # 入力者注は入れ子になる(001805 実測 2026-08-27):
    #   ［＃「小笊《こざる》」は底本では「小※［＃「竹かんむり／瓜」、314-上-1］《こざる》」］
    # 入れ子を許さない ［＃[^］]*］ は内側の ］ で閉じ、残りを地の文に落とす。
    # 落ちた残骸には 笊《 のような**漢字基底のルビが含まれる**ため、計量が静かに狂う。
    # HC-027 が同型を記録済み。往復検査は残骸ごと復元するので、この誤りを検出しない。
    def scan_annotation(s)
      raw = +"" << s.scan(/※?［＃/)
      depth = 1
      while depth.positive? && !s.eos?
        ch = s.getch
        raw << ch
        depth += 1 if ch == "［"
        depth -= 1 if ch == "］"
      end
      raw
    end

    # 直前の文字列から基底を切り出し、**その分を buf / nodes から取り除く**。
    # 取り除きを忘れると往復検査で二重になる。
    # 戻り値は [基底, 割り込んだ入力者注]。基底が取れなければ ["", 割り込み]。
    def take_base!(buf, nodes)
      # 基底と 《 の間に入力者注が挟まる形を先に剥がす(000351)。外字注記は基底そのものなので剥がさない。
      mid = +""
      mid.prepend(nodes.pop.raw) while buf.empty? && nodes.last.is_a?(Annot)

      # 直前が外字注記なら、それ自体が基底(例: ※［＃「亞＋鳥」…］《からす》)。
      # さらにその前が漢字なら、漢字＋外字で 1 つの基底である
      # (什※［＃「麾」の「毛」…］《どんな》 — 凡例の実例。実測 2026-08-27)。
      if buf.empty? && nodes.last.is_a?(Gaiji)
        g = nodes.pop.raw
        prev = nodes.last
        if prev.is_a?(Text) && (run = prev.raw[/(?:#{KANJI.source})+\z/])
          prev.raw = prev.raw[0...-run.length]
          nodes.pop if prev.raw.empty?
          return [run + g, mid]
        end
        return [g, mid]
      end

      # 注記を剥がすと、基底は確定済みの Text 節点の末尾に残っている。buf に戻して切り出す。
      buf << nodes.pop.raw if buf.empty? && nodes.last.is_a?(Text)
      return ["", mid] if buf.empty?

      # 亀甲括弧の閉じで終わるなら、対応する開きまでが基底。
      if (br = buf[BRACKETED])
        buf.slice!(buf.length - br.length, br.length)
        return [br, mid]
      end

      cls = CLASSES.find { |c| buf.match?(/(?:#{c.source})\z/) }
      return ["", mid] unless cls

      run = buf[/(?:#{cls.source})+\z/]
      return ["", mid] if run.nil? || run.empty?

      buf.slice!(buf.length - run.length, run.length)
      # 漢字基底のときだけ、直前の外字注記も基底に含める。
      run = nodes.pop.raw + run if run.match?(KANJI) && buf.empty? && nodes.last.is_a?(Gaiji)
      [run, mid]
    end
  end
end
