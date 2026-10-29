const BROKER_INFO = {
  conectando: { color: 'var(--status-warning)', icon: '▲', label: 'conectando…' },
  conectado: { color: 'var(--status-good)', icon: '●', label: 'conectado' },
  desconectado: { color: 'var(--status-critical)', icon: '⛔', label: 'desconectado' },
  erro: { color: 'var(--status-critical)', icon: '⛔', label: 'erro' },
};

const BAND_INFO = {
  online: { color: 'var(--status-good)', icon: '●', label: 'online' },
  offline: { color: 'var(--status-critical)', icon: '⛔', label: 'offline' },
  desconhecido: { color: 'var(--status-warning)', icon: '▲', label: 'aguardando status' },
};

function Item({ title, info }) {
  return (
    <span className="connection-status__item" style={{ '--item-color': info.color }}>
      <span className="connection-status__icon" aria-hidden="true">{info.icon}</span>
      {title}: <strong>{info.label}</strong>
    </span>
  );
}

export default function ConnectionStatus({ brokerStatus, bandStatus, error }) {
  return (
    <div className="connection-status">
      <Item title="Broker" info={BROKER_INFO[brokerStatus] ?? BROKER_INFO.desconectado} />
      <Item title="Pulseira" info={BAND_INFO[bandStatus] ?? BAND_INFO.desconhecido} />
      {error && <span className="connection-status__error">{error}</span>}
    </div>
  );
}
