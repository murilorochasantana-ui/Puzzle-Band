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

// App do cuidador (puzzleband/<id>/app/status, "online"/"offline" com retain
// e Last Will). Com o broker conectado, a falta de mensagem retida quer dizer
// que o app nunca conectou: conta como desconectado.
const APP_INFO = {
  online: { color: 'var(--status-good)', icon: '●', label: 'conectado' },
  offline: { color: 'var(--status-critical)', icon: '⛔', label: 'desconectado' },
  sem_broker: { color: 'var(--status-warning)', icon: '▲', label: 'sem informação (broker desconectado)' },
};

function appInfo(appStatus, brokerStatus) {
  if (brokerStatus !== 'conectado') return APP_INFO.sem_broker;
  return appStatus === 'online' ? APP_INFO.online : APP_INFO.offline;
}

function Item({ title, info }) {
  return (
    <span className="connection-status__item" style={{ '--item-color': info.color }}>
      <span className="connection-status__icon" aria-hidden="true">{info.icon}</span>
      {title}: <strong>{info.label}</strong>
    </span>
  );
}

export default function ConnectionStatus({ brokerStatus, bandStatus, appStatus, error }) {
  return (
    <div className="connection-status">
      <Item title="Broker" info={BROKER_INFO[brokerStatus] ?? BROKER_INFO.desconectado} />
      <Item title="Pulseira" info={BAND_INFO[bandStatus] ?? BAND_INFO.desconhecido} />
      <Item title="App do cuidador" info={appInfo(appStatus, brokerStatus)} />
      {error && <span className="connection-status__error">{error}</span>}
    </div>
  );
}
