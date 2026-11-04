import { formatClock } from './formatTime';

// `trigger`: objeto de model/trigger.js do episodio em andamento (ou null)
// `seenAt`: quando o cuidador tocou "Estou ciente" no app (ISO) ou null
export default function AlertBanner({ tier, probability, childLabel, trigger, seenAt }) {
  if (tier !== 'atencao' && tier !== 'alto_risco') return null;

  const isCritical = tier === 'alto_risco';
  const pct = probability !== null ? Math.round(probability * 100) : null;
  const seenClock = formatClock(seenAt);

  return (
    <div className={`alert-banner ${isCritical ? 'alert-banner--critical' : 'alert-banner--serious'}`} role="alert">
      <span className="alert-banner__icon" aria-hidden="true">{isCritical ? '⛔' : '▲'}</span>
      <div>
        <strong>
          {isCritical ? 'Modelo detectou possível crise' : 'Modelo identificou sinais de atenção'}
          {pct !== null && ` (probabilidade estimada: ${pct}%)`}
        </strong>
        <p>
          {childLabel}: o cruzamento de batimento cardíaco, suor (EDA) e movimento sugere possível
          sobrecarga sensorial. Verifique o ambiente ao redor.
        </p>
        {trigger?.texto && <p className="alert-banner__trigger">{trigger.texto}</p>}
        {seenClock && (
          <p className="alert-banner__seen">
            <span aria-hidden="true">✓ </span>Alerta visto pelo cuidador às {seenClock}
          </p>
        )}
        <p className="alert-banner__disclaimer">
          Indicação de apoio ao cuidador, sem valor diagnóstico.
        </p>
      </div>
    </div>
  );
}
