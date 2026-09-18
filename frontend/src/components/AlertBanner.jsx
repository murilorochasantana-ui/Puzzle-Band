export default function AlertBanner({ tier, probability, childLabel }) {
  if (tier !== 'atencao' && tier !== 'alto_risco') return null;

  const isCritical = tier === 'alto_risco';
  const pct = probability !== null ? Math.round(probability * 100) : null;

  return (
    <div className={`alert-banner ${isCritical ? 'alert-banner--critical' : 'alert-banner--serious'}`} role="alert">
      <span className="alert-banner__icon" aria-hidden="true">{isCritical ? '⛔' : '▲'}</span>
      <div>
        <strong>
          {isCritical ? 'Modelo detectou possível crise' : 'Modelo identificou sinais de atenção'}
          {pct !== null && ` (${pct}% de confiança)`}
        </strong>
        <p>
          {childLabel}: o cruzamento de batimento cardíaco, suor (EDA) e movimento sugere possível
          sobrecarga sensorial. Verifique o ambiente ao redor.
        </p>
      </div>
    </div>
  );
}
