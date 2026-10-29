import { useEffect, useRef, useState } from 'react';
import './App.css';
import StatTile from './components/StatTile';
import RiskBadge from './components/RiskBadge';
import BpmChart from './components/BpmChart';
import ManualControls from './components/ManualControls';
import AlertBanner from './components/AlertBanner';
import ConnectionStatus from './components/ConnectionStatus';
import useMqttReadings from './hooks/useMqttReadings';
import { generateReading, GYRO_ACTIONS } from './model/simulate';
import { computeFeatures, predictCrisisProbability, riskTierFromProbability, MIN_HISTORY_REQUIRED } from './model/predict';

const TICK_MS = 1000; // 1 "segundo simulado" por tick, como um sensor real a 1Hz
const CHART_WINDOW = 60; // segundos exibidos no grafico
const MAX_BUFFER = 300; // limite de memoria (5 min de historico)

function App() {
  const [bpmTarget, setBpmTarget] = useState(78);
  const [edaTarget, setEdaTarget] = useState(4);
  const [gyroAction, setGyroAction] = useState('repouso');
  const [hrvTarget, setHrvTarget] = useState(55);
  const [movimentoRepetitivo, setMovimentoRepetitivo] = useState(false);
  const [luzTarget, setLuzTarget] = useState(300);
  const [ruidoTarget, setRuidoTarget] = useState(45);
  const [idade, setIdade] = useState(8);

  const [isRunning, setIsRunning] = useState(true);
  const [speed, setSpeed] = useState(1);
  const [simBuffer, setBuffer] = useState([]);

  // Fonte dos dados: 'manual' (simulador no navegador) ou 'mqtt' (pulseira via broker)
  const [source, setSource] = useState('manual');
  const mqttMode = source === 'mqtt';
  const link = useMqttReadings({ enabled: mqttMode, maxBuffer: MAX_BUFFER });
  const { publishAlert } = link;
  const buffer = mqttMode ? link.readings : simBuffer;

  const changeSource = (next) => {
    if (next === source) return;
    setSource(next);
    setBuffer([]); // o buffer do MQTT e zerado pelo proprio hook ao ligar/desligar
  };

  const controlsRef = useRef();
  useEffect(() => {
    controlsRef.current = {
      bpmTarget, edaTarget, gyroAction, idade,
      hrvTarget, movimentoRepetitivo, luzTarget, ruidoTarget,
    };
  });

  useEffect(() => {
    if (!isRunning || mqttMode) return undefined;

    const interval = setInterval(() => {
      setBuffer((prev) => {
        const next = [...prev];
        for (let i = 0; i < speed; i += 1) {
          next.push(
            generateReading({
              ...controlsRef.current,
              timestamp: new Date().toISOString(),
            }),
          );
        }
        return next.length > MAX_BUFFER ? next.slice(next.length - MAX_BUFFER) : next;
      });
    }, TICK_MS);

    return () => clearInterval(interval);
  }, [isRunning, speed, mqttMode]);

  const current = buffer[buffer.length - 1];
  const chartPoints = buffer.slice(-CHART_WINDOW);
  const statHistory = buffer.slice(-30);

  let tier = 'baixo_risco';
  let probability = null;
  if (buffer.length >= MIN_HISTORY_REQUIRED) {
    const features = computeFeatures(buffer.slice(-MIN_HISTORY_REQUIRED));
    if (features) {
      probability = predictCrisisProbability(features);
      tier = riskTierFromProbability(probability);
    }
  }

  // Publica em puzzleband/<id>/alertas so quando o nivel MUDA para atencao/alto_risco
  const prevTierRef = useRef('baixo_risco');
  useEffect(() => {
    if (tier === prevTierRef.current) return;
    prevTierRef.current = tier;
    if (!mqttMode || (tier !== 'atencao' && tier !== 'alto_risco')) return;
    if (probability === null || !current) return;
    publishAlert({
      timestamp: new Date().toISOString(),
      nivel: tier,
      probabilidade: Number(probability.toFixed(3)),
      leituras: current,
    });
  }, [tier, probability, current, mqttMode, publishAlert]);

  const gyroLabel = GYRO_ACTIONS.find((a) => a.id === gyroAction)?.label ?? gyroAction;

  return (
    <div className="dashboard" data-theme="light">
      <header className="dashboard__header">
        <div>
          <h1>Puzzle Band</h1>
          <p className="dashboard__subtitle">
            {mqttMode
              ? `Pulseira (MQTT) · leituras recebidas do broker, criança ${link.childId ?? '—'}`
              : 'Simulador manual · teste o modelo com cenários que você define, fora do dataset'}
          </p>
        </div>
        <div className="source-select" role="group" aria-label="Fonte dos dados">
          <span className="source-select__label">Fonte dos dados</span>
          <div className="source-select__options">
            <button
              type="button"
              className={`manual-controls__toggle-btn ${!mqttMode ? 'is-active' : ''}`}
              aria-pressed={!mqttMode}
              onClick={() => changeSource('manual')}
            >
              Simulador manual
            </button>
            <button
              type="button"
              className={`manual-controls__toggle-btn ${mqttMode ? 'is-active' : ''}`}
              aria-pressed={mqttMode}
              onClick={() => changeSource('mqtt')}
            >
              Pulseira (MQTT)
            </button>
          </div>
        </div>
      </header>

      {mqttMode && (
        <ConnectionStatus
          brokerStatus={link.brokerStatus}
          bandStatus={link.bandStatus}
          error={link.error}
        />
      )}

      <AlertBanner tier={tier} probability={probability} childLabel="Criança simulada" />

      <section className="dashboard__status">
        <div className="dashboard__status-col">
          <span className="dashboard__status-label">Previsão do modelo (IA)</span>
          <RiskBadge tier={tier} probability={probability} />
        </div>
        {!mqttMode && (
          <span className="dashboard__activity">
            Ação simulada: <strong>{gyroLabel}</strong>
            {movimentoRepetitivo && ' · movimento repetitivo'}
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
        <h2>Frequência cardíaca — últimos {CHART_WINDOW}s {mqttMode ? 'recebidos da pulseira' : 'da simulação'}</h2>
        {chartPoints.length >= 2 ? (
          <BpmChart points={chartPoints} />
        ) : (
          <p className="dashboard__chart-note">
            {mqttMode ? 'Aguardando leituras da pulseira...' : 'Aguardando leituras da simulação...'}
          </p>
        )}
      </section>

      {!mqttMode && (
        <section className="dashboard__sim-card">
          <h2>Controle manual</h2>
          <ManualControls
            bpmTarget={bpmTarget}
            onChangeBpm={setBpmTarget}
            edaTarget={edaTarget}
            onChangeEda={setEdaTarget}
            gyroAction={gyroAction}
            onChangeGyroAction={setGyroAction}
            hrvTarget={hrvTarget}
            onChangeHrv={setHrvTarget}
            movimentoRepetitivo={movimentoRepetitivo}
            onToggleMovimentoRepetitivo={setMovimentoRepetitivo}
            luzTarget={luzTarget}
            onChangeLuz={setLuzTarget}
            ruidoTarget={ruidoTarget}
            onChangeRuido={setRuidoTarget}
            idade={idade}
            onChangeIdade={setIdade}
            isRunning={isRunning}
            onToggleRunning={() => setIsRunning((r) => !r)}
            onReset={() => setBuffer([])}
            speed={speed}
            onChangeSpeed={setSpeed}
            bufferLength={buffer.length}
          />
        </section>
      )}

      <footer className="dashboard__footer">
        Protótipo acadêmico (TCC). Este sistema não tem finalidade médica ou diagnóstica: as
        indicações são apenas um apoio ao cuidador e não substituem avaliação profissional.
      </footer>
    </div>
  );
}

export default App;
