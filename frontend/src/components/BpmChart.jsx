import { useMemo, useRef, useState } from 'react';

const WIDTH = 640;
const HEIGHT = 200;
const PAD_LEFT = 36;
const PAD_BOTTOM = 20;
const PAD_TOP = 12;

export default function BpmChart({ points }) {
  const svgRef = useRef(null);
  const [hoverIndex, setHoverIndex] = useState(null);

  const { path, areaPath, yTicks, scaleX, scaleY, stressBands } = useMemo(() => {
    if (points.length < 2) {
      return { path: '', areaPath: '', yTicks: [], scaleX: () => 0, scaleY: () => 0, stressBands: [] };
    }

    const values = points.map((p) => p.bpm);
    const min = Math.min(...values);
    const max = Math.max(...values);
    const yMin = Math.floor((min - 5) / 5) * 5;
    const yMax = Math.ceil((max + 5) / 5) * 5;

    const innerW = WIDTH - PAD_LEFT;
    const innerH = HEIGHT - PAD_TOP - PAD_BOTTOM;

    const sx = (i) => PAD_LEFT + (i / (points.length - 1)) * innerW;
    const sy = (v) => PAD_TOP + innerH - ((v - yMin) / (yMax - yMin)) * innerH;

    const linePoints = points.map((p, i) => `${sx(i).toFixed(1)},${sy(p.bpm).toFixed(1)}`);
    const areaPoints = [
      `${sx(0).toFixed(1)},${(PAD_TOP + innerH).toFixed(1)}`,
      ...linePoints,
      `${sx(points.length - 1).toFixed(1)},${(PAD_TOP + innerH).toFixed(1)}`,
    ];

    const ticks = [yMin, Math.round((yMin + yMax) / 2), yMax];

    // contiguous ranges where estresse === 1, for the background wash
    const bands = [];
    let start = null;
    points.forEach((p, i) => {
      if (p.estresse === 1 && start === null) start = i;
      if (p.estresse !== 1 && start !== null) {
        bands.push([start, i - 1]);
        start = null;
      }
    });
    if (start !== null) bands.push([start, points.length - 1]);

    return {
      path: `M ${linePoints.join(' L ')}`,
      areaPath: `M ${areaPoints.join(' L ')} Z`,
      yTicks: ticks,
      scaleX: sx,
      scaleY: sy,
      stressBands: bands,
    };
  }, [points]);

  if (points.length < 2) return null;

  const handleMove = (evt) => {
    const rect = svgRef.current.getBoundingClientRect();
    const relX = ((evt.clientX - rect.left) / rect.width) * WIDTH;
    const innerW = WIDTH - PAD_LEFT;
    const ratio = Math.min(1, Math.max(0, (relX - PAD_LEFT) / innerW));
    const idx = Math.round(ratio * (points.length - 1));
    setHoverIndex(idx);
  };

  const hovered = hoverIndex !== null ? points[hoverIndex] : null;

  return (
    <div className="bpm-chart">
      <svg
        ref={svgRef}
        viewBox={`0 0 ${WIDTH} ${HEIGHT}`}
        className="bpm-chart__svg"
        onPointerMove={handleMove}
        onPointerLeave={() => setHoverIndex(null)}
      >
        {yTicks.map((t) => (
          <g key={t}>
            <line
              x1={PAD_LEFT}
              x2={WIDTH}
              y1={scaleY(t)}
              y2={scaleY(t)}
              stroke="var(--gridline)"
              strokeWidth="1"
            />
            <text x={0} y={scaleY(t) + 4} className="bpm-chart__tick">
              {t}
            </text>
          </g>
        ))}

        {stressBands.map(([s, e], i) => (
          <rect
            key={i}
            x={scaleX(s)}
            y={PAD_TOP}
            width={Math.max(2, scaleX(e) - scaleX(s))}
            height={HEIGHT - PAD_TOP - PAD_BOTTOM}
            fill="var(--status-serious)"
            opacity="0.12"
          />
        ))}

        <path d={areaPath} fill="var(--series-1)" opacity="0.1" stroke="none" />
        <path d={path} fill="none" stroke="var(--series-1)" strokeWidth="2" strokeLinejoin="round" strokeLinecap="round" />

        {hovered && (
          <>
            <line
              x1={scaleX(hoverIndex)}
              x2={scaleX(hoverIndex)}
              y1={PAD_TOP}
              y2={HEIGHT - PAD_BOTTOM}
              stroke="var(--baseline)"
              strokeWidth="1"
            />
            <circle
              cx={scaleX(hoverIndex)}
              cy={scaleY(hovered.bpm)}
              r="4"
              fill="var(--series-1)"
              stroke="var(--surface-1)"
              strokeWidth="2"
            />
          </>
        )}
      </svg>

      {hovered && (
        <div
          className="bpm-chart__tooltip"
          style={{ left: `${(scaleX(hoverIndex) / WIDTH) * 100}%` }}
        >
          <strong>{hovered.bpm} bpm</strong>
          <span>{new Date(hovered.timestamp).toLocaleTimeString('pt-BR')}</span>
        </div>
      )}
    </div>
  );
}
