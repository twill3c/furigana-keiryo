# frozen_string_literal: true

require "set"

module Aozora
  # 難読度の帯と二軸(SPEC F-04 / F-06)。
  #
  # 難読度は**出現頻度**から作る。常用漢字表(1981)を使わないのは、1890 年の本文を
  # 1981 年の基準で測ることになるためである(G-06 時代錯誤)。頻度なら同時代の
  # 書き手から作れる。
  #
  # 循環の禁止(G-05): 頻度表の入力は**漢字が何回出たか**だけであり、
  # その漢字にルビが振られたかどうかを一切参照しない。Axes.frequency は
  # plain / rubied / duty を合算するので、三者の内訳が変わっても表は変わらない。
  # この不変量は test_axes.rb で明示的に検査する(O-03)。
  module Axes
    EASY_CUM = 0.75   # 累積被覆 0〜75% を易読帯
    HARD_CUM = 0.95   # 累積被覆 95〜100% を難読帯(75〜95% は緩衝帯で、どちらにも入れない)

    Result = Struct.new(:kindness, :trust, :hard_n, :easy_n, keyword_init: true)

    module_function

    # 出現頻度表。ルビの有無は見ない(G-05)。
    def frequency(counts)
      f = Hash.new(0)
      [counts.plain, counts.rubied, counts.duty].each { |h| h.each { |c, n| f[c] += n } }
      f
    end

    # 作家一人抜き(SPEC F-04)。作家 A の難読度を A 自身の本文から作ると、
    # 「A がよく使う字は A にとって易しい」という自明な結論しか出ない。
    # 全体から A の分を引いて、A 以外の書き手が作った表で A を測る。
    def leave_one_out(global, own)
      out = Hash.new(0)
      global.each { |c, n| (m = n - own.fetch(c, 0)).positive? && out[c] = m }
      out
    end

    # 頻度表 → [易読帯, 難読帯]。累積被覆で切るので、母集団は構成上互いに素(O-02)。
    def bands(freq)
      total = freq.values.sum
      return [Set.new, Set.new] if total.zero?

      easy = Set.new
      hard = Set.new
      cum = 0
      # 同数の字は符号位置で並べる。再実行で帯が変わらないため(O-05 決定論)。
      freq.sort_by { |c, n| [-n, c] }.each do |c, n|
        lo = cum.to_f / total
        cum += n
        hi = cum.to_f / total
        if hi <= EASY_CUM then easy << c
        elsif lo >= HARD_CUM then hard << c
        end
      end
      [easy, hard]
    end

    # 二軸。母集団が異なるだけで、計算式は同じ「ルビが振られた出現の割合」である。
    #   優しさ = 難読帯でルビが振られた割合(高いほど助ける)
    #   信用   = 易読帯でルビを振らなかった割合(高いほど放っておく)
    # 義務ルビは分子にも分母にも入れない(SPEC F-05)。
    def measure(counts, easy, hard)
      k = rate(counts, hard)
      t = rate(counts, easy)
      Result.new(kindness: k && k * 100, trust: t && (1.0 - t) * 100,
                 hard_n: denom(counts, hard), easy_n: denom(counts, easy))
    end

    def rate(counts, set)
      d = denom(counts, set)
      return nil if d.zero?

      set.sum { |c| counts.rubied[c] }.to_f / d
    end

    def denom(counts, set)
      set.sum { |c| counts.rubied[c] + counts.plain[c] }
    end

    # ピアソンの積率相関。G-04(二軸の独立)の判定に使う。
    def correlation(xs, ys)
      n = xs.length
      return nil if n < 3

      mx = xs.sum / n.to_f
      my = ys.sum / n.to_f
      sxy = xs.zip(ys).sum { |x, y| (x - mx) * (y - my) }
      sxx = xs.sum { |x| (x - mx)**2 }
      syy = ys.sum { |y| (y - my)**2 }
      return nil if sxx.zero? || syy.zero?

      sxy / Math.sqrt(sxx * syy)
    end
  end
end
