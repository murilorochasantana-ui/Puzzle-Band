import { STRESS_LABELS } from '../data/children';

const STATUS_BY_LEVEL = {
  nenhum: { color: 'var(--status-good)', icon: '●' },
  leve: { color: 'var(--status-warning)', icon: '▲' },
  moderado: { color: 'var(--status-serious)', icon: '▲' },
  alto: { color: 'var(--status-critical)', icon: '⛔' },
};

export default function StressBadge({ level }) {
  const status = STATUS_BY_LEVEL[level] ?? STATUS_BY_LEVEL.nenhum;

  return (
    <div className="stress-badge" style={{ '--badge-color': status.color }}>
      <span className="stress-badge__icon" aria-hidden="true">
        {status.icon}
      </span>
      <span className="stress-badge__label">{STRESS_LABELS[level] ?? STRESS_LABELS.nenhum}</span>
    </div>
  );
}
