# frozen_string_literal: true

# 三軸を実測する(SPEC F-12)。
#
#   ruby bin/three_axes.rb [--limit N]
#
# 第一軸 総ルビ傾向      … 支配因子。名指しして主役に据える
# 第二軸 難所への偏り    … 優しさを総ルビ傾向へ回帰した残差
# 第三軸 繰り返しの抑制  … 記憶を総ルビ傾向へ回帰した残差
#
# 判定するゲート(判定線は測定前に SPEC へ書き、commit b9a6443 で封じてある):
#   G-11 半分割再現性  r(前半, 後半) > 0.5
#   G-12 残差同士の独立 |r| < 0.3
#   G-13 置換検定(2,000 回・seed 20260827)で帰無分布の最大値を超える

require "json"
require_relative "../lib/aozora/corpus"
require_relative "../lib/aozora/tally"
require_relative "../lib/aozora/axes"
require_relative "../lib/aozora/repeat"
require_relative "../lib/aozora/residual"

C = Aozora::Corpus
T = Aozora::Tally
A = Aozora::Axes
R = Aozora::Repeat
D = Aozora::Residual

SEED = 20_260_827
PERM = 2000
MIN_N   = 500   # 半分ずつ測るので loop_002 の 1000 の半分
MIN_REP = 100

limit = (i = ARGV.index("--limit")) ? ARGV[i + 1].to_i : nil
works = C.works.sort_by(&:id)
works = works.first(limit) if limit

# ── 第 1 走査 ────────────────────────────────────────────────
# 作家ごとに、全体・前半・後半の三つ組で数える。
# 半分割は作品 ID 昇順で交互に振り分ける(決定論・O-05)。
Bucket = Struct.new(:counts, :rep) do
  def self.empty = new(T::Counts.empty, R::Tally.empty)
  def add!(c, r) = (counts.merge!(c); rep.merge!(r); self)
end

sets = { full: {}, a: {}, b: {} }
meta = Hash.new { |h, k| h[k] = { works: 0, born: nil, kana: Hash.new(0) } }
seq = Hash.new(0)

works.each_with_index do |w, i|
  nodes = C.parse(w.id)
  next if nodes.nil?

  c = T.count(nodes)
  r = R.count(nodes)
  half = seq[w.author].even? ? :a : :b
  seq[w.author] += 1

  [[:full, w.author], [half, w.author]].each do |set, au|
    (sets[set][au] ||= Bucket.empty).add!(c, r)
  end
  m = meta[w.author]
  m[:works] += 1
  m[:born] ||= w.born
  m[:kana][w.kana] += 1
  warn "  #{i + 1}/#{works.length}" if ((i + 1) % 1000).zero?
end

# ── 帯は全体コーパスの一人抜きで作る ─────────────────────────
# 半分ごとに帯を作り直すと、帯の違いが半分割相関に混ざる。
# 帯はコーパスの性質であって半分の性質ではない。
freq_of = sets[:full].transform_values { |b| A.frequency(b.counts) }
global = Hash.new(0)
freq_of.each_value { |f| f.each { |ch, n| global[ch] += n } }
bands_of = freq_of.transform_values { |own| A.bands(A.leave_one_out(global, own)) }

def triple(bucket, easy, hard)
  m = Aozora::Axes.measure(bucket.counts, easy, hard)
  rubied = bucket.counts.rubied.values.sum
  plain  = bucket.counts.plain.values.sum
  {
    kindness: m.kindness, hard_n: m.hard_n, easy_n: m.easy_n,
    memory: bucket.rep.rate&.then { |x| (1.0 - x) * 100 }, repeats: bucket.rep.repeats,
    density: rubied * 100.0 / [plain + rubied, 1].max
  }
end

rows = sets[:full].keys.map { |au|
  easy, hard = bands_of[au]
  { author: au, born: meta[au][:born], works: meta[au][:works],
    kana: meta[au][:kana].max_by { |_, v| v }&.first,
    chars: sets[:full][au].counts.total_chars,
    full: triple(sets[:full][au], easy, hard),
    a: sets[:a][au] && triple(sets[:a][au], easy, hard),
    b: sets[:b][au] && triple(sets[:b][au], easy, hard) }
}

usable = lambda { |t, mn, mr|
  t && t[:kindness] && t[:memory] && t[:hard_n] >= mn && t[:easy_n] >= mn && t[:repeats] >= mr
}
full_ok = rows.select { |r| usable.call(r[:full], MIN_N * 2, MIN_REP * 2) }
split_ok = full_ok.select { |r| usable.call(r[:a], MIN_N, MIN_REP) && usable.call(r[:b], MIN_N, MIN_REP) }

# ── 残差 ─────────────────────────────────────────────────────
def residual_axes(set)
  d = set.map { |t| t[:density] }
  { hard: Aozora::Residual.residuals(d, set.map { |t| t[:kindness] }),
    repeat: Aozora::Residual.residuals(d, set.map { |t| t[:memory] }) }
