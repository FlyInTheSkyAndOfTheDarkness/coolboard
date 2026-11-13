const distance = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
export function resample(points, count = 24) {
  if (!points.length) return [];
  const lengths = [0];
  for (let i = 1; i < points.length; i++) lengths.push(lengths.at(-1) + distance(points[i - 1], points[i]));
  const length = lengths.at(-1);
  if (!length) return Array.from({ length: count }, () => ({ ...points[0] }));
  let segment = 1;
  return Array.from({ length: count }, (_, i) => {
    const target = length * i / (count - 1);
    while (segment < lengths.length - 1 && lengths[segment] < target) segment++;
    const t = (target - lengths[segment - 1]) / (lengths[segment] - lengths[segment - 1] || 1);
    return { x: points[segment - 1].x + t * (points[segment].x - points[segment - 1].x), y: points[segment - 1].y + t * (points[segment].y - points[segment - 1].y) };
  });
}
export function rankGlide(trace, centers, words, limit = 3) {
  if (trace.length < 2) return [];
  const keys = Object.values(centers);
  if (keys.length < 3) return [];
  const unit = keys.reduce((sum, point) => sum + Math.min(...keys.filter(other => other !== point).map(other => distance(point, other))), 0) / keys.length;
  if (unit <= 0 || trace.reduce((sum, p, i) => sum + (i ? distance(p, trace[i - 1]) : 0), 0) < unit * .7) return [];
  const sample = resample(trace);
  const ranked = [];
  const seen = new Set();
  words.forEach((original, index) => {
    const word = original.toLocaleLowerCase();
    if (seen.has(word) || word.length < 2 || word.length > 24) return;
    seen.add(word);
    const path = [...word].filter((char, i, all) => !i || char !== all[i - 1]).map(char => centers[char]);
    if (path.length < 2 || path.some(p => !p)) return;
    const endpoints = distance(trace[0], path[0]) + distance(trace.at(-1), path.at(-1));
    if (distance(trace[0], path[0]) > unit * .9 || distance(trace.at(-1), path.at(-1)) > unit * .9) return;
    const expected = resample(path);
    const rows = Array.from({ length: sample.length + 1 }, () => Array(expected.length + 1).fill(Infinity)); rows[0][0] = 0;
    for (let i = 1; i <= sample.length; i++) for (let j = 1; j <= expected.length; j++) rows[i][j] = distance(sample[i - 1], expected[j - 1]) / unit + Math.min(rows[i - 1][j], rows[i][j - 1], rows[i - 1][j - 1]);
    const score = rows[sample.length][expected.length] / sample.length + endpoints / unit + index * .000002;
    if (score < 2.5) ranked.push({ word: original, score });
  });
  return ranked.sort((a, b) => a.score - b.score).slice(0, limit).map(item => item.word);
}

export function nextWords(context, language, seeds, learned = {}) {
  const previous = /([\p{L}\p{M}]+)[\s.!?,:;]+$/u.exec(context)?.[1]?.toLocaleLowerCase();
  if (!previous) return [];
  const personal = Object.entries(learned[language]?.[previous] || {}).sort((a, b) => b[1] - a[1]).map(([word]) => word);
  return [...new Set([...personal, ...(seeds[language]?.[previous] || [])])].slice(0, 3);
}

export function deleteWord(value, start, end) {
  if (start !== end) return { value: value.slice(0, start) + value.slice(end), cursor: start };
  const before = value.slice(0, start);
  const match = /(?:[\p{L}\p{M}\p{N}'’]+|[^\p{L}\p{M}\p{N}\s]+)\s*$/u.exec(before) || /\s+$/u.exec(before);
  const cursor = match?.index ?? start;
  return { value: value.slice(0, cursor) + value.slice(end), cursor };
}
