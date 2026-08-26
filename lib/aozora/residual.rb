# frozen_string_literal: true

require_relative "axes"

module Aozora
  # 支配因子を統制した残差(SPEC F-12)と、その残差が雑音でないことの検査(G-11 / G-13)。
  #
  # loop_002 / loop_003 で、支配因子(総ルビ傾向)と直交すると称する軸を二度立て、
  # 二度とも潰れた。母集団の構成をいじって直交させようとしたのが誤りで、
  # **直交させたいなら支配因子を明示的に回帰して残差を取るしかない**(HC-039)。
  #
  # ただし残差が支配因子と直交するのは**回帰の構成上あたりまえ**である。
  # それは成果ではないので、ゲートにしてはならない。新設計で問うべきは
  #
  #   その残差は作家の性質か、それとも標本の雑音か
  #
  # であり、半分割再現性(G-11)と置換検定(G-13)がそれを見る。
  module Residual
    module_function

    # 最小二乗。y = a + b x の [a, b]。
    def ols(xs, ys)
      n = xs.length
      mx = xs.sum / n.to_f
      my = ys.sum / n.to_f
      sxx = xs.sum { |x| (x - mx)**2 }
      return [my, 0.0] if sxx.zero?

      b = xs.zip(ys).sum { |x, y| (x - mx) * (y - my) } / sxx
      [my - b * mx, b]
    end

    # y から x の線形成分を抜いた残差。
    def residuals(xs, ys)
      a, b = ols(xs, ys)
      xs.zip(ys).map { |x, y| y - (a + b * x) }
    end

    # 置換検定(G-13)。作家ラベルを混ぜたときの半分割相関の帰無分布を作る。
    # 観測がこの分布の最大値を超えていれば、残差は作家に紐づいている。
    #
    # 乱数は seed 固定。再実行で同じ帰無分布が出ること自体が決定論の検査になる(O-05)。
    def permutation_null(xs, ys, seed:, n: 2000)
      rng = Random.new(seed)
      Array.new(n) { Axes.correlation(xs, ys.shuffle(random: rng)) }.compact
    end

    # 帰無分布に対する観測の位置。
    Verdict = Struct.new(:observed, :null_max, :null_p95, :p_value, keyword_init: true) do
      def separated? = observed > null_max
    end

    def permutation_test(xs, ys, seed:, n: 2000)
      obs = Axes.correlation(xs, ys)
      null = permutation_null(xs, ys, seed: seed, n: n)
      sorted = null.sort
      Verdict.new(
        observed: obs,
        null_max: sorted.last,
        null_p95: sorted[(n * 0.95).to_i],
        # 片側。観測以上の帰無標本の割合(+1/+1 は保守側の補正)。
        p_value: (null.count { |r| r >= obs } + 1).to_f / (n + 1)
      )
    end
  end
end
