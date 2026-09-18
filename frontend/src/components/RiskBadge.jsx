const TIER_INFO = {
  baixo_risco: { color: 'var(--status-good)', icon: '●', label: 'Sem sinais de crise' },
  atencao: { color: 'var(--status-warning)', icon: '▲', label: 'Atenção' },
  alto_risco: { color: 'var(--status-critical)', icon: '⛔', label: 'Possível crise' },
};

export default function RiskBadge({ tier, probability }) {
  const info = TIER_INFO[tier] ?? TIER_INFO.baixo_risco;

  return (
    <div className="stress-badge" style={{ '--badge-color': info.color }}>
      <span className="stress-badge__icon" aria-hidden="true">
        {info.icon}
      </span>
      <span className="stress-badge__label">
        {info.label}
        {probability !== null && (
          <span className="stress-badge__proba"> · {Math.round(probability * 100)}%</span>
        )}
      </span>
    </div>
  );
}