end

res_full = residual_axes(full_ok.map { |r| r[:full] })
res_a = residual_axes(split_ok.map { |r| r[:a] })
res_b = residual_axes(split_ok.map { |r| r[:b] })

r_hh = A.correlation(res_a[:hard], res_b[:hard])
r_rr = A.correlation(res_a[:repeat], res_b[:repeat])
r_hr = A.correlation(res_full[:hard], res_full[:repeat])

v_hard = D.permutation_test(res_a[:hard], res_b[:hard], seed: SEED, n: PERM)
v_rep  = D.permutation_test(res_a[:repeat], res_b[:repeat], seed: SEED, n: PERM)

# ── 報告 ─────────────────────────────────────────────────────
puts "== 走査 =="
puts "作品            : #{works.length}"
puts "作家            : #{rows.length}"
puts "三軸を測れる作家: #{full_ok.length}"
puts "半分割できる作家: #{split_ok.length}(前半・後半それぞれ最低量を満たす)"
puts
puts "== 第一軸 総ルビ傾向(支配因子・名指しした) =="
ds = full_ok.map { |r| r[:full][:density] }
puts "平均 #{'%.2f' % (ds.sum / ds.length)} % / 最小 #{'%.2f' % ds.min} / 最大 #{'%.2f' % ds.max}"
puts "優しさ × 総ルビ傾向 r : #{'%+.3f' % A.correlation(full_ok.map { |r| r[:full][:kindness] }, ds)}"
puts "記憶   × 総ルビ傾向 r : #{'%+.3f' % A.correlation(full_ok.map { |r| r[:full][:memory] }, ds)}"
puts "  → この 1 変数が両方を押している。だから残差にする"
puts
puts "== 構成上の帰結(成果ではない) =="
puts "難所への偏り × 総ルビ傾向 r : #{'%+.3f' % A.correlation(res_full[:hard], ds)}"
puts "繰り返しの抑制 × 総ルビ傾向 r : #{'%+.3f' % A.correlation(res_full[:repeat], ds)}"
puts "  → 回帰の構成上 0 になる。ゲートにしてはならない(HC-039)"
puts
puts "== G-11 残差の再現性(判定線 r > 0.5・測定前に宣言) =="
puts "難所への偏り   r(前半, 後半) : #{'%+.3f' % r_hh}  #{r_hh > 0.5 ? '合格' : '失格'}"
puts "繰り返しの抑制 r(前半, 後半) : #{'%+.3f' % r_rr}  #{r_rr > 0.5 ? '合格' : '失格'}"
puts
puts "== G-12 残差同士の独立(判定線 |r| < 0.3・測定前に宣言) =="
puts "難所への偏り × 繰り返しの抑制 r : #{'%+.3f' % r_hr}  #{r_hr.abs < 0.3 ? '合格' : '失格'}"
puts
puts "== G-13 置換検定(#{PERM} 回・seed #{SEED}・測定前に宣言) =="
[["難所への偏り", v_hard], ["繰り返しの抑制", v_rep]].each do |name, v|
  puts format("%-14s 観測 %+.3f / 帰無最大 %+.3f / p = %.4f  %s",
              name, v.observed, v.null_max, v.p_value, v.separated? ? "合格" : "失格")
end

g11 = r_hh > 0.5 && r_rr > 0.5
g12 = r_hr.abs < 0.3
g13 = v_hard.separated? && v_rep.separated?
puts
puts "== 総合 =="
puts(g11 && g12 && g13 ? "三軸は成立する。残差は作家の性質であって雑音ではない" : "失格。三軸も捨てる")

puts
puts "== 残差の両端(難所への偏り) =="
idx = full_ok.each_index.sort_by { |i| -res_full[:hard][i] }
puts format("%-14s %5s %7s %7s %7s", "作家", "生年", "総ルビ", "優しさ", "偏り")
(idx.first(8) + idx.last(8)).each do |i|
  r = full_ok[i]
  puts format("%-14s %5s %7.1f %7.1f %+7.1f",
              r[:author], r[:born] || "–", r[:full][:density], r[:full][:kindness], res_full[:hard][i])
end

File.write(File.expand_path("../out/three_axes.json", __dir__),
           JSON.pretty_generate(
             works_scanned: works.length, limit: limit,
             authors_full: full_ok.length, authors_split: split_ok.length,
             seed: SEED, permutations: PERM, min_n: MIN_N, min_rep: MIN_REP,
             gates: { g11_hard: r_hh, g11_repeat: r_rr, g11_pass: g11,
                      g12_r: r_hr, g12_pass: g12,
                      g13_hard_p: v_hard.p_value, g13_repeat_p: v_rep.p_value, g13_pass: g13 },
             authors: full_ok.each_with_index.map { |r, i|
               r.merge(resid_hard: res_full[:hard][i], resid_repeat: res_full[:repeat][i])
             }
           ))
exit(g11 && g12 && g13 ? 0 : 1)
