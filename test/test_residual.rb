# frozen_string_literal: true

require "minitest/autorun"
require_relative "../lib/aozora/residual"
require_relative "../lib/aozora/axes"

class TestResidual < Minitest::Test
  R = Aozora::Residual
  A = Aozora::Axes

  # ── F-12 回帰と残差 ───────────────────────────────────────
  def test_ols_recovers_a_known_line
    xs = (1..20).map(&:to_f)
    ys = xs.map { |x| 3.0 + 2.0 * x }
    a, b = R.ols(xs, ys)
    assert_in_delta 3.0, a, 1e-9
    assert_in_delta 2.0, b, 1e-9
  end

  def test_residuals_of_a_perfect_line_are_zero
    xs = (1..20).map(&:to_f)
    ys = xs.map { |x| 3.0 + 2.0 * x }
    assert(R.residuals(xs, ys).all? { |r| r.abs < 1e-9 })
  end

  def test_residuals_are_orthogonal_to_the_regressor_by_construction
    # これは**成果ではなく構成上の帰結**である。ゲートにしてはならない理由を
    # テストで明示しておく(HC-039)。どんな入力でも 0 になる。
    xs = [1.0, 4, 2, 8, 5, 7, 3, 6]
    ys = [2.0, 9, 1, 15, 8, 20, 4, 11]
    res = R.residuals(xs, ys)
    assert_in_delta 0.0, A.correlation(xs, res), 1e-9,
                    "残差が回帰変数と直交していない = 実装の誤り"
  end

  def test_residual_keeps_the_part_not_explained_by_the_regressor
    # y = x + s。s(作家固有の成分)は残差として残らなければならない。
    xs = (1..12).map(&:to_f)
    s  = [1.0, -1, 1, -1, 1, -1, 1, -1, 1, -1, 1, -1]
    ys = xs.each_with_index.map { |x, i| x + s[i] }
    res = R.residuals(xs, ys)
    assert_operator A.correlation(s, res), :>, 0.9, "固有成分が残差に残っていない"
  end

  # ── G-13 置換検定 ─────────────────────────────────────────
  def test_permutation_null_is_centred_on_zero
    xs = (1..40).map { |i| Math.sin(i) }
    ys = (1..40).map { |i| Math.cos(i) }
    null = R.permutation_null(xs, ys, seed: 20_260_827, n: 500)
    assert_in_delta 0.0, null.sum / null.length, 0.06
  end

  def test_permutation_is_deterministic_for_a_fixed_seed
    # 帰無分布が実行ごとに動くと、ゲートの判定が再現しない(O-05)。
    xs = (1..30).map(&:to_f)
    ys = (1..30).map { |i| (i * 7 % 13).to_f }
    a = R.permutation_null(xs, ys, seed: 20_260_827, n: 200)
    b = R.permutation_null(xs, ys, seed: 20_260_827, n: 200)
    assert_equal a, b
  end

  def test_a_real_signal_separates_from_the_null
    xs = (1..60).map(&:to_f)
    ys = xs.map { |x| x + Math.sin(x) }           # 強い対応
    v = R.permutation_test(xs, ys, seed: 20_260_827, n: 500)
    assert v.separated?, "本物の信号が帰無分布から分離しない"
    assert_operator v.p_value, :<, 0.01
  end

  def test_pure_noise_does_not_separate_from_the_null
    # 検定が何でも通すなら意味がない。雑音は落ちなければならない。
    rng = Random.new(1)
    xs = Array.new(60) { rng.rand }
    ys = Array.new(60) { rng.rand }
    v = R.permutation_test(xs, ys, seed: 20_260_827, n: 500)
    refute v.separated?, "雑音が帰無分布から分離してしまう = 検定が無力"
  end
end
