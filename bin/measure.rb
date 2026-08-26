# frozen_string_literal: true

# 二軸を全作家について実測する(SPEC F-04〜F-07)。
#
#   ruby bin/measure.rb [--limit N]
#
# 判定するゲート:
#   G-04 二軸の独立   |r| < 0.7      … 超えたら二軸は実質一軸。企画の失格条件
#   G-05 循環の禁止   頻度表がルビを参照しない
#   G-06 時代整合     世代帯そろえの表と全体の表で作家の順位が変わらないこと

require "json"
require_relative "../lib/aozora/corpus"
require_relative "../lib/aozora/tally"
require_relative "../lib/aozora/axes"
require_relative "../lib/aozora/repeat"

C = Aozora::Corpus
T = Aozora::Tally
A = Aozora::Axes
R = Aozora::Repeat

MIN_N = 1000   # 各帯でこれ未満の出現しかない作家は測定不能として外す
MIN_REP = 200  # 再出現がこれ未満の作家は反復率を測定不能として外す

limit = (i = ARGV.index("--limit")) ? ARGV[i + 1].to_i : nil
works = C.works
works = works.first(limit) if limit

# ── 第 1 走査: 作家ごとに漢字の出現を数える ────────────────────
by_author = Hash.new { |h, k| h[k] = T::Counts.empty }
rep_of = Hash.new { |h, k| h[k] = R::Tally.empty }
meta = Hash.new { |h, k| h[k] = { works: 0, born: nil, kana: Hash.new(0) } }
missing = 0

works.each_with_index do |w, i|
  nodes = C.parse(w.id)
  if nodes.nil?
    missing += 1
    next
  end
  by_author[w.author].merge!(T.count(nodes))
  rep_of[w.author].merge!(R.count(nodes))   # 反復は作品単位で数えてから合算する
  m = meta[w.author]
  m[:works] += 1
  m[:born] ||= w.born
  m[:kana][w.kana] += 1
  warn "  #{i + 1}/#{works.length}" if ((i + 1) % 1000).zero?
end

freq_of = by_author.transform_values { |c| A.frequency(c) }
global = Hash.new(0)
freq_of.each_value { |f| f.each { |c, n| global[c] += n } }

# 世代帯ごとの合算(G-06 用)。
cohort_of = meta.transform_values { |m| C.cohort(m[:born]) }
cohort_freq = Hash.new { |h, k| h[k] = Hash.new(0) }
freq_of.each { |a, f| f.each { |c, n| cohort_freq[cohort_of[a]][c] += n } }

# ── 第 2 走査: 一人抜きの表で二軸を測る ────────────────────────
rows = []
by_author.each do |author, counts|
  own = freq_of[author]
  easy, hard = A.bands(A.leave_one_out(global, own))
  r = A.measure(counts, easy, hard)

  ce, ch = A.bands(A.leave_one_out(cohort_freq[cohort_of[author]], own))
  rc = A.measure(counts, ce, ch)

  rows << {
    author: author, works: meta[author][:works], born: meta[author][:born],
    cohort: cohort_of[author].to_s,
    kana: meta[author][:kana].max_by { |_, v| v }&.first,
    chars: counts.total_chars,
    kindness: r.kindness, trust: r.trust, hard_n: r.hard_n, easy_n: r.easy_n,
    kindness_cohort: rc.kindness, trust_cohort: rc.trust,
    duty: counts.duty.values.sum,
    repeats: rep_of[author].repeats,
    # 記憶への信用 = 1 − 反復率。一度教えた語を二度目に放っておく度合い。
    memory: rep_of[author].rate&.then { |r| (1.0 - r) * 100 },
    # 総ルビ傾向。二軸の交絡候補。この 1 変数が二軸の両方を押し引きしている疑いがある。
    density: counts.rubied.values.sum * 100.0 /
             [counts.plain.values.sum + counts.rubied.values.sum, 1].max
  }
