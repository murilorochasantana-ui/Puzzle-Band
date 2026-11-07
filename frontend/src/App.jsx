import { useEffect, useState } from 'react';
import './App.css';
import StatTile from './components/StatTile';
import RiskBadge from './components/RiskBadge';
import BpmChart from './components/BpmChart';
import BandControls from './components/BandControls';
import AlertBanner from './components/AlertBanner';
import ConnectionStatus from './components/ConnectionStatus';
import EpisodeHistory from './components/EpisodeHistory';
import ThemeToggle from './components/ThemeToggle';
import { formatClock } from './components/formatTime';
import useBandLink from './hooks/useBandLink';
import useControlSender from './hooks/useControlSender';
import { CALM_CONTROL, GYRO_ACTIONS, REGULARIDADE } from './model/simulate';
import { MODEL_DESCRIPTION } from './modelMeta';

// PAINEL do desenvolvedor: so visualizacao e controle. Quem processa e a
// pulseira (simulator/, processamento na borda): ela roda o modelo, os
// episodios e o gatilho e publica estado, alertas e historico. O painel
// assina esses topicos (e as leituras, para os graficos) e publica so
// controle e avaliacao. O app do cuidador funciona com o painel fechado.

const CHART_WINDOW = 60; // segundos exibidos no grafico
const MAX_BUFFER = 300; // leituras guardadas na memoria do painel (5 min)
const STATE_LIVE_MS = 6000; // mesma regra do app: estado com ate 6 s e "ao vivo"
const PENDING_MS = 10000; // avaliacao enviada sem resposta da pulseira: para de mostrar "aguardando"

const TIER_LABEL = { baixo_risco: 'Sem sinais de crise', atencao: 'Atenção', alto_risco: 'Possível crise' };

// Relogio de 1 s: o estado "ao vivo" vira "velho" mesmo sem mensagem nova
function useNow(intervalMs) {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), intervalMs);
    return () => clearInterval(id);
  }, [intervalMs]);
  return now;
}

// Situacao da pulseira para o "Controle da pulseira"
function controlNotice({ connected, bandStatus, live }) {
  if (!connected) return { tone: 'warning', text: 'Sem conexão com o broker: os controles não chegam à pulseira.' };
  if (bandStatus !== 'online') return { tone: 'warning', text: 'Inicie a pulseira com npm run controle para usar estes controles.' };
  if (!live) return { tone: 'warning', text: 'Pulseira online; aguardando o estado ao vivo dela...' };
  if (live.fonte !== 'manual') {
    return {
      tone: 'warning',
      text: 'A pulseira está rodando um cenário e ignora estes controles. Para usá-los, reinicie-a com npm run controle.',
    };
  }
  return { tone: 'ok', text: 'Pulseira no modo controle: as leituras seguem estes valores.' };
}

