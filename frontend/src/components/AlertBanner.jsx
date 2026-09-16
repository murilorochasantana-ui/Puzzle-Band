export default function AlertBanner({ level, childLabel }) {
  if (level !== 'moderado' && level !== 'alto') return null;

  const isCritical = level === 'alto';

  return (
    <div className={`alert-banner ${isCritical ? 'alert-banner--critical' : 'alert-banner--serious'}`} role="alert">
      <span className="alert-banner__icon" aria-hidden="true">{isCritical ? '⛔' : '▲'}</span>
      <div>
        <strong>{isCritical ? 'Estresse alto detectado' : 'Estresse moderado detectado'}</strong>
        <p>{childLabel} pode estar passando por sobrecarga sensorial. Verifique o ambiente ao redor.</p>
      </div>
    </div>
  );
}