end

ok = rows.select { |r| r[:kindness] && r[:trust] && r[:hard_n] >= MIN_N && r[:easy_n] >= MIN_N }

# ── ゲート判定 ────────────────────────────────────────────────
ks = ok.map { |r| r[:kindness] }
ts = ok.map { |r| r[:trust] }
r_axes = A.correlation(ks, ts)

pair = ok.select { |r| r[:kindness_cohort] && r[:trust_cohort] }
r_era_k = A.correlation(pair.map { |r| r[:kindness] }, pair.map { |r| r[:kindness_cohort] })
r_era_t = A.correlation(pair.map { |r| r[:trust] }, pair.map { |r| r[:trust_cohort] })

mk = ks.sum / ks.length
mt = ts.sum / ts.length
quad = Hash.new(0)
ok.each do |r|
  quad[[r[:kindness] >= mk, r[:trust] >= mt]] += 1
end

puts "== 走査 =="
puts "作品          : #{works.length}(本文なし #{missing})"
puts "作家          : #{by_author.length}"
puts "測定可能な作家: #{ok.length}(各帯 #{MIN_N} 出現以上)"
puts
puts "== 二軸(中央の作家) =="
puts "優しさ 平均   : #{'%.1f' % mk} %"
puts "信用   平均   : #{'%.1f' % mt} %"
puts
puts "== G-04 二軸の独立 =="
puts "相関 r        : #{'%.3f' % r_axes}"
puts(r_axes.abs < 0.7 ? "  → 合格。二軸は別の量を測っている" : "  → 失格。二軸は実質一軸であり、企画が成立しない")
puts
puts "== G-06 時代整合(全体の表 vs 世代帯の表) =="
# 前提の検算。生年が引けず全員が unknown に落ちると、世代帯の表は全体の表と同一になり、
# r = 1.000 が必ず出る。データ欠落が合格の原因になる、落ちないゲートだった(実測 2026-08-27)。
known = ok.count { |r| r[:cohort] != "unknown" }
share = known * 100.0 / ok.length
puts "生年の判明率  : #{'%.1f' % share} %(#{known} / #{ok.length})"
puts "優しさ の一致 r: #{'%.3f' % r_era_k}"
puts "信用   の一致 r: #{'%.3f' % r_era_t}"
puts(if share < 90
       "  → 判定不能。生年が引けていないので世代帯の表が作れていない"
     elsif r_era_k > 0.9 && r_era_t > 0.9
       "  → 合格。表を同時代に絞っても順位はほぼ変わらない"
     else
       "  → 保留。表の時代で結果が動く"
     end)

# ── G-09 / G-10 第二軸(記憶への信用) ─────────────────────────
# 判定線は測定前に SPEC へ書き、コミット 0102e33 で封じてある。
mem_ok = ok.select { |r| r[:memory] && r[:repeats] >= MIN_REP }
ms = mem_ok.map { |r| r[:memory] }
mks = mem_ok.map { |r| r[:kindness] }
mds = mem_ok.map { |r| r[:density] }
r_km = A.correlation(mks, ms)
r_md = A.correlation(ms, mds)

puts
puts "== 第二軸: 記憶への信用(反復率の裏返し) =="
puts "測定可能な作家: #{mem_ok.length}(再出現 #{MIN_REP} 回以上)"
puts "平均          : #{'%.1f' % (ms.sum / ms.length)} %"
puts
puts "== G-09 二軸の独立(判定線 |r| < 0.7・測定前に宣言) =="
puts "優しさ × 記憶への信用 r : #{'%.3f' % r_km}"
puts(r_km.abs < 0.7 ? "  → 合格" : "  → 失格")
puts
puts "== G-10 交絡からの独立(判定線 |r| < 0.5・測定前に宣言) =="
puts "記憶への信用 × 総ルビ傾向 r : #{'%.3f' % r_md}"
puts(r_md.abs < 0.5 ? "  → 合格。第二軸は総ルビ傾向の言い換えではない" : "  → 失格。loop_002 と同じ失敗。軸を捨てる")