function App() {
  const link = useBandLink({ maxBuffer: MAX_BUFFER });
  const now = useNow(1000);
  const { readings, state, history, lastAlert, childId } = link;

  // Estado publicado pela pulseira; retido e velho (pulseira desligada) nao conta
  const stateTime = state?.timestamp ? Date.parse(state.timestamp) : Number.NaN;
  const live = state && now - stateTime <= STATE_LIVE_MS ? state : null;
  const tier = live ? live.nivel : 'sem_dados';
  const probability = live ? live.probabilidade : null;
  const controlMode = live?.fonte === 'manual';
  const canEvaluate = link.connected && link.bandStatus === 'online';

  // Controle da pulseira: valores-alvo publicados em controle (no maximo 2x/s)
  const [control, setControl] = useState(CALM_CONTROL);
  const lastSentAt = useControlSender({
    values: control,
    publishControl: link.publishControl,
    connected: link.connected,
    bandStatus: link.bandStatus,
    connectionId: link.connectionId,
  });

  // Confirmar / Descartar: publica em avaliacao; a pulseira aplica e republica o historico
  const [pending, setPending] = useState({}); // { id: { at, historyTs } }
  const evaluate = (id, avaliacao, observacao) => {
    const sent = link.publishEvaluation({ episodioId: id, avaliacao, observacao });
    if (sent) setPending((prev) => ({ ...prev, [id]: { at: Date.now(), historyTs: history?.timestamp ?? null } }));
  };
  const pendingIds = Object.fromEntries(Object.entries(pending)
    .filter(([, p]) => p.historyTs === (history?.timestamp ?? null) && now - p.at < PENDING_MS)
    .map(([id]) => [id, true]));

  const current = readings[readings.length - 1];
  const chartPoints = readings.slice(-CHART_WINDOW);
  const statHistory = readings.slice(-30);
  const gyroLabel = GYRO_ACTIONS.find((a) => a.base === control.movimento)?.label ?? `${control.movimento} dps`;
  const alertClock = lastAlert ? formatClock(lastAlert.timestamp) : null;

  return (
    <div className="dashboard">
      <header className="dashboard__header">
        <div>
          <h1>Puzzle Band</h1>
          <p className="dashboard__subtitle">
            Painel do desenvolvedor · a pulseira processa (modelo, episódios e gatilho); este site só mostra e
            controla · criança {childId ?? '—'}
          </p>
        </div>
        <div className="dashboard__header-controls">
          <ThemeToggle />
        </div>
      </header>

      <ConnectionStatus
        brokerStatus={link.brokerStatus}
        bandStatus={link.bandStatus}
        appStatus={link.appStatus}
        error={link.error}
      />

      <AlertBanner
        tier={tier}
        probability={probability}
        childLabel={`Criança ${childId ?? '—'}`}
        trigger={live?.gatilho}
        seenAt={live?.episodio?.visto_pelo_cuidador_em}
      />

      <section className="dashboard__status">
        <div className="dashboard__status-col">
          <span className="dashboard__status-label">Previsão do modelo (IA), calculada na pulseira</span>
          <RiskBadge tier={tier} probability={probability} />
        </div>
        {live && (
          <span className="dashboard__activity">
            {controlMode ? (
              <>
                Modo controle · ação simulada: <strong>{gyroLabel}</strong>
                {control.regularidade >= REGULARIDADE.repetitivo && ' · movimento repetitivo'}
              </>
            ) : 'Pulseira rodando um cenário'}
          </span>
        )}
        {lastAlert && (
          <span className="dashboard__activity">
            Último alerta{alertClock && ` às ${alertClock}`}: <strong>{TIER_LABEL[lastAlert.nivel] ?? lastAlert.nivel}</strong>
            {Number.isFinite(lastAlert.probabilidade) && ` (${Math.round(lastAlert.probabilidade * 100)}%)`}
          </span>
        )}
        {current && (
          <span className="dashboard__timestamp">
            {new Date(current.timestamp).toLocaleTimeString('pt-BR')}
          </span>
        )}
      </section>

      <section className="dashboard__tiles">
        <StatTile
          label="Frequência cardíaca"
          value={current ? current.bpm : '—'}
          unit="bpm"
          color="var(--series-1)"
          history={statHistory.map((p) => p.bpm)}
        />
        <StatTile
          label="Atividade eletrodérmica (GSR)"
          value={current ? current.eda_uS.toFixed(2) : '—'}
          unit="µS"
          color="var(--series-3)"
          history={statHistory.map((p) => p.eda_uS)}
        />
        <StatTile
          label="Movimento (giroscópio)"
          value={current ? current.gyro_mag_dps.toFixed(1) : '—'}
          unit="dps"
          color="var(--series-7)"
          history={statHistory.map((p) => p.gyro_mag_dps)}
        />
        <StatTile
          label="HRV (variabilidade cardíaca)"
          value={current ? current.hrv_ms.toFixed(1) : '—'}
          unit="ms"
          color="var(--series-1)"
          history={statHistory.map((p) => p.hrv_ms)}
        />
        <StatTile
          label="Regularidade do movimento"
          value={current ? current.regularidade.toFixed(2) : '—'}
          unit=""
          color="var(--series-7)"
          history={statHistory.map((p) => p.regularidade)}
        />
        <StatTile
          label="Luminosidade"
          value={current ? current.luz_lux : '—'}
          unit="lux"
          color="var(--series-3)"
          history={statHistory.map((p) => p.luz_lux)}
        />
        <StatTile
          label="Ruído ambiente"
          value={current ? current.ruido_db.toFixed(1) : '—'}
          unit="dB"
          color="var(--series-3)"
          history={statHistory.map((p) => p.ruido_db)}
        />
      </section>

      <section className="dashboard__chart-card">
        <h2>Frequência cardíaca — últimos {CHART_WINDOW}s recebidos da pulseira</h2>
        {chartPoints.length >= 2 ? (
          <BpmChart points={chartPoints} />
        ) : (
          <p className="dashboard__chart-note">Aguardando leituras da pulseira...</p>
        )}
      </section>

      <EpisodeHistory
        episodes={history?.episodios ?? []}
        total={history?.total ?? 0}
        received={Boolean(history)}
        live={live?.episodio ? { episodioId: live.episodio.id, timestamp: live.timestamp } : null}
        canEvaluate={canEvaluate}
        pending={pendingIds}
        onEvaluate={evaluate}
      />

      <section className="dashboard__sim-card">
        <h2>Controle da pulseira</h2>
        <BandControls
          values={control}
          onChange={(field, value) => setControl((prev) => ({ ...prev, [field]: value }))}
          onReset={() => setControl(CALM_CONTROL)}
          notice={controlNotice({ connected: link.connected, bandStatus: link.bandStatus, live })}
          lastSentAt={lastSentAt}
        />
      </section>

      <footer className="dashboard__footer">
        <p>
          Protótipo acadêmico (TCC). Este sistema não tem finalidade médica ou diagnóstica: as
          indicações são apenas um apoio ao cuidador e não substituem avaliação profissional.
        </p>
        <p className="dashboard__model-info">{MODEL_DESCRIPTION}</p>
      </footer>
    </div>
  );
}

export default App;