mm = ms.sum / ms.length
mkk = mks.sum / mks.length
q2 = Hash.new(0)
mem_ok.each { |r| q2[[r[:kindness] >= mkk, r[:memory] >= mm]] += 1 }
puts
puts "== 新しい四象限(平均で区切る) =="
puts "過保護  (優 高・記憶 低): #{q2[[true, false]]}   難所で助け、何度でも振り直す"
puts "案内人  (優 高・記憶 高): #{q2[[true, true]]}   難所で助け、一度教えたら放っておく"
puts "無頓着  (優 低・記憶 低): #{q2[[false, false]]}   助けないのに振り直す"
puts "突き放し(優 低・記憶 高): #{q2[[false, true]]}   助けず、繰り返しもしない"

# ── 事後診断(ゲートではない) ────────────────────────────────
# G-04 が落ちた機構を測る。閾値も帯も動かさない。
# 総ルビ傾向(density)は作家ごとの文体・編集方針であり、二軸の**両方**を押す。
# これを統制してなお二軸が相関するなら、二軸は本当に同じ量である。
ds = ok.map { |r| r[:density] }
r_kd = A.correlation(ks, ds)
r_td = A.correlation(ts, ds)
partial = (r_axes - r_kd * r_td) / Math.sqrt((1 - r_kd**2) * (1 - r_td**2))

puts
puts "== 事後診断: 総ルビ傾向を統制したら =="
puts "優しさ × 総ルビ傾向 r : #{'%.3f' % r_kd}"
puts "信用   × 総ルビ傾向 r : #{'%.3f' % r_td}"
puts "二軸の偏相関       r : #{'%.3f' % partial}"
puts "  (ゲートではない。G-04 の判定は上の -0.721 のままである)"
puts
puts "== 四象限(平均で区切る) =="
puts "過保護  (優 高・信 低): #{quad[[true, false]]}"
puts "案内人  (優 高・信 高): #{quad[[true, true]]}"
puts "ちぐはぐ(優 低・信 低): #{quad[[false, false]]}"
puts "突き放し(優 低・信 高): #{quad[[false, true]]}"
puts
puts
puts "== 作品数の多い作家 20 名 =="
puts format("%-14s %5s %5s %7s %7s %7s", "作家", "作品", "生年", "優しさ", "記憶", "総ルビ")
mem_ok.sort_by { |r| -r[:chars] }.first(20).each do |r|
  puts format("%-14s %5d %5s %7.1f %7.1f %7.1f",
              r[:author], r[:works], r[:born] || "–", r[:kindness], r[:memory], r[:density])
end

File.write(File.expand_path("../out/axes.json", __dir__),
           JSON.pretty_generate(
             generated_from: "aozora-sakuin/data/raw",
             # 走査条件を刻む。抜き取り実行が全件実行の出力を黙って上書きしても、
             # ファイルを見れば分かるようにする(実測 2026-08-27: 古い背景ジョブが
             # 全件の出力を 400 作の結果で上書きした)。
             works_scanned: works.length, limit: limit, authors_measured: ok.length,
             min_n: MIN_N, easy_cum: A::EASY_CUM, hard_cum: A::HARD_CUM,
             gates: { g04_r: r_axes, g04_pass: r_axes.abs < 0.7,
                        g09_r: r_km, g09_pass: r_km.abs < 0.7,
                        g10_r: r_md, g10_pass: r_md.abs < 0.5,
                        g06_r_kindness: r_era_k, g06_r_trust: r_era_t },
             diagnostic: { r_kindness_density: r_kd, r_trust_density: r_td, partial_r: partial },
             authors: rows.sort_by { |r| -r[:chars] }
           ))
exit(r_km.abs < 0.7 && r_md.abs < 0.5 ? 0 : 1)
